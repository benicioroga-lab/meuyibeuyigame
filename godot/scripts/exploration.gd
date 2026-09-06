class_name MeyuiExploration
extends Node3D

const Loot = preload("res://data/loot_data.gd")
const Drop = preload("res://scripts/loot_drop.gd")
const MAX_DROPS := 96
const MAX_PENDING_REWARDS := 512
const SOLID_WORLD_MASK := 1
const MOVEMENT_GATE_MASK := 32
const POWERUPS := ["infinite_ammo", "double_damage", "frenzy", "nuke", "magnet", "jackpot", "overcharge"]
const POWERUP_NAMES := {"infinite_ammo":"MUNIÇÃO LIVRE", "double_damage":"IMPACTO DUPLO", "frenzy":"FRENESI", "nuke":"PULSO ZERO", "magnet":"ÍMÃ", "jackpot":"FORTUNA", "overcharge":"SOBRECARGA"}
var game: Node
var drops: Array[Node3D] = []
var used_pois: Dictionary = {}
var discovered: Array = []
var bosses_defeated: Array = []
var challenge: Dictionary = {}
var target: Dictionary = {}
var _clock := 0.0
var pending_drops: Array[Dictionary] = []
var _next_pickup_sound := 0
var _next_storage_notice := 0
var _highlighted_drop: Node3D

func setup(owner_game: Node) -> void:
	game = owner_game
	process_mode = Node.PROCESS_MODE_PAUSABLE

func _process(delta: float) -> void:
	if not game.running or game.paused: return
	_clock -= delta
	if _clock <= 0:
		_clock = 0.13
		_scan()
		collect_nearby(game.player.global_position, 1.25 if not game.active_powerups.has("magnet") else 8.0)
		var region: String = game.world.get_region_id(game.player.global_position)
		if not region.is_empty() and not discovered.has(region) and game.world.unlocked_regions.has(region):
			discovered.append(region)
			game.add_coins(40, "exploration")
			game.ui.announce("NOVA ÁREA", game.world.district(game.player.global_position))
			game.audio.play("discovery")
			game.schedule_save()
	if not challenge.is_empty():
		challenge["remaining"] = maxf(0, float(challenge["remaining"]) - delta)
		if float(challenge["remaining"]) <= 0:
			game.notify("Desafio encerrado. Tente outra rota.")
			challenge.clear()
	for index in range(drops.size() - 1, -1, -1):
		var drop: Node3D = drops[index]
		if is_instance_valid(drop) and drop.kind in ["ammo", "currency"] and drop.lifetime > 100:
			drops.remove_at(index)
			drop.queue_free()
	_flush_pending()

func can_accept_drop(kind: String, payload: Dictionary) -> bool:
	if not _valid_payload(kind, payload): return false
	var active := 0
	for drop: Node3D in drops:
		if is_instance_valid(drop) and not drop.collected: active += 1
	return active < MAX_DROPS or is_instance_valid(_replacement_for(kind, payload)) or is_instance_valid(_merge_target(kind))

func drop_item(kind: String, payload: Dictionary, at: Vector3, guaranteed: bool = false) -> Node3D:
	if not _valid_payload(kind, payload) or not at.is_finite(): return null
	_prune_drops()
	if drops.size() >= MAX_DROPS:
		var merge := _merge_target(kind)
		if is_instance_valid(merge):
			merge.payload["amount"] = int(merge.payload.get("amount", 0)) + int(payload.get("amount", 0))
			game.schedule_save()
			return merge
		var replaced := _replacement_for(kind, payload)
		if is_instance_valid(replaced):
			_compensate(replaced)
			drops.erase(replaced)
			replaced.collected = true
			replaced.queue_free()
		else:
			if guaranteed or kind == "powerup" or _rarity(payload) >= 3:
				_bank_reward(kind, payload, at)
			elif kind == "currency":
				game.add_coins(int(payload.get("amount", 0)), "ground_capacity")
				game.schedule_save()
			return null
	return _create_drop(kind, payload, at)

func _bank_reward(kind: String, payload: Dictionary, at: Vector3) -> void:
	if pending_drops.size() < MAX_PENDING_REWARDS:
		pending_drops.append({"kind":kind,"payload":payload.duplicate(true),"position":[at.x,at.y + 0.07,at.z],"lifetime":0.0})
		if Time.get_ticks_msec() >= _next_storage_notice:
			_next_storage_notice = Time.get_ticks_msec() + 2500
			game.notify("Recompensa guardada · aparece ao abrir espaço no chão")
	else:
		# The data reserve also has a file-budget bound; extreme overflow keeps its value.
		var delivered := false
		if kind == "weapon":
			delivered = game.inventory.add_item(payload)
			if delivered: game.record_weapon(payload)
		elif kind == "attachment": delivered = game.inventory.add_attachment(payload)
		elif kind == "powerup":
			game.activate_powerup(str(payload.id))
			delivered = true
		if delivered:
			game.notify("Reserva cheia · recompensa entregue diretamente")
		else:
			var value := _compensation_value(kind, payload)
			game.add_coins(value, "reward_reserve_capacity")
			game.notify("Chão e reserva cheios · recompensa convertida em +%d petiscos" % value)
	game.schedule_save()

func _create_drop(kind: String, payload: Dictionary, at: Vector3, quiet: bool = false, snap_floor: bool = true) -> Node3D:
	var drop := Drop.new()
	drop.setup(kind, payload)
	add_child(drop)
	var manager: Variant = game.get("settings") if is_instance_valid(game) else null
	if manager is Object and is_instance_valid(manager):
		var values: Variant = manager.get("data")
		if values is Dictionary: drop.apply_settings(values)
	drop.global_position = (_floor_position(at) if snap_floor else at) + Vector3(0, 0.07, 0)
	drops.append(drop)
	if quiet: return drop
	if kind == "weapon" and _rarity(payload) >= 4:
		game.ui.announce("ARMA " + str(Loot.RARITIES[payload["rarity"]]["name"]).to_upper(), game.inventory.stats(payload).get("name", ""))
		game.audio.play("loot_" + str(payload["rarity"]))
	elif kind == "powerup":
		game.audio.play("loot_rare")
	return drop

func _valid_payload(kind: String, payload: Dictionary) -> bool:
	match kind:
		"weapon": return Loot.Data.WEAPONS.has(str(payload.get("model_id", ""))) and not str(payload.get("uid", "")).is_empty()
		"attachment": return Loot.ATTACHMENTS.has(str(payload.get("id", "")))
		"powerup": return POWERUP_NAMES.has(str(payload.get("id", "")))
		"ammo", "currency": return (payload.get("amount") is int or payload.get("amount") is float) and is_finite(float(payload.amount)) and int(payload.amount) > 0
	return false

func _rarity(payload: Dictionary) -> int:
	return Loot.rarity_rank(str(payload.get("rarity", "common")))

func _merge_target(kind: String) -> Node3D:
	if kind not in ["ammo", "currency"]: return null
	for drop: Node3D in drops:
		if is_instance_valid(drop) and not drop.collected and drop.kind == kind: return drop
	return null

func _replacement_for(kind: String, payload: Dictionary) -> Node3D:
	var incoming := 3 if kind == "powerup" else _rarity(payload)
	var best: Node3D
	var lowest := incoming
	for drop: Node3D in drops:
		if not is_instance_valid(drop) or drop.collected: continue
		if drop.kind in ["ammo", "currency"]: return drop
		if drop.kind not in ["weapon", "attachment"] or bool(drop.payload.get("favorite", false)): continue
		var rank := _rarity(drop.payload)
		if rank < lowest:
			lowest = rank
			best = drop
	return best

func _compensate(drop: Node3D) -> void:
	if drop.kind == "currency":
		game.add_coins(int(drop.payload.get("amount", 0)), "ground_capacity")
	elif drop.kind == "ammo":
		# Resource piles are returned directly when equipment needs their floor slot.
		game.player.add_ammo(int(drop.payload.get("amount", 0)))
	else:
		var value := _compensation_value(drop.kind, drop.payload)
		game.add_coins(value, "ground_capacity")
		game.notify("Chão cheio · %s inferior convertido em +%d petiscos" % ["arma" if drop.kind == "weapon" else "acessório", value])
	game.schedule_save()

func _compensation_value(kind: String, payload: Dictionary) -> int:
	if kind == "weapon": return maxi(20, int(game.inventory.stats(payload).get("value", 20)))
	if kind == "attachment": return maxi(20, int(Loot.ATTACHMENTS.get(payload.get("id", ""), {}).get("cost", 80)) / 2)
	return maxi(1, int(payload.get("amount", 25)))

func _prune_drops() -> void:
	for index in range(drops.size() - 1, -1, -1):
		if not is_instance_valid(drops[index]) or drops[index].collected: drops.remove_at(index)

func _flush_pending() -> void:
	_prune_drops()
	while drops.size() < MAX_DROPS and not pending_drops.is_empty():
		var best := 0
		for index in range(1, pending_drops.size()):
			if _rarity(pending_drops[index].payload) > _rarity(pending_drops[best].payload): best = index
		var entry: Dictionary = pending_drops.pop_at(best)
		var p: Array = entry.position
		var drop := _create_drop(entry.kind, entry.payload, Vector3(float(p[0]), float(p[1]) - 0.07, float(p[2])), true)
		drop.lifetime = float(entry.get("lifetime", 0))

func _floor_position(at: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.4, at + Vector3.DOWN * 4, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and Vector3(hit.normal).dot(Vector3.UP) > 0.65: return hit.position
	return at

func _scan() -> void:
	target = {}
	var camera: Camera3D = game.player.camera
	var origin: Vector3 = camera.global_position
	var forward: Vector3 = -camera.global_basis.z
	var best := 3.4
	var best_alignment := INF
	for drop: Node3D in drops:
		if not is_instance_valid(drop) or drop.collected: continue
		var point := drop.global_position + Vector3.UP * 0.4
		var distance: float = game.player.global_position.distance_to(drop.global_position)
		var offset := point - origin
		var along := forward.dot(offset)
		var radius := 0.65 if drop.kind == "weapon" else 0.45
		var alignment := offset.cross(forward).length() / radius
		if distance >= 3.4 or along <= 0 or alignment > 1.0: continue
		if (alignment < best_alignment - 0.001 or (absf(alignment - best_alignment) <= 0.001 and distance < best)) and _visible(point):
			best = distance
			best_alignment = alignment
			target = {"kind":"drop", "node":drop, "type":drop.kind, "name":_drop_name(drop), "distance":distance, "range":3.4, "prompt":"E  RECOLHER"}
	if not target.is_empty():
		_set_highlight(target.get("node"))
		return
	for poi: Dictionary in game.world.interactables(game.player.global_position):
		var at: Vector3 = poi.get("position", Vector3.ZERO)
		var type: String = str(poi.get("type", ""))
		if not _available(poi): continue
		var distance: float = game.player.global_position.distance_to(at)
		if distance < best and forward.dot((at + Vector3.UP - origin).normalized()) > 0.2 and _visible(at + Vector3.UP, type == "door"):
			best = distance
			var terms := _door_terms(poi) if type == "door" else {"cost":maxi(0, int(poi.get("cost", 0))),"round":1}
			target = {"kind":"poi", "poi":poi, "type":type, "name":poi.get("name", ""), "cost":terms.cost, "prompt":"E  INTERAGIR" + (" · ROUND %d" % int(terms.round) if game.round_number < int(terms.round) else "")}
	_set_highlight(target.get("node") if target.get("kind") == "drop" else null)

func _set_highlight(drop: Node3D) -> void:
	if _highlighted_drop == drop: return
	if is_instance_valid(_highlighted_drop) and _highlighted_drop.has_method("set_highlighted"):
		_highlighted_drop.set_highlighted(false)
	_highlighted_drop = drop
	if is_instance_valid(_highlighted_drop) and _highlighted_drop.has_method("set_highlighted"):
		_highlighted_drop.set_highlighted(true)

func _visible(point: Vector3, through_gates: bool = false) -> bool:
	var origin: Vector3 = game.player.camera.global_position
	var end := point + (origin - point).normalized() * 0.25
	var space := get_world_3d().direct_space_state
	var mask := SOLID_WORLD_MASK if through_gates else SOLID_WORLD_MASK | MOVEMENT_GATE_MASK
	var camera_query := PhysicsRayQueryParameters3D.create(origin, end, mask)
	camera_query.hit_from_inside = true
	if not space.intersect_ray(camera_query).is_empty(): return false
	var player_origin: Vector3 = game.player.global_position + Vector3.UP * 1.1
	var player_end := point + (player_origin - point).normalized() * 0.12
	var player_query := PhysicsRayQueryParameters3D.create(player_origin, player_end, mask)
	player_query.hit_from_inside = true
	return space.intersect_ray(player_query).is_empty()

func _door_terms(poi: Dictionary) -> Dictionary:
	for region: Dictionary in game.world.regions:
		if str(region.id) == str(poi.get("region_id", "")):
			return {"valid":true,"cost":maxi(0, int(region.get("unlock_cost", poi.get("cost", 0)))),"round":maxi(1, int(region.get("unlock_round", 1)))}
	return {"valid":false,"cost":0,"round":1}

func _available(poi: Dictionary) -> bool:
	var type: String = str(poi.get("type", ""))
	var region: String = str(poi.get("region_id", "patio"))
	if type == "door": return game.world.can_purchase_region(region) and bool(_door_terms(poi).valid)
	if type != "door" and not game.world.unlocked_regions.has(region): return false
	if type in ["chest", "cache"]:
		return game.round_number >= int(used_pois.get(str(poi["id"]), -5)) + 5
	if type == "boss": return not bosses_defeated.has(str(poi["id"])) and game.boss_zone.is_empty()
	if type == "challenge": return challenge.is_empty()
	return true

func get_context() -> Dictionary:
	var result: Dictionary = target.duplicate()
	result.erase("node")
	result.erase("poi")
	if target.get("kind", "") == "drop":
		var drop: Node3D = target.get("node")
		if not is_instance_valid(drop) or drop.collected: return {}
		var comparison := _drop_comparison(drop)
		result["comparison"] = comparison
		for key: String in ["name", "amount", "slot", "description", "duration", "rarity"]:
			if comparison.item.has(key): result[key] = comparison.item[key]
	return result

func _drop_comparison(drop: Node3D) -> Dictionary:
	var current: Dictionary = game.player.get_weapon_stats()
	if drop.kind == "weapon":
		return {"type":"weapon", "item":drop.payload.duplicate(true), "stats":game.inventory.stats(drop.payload), "current":current}
	var item: Dictionary = drop.payload.duplicate(true)
	item["name"] = _drop_name(drop)
	var stats: Dictionary = {}
	var comparison := {"type":drop.kind, "item":item, "stats":stats, "current":current}
	match drop.kind:
		"ammo":
			var amount := int(item.get("amount", 0))
			var capacity := int(current.get("max_reserve", 0))
			var reserve: int = game.player.reserve
			stats.merge({"amount":amount, "reserve":reserve, "max_reserve":capacity, "collectable":mini(amount, maxi(0, capacity - reserve))})
			item["description"] = "%d projéteis · reserva %d / %d" % [amount, reserve, capacity]
		"attachment":
			var config: Dictionary = Loot.ATTACHMENTS.get(str(item.get("id", "")), {})
			var slot := str(config.get("slot", item.get("slot", "")))
			item["slot"] = slot
			item["description"] = "Instale na arma pelo inventário."
			var equipped: Dictionary = game.inventory.equipped().duplicate(true)
			comparison["current_attachment"] = equipped.get("attachments", {}).get(slot, {}).duplicate(true)
			# Compare permanent item stats on both sides; temporary combat buffs are unchanged.
			comparison["current"] = game.inventory.stats(equipped)
			if not equipped.is_empty():
				equipped["attachments"][slot] = drop.payload.duplicate(true)
				stats.merge(game.inventory.stats(equipped))
			comparison["modifiers"] = _attachment_modifiers(drop.payload, config)
		"powerup":
			var id := str(item.get("id", ""))
			var duration := 0 if id in ["nuke", "jackpot"] else 24
			item["duration"] = duration
			stats["duration"] = duration
			var descriptions := {"infinite_ammo":"Atire sem consumir munição por 24s.", "double_damage":"Dano dobrado por 24s.", "frenzy":"Cadência e movimento aumentados por 24s.", "magnet":"Recolhe recursos próximos em um raio de 8m por 24s.", "overcharge":"Disparos elétricos por 24s."}
			if id == "jackpot":
				item["amount"] = 250 + game.round_number * 30
				item["description"] = "+%d petiscos imediatamente." % int(item.amount)
			elif id == "nuke":
				item["amount"] = 220 + game.round_number * 12
				item["description"] = "Causa %d de dano a todos os inimigos vivos." % int(item.amount)
			else: item["description"] = descriptions.get(id, "Power-up temporário.")
			if item.has("amount"): stats["amount"] = item.amount
		"currency":
			stats["amount"] = int(item.get("amount", 0))
			item["description"] = "+%d petiscos para compras e melhorias." % int(stats.amount)
	return comparison

func _attachment_modifiers(item: Dictionary, config: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var potency := float(item.get("roll", 1.0)) * (1.0 + Loot.rarity_rank(str(item.get("rarity", "common"))) * 0.12)
	for key: String in game.inventory.MULTIPLIERS:
		if not config.has(key): continue
		var factor := float(config[key])
		var beneficial := factor < 1 if key in ["spread", "recoil", "reload_time"] else factor > 1
		result[key] = 1.0 + (factor - 1.0) * potency if beneficial else factor
	for key: String in game.inventory.ADDITIONS:
		if config.has(key): result[key] = float(config[key]) * potency
	for key: String in ["modifier", "element"]:
		if config.has(key): result[key] = config[key]
	return result

func interact() -> void:
	_scan()
	if target.is_empty(): return
	if target.get("kind", "") == "drop":
		collect_drop(target["node"])
		return
	var poi: Dictionary = target.get("poi", {})
	if poi.is_empty(): return
	var type: String = str(poi.get("type", ""))
	var cost := maxi(0, int(poi.get("cost", 0)))
	if type == "door":
		var terms := _door_terms(poi)
		if not terms.valid: return
		cost = int(terms.cost)
		var unlock_round := int(terms.round)
		if game.round_number < unlock_round:
			game.notify("Acesso no round %d" % unlock_round)
			return
		if game.coins < cost:
			game.notify("Faltam %d petiscos" % (cost - game.coins))
			return
		if game.world.unlock_region(str(poi.get("region_id", ""))):
			game.coins -= cost
			game.audio.play("purchase")
			game.ui.announce("CAMINHO ABERTO", poi.get("name", ""))
			game.schedule_save()
	elif type in ["forge", "merchant", "food"]:
		game.open_inventory("forge")
	elif type in ["chest", "cache"]:
		if not game.spend(cost): return
		used_pois[str(poi["id"])] = game.round_number
		var quality: float = game.loot_quality() * (1.6 if type == "cache" else 1.15)
		var at: Vector3 = poi["position"]
		drop_item("weapon", Loot.roll_weapon(game.round_number, game.rng, quality, "rare" if type == "cache" else ""), at + Vector3(0.7, 0, 0), true)
		drop_item("attachment", Loot.roll_attachment(game.rng, quality), at + Vector3(-0.5, 0, 0), true)
		drop_item("ammo", {"amount":24}, at + Vector3(0, 0, 0.5), true)
		game.audio.play("loot_rare")
		game.schedule_save()
	elif type == "boss":
		game.start_boss(poi)
	elif type == "challenge":
		challenge = {"id":str(poi["id"]), "name":"SEGURE A ESQUINA", "region":str(poi.get("region_id", "patio")), "remaining":90.0, "kills":0, "target":12}
		game.ui.announce("SEGURE A ESQUINA", "12 eliminações nesta região · 90 segundos")
		game.schedule_save()
	_scan()

func collect_drop(drop: Node3D) -> bool:
	if not is_instance_valid(drop) or drop.collected: return false
	var success := true
	var remainder := 0
	match drop.kind:
		"weapon":
			success = game.inventory.add_item(drop.payload)
			if success: game.record_weapon(drop.payload)
		"attachment": success = game.inventory.add_attachment(drop.payload)
		"ammo":
			var before := int(game.player.reserve)
			var amount := int(drop.payload.get("amount", 18))
			game.player.add_ammo(amount)
			var collected_amount := maxi(0, int(game.player.reserve) - before)
			if collected_amount == 0: return false
			remainder = maxi(0, amount - collected_amount)
		"currency": game.add_coins(int(drop.payload.get("amount", 25)), "pickup")
		"powerup": game.activate_powerup(str(drop.payload.get("id", "frenzy")))
	if not success:
		game.notify("Mochila cheia · I para organizar")
		return false
	if drop.kind in ["ammo", "currency"]:
		if Time.get_ticks_msec() >= _next_pickup_sound:
			_next_pickup_sound = Time.get_ticks_msec() + 180
			game.audio.play("coin" if drop.kind == "currency" else "loot_common")
	elif drop.kind != "powerup":
		game.audio.play("loot_common")
		game.notify(_drop_name(drop))
	if remainder > 0:
		drop.payload["amount"] = remainder
		game.schedule_save()
		return true
	drop.collected = true
	drops.erase(drop)
	drop.queue_free()
	target = {}
	_flush_pending()
	game.schedule_save()
	return true

func collect_nearby(at: Vector3, radius: float) -> void:
	for drop: Node3D in drops.duplicate():
		if is_instance_valid(drop) and drop.kind in ["ammo", "currency", "powerup"] and at.distance_to(drop.global_position) < radius and _visible(drop.global_position + Vector3.UP * 0.3):
			collect_drop(drop)

func _drop_name(drop: Node3D) -> String:
	match drop.kind:
		"weapon": return str(game.inventory.stats(drop.payload).get("name", "Arma"))
		"attachment": return str(Loot.ATTACHMENTS.get(drop.payload.get("id", ""), {}).get("name", "Peça"))
		"powerup": return str(POWERUP_NAMES.get(drop.payload.get("id", ""), "POWER-UP"))
		"ammo": return "+%d MUNIÇÃO" % int(drop.payload.get("amount", 18))
	return "+%d PETISCOS" % int(drop.payload.get("amount", 0))

func on_kill(enemy: Node3D) -> void:
	if challenge.is_empty(): return
	if game.world.get_region_id(enemy.global_position) != str(challenge.get("region", "")): return
	challenge["kills"] = int(challenge["kills"]) + 1
	if int(challenge["kills"]) >= int(challenge["target"]):
		var reward: int = 300 + game.round_number * 25
		game.add_coins(reward, "challenge")
		drop_item("weapon", Loot.roll_weapon(game.round_number + 2, game.rng, game.loot_quality(), "epic"), enemy.global_position)
		game.award_profile("challenge", 1)
		game.ui.announce("DESAFIO COMPLETO", "Equipamento épico · +%d petiscos" % reward)
		challenge.clear()
		game.schedule_save()

func export_state() -> Dictionary:
	var loot: Array = []
	for drop: Node3D in drops:
		if is_instance_valid(drop) and not drop.collected: loot.append(drop.export_state())
	return {"used_pois":used_pois.duplicate(true),"discovered":discovered.duplicate(),"bosses_defeated":bosses_defeated.duplicate(),"challenge":challenge.duplicate(true),"drops":loot,"pending_rewards":pending_drops.duplicate(true)}

func import_state(data: Dictionary) -> void:
	_set_highlight(null)
	for drop: Node3D in drops:
		if is_instance_valid(drop): drop.queue_free()
	drops.clear()
	pending_drops.clear()
	target = {}
	used_pois = data.get("used_pois", {}).duplicate(true)
	discovered = data.get("discovered", []).duplicate()
	bosses_defeated = data.get("bosses_defeated", []).duplicate()
	challenge = data.get("challenge", {}).duplicate(true)
	for entry: Variant in data.get("drops", []):
		if not _valid_saved_drop(entry): continue
		if drops.size() >= MAX_DROPS:
			if pending_drops.size() < MAX_PENDING_REWARDS: pending_drops.append(entry.duplicate(true))
			continue
		var p: Array = entry.position
		var restored := _create_drop(str(entry.kind), entry.payload, Vector3(float(p[0]), float(p[1]) - 0.07, float(p[2])), true, false)
		restored.lifetime = float(entry.get("lifetime", 0))
	for entry: Variant in data.get("pending_rewards", []):
		if _valid_saved_drop(entry) and pending_drops.size() < MAX_PENDING_REWARDS: pending_drops.append(entry.duplicate(true))

func _valid_saved_drop(entry: Variant) -> bool:
	if not entry is Dictionary or not entry.get("payload") is Dictionary: return false
	if not _valid_payload(str(entry.get("kind", "")), entry.payload): return false
	var p: Variant = entry.get("position")
	if not p is Array or p.size() != 3: return false
	for axis: Variant in p:
		if not (axis is int or axis is float) or not is_finite(float(axis)): return false
	var age: Variant = entry.get("lifetime", 0)
	return (age is int or age is float) and is_finite(float(age)) and float(age) >= 0

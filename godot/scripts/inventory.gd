class_name MeyuiInventory
extends RefCounted

## A weapon's ammo and upgrades belong to its instance, not its model.
const Data = preload("res://data/game_data.gd")
const Loot = preload("res://data/loot_data.gd")
const Equipment = preload("res://data/equipment_data.gd")
const MULTIPLIERS: Array[String] = ["damage", "fire_rate", "magazine_size", "max_reserve", "reload_time", "range", "spread", "recoil"]
const ADDITIONS: Array[String] = ["critical_chance", "critical_multiplier", "handling"]
var items: Array[Dictionary] = []
var attachments: Array[Dictionary] = []
var equipped_id: String = ""
var weapon_slots: Array[String] = ["", "", "", ""]
var active_weapon_slot: int = 0
var grenade_id: String = "pulse"
var module_id: String = "balanced"
var owned_grenades: Array = ["pulse"]
var owned_modules: Array = ["balanced"]
var supplies: Dictionary = {"medkit":1, "ammo":1, "grenade":3}
var capacity: int = 24
var materials: int = 0

func create_starter() -> void:
	items.clear()
	attachments.clear()
	materials = 0
	var starter: Dictionary = Loot.starter_weapon()
	items.append(starter)
	equipped_id = String(starter.uid)
	weapon_slots = [equipped_id, "", "", ""]
	active_weapon_slot = 0
	grenade_id = "pulse"
	module_id = "balanced"
	owned_grenades = ["pulse"]
	owned_modules = ["balanced"]
	supplies = {"medkit":1, "ammo":1, "grenade":3}

func equipped() -> Dictionary:
	return find_item(equipped_id)

func find_item(uid: String) -> Dictionary:
	for item: Dictionary in items:
		if String(item.uid) == uid:
			return item
	return {}

func stats(item: Dictionary = {}) -> Dictionary:
	if item.is_empty():
		item = equipped()
	if item.is_empty() or not Data.WEAPONS.has(String(item.get("model_id", ""))):
		return {}
	var model_id: String = String(item.model_id)
	var result: Dictionary = Data.WEAPONS[model_id].duplicate(true)
	var rarity: String = String(item.get("rarity", "common"))
	var rarity_data: Dictionary = Loot.RARITIES.get(rarity, Loot.RARITIES.common)
	var manufacturer: Dictionary = Loot.MANUFACTURERS.get(String(item.get("manufacturer", "independent")), {})
	var level: int = maxi(1, int(item.get("level", 1)))
	var modifiers: Array[String] = []
	for value: Variant in item.get("modifiers", []):
		if Loot.MODIFIERS.has(String(value)) and not modifiers.has(String(value)):
			modifiers.append(String(value))
	result["model_id"] = model_id
	result["uid"] = String(item.get("uid", ""))
	result["family"] = String(result.get("family", "pistol" if model_id == "biscuit" else "rifle"))
	result["critical_chance"] = float(result.get("critical_chance", 0.05))
	result["critical_multiplier"] = float(result.get("critical_multiplier", 1.75))
	result["handling"] = float(result.get("handling", 70.0))
	result["pellets"] = int(result.get("pellets", 1))
	result["penetration"] = int(result.get("penetration", 0))
	result["element"] = String(item.get("element", result.get("element", "none")))
	var elements: Array[String] = []
	if String(result.element) != "none":
		elements.append(String(result.element))
	result["level"] = level
	result["rarity"] = rarity
	result["manufacturer"] = String(item.get("manufacturer", "independent"))
	result["manufacturer_name"] = String(manufacturer.get("name", "Oficina do Morro"))
	result["color"] = Loot.rarity_color(rarity)
	result["rarity_name"] = String(rarity_data.name)
	result["rarity_icon"] = String(rarity_data.icon)
	result["upgrade_level"] = maxi(0, int(item.get("upgrade_level", 0)))
	result["name"] = String(result.name)
	if not bool(Data.WEAPONS[model_id].get("legendary_only",false)) and Loot.rarity_rank(rarity) >= 4 and not modifiers.is_empty() and Loot.LEGENDARY_NAMES.has(modifiers[0]):
		result["name"] = "%s · %s" % [Loot.LEGENDARY_NAMES[modifiers[0]], result.name]
	_apply_stats(result, manufacturer)
	var rolls: Dictionary = item.get("rolls", {})
	_apply_stats(result, rolls)
	var level_scale: float = 1.0 + float(level - 1) * 0.09 + sqrt(float(level - 1)) * 0.08
	result.damage = float(result.damage) * level_scale * float(rarity_data.power) * Data.upgrade_multiplier(int(result.upgrade_level))
	var fitted: Dictionary = item.get("attachments", {})
	for slot: String in Loot.SLOTS:
		if not fitted.has(slot):
			continue
		var part: Dictionary = fitted[slot]
		var config: Dictionary = Loot.ATTACHMENTS.get(String(part.get("id", "")), {})
		var potency: float = float(part.get("roll", 1.0)) * (1.0 + Loot.rarity_rank(String(part.get("rarity", "common"))) * 0.12)
		_apply_stats(result, config, potency)
		if config.has("modifier") and not modifiers.has(String(config.modifier)):
			modifiers.append(String(config.modifier))
		if config.has("element"):
			var part_element: String = String(config.element)
			if not elements.has(part_element):
				elements.append(part_element)
			if String(result.element) == "none":
				result.element = part_element
	result["zoom"] = 2.0 if String(result.family) == "sniper" else 1.2
	if fitted.has("sight"):
		var sight_id: String = String(fitted.sight.get("id", ""))
		if sight_id == "scope":
			result.zoom = 2.6
		elif sight_id == "hybrid":
			result.zoom = 1.8
	result["weight"] = {"lmg":1.5, "sniper":1.3, "shotgun":1.2, "special":1.4, "smg":0.8}.get(result.family, 1.0)
	result["reload_empty_multiplier"] = 1.25 if String(result.family) == "shotgun" else 1.18
	result.damage = maxf(1.0, float(result.damage))
	result.fire_rate = clampf(float(result.fire_rate), 0.3, 24.0)
	result.magazine_size = maxi(1, roundi(float(result.magazine_size)))
	result.max_reserve = maxi(int(result.magazine_size), roundi(float(result.max_reserve)))
	result.reserve_ammo = mini(int(result.max_reserve), int(result.reserve_ammo))
	result.reload_time = clampf(float(result.reload_time), 0.35, 7.0)
	result.spread = clampf(float(result.spread), 0.0001, 0.15)
	result.recoil = clampf(float(result.recoil), 0.001, 0.09)
	result.handling = clampf(float(result.handling), 10.0, 100.0)
	result.critical_chance = clampf(float(result.critical_chance), 0.0, 0.85)
	result.critical_multiplier = clampf(float(result.critical_multiplier), 1.0, 5.0)
	result["precision"] = clampf(100.0 - float(result.spread) * 850.0, 5.0, 99.0)
	result["accuracy"] = float(result.precision)
	result["modifiers"] = modifiers
	result["elements"] = elements
	if modifiers.has("pierce"):
		result.penetration = maxi(1, int(result.penetration))
	result["pierce"] = int(result.penetration)
	result["crit_chance"] = float(result.critical_chance)
	result["crit_multiplier"] = float(result.critical_multiplier)
	result["projectile_speed"] = 0.0
	result["attachments"] = fitted.duplicate(true)
	result["dps"] = float(result.damage) * int(result.pellets) * float(result.fire_rate)
	var cycle: float = float(result.magazine_size) / float(result.fire_rate) + float(result.reload_time)
	result["sustained_dps"] = float(result.damage) * int(result.pellets) * int(result.magazine_size) / cycle
	result["value"] = maxi(20, roundi((65.0 + float(level) * 22.0) * (1.0 + int(rarity_data.rank) * 0.8) + int(result.upgrade_level) * 30.0))
	return result

func _apply_stats(result: Dictionary, changes: Dictionary, potency: float = 1.0) -> void:
	for key: String in MULTIPLIERS:
		if changes.has(key) and result.has(key):
			var factor: float = float(changes[key])
			var beneficial: bool = factor < 1.0 if key in ["spread", "recoil", "reload_time"] else factor > 1.0
			if beneficial:
				factor = 1.0 + (factor - 1.0) * potency
			result[key] = float(result[key]) * factor
	for key: String in ADDITIONS:
		if changes.has(key):
			result[key] = float(result.get(key, 0.0)) + float(changes[key]) * potency

func add_item(item: Dictionary) -> bool:
	if items.size() >= capacity or not _valid_weapon(item) or not find_item(String(item.uid)).is_empty():
		return false
	var candidate: Dictionary = _normalize_weapon(item)
	# Parts cannot exist in the backpack and on a gun at the same time.
	for part: Dictionary in candidate.attachments.values():
		if _has_attachment_uid(String(part.uid)):
			return false
	items.append(candidate)
	var vacant := weapon_slots.find("")
	if vacant >= 0: weapon_slots[vacant] = String(candidate.uid)
	if equipped_id.is_empty():
		equipped_id = String(candidate.uid)
		active_weapon_slot = maxi(0, vacant)
	return true

func equip(uid: String) -> bool:
	if find_item(uid).is_empty():
		return false
	var slot := weapon_slots.find(uid)
	if slot < 0:
		slot = active_weapon_slot
		weapon_slots[slot] = uid
	active_weapon_slot = slot
	equipped_id = uid
	return true

func assign_slot(uid: String, slot: int) -> bool:
	if slot < 0 or slot >= 4 or find_item(uid).is_empty(): return false
	var previous := weapon_slots.find(uid)
	if previous >= 0: weapon_slots[previous] = weapon_slots[slot]
	weapon_slots[slot] = uid
	active_weapon_slot = slot
	equipped_id = uid
	return true

func select_slot(slot: int) -> bool:
	return slot >= 0 and slot < 4 and not weapon_slots[slot].is_empty() and equip(weapon_slots[slot])

func swap_held(incoming: Dictionary) -> Dictionary:
	# Validate the complete transaction first, including duplicate attachment ownership.
	# Swapping still works with a full backpack; no pickup is lost on failure.
	var held := equipped()
	if held.is_empty() or bool(held.get("favorite", false)): return {}
	var candidate: RefCounted = get_script().new()
	if not candidate.import_state(export_state()): return {}
	var index: int = candidate.items.find(candidate.equipped())
	candidate.items.remove_at(index)
	candidate.weapon_slots[candidate.active_weapon_slot] = ""
	if not candidate.add_item(incoming): return {}
	candidate.assign_slot(String(incoming.uid), active_weapon_slot)
	if not import_state(candidate.export_state()): return {}
	return held

func remove(uid: String, mode: String = "discard") -> Dictionary:
	if not mode in ["discard", "sell", "dismantle", "drop"]:
		return {}
	var item: Dictionary = find_item(uid)
	if item.is_empty() or uid == equipped_id or bool(item.get("favorite", false)):
		return {}
	if mode == "dismantle":
		materials += 2 + Loot.rarity_rank(String(item.rarity)) * 2 + int(item.get("upgrade_level", 0))
	items.erase(item)
	var slot := weapon_slots.find(uid)
	if slot >= 0: weapon_slots[slot] = ""
	return item

func set_flag(uid: String, flag: String, value: bool) -> bool:
	if not flag in ["favorite", "junk"]:
		return false
	var item: Dictionary = find_item(uid)
	if item.is_empty():
		return false
	item[flag] = value
	if value:
		item["junk" if flag == "favorite" else "favorite"] = false
	return true

func auto_equip() -> bool:
	if items.is_empty():
		return false
	var best_id: String = equipped_id
	var best_score: float = -1.0
	for item: Dictionary in items:
		if bool(item.get("junk", false)):
			continue
		var evaluated: Dictionary = stats(item)
		var score: float = float(evaluated.sustained_dps) * (1.0 + float(evaluated.critical_chance) * (float(evaluated.critical_multiplier) - 1.0))
		if score > best_score:
			best_score = score
			best_id = String(item.uid)
	return equip(best_id)

func sorted_items(sort_id: String) -> Array:
	var result: Array = items.duplicate()
	if sort_id == "recent" or sort_id == "newest":
		result.reverse()
		return result
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if sort_id == "rarity":
			return Loot.rarity_rank(String(a.rarity)) > Loot.rarity_rank(String(b.rarity))
		if sort_id == "level":
			return int(a.level) > int(b.level)
		if sort_id == "type":
			return String(stats(a).family) < String(stats(b).family)
		var key: String = "value" if sort_id == "value" else ("dps" if sort_id == "dps" else "damage")
		return float(stats(a)[key]) > float(stats(b)[key])
	)
	return result

func add_attachment(item: Dictionary) -> bool:
	if attachments.size() >= 96 or not _valid_attachment(item) or _has_attachment_uid(String(item.uid)):
		return false
	attachments.append(_normalize_attachment(item))
	return true

func install(weapon_uid: String, attachment_uid: String) -> bool:
	var weapon: Dictionary = find_item(weapon_uid)
	if weapon.is_empty():
		return false
	for part: Dictionary in attachments:
		if String(part.uid) != attachment_uid:
			continue
		var slot: String = String(part.slot)
		var old_part: Dictionary = weapon.attachments.get(slot, {})
		attachments.erase(part)
		if not old_part.is_empty():
			attachments.append(old_part)
		weapon.attachments[slot] = part
		_clamp_ammo(weapon)
		return true
	return false

func uninstall(weapon_uid: String, slot: String) -> bool:
	var weapon: Dictionary = find_item(weapon_uid)
	if weapon.is_empty() or not weapon.attachments.has(slot) or attachments.size() >= 96:
		return false
	attachments.append(weapon.attachments[slot])
	weapon.attachments.erase(slot)
	_clamp_ammo(weapon)
	return true

func _clamp_ammo(weapon: Dictionary) -> void:
	var evaluated: Dictionary = stats(weapon)
	var excess: int = maxi(0, int(weapon.magazine) - int(evaluated.magazine_size))
	weapon.magazine = clampi(int(weapon.magazine), 0, int(evaluated.magazine_size))
	# Run perks can increase reserve capacity beyond the weapon's base stats.
	# Player.sync_inventory applies that final cap after the run build is restored.
	weapon.reserve = maxi(0, int(weapon.reserve) + excess)

func _has_attachment_uid(uid: String) -> bool:
	for part: Dictionary in attachments:
		if String(part.uid) == uid:
			return true
	for weapon: Dictionary in items:
		for part: Dictionary in weapon.attachments.values():
			if String(part.uid) == uid:
				return true
	return false

func upgrade_preview(uid: String = "") -> Dictionary:
	var item: Dictionary = equipped() if uid.is_empty() else find_item(uid)
	if item.is_empty():
		return {}
	var next: Dictionary = item.duplicate(true)
	next.upgrade_level = int(item.upgrade_level) + 1
	return {"cost":Data.upgrade_cost(int(item.upgrade_level)), "from":stats(item), "to":stats(next)}

func reroll_cost(uid: String, kind: String = "stat") -> int:
	if kind == "modifiers":
		kind = "modifier"
	var item: Dictionary = find_item(uid)
	if item.is_empty() or kind not in ["stat", "element", "modifier", "attachment", "manufacturer"]:
		return 0
	var count: int = maxi(0, int(item.get("reroll_count", 0)))
	var base: float = 110.0 + int(item.level) * 12.0 + Loot.rarity_rank(String(item.rarity)) * 35.0
	var factor: float = {"stat":1.0, "element":1.4, "modifier":1.8, "attachment":1.25, "manufacturer":1.6}[kind]
	return roundi(base * factor * (1.0 + count * 0.3 + pow(float(count), 1.12) * 0.08))

func reroll(uid: String, kind: String, rng: RandomNumberGenerator) -> bool:
	# The coordinator owns coins and charges reroll_cost after a successful result.
	if kind == "modifiers":
		kind = "modifier"
	var item: Dictionary = find_item(uid)
	if item.is_empty() or reroll_cost(uid, kind) <= 0:
		return false
	if kind == "stat":
		var keys: Array[String] = ["damage", "fire_rate", "magazine_size", "reload_time", "range", "spread", "recoil"]
		var key: String = keys[rng.randi_range(0, keys.size() - 1)]
		item.rolls[key] = snappedf(rng.randf_range(0.88, 1.12), 0.001)
	elif kind == "element":
		var choices: Array[String] = []
		for element: String in Loot.ELEMENTS:
			if element != "none" and element != String(item.element):
				choices.append(element)
		item.element = choices[rng.randi_range(0, choices.size() - 1)]
	elif kind == "modifier":
		var index: int = rng.randi_range(0, maxi(0, item.modifiers.size() - 1))
		var pool: Array = Loot.LEGENDARY_NAMES.keys() if Loot.rarity_rank(String(item.rarity)) >= 4 and index == 0 else Loot.MODIFIERS.keys()
		var choices: Array[String] = []
		for key: String in pool:
			if not item.modifiers.has(key):
				choices.append(key)
		if choices.is_empty():
			return false
		var replacement: String = choices[rng.randi_range(0, choices.size() - 1)]
		if item.modifiers.is_empty():
			item.modifiers.append(replacement)
		else:
			item.modifiers[index] = replacement
	elif kind == "attachment":
		var slots: Array = item.attachments.keys() if not item.attachments.is_empty() else Loot.SLOTS
		var slot: String = String(slots[rng.randi_range(0, slots.size() - 1)])
		var replacement: Dictionary = Loot.roll_attachment(rng, 1.0 + Loot.rarity_rank(String(item.rarity)) * 0.3, slot)
		if replacement.is_empty() or _has_attachment_uid(String(replacement.uid)):
			return false
		item.attachments[slot] = replacement
	elif kind == "manufacturer":
		var choices: Array[String] = []
		for maker: String in Loot.MANUFACTURERS:
			if maker != String(item.manufacturer):
				choices.append(maker)
		item.manufacturer = choices[rng.randi_range(0, choices.size() - 1)]
	item["reroll_count"] = int(item.get("reroll_count", 0)) + 1
	_clamp_ammo(item)
	return true

func export_state() -> Dictionary:
	return {"version":2, "items":items.duplicate(true), "attachments":attachments.duplicate(true), "equipped_id":equipped_id, "capacity":capacity, "materials":materials, "weapon_slots":weapon_slots.duplicate(), "active_weapon_slot":active_weapon_slot, "grenade_id":grenade_id, "module_id":module_id, "owned_grenades":owned_grenades.duplicate(), "owned_modules":owned_modules.duplicate(), "supplies":supplies.duplicate()}

func import_state(state: Dictionary) -> bool:
	# Validate into a temporary inventory, then commit once. Bad saves never half-load.
	if not _valid_number(state.get("version", 0), 1.0, 2.0) or not state.get("items") is Array or not state.get("attachments") is Array:
		return false
	if not state.get("equipped_id") is String or not _valid_number(state.get("capacity", 24), 1.0, 96.0) or not _valid_number(state.get("materials", 0), 0.0, 2000000000.0):
		return false
	var candidate: RefCounted = get_script().new()
	candidate.capacity = clampi(int(state.get("capacity", 24)), 1, 96)
	candidate.materials = clampi(int(state.get("materials", 0)), 0, 2000000000)
	for value: Variant in state.items:
		if not value is Dictionary or not candidate.add_item(value):
			return false
	for value: Variant in state.attachments:
		if not value is Dictionary or not candidate.add_attachment(value):
			return false
	if candidate.items.is_empty() or not candidate.equip(String(state.get("equipped_id", ""))):
		return false
	if int(state.version) >= 2:
		if not state.get("weapon_slots") is Array or state.weapon_slots.size() != 4 or not _valid_number(state.get("active_weapon_slot"), 0, 3): return false
		var seen: Array = []
		for uid: Variant in state.weapon_slots:
			if not uid is String: return false
			if uid != "" and (candidate.find_item(uid).is_empty() or seen.has(uid)): return false
			if uid != "": seen.append(uid)
		if state.weapon_slots[int(state.active_weapon_slot)] != state.equipped_id: return false
		candidate.weapon_slots.assign(state.weapon_slots)
		candidate.active_weapon_slot = int(state.active_weapon_slot)
		for pair: Array in [["owned_grenades", "grenade_id", Equipment.GRENADES], ["owned_modules", "module_id", Equipment.MODULES]]:
			var owned: Variant = state.get(pair[0])
			if not owned is Array or owned.is_empty() or owned.size() > pair[2].size(): return false
			var unique: Array = []
			for id: Variant in owned:
				if not id is String or not pair[2].has(id) or unique.has(id): return false
				unique.append(id)
			if not state.get(pair[1]) is String or not owned.has(state[pair[1]]): return false
			candidate.set(pair[0], owned.duplicate())
			candidate.set(pair[1], state[pair[1]])
		if not state.get("supplies") is Dictionary or state.supplies.size() != Equipment.SUPPLIES.size(): return false
		for id: String in Equipment.SUPPLIES:
			if not _valid_number(state.supplies.get(id), 0, Equipment.SUPPLIES[id].max): return false
		candidate.supplies = state.supplies.duplicate()
		for id: String in Equipment.SUPPLIES: candidate.supplies[id] = int(candidate.supplies[id])
	items = candidate.items
	attachments = candidate.attachments
	equipped_id = candidate.equipped_id
	capacity = candidate.capacity
	materials = candidate.materials
	weapon_slots = candidate.weapon_slots
	active_weapon_slot = candidate.active_weapon_slot
	grenade_id = candidate.grenade_id
	module_id = candidate.module_id
	owned_grenades = candidate.owned_grenades
	owned_modules = candidate.owned_modules
	supplies = candidate.supplies
	return true

func _valid_weapon(item: Dictionary) -> bool:
	if not item.get("uid") is String or String(item.uid).is_empty() or String(item.uid).length() > 128:
		return false
	for key: String in ["model_id", "rarity", "manufacturer"]:
		if not item.get(key) is String:
			return false
	if not Data.WEAPONS.has(String(item.model_id)) or not Loot.RARITIES.has(String(item.rarity)):
		return false
	var maker: String = String(item.get("manufacturer", ""))
	if maker != "independent" and not Loot.MANUFACTURERS.has(maker):
		return false
	if not item.get("rolls") is Dictionary or not item.get("modifiers") is Array or not item.get("attachments") is Dictionary:
		return false
	if not item.get("element", "none") is String or not Loot.ELEMENTS.has(String(item.get("element", "none"))) or item.modifiers.size() > Loot.MODIFIERS.size():
		return false
	for key: Variant in item.rolls:
		if not key is String:
			return false
		if key not in MULTIPLIERS and key != "critical_chance":
			return false
		if not _valid_number(item.rolls[key], 0.0 if key == "critical_chance" else 0.5, 0.25 if key == "critical_chance" else 1.5):
			return false
	for value: Variant in item.modifiers:
		if not value is String or not Loot.MODIFIERS.has(value):
			return false
	for key: String in ["level", "magazine", "reserve", "upgrade_level", "reroll_count"]:
		if not _valid_number(item.get(key, 0), 1.0 if key == "level" else 0.0, 1000000.0):
			return false
	if not _valid_number(item.get("seed", 0), -9007199254740991.0, 9007199254740991.0):
		return false
	if not item.get("favorite", false) is bool or not item.get("junk", false) is bool:
		return false
	var part_uids: Dictionary = {}
	for slot: Variant in item.attachments:
		if not slot is String or not Loot.SLOTS.has(slot):
			return false
		var value: Variant = item.attachments[slot]
		if not value is Dictionary or not _valid_attachment(value) or String(value.slot) != String(slot) or part_uids.has(String(value.uid)):
			return false
		part_uids[String(value.uid)] = true
	return true

func _valid_attachment(item: Dictionary) -> bool:
	if not item.get("uid") is String or String(item.uid).is_empty() or String(item.uid).length() > 128:
		return false
	for key: String in ["id", "slot", "rarity"]:
		if not item.get(key) is String:
			return false
	if not Loot.ATTACHMENTS.has(String(item.id)) or not Loot.RARITIES.has(String(item.rarity)):
		return false
	return String(item.get("slot", "")) == String(Loot.ATTACHMENTS[String(item.id)].slot) and _valid_number(item.get("roll", 0), 0.5, 1.5)

func _valid_number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

func _normalize_weapon(item: Dictionary) -> Dictionary:
	var clean: Dictionary = {
		"uid":String(item.uid), "model_id":String(item.model_id), "level":int(item.level),
		"rarity":String(item.rarity), "manufacturer":String(item.manufacturer), "seed":int(item.get("seed", 0)),
		"rolls":item.rolls.duplicate(true), "modifiers":item.modifiers.duplicate(), "element":String(item.get("element", "none")),
		"attachments":{}, "magazine":int(item.magazine), "reserve":int(item.reserve),
		"upgrade_level":int(item.upgrade_level), "reroll_count":int(item.get("reroll_count", 0)), "favorite":bool(item.get("favorite", false)), "junk":bool(item.get("junk", false))
	}
	for slot: String in item.attachments:
		clean.attachments[slot] = _normalize_attachment(item.attachments[slot])
	if clean.favorite:
		clean.junk = false
	_clamp_ammo(clean)
	return clean

func _normalize_attachment(item: Dictionary) -> Dictionary:
	return {"uid":String(item.uid), "id":String(item.id), "slot":String(item.slot), "rarity":String(item.rarity), "roll":float(item.roll)}

extends Node3D
## Run coordinator. Every purchase, reward and checkpoint uses the same live state.
const Data = preload("res://data/game_data.gd")
const Loot = preload("res://data/loot_data.gd")
const Inventory = preload("res://scripts/inventory.gd")
const Progression = preload("res://scripts/run_progression.gd")
const Director = preload("res://scripts/run_director.gd")
const SaveManager = preload("res://scripts/save_manager.gd")
const SnapshotValidator = preload("res://scripts/snapshot_validator.gd")
const Settings = preload("res://scripts/game_settings.gd")
const Player = preload("res://scripts/player.gd")
const World = preload("res://scripts/world.gd")
const Enemy = preload("res://scripts/enemy.gd")
const EnemyData = preload("res://data/enemy_data.gd")
const Companion = preload("res://scripts/companion.gd")
const Exploration = preload("res://scripts/exploration.gd")
const UI = preload("res://scripts/game_ui.gd")
const Audio = preload("res://scripts/game_audio.gd")
const Equipment = preload("res://data/equipment_data.gd")
const WeaponWheel = preload("res://scripts/weapon_wheel.gd")
const Grenade = preload("res://scripts/thrown_grenade.gd")
const Coop = preload("res://scripts/coop_session.gd")
const CoopMenu = preload("res://scripts/coop_menu.gd")
var coop: Node
var coop_identity_path := "user://coop_identity.cfg"
var weapon_wheel: Control
var _grenade_ready_at := 0.0
var inventory = Inventory.new()
var progression = Progression.new()
var director = Director.new()
var save_manager = SaveManager.new()
var settings = Settings.new()
var rng := RandomNumberGenerator.new()
var running := false
var paused := true
var coins := 250
var round_number := 1
var difficulty_id := "normal"
var chaos_active := false
var active_slot := 0
var run_seed := 1
var elapsed := 0.0
var kills := 0
var phase := "prepare"
var phase_time := 3.0
var wave_total := 6
var wave_spawned := 0
var wave_killed := 0
var active_powerups: Dictionary = {}
var boss_zone: Dictionary = {}
var stats: Dictionary = {"damage":0.0,"headshots":0,"shots":0,"earned":0,"purchases":0,"bosses":0}
var profile: Dictionary = {"sigils":0,"record":0,"weapons":[],"enemies":[],"achievements":[],"unlocks":[],"awarded":[]}
var enemies: Array = []
var player: CharacterBody3D
var companion: CharacterBody3D
var world: Node3D
var exploration: Node3D
var ui: CanvasLayer
var audio: Node
var _profile_store = SaveManager.new("user://profile")
var _menu_camera: Camera3D
var _effects: Array[Node3D] = []
var _hud_clock := 0.0
var _menu_kind := "main"
var _last_damage := -30.0
var _last_kill := -10.0
var _kill_chain := 0
var _save_pending := false
var _save_delay := 0.0
var _saved_time := 0.0
var _coins_gain := 0
var _gain_time := 0.0
var _slow_remaining := 0.0
var _regeneration_clock := 0.0
var _damage_credit := 0.0
var _restoring := false
var _shot_kill := false
var _quitting := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	get_tree().auto_accept_quit = false
	settings.load_settings()
	var saved_profile: Dictionary = _profile_store.load_slot(1)
	if bool(saved_profile.get("ok", false)): profile.merge(saved_profile.get("state", {}), true)
	rng.randomize()
	inventory.create_starter()
	world = World.new()
	world.setup(self)
	add_child(world)
	_create_actors()
	exploration = Exploration.new()
	exploration.setup(self)
	add_child(exploration)
	_menu_camera = Camera3D.new()
	_menu_camera.fov = 61
	add_child(_menu_camera)
	_menu_camera.position = world.menu_camera_position
	_menu_camera.look_at(world.menu_look_at)
	_menu_camera.make_current()
	player.hide()
	audio = Audio.new()
	add_child(audio)
	ui = UI.new()
	ui.setup(self)
	add_child(ui)
	coop = Coop.new()
	coop.setup(self)
	add_child(coop)
	var coop_menu := CoopMenu.new()
	coop_menu.game = self
	add_child(coop_menu)
	settings.apply(get_tree(), self)
	audio.set_active(true)
	ui.show_menu()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_update_hud()

func _create_actors() -> void:
	for actor: Node in [player, companion]:
		if is_instance_valid(actor):
			remove_child(actor)
			actor.queue_free()
	player = Player.new()
	player.setup(self)
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.position = world.spawn_position
	companion = Companion.new()
	companion.setup(self)
	companion.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(companion)
	companion.position = player.position + Vector3(1.3, 0, -0.2)

func _setup_input() -> void:
	var keys := {"move_forward":KEY_W,"move_back":KEY_S,"move_left":KEY_A,"move_right":KEY_D,"jump":KEY_SPACE,"sprint":KEY_SHIFT,"reload":KEY_R,"view_toggle":KEY_F1,"weapon_1":KEY_1,"weapon_2":KEY_2,"weapon_3":KEY_3,"shop":KEY_TAB,"pause_game":KEY_ESCAPE,"dog_mode":KEY_C,"interact":KEY_E,"inventory":KEY_I,"weapon_inspect":KEY_V,"flashlight":KEY_L}
	keys.merge({"weapon_4":KEY_4, "weapon_wheel":KEY_T, "swap_loot":KEY_F, "grenade":KEY_G, "use_medkit":KEY_H, "use_ammo":KEY_J, "crouch":KEY_CTRL, "dive":KEY_Z})
	for action: String in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var key := InputEventKey.new()
			key.physical_keycode = keys[action]
			InputMap.action_add_event(action, key)
	for action: String in ["fire", "aim"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var button := InputEventMouseButton.new()
			button.button_index = MOUSE_BUTTON_LEFT if action == "fire" else MOUSE_BUTTON_RIGHT
			InputMap.action_add_event(action, button)

func start_run(selected_difficulty: String, chaos: bool, slot: int = -1) -> void:
	if running: return
	if is_instance_valid(coop):
		if coop.is_online(): coop.stop()
		coop.records.clear()
	if slot < 1:
		for entry: Dictionary in save_manager.list_slots():
			if not bool(entry.get("exists", false)):
				slot = int(entry["slot"])
				break
	if slot < 1 or slot > 3:
		notify("Escolha um slot para a nova expedição.")
		return
	active_slot = slot
	difficulty_id = selected_difficulty if Data.DIFFICULTIES.has(selected_difficulty) else "normal"
	chaos_active = chaos
	_clear_run()
	inventory.create_starter()
	progression = Progression.new()
	run_seed = int(Time.get_unix_time_from_system()) ^ int(Time.get_ticks_usec())
	rng.seed = run_seed
	director.start(difficulty_id, 1 if chaos else 0, run_seed)
	coins = 250
	elapsed = 0
	kills = 0
	stats = {"damage":0.0,"headshots":0,"shots":0,"earned":0,"purchases":0,"bosses":0}
	world.import_state({"unlocked_regions":["patio","mercado"]})
	exploration.import_state({})
	_create_actors()
	_sync_director()
	running = true
	paused = false
	_menu_kind = ""
	get_tree().paused = false
	player.camera.make_current()
	ui.hide_menus()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	audio.set_active(true)
	settings.apply(get_tree(), self)
	ui.announce("ENTRE BECOS", "A noite é longa. Faro conhece o caminho.")
	schedule_save()

func _clear_run() -> void:
	_grenade_ready_at = 0
	for grenade: Node in get_tree().get_nodes_in_group("run_grenades"): grenade.queue_free()
	for enemy: Node in enemies:
		if is_instance_valid(enemy):
			remove_child(enemy)
			enemy.queue_free()
	enemies.clear()
	for effect: Node3D in _effects:
		if is_instance_valid(effect): effect.queue_free()
	_effects.clear()
	active_powerups.clear()
	boss_zone.clear()
	_save_pending = false
	_last_damage = -30
	_kill_chain = 0
	_damage_credit = 0
	Engine.time_scale = 1
	world.set_boss_arena(false)

func _input(event: InputEvent) -> void:
	if not running: return
	if event.is_action_pressed("weapon_wheel") and not paused:
		open_weapon_wheel()
		get_viewport().set_input_as_handled()
		return
	if _menu_kind == "wheel":
		if event.is_action_released("weapon_wheel"): close_weapon_wheel(true)
		elif event.is_action_pressed("pause_game"): close_weapon_wheel(false)
		get_viewport().set_input_as_handled()
		return
	if not paused:
		if event.is_action_pressed("swap_loot"):
			if not _coop_action("swap_ground_weapon"): exploration.swap_ground_weapon()
		elif event.is_action_pressed("grenade"): use_supply("grenade")
		elif event.is_action_pressed("use_medkit"): use_supply("medkit")
		elif event.is_action_pressed("use_ammo"): use_supply("ammo")
	if event.is_action_pressed("pause_game"):
		if paused: resume_game()
		else: pause_game()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("shop") or event.is_action_pressed("inventory"):
		if paused and _menu_kind == "inventory": resume_game()
		else: open_inventory("forge" if event.is_action_pressed("shop") else "inventory")
		get_viewport().set_input_as_handled()
	elif not paused and event.is_action_pressed("interact"):
		if not _coop_action("interact"): exploration.interact()
		get_viewport().set_input_as_handled()
	elif not paused and event.is_action_pressed("dog_mode"):
		if not _coop_action("dog_mode"): companion.toggle_mode()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _menu_kind == "wheel":
		close_weapon_wheel(false)
		pause_game()
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and running and not paused: pause_game()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST: quit_game()

func _process(delta: float) -> void:
	if not is_instance_valid(ui): return
	_saved_time = maxf(0, _saved_time - delta)
	_gain_time = maxf(0, _gain_time - delta)
	_hud_clock -= delta
	if _hud_clock <= 0:
		_hud_clock = 0.075
		_update_hud()
	if not running:
		if _menu_kind == "main":
			_menu_camera.position = world.menu_camera_position + Vector3(sin(Time.get_ticks_msec() * 0.00012) * 0.45, 0, 0)
			_menu_camera.look_at(world.menu_look_at)
		return
	if simulation_paused() or (is_instance_valid(coop) and coop.is_client()): return
	elapsed += delta
	if _slow_remaining > 0:
		_slow_remaining -= delta / maxf(0.1, Engine.time_scale)
		if _slow_remaining <= 0: Engine.time_scale = 1
	audio.set_context(not boss_zone.is_empty() or enemies.any(func(enemy: Node) -> bool: return is_instance_valid(enemy) and str(enemy.kind).begins_with("boss")), str(director.active_event.get("id", "")))
	audio.tick(delta, clampf(float(enemies.size()) / 20.0, 0, 1))
	for id: String in active_powerups.keys():
		active_powerups[id] = float(active_powerups[id]) - delta
		if float(active_powerups[id]) <= 0: active_powerups.erase(id)
	_regeneration_clock += delta
	if _regeneration_clock >= 1:
		_regeneration_clock = 0
		if elapsed - _last_damage > 5: player.heal(float(progression.modifiers()["regen"]))
	if world.navigation_ready:
		var actions: Array = director.tick(delta, {"health_ratio":player.health / player.max_health,"ammo_ratio":float(player.reserve + player.magazine) / maxf(1, float(player.get_weapon_stats()["max_reserve"])),"alive":enemies.size(),"kills_per_second":float(kills) / maxf(1, elapsed),"seconds_without_damage":elapsed - _last_damage,"region_id":world.get_region_id(player.global_position)})
		_sync_director()
		for action: Dictionary in actions: _director_action(action)
	if _save_pending:
		_save_delay -= delta
		if _save_delay <= 0: save_game()

func _sync_director() -> void:
	round_number = director.round_number
	phase = director.phase
	phase_time = director.phase_time
	wave_total = director.wave_total
	wave_spawned = director.spawned
	wave_killed = director.killed

func _director_action(action: Dictionary) -> void:
	match str(action.get("type", "")):
		"spawn": _spawn_enemy_data(action)
		"round_start":
			audio.play("round")
			ui.announce("ROUND %02d" % round_number, "A cidade mudou. Sua build também.")
		"round_complete":
			add_coins(int(action.get("reward", 100)), "round")
			player.heal(12)
			player.add_ammo(12)
			audio.play("victory")
			ui.announce("ROUND %02d COMPLETO" % round_number, "+%d petiscos · um respiro para explorar" % int(action.get("reward", 100)))
			if not bool(settings.data.get("reduced_flashes", false)) and not coop.is_online():
				Engine.time_scale = 0.42
				_slow_remaining = 0.23
			if round_number > int(profile.get("record", 0)):
				profile["record"] = round_number
				if round_number % 5 == 0: award_profile("round_%d" % round_number, 2)
			schedule_save()
		"event_start":
			var event: Dictionary = action.get("event", {})
			world.set_event(str(event.get("id", "")))
			ui.announce(str(event.get("name", "EVENTO")), "Risco maior. Novas oportunidades.")
			audio.play("event")
			if event.get("id", "") == "supply":
				exploration.drop_item("ammo", {"amount":48}, player.global_position + Vector3(1, 0, 0))
				exploration.drop_item("weapon", Loot.roll_weapon(round_number, rng, loot_quality(), "rare"), player.global_position + Vector3(1.6, 0, 0))
		"event_complete":
			world.set_event("")
			add_coins(int(action.get("reward", 80)), "event")
			notify("Evento completo · recompensa recebida")
			schedule_save()

func _spawn_enemy_data(data: Dictionary) -> Node3D:
	var kind: String = str(data.get("kind", "grunt"))
	var elite: bool = bool(data.get("elite", false)) or kind == "elite"
	if kind == "elite": kind = "grunt"
	var enemy := Enemy.new()
	enemy.setup(self, kind, round_number, float(Data.DIFFICULTIES[difficulty_id]["health"]))
	var mods: Dictionary = director.get_modifiers()
	enemy.configure_difficulty(float(Data.DIFFICULTIES[difficulty_id]["damage"]) * float(mods.get("enemy_damage", 1)), float(Data.DIFFICULTIES[difficulty_id]["speed"]) * float(mods.get("enemy_speed", 1)), chaos_active)
	if elite: enemy.configure_elite(["fire","vampiric","frenzy"][rng.randi_range(0, 2)])
	if is_instance_valid(coop) and coop.is_host():
		enemy.health *= coop.health_multiplier()
		enemy.max_health *= coop.health_multiplier()
	enemy.process_mode = Node.PROCESS_MODE_PAUSABLE
	enemy.set_meta("wave_enemy", bool(data.get("wave_enemy", true)))
	add_child(enemy)
	enemy.global_position = data.get("position", world.get_spawn_near(player.global_position, 11))
	enemies.append(enemy)
	if not profile["enemies"].has(kind): profile["enemies"].append(kind)
	return enemy

func spawn_add(kind: String, at: Vector3) -> void:
	if enemies.size() >= 24 or not director.add_summon(): return
	_spawn_enemy_data({"kind":kind,"position":at,"wave_enemy":true})

func start_boss(poi: Dictionary) -> void:
	if not boss_zone.is_empty(): return
	if enemies.size() >= Director.MAX_ALIVE:
		notify("Abra espaço na horda antes de desafiar o boss")
		return
	boss_zone = {"id":str(poi.get("id", "boss_quadra")),"region":str(poi.get("region_id", "quadra"))}
	world.set_boss_arena(true)
	var at: Vector3 = poi.get("position", player.global_position + Vector3(0, 0, -8))
	var enemy := _spawn_enemy_data({"kind":"boss_bulwark","position":at + Vector3(0, 0.1, -3),"wave_enemy":false})
	enemy.set_meta("boss_zone_id", boss_zone["id"])
	ui.announce(str(EnemyData.BOSSES["bulwark"]["name"]).to_upper(), "Os portões fecharam. Observe o chão.")
	audio.play("boss")
	schedule_save()

func on_enemy_damaged(enemy: Node3D, amount: float, zone: String, source: String) -> void:
	if not running or amount <= 0: return
	stats["damage"] = float(stats.get("damage", 0)) + amount
	if zone == "head": stats["headshots"] = int(stats.get("headshots", 0)) + 1
	if source != "self":
		_damage_credit += minf(amount, 200.0) * 0.08
		if _damage_credit >= 1:
			var awarded := floori(_damage_credit)
			_damage_credit -= awarded
			add_coins(awarded, "damage")
	if bool(settings.data.get("damage_numbers", true)):
		_float_text(str(roundi(amount)), enemy.global_position + Vector3(0, 1.8, 0), Color("ecc485") if zone == "head" else Color("cbd9d9"))

func on_enemy_killed(enemy: Node, reward: int, source: String = "player") -> void:
	if enemy.get_meta("reward_paid", false): return
	enemy.set_meta("reward_paid", true)
	if enemy in enemies:
		enemies.erase(enemy)
		director.register_kill(bool(enemy.get_meta("wave_enemy", true)))
		_sync_director()
	kills += 1
	if not running: return
	var event_mods: Dictionary = director.get_modifiers()
	var earned := roundi(reward * float(Data.DIFFICULTIES[difficulty_id]["reward"]) * (1.6 if chaos_active else 1.0) * float(event_mods.get("reward", 1)))
	add_coins(earned, "kill")
	audio.play("kill")
	if source == "player":
		_shot_kill = true
		ui.show_hit(false, true)
	player.on_enemy_killed(enemy, source)
	exploration.on_kill(enemy)
	_kill_chain = _kill_chain + 1 if elapsed - _last_kill < 2.5 else 1
	_last_kill = elapsed
	if _kill_chain in [3, 6, 10]: notify({3:"TRIPLA",6:"SEQUÊNCIA",10:"IMPARÁVEL"}[_kill_chain] + " · %d eliminações" % _kill_chain)
	var boss: bool = str(enemy.get("kind")).begins_with("boss")
	var elite: bool = not str(enemy.get("elite")).is_empty()
	if source != "self" and (boss or kills == 1 or rng.randf() < (0.35 if elite else 0.10)):
		var rarity := "legendary" if boss else ("rare" if elite else ("uncommon" if kills == 1 else ""))
		exploration.drop_item("weapon", Loot.roll_weapon(round_number + (2 if boss else 0), rng, loot_quality(), rarity), enemy.global_position)
	if rng.randf() < (0.55 if elite else 0.12): exploration.drop_item("attachment", Loot.roll_attachment(rng, loot_quality()), enemy.global_position + Vector3(0.45, 0, 0))
	if rng.randf() < 0.2: exploration.drop_item("ammo", {"amount":18}, enemy.global_position + Vector3(-0.4, 0, 0))
	if rng.randf() < 0.035: exploration.drop_item("powerup", {"id":Exploration.POWERUPS[rng.randi_range(0, Exploration.POWERUPS.size() - 1)]}, enemy.global_position + Vector3(0, 0, 0.5))
	if boss:
		stats["bosses"] = int(stats.get("bosses", 0)) + 1
		player.add_ammo(48)
		award_profile("boss_%d_%s" % [round_number, str(enemy.get("boss_id"))], 3)
		var zone: String = str(enemy.get_meta("boss_zone_id", ""))
		if not zone.is_empty():
			exploration.bosses_defeated.append(zone)
			boss_zone.clear()
			world.set_boss_arena(false)
		ui.announce("BOSS DERROTADO", "Uma lendária espera por você.")
		audio.play("boss_kill")
		schedule_save()

func on_shot(weapon: Dictionary, origin: Vector3, point: Vector3, hit_enemy: bool, headshot: bool) -> void:
	if is_instance_valid(coop): coop.shot_feedback(weapon, origin, point, hit_enemy, headshot)
	stats["shots"] = int(stats.get("shots", 0)) + 1
	audio.play("shot", str(weapon.get("model_id", weapon.get("id", "biscuit"))))
	if hit_enemy:
		var critical: bool = headshot or bool(weapon.get("critical", false))
		ui.show_hit(critical, _shot_kill)
		audio.play("headshot" if critical else "hit")
	_shot_kill = false
	if float(settings.data.get("weapon_effects", 1)) <= 0.05: return
	var tracer := MeshInstance3D.new()
	var beam := CylinderMesh.new()
	beam.top_radius = 0.008
	beam.bottom_radius = 0.008
	beam.height = maxf(0.01, origin.distance_to(point))
	beam.radial_segments = 4
	tracer.mesh = beam
	tracer.material_override = _fx_material(Color("c2b394"))
	add_child(tracer)
	tracer.position = (origin + point) * 0.5
	if origin.distance_squared_to(point) > 0.0001: tracer.quaternion = Quaternion(Vector3.UP, (point - origin).normalized())
	_track_effect(tracer, 0.05)

func on_dog_attack(_enemy: Node = null) -> void: audio.play("dog")
func on_player_damaged(amount: float, source_world: Vector3 = Vector3.INF, absorbed: bool = false) -> void:
	_last_damage = elapsed
	if is_instance_valid(coop) and coop.damage_feedback(amount, source_world, absorbed): return
	audio.play("shield" if absorbed else "hurt")
	ui.show_damage(amount, _damage_direction(source_world), absorbed)

func _damage_direction(source_world: Vector3) -> Vector2:
	if not source_world.is_finite() or not is_instance_valid(player): return Vector2.ZERO
	var offset := source_world - player.global_position
	offset.y = 0.0
	if offset.length_squared() < 0.0001: return Vector2.ZERO
	var basis: Basis = player.camera.global_basis
	# Camera local -Z is ahead: threats in front draw above the reticle,
	# threats behind draw below it, including when the view is turned.
	return Vector2(offset.dot(basis.x), offset.dot(basis.z)).normalized()

func on_player_died() -> void:
	if is_instance_valid(coop) and coop.is_host():
		coop.on_died()
		return
	if companion.try_revive():
		ui.announce("FARO TE LEVANTOU", "Fique perto. Vocês ainda têm uma chance.")
		return
	running = false
	paused = true
	_save_pending = false
	_menu_kind = "dead"
	Engine.time_scale = 1
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = simulation_paused()
	if not is_instance_valid(coop) or not coop.is_online() or coop.current_peer_id == 1: _profile_store.save_slot(1, profile)
	ui.show_game_over(round_number, coins)

func add_coins(amount: int, _source: String = "") -> void:
	if amount <= 0: return
	if is_instance_valid(coop) and _source in ["round", "event", "challenge"]: coop.reward_others(amount, _source)
	coins += amount
	stats["earned"] = int(stats.get("earned", 0)) + amount
	_coins_gain = _coins_gain + amount if _gain_time > 0 else amount
	_gain_time = 1.2

func spend(amount: int) -> bool:
	if amount < 0 or coins < amount:
		notify("Petiscos insuficientes")
		return false
	coins -= amount
	return true

func get_player_modifiers() -> Dictionary:
	var result: Dictionary = progression.modifiers()
	var bonuses: Dictionary = Equipment.MODULES[inventory.module_id].bonuses
	for key: String in bonuses:
		if key == "critical_chance": result["crit_chance"] = float(result.get("crit_chance", 0)) + float(bonuses[key])
		elif key == "reload_time": result["reload"] = float(result.get("reload", 1)) / float(bonuses[key])
		else: result[key] = float(result.get(key, 1)) * float(bonuses[key])
	if active_powerups.has("double_damage"): result["damage"] *= 2
	if active_powerups.has("frenzy"):
		result["move_speed"] *= 1.22
		result["fire_rate"] = 1.4
	result["infinite_ammo"] = active_powerups.has("infinite_ammo")
	result["overcharge"] = "shock" if active_powerups.has("overcharge") else ""
	return result

func loot_quality() -> float:
	return float(Data.DIFFICULTIES[difficulty_id]["reward"]) * (1.4 if chaos_active else 1) * float(progression.modifiers()["loot_luck"]) * float(director.get_modifiers().get("loot", 1))

func activate_powerup(id: String) -> void:
	if not Exploration.POWERUP_NAMES.has(id): return
	if id == "nuke":
		for enemy: Node in enemies.duplicate():
			if is_instance_valid(enemy): enemy.take_damage(220.0 + round_number * 12.0, "body", "powerup")
	elif id == "jackpot": add_coins(250 + round_number * 30, "powerup")
	else: active_powerups[id] = 24.0
	ui.announce(str(Exploration.POWERUP_NAMES[id]), "POWER-UP · 24s" if id not in ["nuke","jackpot"] else "POWER-UP")
	audio.play("purchase")
	schedule_save()

func collect_nearby_drops(at: Vector3, radius: float) -> void: exploration.collect_nearby(at, radius)

func buy_weapon(model_id: String) -> void:
	if _coop_action("buy_weapon", [model_id]): return
	if not running or not Data.WEAPONS.has(model_id): return
	var model: Dictionary = Data.WEAPONS[model_id]
	if bool(model.get("legendary_only", false)):
		notify("Lendária exclusiva de loot e desafios")
		return
	if round_number < int(model["unlock_round"]):
		notify("Disponível no round %d" % int(model["unlock_round"]))
		return
	if inventory.items.size() >= inventory.capacity:
		notify("Mochila cheia")
		return
	var cost: int = maxi(80, int(model["price"])) + (round_number - 1) * 22
	if not spend(cost): return
	var item: Dictionary = Loot.make_weapon(model_id, round_number, "uncommon", rng.randi())
	if not inventory.add_item(item):
		coins += cost
		return
	inventory.equip(str(item["uid"]))
	player.sync_inventory()
	record_weapon(item)
	_purchase("Arma equipada")

func equip_item(uid: String) -> void:
	if _coop_action("equip_item", [uid]): return
	player._save_ammo()
	if not running or not inventory.equip(uid): return
	player.sync_inventory()
	_purchase("Equipado", false)

func choose_dog_element(id: String) -> void:
	if _coop_action("choose_dog_element", [id]): return
	if companion.choose_element(id): _purchase("Afinidade do Faro alterada", false)

func equip_to_slot(uid: String, slot: int) -> void:
	if _coop_action("equip_to_slot", [uid, slot]): return
	if not running: return
	player._save_ammo()
	if not inventory.assign_slot(uid, slot): return
	player.sync_inventory()
	_purchase("Arma no slot %d" % (slot + 1), false)

func buy_equipment(kind: String, id: String) -> void:
	if _coop_action("buy_equipment", [kind, id]): return
	if not running or kind not in ["grenade", "module"]: return
	var definitions: Dictionary = Equipment.GRENADES if kind == "grenade" else Equipment.MODULES
	if not definitions.has(id): return
	var owned: Array = inventory.owned_grenades if kind == "grenade" else inventory.owned_modules
	if not owned.has(id):
		if not spend(int(definitions[id].cost)): return
		owned.append(id)
	if kind == "grenade": inventory.grenade_id = id
	else: inventory.module_id = id
	_purchase("%s equipado" % definitions[id].name)

func buy_supply(id: String) -> void:
	if _coop_action("buy_supply", [id]): return
	if not running or not Equipment.SUPPLIES.has(id): return
	var config: Dictionary = Equipment.SUPPLIES[id]
	if int(inventory.supplies[id]) >= int(config.max): return
	if not spend(int(config.cost)): return
	inventory.supplies[id] += 1
	_purchase("+1 " + config.name)

func use_supply(id: String) -> bool:
	if _coop_action("use_supply", [id]): return true
	if not running or paused or player.health <= 0 or not Equipment.SUPPLIES.has(id): return false
	if int(inventory.supplies[id]) <= 0:
		notify("Sem cargas · reabasteça em I / UTILITÁRIOS")
		return false
	if id == "medkit":
		if player.health >= player.max_health: return false
		player.health = minf(player.max_health, player.health + player.max_health * 0.45)
	elif id == "ammo":
		var weapon: Dictionary = player.get_weapon_stats()
		if player.reserve >= int(weapon.max_reserve): return false
		player.add_ammo(int(weapon.magazine_size) * 2)
	else:
		if elapsed < _grenade_ready_at: return false
		_grenade_ready_at = elapsed + 1.4
		var grenade := Grenade.new()
		grenade.game = self
		if is_instance_valid(coop): grenade.owner_peer_id = coop.current_peer_id
		grenade.config = Equipment.GRENADES[inventory.grenade_id]
		grenade.velocity = -player.camera.global_basis.z * 15 + Vector3.UP * 3
		add_child(grenade)
		grenade.global_position = player.camera.global_position - player.camera.global_basis.z * 0.25
	inventory.supplies[id] -= 1
	audio.play("purchase" if id != "grenade" else "reload")
	notify(Equipment.SUPPLIES[id].name + " · " + str(inventory.supplies[id]) + " restantes")
	schedule_save()
	return true

func open_weapon_wheel() -> void:
	if not is_instance_valid(weapon_wheel):
		weapon_wheel = WeaponWheel.new()
		ui.root.add_child(weapon_wheel)
	player._save_ammo()
	paused = true
	_menu_kind = "wheel"
	ui.hud.hide()
	ui.notice_time = 0
	ui.labels.notice.text = ""
	get_tree().paused = simulation_paused()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	weapon_wheel.open(self)

func close_weapon_wheel(commit: bool) -> void:
	if not is_instance_valid(weapon_wheel): return
	if commit and _coop_action("select_slot", [weapon_wheel.selected]):
		weapon_wheel.hide()
		resume_game()
		return
	if commit and inventory.select_slot(weapon_wheel.selected):
		player.sync_inventory()
		schedule_save()
	weapon_wheel.hide()
	resume_game()
func auto_equip() -> void:
	if _coop_action("auto_equip", []): return
	if inventory.auto_equip():
		player.sync_inventory()
		_purchase("Melhor DPS sustentado equipado", false)
func set_item_flag(uid: String, flag: String) -> void:
	if _coop_action("set_item_flag", [uid, flag]): return
	var item: Dictionary = inventory.find_item(uid)
	if not item.is_empty() and inventory.set_flag(uid, flag, not bool(item.get(flag, false))): _purchase("Marcado", false)
func discard_item(uid: String) -> void:
	if _coop_action("discard_item", [uid]): return
	var item: Dictionary = inventory.find_item(uid)
	if item.is_empty(): return
	if not exploration.can_accept_drop("weapon", item):
		notify("O chão está cheio · venda ou desmonte equipamentos para abrir espaço")
		return
	var removed: Dictionary = inventory.remove(uid, "discard")
	if removed.is_empty():
		notify("Desequipe ou remova o favorito antes de descartar")
		return
	var dropped: Node3D = exploration.drop_item("weapon", removed, player.global_position + Vector3(0.8, 0, 0))
	if not is_instance_valid(dropped):
		inventory.add_item(removed)
		notify("Não foi possível descartar · equipamento mantido na mochila")
		return
	_purchase("Item no chão", false)
func sell_item(uid: String) -> void:
	if _coop_action("sell_item", [uid]): return
	var item: Dictionary = inventory.find_item(uid)
	if item.is_empty(): return
	var value := int(inventory.stats(item).get("value", 0))
	if inventory.remove(uid, "sell").is_empty():
		notify("Favoritos e arma equipada estão protegidos")
		return
	add_coins(value, "sale")
	_purchase("+%d petiscos" % value, false)
func salvage_item(uid: String) -> void:
	if _coop_action("salvage_item", [uid]): return
	if inventory.remove(uid, "dismantle").is_empty():
		notify("Favoritos e arma equipada estão protegidos")
		return
	_purchase("Materiais recuperados", false)
func install_attachment(uid: String, attachment_uid: String) -> void:
	if _coop_action("install_attachment", [uid, attachment_uid]): return
	if inventory.install(uid, attachment_uid):
		player.sync_inventory()
		_purchase("Peça instalada", false)
		audio.play("attachment")
func uninstall_attachment(uid: String, slot: String) -> void:
	if _coop_action("uninstall_attachment", [uid, slot]): return
	if inventory.uninstall(uid, slot):
		player.sync_inventory()
		_purchase("Peça guardada", false)
func buy_attachment(id: String) -> void:
	if _coop_action("buy_attachment", [id]): return
	if not Loot.ATTACHMENTS.has(id): return
	var config: Dictionary = Loot.ATTACHMENTS[id]
	var cost: int = int(config.get("cost", 150))
	if not spend(cost): return
	var attachment := {"uid":"part_%s_%s" % [str(run_seed),str(rng.randi())],"id":id,"slot":config["slot"],"rarity":"common","roll":1.0}
	if not inventory.add_attachment(attachment):
		coins += cost
		return
	_purchase("Peça na mochila")
func upgrade_weapon(uid: String = "") -> void:
	if _coop_action("upgrade_weapon", [uid]): return
	if uid.is_empty(): uid = inventory.equipped_id
	var item: Dictionary = inventory.find_item(uid)
	if item.is_empty(): return
	var cost := Data.upgrade_cost(int(item.get("upgrade_level", 0)))
	var material_discount: int = mini(inventory.materials, floori(cost / 4.0))
	if not spend(cost - material_discount): return
	inventory.materials -= material_discount
	item["upgrade_level"] = int(item.get("upgrade_level", 0)) + 1
	player.sync_inventory()
	_purchase("Refinamento %d · sem limite de níveis" % int(item["upgrade_level"]))
func reroll_weapon(uid: String, kind: String) -> void:
	if _coop_action("reroll_weapon", [uid, kind]): return
	var cost: int = inventory.reroll_cost(uid, kind)
	if cost <= 0 or not spend(cost): return
	if not inventory.reroll(uid, kind, rng):
		coins += cost
		return
	player.sync_inventory()
	_purchase("Nova combinação")
func buy_perk(id: String) -> void:
	if _coop_action("buy_perk", [id]): return
	var cost: int = progression.cost(id)
	if cost <= 0 or not spend(cost): return
	progression.increment(id)
	var previous: float = player.max_health
	player.max_health = 100.0 * float(progression.modifiers()["max_health"])
	player.heal(player.max_health - previous)
	player.sync_inventory()
	_purchase(str(Progression.PERKS[id]["name"]) + " evoluiu")
func upgrade_dog(branch: String = "attack") -> void:
	if _coop_action("upgrade_dog", [branch]): return
	if companion.upgrade_branch(branch): _purchase("Faro evoluiu", false)
func select_dog(id: String) -> void:
	if _coop_action("select_dog", [id]): return
	if companion.switch_archetype(id): _purchase("Companhia pronta", false)
func refill_ammo() -> void:
	if _coop_action("refill_ammo", []): return
	if player.refill(): _purchase("Munição pronta", false)
func _purchase(message: String, counted: bool = true) -> void:
	if counted: stats["purchases"] = int(stats.get("purchases", 0)) + 1
	notify(message)
	audio.play("purchase")
	ui.refresh_progression()
	_update_hud()
	schedule_save()

func get_progression_data() -> Dictionary:
	var stock: Array = []
	for id: String in Data.WEAPONS:
		if bool(Data.WEAPONS[id].get("legendary_only", false)): continue
		var row: Dictionary = Data.WEAPONS[id].duplicate()
		row["model_id"] = id
		row["price"] = maxi(80, int(row["price"])) + (round_number - 1) * 22
		row["cost"] = row["price"]
		row["locked"] = round_number < int(row["unlock_round"])
		row["level"] = round_number
		stock.append(row)
	var parts: Array = []
	for id: String in Loot.ATTACHMENTS:
		var part: Dictionary = Loot.ATTACHMENTS[id].duplicate()
		part["id"] = id
		parts.append(part)
	return {"coins":coins,"materials":inventory.materials,"perks":progression.describe(),"dog":companion.get_progression(),"stock_weapons":stock,"stock_attachments":parts,"current_region":world.district(player.global_position)}
func get_shop_data() -> Dictionary:
	var state: Dictionary = get_progression_data()
	state["weapons"] = state["stock_weapons"]
	state["ammo_cost"] = player.get_refill_cost()
	state["upgrade_cost"] = Data.upgrade_cost(int(inventory.equipped().get("upgrade_level", 0)))
	return state
func record_weapon(item: Dictionary) -> void:
	var id: String = str(item.get("model_id", ""))
	if not profile["weapons"].has(id): profile["weapons"].append(id)
	if Loot.rarity_rank(str(item.get("rarity", "common"))) >= 4: award_profile("first_legendary", 1)
func award_profile(id: String, amount: int) -> void:
	var token := "%s_%s" % [str(run_seed),id]
	if profile["awarded"].has(token): return
	profile["awarded"].append(token)
	while profile["awarded"].size() > 2048: profile["awarded"].pop_front()
	profile["sigils"] = int(profile.get("sigils", 0)) + amount
	if not profile["achievements"].has(id): profile["achievements"].append(id)
	if not is_instance_valid(coop) or not coop.is_online() or coop.current_peer_id == 1: _profile_store.save_slot(1, profile)
func unlock_meta(id: String) -> void:
	var costs := {"collector":3,"support":5,"guardian":7}
	if not costs.has(id) or profile["unlocks"].has(id) or int(profile["sigils"]) < int(costs[id]): return
	profile["sigils"] = int(profile["sigils"]) - int(costs[id])
	profile["unlocks"].append(id)
	if not is_instance_valid(coop) or not coop.is_online() or coop.current_peer_id == 1: _profile_store.save_slot(1, profile)
	notify("Especialização de companheiro desbloqueada")
func get_extras() -> Dictionary:
	var result: Dictionary = profile.duplicate(true)
	result["stats"] = stats.duplicate(true)
	result["credits"] = "Meyui Beuyi · mundo, áudio e modelos originais procedurais. Godot Engine · MIT."
	return result

func pause_game() -> void:
	if not running: return
	paused = true
	_menu_kind = "pause"
	Engine.time_scale = 1
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = simulation_paused()
	ui.show_pause()
func open_inventory(tab: String = "inventory") -> void:
	if not running: return
	if is_instance_valid(coop) and coop.open_remote_inventory(tab): return
	paused = true
	_menu_kind = "inventory"
	Engine.time_scale = 1
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = simulation_paused()
	ui.show_inventory(tab)
func open_shop() -> void: open_inventory("forge")
func resume_game() -> void:
	if not running: return
	player.show()
	paused = false
	_menu_kind = ""
	ui.hide_menus()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	audio.set_active(true)
	if _save_pending: save_game()
func return_to_menu() -> bool:
	if is_instance_valid(coop) and coop.is_client():
		coop.stop("Você saiu. Seu progresso ficou salvo no host.")
		return true
	if running and not save_game():
		pause_game()
		return false
	if is_instance_valid(coop) and coop.is_host(): coop.stop("Host encerrou a sessão")
	running = false
	paused = true
	get_tree().paused = false
	_menu_kind = "main"
	_menu_camera.make_current()
	player.hide()
	audio.set_context(false, "")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.show_menu()
	return true
func restart_run() -> void:
	if return_to_menu(): ui.show_new_game()
func quit_game() -> void:
	if _quitting: return
	_quitting = true
	if running and not save_game():
		pause_game()
		notify("Não foi possível salvar. Tente outro slot antes de sair.")
		_quitting = false
		return
	settings.save_settings()
	running = false
	paused = true
	get_tree().paused = false
	await audio.shutdown()
	get_tree().quit()
func notify(message: String) -> void:
	if is_instance_valid(coop) and coop.notice(message): return
	if is_instance_valid(ui): ui.show_notice(message)
func ui_feedback(cue: String = "ui_click") -> void:
	if is_instance_valid(audio): audio.play(cue)
func apply_settings(values: Dictionary) -> void:
	# The menu is a live view of the world, so its FOV must preview the same
	# preference as the player camera, including while gameplay is paused.
	if is_instance_valid(_menu_camera):
		_menu_camera.fov = clampf(float(values.get("fov", 76.0)), 60.0, 110.0)
func update_setting(key: String, value: Variant) -> void:
	if settings.set_value(key, value):
		settings.apply(get_tree(), self)
		if not settings.save_settings(): notify(settings.last_error)
		_update_hud()
func apply_graphics_preset(id: String) -> void:
	if settings.apply_preset(id):
		settings.apply(get_tree(), self)
		if not settings.save_settings(): notify(settings.last_error)
func schedule_save() -> void:
	if is_instance_valid(coop) and coop.is_client(): return
	if _restoring or not running: return
	if not _save_pending: _save_delay = 0.7
	_save_pending = true

func snapshot_state() -> Dictionary:
	var player_state: Dictionary = player.snapshot()
	var living: Array = []
	for enemy: Node in enemies:
		if is_instance_valid(enemy) and not enemy.dead:
			var state: Dictionary = enemy.export_state()
			state["wave_enemy"] = bool(enemy.get_meta("wave_enemy", true))
			state["boss_zone_id"] = str(enemy.get_meta("boss_zone_id", ""))
			living.append(state)
	return {"round_number":round_number,"coins":coins,"elapsed":elapsed,"kills":kills,"difficulty":difficulty_id,"chaos":chaos_active,"run_seed":str(run_seed),"rng_state":str(rng.state),"inventory":inventory.export_state(),"player":player_state,"perks":progression.export_state(),"dog":companion.export_state(),"world":world.export_state(),"director":director.export_state(),"exploration":exploration.export_state(),"enemies":living,"stats":stats.duplicate(true),"powerups":active_powerups.duplicate(true),"boss_zone":boss_zone.duplicate(true),"coop":coop.export_state() if is_instance_valid(coop) else {}}
func save_game(slot: int = -1) -> bool:
	if is_instance_valid(coop) and coop.is_client():
		notify("O host salva sua progressão automaticamente")
		return true
	if not running or player.health <= 0: return false
	if slot < 1: slot = active_slot
	if slot < 1 or slot > 3: return false
	var weapon: Dictionary = inventory.stats()
	var metadata := {"round":round_number,"time":elapsed,"region":world.district(player.global_position),"weapon_name":weapon.get("name", ""),"weapon_model":player.weapon_id,"weapon_rarity":weapon.get("rarity", "common"),"dog_type":companion.archetype,"dog_level":companion.level}
	var result: Dictionary = save_manager.save_slot(slot, snapshot_state(), metadata)
	if not bool(result.get("ok", false)):
		notify("Save indisponível: " + str(result.get("error", "falha de escrita")))
		_save_pending = false
		return false
	active_slot = slot
	_save_pending = false
	_saved_time = 1.8
	if not is_instance_valid(coop) or not coop.is_online() or coop.current_peer_id == 1: _profile_store.save_slot(1, profile)
	return true
func get_save_slots() -> Array: return save_manager.list_slots()
func continue_game() -> void:
	var slot: int = save_manager.latest_slot()
	if slot > 0: load_game(slot)
func load_game(slot: int) -> void:
	if is_instance_valid(coop) and coop.is_online(): coop.stop()
	var result: Dictionary = save_manager.load_slot(slot)
	if not bool(result.get("ok", false)):
		notify(str(result.get("error", "Save indisponível")))
		return
	if apply_snapshot(result.get("state", {})):
		active_slot = slot
		resume_game()
		ui.announce("DE VOLTA À NOITE", "Round %d · %s" % [round_number, world.district(player.global_position)])
		if bool(result.get("recovered", false)): notify("Save recuperado do backup")
	else: notify("Save incompatível com os dados desta versão")
func apply_snapshot(state: Dictionary) -> bool:
	if not _valid_snapshot(state): return false
	var candidate_inventory = Inventory.new()
	var candidate_director = Director.new()
	if not candidate_inventory.import_state(state.get("inventory", {})): return false
	if not candidate_director.import_state(state.get("director", {})): return false
	if not state.get("player", {}) is Dictionary or not state.get("enemies", []) is Array: return false
	_restoring = true
	_clear_run()
	inventory = candidate_inventory
	director = candidate_director
	progression = Progression.new()
	progression.import_state(state.get("perks", {}))
	difficulty_id = str(state.get("difficulty", "normal"))
	if not Data.DIFFICULTIES.has(difficulty_id): difficulty_id = "normal"
	chaos_active = bool(state.get("chaos", false))
	run_seed = int(state.get("run_seed", 1))
	rng.seed = run_seed
	rng.state = int(state.get("rng_state", str(rng.state)))
	coins = maxi(0, int(state.get("coins", 250)))
	elapsed = maxf(0, float(state.get("elapsed", 0)))
	kills = maxi(0, int(state.get("kills", 0)))
	stats = state.get("stats", {}).duplicate(true)
	world.import_state(state.get("world", {}))
	_create_actors()
	player.restore(state.get("player", {}))
	companion.import_state(state.get("dog", {}))
	active_powerups = state.get("powerups", {}).duplicate(true)
	boss_zone = state.get("boss_zone", {}).duplicate(true)
	world.set_boss_arena(not boss_zone.is_empty())
	_sync_director()
	for entry: Dictionary in state.get("enemies", []):
		var enemy := _spawn_enemy_data({"kind":entry.get("kind", "grunt"),"wave_enemy":entry.get("wave_enemy", true)})
		enemy.import_state(entry)
		enemy.set_meta("boss_zone_id", str(entry.get("boss_zone_id", "")))
	exploration.import_state(state.get("exploration", {}))
	if is_instance_valid(coop): coop.import_state(state.get("coop", {}))
	world.set_event(str(director.active_event.get("id", "")))
	player.camera.make_current()
	running = true
	paused = true
	_restoring = false
	settings.apply(get_tree(), self)
	return true

func _valid_snapshot(state: Dictionary) -> bool:
	if not SnapshotValidator.valid(state): return false
	if state.has("coop"):
		var network: Variant = state.coop
		if not network is Dictionary or not network.get("players", {}) is Dictionary or network.get("players", {}).size() > 64: return false
		var multiplier: Variant = network.get("enemy_multiplier", 1.0)
		if not (multiplier is float or multiplier is int) or not is_finite(float(multiplier)) or float(multiplier) < 1 or float(multiplier) > 3.40001: return false
		for token: Variant in network.get("players", {}):
			if not token is String or str(token).length() != 64 or not str(token).is_valid_hex_number(false): return false
			var personal: Variant = network.players[token]
			if not personal is Dictionary: return false
			for key: String in ["inventory", "perks", "player", "dog", "stats", "profile", "powerups"]:
				if not personal.get(key) is Dictionary: return false
			var health: Variant = personal.player.get("health")
			if not (health is float or health is int) or not is_finite(float(health)) or float(health) < 0: return false
			var candidate: Dictionary = state.duplicate(true)
			candidate.erase("coop")
			for key: String in ["inventory", "perks", "player", "dog", "stats", "powerups", "coins"]: candidate[key] = personal.get(key)
			candidate.player = candidate.player.duplicate(true)
			# A disconnected guest may be downed; validate the remaining snapshot normally.
			candidate.player.health = maxf(1.0, float(health))
			if not SnapshotValidator.valid(candidate): return false
	for key: String in ["inventory","director","player","perks","dog","world","exploration","stats","powerups","boss_zone"]:
		if not state.get(key) is Dictionary: return false
	if not Data.DIFFICULTIES.has(str(state.get("difficulty", ""))): return false
	if not _saved_position(state["player"].get("position")): return false
	if float(state["player"].get("health", 0)) <= 0: return false
	if not state.get("enemies") is Array or state["enemies"].size() > 24: return false
	var wave_actors := 0
	for entry: Variant in state["enemies"]:
		if not entry is Dictionary or not _saved_position(entry.get("position")): return false
		if float(entry.get("health", 0)) <= 0: return false
		if bool(entry.get("wave_enemy", true)): wave_actors += 1
	if wave_actors != int(state["director"].get("spawned", 0)) - int(state["director"].get("killed", 0)): return false
	if not state["exploration"].get("drops", []) is Array: return false
	var inspector = Inventory.new()
	inspector.capacity = 128
	for drop: Variant in state["exploration"].get("drops", []):
		if not drop is Dictionary or not _saved_position(drop.get("position")): return false
		if not drop.get("payload") is Dictionary: return false
		if str(drop.get("kind", "")) == "weapon" and not inspector.add_item(drop["payload"]): return false
	for id: String in state["powerups"]:
		if not Exploration.POWERUP_NAMES.has(id): return false
		if not (state["powerups"][id] is float or state["powerups"][id] is int): return false
		if not is_finite(float(state["powerups"][id])) or float(state["powerups"][id]) < 0: return false
	return true

func _saved_position(value: Variant) -> bool:
	if not value is Array or value.size() != 3: return false
	for component: Variant in value:
		if not (component is float or component is int): return false
		if not is_finite(float(component)) or absf(float(component)) > 10000: return false
	return true

func _update_hud() -> void:
	if not is_instance_valid(player) or not is_instance_valid(companion): return
	var weapon: Dictionary = player.get_weapon_stats()
	var progress: float = 1.0 - player.reload_remaining / maxf(0.01, player.reload_duration) if player.reloading else 0
	var context: Dictionary = exploration.get_context() if is_instance_valid(exploration) else {}
	var boss: Node = null
	for enemy: Node in enemies:
		if is_instance_valid(enemy) and str(enemy.kind).begins_with("boss"):
			boss = enemy
			break
	var boss_name: String = str(EnemyData.BOSSES.get(boss.boss_id, EnemyData.BOSSES["captain"])["name"]) if is_instance_valid(boss) else ""
	var objective := "Explore o Mercado · E interagir · L lanterna" if round_number == 1 and world.get_region_id(player.global_position) in ["patio", "mercado"] and not exploration.discovered.has("mercado") else ""
	if not exploration.challenge.is_empty(): objective = "%s · %d/%d · %ds" % [exploration.challenge["name"],exploration.challenge["kills"],exploration.challenge["target"],ceili(exploration.challenge["remaining"])]
	ui.update_hud({
		"supplies":inventory.supplies,
		"round":round_number,"remaining":maxi(0, wave_total - wave_killed),"phase":phase,
		"coins":coins,"coins_gain":_coins_gain if _gain_time > 0 else 0,
		"health":player.health,"max_health":player.max_health,
		"weapon_name":weapon.get("name", ""),"rarity":weapon.get("rarity", "common"),
		"weapon_rarity":weapon.get("rarity_name", "Comum"),"build":_build_summary(),
		"magazine":player.magazine,"reserve":player.reserve,"reload_progress":progress,"reloading":player.reloading,
		"dog_health":companion.health,"dog_max_health":companion.max_health,
		"dog_level":companion.level,"dog_status":companion.get_status(),
		"district":world.district(player.global_position),"difficulty":difficulty_id,"chaos":chaos_active,
		"seconds":ceili(phase_time),"saved":_saved_time > 0,
		"event_name":director.active_event.get("name", ""),"event_remaining":director.active_event.get("remaining", 0),
		"boss_name":boss_name,"boss_health":boss.health if is_instance_valid(boss) else 0,
		"boss_phase":boss.boss_phase if is_instance_valid(boss) else 1,
		"boss_max_health":boss.max_health if is_instance_valid(boss) else 1,
		"objective":objective,"interaction":context,"loot_compare":context.get("comparison", {}),
		"powerups":active_powerups.duplicate()
	})

func _build_summary() -> String:
	var branches: Array = progression.levels.keys()
	branches.sort_custom(func(a: String, b: String) -> bool: return int(progression.levels[a]) > int(progression.levels[b]))
	var names: PackedStringArray = []
	for id: String in branches:
		if int(progression.levels[id]) > 0:
			names.append("%s %d" % [Progression.PERKS[id]["name"], int(progression.levels[id])])
		if names.size() == 3: break
	return " · ".join(names) if not names.is_empty() else "Escolha seus talentos para começar uma build."

func _fx_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material
func _float_text(value: String, at: Vector3, tint: Color) -> void:
	if _effects.size() > 50: return
	var label := Label3D.new()
	label.text = value
	label.modulate = tint
	label.font_size = 34
	label.outline_size = 6
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
	label.position = at + Vector3(rng.randf_range(-0.22, 0.22), rng.randf_range(0, 0.16), 0)
	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + 0.6, 0.65)
	tween.tween_property(label, "modulate:a", 0.0, 0.4).set_delay(0.25)
	_track_effect(label, 0.7)
func _track_effect(effect: Node3D, lifetime: float) -> void:
	effect.process_mode = Node.PROCESS_MODE_PAUSABLE
	_effects.append(effect)
	while _effects.size() > 64:
		var oldest: Node3D = _effects.pop_front()
		if is_instance_valid(oldest): oldest.queue_free()
	get_tree().create_timer(lifetime, false).timeout.connect(func() -> void:
		if is_instance_valid(effect):
			_effects.erase(effect)
			effect.queue_free())

func simulation_paused() -> bool:
	return paused and not (is_instance_valid(coop) and coop.is_online())

func _coop_action(action: String, args: Array = []) -> bool:
	return is_instance_valid(coop) and coop.request_action(action, args)

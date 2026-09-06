extends SceneTree
## Full-scene endurance QA. Native physics, navigation, actor AI, combat, economy,
## drops, effects and timers remain active; only the test pilot is automated.
## Run: Godot --headless --path godot --script res://tests/test_stress.gd
const MainScene = preload("res://scenes/main.tscn")
const Saves = preload("res://scripts/save_manager.gd")
const Settings = preload("res://scripts/game_settings.gd")
const Loot = preload("res://data/loot_data.gd")
const TIME_SCALE: float = 6.0
const PHYSICS_HZ: int = 180
const COMBAT_SECONDS: float = 180.0
var _game: Node3D
var _directory: String
var _checks: int = 0
var _failures: Array[String] = []
var _finished: bool = false
var _start_ms: int = 0
var _initial_orphans: int = 0
var _baseline_nodes: int = 0
var _peak_nodes: int = 0
var _peak_alive: int = 0
var _peak_effects: int = 0
var _peak_drops: int = 0
var _peak_projectiles: int = 0
var _simulated: float = 0.0
var _samples: int = 0
var _bot_target: Node3D
var _route: PackedVector3Array = PackedVector3Array()
var _waypoint: int = 0
var _goal_index: int = 0
var _visited: Dictionary = {}
var _dog_bit: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_start_ms = Time.get_ticks_msec()
	seed(385019)
	_initial_orphans = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_directory = "user://stress_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_game = MainScene.instantiate()
	_game.save_manager = Saves.new(_directory + "/saves")
	_game._profile_store = Saves.new(_directory + "/profile")
	_game.settings = Settings.new(_directory + "/settings")
	_game.settings.set_value("fps_limit", 0)
	_game.settings.set_value("master", 0.0)
	_game.settings.set_value("reduced_flashes", true)
	_game.settings.save_settings()
	root.add_child(_game)
	current_scene = _game
	for frame: int in range(600):
		if _game.world.navigation_ready:
			break
		await process_frame
	_check(_game.world.navigation_ready, "Native world navigation is ready before endurance simulation")
	if not _game.world.navigation_ready:
		await _finish()
		return
	var navigation_mesh: NavigationMesh = _game.world.navigation_region.navigation_mesh
	print("STRESS native map radius=%.2f height=%.2f" % [navigation_mesh.agent_radius, navigation_mesh.agent_height])
	_game.start_run("hard", true, 1)
	_game.rng.seed = 455821
	for region: Dictionary in _game.world.regions:
		_game.world.unlock_region(str(region.id))
	await physics_frame
	await physics_frame
	_baseline_nodes = _node_count(_game)
	Engine.physics_ticks_per_second = PHYSICS_HZ
	Engine.max_physics_steps_per_frame = 16
	Engine.time_scale = TIME_SCALE
	await _test_live_level_navigation()
	if OS.get_cmdline_user_args().has("--navigation-only"):
		await _test_cleanup()
		await _finish()
		return
	await _test_projectile_pressure()
	await _test_population_and_summons()
	await _test_endurance_combat()
	await _diagnose_survivor()
	await _test_drop_pressure()
	await _test_pause_and_death()
	await _test_cleanup()
	await _finish()


func _test_live_level_navigation() -> void:
	_game.director.phase = "prepare"
	_game.director.phase_time = 10000.0
	_game.companion.follow_only = true
	var flights: Array = [
		[Vector3(10, 0, 14), Vector3(10, 4, -2)],
		[Vector3(11, 4, -17), Vector3(11, 8, -33)],
		[Vector3(-24, 0, -15), Vector3(-24, -4, -31)],
		[Vector3(32, 4, -18), Vector3(32, 0, -34)],
		# Both actors need room to arrive: a melee grunt at the exact edge would
		# physically block the following dog while legitimately attacking there.
		[Vector3(29.8, 0, -36), Vector3(13, 8, -36)],
		[Vector3(-10, -4, -40), Vector3(2, 0, -40)],
		[Vector3(2, 0, -40), Vector3(2, 4, -53)],
		[Vector3(-5, 4, -53), Vector3(-5, 8, -43)]
	]
	for index: int in range(flights.size()):
		var begin: Vector3 = flights[index][0]
		var end: Vector3 = flights[index][1]
		_game.player.position = end + Vector3.UP * 0.12
		_game.player.velocity = Vector3.ZERO
		_game.companion.position = begin + Vector3(0.55, 0.12, 0)
		_game.companion.velocity = Vector3.ZERO
		_game.companion._path_timer = 0.0
		var enemy: Node3D = _game._spawn_enemy_data({"kind": "grunt", "position": begin + Vector3(-0.55, 0.12, 0), "wave_enemy": false})
		await _simulate(18.0, false)
		_check(enemy.global_position.distance_to(_game.player.global_position) < 3.0, "Enemy physically follows native route %d across a height change: %s" % [index, enemy.global_position])
		_check(absf(enemy.global_position.y - end.y) < 0.8, "Enemy reaches the correct floor on route %d" % index)
		if enemy.global_position.distance_to(_game.player.global_position) >= 3.0:
			_print_actor_diagnostic(enemy)
		_check(_game.companion.global_position.distance_to(_game.player.global_position) < 3.5, "Companion physically follows route %d: %s" % [index, _game.companion.global_position])
		_check(absf(_game.companion.global_position.y - end.y) < 0.8, "Companion reaches the correct floor on route %d: dog=%s player=%s" % [index, _game.companion.global_position, _game.player.global_position])
		if _game.companion.global_position.distance_to(_game.player.global_position) >= 3.5 or absf(_game.companion.global_position.y - end.y) >= 0.8:
			_print_companion_diagnostic()
			_print_actor_diagnostic(enemy)
		enemy.take_damage(1000000.0, "body", "self")
		await _simulate(1.0, false)
	print("STRESS navigation routes=%d simulated=%.1f" % [flights.size(), _simulated])


func _test_projectile_pressure() -> void:
	_game.player.position = _game.world.spawn_position
	_game.player.velocity = Vector3.ZERO
	_game.companion.position = _game.player.position + Vector3(2, 0, 0)
	var enemy: Node3D = _game._spawn_enemy_data({"kind": "spitter", "position": _game.player.position + Vector3(0, 0.1, -7), "wave_enemy": false})
	for index: int in range(40):
		enemy._launch_projectile(Vector3.BACK, 7.0, Color("92bd83"))
	_peak_projectiles = maxi(_peak_projectiles, enemy._projectiles.size())
	_check(enemy._projectiles.size() == 3, "Forty launch requests create only three real native projectile nodes")
	var shots: Array = enemy._projectiles.duplicate()
	var initial: Vector3 = shots[0].node.global_position
	await _simulate(0.2, false)
	_check(not is_instance_valid(shots[0].node) or shots[0].node.global_position.distance_to(initial) > 0.2, "Native projectiles physically advance through the real world")
	enemy._special_cooldown = 1000.0
	await _simulate(4.0, false)
	_check(enemy._projectiles.is_empty(), "All launched projectiles retire after collision or their bounded lifetime")
	for shot: Dictionary in shots:
		_check(not is_instance_valid(shot.node), "Retired projectile meshes are freed")
	enemy.take_damage(1000000.0, "body", "self")
	await _simulate(1.0, false)


func _test_population_and_summons() -> void:
	_game._clear_run()
	Engine.time_scale = TIME_SCALE
	_game.exploration.import_state({})
	_game.director.start("hard", 1, 783511)
	_game.director.round_number = 25
	_game.director.phase = "combat"
	_game.director.wave_total = 48
	_game.director.spawned = 1
	_game.director._last_alive = 1
	_game.director._spawn_clock = 0.0
	_game.player.position = _game.world.spawn_position
	_game.player.velocity = Vector3.ZERO
	_game.companion.position = _game.player.position + Vector3(2, 0, 0)
	_game._sync_director()
	var summoner: Node3D = _game._spawn_enemy_data({"kind": "summoner", "position": _game.player.position + Vector3(0, 0.1, -9), "wave_enemy": true})
	var before_total: int = _game.director.wave_total
	summoner._summon_adds(30, "grunt")
	_check(_game.director._summons == 4 and _game.enemies.size() == 5, "A summoner asking for 30 adds receives only four wave summons")
	_check(_game.director.wave_total == before_total + 4 and _game.director.spawned == 5, "Summoned actors reserve real, bounded wave slots")
	for index: int in range(30):
		_game.spawn_add("parasite", _game.player.position + Vector3(3, 0.1, -8))
	_check(_game.enemies.size() == 5 and _game.director._summons == 4, "Repeated external summon requests cannot exceed the per-wave allowance")
	await _simulate(30.0, false)
	_check(_peak_alive == 24, "An unattended late wave reaches the intended 24-actor pressure cap")
	_check(_game.enemies.size() <= 24 and _game.director.spawned <= _game.director.wave_total, "Sustained spawning never exceeds live population or wave reservations")
	print("STRESS population alive=%d peak=%d summons=%d" % [_game.enemies.size(), _peak_alive, _game.director._summons])


func _test_endurance_combat() -> void:
	var item: Dictionary = Loot.make_weapon("sparrow", 35, "legendary", 374891)
	item["modifiers"] = ["shock", "death_blast", "double_shot"]
	item["attachments"] = {}
	_check(_game.inventory.add_item(item), "Stress pilot equips an actual rolled late-game weapon")
	_game.player.equip_weapon(str(item.uid))
	_game.active_powerups["infinite_ammo"] = COMBAT_SECONDS + 30.0
	_game.companion.follow_only = false
	_game.companion.levels["attack"] = 5
	_game.companion._recalculate_stats()
	Input.action_press("aim")
	var initial_round: int = _game.round_number
	var initial_kills: int = _game.kills
	var initial_shots: int = int(_game.stats.shots)
	var initial_coins: int = _game.coins
	var previous_section_kills: int = _game.kills
	_set_route(_game.world.regions[1].center)
	for section: int in range(6):
		await _simulate(COMBAT_SECONDS / 6.0, true)
		if not _game.running:
			break
		await _pause_probe()
		_goal_index = (section + 2) % _game.world.regions.size()
		_set_route(_game.world.regions[_goal_index].center)
		print("STRESS combat t=%.1f round=%d kills=%d alive=%d drops=%d effects=%d nodes=%d" % [_simulated, _game.round_number, _game.kills, _game.enemies.size(), _game.exploration.drops.size(), _game._effects.size(), _node_count(_game)])
		if _game.enemies.size() <= 3 or _game.kills == previous_section_kills:
			for enemy: Node3D in _game.enemies:
				_print_actor_diagnostic(enemy)
		previous_section_kills = _game.kills
	_release_controls()
	_check(_game.kills - initial_kills >= 30, "Live raycast combat kills at least thirty native actors during endurance")
	_check(int(_game.stats.shots) - initial_shots >= 150, "The real weapon, recoil, cooldown and effect paths process sustained fire")
	_check(_game.coins > initial_coins, "Stress combat produces real run economy rewards")
	_check(_game.round_number > initial_round, "Completing real waves advances at least one late-game round")
	_check(_visited.size() >= 2, "The moving pilot physically visits multiple native districts")
	_check(_dog_bit, "The real companion reaches a target and enters its bite attack")
	_check(_game.player._effect_nodes.size() == 12 and _peak_effects <= 64, "Long combat preserves fixed player and bounded coordinator effect pools")


func _diagnose_survivor() -> void:
	if _game.enemies.is_empty():
		return
	_release_controls()
	_game.companion.follow_only = true
	var survivors: Array[Dictionary] = []
	for enemy: Node3D in _game.enemies:
		survivors.append({"enemy": enemy, "start": enemy.global_position, "ranged_active": false})
	print("STRESS survivor probe begins count=%d player=%s" % [survivors.size(), _game.player.global_position])
	for sample: int in range(20):
		await _simulate(1.0, false)
		for entry: Dictionary in survivors:
			# An existing burn/chain effect can finish an actor while this probe
			# waits. Validate the Variant before assigning a freed object to Node3D.
			if not is_instance_valid(entry.enemy): continue
			var enemy: Node3D = entry.enemy
			if is_instance_valid(enemy) and not enemy.dead and enemy.kind in ["spitter", "screamer", "summoner", "boss"]:
				if enemy._special_time > 0.0 or not enemy._projectiles.is_empty():
					entry.ranged_active = true
	for entry: Dictionary in survivors:
		if not is_instance_valid(entry.enemy): continue
		var enemy: Node3D = entry.enemy
		if not is_instance_valid(enemy) or enemy.dead:
			continue
		var moved: float = enemy.global_position.distance_to(entry.start)
		var distance: float = enemy.global_position.distance_to(_game.player.global_position)
		var path: PackedVector3Array = NavigationServer3D.map_get_path(_game.get_world_3d().navigation_map, enemy.global_position, _game.player.global_position, true)
		var blocked: bool = moved < 0.25 and distance > 7.0 and path.size() > 1 and _game.boss_zone.is_empty() and not enemy.statuses.has("freeze") and not bool(entry.ranged_active)
		_check(not blocked, "Remaining enemy progresses toward a reachable distant stationary player over 20 seconds: moved=%.3f distance=%.2f kind=%s pos=%s" % [moved, distance, enemy.kind, enemy.global_position])
		if blocked:
			_print_actor_diagnostic(enemy)
		print("STRESS survivor kind=%s displacement=%.3f distance=%.3f native_route_points=%d ranged_active=%s" % [enemy.kind, moved, distance, path.size(), entry.ranged_active])


func _print_actor_diagnostic(enemy: Node3D) -> void:
	var agent: NavigationAgent3D = enemy._agent
	var path: PackedVector3Array = agent.get_current_navigation_path()
	var index: int = agent.get_current_navigation_path_index()
	var next: Vector3 = path[index] if index < path.size() else Vector3.ZERO
	print("STRESS ACTOR kind=%s hp=%.2f pos=%s vel=%s player=%s next=%s index=%d/%d reachable=%s finished=%s target=%s special=%s/%.3f freeze=%s bosszone=%s" % [enemy.kind, enemy.health, enemy.global_position, enemy.velocity, _game.player.global_position, next, index, path.size(), agent.is_target_reachable(), agent.is_navigation_finished(), agent.target_position, enemy._special, enemy._special_time, enemy.statuses.has("freeze"), _game.boss_zone])


func _print_companion_diagnostic() -> void:
	var companion: CharacterBody3D = _game.companion
	var agent: NavigationAgent3D = companion._agent
	var path: PackedVector3Array = agent.get_current_navigation_path()
	var index: int = agent.get_current_navigation_path_index()
	var next: Vector3 = path[index] if index < path.size() else Vector3.ZERO
	print("STRESS FARO pos=%s vel=%s player=%s next=%s index=%d/%d downed=%.3f bite=%.3f" % [companion.global_position, companion.velocity, _game.player.global_position, next, index, path.size(), companion._downed_time, companion._bite_time])
	for collision_index: int in range(companion.get_slide_collision_count()):
		var collision: KinematicCollision3D = companion.get_slide_collision(collision_index)
		print("STRESS FARO collision=%s normal=%s point=%s" % [collision.get_collider(), collision.get_normal(), collision.get_position()])


func _test_drop_pressure() -> void:
	_game.director.phase = "prepare"
	_game.director.phase_time = 10000.0
	var at: Vector3 = _game.world.spawn_position + Vector3(-18, 0, 8)
	for index: int in range(130):
		_game.exploration.drop_item("weapon", Loot.make_weapon("biscuit", 2, "common", 890000 + index), at + Vector3(index % 8, 0, index / 8))
	_check(_game.exploration.drops.size() == 96, "Weapon drop pressure fills but cannot exceed the 96-drop cap")
	for index: int in range(80):
		_game.exploration.drop_item("ammo", {"amount": 5}, at)
	_check(_game.exploration.drops.size() <= 96, "Ammo pressure cannot evict protected equipment or exceed drop capacity")
	await _simulate(1.0, false)
	var actual_drops: int = _game.exploration.get_child_count()
	_check(actual_drops <= 96, "Deferred cleanup also keeps actual loot nodes within the cap")
	_game.exploration.import_state({})
	for index: int in range(140):
		_game.exploration.drop_item("ammo", {"amount": 5}, at)
	_check(_game.exploration.drops.size() == 96, "Disposable ammo replaces old ammo while retaining the cap")
	await _simulate(1.0, false)
	_check(_game.exploration.get_child_count() <= 96, "Replaced ammo nodes are actually freed after the frame")


func _pause_probe() -> void:
	_release_controls()
	_game.pause_game()
	var elapsed: float = _game.elapsed
	var event_time: float = float(_game.director.active_event.get("remaining", 0.0))
	var enemy: Node3D = _game.enemies[0] if not _game.enemies.is_empty() else null
	var enemy_position: Vector3 = enemy.global_position if is_instance_valid(enemy) else Vector3.ZERO
	for frame: int in range(12):
		await physics_frame
	_check(is_equal_approx(_game.elapsed, elapsed) and is_equal_approx(float(_game.director.active_event.get("remaining", 0.0)), event_time), "Pause freezes live elapsed time and event countdowns")
	_check(not is_instance_valid(enemy) or enemy.global_position.is_equal_approx(enemy_position), "Pause freezes native enemy motion")
	_game.resume_game()
	Engine.time_scale = TIME_SCALE
	Input.action_press("aim")


func _test_pause_and_death() -> void:
	_release_controls()
	await _pause_probe()
	_release_controls()
	_game.companion._revive_cooldown = 10000.0
	_game.player.damage_cooldown = 0.0
	_game.player.dash_remaining = 0.0
	_game.player.take_damage(1000000.0)
	_check(not _game.running and _game.paused and paused and _game._menu_kind == "dead", "A lethal native hit ends the endurance run and pauses the tree")
	_check(_game.player.health <= 0.0 and not _game.player.shoot(), "Dead players cannot continue firing or generating effects")
	_check(_game.return_to_menu(), "A finished endurance run can return to its real main menu")
	_game.start_run("normal", false, 2)
	Engine.time_scale = TIME_SCALE
	for region: Dictionary in _game.world.regions:
		_game.world.unlock_region(str(region.id))
	_game.director.phase_time = 10000.0
	_check(_game.running and _game.round_number == 1 and _game.enemies.is_empty(), "Starting again creates a clean first round after death")


func _test_cleanup() -> void:
	_release_controls()
	_game._clear_run()
	_game.inventory.create_starter()
	_game.exploration.import_state({})
	_game._create_actors()
	_game.director.phase = "prepare"
	_game.director.phase_time = 10000.0
	Engine.time_scale = TIME_SCALE
	await _simulate(2.0, false)
	var remaining_enemies: int = get_nodes_in_group("meyui_enemies").size()
	var nodes: int = _node_count(_game)
	_check(remaining_enemies == 0, "Old living and defeated enemy nodes disappear after run cleanup")
	_check(_game._effects.is_empty() and _game.exploration.drops.is_empty(), "Transient effects and ground loot are empty after cleanup")
	_check(nodes <= _baseline_nodes + 20, "Node count returns near its pre-run baseline: before=%d after=%d" % [_baseline_nodes, nodes])
	print("STRESS cleanup baseline=%d after=%d enemies=%d" % [_baseline_nodes, nodes, remaining_enemies])


func _simulate(seconds: float, pilot: bool) -> void:
	var target: float = _game.elapsed + seconds
	var previous: float = _game.elapsed
	while _game.elapsed < target and _game.running:
		if Time.get_ticks_msec() - _start_ms > 150000:
			_check(false, "Endurance simulation exceeded its 150-second wall-time budget")
			return
		# A test-pilot grace window prevents random death from truncating coverage.
		# The real lethal-damage/game-over path is exercised after endurance.
		_game.player.damage_cooldown = 10.0
		if pilot:
			_pilot()
		await physics_frame
		_simulated += maxf(0.0, _game.elapsed - previous)
		previous = _game.elapsed
		_samples += 1
		_peak_alive = maxi(_peak_alive, _game.enemies.size())
		_peak_effects = maxi(_peak_effects, _game._effects.size())
		_peak_drops = maxi(_peak_drops, _game.exploration.drops.size())
		if _game.companion._bite_time > 0.0:
			_dog_bit = true
		if _samples % 60 == 0:
			_sample_invariants()
	_check(_game.running, "Simulation remains live throughout its requested interval")


func _pilot() -> void:
	if not is_instance_valid(_bot_target) or bool(_bot_target.dead) or _samples % 6 == 0:
		_bot_target = null
		var distance: float = 1000000.0
		for enemy: Node3D in _game.enemies:
			if not is_instance_valid(enemy) or enemy.dead:
				continue
			var point: Vector3 = enemy.global_position + Vector3.UP
			var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(_game.player.camera.global_position, point, 1)
			var current: float = point.distance_squared_to(_game.player.camera.global_position)
			if current < distance and _game.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
				_bot_target = enemy
				distance = current
	if is_instance_valid(_bot_target):
		var point: Vector3 = _bot_target.global_position + Vector3.UP
		for area: Area3D in _bot_target._hit_areas:
			if str(area.get_meta("zone", "")) == "body":
				point = area.global_position
				break
		var direction: Vector3 = (point - _game.player.camera.global_position).normalized()
		_game.player.rotation.y = atan2(-direction.x, -direction.z)
		_game.player._pitch = asin(clampf(direction.y, -0.95, 0.95))
		_game.player._update_view(0.0, 0.0)
		_game.player.shoot()
	if _waypoint < _route.size():
		var offset: Vector3 = _route[_waypoint] - _game.player.global_position
		if Vector2(offset.x, offset.z).length() < 0.65 and absf(offset.y) < 1.0:
			_waypoint += 1
		else:
			offset.y = 0.0
			var local: Vector3 = _game.player.global_basis.inverse() * offset.normalized()
			_axis("move_right", maxf(0.0, local.x))
			_axis("move_left", maxf(0.0, -local.x))
			_axis("move_back", maxf(0.0, local.z))
			_axis("move_forward", maxf(0.0, -local.z))
	else:
		for action: String in ["move_right", "move_left", "move_back", "move_forward"]:
			Input.action_release(action)
	_visited[_game.world.get_region_id(_game.player.global_position)] = true


func _set_route(goal: Vector3) -> void:
	var map: RID = _game.get_world_3d().navigation_map
	var start: Vector3 = NavigationServer3D.map_get_closest_point(map, _game.player.global_position)
	var end: Vector3 = NavigationServer3D.map_get_closest_point(map, goal)
	_route = NavigationServer3D.map_get_path(map, start, end, true)
	_waypoint = 1 if _route.size() > 1 else 0
	_check(not _route.is_empty(), "The moving pilot receives a real native route to its next district")


func _axis(action: String, strength: float) -> void:
	if strength > 0.01:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _release_controls() -> void:
	for action: String in ["move_right", "move_left", "move_back", "move_forward", "fire", "aim", "sprint", "jump"]:
		Input.action_release(action)


func _sample_invariants() -> void:
	_check(_game.enemies.size() <= 24, "Native live actor count remains at or below 24")
	_check(_game.director._summons <= 4, "Per-wave summons remain at or below four")
	_check(_game._effects.size() <= 64 and _game.exploration.drops.size() <= 96, "Effect and loot pools remain bounded")
	_check(_game.player.global_position.is_finite() and _game.player.global_position.y > -14.0, "The player remains on a finite world floor")
	_check(_game.companion.global_position.is_finite() and _game.companion.global_position.y > -14.0, "The companion remains on a finite world floor")
	for enemy: Node3D in _game.enemies:
		_check(is_instance_valid(enemy) and not enemy.dead, "Live enemy registry has no stale or defeated actor")
		if not is_instance_valid(enemy):
			continue
		_check(enemy.global_position.is_finite() and enemy.global_position.y > -14.0, "Enemy %s stays above the world void: %s" % [enemy.kind, enemy.global_position])
		_check(Vector2(enemy.velocity.x, enemy.velocity.z).length() <= enemy.speed_max + 0.06, "Enemy %s respects its movement speed ceiling" % enemy.kind)
		_peak_projectiles = maxi(_peak_projectiles, enemy._projectiles.size())
		_check(enemy._projectiles.size() <= 3, "Individual ranged actors keep at most three live projectiles")
	_peak_nodes = maxi(_peak_nodes, _node_count(_game))


func _node_count(node: Node) -> int:
	var count: int = 1
	for child: Node in node.get_children():
		count += _node_count(child)
	return count


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition and not _failures.has(message):
		_failures.append(message)
		printerr("STRESS FAIL: " + message)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_release_controls()
	paused = false
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 8
	Engine.max_fps = 0
	if is_instance_valid(_game):
		_game.running = false
		await _game.audio.shutdown()
		_game.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.2, true).timeout
	_check(_node_count(root) == 1, "Whole-scene cleanup leaves only the root window")
	_check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) <= _initial_orphans, "Whole-scene cleanup creates no orphan nodes")
	for folder: String in ["saves", "profile", "settings"]:
		var directory: String = ProjectSettings.globalize_path(_directory + "/" + folder)
		if DirAccess.dir_exists_absolute(directory):
			for file: String in DirAccess.get_files_at(directory):
				DirAccess.remove_absolute(directory.path_join(file))
			DirAccess.remove_absolute(directory)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_directory))
	print("STRESS RESULT checks=%d failures=%d virtual_seconds=%.1f wall_seconds=%.1f physics_samples=%d peak_alive=%d peak_drops=%d peak_effects=%d peak_projectiles=%d baseline_nodes=%d peak_nodes=%d districts=%d" % [_checks, _failures.size(), _simulated, (Time.get_ticks_msec() - _start_ms) / 1000.0, _samples, _peak_alive, _peak_drops, _peak_effects, _peak_projectiles, _baseline_nodes, _peak_nodes, _visited.size()])
	quit(0 if _failures.is_empty() else 1)

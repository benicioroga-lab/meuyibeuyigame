extends "res://tests/test_stress.gd"
## A real player walks the exploration loop with movement input and native collision.
## Reuses the endurance pilot/cleanup; all saves stay in a unique test directory.
func _run() -> void:
	create_timer(145, true, false, true).timeout.connect(func():
		printerr("MAP_WALK timed out")
		quit(1))
	_start_ms = Time.get_ticks_msec()
	_initial_orphans = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_directory = "user://map_expansion_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_game = MainScene.instantiate()
	_game.save_manager = Saves.new(_directory + "/saves")
	_game._profile_store = Saves.new(_directory + "/profile")
	_game.settings = Settings.new(_directory + "/settings")
	_game.settings.set_value("fps_limit", 0)
	_game.settings.set_value("master", 0.0)
	_game.settings.save_settings()
	root.add_child(_game)
	while not _game.world.navigation_ready: await physics_frame
	_game.start_run("normal", false, 1)
	for region: Dictionary in _game.world.regions: _game.world.unlock_region(region.id)
	_game.director.phase = "prepare"
	_game.director.phase_time = 10000.0
	_game.companion.follow_only = true
	Engine.physics_ticks_per_second = PHYSICS_HZ
	Engine.max_physics_steps_per_frame = 16
	Engine.time_scale = TIME_SCALE
	await physics_frame
	for id: String in ["jardim", "estufa", "quiosque", "atrio", "farmacia", "mezanino", "terraco", "cafe", "oficina_loja", "arsenal", "bilheteria", "plateia", "palco", "projecao"]:
		var goal: Vector3 = _game.world.Expansion.LANDMARKS[id]
		await _walk_to(goal, id)
	await _walk_to(Vector3(20, 4.2, -7), "Volta pela oficina")
	await _walk_to(_game.world.spawn_position, "Circuito fecha no pátio")
	_check(_visited.has("parque") and _visited.has("shopping") and _visited.has("cinema"), "Player physically discovers all expansion districts")
	_release_controls()
	_check(_game.save_game(1), "Expanded district snapshot saves successfully")
	_game.world.import_state({"unlocked_regions":["patio", "mercado"]})
	var loaded: Dictionary = _game.save_manager.load_slot(1)
	_check(bool(loaded.get("ok", false)) and _game.apply_snapshot(loaded.get("state", {})), "Snapshot with expansion identifiers loads through the real validator")
	_check(_game.world.unlocked_regions.size() == 11, "All eleven district unlocks survive a full run save/load")
	var legacy: Dictionary = loaded.state.duplicate(true)
	legacy.world.unlocked_regions = ["patio", "mercado", "oficina", "galeria", "lajes", "quadra"]
	legacy.exploration.discovered = ["patio", "mercado"]
	_check(_game.apply_snapshot(legacy), "Pre-expansion six-district snapshots still load")
	_check(_game.world.unlocked_regions.size() == 6 and _game.world.can_purchase_region("parque"), "Old saves expose the new district purchases without resetting progression")
	await _finish()

func _walk_to(goal: Vector3, label: String) -> void:
	_set_route(goal)
	var length := 0.0
	for index in range(1, _route.size()): length += _route[index-1].distance_to(_route[index])
	var limit: float = _game.elapsed + length / 3.0 + 8.0
	while _game.player.global_position.distance_to(goal) > 1.1 and _game.elapsed < limit and _game.running:
		await _simulate(0.15, true)
	_release_controls()
	var distance: float = _game.player.global_position.distance_to(goal)
	_check(distance < 1.1, "%s reached using actual WASD physics: %s -> %s" % [label, _game.player.global_position, goal])
	print("MAP_WALK ", label, " distance=", snappedf(distance, 0.01), " path=", snappedf(length, 0.1))

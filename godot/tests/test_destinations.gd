extends "res://tests/test_map_expansion.gd"

func _run() -> void:
	create_timer(145,true,false,true).timeout.connect(func(): quit(1))
	_start_ms = Time.get_ticks_msec()
	_initial_orphans = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_directory = "user://destination_walk_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()]
	_game = MainScene.instantiate()
	_game.save_manager = Saves.new(_directory+"/saves")
	_game._profile_store = Saves.new(_directory+"/profile")
	_game.settings = Settings.new(_directory+"/settings")
	_game.settings.set_value("master",0)
	_game.settings.save_settings()
	root.add_child(_game)
	while not _game.world.navigation_ready: await physics_frame
	_game.start_run("normal",false,1)
	_game.coins = 12000
	_game.director.round_number = 8
	_game.director.phase = "prepare"
	_game.director.phase_time = 10000
	_game._sync_director()
	for region: Dictionary in _game.world.regions: _game.world.unlock_region(region.id)
	_game.companion.follow_only = true
	Engine.physics_ticks_per_second = PHYSICS_HZ
	Engine.max_physics_steps_per_frame = 16
	Engine.time_scale = TIME_SCALE
	for id: String in ["cisterna","painel_bombas","terminal","despacho"]:
		await _walk_to(_game.world.Destinations.LANDMARKS[id],id)
		if id == "painel_bombas": _purchase_station("pressure")
		if id == "despacho": _purchase_station("express")
	await _walk_to(_game.world.spawn_position,"Retorno pelo shopping e jardim")
	_check(_visited.has("cisterna") and _visited.has("terminal"),"Player physically discovers both new districts")
	_release_controls()
	Engine.time_scale = 1.0
	_game.set_process(false)
	_game.player.set_physics_process(false)
	_game.companion.set_physics_process(false)
	_game.exploration.set_process(false)
	for id: String in ["desafio_bombas","desafio_terminal"]:
		var poi: Dictionary = _game.world.points_of_interest.filter(func(p: Dictionary) -> bool: return p.id == id)[0]
		_game.player.global_position = poi.position + Vector3(0,0,2)
		_aim_at(poi.position+Vector3.UP*0.9)
		_game.exploration.interact()
		_check(_game.exploration.challenge.get("id","") == id,"E activates the physical district challenge: "+id)
		if _game.exploration.challenge.is_empty(): continue
		var active: Dictionary = JSON.parse_string(JSON.stringify(_game.snapshot_state()))
		_check(_game.apply_snapshot(active),"Active challenge survives strict save validation: "+id)
		_game.set_process(false)
		_game.player.set_physics_process(false)
		_game.companion.set_physics_process(false)
		_game.exploration.set_process(false)
		_game.exploration._tick_challenge(0.05)
		_check(not _game.enemies.is_empty(),"Challenge generates actual local pressure: "+id)
		for enemy: Node3D in _game.enemies:
			_check(enemy.global_position.distance_to(_game.player.global_position)>5,"Challenge cannot spawn on the participant")
			_check(_game.world.get_region_id(enemy.global_position) == poi.region_id,"Challenge pressure stays in its region")
			if not enemy.dead: enemy.dead = true
			enemy.queue_free()
		_game.enemies.clear()
		await physics_frame
		var challenge: Dictionary = _game.exploration.challenge
		var coins: int = _game.coins
		var drops: int = _game.exploration.drops.size()
		if challenge.mode == "hold":
			_game.exploration._pressure_clock = 100
			_game.player.global_position = poi.position+Vector3(0,0,10)
			_game.exploration._tick_challenge(1.01)
			_check(int(challenge.kills)==0,"Leaving the pump panel prevents hold progress")
			_game.player.global_position = poi.position+Vector3(0,0,2)
			for second: int in range(int(challenge.target)): _game.exploration._tick_challenge(1.01)
		else:
			var marker := Node3D.new()
			_game.add_child(marker)
			marker.global_position = poi.position
			for kill: int in range(int(challenge.target)): _game.exploration.on_kill(marker)
			marker.queue_free()
		_check(_game.exploration.challenge.is_empty() and _game.coins>coins and _game.exploration.drops.size()>drops,"Completing a challenge pays coins and equipment: "+id)
		_check(not _game.exploration._available(poi),"Challenge reward cannot be farmed again in the same round")
		_game.director.round_number += 4
		_game._sync_director()
		_check(_game.exploration._available(poi),"New rounds reopen regional challenges for ongoing progression")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(_game.snapshot_state()))
	_check(_game.apply_snapshot(snapshot),"New region unlocks, bought perks and challenge rewards persist together")
	_check(_game.progression.station_levels.get("pressure",0)==1 and _game.progression.station_levels.get("express",0)==1,"Saved regional perk ranks restore exactly once")
	await _finish()

func _aim_at(at: Vector3) -> void:
	_game.player.camera.rotation.y = 0.0
	var direction: Vector3 = (at-_game.player.camera.global_position).normalized()
	_game.player.rotation.y = atan2(-direction.x,-direction.z)
	_game.player._pitch = asin(clampf(direction.y,-0.95,0.95))
	_game.player._update_view(1,0)

func _purchase_station(id: String) -> void:
	var config: Dictionary = preload("res://data/district_perks.gd").PERKS[id]
	var coins: int = _game.coins
	var cost: int = _game.progression.station_cost(id)
	_aim_at(config.position+Vector3.UP*0.9)
	_game.exploration.interact()
	_check(_game.progression.station_levels.get(id,0)==1 and _game.coins==coins-cost,"Real E interaction purchases exactly one station rank: %s (rank %s, coins %d -> %d, cost %d, at %s, target %s)" % [id,_game.progression.station_levels.get(id,0),coins,_game.coins,cost,_game.player.global_position,_game.exploration.target.get("name","")])
	_game.player.camera.rotate_y(PI)
	_game.exploration.interact()
	_check(_game.coins==coins-cost,"Looking away prevents a second purchase: "+id)

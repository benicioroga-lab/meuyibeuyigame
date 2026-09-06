extends "res://tests/render_showcase.gd"

func _capture() -> void:
	output = "res://test-output/hud-revision" + ("/large" if OS.get_cmdline_user_args().has("--large-ui") else "")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	game = load("res://scenes/main.tscn").instantiate()
	var path := "user://hud_visual_%d" % OS.get_process_id()
	game.save_manager = Save.new(path+"/run")
	game._profile_store = Save.new(path+"/profile")
	game.settings = Settings.new(path+"/settings")
	game.settings.set_value("master",0)
	game.settings.set_value("resolution",[1280,720])
	game.settings.set_value("ui_scale",1.3 if OS.get_cmdline_user_args().has("--large-ui") else 1.0)
	game.settings.save_settings()
	root.add_child(game)
	while not game.world.navigation_ready: await physics_frame
	game.start_run("normal",false,1)
	game.set_process(false)
	game.player.set_physics_process(false)
	game.companion.set_physics_process(false)
	game.exploration.set_process(false)
	game.player.global_position = Vector3(0,0.2,17)
	game.player.rotation.y = 0.22
	game.player._pitch = 0.01
	game.player._update_view(1,0)
	game.player.flashlight.visible = true
	game.coins = 2470
	game.director.round_number = 12
	game._sync_director()
	game.ui.announcement_time = 0
	game.ui.notice_time = 0
	game.ui.saved_time = 0
	game._update_hud()
	await _save("combat")
	if OS.get_cmdline_user_args().has("--diagnose"):
		game.world._environment.ssao_enabled = false
		await _save("no-ssao")
		for mat: Material in game.world._materials.values():
			if mat is StandardMaterial3D: mat.normal_enabled = false
		await _save("no-normal")
		game.player.flashlight.shadow_enabled = false
		await _save("no-flashlight-shadow")
		game.world._moon.shadow_enabled = false
		game.world.apply_graphics({"shadows":0})
		await _save("no-shadows")
	game.ui.update_hud({"round":12,"coins":2470,"health":24,"max_health":120,"magazine":0,"reserve":84,"reloading":true,"reload_progress":0.45,"weapon_name":"Maré de Íons","weapon_rarity":"Lendária","dog_level":6,"dog_status":"protegendo","dog_health":60,"dog_max_health":90,"district":"Terminal da Madrugada","objective":"Último embarque · 12/18 · 35s","supplies":{"grenade":3,"medkit":1,"ammo":2},"powerups":{"double_damage":14,"frenzy":9}})
	game.ui.damage_screen.receive(0.8,Vector2.LEFT,false)
	await _save("damage-reload")
	game.pause_game()
	game.get_node("CoopMenu").open()
	await _save("cooperative-menu")
	game.get_node("CoopMenu").close()
	await _finish()

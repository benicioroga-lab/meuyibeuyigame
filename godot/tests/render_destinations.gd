extends "res://tests/render_showcase.gd"

func _capture() -> void:
	output = "res://test-output/destinations"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	game = load("res://scenes/main.tscn").instantiate()
	var path := "user://destination_visual_%d" % OS.get_process_id()
	game.save_manager = Save.new(path+"/run")
	game._profile_store = Save.new(path+"/profile")
	game.settings = Settings.new(path+"/settings")
	game.settings.set_value("master",0)
	game.settings.set_value("resolution",[1280,720])
	game.settings.save_settings()
	root.add_child(game)
	await create_timer(0.5).timeout
	game.start_run("normal",false,1)
	game.set_process(false)
	game.player.set_physics_process(false)
	game.companion.set_physics_process(false)
	game.exploration.set_process(false)
	game.coins = 1800
	game.director.round_number = 8
	game._sync_director()
	game.ui.announcement_time = 0
	game.ui.notice_time = 0
	game.ui.saved_time = 0
	for region: Dictionary in game.world.regions: game.world.unlock_region(region.id)
	for shot: Array in [
		["pump-house",Vector3(-28,-1.8,54),Vector3(-46,0,43)],
		["pump-interior",Vector3(-34,-1.8,61),Vector3(-45,0,44)],
		["terminal",Vector3(47,0.2,82),Vector3(45,1.2,103)],
		["mall",Vector3(49,0.2,54),Vector3(64,1.6,57)],
		["hud",Vector3(0,0.2,17),Vector3(-3,1.4,8)]
	]:
		game.player.global_position = shot[1]
		game.player._update_view(1,0)
		game.player.camera.look_at(shot[2])
		game.player.flashlight.visible = true
		game._update_hud()
		await _save(shot[0])
	for id: String in ["tidecaller","night_express","final_frame"]:
		var item := Loot.make_weapon(id,8,"legendary",98765)
		game.inventory.add_item(item)
		game.player.equip_weapon(item.uid)
		game.open_inventory("forge")
		game.ui.shop._selected_uid = item.uid
		game.ui.shop.refresh()
		await _save(id)
		game.resume_game()
	game.world.set_event("blackout")
	game.player.flashlight.visible = false
	game.ui.announcement_time = 0
	for i: int in range(3): game.exploration.drop_item("weapon",Loot.make_weapon(["tidecaller","night_express","final_frame"][i],8,"legendary",345+i),game.player.global_position+Vector3(i*1.6-1.6,0,-3),true)
	game.player.camera.look_at(game.player.global_position+Vector3(0,0.8,-3))
	game._update_hud()
	await _save("legendary-ground")
	await _finish()

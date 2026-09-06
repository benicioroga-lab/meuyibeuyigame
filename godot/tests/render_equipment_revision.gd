extends "res://tests/render_showcase.gd"

func _capture() -> void:
	output = "res://test-output/equipment-revision"
	var large := OS.get_cmdline_user_args().has("--large-ui")
	if large: output += "/large"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	game = load("res://scenes/main.tscn").instantiate()
	var path := "user://equipment_visual_%d" % OS.get_process_id()
	game.save_manager = Save.new(path + "/run")
	game._profile_store = Save.new(path + "/profile")
	game.settings = Settings.new(path + "/settings")
	game.settings.set_value("ui_scale", 1.3 if large else 1.0)
	game.settings.set_value("resolution", [1280,720])
	game.settings.save_settings()
	root.add_child(game)
	await create_timer(0.4).timeout
	game.start_run("normal", false, 1)
	game.set_process(false)
	game.player.set_physics_process(false)
	game.companion.set_physics_process(false)
	game.exploration.set_process(false)
	game.coins = 15000
	game.director.round_number = 12
	game._sync_director()
	game.ui.announcement_time = 0
	for index: int in range(10):
		game.inventory.add_item(Loot.make_weapon(["boardwalk","hammer","biscuit"][index%3], 8, ["rare","epic","legendary","mythic"][index%4], index+786))
	game.player.equip_weapon(game.inventory.weapon_slots[1])
	for index: int in range(10): game.inventory.add_attachment(Loot.roll_attachment(game.rng, 2.0))
	for branch: String in game.companion.levels: game.companion.levels[branch] = 3
	game.companion._recalculate_stats()
	game.companion._refresh_upgrade_visual()
	for id: String in ["force","hands","eye","heart"]: game.progression.levels[id] = 4
	game._update_hud()
	for tab: String in ["inventory", "supplies", "forge", "perks", "dog"]:
		game.open_inventory(tab)
		await _save(tab)
	game.resume_game()
	game.open_weapon_wheel()
	root.warp_mouse(Vector2(root.size) * Vector2(0.5, 0.2))
	await _save("wheel")
	game.close_weapon_wheel(false)
	game.player.rotation = Vector3.ZERO
	game.player._pitch = 0
	game.player.aiming = false
	game.player._update_view(1,0)
	for index: int in range(5):
		var enemy := preload("res://scripts/enemy.gd").new()
		enemy.setup(game, ["grunt","runner","spitter","screamer","tank"][index], 1)
		game.add_child(enemy)
		enemy.global_position = game.player.global_position + Vector3((index - 2) * 1.7,0,-6)
		enemy.rotation.y = PI
		enemy.set_physics_process(false)
	game.player.flashlight_on = true
	game.player.flashlight.visible = true
	await _save("creatures-night")
	game.world.set_event("blackout")
	game.player.flashlight.visible = false
	await _save("blackout")
	game.player.flashlight.visible = true
	await _save("blackout-flashlight")
	game.world.set_event("")
	for index: int in range(6):
		game.exploration.drop_item("weapon", Loot.make_weapon("boardwalk", 8, Loot.RARITY_ORDER[index],index+910),game.player.global_position + Vector3((index-2.5)*1.5,0,-5),true)
	await _save("loot-rarities")
	await _finish()

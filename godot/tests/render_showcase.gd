extends SceneTree
## Reproducible native screenshots, isolated from the player's saves and profile.
const Save = preload("res://scripts/save_manager.gd")
const Settings = preload("res://scripts/game_settings.gd")
const Loot = preload("res://data/loot_data.gd")
var game: Node
var output := "res://test-output"

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var large_ui := OS.get_cmdline_user_args().has("--large-ui")
	if large_ui: output += "/large-ui"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var ignore := FileAccess.open("res://test-output/.gdignore", FileAccess.WRITE)
	if ignore != null: ignore.close()
	game = load("res://scenes/main.tscn").instantiate()
	game.save_manager = Save.new("user://visual-tests-run")
	game._profile_store = Save.new("user://visual-tests-profile")
	game.settings = Settings.new("user://visual-tests-settings")
	game.settings.set_value("ui_scale", 1.3 if large_ui else 1.0)
	game.settings.save_settings()
	root.add_child(game)
	await create_timer(1.0).timeout
	await _save("01-menu")
	game.ui.show_new_game()
	await _save("02-new-game")
	game.start_run("normal", false, 1)
	await create_timer(0.35).timeout
	game.set_process(false)
	game.player.set_physics_process(false)
	game.companion.set_physics_process(false)
	game.ui.announcement_time = 0
	await _save("03-gameplay")
	if OS.get_cmdline_user_args().has("--menu-only"):
		await _finish()
		return
	game.coins = 12000
	game.director.round_number = 8
	game._sync_director()
	for index in range(8):
		game.inventory.add_item(Loot.roll_weapon(8, game.rng, 2.0, ["uncommon","rare","epic","legendary"][index % 4]))
	for index in range(8): game.inventory.add_attachment(Loot.roll_attachment(game.rng, 2.0))
	game.save_game(1)
	game._update_hud()
	for tab: String in ["inventory","forge","perks","dog"]:
		game.open_inventory(tab)
		await _save("04-" + tab)
	game.pause_game()
	await _save("05-pause")
	if game.ui.has_method("show_settings"):
		game.ui.show_settings()
		await _save("06-settings")
	if game.ui.has_method("show_load_game"):
		game.ui.show_load_game()
		await _save("07-saves")
	await _finish()

func _finish() -> void:
	game.running = false
	paused = false
	await game.audio.shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	print("SHOWCASE_CAPTURED")
	quit()

func _save(label: String) -> void:
	await create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var status := image.save_png(output + "/" + label + ".png")
	print("RENDER ", label, " ", status)

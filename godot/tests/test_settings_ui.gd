extends SceneTree
## Exercise real option controls against a running scene, including while paused.
## All preferences and saves are isolated; --capture also records GPU previews.
const Main = preload("res://scenes/main.tscn")
const Saves = preload("res://scripts/save_manager.gd")
const Settings = preload("res://scripts/game_settings.gd")
var game: Node
var directory: String
var checks := 0
var failures: Array[String] = []
var capture := false
const OUTPUT := "res://test-output/settings-regression"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	capture = DisplayServer.get_name() != "headless" and OS.get_cmdline_user_args().has("--capture")
	directory = "user://settings_ui_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	game = Main.instantiate()
	game.save_manager = Saves.new(directory + "/saves")
	game._profile_store = Saves.new(directory + "/profile")
	game.settings = Settings.new(directory + "/settings")
	game.settings.apply_preset("low")
	game.settings.set_value("master", 0.0)
	game.settings.save_settings()
	root.add_child(game)
	current_scene = game
	game.set_process(false)
	await _settle()
	_check(not game.world._moon.shadow_enabled, "Saved Low preset really starts with shadows disabled")
	game.ui.show_settings()
	_set_slider("gameplay", "fov", 60)
	_check(is_equal_approx(game._menu_camera.fov, 60), "Main menu camera immediately previews 60-degree FOV")
	_set_slider("gameplay", "fov", 110)
	_check(is_equal_approx(game._menu_camera.fov, 110), "Main menu camera immediately previews 110-degree FOV")
	_select("graphics", "preset", "high")
	_check(game.world._moon.shadow_enabled, "Changing saved Low to High restores the sun shadows")
	_check(game.world._lights[0].shadow_enabled, "Changing saved Low to High restores authored local shadows")
	_check(root.msaa_3d == Viewport.MSAA_4X, "Native quality selector updates the rendering viewport")
	_set_slider("graphics", "render_distance", 150)
	var preset: OptionButton = game.ui.setting_controls.preset
	_check(preset.get_item_text(preset.selected) == "Personalizado", "Manual change updates the visible preset without a page rebuild")
	_check(is_equal_approx(game._menu_camera.far, 150), "Draw distance reaches the visible menu camera")
	_select("graphics", "preset", "low")
	_check(not game.world._moon.shadow_enabled and not game.world._lights[0].shadow_enabled, "Returning to Low disables sun and local shadows")
	_select("graphics", "preset", "ultra")
	_check(game.world._moon.shadow_enabled and game.world._lights[0].shadow_enabled, "Shadows can be switched repeatedly without latching off")
	_set_toggle("graphics", "fog", false)
	_check(not game.world._environment.fog_enabled, "Fog checkbox updates the actual world resource")
	_set_toggle("graphics", "fog", true)
	_check(game.world._environment.fog_enabled, "Fog can be enabled again")
	_set_slider("graphics", "particles", 0)
	_check(not game.world._rain.visible and game.world._rain.multimesh.visible_instance_count == 0, "Particle slider removes rain immediately during menus")
	_set_slider("graphics", "particles", 1)
	_check(game.world._rain.visible and game.world._rain.multimesh.visible_instance_count == 850, "Particle slider restores its actual instance budget")
	_set_toggle("graphics", "vegetation", false)
	_check(game.world._vegetation.all(func(plant: Node3D) -> bool: return not plant.visible), "Vegetation checkbox affects the actual leaves")
	_set_toggle("graphics", "vegetation", true)
	_check(game.world._vegetation.all(func(plant: Node3D) -> bool: return plant.visible), "Vegetation checkbox restores leaves")
	await _check_window_settings()
	for frame in range(480):
		if game.world.navigation_ready: break
		await process_frame
	game.start_run("normal", false, 1)
	game.player.set_physics_process(false)
	game.companion.set_physics_process(false)
	game.pause_game()
	game.ui.show_settings()
	var before: Vector3 = game.player.global_position
	var ammo := int(game.player.magazine)
	_set_slider("gameplay", "fov", 60)
	_check(paused and game.paused, "Options leave the expedition paused")
	_check(is_equal_approx(game.player.camera.fov, 60), "FOV control updates the paused first-person camera immediately")
	var narrow: Vector3 = game.player.camera.project_ray_normal(Vector2(1000, 360))
	await _capture("01-fov-60")
	_set_slider("gameplay", "fov", 110)
	_check(is_equal_approx(game.player.camera.fov, 110), "Paused first-person camera follows a second FOV change")
	var wide: Vector3 = game.player.camera.project_ray_normal(Vector2(1000, 360))
	_check(narrow.angle_to(wide) > 0.1, "FOV changes the actual projection rays, not only displayed numbers")
	await _capture("02-fov-110")
	_check(game.player.global_position == before and game.player.magazine == ammo, "Live preview neither moves the player nor consumes ammunition")
	game.player.third_person = true
	_set_slider("gameplay", "fov", 90)
	_check(is_equal_approx(game.player.camera.fov, 90), "The same FOV control updates third person")
	game.player.third_person = false
	game.player.aiming = true
	_set_slider("gameplay", "fov", 100)
	var ads: float = game.player.camera.fov
	_check(ads < 100 and ads >= 20, "Changing FOV while aiming preserves weapon zoom")
	game.player.aiming = false
	_set_slider("gameplay", "fov", 90)
	_select("graphics", "preset", "low")
	await _capture("03-low")
	game.open_inventory("forge")
	await _settle()
	var preview := game.ui.shop.find_child("InspectionWorld", true, false) as SubViewport
	_check(is_instance_valid(preview) and preview.msaa_3d == Viewport.MSAA_DISABLED, "New forge preview inherits Low quality on its first frame")
	game.ui.show_settings()
	_select("graphics", "preset", "ultra")
	_check(preview.msaa_3d == Viewport.MSAA_8X, "An existing forge preview follows subsequent quality changes")
	game.open_inventory("dog")
	await _settle()
	preview = game.ui.shop.find_child("InspectionWorld", true, false) as SubViewport
	_check(is_instance_valid(preview) and preview.msaa_3d == Viewport.MSAA_8X, "New companion preview inherits the current Ultra quality")
	game.ui.show_settings()
	await _capture("04-ultra")
	game.resume_game()
	_check(not paused and not game.paused and is_equal_approx(game.player.camera.fov, 90), "Resuming preserves the chosen FOV")
	var loaded = Settings.new(directory + "/settings")
	_check(loaded.load_settings().ok and loaded.data.fov == 90 and loaded.data.preset == "ultra", "The same visible controls persist FOV and quality for the next launch")
	game.running = false
	paused = false
	await game.audio.shutdown()
	game.queue_free()
	await _settle()
	for folder: String in ["saves", "profile", "settings"]:
		var path := ProjectSettings.globalize_path(directory + "/" + folder)
		if DirAccess.dir_exists_absolute(path):
			for file: String in DirAccess.get_files_at(path): DirAccess.remove_absolute(path.path_join(file))
			DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
	print("SETTINGS UI: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: printerr(failure)
	quit(0 if failures.is_empty() else 1)

func _check_window_settings() -> void:
	if DisplayServer.get_name() == "headless": return
	_select("graphics", "resolution", [1600, 900])
	await _settle()
	_check(root.size == Vector2i(1600, 900), "Resolution selector changes the real window size")
	root.size = Vector2i(1400, 800)
	await _settle()
	_set_slider("gameplay", "fov", 95)
	await _settle()
	_check(root.size == Vector2i(1400, 800), "FOV slider does not undo a manual window resize")
	_select("graphics", "resolution", [1280, 720])
	await _settle()
	_check(root.size == Vector2i(1280, 720), "Window resolution can be changed back")
	_select("graphics", "window_mode", "borderless")
	await _settle()
	var screen := DisplayServer.screen_get_size(root.current_screen)
	_check(root.borderless and root.size == screen, "Borderless mode fills the current monitor")
	var expected_scale := clampf(minf(1280.0 / screen.x, 720.0 / screen.y), 0.25, 2.0)
	_check(is_equal_approx(root.scaling_3d_scale, expected_scale), "Borderless resolution changes actual 3D rendering scale")
	_select("graphics", "resolution", [1920, 1080])
	await _settle()
	expected_scale = clampf(minf(1920.0 / screen.x, 1080.0 / screen.y), 0.25, 2.0)
	_check(is_equal_approx(root.scaling_3d_scale, expected_scale), "Resolution remains functional while borderless")
	_select("graphics", "window_mode", "fullscreen")
	await _settle()
	_check(root.mode == Window.MODE_FULLSCREEN and is_equal_approx(root.scaling_3d_scale, expected_scale), "Fullscreen also uses the chosen 3D rendering resolution")
	_select("graphics", "resolution", [1280, 720])
	await _settle()
	expected_scale = clampf(minf(1280.0 / screen.x, 720.0 / screen.y), 0.25, 2.0)
	_check(is_equal_approx(root.scaling_3d_scale, expected_scale), "Resolution can be changed while fullscreen")
	_select("graphics", "window_mode", "windowed")
	_select("graphics", "resolution", [1280, 720])
	await _settle()
	_check(not root.borderless and root.mode == Window.MODE_WINDOWED and is_equal_approx(root.scaling_3d_scale, 1.0), "Returning to windowed restores native 3D rendering")

func _set_slider(category: String, key: String, value: float) -> void:
	if game.ui.settings_category != category or game.ui.detail_mode != "settings": game.ui._show_settings_category(category)
	var control: HSlider = game.ui.setting_controls[key]
	control.value = value
	_check(is_equal_approx(float(game.settings.data[key]), value), "Slider applies: " + key)

func _set_toggle(category: String, key: String, value: bool) -> void:
	if game.ui.settings_category != category: game.ui._show_settings_category(category)
	var control: CheckButton = game.ui.setting_controls[key]
	control.button_pressed = value
	_check(game.settings.data[key] == value, "Toggle applies: " + key)

func _select(category: String, key: String, value: Variant) -> void:
	if game.ui.settings_category != category: game.ui._show_settings_category(category)
	var control: OptionButton = game.ui.setting_controls[key]
	var options: Array = control.get_meta("setting_options")
	for index in range(options.size()):
		if options[index].id == value:
			control.select(index)
			control.item_selected.emit(index)
			_check(game.settings.data[key] == value, "Selector applies: " + key)
			return
	_check(false, "Missing option for " + key)

func _settle() -> void:
	for frame in range(6): await process_frame

func _capture(label: String) -> void:
	if not capture: return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var ignore := FileAccess.open("res://test-output/.gdignore", FileAccess.WRITE)
	if ignore != null: ignore.close()
	await create_timer(0.35).timeout
	await _settle()
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(OUTPUT + "/" + label + ".png") == OK, "GPU preview recorded: " + label)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

extends SceneTree
const Settings = preload("res://scripts/game_settings.gd")
var _checks: int = 0
var _failures: Array[String] = []

class LightingOwner extends Node3D:
	var light: OmniLight3D
	var calls: int = 0
	func apply_settings(values: Dictionary) -> void:
		calls += 1
		light.shadow_enabled = int(values.get("shadows", 2)) > 1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var directory: String = "user://test_settings_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var settings = Settings.new(directory)
	_check(settings.load_settings().ok and settings.data.fov == 76, "Missing settings load safe defaults")
	_check(settings.values == settings.data, "Values and data expose the same settings")
	var keys: Array = []
	for entry: Dictionary in settings.setting_schema():
		keys.append(entry.key)
		_check(entry.has("category") and entry.has("type") and entry.has("default"), "Every setting exposes a usable UI schema: " + entry.key)
	_check(keys.size() == Settings.DEFAULTS.size(), "Every stored setting has a visible form control")
	_check(not keys.has("dlss") and not keys.has("ssao") and not keys.has("frame_generation"), "Unsupported renderer features are absent")
	_check(not settings.set_value("fov", NAN) and not settings.set_value("fov", 170), "Reject nonfinite and out-of-range field of view")
	_check(not settings.set_value("msaa", 3) and not settings.set_value("vsync", "false"), "Reject unsupported enums and wrong scalar types")
	_check(not settings.set_value("crosshair_color", "zzzzzz") and not settings.set_value("resolution", [500, 300]), "Reject invalid colors and unusable window sizes")
	_check(settings.apply_preset("low") and settings.data.shadows == 0 and settings.data.particles == 0.25, "Low preset changes actual quality budgets")
	_check(settings.set_value("render_distance", 150) and settings.data.preset == "custom", "Individual graphics change marks preset custom")
	_check(settings.apply_preset("ultra") and settings.data.msaa == 8 and settings.data.shadows == 3, "Ultra applies maximum supported settings")
	_check(settings.set_value("mouse_sensitivity", 0.004) and settings.set_value("toggle_aim", true), "Gameplay controls can be personalized")
	_check(settings.set_value("music", 0.1) and settings.set_value("master", 0.0), "Audio categories have independent values")
	_check(settings.save_settings(), "Preferences atomically persist")
	var loaded = Settings.new(directory)
	_check(loaded.load_settings().ok and loaded.data.toggle_aim and is_equal_approx(loaded.data.mouse_sensitivity, 0.004), "Controls round trip independently from run slots")
	_check(loaded.data.preset == "ultra" and loaded.data.msaa == 8, "Graphics enums survive JSON float representation")
	loaded.set_value("music", 0.6)
	_check(loaded.save_settings(), "Second save creates previous preference backup")
	var path: String = loaded.storage_root.path_join("preferences.json")
	_write(path, "interrupted")
	var recovered = Settings.new(directory)
	_check(recovered.load_settings().recovered and is_equal_approx(recovered.data.music, 0.1), "Corruption restores valid previous preferences")
	var game: Node3D = Node3D.new()
	root.add_child(game)
	var camera: Camera3D = Camera3D.new()
	game.add_child(camera)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.shadow_enabled = true
	game.add_child(light)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	game.add_child(environment)
	recovered.apply_preset("low")
	recovered.set_value("fog", false)
	recovered.set_value("fps_limit", 60)
	recovered.apply(self, game)
	_check(Engine.max_fps == 60 and camera.far == 90, "Applying settings changes engine FPS and camera draw distance")
	_check(not light.shadow_enabled and not environment.environment.fog_enabled, "Low shadows and disabled fog reach actual scene resources")
	_check(root.msaa_3d == Viewport.MSAA_DISABLED and AudioServer.is_bus_mute(0), "MSAA and master mute are applied natively")
	recovered.apply_preset("high")
	recovered.apply(self, game)
	_check(light.shadow_enabled and root.msaa_3d == Viewport.MSAA_4X, "Re-enabling quality restores authored shadows")
	var owner: LightingOwner = LightingOwner.new()
	game.add_child(owner)
	owner.light = OmniLight3D.new()
	owner.light.shadow_enabled = true
	owner.light.set_meta("authored_shadow_enabled", true)
	owner.add_child(owner.light)
	var preview: SubViewport = SubViewport.new()
	preview.own_world_3d = true
	preview.size = Vector2i(128, 128)
	game.add_child(preview)
	var preview_camera: Camera3D = Camera3D.new()
	preview_camera.far = 25.0
	preview.add_child(preview_camera)
	var preview_environment: WorldEnvironment = WorldEnvironment.new()
	preview_environment.environment = Environment.new()
	preview_environment.environment.fog_enabled = false
	preview.add_child(preview_environment)
	var texture_image: Image = Image.create(8, 8, true, Image.FORMAT_RGBA8)
	texture_image.fill(Color.WHITE)
	var texture: ImageTexture = ImageTexture.create_from_image(texture_image)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.material_override = material
	game.add_child(mesh)
	var nearest_material: StandardMaterial3D = StandardMaterial3D.new()
	nearest_material.albedo_texture = texture
	nearest_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var preview_mesh: MeshInstance3D = MeshInstance3D.new()
	preview_mesh.mesh = BoxMesh.new()
	preview_mesh.material_override = nearest_material
	preview.add_child(preview_mesh)
	recovered.apply_preset("low")
	recovered.apply(self, game)
	_check(not owner.light.shadow_enabled and preview.msaa_3d == Viewport.MSAA_DISABLED, "Low preset disables owned street-light shadows and inspection AA")
	recovered.apply_preset("high")
	paused = true
	recovered.apply(self, game)
	_check(owner.light.shadow_enabled, "Starting on low cannot permanently cache an owner's shadows as disabled")
	_check(owner.calls == 2, "Native settings dispatch owner callbacks even while gameplay is paused")
	_check(preview.msaa_3d == Viewport.MSAA_4X and preview.anisotropic_filtering_level == 2, "Runtime AA and texture quality reach the inspection viewport")
	_check(not preview_environment.environment.fog_enabled and preview_camera.far == 25, "World fog and render distance do not contaminate the isolated inspection scene")
	_check(material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC, "Textured world materials opt into the selected anisotropic filtering")
	_check(nearest_material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC, "Anisotropic filtering preserves an authored nearest texture style")
	recovered.apply_preset("medium")
	recovered.apply(self, game)
	_check(not owner.light.shadow_enabled and light.shadow_enabled, "Owner-specific medium shadow budget has final say after generic native defaults")
	_check(root.positional_shadow_atlas_size == 1024 and preview.positional_shadow_atlas_size == 1024, "Shadow quality changes real viewport atlas budgets")
	paused = false
	var original_size: Vector2i = root.size
	recovered.set_value("window_mode", "windowed")
	recovered.apply(self, game)
	root.size = Vector2i(1337, 777)
	recovered.set_value("fov", 99.0)
	recovered.apply(self, game)
	_check(root.size == Vector2i(1337, 777), "An unrelated slider does not reset a manually resized game window")
	recovered.set_value("window_mode", "borderless")
	recovered.set_value("resolution", [1280, 720])
	recovered.apply(self, game)
	var target_size: Vector2i = root.size if DisplayServer.get_name() == "headless" else DisplayServer.screen_get_size(root.current_screen)
	var expected_scale: float = clampf(minf(1280.0 / target_size.x, 720.0 / target_size.y), 0.25, 2.0)
	_check(is_equal_approx(root.scaling_3d_scale, expected_scale), "Borderless selected resolution changes the real 3D buffer scale")
	recovered.set_value("window_mode", "fullscreen")
	recovered.set_value("resolution", [960, 540])
	recovered.apply(self, game)
	target_size = root.size if DisplayServer.get_name() == "headless" else DisplayServer.screen_get_size(root.current_screen)
	expected_scale = clampf(minf(960.0 / target_size.x, 540.0 / target_size.y), 0.25, 2.0)
	_check(is_equal_approx(root.scaling_3d_scale, expected_scale) and root.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR, "Fullscreen resolution uses supported bilinear scaling without a fake upscaler")
	recovered.set_value("window_mode", "windowed")
	recovered.apply(self, game)
	_check(root.scaling_3d_scale == 1.0, "Returning to a window restores native 3D rendering at its chosen size")
	root.size = original_size
	recovered.set_value("fov", 101.0)
	recovered.set_value("shadows", 3)
	recovered.set_value("render_distance", 220.0)
	recovered.set_value("fog", false)
	_check(recovered.save_settings(), "Runtime graphics and FOV changes persist after preference recovery")
	var persisted = Settings.new(directory)
	_check(persisted.load_settings().ok and persisted.data.fov == 101.0, "FOV preference survives a fresh settings instance")
	light.shadow_enabled = false
	environment.environment.fog_enabled = true
	camera.far = 10.0
	persisted.apply(self, game)
	_check(light.shadow_enabled and camera.far == 220.0 and not environment.environment.fog_enabled, "Reloading persisted graphics reapplies actual scene resources")
	game.free()
	_write(path, JSON.stringify({"version": 99, "body": "{}"}))
	var future = Settings.new(directory)
	_check(not future.load_settings().ok and not future.save_settings(), "Older engine cannot overwrite future preferences")
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)
	DirAccess.remove_absolute(loaded.storage_root)
	Engine.max_fps = 0
	AudioServer.set_bus_mute(0, false)
	print("SETTINGS TESTS: %d checks, %d failures" % [_checks, _failures.size()])
	for failure in _failures:
		printerr(failure)
	quit(0 if _failures.is_empty() else 1)


func _write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)

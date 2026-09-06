class_name MeyuiSettings
extends RefCounted
## The options describe features actually used by the Compatibility renderer.
## Persistence is independent of runs, so a failed run/save never resets controls.

const VERSION: int = 1
const MAX_BYTES: int = 65536
const DEFAULTS: Dictionary = {
	"preset": "high", "resolution": [1280, 720], "window_mode": "windowed",
	"vsync": true, "fps_limit": 120, "shadows": 2, "render_distance": 180.0,
	"effects": 0.8, "particles": 0.8, "vegetation": true, "msaa": 4, "fog": true,
	"anisotropic": 2, "mouse_sensitivity": 0.0022, "ads_sensitivity": 0.64,
	"fov": 76.0, "head_bob": 0.6, "camera_shake": 0.65, "visual_recoil": 1.0,
	"auto_sprint": false, "toggle_aim": false, "toggle_sprint": false,
	"crosshair": true, "hitmarkers": true, "damage_numbers": true,
	"reduced_flashes": false, "weapon_effects": 0.8,
	"ui_scale": 1.0, "colorblind_mode": "normal", "crosshair_color": "f5edd6",
	"hitmarker_color": "e9bd70", "high_contrast": false,
	"master": 0.8, "music": 0.45, "effects_audio": 0.8, "weapons": 0.85,
	"ambient": 0.65, "interface": 0.65, "output_device": "Default",
}
const PRESETS: Dictionary = {
	"low": {"shadows": 0, "render_distance": 90.0, "effects": 0.35, "particles": 0.25, "vegetation": false, "msaa": 0, "fog": true, "anisotropic": 0, "weapon_effects": 0.4},
	"medium": {"shadows": 1, "render_distance": 140.0, "effects": 0.6, "particles": 0.5, "vegetation": true, "msaa": 2, "fog": true, "anisotropic": 1, "weapon_effects": 0.6},
	"high": {"shadows": 2, "render_distance": 180.0, "effects": 0.8, "particles": 0.8, "vegetation": true, "msaa": 4, "fog": true, "anisotropic": 2, "weapon_effects": 0.8},
	"ultra": {"shadows": 3, "render_distance": 240.0, "effects": 1.0, "particles": 1.0, "vegetation": true, "msaa": 8, "fog": true, "anisotropic": 3, "weapon_effects": 1.0},
}
var data: Dictionary = DEFAULTS.duplicate(true)
var values: Dictionary:
	get:
		return data
	set(value):
		data = value
var storage_root: String
var last_error: String = ""
var recovered: bool = false
var _schema: Array = []
var _loaded_future_version: bool = false
var _window_preferences: Dictionary = {}
var _window_id: int = 0
var _applied_vsync: int = -1
var _shadow_atlas_size: int = -1
var _materials_seen: Dictionary = {}


func _init(directory: String = "user://settings") -> void:
	storage_root = ProjectSettings.globalize_path(directory).simplify_path()


func get_value(key: String, fallback: Variant = null) -> Variant:
	return data.get(key, DEFAULTS.get(key, fallback))


func set_value(key: String, value: Variant) -> bool:
	if key == "preset":
		return apply_preset(str(value))
	if not DEFAULTS.has(key) or not _valid_value(key, value):
		return false
	data[key] = value.duplicate(true) if value is Array or value is Dictionary else value
	if PRESETS.high.has(key):
		data.preset = "custom"
	return true


func apply_preset(id: String) -> bool:
	if id == "custom":
		data.preset = id
		return true
	if not PRESETS.has(id):
		return false
	for key in PRESETS[id]:
		data[key] = PRESETS[id][key]
	data.preset = id
	return true


func load_settings() -> Dictionary:
	data = DEFAULTS.duplicate(true)
	recovered = false
	_loaded_future_version = false
	var result: Dictionary = _read_file(_path())
	if result.get("future", false):
		_loaded_future_version = true
		last_error = "As configurações pertencem a uma versão mais recente."
		return {"ok": false, "error": last_error, "recovered": false}
	if not result.get("ok", false):
		for suffix in [".bak", ".tmp"]:
			var backup: Dictionary = _read_file(_path() + suffix)
			if backup.get("ok", false):
				result = backup
				recovered = true
				break
	if result.get("ok", false):
		for key in result.data:
			if DEFAULTS.has(key) and _valid_value(key, result.data[key]):
				data[key] = result.data[key]
		last_error = ""
		return {"ok": true, "recovered": recovered, "error": ""}
	last_error = "" if not FileAccess.file_exists(_path()) else "Configurações danificadas; os padrões foram restaurados."
	return {"ok": last_error.is_empty(), "error": last_error, "recovered": false}


func save_settings() -> bool:
	if _loaded_future_version:
		last_error = "Uma versão anterior não pode substituir estas configurações."
		return false
	for key in data:
		if not DEFAULTS.has(key) or not _valid_value(key, data[key]):
			last_error = "Configuração inválida: " + str(key)
			return false
	if DirAccess.make_dir_recursive_absolute(storage_root) != OK:
		last_error = "Não foi possível criar a pasta de configurações."
		return false
	var body: String = JSON.stringify(data, "", true, true)
	var encoded: String = JSON.stringify({"version": VERSION, "body": body, "checksum": body.sha256_text()})
	var path: String = _path()
	var file: FileAccess = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		last_error = "Não foi possível gravar as configurações."
		return false
	file.store_string(encoded)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK or not _read_file(path + ".tmp").get("ok", false):
		last_error = "Não foi possível verificar as configurações."
		return false
	if _read_file(path).get("ok", false):
		if DirAccess.copy_absolute(path, path + ".bak.tmp") != OK or DirAccess.rename_absolute(path + ".bak.tmp", path + ".bak") != OK:
			last_error = "Não foi possível preservar as configurações anteriores."
			return false
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		last_error = "Não foi possível concluir as configurações."
		return false
	last_error = ""
	return true


func apply(tree: SceneTree, game: Node = null) -> void:
	if tree == null:
		return
	var window: Window = tree.root
	Engine.max_fps = int(get_value("fps_limit"))
	_apply_viewport(window)
	_apply_window(window)
	_apply_render_resolution(window)
	var atlas_size: int = [512, 1024, 2048, 4096][int(get_value("shadows"))]
	if DisplayServer.get_name() != "headless" and _shadow_atlas_size != atlas_size:
		RenderingServer.directional_shadow_atlas_set_size(atlas_size, true)
		_shadow_atlas_size = atlas_size
	var master_index: int = AudioServer.get_bus_index("Master")
	if master_index >= 0:
		var volume_db: float = linear_to_db(maxf(0.0001, float(get_value("master"))))
		if not is_equal_approx(AudioServer.get_bus_volume_db(master_index), volume_db):
			AudioServer.set_bus_volume_db(master_index, volume_db)
		var muted: bool = float(get_value("master")) <= 0.0
		if AudioServer.is_bus_mute(master_index) != muted:
			AudioServer.set_bus_mute(master_index, muted)
	var device: String = get_value("output_device")
	if AudioServer.output_device != device and device in AudioServer.get_output_device_list():
		AudioServer.output_device = device
	if game != null:
		_materials_seen.clear()
		# Capture authored light defaults BEFORE world/player callbacks change them.
		# Specialized owners then have the final say over their own lighting and FOV.
		_apply_native_nodes(game)
		_dispatch_callbacks(game)


func _apply_window(window: Window) -> void:
	var preferences: Dictionary = {"mode": get_value("window_mode"), "resolution": get_value("resolution").duplicate()}
	var changed: bool = _window_id != window.get_instance_id() or _window_preferences != preferences
	if changed:
		_window_id = window.get_instance_id()
		_window_preferences = preferences
		if DisplayServer.get_name() != "headless":
			var mode: String = preferences.mode
			if mode == "fullscreen":
				window.borderless = false
				window.mode = Window.MODE_FULLSCREEN
			elif mode == "borderless":
				window.mode = Window.MODE_WINDOWED
				window.borderless = true
				window.position = DisplayServer.screen_get_position(window.current_screen)
				window.size = DisplayServer.screen_get_size(window.current_screen)
			else:
				window.mode = Window.MODE_WINDOWED
				window.borderless = false
				window.size = Vector2i(int(preferences.resolution[0]), int(preferences.resolution[1]))
	var vsync: int = DisplayServer.VSYNC_ENABLED if get_value("vsync") else DisplayServer.VSYNC_DISABLED
	if DisplayServer.get_name() != "headless" and (changed or _applied_vsync != vsync):
		DisplayServer.window_set_vsync_mode(vsync, window.get_window_id())
		_applied_vsync = vsync


func _apply_render_resolution(window: Window) -> void:
	# Fullscreen/borderless keep the desktop mode and a crisp native HUD, while
	# the chosen resolution controls the real 3D buffer. This works in Compatibility.
	var scale: float = 1.0
	if str(get_value("window_mode")) != "windowed":
		var target: Vector2i = window.size
		if DisplayServer.get_name() != "headless":
			target = DisplayServer.screen_get_size(window.current_screen)
		var resolution: Array = get_value("resolution")
		scale = clampf(minf(float(resolution[0]) / maxf(1.0, float(target.x)), float(resolution[1]) / maxf(1.0, float(target.y))), 0.25, 2.0)
	if window.scaling_3d_mode != Viewport.SCALING_3D_MODE_BILINEAR:
		window.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	if not is_equal_approx(window.scaling_3d_scale, scale):
		window.scaling_3d_scale = scale


func _apply_viewport(viewport: Viewport) -> void:
	var msaa: int = {0: Viewport.MSAA_DISABLED, 2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X, 8: Viewport.MSAA_8X}.get(int(get_value("msaa")), Viewport.MSAA_DISABLED)
	if viewport.msaa_3d != msaa:
		viewport.msaa_3d = msaa
	if viewport.anisotropic_filtering_level != int(get_value("anisotropic")):
		viewport.anisotropic_filtering_level = int(get_value("anisotropic"))
	var atlas_size: int = [512, 1024, 2048, 4096][int(get_value("shadows"))]
	if viewport.positional_shadow_atlas_size != atlas_size:
		viewport.positional_shadow_atlas_size = atlas_size


func _apply_native_nodes(node: Node, isolated_world: bool = false) -> void:
	if node is SubViewport:
		_apply_viewport(node)
		isolated_world = isolated_world or node.own_world_3d
	if node is Camera3D and not isolated_world:
		if not is_equal_approx(node.far, float(get_value("render_distance"))):
			node.far = float(get_value("render_distance"))
	if node is Light3D and not isolated_world:
		if not node.has_meta("settings_default_shadow"):
			node.set_meta("settings_default_shadow", node.get_meta("authored_shadow_enabled", node.shadow_enabled))
		var quality: int = int(get_value("shadows"))
		if int(node.get_meta("settings_shadow_quality", -1)) != quality:
			node.shadow_enabled = quality > 0 and bool(node.get_meta("authored_shadow_enabled", node.get_meta("settings_default_shadow")))
			node.set_meta("settings_shadow_quality", quality)
	if node is WorldEnvironment and node.environment != null and not isolated_world:
		if node.environment.fog_enabled != bool(get_value("fog")):
			node.environment.fog_enabled = bool(get_value("fog"))
	if node is GeometryInstance3D:
		_prepare_material(node.material_override)
		_prepare_material(node.material_overlay)
	if node is MeshInstance3D and node.mesh != null:
		for surface in range(node.mesh.get_surface_count()):
			_prepare_material(node.get_active_material(surface))
	elif node is MultiMeshInstance3D and node.multimesh != null and node.multimesh.mesh != null:
		for surface in range(node.multimesh.mesh.get_surface_count()):
			_prepare_material(node.multimesh.mesh.surface_get_material(surface))
	for child in node.get_children():
		_apply_native_nodes(child, isolated_world)


func _prepare_material(material: Material) -> void:
	if not material is BaseMaterial3D or _materials_seen.has(material.get_instance_id()):
		return
	_materials_seen[material.get_instance_id()] = true
	if material.albedo_texture == null and material.normal_texture == null and material.roughness_texture == null:
		return
	# The viewport's anisotropy level is ignored unless the material opts in.
	var nearest: bool = material.texture_filter in [BaseMaterial3D.TEXTURE_FILTER_NEAREST, BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS, BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC]
	var texture_filter: int = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC if nearest else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if material.texture_filter != texture_filter:
		material.texture_filter = texture_filter


func _dispatch_callbacks(node: Node) -> void:
	if node.has_method("apply_settings"):
		node.call("apply_settings", data)
	for child in node.get_children():
		_dispatch_callbacks(child)


func setting_schema() -> Array:
	if not _schema.is_empty():
		return _schema.duplicate(true)
	_schema = [
		_select("preset", "Qualidade", "graphics", [{"id": "low", "label": "Baixo"}, {"id": "medium", "label": "Médio"}, {"id": "high", "label": "Alto"}, {"id": "ultra", "label": "Ultra"}, {"id": "custom", "label": "Personalizado"}]),
		_select("resolution", "Resolução", "graphics", [{"id": [1280, 720], "label": "1280 × 720"}, {"id": [1600, 900], "label": "1600 × 900"}, {"id": [1920, 1080], "label": "1920 × 1080"}, {"id": [2560, 1440], "label": "2560 × 1440"}, {"id": [3840, 2160], "label": "3840 × 2160"}]),
		_select("window_mode", "Tela", "graphics", [{"id": "windowed", "label": "Janela"}, {"id": "borderless", "label": "Sem bordas"}, {"id": "fullscreen", "label": "Tela cheia"}]),
		_toggle("vsync", "Sincronização vertical", "graphics"),
		_select("fps_limit", "Limite de FPS", "graphics", [{"id": 0, "label": "Sem limite"}, {"id": 30, "label": "30"}, {"id": 60, "label": "60"}, {"id": 90, "label": "90"}, {"id": 120, "label": "120"}, {"id": 144, "label": "144"}, {"id": 165, "label": "165"}, {"id": 240, "label": "240"}]),
		_select("shadows", "Sombras", "graphics", [{"id": 0, "label": "Desligadas"}, {"id": 1, "label": "Baixas"}, {"id": 2, "label": "Altas"}, {"id": 3, "label": "Ultra"}]),
		_slider("render_distance", "Distância de visão", "graphics", 60, 240, 10),
		_slider("effects", "Efeitos do cenário", "graphics", 0, 1, 0.1),
		_slider("particles", "Chuva e partículas", "graphics", 0, 1, 0.1),
		_toggle("vegetation", "Vegetação", "graphics"),
		_select("msaa", "Suavização MSAA", "graphics", [{"id": 0, "label": "Desligada"}, {"id": 2, "label": "2×"}, {"id": 4, "label": "4×"}, {"id": 8, "label": "8×"}]),
		_toggle("fog", "Neblina", "graphics"),
		_select("anisotropic", "Filtro de texturas", "graphics", [{"id": 0, "label": "2×"}, {"id": 1, "label": "4×"}, {"id": 2, "label": "8×"}, {"id": 3, "label": "16×"}]),
		_slider("mouse_sensitivity", "Sensibilidade", "gameplay", 0.0005, 0.008, 0.0001),
		_slider("ads_sensitivity", "Sensibilidade ao mirar", "gameplay", 0.1, 1.5, 0.05),
		_slider("fov", "Campo de visão", "gameplay", 60, 110, 1),
		_slider("head_bob", "Balanço ao andar", "gameplay", 0, 1, 0.1),
		_slider("camera_shake", "Tremor de câmera", "gameplay", 0, 1, 0.05),
		_slider("visual_recoil", "Recuo visual", "gameplay", 0, 1, 0.1),
		_toggle("auto_sprint", "Correr automaticamente", "gameplay"),
		_toggle("toggle_aim", "Alternar mira com clique", "gameplay"),
		_toggle("toggle_sprint", "Alternar corrida", "gameplay"),
		_toggle("crosshair", "Mira central", "gameplay"),
		_toggle("hitmarkers", "Indicadores de acerto", "gameplay"),
		_toggle("damage_numbers", "Números de dano", "gameplay"),
		_slider("weapon_effects", "Efeitos das armas", "gameplay", 0, 1, 0.1),
		_slider("master", "Geral", "audio", 0, 1, 0.05),
		_slider("music", "Música", "audio", 0, 1, 0.05),
		_slider("effects_audio", "Efeitos", "audio", 0, 1, 0.05),
		_slider("weapons", "Armas", "audio", 0, 1, 0.05),
		_slider("ambient", "Ambiente", "audio", 0, 1, 0.05),
		_slider("interface", "Interface", "audio", 0, 1, 0.05),
		_slider("ui_scale", "Tamanho da interface", "accessibility", 0.8, 1.4, 0.1),
		_toggle("reduced_flashes", "Reduzir flashes", "accessibility"),
		_toggle("high_contrast", "Contraste aumentado", "accessibility"),
		_select("colorblind_mode", "Paleta de raridades", "accessibility", [{"id": "normal", "label": "Original"}, {"id": "protanopia", "label": "Protanopia"}, {"id": "deuteranopia", "label": "Deuteranopia"}, {"id": "tritanopia", "label": "Tritanopia"}]),
		{"key": "crosshair_color", "label": "Cor da mira", "category": "accessibility", "type": "color", "default": DEFAULTS.crosshair_color},
		{"key": "hitmarker_color", "label": "Cor do acerto", "category": "accessibility", "type": "color", "default": DEFAULTS.hitmarker_color},
	]
	var devices: Array = []
	for device in AudioServer.get_output_device_list():
		devices.append({"id": device, "label": "Padrão do sistema" if device == "Default" else device})
	if devices.is_empty():
		devices.append({"id": "Default", "label": "Padrão do sistema"})
	_schema.append(_select("output_device", "Saída de áudio", "audio", devices))
	return _schema.duplicate(true)


func _valid_value(key: String, value: Variant) -> bool:
	if key == "output_device":
		return value is String and value.length() <= 256
	if key == "resolution":
		if not value is Array or value.size() != 2:
			return false
		return _number(value[0]) and _number(value[1]) and float(value[0]) == floor(float(value[0])) and float(value[1]) == floor(float(value[1])) and int(value[0]) >= 960 and int(value[0]) <= 7680 and int(value[1]) >= 540 and int(value[1]) <= 4320
	for definition: Dictionary in setting_schema():
		if definition.key != key:
			continue
		match definition.type:
			"toggle":
				return value is bool
			"slider":
				return _number(value) and float(value) >= float(definition.min) and float(value) <= float(definition.max)
			"color":
				return value is String and value.length() in [6, 8] and value.is_valid_hex_number(false)
			"select":
				for option: Dictionary in definition.options:
					if option.id == value and typeof(option.id) == typeof(value):
						return true
					# JSON numbers deserialize as float, but only exact supported ints pass.
					if typeof(option.id) == TYPE_INT and _number(value) and float(option.id) == float(value):
						return true
				return false
	return false


func _read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false}
	if file.get_length() > MAX_BYTES:
		file.close()
		return {"ok": false}
	var raw: String = file.get_as_text()
	file.close()
	var json: JSON = JSON.new()
	if json.parse(raw) != OK or not json.data is Dictionary:
		return {"ok": false}
	var envelope: Dictionary = json.data
	if not _number(envelope.get("version")):
		return {"ok": false}
	if float(envelope.version) > VERSION:
		return {"ok": false, "future": true}
	if float(envelope.version) != VERSION or not envelope.get("body") is String or not envelope.get("checksum") is String:
		return {"ok": false}
	if envelope.body.sha256_text() != envelope.checksum:
		return {"ok": false}
	var body_json: JSON = JSON.new()
	if body_json.parse(envelope.body) != OK or not body_json.data is Dictionary:
		return {"ok": false}
	for key in body_json.data:
		if not key is String or not DEFAULTS.has(key) or not _valid_value(key, body_json.data[key]):
			return {"ok": false}
	return {"ok": true, "data": body_json.data}


func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


func _path() -> String:
	return storage_root.path_join("preferences.json")


func _slider(key: String, label: String, category: String, minimum: float, maximum: float, step: float) -> Dictionary:
	return {"key": key, "label": label, "category": category, "type": "slider", "default": DEFAULTS[key], "min": minimum, "max": maximum, "step": step}


func _toggle(key: String, label: String, category: String) -> Dictionary:
	return {"key": key, "label": label, "category": category, "type": "toggle", "default": DEFAULTS[key]}


func _select(key: String, label: String, category: String, options: Array) -> Dictionary:
	return {"key": key, "label": label, "category": category, "type": "select", "default": DEFAULTS[key], "options": options}

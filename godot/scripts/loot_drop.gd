class_name MeyuiLootDrop
extends Node3D

## The root remains the physical pickup/save point. Only its presentation floats.
## Geometry and materials are shared; 96 drops allocate no lights or particles.
const Loot = preload("res://data/loot_data.gd")
const Visuals = preload("res://scripts/loot_visuals.gd")
var kind := "weapon"
var payload: Dictionary = {}
var collected := false
var lifetime := 0.0
var _model: MeshInstance3D
var _pivot: Node3D
var _halo: MeshInstance3D
var _beam: MeshInstance3D
var _core: MeshInstance3D
var _badge: MeshInstance3D
var _pulse := 0.0
var _tint := Color("bec9cf")
var _base_height := 0.45
var _beam_height := 1.6
var _model_scale := 1.0
var _effects := 0.8
var _highlight := 0.0
var _highlighted := false
var _reduced_flashes := false
var _rank := 0
var _visibility_clock := 0.0
var _near := true
static var _effect_meshes: Dictionary = {}
static var _effect_materials: Dictionary = {}
static var _beam_shader: Shader

func setup(drop_kind: String, data: Dictionary) -> void:
	kind = drop_kind
	payload = data.duplicate(true)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	name = "Drop_" + kind
	var rarity := str(payload.get("rarity", "common"))
	_rank = Loot.rarity_rank(rarity)
	_tint = Loot.rarity_color(rarity)
	if kind == "ammo": _tint = Color("9ed0b7")
	if kind == "currency": _tint = Color("e8c16e")
	if kind == "powerup": _tint = Color("acdce0")
	_base_height = 0.47 if kind == "weapon" else (0.29 if kind == "ammo" else 0.36)
	_model_scale = 1.12 if kind == "weapon" else (1.45 if kind == "attachment" else 1.0)
	_beam_height = 1.30 + _rank * 0.29 if kind in ["weapon", "attachment"] else (1.3 if kind == "powerup" else 0.84)
	_pulse = float(posmod(hash(str(payload.get("uid", payload.get("id", kind)))), 1000)) * 0.01
	_pivot = Node3D.new()
	_pivot.name = "FloatingPresentation"
	_pivot.position.y = _base_height
	_pivot.rotation_degrees = Vector3(0, 22, -8 if kind == "weapon" else 0)
	_pivot.scale = Vector3.ONE * _model_scale
	add_child(_pivot)
	_model = _instance("GroundModel", Visuals.model(kind, payload), _pivot)
	_model.position = -_model.mesh.get_aabb().get_center()
	_halo = _instance("RarityHalo", _ring_mesh(), self)
	_halo.position.y = 0.012
	var radius := 0.57 if kind == "weapon" else 0.38
	_halo.scale = Vector3.ONE * radius
	_halo.material_override = _effect_material(_tint, false)
	_halo.set_meta("radius", radius)
	_beam = _instance("SoftRarityBeam", _quad_mesh(), self)
	_beam.position = Vector3(0, _beam_height * 0.5, 0)
	_beam.scale = Vector3(0.12 + _rank * 0.022, _beam_height, 1)
	_beam.material_override = _soft_beam_material(_tint)
	_core = _instance("BeamCore", _core_mesh(), self)
	_core.position.y = _beam_height * 0.5
	_core.scale = Vector3(0.008 + _rank * 0.0017, _beam_height, 0.008 + _rank * 0.0017)
	_core.material_override = _effect_material(_tint.lightened(0.22), false)
	_badge = _instance("RaritySymbol", _badge_mesh(kind, _rank), self)
	_badge.position.y = _beam_height + 0.075
	_badge.material_override = _effect_material(_tint.lightened(0.1), true)
	_badge.scale = Vector3.ONE * (0.86 if kind in ["ammo", "currency"] else 1.0)
	# Rendering detail never changes pickup amounts or weapon data.
	set_meta("visual_family", Visuals.family(payload) if kind == "weapon" else kind)
	set_meta("rarity_rank", _rank)
	_refresh_effects()

func _process(delta: float) -> void:
	lifetime += delta
	_pulse += delta
	_visibility_clock -= delta
	if _visibility_clock <= 0:
		_visibility_clock = 0.33
		var camera := get_viewport().get_camera_3d()
		_near = not is_instance_valid(camera) or global_position.distance_squared_to(camera.global_position) < 2500.0
		_refresh_effects()
	_highlight = move_toward(_highlight, 1.0 if _highlighted else 0.0, delta * 7.0)
	if not _near: return
	_pivot.position.y = _base_height + sin(_pulse * 1.55) * (0.014 if _reduced_flashes else 0.032) + _highlight * 0.04
	_pivot.rotation.y += delta * (0.19 if kind == "weapon" else 0.12)
	_pivot.scale = Vector3.ONE * _model_scale * (1.0 + _highlight * 0.055)
	_halo.scale = Vector3.ONE * float(_halo.get_meta("radius")) * (1.0 + _highlight * 0.12)
	_badge.position.y = _beam_height + 0.075 + sin(_pulse * 1.3) * 0.018

func set_highlighted(value: bool) -> void:
	_highlighted = value
	_refresh_effects()

func apply_settings(settings: Dictionary) -> void:
	_effects = clampf(float(settings.get("effects", 0.8)), 0.0, 1.0)
	_reduced_flashes = bool(settings.get("reduced_flashes", false))
	if is_instance_valid(_halo): _refresh_effects()

func _refresh_effects() -> void:
	if not is_instance_valid(_beam): return
	# Always keep the physical model, halo, and non-color rarity symbol readable.
	_beam.visible = _near and _effects > 0.2 and kind in ["weapon", "attachment", "powerup"]
	_core.visible = _near and _effects > 0.05 and (kind in ["weapon", "attachment", "powerup"] or _highlighted)
	_badge.visible = _near
	_halo.visible = _near

func visual_budget() -> Dictionary:
	var surfaces := 0
	var triangles := 0
	for node in [_model, _halo, _beam, _core, _badge]:
		if not is_instance_valid(node): continue
		surfaces += node.mesh.get_surface_count()
		triangles += Visuals.triangle_count(node.mesh)
	return {"nodes":get_child_count() + _pivot.get_child_count() + 1, "meshes":5, "surfaces":surfaces, "triangles":triangles, "lights":0, "particles":0}

func _instance(node_name: String, mesh: Mesh, parent: Node) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = 65.0
	node.visibility_range_end_margin = 4.0
	parent.add_child(node)
	return node

static func _effect_material(tint: Color, billboard: bool) -> StandardMaterial3D:
	var key := str([tint.to_html(), billboard])
	if _effect_materials.has(key): return _effect_materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = 0.85
	if billboard: material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_effect_materials[key] = material
	return material

static func _soft_beam_material(tint: Color) -> ShaderMaterial:
	var key := "beam:" + tint.to_html()
	if _effect_materials.has(key): return _effect_materials[key]
	if _beam_shader == null:
		_beam_shader = Shader.new()
		_beam_shader.code = """shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(1.0);
void vertex() {
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 horizontal = cross(up, INV_VIEW_MATRIX[3].xyz - MODEL_MATRIX[3].xyz);
	vec3 right = length(horizontal) > 0.0001 ? normalize(horizontal) : vec3(1.0, 0.0, 0.0);
	vec3 forward = normalize(cross(right, up));
	mat4 facing = mat4(vec4(right * length(MODEL_MATRIX[0].xyz), 0.0),
		vec4(up * length(MODEL_MATRIX[1].xyz), 0.0), vec4(forward, 0.0), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * facing;
}
void fragment() {
	float center = pow(max(0.0, 1.0 - abs(UV.x - 0.5) * 2.0), 2.5);
	float vertical = smoothstep(0.0, 0.22, UV.y) * (0.65 + UV.y * 0.35);
	ALBEDO = tint.rgb;
	ALPHA = center * vertical * 0.30;
}
"""
	var material := ShaderMaterial.new()
	material.shader = _beam_shader
	material.set_shader_parameter("tint", tint)
	_effect_materials[key] = material
	return material

static func _quad_mesh() -> QuadMesh:
	if not _effect_meshes.has("quad"):
		var mesh := QuadMesh.new()
		mesh.size = Vector2.ONE
		_effect_meshes["quad"] = mesh
	return _effect_meshes["quad"]

static func _core_mesh() -> CylinderMesh:
	if not _effect_meshes.has("core"):
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.25
		mesh.bottom_radius = 1.0
		mesh.height = 1.0
		mesh.radial_segments = 6
		mesh.rings = 1
		_effect_meshes["core"] = mesh
	return _effect_meshes["core"]

static func _ring_mesh() -> ArrayMesh:
	if _effect_meshes.has("ring"): return _effect_meshes["ring"]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(40):
		var a := index * TAU / 40
		var b := (index + 1) * TAU / 40
		var p := Vector3(cos(a), 0, sin(a))
		var q := Vector3(cos(b), 0, sin(b))
		_triangle(tool, p * 0.975, p, q)
		_triangle(tool, p * 0.975, q, q * 0.975)
	var mesh := tool.commit()
	_effect_meshes["ring"] = mesh
	return mesh

static func _badge_mesh(drop_kind: String, rank: int) -> ArrayMesh:
	var key := "badge:%s:%d" % [drop_kind, rank]
	if _effect_meshes.has(key): return _effect_meshes[key]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	if drop_kind == "ammo":
		for x in [-0.09, 0.0, 0.09]:
			_rect(tool, Vector2(x, -0.035), Vector2(0.055, 0.16))
			_triangle(tool, Vector3(x - 0.0275, 0.045, 0), Vector3(x, 0.11, 0), Vector3(x + 0.0275, 0.045, 0))
	elif drop_kind == "currency":
		for index in range(12):
			var a := index * TAU / 12
			var b := (index + 1) * TAU / 12
			_triangle(tool, Vector3.ZERO, Vector3(cos(a), sin(a), 0) * 0.12, Vector3(cos(b), sin(b), 0) * 0.12)
		_rect(tool, Vector2(0.15, 0), Vector2(0.025, 0.17))
	else:
		# The outline becomes a triangle, diamond, pentagon, hexagon, then stars.
		var sides := rank + 3 if rank < 4 else (10 if rank == 4 else 12)
		for index in range(sides):
			var a := -PI * 0.5 + index * TAU / sides
			var b := -PI * 0.5 + (index + 1) * TAU / sides
			var radius_a := 0.17 if rank < 4 or index % 2 == 0 else 0.095
			var radius_b := 0.17 if rank < 4 or (index + 1) % 2 == 0 else 0.095
			_line(tool, Vector2(cos(a), sin(a)) * radius_a, Vector2(cos(b), sin(b)) * radius_b, 0.014)
		for index in range(rank + 1):
			_rect(tool, Vector2((index - rank * 0.5) * 0.042, -0.23), Vector2(0.026, 0.044))
		_rect(tool, Vector2.ZERO, Vector2(0.048, 0.048))
	var mesh := tool.commit()
	_effect_meshes[key] = mesh
	return mesh

static func _triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	tool.add_vertex(a)
	tool.add_vertex(b)
	tool.add_vertex(c)

static func _rect(tool: SurfaceTool, center: Vector2, size: Vector2) -> void:
	var a := Vector3(center.x - size.x * 0.5, center.y - size.y * 0.5, 0)
	var b := Vector3(center.x + size.x * 0.5, center.y - size.y * 0.5, 0)
	var c := Vector3(center.x + size.x * 0.5, center.y + size.y * 0.5, 0)
	var d := Vector3(center.x - size.x * 0.5, center.y + size.y * 0.5, 0)
	_triangle(tool, a, b, c)
	_triangle(tool, a, c, d)

static func _line(tool: SurfaceTool, a: Vector2, b: Vector2, width: float) -> void:
	var perpendicular := (b - a).normalized().orthogonal() * width * 0.5
	var p := Vector3(a.x + perpendicular.x, a.y + perpendicular.y, 0)
	var q := Vector3(a.x - perpendicular.x, a.y - perpendicular.y, 0)
	var r := Vector3(b.x - perpendicular.x, b.y - perpendicular.y, 0)
	var s := Vector3(b.x + perpendicular.x, b.y + perpendicular.y, 0)
	_triangle(tool, p, q, r)
	_triangle(tool, p, r, s)

func export_state() -> Dictionary:
	return {"kind":kind,"payload":payload.duplicate(true),"position":[global_position.x,global_position.y,global_position.z],"lifetime":lifetime}

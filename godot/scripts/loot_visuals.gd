class_name MeyuiLootVisuals
extends RefCounted

## Ground models are batched into one material surface. No first-person arms,
## lights, animation rigs, or per-part Nodes survive the one-time mesh build.
const Loot = preload("res://data/loot_data.gd")
const Data = preload("res://data/game_data.gd")
const MAX_CACHED_MODELS := 128
static var _models: Dictionary = {}
static var _materials: Dictionary = {}
static var _primitives: Dictionary = {}
static var _batched_material: ShaderMaterial
static var _rarity_materials: Dictionary = {}

static func model(kind: String, payload: Dictionary) -> ArrayMesh:
	var signature := _signature(kind, payload)
	if _models.has(signature): return _models[signature]
	var parts: Array[Dictionary] = []
	match kind:
		"weapon": _weapon(parts, payload)
		"ammo": _ammunition(parts)
		"attachment": _attachment(parts, payload)
		"currency": _currency(parts)
		"powerup": _powerup(parts, str(payload.get("id", "")))
		_: _ammunition(parts)
	if kind == "weapon" and bool(Data.WEAPONS.get(str(payload.get("model_id","")),{}).get("legendary_only",false)): _signature_geometry(parts,payload)
	var mesh := _merge(parts, _palette(kind, payload), Loot.rarity_rank(str(payload.get("rarity","common"))) if kind == "weapon" else -1)
	if _models.size() >= MAX_CACHED_MODELS: _models.erase(_models.keys()[0])
	_models[signature] = mesh
	return mesh

static func family(payload: Dictionary) -> String:
	var id := str(payload.get("model_id", "biscuit"))
	return str(Data.WEAPONS.get(id, {}).get("family", "pistol" if id == "biscuit" else "rifle"))

static func _signature(kind: String, payload: Dictionary) -> String:
	if kind == "weapon":
		var slots: Array[String] = []
		for slot: String in Loot.SLOTS:
			slots.append(_part_id(payload, slot))
		return JSON.stringify([kind, payload.get("model_id", "biscuit"), payload.get("manufacturer", "independent"), payload.get("rarity", "common"), payload.get("element", "none"), slots])
	return JSON.stringify([kind, payload.get("id", ""), payload.get("rarity", "common")])

static func _part_id(payload: Dictionary, slot: String) -> String:
	var slots: Dictionary = payload.get("attachments", {})
	var part: Variant = slots.get(slot, {})
	return str(part.get("id", "")) if part is Dictionary else str(part)

static func _weapon(parts: Array[Dictionary], payload: Dictionary) -> void:
	var type := family(payload)
	var muzzle := 0.58
	var magazine_id := _part_id(payload, "magazine")
	var magazine_length := 0.31 * (1.3 if magazine_id == "extended_mag" else (0.8 if magazine_id == "quick_mag" else 1.0))
	if type in ["pistol", "revolver"]:
		_box(parts, Vector3(-0.1, -0.18, 0), Vector3(0.14, 0.29, 0.135), 1, -0.22)
		_box(parts, Vector3(-0.075, -0.14, 0.073), Vector3(0.105, 0.19, 0.012), 2, -0.22)
		_box(parts, Vector3(0.035, -0.07, 0), Vector3(0.30, 0.065, 0.15), 0)
		_box(parts, Vector3(0.025, -0.14, 0), Vector3(0.032, 0.095, 0.03), 3, 0.12)
		_box(parts, Vector3(0.10, -0.18, 0), Vector3(0.20, 0.025, 0.11), 0)
		if type == "revolver":
			_cylinder(parts, Vector3(-0.015, 0.01, 0), 0.105, 0.19, 0)
			_cylinder(parts, Vector3(0.23, 0.05, 0), 0.038, 0.33, 0)
			_box(parts, Vector3(0.22, 0.007, 0), Vector3(0.32, 0.06, 0.073), 2)
			for index in range(6):
				var angle := index * TAU / 6
				_cylinder(parts, Vector3(0.087, 0.01 + cos(angle) * 0.067, sin(angle) * 0.067), 0.022, 0.012, 3)
			_box(parts, Vector3(-0.14, 0.07, 0), Vector3(0.07, 0.08, 0.035), 0, -0.25)
			muzzle = 0.405
		else:
			_box(parts, Vector3(0.10, 0.028, 0), Vector3(0.44, 0.12, 0.15), 0)
			_box(parts, Vector3(0.02, 0.035, 0.078), Vector3(0.25, 0.065, 0.012), 2)
			for index in range(4):
				_box(parts, Vector3(-0.085 + index * 0.025, 0.035, 0.081), Vector3(0.009, 0.075, 0.012), 1)
			_cylinder(parts, Vector3(0.335, 0.025, 0), 0.041, 0.025, 1)
			_box(parts, Vector3(-0.07, -0.31, 0), Vector3(0.17, 0.04, 0.15), 3)
			muzzle = 0.35
		_box(parts, Vector3(-0.07, 0.12, 0), Vector3(0.03, 0.038, 0.10), 1)
		_box(parts, Vector3(muzzle - 0.035, 0.11, 0), Vector3(0.025, 0.035, 0.025), 4)
		if magazine_id == "extended_mag":
			if type == "revolver":
				_cylinder(parts, Vector3(-0.015, 0.01, 0), 0.12, 0.22, 0)
			else:
				_box(parts, Vector3(-0.065, -0.355, 0), Vector3(0.125, 0.14, 0.13), 1, -0.10)
	else:
		var long_body := type in ["rifle", "sniper", "shotgun", "lmg", "special"]
		var receiver_length := 0.49 if long_body else 0.36
		var width := 0.21 if type in ["lmg", "special"] else 0.16
		_box(parts, Vector3(-0.02, 0.01, 0), Vector3(receiver_length, 0.18, width), 0)
		_box(parts, Vector3(-0.025, 0.07, width * 0.53), Vector3(receiver_length * 0.76, 0.065, 0.018), 2)
		_box(parts, Vector3(-0.16, -0.18, 0), Vector3(0.13, 0.28, 0.13), 1, -0.25)
		_box(parts, Vector3(-0.095, -0.10, 0.091), Vector3(0.055, 0.1, 0.018), 3, 0.18)
		_box(parts, Vector3(-0.33, -0.018, 0), Vector3(0.16, 0.075, 0.09), 0)
		if type == "smg":
			_box(parts, Vector3(-0.45, 0.015, 0), Vector3(0.34, 0.045, 0.048), 0)
			_box(parts, Vector3(-0.61, -0.05, 0), Vector3(0.045, 0.19, 0.105), 1)
			_box(parts, Vector3(0.035, -0.23, 0), Vector3(0.10, magazine_length * 1.25, 0.10), 1, 0.08)
			_box(parts, Vector3(0.20, 0.012, 0), Vector3(0.23, 0.135, 0.155), 2)
			muzzle = 0.41
		elif type == "special":
			_cylinder(parts, Vector3(0.05, 0.07, 0), 0.16, 1.0, 2)
			_cylinder(parts, Vector3(-0.47, 0.07, 0), 0.18, 0.10, 0)
			_box(parts, Vector3(0.15, -0.16, 0), Vector3(0.25, 0.20, 0.16), 1)
			_box(parts, Vector3(0.04, 0.075, 0.163), Vector3(0.37, 0.035, 0.012), 3)
			muzzle = 0.60
		elif type == "experimental":
			_box(parts, Vector3(0.03, -0.20, 0), Vector3(0.24, 0.23, 0.19), 2)
			_box(parts, Vector3(0.03, -0.22, 0.10), Vector3(0.14, 0.13, 0.012), 4)
			for index in range(5):
				_cylinder(parts, Vector3(0.18 + index * 0.073, 0.03, 0), 0.095, 0.029, 4 if index % 2 else 3)
			muzzle = 0.56
		else:
			_box(parts, Vector3(-0.45, -0.04, 0), Vector3(0.36, 0.19, 0.13), 2, 0.06)
			_box(parts, Vector3(-0.63, -0.045, 0), Vector3(0.035, 0.23, 0.15), 1)
			if type == "shotgun":
				_cylinder(parts, Vector3(0.34, -0.065, 0), 0.045, 0.63, 0)
				_box(parts, Vector3(0.29, -0.05, 0), Vector3(0.30, 0.13, 0.15), 2)
				for index in range(4):
					_cylinder(parts, Vector3(-0.17 + index * 0.075, 0.01, 0.12), 0.024, 0.12, 3, false)
				muzzle = 0.82
			elif type == "lmg":
				_box(parts, Vector3(0.02, -0.25, 0), Vector3(0.32, 0.33, 0.25), 2)
				_box(parts, Vector3(-0.01, 0.25, 0), Vector3(0.29, 0.035, 0.06), 1)
				_box(parts, Vector3(0.13, 0.18, 0), Vector3(0.035, 0.17, 0.06), 1)
				for index in range(5):
					_cylinder(parts, Vector3(-0.05, -0.035 - index * 0.035, 0.14 + index * 0.039), 0.023, 0.14, 3)
				_box(parts, Vector3(0.53, -0.06, 0.095), Vector3(0.33, 0.032, 0.032), 0)
				muzzle = 0.90
			else:
				_box(parts, Vector3(0.02, -0.18, 0), Vector3(0.15, magazine_length * (0.6 if type == "sniper" else 1.0), 0.12), 1, 0.14)
				_box(parts, Vector3(0.28, -0.005, 0), Vector3(0.31, 0.13, 0.15), 2)
				if type == "sniper":
					_box(parts, Vector3(-0.38, 0.065, 0), Vector3(0.27, 0.07, 0.15), 1)
					muzzle = 1.09
				elif type == "improvised":
					for index in range(3):
						_box(parts, Vector3(0.17 + index * 0.064, 0, 0), Vector3(0.027, 0.18, 0.18), 3)
					_cylinder(parts, Vector3(0.26, 0.09, 0.08), 0.032, 0.40, 0)
					muzzle = 0.55
		var barrel_start := 0.26
		_cylinder(parts, Vector3((barrel_start + muzzle) * 0.5, 0.035, 0), 0.043 if type == "shotgun" else 0.031, muzzle - barrel_start, 0)
		_cylinder(parts, Vector3(muzzle, 0.035, 0), 0.06 if type != "special" else 0.18, 0.06, 1)
		_box(parts, Vector3(0, 0.117, 0), Vector3(0.32, 0.025, 0.075), 1)
		_box(parts, Vector3(muzzle - 0.04, 0.10, 0), Vector3(0.025, 0.075, 0.025), 0)
		_box(parts, Vector3(-0.15, 0.075, -0.10), Vector3(0.07, 0.034, 0.10), 3)
	if magazine_id in ["frost_mag", "arc_mag"]:
		_box(parts, Vector3(0.02, -0.18, 0.076), Vector3(0.1, 0.16, 0.012), 4)
	var optic := _part_id(payload, "sight")
	if type == "sniper" and optic.is_empty(): optic = "scope"
	if not optic.is_empty(): _optic(parts, optic, Vector3(0, 0.21, 0))
	var barrel := _part_id(payload, "barrel")
	if not barrel.is_empty():
		var length := 0.22 if barrel in ["suppressor", "long_barrel"] else 0.085
		_cylinder(parts, Vector3(muzzle + length * 0.5, 0.035, 0), 0.064 if barrel == "suppressor" else 0.046, length, 3 if barrel == "ember_barrel" else 1)
	var underbarrel := _part_id(payload, "underbarrel")
	if underbarrel == "laser":
		_box(parts, Vector3(0.29, -0.065, 0.11), Vector3(0.14, 0.055, 0.055), 1)
		_cylinder(parts, Vector3(0.366, -0.065, 0.11), 0.019, 0.01, 4)
	elif not underbarrel.is_empty():
		_box(parts, Vector3(0.28, -0.17, 0), Vector3(0.09, 0.24 if underbarrel == "grip" else 0.13, 0.09), 1)
	if not _part_id(payload, "internal").is_empty():
		_box(parts, Vector3(-0.04, 0.015, 0.105), Vector3(0.16, 0.085, 0.016), 3)
	if str(payload.get("element", "none")) != "none":
		_box(parts, Vector3(0.10, 0.045, 0.107), Vector3(0.13, 0.018, 0.013), 4)

static func _optic(parts: Array[Dictionary], id: String, at: Vector3) -> void:
	_box(parts, at + Vector3(0, -0.10, 0), Vector3(0.14, 0.08, 0.065), 1)
	if id in ["scope", "hybrid"]:
		_cylinder(parts, at, 0.065, 0.32, 1)
		_cylinder(parts, at + Vector3(0.14, 0, 0), 0.079, 0.055, 0)
		_cylinder(parts, at + Vector3(0.169, 0, 0), 0.057, 0.008, 4)
	else:
		_box(parts, at + Vector3(0, 0.065, 0), Vector3(0.065, 0.022, 0.15), 0)
		for z in [-0.07, 0.07]:
			_box(parts, at + Vector3(0, 0.01, z), Vector3(0.065, 0.13, 0.019), 0)
		_box(parts, at + Vector3(0.02, -0.03, 0), Vector3(0.017, 0.025, 0.021), 4)

static func _ammunition(parts: Array[Dictionary]) -> void:
	# Open olive box, black interior, brass latch and oversized visible cartridges.
	_box(parts, Vector3(0, -0.045, 0), Vector3(0.67, 0.11, 0.42), 2)
	_box(parts, Vector3(0, 0.012, 0), Vector3(0.59, 0.016, 0.35), 1)
	_box(parts, Vector3(0, 0.055, 0.20), Vector3(0.67, 0.17, 0.035), 2)
	for x in [-0.32, 0.32]: _box(parts, Vector3(x, 0.055, 0), Vector3(0.035, 0.17, 0.42), 2)
	_box(parts, Vector3(0, 0.15, -0.21), Vector3(0.67, 0.38, 0.035), 2, 0.0)
	_box(parts, Vector3(0, 0.15, -0.187), Vector3(0.53, 0.25, 0.008), 1)
	_box(parts, Vector3(0, 0.057, 0.225), Vector3(0.085, 0.07, 0.018), 3)
	for row in range(2):
		for column in range(4):
			var at := Vector3(-0.23 + column * 0.152, 0.13, -0.075 + row * 0.17)
			_cylinder(parts, at, 0.046, 0.21, 3, false)
			_cylinder(parts, at + Vector3(0, -0.091, 0), 0.052, 0.025, 0, false)
			_cylinder(parts, at + Vector3(0, 0.155, 0), 0.037, 0.10, 3, false, 0.007)
	# Cartridge pictogram on the front face, visible even at a grazing angle.
	for x in [-0.085, 0, 0.085]:
		_box(parts, Vector3(x, 0.055, 0.222), Vector3(0.036, 0.087, 0.009), 4)

static func _attachment(parts: Array[Dictionary], payload: Dictionary) -> void:
	var id := str(payload.get("id", "red_dot"))
	var slot := str(Loot.ATTACHMENTS.get(id, {}).get("slot", "sight"))
	match slot:
		"sight": _optic(parts, id, Vector3.ZERO)
		"barrel":
			_cylinder(parts, Vector3.ZERO, 0.10, 0.43, 0)
			_cylinder(parts, Vector3(0.23, 0, 0), 0.065, 0.018, 1)
			for x in [-0.16, 0.12]: _cylinder(parts, Vector3(x, 0, 0), 0.107, 0.035, 3)
		"magazine":
			_box(parts, Vector3.ZERO, Vector3(0.24, 0.39, 0.14), 0, 0.12)
			for x in [-0.07, 0.01, 0.09]: _cylinder(parts, Vector3(x, 0.22, 0), 0.035, 0.11, 3, false)
			_box(parts, Vector3(0.02, -0.1, 0.075), Vector3(0.16, 0.04, 0.012), 4)
		"underbarrel":
			_box(parts, Vector3.ZERO, Vector3(0.12, 0.31, 0.12), 1, 0.12)
			_box(parts, Vector3(0, 0.17, 0), Vector3(0.24, 0.045, 0.17), 0)
			_box(parts, Vector3(0, 0, 0.071), Vector3(0.065, 0.14, 0.01), 3)
		"internal":
			_box(parts, Vector3.ZERO, Vector3(0.36, 0.20, 0.065), 0)
			for x in [-0.1, 0, 0.1]:
				_box(parts, Vector3(x, 0, 0.04), Vector3(0.052, 0.10, 0.021), 4)
			_box(parts, Vector3(0, -0.13, 0), Vector3(0.31, 0.06, 0.038), 3)

static func _currency(parts: Array[Dictionary]) -> void:
	for index in range(4):
		_cylinder(parts, Vector3(-0.13 + index * 0.08, index * 0.033, 0), 0.16, 0.028, 3, false)
	_box(parts, Vector3(0.11, 0.105, 0.015), Vector3(0.15, 0.018, 0.043), 4)

static func _powerup(parts: Array[Dictionary], id: String) -> void:
	# A diamond battery has a separate readable silhouette from ammo and parts.
	_box(parts, Vector3.ZERO, Vector3(0.29, 0.29, 0.14), 0, PI / 4)
	_box(parts, Vector3(0, 0, 0.085), Vector3(0.20, 0.20, 0.018), 4, PI / 4)
	if id in ["infinite_ammo", "double_damage"]:
		for x in [-0.055, 0.055]: _cylinder(parts, Vector3(x, 0, 0.10), 0.025, 0.20, 3, false)
	elif id == "jackpot": _cylinder(parts, Vector3(0, 0, 0.12), 0.10, 0.028, 3, false)
	else:
		_box(parts, Vector3(0, 0, 0.11), Vector3(0.045, 0.21, 0.015), 1, -0.28)

static func _box(parts: Array[Dictionary], at: Vector3, size: Vector3, surface: int, angle: float = 0.0) -> void:
	var key := "b" + str(size)
	if not _primitives.has(key):
		var mesh: Mesh
		if minf(size.x, minf(size.y, size.z)) > 0.04:
			mesh = preload("res://scripts/weapon_geometry.gd").chamfer_box(size)
		else:
			# Thin seams and cartridge labels do not benefit from bevel geometry.
			var plate := BoxMesh.new()
			plate.size = size
			mesh = plate
		_primitives[key] = mesh
	parts.append({"mesh":_primitives[key], "transform":Transform3D(Basis(Vector3.FORWARD, angle), at), "surface":surface})

static func _cylinder(parts: Array[Dictionary], at: Vector3, radius: float, height: float, surface: int, horizontal: bool = true, tip: float = -1.0) -> void:
	var key := "c" + str([radius, height, tip])
	if not _primitives.has(key):
		var mesh := CylinderMesh.new()
		mesh.top_radius = radius if tip < 0 else tip
		mesh.bottom_radius = radius
		mesh.height = height
		mesh.radial_segments = 8
		mesh.rings = 1
		_primitives[key] = mesh
	parts.append({"mesh":_primitives[key], "transform":Transform3D(Basis(Vector3.FORWARD, PI * 0.5) if horizontal else Basis.IDENTITY, at), "surface":surface})

static func _signature_geometry(parts: Array[Dictionary], payload: Dictionary) -> void:
	# Sculpt the receiver without losing the fitted optic/barrel/grip geometry.
	for part: Dictionary in parts:
		var size: Vector3 = part.mesh.get_aabb().size
		if size.x > 0.28 and size.y > 0.10 and size.z > 0.10 and part.mesh is ArrayMesh:
			var shell := SphereMesh.new()
			shell.radius = 0.5
			shell.height = 1
			shell.radial_segments = 12
			shell.rings = 6
			part.mesh = shell
			part.transform.basis = part.transform.basis.scaled(size * Vector3(1.1,1.25,1.2))
	var id: String = payload.model_id
	if id == "tidecaller":
		for z: float in [-0.13,0.13]: _cylinder(parts,Vector3(0.33,0.035,z),0.035,0.48,4)
	elif id == "night_express":
		var drum := CylinderMesh.new()
		drum.top_radius = 0.18
		drum.bottom_radius = 0.18
		drum.height = 0.22
		drum.radial_segments = 16
		parts.append({"mesh":drum,"transform":Transform3D(Basis(Vector3.RIGHT,PI/2),Vector3(0.02,-0.16,0)),"surface":3})
	else:
		for z: float in [-0.11,0.11]: _cylinder(parts,Vector3(0.45,0.065,z),0.022,0.54,4)

static func _merge(parts: Array[Dictionary], palette: Array[Material], rarity: int = -1) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part: Dictionary in parts:
		var material: StandardMaterial3D = palette[int(part.surface)]
		var paint := material.albedo_color
		# Alpha is a material channel, not transparency: 1 marks a luminous insert.
		paint.a = 1.0 if int(part.surface) == 4 else material.metallic
		var arrays: Array = part.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var transform: Transform3D = part.transform
		tool.set_color(paint)
		for index in indices:
			tool.set_normal(transform.basis * normals[index])
			tool.add_vertex(transform * vertices[index])
	tool.index()
	if not _rarity_materials.has(rarity):
		var material: ShaderMaterial = _ground_material().duplicate()
		material.set_shader_parameter("rarity_glow", 0.70 if rarity == 5 else 0.45 if rarity == 4 else 0.12 if rarity >= 0 else 0.0)
		_rarity_materials[rarity] = material
	tool.set_material(_rarity_materials[rarity])
	return tool.commit()

static func _ground_material() -> ShaderMaterial:
	if _batched_material != null: return _batched_material
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform float rarity_glow = 0.0;
void fragment() {
	ALBEDO = COLOR.rgb;
	METALLIC = min(COLOR.a, 0.8);
	ROUGHNESS = mix(0.68, 0.38, COLOR.a);
	float rim = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)),0.0),2.5);
	EMISSION = COLOR.rgb * (mix(0.12, 0.68, step(0.95, COLOR.a)) + rarity_glow * (0.4 + rim * 2.5));
}
"""
	_batched_material = ShaderMaterial.new()
	_batched_material.shader = shader
	return _batched_material

static func _palette(kind: String, payload: Dictionary) -> Array[Material]:
	var rarity := str(payload.get("rarity", "common"))
	var accent := Loot.rarity_color(rarity)
	var maker: Dictionary = Loot.MANUFACTURERS.get(str(payload.get("manufacturer", "")), {})
	var stock := Color(str(maker.get("color", "9aa594"))).darkened(0.2)
	if kind == "ammo":
		stock = Color("647e64")
		accent = Color("e8c78b")
	if kind == "currency": accent = Color("edc36f")
	if kind == "powerup": accent = Color("afd9d1")
	var element := str(payload.get("element", "none"))
	if element != "none": accent = {"fire":Color("ebae6d"),"shock":Color("98d3e5"),"cryo":Color("c4e5e6"),"corrosive":Color("b4cb7b"),"explosive":Color("e6b882")}.get(element, accent)
	return [material(Color("809296"), 0.65), material(Color("27383e"), 0.12), material(stock, 0.28), material(Color("d4ac66"), 0.72), material(accent, 0.3, true)]

static func material(color: Color, metallic: float = 0.0, glow: bool = false) -> StandardMaterial3D:
	var key := str([color.to_html(), metallic, glow])
	if _materials.has(key): return _materials[key]
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.metallic = metallic
	result.roughness = 0.42 if metallic > 0.5 else 0.62
	result.emission_enabled = true
	result.emission = color
	result.emission_energy_multiplier = 0.72 if glow else 0.19
	if glow: result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_materials[key] = result
	return result

static func cache_stats() -> Dictionary:
	return {"models":_models.size(),"materials":_materials.size(),"primitives":_primitives.size(),"model_limit":MAX_CACHED_MODELS}

static func triangle_count(mesh: Mesh) -> int:
	var total := 0
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		total += indices.size() / 3 if indices is PackedInt32Array and not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size() / 3
	return total

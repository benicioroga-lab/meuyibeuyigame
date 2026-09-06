extends Node3D
class_name MeyuiWeaponView
const Geometry = preload("res://scripts/weapon_geometry.gd")
var support_hand: MeshInstance3D
var reload_was_empty := false

## A bounded, reusable first-person rig: no particles or nodes are allocated per shot.
var weapon_id: String = "biscuit"
var model: Node3D
var muzzle: Marker3D
var flash: MeshInstance3D
var flash_light: OmniLight3D
var magazine_mesh: MeshInstance3D
var slide: MeshInstance3D
var _recoil: float = 0.0
var _flash_time: float = 0.0
var _equip_time: float = 0.0
var _last_reload: bool = false
var family: String = "pistol"
var _visual_recoil: float = 1.0
var _effect_strength: float = 1.0
var _reduced_flashes: bool = false
var _inspect_remaining: float = 0.0
var _sight_height: float = 0.12
var _weight: float = 1.0
var _element_nodes: Array[MeshInstance3D] = []
var _clock: float = 0.0


func _material(color: Color, metallic: float = 0.0, emission: bool = false) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = 0.55
	if emission:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 2.0
	return mat

func _signature_shell(id: String) -> void:
	for piece: String in ["Receiver","ColoredUpper","Stock","LongForestock"]:
		if model.has_node(piece): model.get_node(piece).hide()
	var color: Color = {"tidecaller":Color("417f8b"),"night_express":Color("a68449"),"final_frame":Color("665d8b")}[id]
	_shell("SculptedReceiver",Vector3(0,0.015,-0.23),Vector3(0.115,0.115,0.29),color)
	_shell("ErgonomicStock",Vector3(0,-0.035,0.15),Vector3(0.075,0.13,0.22),Color("27343e"))
	if id == "tidecaller":
		for side: float in [-1,1]:
			_shell("InductorFork",Vector3(side*0.10,0.03,-0.55),Vector3(0.035,0.06,0.22),Color("516978"))
		for i: int in range(3): _energy_ring(Vector3(0,0.03,-0.4-i*0.095),0.092,Color("7acfe3"))
		_shell("PressureCell",Vector3(0,-0.11,-0.22),Vector3(0.10,0.13,0.12),Color("81abb3"))
	elif id == "night_express":
		_shell("StreamlinedShroud",Vector3(0,0.02,-0.47),Vector3(0.085,0.078,0.18),color)
		var drum := CylinderMesh.new()
		drum.top_radius = 0.13
		drum.bottom_radius = 0.13
		drum.height = 0.18
		drum.radial_segments = 24
		magazine_mesh.mesh = drum
		magazine_mesh.rotation.z = PI/2
		magazine_mesh.scale = Vector3.ONE
		for i: int in range(4):
			var fin := _barrel("HeatSink",Vector3(0,0.025,-0.42-i*0.04),0.08,0.01,Color("e3be78"))
			fin.material_override = _material(Color("cc8b44"),0.5)
	else:
		_shell("LensSpine",Vector3(0,-0.02,-0.51),Vector3(0.08,0.075,0.35),color)
		_energy_ring(Vector3(0,0.23,-0.42),0.078,Color("c1b9f5"))
		for side: float in [-1,1]:
			_shell("FloatingFrame",Vector3(side*0.095,0.03,-0.46),Vector3(0.025,0.033,0.24),Color("9894b9"))
		_barrel("LensMuzzleCrown",Vector3(0,0.03,-1.06),0.058,0.1,Color("9c98b3"))

func _shell(label: String, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	var mesh := SphereMesh.new()
	mesh.radius = 1
	mesh.height = 2
	mesh.radial_segments = 24
	mesh.rings = 12
	node.mesh = mesh
	node.position = at
	node.scale = size
	node.material_override = _material(color,0.65)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.ignore_occlusion_culling = true
	model.add_child(node)
	return node

func _energy_ring(at: Vector3, radius: float, color: Color) -> void:
	var node := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius-0.01
	mesh.outer_radius = radius+0.01
	mesh.rings = 24
	mesh.ring_segments = 6
	node.mesh = mesh
	node.position = at
	node.rotation.x = PI/2
	node.material_override = _material(color,0.3,true)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.ignore_occlusion_culling = true
	model.add_child(node)
	_element_nodes.append(node)


func _box(part_name: String, pos: Vector3, size: Vector3, color: Color, metallic: float = 0.0, parent: Node3D = null) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = part_name
	node.mesh = Geometry.chamfer_box(size)
	node.ignore_occlusion_culling = true
	node.position = pos
	node.material_override = _material(color, metallic)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent != null else model).add_child(node)
	return node


func _barrel(part_name: String, pos: Vector3, radius: float, length: float, color: Color) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = part_name
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 24
	node.mesh = mesh
	node.rotation.x = PI * 0.5
	node.position = pos
	node.material_override = _material(color, 0.65)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(node)
	return node


func set_weapon(id: String, stats: Dictionary) -> void:
	weapon_id = id
	family = str(stats.get("family", "pistol" if id == "biscuit" else "rifle"))
	_weight = float(stats.get("weight", 1.0))
	_element_nodes.clear()
	if is_instance_valid(model):
		remove_child(model)
		model.queue_free()
	model = Node3D.new()
	model.name = "%sModel" % id.capitalize()
	add_child(model)
	slide = null
	magazine_mesh = null
	var accent: Color = Color(stats.get("color", Color("eab96f"))).lerp(Color("586773"), 0.65)
	var steel: Color = Color("34404b")
	var black: Color = Color("141b23")
	var brass: Color = Color("d7b974")
	var muzzle_z: float = -0.46
	_sight_height = 0.12 if id == "biscuit" else 0.18
	if id == "biscuit":
		slide = _box("ReciprocatingSlide", Vector3(0.0, 0.035, -0.23), Vector3(0.14, 0.125, 0.38), accent, 0.45)
		_box("Receiver", Vector3(0.0, -0.055, -0.18), Vector3(0.12, 0.07, 0.32), steel, 0.55)
		_box("PistolGrip", Vector3(0.0, -0.18, -0.055), Vector3(0.115, 0.22, 0.13), black).rotation.x = -0.18
		magazine_mesh = _box("Magazine", Vector3(0.0, -0.29, -0.035), Vector3(0.12, 0.045, 0.135), brass, 0.3)
		_barrel("Barrel", Vector3(0.0, 0.03, -0.39), 0.038, 0.14, steel)
		_box("RearSightLeft", Vector3(-0.046, 0.114, -0.08), Vector3(0.023, 0.048, 0.045), black)
		_box("RearSightRight", Vector3(0.046, 0.114, -0.08), Vector3(0.023, 0.048, 0.045), black)
		_box("FrontSight", Vector3(0.0, 0.112, -0.405), Vector3(0.026, 0.038, 0.029), Color("9dd9bd"))
	elif id == "boardwalk":
		_box("Receiver", Vector3(0.0, 0.0, -0.20), Vector3(0.155, 0.18, 0.43), steel, 0.65)
		_box("WoodenStock", Vector3(0.0, -0.04, 0.11), Vector3(0.13, 0.20, 0.34), accent)
		_box("Handguard", Vector3(0.0, 0.0, -0.47), Vector3(0.15, 0.14, 0.30), accent)
		for index: int in range(4):
			_box("CoolingBand%d" % index, Vector3(0.0, 0.0, -0.38 - float(index) * 0.06), Vector3(0.161, 0.15, 0.015), steel, 0.5)
		_barrel("RifleBarrel", Vector3(0.0, 0.03, -0.70), 0.031, 0.35, black)
		magazine_mesh = _box("Magazine", Vector3(0.0, -0.20, -0.25), Vector3(0.105, 0.26, 0.16), black, 0.6)
		magazine_mesh.rotation.x = 0.10
		_box("Grip", Vector3(0.0, -0.20, -0.025), Vector3(0.10, 0.20, 0.13), black).rotation.x = -0.2
		slide = _box("ChargingHandle", Vector3(0.105, 0.045, -0.15), Vector3(0.095, 0.035, 0.045), brass, 0.6)
		_box("SightBase", Vector3(0.0, 0.12, -0.15), Vector3(0.13, 0.035, 0.15), black)
		_box("SightLeft", Vector3(-0.055, 0.18, -0.16), Vector3(0.022, 0.11, 0.055), black)
		_box("SightRight", Vector3(0.055, 0.18, -0.16), Vector3(0.022, 0.11, 0.055), black)
		_box("SightTop", Vector3(0.0, 0.235, -0.16), Vector3(0.13, 0.021, 0.055), black)
		_box("FrontSight", Vector3(0.0, 0.10, -0.78), Vector3(0.026, 0.10, 0.034), accent)
		muzzle_z = -0.89
	elif id == "hammer":
		_box("HeavyReceiver", Vector3(0.0, 0.0, -0.24), Vector3(0.24, 0.22, 0.52), accent, 0.3)
		_box("UpperRail", Vector3(0.0, 0.13, -0.23), Vector3(0.16, 0.045, 0.40), black, 0.6)
		_barrel("HeavyBarrel", Vector3(0.0, 0.025, -0.59), 0.077, 0.45, steel)
		_barrel("MuzzleBrake", Vector3(0.0, 0.025, -0.80), 0.096, 0.10, black)
		_box("Stock", Vector3(0.0, -0.06, 0.12), Vector3(0.19, 0.20, 0.32), steel)
		_box("Grip", Vector3(0.0, -0.23, -0.01), Vector3(0.14, 0.25, 0.15), black).rotation.x = -0.18
		magazine_mesh = _box("Magazine", Vector3(0.0, -0.23, -0.32), Vector3(0.19, 0.26, 0.24), steel, 0.6)
		for index: int in range(3):
			_box("Shell%d" % index, Vector3(0.135, 0.025, -0.13 - float(index) * 0.09), Vector3(0.035, 0.13, 0.047), brass, 0.6)
		slide = _box("Bolt", Vector3(0.155, 0.06, -0.08), Vector3(0.095, 0.045, 0.06), black, 0.6)
		_box("RearSight", Vector3(0.0, 0.18, -0.08), Vector3(0.15, 0.06, 0.04), steel)
		_box("FrontSight", Vector3(0.0, 0.165, -0.73), Vector3(0.032, 0.12, 0.042), brass)
		muzzle_z = -0.86
	else:
		var length: float = 0.42
		var width: float = 0.16
		if family == "smg":
			length = 0.32
		elif family in ["lmg", "special"]:
			width = 0.25
		_box("Receiver", Vector3(0.0, 0.0, -0.21), Vector3(width, 0.18, length), steel, 0.55)
		_box("ColoredUpper", Vector3(0.0, 0.075, -0.24), Vector3(width + 0.012, 0.055, length * 0.83), accent, 0.35)
		_box("Grip", Vector3(0.0, -0.20, -0.02), Vector3(0.11, 0.22, 0.14), black).rotation.x = -0.2
		slide = _box("ChargingHandle", Vector3(width * 0.65, 0.01, -0.10), Vector3(0.11, 0.038, 0.05), brass, 0.6)
		_box("Stock", Vector3(0.0, -0.04, 0.12), Vector3(0.12, 0.18, 0.29), accent)
		magazine_mesh = _box("Magazine", Vector3(0.0, -0.23, -0.23), Vector3(0.11, 0.30, 0.16), black, 0.4)
		_barrel("Barrel", Vector3(0.0, 0.03, -0.56), 0.035, 0.40, black)
		muzzle_z = -0.79
		match family:
			"smg":
				muzzle_z = -0.64
				model.get_node("Barrel").scale.y = 0.65
				model.get_node("Barrel").position.z = -0.48
				_box("FoldingStockArm", Vector3(0.0, 0.03, 0.24), Vector3(0.055, 0.04, 0.44), steel)
				_box("FoldingStockPad", Vector3(0.0, -0.04, 0.43), Vector3(0.11, 0.20, 0.035), black)
				magazine_mesh.scale = Vector3(0.8, 1.25, 0.72)
				magazine_mesh.rotation.x = 0.12
			"sniper":
				muzzle_z = -1.13
				model.get_node("Barrel").scale.y = 1.7
				model.get_node("Barrel").position.z = -0.78
				_box("LongForestock", Vector3(0.0, -0.035, -0.58), Vector3(0.14, 0.10, 0.45), accent)
				magazine_mesh.scale.y = 0.55
				_box("CheekRest", Vector3(0.0, 0.10, 0.08), Vector3(0.16, 0.12, 0.26), black)
				_scope("FactoryScope", Vector3(0.0, 0.23, -0.25), steel)
				_sight_height = 0.23
			"shotgun":
				muzzle_z = -0.99
				model.get_node("Barrel").position.z = -0.70
				model.get_node("Barrel").scale.y = 1.4
				_barrel("MagazineTube", Vector3(0.0, -0.065, -0.63), 0.046, 0.61, steel)
				_box("PumpForearm", Vector3(0.0, -0.045, -0.55), Vector3(0.16, 0.13, 0.26), accent)
				magazine_mesh.visible = false
				for index: int in range(4):
					_box("SideShell%d" % index, Vector3(0.11, 0.0, -0.12 - index * 0.07), Vector3(0.035, 0.13, 0.045), brass, 0.3)
			"lmg":
				muzzle_z = -1.04
				model.get_node("Barrel").scale.y = 1.65
				model.get_node("Barrel").position.z = -0.71
				magazine_mesh.scale = Vector3(1.8, 0.9, 1.5)
				_box("CarryHandleTop", Vector3(0.0, 0.25, -0.26), Vector3(0.055, 0.035, 0.30), black)
				_box("CarryHandlePost", Vector3(0.0, 0.17, -0.40), Vector3(0.055, 0.17, 0.04), black)
				for index: int in range(5):
					_box("AmmoBelt%d" % index, Vector3(-0.16 - index * 0.032, -0.01 - index * 0.021, -0.20), Vector3(0.031, 0.04, 0.13), brass, 0.65)
				_box("FoldedBipod", Vector3(0.08, -0.075, -0.75), Vector3(0.035, 0.04, 0.36), steel)
			"improvised":
				_box("RepairPlate", Vector3(0.092, 0.01, -0.24), Vector3(0.025, 0.15, 0.26), Color("aa7350"), 0.2).rotation.x = 0.13
				for index: int in range(3):
					_box("Tape%d" % index, Vector3(0.0, -0.02, -0.39 - index * 0.055), Vector3(0.18, 0.20, 0.025), Color("a9b9aa"))
				_barrel("ExhaustPipe", Vector3(0.095, 0.07, -0.50), 0.025, 0.23, brass)
			"experimental":
				magazine_mesh.scale = Vector3(1.4, 0.8, 1.25)
				for index: int in range(5):
					var coil: MeshInstance3D = _barrel("InductionCoil%d" % index, Vector3(0.0, 0.03, -0.40 - index * 0.065), 0.085, 0.032, Color("95d7f0"))
					coil.material_override = _material(Color("7fd4f4"), 0.1, true)
					_element_nodes.append(coil)
				_box("BatteryCore", Vector3(0.0, -0.18, -0.20), Vector3(0.13, 0.16, 0.15), Color("a6dded"))
			"special":
				muzzle_z = -0.92
				_barrel("LauncherTube", Vector3(0.0, 0.025, -0.38), 0.135, 1.0, accent)
				_barrel("MuzzleRing", Vector3(0.0, 0.025, -0.88), 0.16, 0.09, steel)
				_box("WarningStripe", Vector3(0.14, 0.05, -0.28), Vector3(0.012, 0.05, 0.26), brass)
				magazine_mesh.scale.y = 0.75
				_sight_height = 0.24
		_box("FrontSight", Vector3(0.0, _sight_height, muzzle_z + 0.12), Vector3(0.025, 0.035, 0.035), brass)
		_box("RearSightLeft", Vector3(-0.044, _sight_height, -0.10), Vector3(0.022, 0.048, 0.04), black)
		_box("RearSightRight", Vector3(0.044, _sight_height, -0.10), Vector3(0.022, 0.048, 0.04), black)
	var attachments: Dictionary = stats.get("attachments", {})
	if id in ["tidecaller","night_express","final_frame"]: _signature_shell(id)
	muzzle_z = _add_attachments(attachments, muzzle_z, steel, accent)
	var element: String = str(stats.get("element", "none"))
	if element != "none":
		var glow: Color = {"fire": Color("f0ad68"), "shock": Color("97d8f2"), "cryo": Color("b5dbe8"), "corrosive": Color("acd677"), "explosive": Color("e8b788")}.get(element, accent)
		var indicator: MeshInstance3D = _box("ElementIndicator", Vector3(0.09, 0.06, -0.19), Vector3(0.017, 0.033, 0.12), glow)
		indicator.material_override = _material(glow, 0.0, true)
		_element_nodes.append(indicator)
	# Paws keep the rig tied visually to the dachshund protagonist.
	_box("TriggerPaw", Vector3(0.055, -0.20, 0.02), Vector3(0.15, 0.14, 0.19), Color("b87545"))
	_box("TealSleeve", Vector3(0.085, -0.26, 0.17), Vector3(0.17, 0.15, 0.25), Color("477e77"))
	support_hand = _box("SupportPaw", Vector3(-0.035, -0.15, -0.38 if id != "biscuit" else -0.035), Vector3(0.15, 0.115, 0.17), Color("8c664d"))
	support_hand.set_meta("rest_position", support_hand.position)
	# Machined side panels, slide serrations and grip ribs catch the local lights.
	for side: float in [-1.0, 1.0]:
		_box("RecessedEjectionPort", Vector3(side * 0.073, 0.038, -0.18), Vector3(0.009, 0.045, 0.092), black, 0.2)
		_box("SerialInlay", Vector3(side * 0.079, -0.008, -0.28), Vector3(0.008, 0.012, 0.075), Color("a3afad"), 0.6)
		for rib: int in range(6):
			_box("SlideSerration", Vector3(side * 0.074, 0.055, -0.12 + rib * 0.013), Vector3(0.008, 0.052, 0.006), black)
		for rib: int in range(5):
			_box("GripStipple", Vector3(side * 0.060, -0.135 - rib * 0.023, -0.04), Vector3(0.009, 0.008, 0.085), Color("35404a"))
		if family not in ["pistol", "revolver"]:
			for vent: int in range(5):
				_box("MlokVent", Vector3(side * 0.076, 0.005, -0.38 - vent * 0.038), Vector3(0.008, 0.029, 0.024), black)
	muzzle = Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0.0, 0.03, muzzle_z)
	model.add_child(muzzle)
	flash = MeshInstance3D.new()
	flash.name = "MuzzleFlash"
	var flash_mesh: SphereMesh = SphereMesh.new()
	flash_mesh.radius = 0.055
	flash_mesh.height = 0.19
	flash_mesh.radial_segments = 8
	flash_mesh.rings = 4
	flash.mesh = flash_mesh
	flash.rotation.x = PI * 0.5
	flash.position.z = -0.055
	flash.material_override = _material(Color("ffe1a0"), 0.0, true)
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.visible = false
	muzzle.add_child(flash)
	flash_light = OmniLight3D.new()
	flash_light.name = "MuzzleLight"
	flash_light.light_color = Color("ffd58e")
	var shot_tint: Color = {"shock":Color("90d4ec"),"fire":Color("ffc38a"),"cryo":Color("b7c8f1"),"corrosive":Color("a7dd91")}.get(element,Color("ffe1a0"))
	flash.material_override = _material(shot_tint,0,true)
	flash_light.light_color = shot_tint
	flash_light.omni_range = 3.0
	flash_light.light_energy = 1.7
	flash_light.shadow_enabled = false
	flash_light.visible = false
	muzzle.add_child(flash_light)
	_equip_time = 0.32
	_recoil = 0.0
	_flash_time = 0.0
	position = Vector3(0.25, -0.26, -0.34)
	if is_instance_valid(magazine_mesh):
		magazine_mesh.set_meta("rest_position", magazine_mesh.position)
		magazine_mesh.set_meta("rest_rotation", magazine_mesh.rotation)
		magazine_mesh.set_meta("rest_visible", magazine_mesh.visible)
	if is_instance_valid(slide):
		slide.set_meta("rest_position", slide.position)


func _scope(part_name: String, pos: Vector3, color: Color) -> void:
	_box(part_name + "Mount", pos + Vector3(0.0, -0.075, 0.0), Vector3(0.08, 0.12, 0.15), color)
	for index: int in range(2):
		var ring_node: MeshInstance3D = MeshInstance3D.new()
		ring_node.name = part_name + "Ring%d" % index
		var ring: TorusMesh = TorusMesh.new()
		ring.inner_radius = 0.044
		ring.outer_radius = 0.060
		ring.rings = 12
		ring.ring_segments = 8
		ring_node.mesh = ring
		ring_node.rotation.x = PI * 0.5
		ring_node.position = pos + Vector3(0.0, 0.0, -0.10 if index == 0 else 0.10)
		ring_node.material_override = _material(color, 0.5)
		model.add_child(ring_node)
	_box(part_name + "SideLeft", pos + Vector3(-0.055, 0.0, 0.0), Vector3(0.017, 0.045, 0.22), color)
	_box(part_name + "SideRight", pos + Vector3(0.055, 0.0, 0.0), Vector3(0.017, 0.045, 0.22), color)


func _add_attachments(attachments: Dictionary, muzzle_z: float, steel: Color, accent: Color) -> float:
	for slot: String in attachments:
		var value: Variant = attachments[slot]
		var id: String = str(value.get("id", "")) if value is Dictionary else str(value)
		match slot:
			"sight":
				for child: Node in model.get_children():
					if "Sight" in child.name or "Scope" in child.name:
						model.remove_child(child)
						child.queue_free()
				_sight_height = 0.20 if id not in ["scope", "hybrid"] else 0.23
				if id in ["scope", "hybrid"]:
					_scope("AttachmentScope", Vector3(0.0, _sight_height, -0.20), steel)
				else:
					_box("OpticLeft", Vector3(-0.055, _sight_height, -0.19), Vector3(0.022, 0.10, 0.065), steel)
					_box("OpticRight", Vector3(0.055, _sight_height, -0.19), Vector3(0.022, 0.10, 0.065), steel)
					_box("OpticTop", Vector3(0.0, _sight_height + 0.05, -0.19), Vector3(0.13, 0.022, 0.065), steel)
					var dot := _box("OpticReticle",Vector3(0,_sight_height,-0.215),Vector3(0.006,0.006,0.006),Color("c2efd4"))
					dot.material_override = _material(Color("c2efd4"),0,true)
			"barrel":
				var extension: float = 0.20 if id in ["suppressor", "long_barrel"] else 0.07
				_barrel("AttachmentBarrel_" + id, Vector3(0.0, 0.03, muzzle_z - extension * 0.5), 0.052 if id == "suppressor" else 0.042, extension, steel if id != "ember_barrel" else Color("b66e45"))
				muzzle_z -= extension
			"underbarrel":
				if id == "laser":
					_box("LaserModule", Vector3(0.11, -0.055, -0.41), Vector3(0.055, 0.045, 0.12), steel)
					_box("LaserLens", Vector3(0.11, -0.055, -0.477), Vector3(0.025, 0.025, 0.008), Color("e78779")).material_override = _material(Color("e78779"), 0.0, true)
				else:
					_box("AttachmentGrip", Vector3(0.0, -0.21, -0.42), Vector3(0.09, 0.22 if id == "grip" else 0.11, 0.09), steel)
			"magazine":
				if is_instance_valid(magazine_mesh):
					magazine_mesh.scale.y *= 1.35 if id == "extended_mag" else (0.86 if id == "quick_mag" else 1.0)
					if id in ["frost_mag", "arc_mag"]:
						magazine_mesh.material_override = _material(Color("91cada") if id == "frost_mag" else Color("95b7db"), 0.4)
			"internal":
				_box("ReceiverUpgradePlate", Vector3(0.10, 0.015, -0.15), Vector3(0.016, 0.09, 0.12), accent.lightened(0.18), 0.6)
	return muzzle_z


func set_visual_options(recoil_strength: float, effect_strength: float, reduced_flashes: bool, inspect_remaining: float) -> void:
	_visual_recoil = clampf(recoil_strength, 0.0, 1.0)
	_effect_strength = clampf(effect_strength, 0.0, 1.0)
	_reduced_flashes = reduced_flashes
	_inspect_remaining = inspect_remaining


func get_muzzle_position() -> Vector3:
	return muzzle.global_position if is_instance_valid(muzzle) else global_position


func fire(recoil_amount: float, is_aiming: bool) -> void:
	_recoil = minf(1.4, _recoil + recoil_amount * 30.0 * (0.7 if is_aiming else 1.0))
	_flash_time = 0.045 if weapon_id == "hammer" else 0.035
	if is_instance_valid(flash):
		flash.visible = _effect_strength > 0.0
		flash.rotation.z = randf() * TAU
		flash.scale = Vector3.ONE * (1.8 if family in ["revolver", "shotgun", "special"] else 1.0) * (0.5 if _reduced_flashes else 1.0)
		flash_light.visible = not _reduced_flashes and _effect_strength > 0.0


func animate_view(delta: float, is_aiming: bool, movement: float, sprint: bool, bob_time: float, reload_progress: float, is_reloading: bool) -> void:
	if not is_instance_valid(model):
		return
	_clock += delta
	_equip_time = maxf(0.0, _equip_time - delta)
	_flash_time = maxf(0.0, _flash_time - delta)
	_recoil = move_toward(_recoil, 0.0, delta * (3.7 if weapon_id == "hammer" else 5.2))
	flash.visible = _flash_time > 0.0 and _effect_strength > 0.0
	flash_light.visible = flash.visible and not _reduced_flashes
	var rest: Vector3 = Vector3(0.25, -0.26, -0.34)
	if is_aiming:
		rest = Vector3(0.0, -_sight_height - 0.022, -0.28)
	var bob_scale: float = movement * (0.16 if is_aiming else 1.0)
	rest += Vector3(sin(bob_time) * 0.012, cos(bob_time * 2.0) * 0.010, 0.0) * bob_scale
	var target_rotation: Vector3 = Vector3.ZERO
	if sprint:
		target_rotation = Vector3(-0.2, 0.14, 0.12)
		rest.y -= 0.06
	if _inspect_remaining > 0.0 and not is_reloading and not is_aiming:
		var inspect_phase: float = clampf((2.25 - _inspect_remaining) / 2.25, 0.0, 1.0)
		var inspect_curve: float = sin(inspect_phase * PI)
		target_rotation = Vector3(0.12, inspect_curve * 0.68, inspect_curve * -0.65)
		rest += Vector3(-0.09, 0.08, 0.06) * inspect_curve
	if is_reloading:
		var p := clampf(reload_progress, 0, 1)
		var present := smoothstep(0.0, 0.15, p) * (1.0 - smoothstep(0.88, 1.0, p))
		rest += Vector3(-0.055, 0.012, 0.025) * present
		target_rotation = Vector3(-present * 0.14, present * 0.28, -present * (0.72 if family == "pistol" else 0.43))
		if is_instance_valid(magazine_mesh):
			var magazine_rest: Vector3 = magazine_mesh.get_meta("rest_position")
			var extract := smoothstep(0.18, 0.38, p) * (1.0 - smoothstep(0.57, 0.77, p))
			if family == "shotgun": extract = absf(sin(clampf((p - 0.18) / 0.64, 0, 1) * PI * 3)) * 0.35
			magazine_mesh.position = magazine_rest + Vector3(-extract * 0.11, -extract * 0.37, extract * 0.065)
			magazine_mesh.rotation = Vector3(magazine_mesh.get_meta("rest_rotation")) + Vector3(0,0,-extract * 0.25)
			magazine_mesh.visible = bool(magazine_mesh.get_meta("rest_visible")) and (family == "shotgun" or p < 0.39 or p > 0.55)
			support_hand.position = Vector3(support_hand.get_meta("rest_position")).lerp(magazine_mesh.position + Vector3(-0.08, -0.02, 0.035), present)
		var rack := sin(smoothstep(0.79, 0.95, p) * PI) if reload_was_empty else 0.0
		if rack > 0: support_hand.position = support_hand.position.lerp(Vector3(-0.07, 0.10, -0.08), rack)
	else:
		if is_instance_valid(magazine_mesh):
			magazine_mesh.position = magazine_mesh.get_meta("rest_position")
			magazine_mesh.rotation = magazine_mesh.get_meta("rest_rotation")
			magazine_mesh.visible = magazine_mesh.get_meta("rest_visible")
		support_hand.position = support_hand.get_meta("rest_position")
	_last_reload = is_reloading
	rest.y -= _equip_time * 0.8
	target_rotation.x -= _equip_time * 0.65
	position = position.lerp(rest, 1.0 - exp(-delta * 17.0))
	rotation = rotation.lerp(target_rotation, 1.0 - exp(-delta * 17.0))
	model.position.z = _recoil * 0.10 * _visual_recoil
	model.rotation.x = _recoil * 0.17 * _visual_recoil
	if model.has_node("PumpForearm"):
		model.get_node("PumpForearm").position.z = -0.55 + _recoil * 0.09
	for element_node: MeshInstance3D in _element_nodes:
		if is_instance_valid(element_node):
			var mat: StandardMaterial3D = element_node.material_override as StandardMaterial3D
			mat.emission_energy_multiplier = (0.75 + sin(_clock * 3.0) * 0.15) * _effect_strength
	if is_instance_valid(slide):
		var slide_rest: Vector3 = slide.get_meta("rest_position")
		slide.position = slide_rest + Vector3(0.0, 0.0, _recoil * (0.07 if weapon_id == "biscuit" else 0.025))
		if is_reloading and reload_was_empty: slide.position.z += sin(smoothstep(0.79, 0.95, reload_progress) * PI) * 0.06

class_name MeyuiActorVisual
extends RefCounted
## Lightweight original character rigs, facing -Z, with their feet at Y = 0.
## Materials belong to one actor so a damage flash never tints another actor.


static func build_enemy(parent: Node3D, kind: String) -> Dictionary:
	var materials: Array[StandardMaterial3D] = []
	var default_colors: Array[Color] = []
	var coat_color: Color = Color("bc524d")
	var skin_color: Color = Color("9b643f")
	var accent_color: Color = Color("f7c56b")
	match kind:
		"runner":
			coat_color = Color("389b96")
			skin_color = Color("7b4c32")
		"tank":
			coat_color = Color("577894")
			skin_color = Color("af7750")
		"boss":
			coat_color = Color("8255aa")
			skin_color = Color("895437")
			accent_color = Color("ffda76")
		"exploder":
			coat_color = Color("ae6840")
			accent_color = Color("ff9058")
		"spitter":
			coat_color = Color("617745")
			accent_color = Color("c1ed85")
		"screamer":
			coat_color = Color("725780")
			accent_color = Color("ce9ee9")
		"hunter":
			coat_color = Color("77714f")
			accent_color = Color("e0c47c")
		"armored":
			coat_color = Color("54606b")
			accent_color = Color("a9c6d7")
		"parasite":
			coat_color = Color("9a7056")
			accent_color = Color("dfb291")
		"summoner":
			coat_color = Color("675584")
			accent_color = Color("c9a6f1")
		"stealth":
			coat_color = Color("323e50")
			accent_color = Color("a0b7d1")
	var skin: StandardMaterial3D = _material(skin_color, materials, default_colors)
	var coat: StandardMaterial3D = _material(coat_color, materials, default_colors)
	var trim: StandardMaterial3D = _material(Color("24333e"), materials, default_colors)
	var accent: StandardMaterial3D = _material(accent_color, materials, default_colors)
	var pale: StandardMaterial3D = _material(Color("eee6ce"), materials, default_colors)
	var black: StandardMaterial3D = _material(Color("181e24"), materials, default_colors)
	var sole: StandardMaterial3D = _material(Color("c9ad79"), materials, default_colors)
	var platinum: StandardMaterial3D = _material(Color("ded9ca"), materials, default_colors)
	accent.emission_enabled = true
	accent.emission = accent_color
	accent.emission_energy_multiplier = 0.16

	var root: Node3D = _pivot(parent, "EnemyVisual", Vector3.ZERO)
	var body: Node3D = _pivot(root, "Body", Vector3.ZERO)
	var torso: MeshInstance3D = _cylinder(body, coat, Vector3(0.0, 1.035, 0.0), 0.25, 0.225, 0.57)
	torso.scale.z = 0.75
	_box(body, trim, Vector3(0.0, 0.715, 0.0), Vector3(0.40, 0.19, 0.29))
	_cylinder(body, skin, Vector3(0.0, 1.345, 0.0), 0.083, 0.083, 0.15)
	var neckline: MeshInstance3D = _cylinder(body, trim, Vector3(0.0, 1.313, 0.0), 0.105, 0.125, 0.038)
	neckline.scale.z = 0.86

	# Sports stripes and the broken amber bars identify the fictional Liga do Ruido.
	for side_index: int in range(2):
		var side: float = -1.0 if side_index == 0 else 1.0
		_box(body, trim, Vector3(side * 0.135, 1.065, -0.190), Vector3(0.032, 0.43, 0.014))
		_box(body, trim, Vector3(side * 0.135, 1.065, 0.188), Vector3(0.032, 0.43, 0.014))
		var badge: MeshInstance3D = _box(body, trim, Vector3(0.0, 1.12, side * 0.202), Vector3(0.145, 0.145, 0.020))
		badge.rotation.z = PI * 0.25
		for bar_index: int in range(2):
			var bar_x: float = -0.035 if bar_index == 0 else 0.035
			var bar: MeshInstance3D = _box(body, accent, Vector3(bar_x, 1.12, side * 0.218), Vector3(0.026, 0.114, 0.018))
			bar.rotation.z = -0.27

	# Belt radio, screen, antenna and a diagonal shoulder strap read from all sides.
	_box(body, black, Vector3(0.235, 0.82, 0.035), Vector3(0.112, 0.17, 0.092))
	_box(body, accent, Vector3(0.24, 0.852, -0.016), Vector3(0.055, 0.033, 0.015))
	_cylinder(body, trim, Vector3(0.263, 0.979, 0.035), 0.007, 0.007, 0.16)
	var strap: MeshInstance3D = _box(body, trim, Vector3(0.0, 1.045, 0.199), Vector3(0.060, 0.51, 0.028))
	strap.rotation.z = -0.43

	var head: Node3D = _pivot(body, "Head", Vector3(0.0, 1.55, 0.0))
	_sphere(head, skin, Vector3.ZERO, Vector3(0.215, 0.225, 0.198))
	for eye_index: int in range(2):
		var eye_side: float = -1.0 if eye_index == 0 else 1.0
		_sphere(head, skin, Vector3(eye_side * 0.211, -0.005, 0.0), Vector3(0.040, 0.063, 0.047))
		_sphere(head, pale, Vector3(eye_side * 0.075, 0.036, -0.185), Vector3(0.046, 0.030, 0.022))
		_sphere(head, black, Vector3(eye_side * 0.075, 0.034, -0.204), Vector3(0.019, 0.023, 0.012))
		var brow: MeshInstance3D = _box(head, black, Vector3(eye_side * 0.074, 0.081, -0.185), Vector3(0.090, 0.017, 0.026))
		brow.rotation.z = eye_side * 0.16
	# Non-graphic geometric face covering with a faction-coloured vent.
	_box(head, trim, Vector3(0.0, -0.075, -0.186), Vector3(0.28, 0.11, 0.080))
	_box(head, accent, Vector3(0.0, -0.074, -0.231), Vector3(0.11, 0.018, 0.012))
	_sphere(head, skin, Vector3(0.0, -0.008, -0.203), Vector3(0.034, 0.035, 0.034))
	var hair_material: StandardMaterial3D = platinum if kind == "runner" or kind == "boss" else black
	_sphere(head, hair_material, Vector3(0.0, 0.154, 0.020), Vector3(0.218, 0.075, 0.186))
	if kind == "runner":
		var fringe: MeshInstance3D = _box(head, platinum, Vector3(0.0, 0.165, -0.104), Vector3(0.27, 0.095, 0.13))
		fringe.rotation.z = -0.10
	elif kind == "grunt":
		# A short hood at the back preserves the face and headshot silhouette.
		_sphere(head, coat, Vector3(0.0, -0.125, 0.12), Vector3(0.23, 0.10, 0.11))

	var arms: Array[Node3D] = []
	var legs: Array[Node3D] = []
	for limb_index: int in range(2):
		var limb_side: float = -1.0 if limb_index == 0 else 1.0
		var side_name: String = "Left" if limb_index == 0 else "Right"
		var arm: Node3D = _pivot(body, side_name + "Arm", Vector3(limb_side * 0.29, 1.26, 0.0))
		arms.append(arm)
		_capsule(arm, coat, Vector3(0.0, -0.095, 0.0), 0.083, 0.245)
		_capsule(arm, skin, Vector3(0.0, -0.32, -0.008), 0.064, 0.27)
		_sphere(arm, skin, Vector3(0.0, -0.481, -0.018), Vector3(0.075, 0.087, 0.071))
		_box(arm, trim, Vector3(0.0, -0.419, -0.004), Vector3(0.132, 0.045, 0.125))
		var leg: Node3D = _pivot(body, side_name + "Leg", Vector3(limb_side * 0.126, 0.68, 0.0))
		legs.append(leg)
		_capsule(leg, trim, Vector3(0.0, -0.14, 0.0), 0.087, 0.30)
		_capsule(leg, skin, Vector3(0.0, -0.412, 0.0), 0.065, 0.286)
		# Visible toes and two crossed straps keep the footwear recognisable as slippers.
		_sphere(leg, skin, Vector3(0.0, -0.591, -0.044), Vector3(0.088, 0.047, 0.132))
		_box(leg, sole, Vector3(0.0, -0.659, -0.045), Vector3(0.184, 0.042, 0.285))
		for sandal_index: int in range(2):
			var sandal_side: float = -1.0 if sandal_index == 0 else 1.0
			var sandal_strap: MeshInstance3D = _box(leg, coat, Vector3(sandal_side * 0.027, -0.56, -0.077), Vector3(0.036, 0.027, 0.142))
			sandal_strap.rotation.y = sandal_side * 0.47
		if kind == "runner":
			_box(leg, accent, Vector3(0.0, -0.13, -0.087), Vector3(0.034, 0.20, 0.018))

	if kind in ["tank", "boss", "armored"]:
		for armor_index: int in range(2):
			var armor_side: float = -1.0 if armor_index == 0 else 1.0
			var pad: MeshInstance3D = _box(arms[armor_index], trim, Vector3(0.0, 0.0, 0.0), Vector3(0.20, 0.16, 0.25))
			pad.rotation.z = armor_side * 0.16
			_box(arms[armor_index], accent, Vector3(0.0, 0.01, -0.133), Vector3(0.093, 0.053, 0.018))
		_box(body, trim, Vector3(0.0, 1.07, 0.245), Vector3(0.34, 0.43, 0.14))
		_box(body, accent, Vector3(0.0, 1.08, 0.324), Vector3(0.055, 0.31, 0.020))
		_box(body, trim, Vector3(0.0, 0.96, -0.217), Vector3(0.30, 0.11, 0.035))
	if kind == "boss":
		var band: MeshInstance3D = _cylinder(head, accent, Vector3(0.0, 0.135, 0.0), 0.22, 0.22, 0.045)
		band.scale.z = 0.86
		for fin_index: int in range(2):
			var fin_side: float = -1.0 if fin_index == 0 else 1.0
			var fin: MeshInstance3D = _box(body, accent, Vector3(fin_side * 0.20, 1.36, 0.27), Vector3(0.075, 0.41, 0.10))
			fin.rotation.z = -fin_side * 0.16
		_box(arms[1], trim, Vector3(0.0, -0.44, -0.18), Vector3(0.12, 0.15, 0.34))
		_box(arms[1], accent, Vector3(0.0, -0.42, -0.36), Vector3(0.09, 0.07, 0.04))
	match kind:
		"exploder":
			# A bulky signal battery flashes during the actor's radial fuse.
			_box(body, trim, Vector3(0.0, 1.04, 0.29), Vector3(0.46, 0.54, 0.23))
			for side in [-1.0, 1.0]:
				_cylinder(body, accent, Vector3(side * 0.13, 1.06, 0.43), 0.076, 0.076, 0.36)
			_box(body, accent, Vector3(0.0, 1.05, -0.215), Vector3(0.21, 0.22, 0.025))
		"spitter":
			_cylinder(body, trim, Vector3(0.0, 1.04, 0.3), 0.17, 0.17, 0.53)
			_cylinder(body, accent, Vector3(0.0, 1.04, 0.315), 0.175, 0.175, 0.19)
			_box(head, trim, Vector3(0.0, -0.07, -0.25), Vector3(0.28, 0.18, 0.14))
			_cylinder(arms[1], accent, Vector3(0.0, -0.38, -0.12), 0.08, 0.09, 0.28).rotation.x = PI * 0.5
		"screamer":
			for side in [-1.0, 1.0]:
				_box(body, trim, Vector3(side * 0.27, 1.32, 0.18), Vector3(0.23, 0.35, 0.22))
				var cone: MeshInstance3D = _cylinder(body, accent, Vector3(side * 0.27, 1.32, 0.035), 0.084, 0.11, 0.06)
				cone.rotation.x = PI * 0.5
			_cylinder(body, trim, Vector3(0.14, 1.71, 0.2), 0.012, 0.012, 0.5)
		"hunter":
			_box(head, trim, Vector3(0.0, 0.055, -0.205), Vector3(0.31, 0.095, 0.07))
			for side in [-1.0, 1.0]:
				_sphere(head, accent, Vector3(side * 0.075, 0.055, -0.246), Vector3(0.043, 0.035, 0.012))
			for arm in arms:
				_box(arm, trim, Vector3(0.0, -0.3, -0.068), Vector3(0.17, 0.21, 0.10))
		"armored":
			_box(body, trim, Vector3(0.0, 1.04, -0.22), Vector3(0.44, 0.47, 0.12))
			_box(body, accent, Vector3(0.0, 1.055, -0.285), Vector3(0.042, 0.35, 0.014))
			_sphere(head, trim, Vector3(0.0, 0.137, 0.015), Vector3(0.24, 0.095, 0.21))
		"parasite":
			# A low, masked radio scavenger; the actor also uses a smaller hit rig.
			_sphere(head, pale, Vector3(0.0, -0.015, -0.20), Vector3(0.24, 0.2, 0.065))
			for side in [-1.0, 1.0]:
				_sphere(head, black, Vector3(side * 0.086, 0.025, -0.259), Vector3(0.063, 0.077, 0.019))
				_box(body, trim, Vector3(side * 0.20, 1.02, 0.22), Vector3(0.13, 0.44, 0.22)).rotation.z = side * 0.18
		"summoner":
			_cylinder(body, coat, Vector3(0.0, 0.58, 0.015), 0.21, 0.31, 0.43)
			_cylinder(arms[1], trim, Vector3(0.0, -0.34, -0.12), 0.024, 0.024, 1.18)
			_sphere(arms[1], accent, Vector3(0.0, 0.28, -0.12), Vector3(0.095, 0.12, 0.095))
			_box(body, trim, Vector3(0.0, 1.13, 0.28), Vector3(0.34, 0.52, 0.19))
		"stealth":
			_sphere(head, coat, Vector3(0.0, 0.055, 0.075), Vector3(0.25, 0.235, 0.21))
			_box(head, black, Vector3(0.0, 0.015, -0.21), Vector3(0.28, 0.085, 0.025))
			_box(head, accent, Vector3(0.0, 0.015, -0.228), Vector3(0.17, 0.013, 0.012))
			_box(body, coat, Vector3(0.0, 0.83, 0.23), Vector3(0.38, 0.78, 0.045))

	return {
		"root": root, "body": body, "head": head,
		"left_arm": arms[0], "right_arm": arms[1],
		"left_leg": legs[0], "right_leg": legs[1],
		"materials": materials, "default_colors": default_colors,
	}


static func build_dog(parent: Node3D) -> Dictionary:
	var materials: Array[StandardMaterial3D] = []
	var default_colors: Array[Color] = []
	var fur: StandardMaterial3D = _material(Color("ac683b"), materials, default_colors)
	var dark_fur: StandardMaterial3D = _material(Color("643b26"), materials, default_colors)
	var muzzle: StandardMaterial3D = _material(Color("d7a16a"), materials, default_colors)
	var black: StandardMaterial3D = _material(Color("10191d"), materials, default_colors)
	var highlight: StandardMaterial3D = _material(Color("fff4de"), materials, default_colors)
	var collar_material: StandardMaterial3D = _material(Color("53c6b5"), materials, default_colors)
	var gold: StandardMaterial3D = _material(Color("f5c567"), materials, default_colors)
	collar_material.emission_enabled = true
	collar_material.emission = Color("53c6b5")
	collar_material.emission_energy_multiplier = 0.20

	var root: Node3D = _pivot(parent, "FaroVisual", Vector3.ZERO)
	var body: Node3D = _pivot(root, "Body", Vector3.ZERO)
	var torso: MeshInstance3D = _capsule(body, fur, Vector3(0.0, 0.31, 0.03), 0.18, 1.03)
	torso.rotation.x = PI * 0.5
	torso.scale.x = 0.94
	_sphere(body, muzzle, Vector3(0.0, 0.215, -0.17), Vector3(0.135, 0.077, 0.23))
	var head: Node3D = _pivot(body, "Head", Vector3(0.0, 0.435, -0.49))
	_sphere(head, fur, Vector3.ZERO, Vector3(0.181, 0.183, 0.204))
	_sphere(head, muzzle, Vector3(0.0, -0.059, -0.175), Vector3(0.115, 0.088, 0.197))
	_sphere(head, black, Vector3(0.0, -0.024, -0.345), Vector3(0.064, 0.046, 0.047))
	var ears: Array[Node3D] = []
	for ear_index: int in range(2):
		var ear_side: float = -1.0 if ear_index == 0 else 1.0
		_sphere(head, black, Vector3(ear_side * 0.111, 0.051, -0.157), Vector3(0.031, 0.036, 0.021))
		_sphere(head, highlight, Vector3(ear_side * 0.111 - 0.008, 0.061, -0.175), Vector3(0.008, 0.009, 0.006))
		_sphere(head, muzzle, Vector3(ear_side * 0.101, 0.104, -0.129), Vector3(0.044, 0.018, 0.021))
		var ear: Node3D = _pivot(head, "Ear" + str(ear_index), Vector3(ear_side * 0.168, 0.035, 0.012))
		ears.append(ear)
		var floppy_ear: MeshInstance3D = _capsule(ear, dark_fur, Vector3(ear_side * 0.017, -0.137, 0.008), 0.070, 0.335)
		floppy_ear.scale.z = 0.42
		floppy_ear.rotation.z = ear_side * 0.12

	var legs: Array[Node3D] = []
	# Ordered front-left, front-right, rear-left, rear-right for a diagonal trot.
	for leg_index: int in range(4):
		var leg_side: float = -1.0 if leg_index % 2 == 0 else 1.0
		var leg_z: float = -0.305 if leg_index < 2 else 0.355
		var leg: Node3D = _pivot(body, "Leg" + str(leg_index), Vector3(leg_side * 0.12, 0.22, leg_z))
		legs.append(leg)
		_capsule(leg, fur, Vector3(0.0, -0.082, 0.0), 0.055, 0.215)
		_sphere(leg, muzzle, Vector3(0.0, -0.178, -0.024), Vector3(0.063, 0.042, 0.082))

	var tail: Node3D = _pivot(body, "Tail", Vector3(0.0, 0.38, 0.50))
	var tail_mesh: MeshInstance3D = _capsule(tail, dark_fur, Vector3(0.0, 0.09, 0.105), 0.032, 0.30)
	tail_mesh.rotation.x = 0.84
	var collar_shape: TorusMesh = TorusMesh.new()
	collar_shape.inner_radius = 0.141
	collar_shape.outer_radius = 0.18
	collar_shape.rings = 12
	collar_shape.ring_segments = 6
	var collar: MeshInstance3D = _mesh(body, collar_shape, collar_material, Vector3(0.0, 0.363, -0.40))
	collar.rotation.x = PI * 0.5
	_sphere(body, gold, Vector3(0.0, 0.175, -0.429), Vector3(0.045, 0.056, 0.015))
	_box(body, dark_fur, Vector3(0.0, 0.485, -0.015), Vector3(0.18, 0.025, 0.30))
	_box(body, collar_material, Vector3(0.0, 0.502, -0.015), Vector3(0.088, 0.014, 0.095))
	return {
		"root": root, "body": body, "head": head,
		"legs": legs, "tail": tail, "ears": ears, "collar": collar,
		"materials": materials, "default_colors": default_colors,
	}


static func _material(color: Color, materials: Array[StandardMaterial3D], colors: Array[Color]) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.88
	materials.append(material)
	colors.append(color)
	return material


static func _pivot(parent: Node3D, node_name: String, at: Vector3) -> Node3D:
	var node: Node3D = Node3D.new()
	node.name = node_name
	node.position = at
	parent.add_child(node)
	return node


static func _mesh(parent: Node3D, shape: PrimitiveMesh, material: StandardMaterial3D, at: Vector3) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = shape
	node.material_override = material
	node.position = at
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(node)
	return node


static func _box(parent: Node3D, material: StandardMaterial3D, at: Vector3, size: Vector3) -> MeshInstance3D:
	var shape: BoxMesh = BoxMesh.new()
	shape.size = size
	return _mesh(parent, shape, material, at)


static func _sphere(parent: Node3D, material: StandardMaterial3D, at: Vector3, radii: Vector3) -> MeshInstance3D:
	var shape: SphereMesh = SphereMesh.new()
	shape.radius = 1.0
	shape.height = 2.0
	shape.radial_segments = 10
	shape.rings = 6
	var node: MeshInstance3D = _mesh(parent, shape, material, at)
	node.scale = radii
	return node


static func _capsule(parent: Node3D, material: StandardMaterial3D, at: Vector3, radius: float, height: float) -> MeshInstance3D:
	var shape: CapsuleMesh = CapsuleMesh.new()
	shape.radius = radius
	shape.height = height
	shape.radial_segments = 8
	shape.rings = 3
	return _mesh(parent, shape, material, at)


static func _cylinder(parent: Node3D, material: StandardMaterial3D, at: Vector3, top_radius: float, bottom_radius: float, height: float) -> MeshInstance3D:
	var shape: CylinderMesh = CylinderMesh.new()
	shape.top_radius = top_radius
	shape.bottom_radius = bottom_radius
	shape.height = height
	shape.radial_segments = 10
	return _mesh(parent, shape, material, at)

class_name MeyuiPreviewStage
extends SubViewportContainer

## An isolated inspection world. Its models and lights never enter gameplay physics.
const ActorVisual = preload("res://scripts/actor_visual.gd")
const AMBER: Color = Color("d9b477")
const MINT: Color = Color("80c9b6")

var viewport: SubViewport
var camera: Camera3D
var pivot: Node3D
var _model: Node3D
var _dog_rig: Dictionary = {}
var _time: float = 0.0
var _dragging: bool = false
var _manual_turn: float = 0.0
var _kind: String = "weapon"
var _signature: String = ""


func _ready() -> void:
	stretch = true
	custom_minimum_size = Vector2(maxf(160.0, custom_minimum_size.x), maxf(210.0, custom_minimum_size.y))
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	tooltip_text = "Arraste para girar a prévia 3D."
	viewport = SubViewport.new()
	viewport.name = "InspectionWorld"
	viewport.size = Vector2i(640, 360)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	# Tabs create previews on demand, after the last global settings application.
	# Inherit the active renderer quality instead of briefly restoring a fixed 2x AA.
	viewport.msaa_3d = get_viewport().msaa_3d
	viewport.anisotropic_filtering_level = get_viewport().anisotropic_filtering_level
	viewport.positional_shadow_atlas_size = get_viewport().positional_shadow_atlas_size
	add_child(viewport)
	var stage: Node3D = Node3D.new()
	viewport.add_child(stage)
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("10171e")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b8cbd0")
	environment.ambient_light_energy = 0.68
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	stage.add_child(world_environment)
	var key_light: DirectionalLight3D = DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-35.0, -30.0, 0.0)
	key_light.light_color = Color("ffe2b5")
	key_light.light_energy = 2.0
	stage.add_child(key_light)
	var rim_light: OmniLight3D = OmniLight3D.new()
	rim_light.position = Vector3(-2.0, 1.2, -1.6)
	rim_light.light_color = Color("80c9b6")
	rim_light.light_energy = 3.2
	rim_light.omni_range = 7.0
	stage.add_child(rim_light)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.0
	camera.position = Vector3(2.0, 1.15, 3.8)
	stage.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	pivot = Node3D.new()
	stage.add_child(pivot)
	var plinth: MeshInstance3D = MeshInstance3D.new()
	var plinth_mesh: CylinderMesh = CylinderMesh.new()
	plinth_mesh.top_radius = 1.05
	plinth_mesh.bottom_radius = 1.12
	plinth_mesh.height = 0.045
	plinth_mesh.radial_segments = 48
	plinth.mesh = plinth_mesh
	plinth.position.y = -0.60
	plinth.material_override = _material(Color("202d34"), 0.5)
	stage.add_child(plinth)
	var ring: MeshInstance3D = MeshInstance3D.new()
	var ring_mesh: TorusMesh = TorusMesh.new()
	ring_mesh.inner_radius = 1.03
	ring_mesh.outer_radius = 1.043
	ring_mesh.rings = 48
	ring_mesh.ring_segments = 6
	ring.mesh = ring_mesh
	ring.position.y = -0.57
	ring.material_override = _material(MINT, 0.4, true)
	stage.add_child(ring)
func _process(delta: float) -> void:
	if not is_visible_in_tree() or not is_instance_valid(pivot):
		return
	_time += delta
	pivot.rotation.y = _manual_turn + sin(_time * 0.42) * 0.13
	if not _dog_rig.is_empty():
		var tail: Node3D = _dog_rig.get("tail") as Node3D
		if is_instance_valid(tail):
			tail.rotation.z = sin(_time * 4.0) * 0.24
		var head: Node3D = _dog_rig.get("head") as Node3D
		if is_instance_valid(head):
			head.rotation.x = sin(_time * 1.5) * 0.035


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
			accept_event()
	if event is InputEventMouseMotion and _dragging:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		_manual_turn += motion.relative.x * 0.012
		accept_event()


func _clear_model(signature: String) -> bool:
	if not is_node_ready():
		return false
	if _signature == signature:
		return false
	_signature = signature
	_dog_rig.clear()
	if is_instance_valid(_model):
		_model.free()
	_model = Node3D.new()
	pivot.add_child(_model)
	_manual_turn = 0.0
	return true


func show_weapon(item: Dictionary, stats: Dictionary) -> void:
	if not is_node_ready():
		call_deferred("show_weapon", item, stats)
		return
	if not _clear_model("weapon:" + JSON.stringify([item, stats])): return
	_kind = "weapon"
	camera.size = 1.35
	var rig := preload("res://scripts/weapon_view.gd").new()
	_model.add_child(rig)
	rig.set_weapon(String(item.get("model_id", "biscuit")), stats)
	# Inspect the exact weapon used in combat, without first-person hands or flash.
	for part: Node in rig.model.get_children():
		if String(part.name) in ["TriggerPaw", "SupportPaw", "TealSleeve", "Muzzle"]:
			part.hide()
	rig.position = Vector3(-0.38, 0.08, 0)
	rig.rotation.y = -PI * 0.5
	rig.scale = Vector3.ONE * 1.6
	_model.rotation.y = -0.15

func show_character(source: Node3D) -> void:
	if not is_node_ready():
		call_deferred("show_character", source)
		return
	if not is_instance_valid(source) or not _clear_model("character"): return
	_kind = "character"
	camera.size = 1.9
	var character := source.duplicate() as Node3D
	_model.add_child(character)
	character.visible = true
	character.position = Vector3.ZERO
	_model.position.y = -0.59
	_model.rotation.y = 2.5

func show_dog(progression: Dictionary) -> void:
	if not is_node_ready():
		call_deferred("show_dog", progression)
		return
	if not _clear_model("dog:" + JSON.stringify(progression)):
		return
	_kind = "dog"
	camera.size = 1.70
	_model.position.y = -0.54
	_model.rotation.y = -0.42
	_dog_rig = ActorVisual.build_dog(_model)
	var archetype: String = str(progression.get("archetype", progression.get("selected", "combat")))
	var gear: Color = {"combat": AMBER, "collector": MINT, "support": Color("90b7df"), "guardian": Color("b4a0d5")}.get(archetype, MINT)
	var body: Node3D = _dog_rig.get("body") as Node3D
	if is_instance_valid(body):
		var old_model: Node3D = _model
		_model = body
		_box("ProgressionHarness", Vector3(0.0, 0.47, 0.07), Vector3(0.28, 0.06, 0.38), gear)
		var levels: Dictionary = progression.get("levels", {})
		if int(levels.get("elemental", 0)) > 0:
			var element_color: Color = {"fire":Color("ef9c68"), "shock":Color("be9ff0"), "cryo":Color("8addf0")}.get(progression.get("element", "shock"), MINT)
			for side: float in [-1.0, 1.0]: _box("ElementCell", Vector3(side * 0.15, 0.51, -0.20), Vector3(0.07, 0.1, 0.13), element_color, true)
		if int(levels.get("resupply", 0)) > 0:
			for index: int in range(3): _box("AmmoCanister", Vector3(0.18, 0.4, -0.03 + index * 0.09), Vector3(0.07, 0.13, 0.055), AMBER)
		if int(levels.get("survival", 0)) > 0: _box("BackArmor", Vector3(0,0.49,0.04), Vector3(0.25,0.11,0.53), Color("39434c"))
		if int(levels.get("control", 0)) > 0: _box("HunterHarness", Vector3(0,0.38,-0.35), Vector3(0.32,0.15,0.09), Color("707f8b"))
		if archetype in ["collector", "support"]:
			for side: int in [-1, 1]:
				_box("SaddleBag%d" % side, Vector3(side * 0.19, 0.30, 0.13), Vector3(0.12, 0.23, 0.28), gear)
		elif archetype == "guardian":
			_box("GuardPlate", Vector3(0.0, 0.30, -0.28), Vector3(0.37, 0.19, 0.10), Color("718396"))
		elif archetype == "combat":
			_box("TrailBadge", Vector3(0.0, 0.508, 0.02), Vector3(0.13, 0.024, 0.16), AMBER, true)
		_model = old_model


func _material(color: Color, metallic: float = 0.25, glow: bool = false) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = 0.52
	if glow:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.45
	return material


func _box(part_name: String, at: Vector3, dimensions: Vector3, color: Color, glow: bool = false) -> MeshInstance3D:
	var shape: ArrayMesh = preload("res://scripts/weapon_geometry.gd").chamfer_box(dimensions)
	return _part(part_name, shape, at, color, glow)


func _cylinder(part_name: String, at: Vector3, radius: float, length: float, color: Color, glow: bool = false) -> MeshInstance3D:
	var shape: CylinderMesh = CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = length
	shape.radial_segments = 16
	var node: MeshInstance3D = _part(part_name, shape, at, color, glow)
	node.rotation.z = PI * 0.5
	return node


func _part(part_name: String, mesh: Mesh, at: Vector3, color: Color, glow: bool) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = part_name
	node.mesh = mesh
	node.position = at
	node.material_override = _material(color, 0.25, glow)
	_model.add_child(node)
	return node

extends Node3D
class_name MeyuiWorld

## Morro do Vento, after the rain: nine districts with physical circulation.
const Expansion = preload("res://scripts/world_expansion.gd")
var game: Node
var spawn_position := Vector3(0, 0.25, 17)
var menu_camera_position := Vector3(3.8, 4.3, 23.5)
var menu_look_at := Vector3(-0.7, 1.15, 13.4)
var navigation_ready := false
var navigation_region: NavigationRegion3D
var unlocked_regions: Array[String] = ["patio", "mercado"]
var regions: Array[Dictionary] = [
	{"id": "patio", "name": "Pátio do Farol", "center": Vector3(0, 0, 14), "unlock_cost": 0, "unlock_round": 1},
	{"id": "mercado", "name": "Beco das Marés", "center": Vector3(-20, 0, 1.5), "unlock_cost": 0, "unlock_round": 1},
	{"id": "oficina", "name": "Oficina Suspensa", "center": Vector3(17, 4, -7), "unlock_cost": 180, "unlock_round": 2},
	{"id": "galeria", "name": "Galeria da Chuva", "center": Vector3(-20, -4, -36), "unlock_cost": 260, "unlock_round": 3},
	{"id": "lajes", "name": "Lajes do Sinal", "center": Vector3(-1, 8, -31), "unlock_cost": 420, "unlock_round": 4},
	{"id": "quadra", "name": "Quadra do Eco", "center": Vector3(25, 0, -44), "unlock_cost": 650, "unlock_round": 5}
]
var spawn_points: Array[Vector3] = [
	Vector3(-6, 0.25, 19), Vector3(5, 0.25, 9), Vector3(-3, 0.25, 6),
	Vector3(-17, 0.25, 1), Vector3(-26.5, 0.25, -9), Vector3(-15, 0.25, -11),
	Vector3(17, 4.25, -7), Vector3(24, 4.25, 0), Vector3(10, 4.25, -12),
	Vector3(-20, -3.75, -36), Vector3(-26, -3.75, -40), Vector3(-12, -3.75, -35),
	Vector3(-1, 8.25, -31), Vector3(-5, 8.25, -39), Vector3(5, 8.25, -27),
	Vector3(25, 0.25, -44), Vector3(18, 0.25, -51), Vector3(32, 0.25, -40)
]
var shops: Array[Dictionary] = [
	{"id": "ferro_do_morro", "name": "Ferro do Morro", "position": Vector3(-6.8, 0.2, 14), "type": "forge"},
	{"id": "mercador_das_mares", "name": "Mercador das Marés", "position": Vector3(-27, 0.2, 2), "type": "merchant"}
]
var points_of_interest: Array[Dictionary] = [
	{"id": "forja_patio", "type": "forge", "name": "Ferro do Morro", "position": Vector3(-6.8, 0.2, 14), "cost": 0, "region_id": "patio"},
	{"id": "mercador_mares", "type": "merchant", "name": "Mercador das Marés", "position": Vector3(-27, 0.2, 2), "cost": 0, "region_id": "mercado"},
	{"id": "bau_patio", "type": "chest", "name": "Baú dos moradores", "position": Vector3(4.2, 0.2, 19.2), "cost": 0, "region_id": "patio"},
	{"id": "reserva_mercado", "type": "cache", "name": "Reserva sob o toldo", "position": Vector3(-13, 0.2, -6), "cost": 0, "region_id": "mercado"},
	{"id": "bau_oficina", "type": "chest", "name": "Caixa da oficina", "position": Vector3(22, 4.2, -11), "cost": 80, "region_id": "oficina"},
	{"id": "bau_galeria", "type": "chest", "name": "Cofre na galeria", "position": Vector3(-26, -3.8, -36), "cost": 120, "region_id": "galeria"},
	{"id": "reserva_lajes", "type": "cache", "name": "Suprimentos do sinal", "position": Vector3(3, 8.2, -39), "cost": 0, "region_id": "lajes"},
	{"id": "desafio_sinal", "type": "challenge", "name": "Manter o sinal", "position": Vector3(-4, 8.2, -28), "cost": 0, "region_id": "lajes"},
	{"id": "desafio_galeria", "type": "challenge", "name": "Vigília da chuva", "position": Vector3(-15, -3.8, -41), "cost": 0, "region_id": "galeria"},
	{"id": "boss_quadra", "type": "boss", "name": "Chamar o Eco", "position": Vector3(25, 0.2, -48), "cost": 0, "region_id": "quadra"},
	{"id": "porta_oficina_patio", "type": "door", "name": "Abrir Oficina Suspensa", "position": Vector3(10, 0.55, 12.4), "cost": 180, "region_id": "oficina"},
	{"id": "porta_oficina_lajes", "type": "door", "name": "Abrir Oficina Suspensa", "position": Vector3(11, 5.0, -20.1), "cost": 180, "region_id": "oficina"},
	{"id": "porta_galeria_mercado", "type": "door", "name": "Abrir Galeria da Chuva", "position": Vector3(-24, 0.12, -15.8), "cost": 260, "region_id": "galeria"},
	{"id": "porta_galeria_lajes", "type": "door", "name": "Abrir Galeria da Chuva", "position": Vector3(-6.8, -2.52, -40), "cost": 260, "region_id": "galeria"},
	{"id": "porta_lajes_oficina", "type": "door", "name": "Abrir Lajes do Sinal", "position": Vector3(11, 7.32, -29.1), "cost": 420, "region_id": "lajes"},
	{"id": "porta_lajes_galeria", "type": "door", "name": "Abrir Lajes do Sinal", "position": Vector3(-5, 7.0, -45.4), "cost": 420, "region_id": "lajes"},
	{"id": "porta_lajes_quadra", "type": "door", "name": "Abrir Lajes do Sinal", "position": Vector3(17.7, 6.65, -36), "cost": 420, "region_id": "lajes"},
	{"id": "porta_quadra_oficina", "type": "door", "name": "Abrir Quadra do Eco", "position": Vector3(32, 0.7, -31.8), "cost": 650, "region_id": "quadra"},
	{"id": "porta_quadra_lajes", "type": "door", "name": "Abrir Quadra do Eco", "position": Vector3(26.4, 1.7, -36), "cost": 650, "region_id": "quadra"}
]

const STONE := Color("536267")
const BRICK := Color("68504b")
const TEAL := Color("36585c")
const PLASTER := Color("747873")
const DARK := Color("202c33")
const RUST := Color("80553e")
const WARM := Color("ffbd79")
## Gates stop actors and camera booms, while ballistic rays use solid world layer 1.
const GATE_COLLISION_LAYER := 32
var _geometry: Node3D
var _materials: Dictionary = {}
var _gates: Dictionary = {}
var _lights: Array[OmniLight3D] = []
var _clock := 0.0
var _environment: Environment
var _moon: DirectionalLight3D
var _rain: MultiMeshInstance3D
var _rain_material: ShaderMaterial
var _vegetation: Array[Node3D] = []
var _boss_arena := false
var _event_id := "none"
var _event_light := 1.0
var _graphics: Dictionary = {}
var _surface_grain: NoiseTexture2D
var _effect_level := 1.0
var _puddles: Array[MeshInstance3D] = []
var _emissive_materials: Array[Dictionary] = []

func setup(owner_game: Node) -> void:
	game = owner_game

func _ready() -> void:
	name = "MorroDoVento"
	process_mode = Node.PROCESS_MODE_ALWAYS
	navigation_region = NavigationRegion3D.new()
	navigation_region.name = "NativeDistrictNavigation"
	add_child(navigation_region)
	_geometry = Node3D.new()
	_geometry.name = "PhysicalNeighborhood"
	navigation_region.add_child(_geometry)
	Expansion.register(self)
	_build_lighting()
	_build_routes()
	_build_architecture()
	Expansion.new().build(self)
	_build_interactables()
	_build_rain()
	call_deferred("_bake_navigation")

func _process(delta: float) -> void:
	_clock += delta
	for index in range(mini(3, _lights.size())):
		var flicker := (sin(_clock * 1.7 + index * 2.0) * 0.075 + sin(_clock * 11.0) * 0.018) * _effect_level
		_lights[index].light_energy = (2.0 + flicker) * _event_light

func _bake_navigation() -> void:
	var mesh := NavigationMesh.new()
	# The shared map must also clear 2.275m bosses and their wider corner turns.
	mesh.agent_radius = 0.8
	mesh.agent_height = 2.3999999
	mesh.agent_max_climb = 0.45000002
	mesh.agent_max_slope = 45
	mesh.cell_size = 0.2
	mesh.cell_height = 0.05
	mesh.region_min_size = 1
	# Monotone regions keep stacked shop floors and long interior ramps manifold.
	mesh.sample_partition_type = NavigationMesh.SAMPLE_PARTITION_MONOTONE
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = 1
	NavigationServer3D.map_set_cell_size(get_world_3d().navigation_map, mesh.cell_size)
	NavigationServer3D.map_set_cell_height(get_world_3d().navigation_map, mesh.cell_height)
	navigation_region.navigation_mesh = mesh
	navigation_region.bake_navigation_mesh(false)
	# Gates enter physics after baking: opening them immediately exposes an existing route.
	_build_gates()
	await get_tree().physics_frame
	await get_tree().physics_frame
	for frame in range(120):
		NavigationServer3D.map_force_update(get_world_3d().navigation_map)
		var closest := NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, spawn_position)
		if closest.distance_to(spawn_position) < 1.0:
			break
		await get_tree().physics_frame
	navigation_ready = mesh.get_polygon_count() > 0 and NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, spawn_position).distance_to(spawn_position) < 1.0

func set_boss_arena(active: bool) -> void:
	_boss_arena = active
	_apply_gate_state()

func set_event(id: String) -> void:
	_event_id = id
	_event_light = 0.07 if id == "blackout" else 1.0
	if is_instance_valid(_moon):
		_moon.light_energy = 0.15 if id == "blackout" else 0.28
	if _environment != null:
		_environment.ambient_light_energy = 0.20 if id == "blackout" else (0.32 if id == "storm" else 0.38)
		_environment.fog_density = 0.015 if id == "storm" else 0.008
	for light: OmniLight3D in _lights:
		light.light_energy = 2.0 * _event_light
	if _rain_material != null:
		_rain_material.set_shader_parameter("rain_speed", 20.0 if id == "storm" else 13.0)
		_rain_material.set_shader_parameter("rain_alpha", 0.36 if id == "storm" else 0.22)

func apply_settings(values: Dictionary) -> void:
	apply_graphics(values)

func apply_graphics(values: Dictionary) -> void:
	_graphics = values.duplicate()
	_effect_level = clampf(float(values.get("effects", 1.0)), 0, 1)
	for puddle: MeshInstance3D in _puddles:
		puddle.visible = _effect_level > 0.01
		var material := puddle.material_override as StandardMaterial3D
		material.roughness = lerpf(0.68, 0.13, _effect_level)
		material.metallic = lerpf(0, 0.38, _effect_level)
	for glow: Dictionary in _emissive_materials:
		glow.material.emission_energy_multiplier = float(glow.energy) * lerpf(0.15, 1.0, _effect_level)
	if _environment != null:
		_environment.fog_enabled = bool(values.get("fog", true))
	if is_instance_valid(_moon):
		_moon.shadow_enabled = int(values.get("shadows", 2)) > 0
		_moon.directional_shadow_max_distance = clampf(float(values.get("render_distance", 120)), 40, 120)
	for index in range(_lights.size()):
		_lights[index].shadow_enabled = int(values.get("shadows", 2)) > 1 and index < 2
	for plant: Node3D in _vegetation:
		plant.visible = bool(values.get("vegetation", true))
	if is_instance_valid(_rain):
		_rain.multimesh.visible_instance_count = int(850 * clampf(float(values.get("particles", 1.0)), 0, 1))
		_rain.visible = _rain.multimesh.visible_instance_count > 0

func unlock_region(id: String) -> bool:
	if not _has_region(id):
		return false
	if not unlocked_regions.has(id):
		unlocked_regions.append(id)
	_apply_gate_state()
	return true

func export_state() -> Dictionary:
	return {"version": 1, "unlocked_regions": unlocked_regions.duplicate()}

func import_state(state: Dictionary) -> bool:
	var saved: Variant = state.get("unlocked_regions", [])
	if not saved is Array:
		return false
	var restored: Array[String] = ["patio", "mercado"]
	for entry: Variant in saved:
		if not entry is String or not _has_region(String(entry)):
			return false
		if not restored.has(String(entry)):
			restored.append(String(entry))
	unlocked_regions = restored
	_apply_gate_state()
	return true

func interactables(observer_position: Variant = null) -> Array:
	var result: Array = []
	for point: Dictionary in points_of_interest:
		if point.type == "door":
			if can_purchase_region(str(point.region_id)):
				var entry: Dictionary = point.duplicate()
				if observer_position is Vector3:
					entry["position"] = _gate_interaction_position(str(point.id), observer_position, point.position)
				result.append(entry)
		elif unlocked_regions.has(point.region_id):
			result.append(point)
	return result

func can_purchase_region(region_id: String) -> bool:
	return _has_region(region_id) and not unlocked_regions.has(region_id) and not (_boss_arena and region_id == "quadra")

func _gate_interaction_position(poi_id: String, observer: Vector3, fallback: Vector3) -> Vector3:
	for gates: Array in _gates.values():
		for gate: Dictionary in gates:
			if str(gate.poi_id) != poi_id: continue
			var center: Vector3 = gate.node.global_position
			var normal: Vector3 = gate.node.global_basis.z.normalized()
			var side := 1.0 if (observer - center).dot(normal) >= 0 else -1.0
			# The same gate ID and purchase target expose a reachable point on either face.
			var approach := center + normal * side * 0.85
			var query := PhysicsRayQueryParameters3D.create(approach + Vector3.UP * 1.5, approach + Vector3.DOWN * 3, 1)
			var floor_hit := get_world_3d().direct_space_state.intersect_ray(query)
			if not floor_hit.is_empty() and Vector3(floor_hit.normal).dot(Vector3.UP) > 0.65:
				approach.y = Vector3(floor_hit.position).y
			return approach + Vector3.UP * 0.2
	return fallback

func _has_region(id: String) -> bool:
	for region: Dictionary in regions:
		if region.id == id:
			return true
	return false

func get_region_id(p: Vector3) -> String:
	if p.x >= 24 and p.z >= 24: return "shopping"
	if p.x >= 30 and p.z >= -14 and p.z < 24: return "cinema"
	if p.z >= 26: return "parque"
	# Height is part of district identity, including the gallery beneath the roof walk.
	if p.y < -1.3 and p.z < -16:
		return "galeria"
	if p.y > 6.0 and p.z < -22:
		return "lajes"
	if p.x >= 14 and p.z < -32 and p.y < 4.0:
		return "quadra"
	if p.x >= 7 and p.y > 2.3:
		return "oficina"
	if p.x < -9 and p.z < 9:
		return "mercado"
	return "patio"

func district(p: Vector3) -> String:
	var id := get_region_id(p)
	for region: Dictionary in regions:
		if region.id == id:
			return region.name
	return "Morro do Vento"

func height_at(x: float, z: float) -> float:
	# Used for exterior placement only; actor movement always uses real physics.
	if z >= 26 or (x >= 30 and z >= -14): return 0
	if x >= 7.4 and x <= 12.6 and z <= 14 and z >= -2:
		return (14 - z) * 0.25
	if x >= -26.5 and x <= -21.5 and z <= -15.5 and z >= -31:
		return (z + 15.5) * 4.0 / 15.5
	if x >= 8.7 and x <= 13.3 and z < -17 and z > -32.5:
		return 4 + (-17 - z) * 4.0 / 15.5
	if x >= 29.5 and x <= 34.5 and z < -18 and z > -34:
		return 4 + (z + 18) * 0.25
	if z < -31 and x < -7:
		return -4
	if z < -23 and x >= -8 and x < 15:
		return 8
	if x >= 7 and z < 5 and z >= -18:
		return 4
	return 0

func get_spawn_near(player_position: Vector3, min_distance: float = 12) -> Vector3:
	var available: Array[Vector3] = []
	var same_level: Array[Vector3] = []
	var local_district: Array[Vector3] = []
	var player_district := get_region_id(player_position)
	for point: Vector3 in spawn_points:
		if not unlocked_regions.has(get_region_id(point)):
			continue
		if point.distance_to(player_position) >= min_distance:
			available.append(point)
			if get_region_id(point) == player_district: local_district.append(point)
			if absf(point.y - player_position.y) < 2.5:
				same_level.append(point)
	var pool := local_district if not local_district.is_empty() else (same_level if not same_level.is_empty() else available)
	if not pool.is_empty():
		# The expanded footprint must not turn the end of a wave into a long wait.
		var nearest := INF
		for point: Vector3 in pool: nearest = minf(nearest, point.distance_to(player_position))
		var nearby: Array[Vector3] = []
		for point: Vector3 in pool:
			if point.distance_to(player_position) <= nearest + 12.0: nearby.append(point)
		return nearby[randi() % nearby.size()]
	# Even an impossible requested distance cannot select a locked district.
	var farthest := spawn_position
	var distance := -1.0
	for point: Vector3 in spawn_points:
		if unlocked_regions.has(get_region_id(point)) and point.distance_squared_to(player_position) > distance:
			farthest = point
			distance = point.distance_squared_to(player_position)
	return farthest

func _build_routes() -> void:
	_floor("Patio", Vector3(0, 0, 14.5), Vector2(24, 21))
	_floor("Mercado", Vector3(-20, 0, -4), Vector2(22, 23))
	_floor("CoveredPassage", Vector3(-13, 0, 8), Vector2(18, 6))
	# Two slabs leave the incoming staircase open all the way to its upper landing.
	_floor("OficinaMain", Vector3(20.3, 4, -6), Vector2(15.4, 22))
	_floor("OficinaWest", Vector3(9.8, 4, -9.5), Vector2(5.6, 15))
	_floor("EastLanding", Vector3(29.5, 4, -15.5), Vector2(11, 5))
	_floor("Galeria", Vector3(-18.5, -4, -37.5), Vector2(23, 13))
	_floor("Lajes", Vector3(-0.5, 8, -33.5), Vector2(15, 19))
	_floor("RoofEastLanding", Vector3(9.5, 8, -35), Vector2(11, 5))
	_floor("Quadra", Vector3(25, 0, -44.5), Vector2(22, 21))
	_ramp("EscadaDoFarol", Vector3(10, 0, 14), Vector3(10, 4, -2), 5.2)
	_ramp("DescidaDaChuva", Vector3(-24, 0, -15.5), Vector3(-24, -4, -31), 5)
	_ramp("EscadaDasAntenas", Vector3(11, 4, -17), Vector3(11, 8, -32.5), 4.6)
	_ramp("EscadaDaQuadra", Vector3(32, 4, -18), Vector3(32, 0, -34), 5)
	_ramp("PassarelaDoEco", Vector3(15, 8, -36), Vector3(29, 0, -36), 3.8)
	# Flat turn landings keep perpendicular ramp volumes from capping one another.
	_ramp("SaidaDoSubsolo", Vector3(-10, -4, -40), Vector3(0, 0, -40), 4)
	_floor("ServiceLowerLanding", Vector3(2, 0, -40), Vector2(4, 4))
	_ramp("EscadaDeServicoA", Vector3(2, 0, -42), Vector3(2, 4, -52), 4)
	_edge(Vector3(4, 0, -42), Vector3(4, 0, -38), 1.6)
	_edge(Vector3(0, 0, -38), Vector3(4, 0, -38), 1.6)
	_floor("SwitchbackLanding", Vector3(-1.5, 4, -53.7), Vector2(11, 3.4))
	_ramp("EscadaDeServicoB", Vector3(-5, 4, -53), Vector3(-5, 8, -43), 4)
	# Retaining walls and railings follow actual edges; narrow openings belong to routes.
	_edge(Vector3(-12, 0, 11), Vector3(-12, 0, 25), 1.8)
	_edge(Vector3(-12, 0, 25), Vector3(-3, 0, 25), 1.8)
	_edge(Vector3(3, 0, 25), Vector3(12, 0, 25), 1.8)
	_edge(Vector3(12, 0, 25), Vector3(12, 0, 15), 1.8)
	_edge(Vector3(-12, 0, 4), Vector3(7.4, 0, 4), 1.5)
	_edge(Vector3(-31, 0, -15.5), Vector3(-31, 0, 7.5), 2.5)
	_edge(Vector3(-31, 0, -15.5), Vector3(-26.5, 0, -15.5), 2.1)
	_edge(Vector3(-21.5, 0, -15.5), Vector3(-9, 0, -15.5), 2.1)
	_edge(Vector3(-9, 0, -15.5), Vector3(-9, 0, 4.8), 2.1)
	_edge(Vector3(-31, 0, 7.5), Vector3(-22, 0, 7.5), 2.1)
	_edge(Vector3(-22, 0, 11), Vector3(-5, 0, 11), 1.5)
	_edge(Vector3(7, 4, -17), Vector3(7, 4, 5), 1.4)
	_edge(Vector3(7, 4, 5), Vector3(7.4, 4, 5), 1.4)
	_edge(Vector3(12.6, 4, 5), Vector3(28, 4, 5), 1.4)
	_edge(Vector3(28, 4, 5), Vector3(28, 4, -4), 1.5)
	_edge(Vector3(28, 4, -10), Vector3(28, 4, -13), 1.5)
	_edge(Vector3(7, 4, -17), Vector3(8.7, 4, -17), 1.5)
	_edge(Vector3(13.3, 4, -17), Vector3(24, 4, -17), 1.5)
	_edge(Vector3(24, 4, -18), Vector3(29.5, 4, -18), 1.5)
	_edge(Vector3(34.5, 4, -18), Vector3(35, 4, -18), 1.5)
	_edge(Vector3(35, 4, -18), Vector3(35, 4, -13), 1.5)
	_edge(Vector3(28, 4, -13), Vector3(35, 4, -13), 1.5)
	_edge(Vector3(-30, -4, -31), Vector3(-26.5, -4, -31), 3.5)
	_edge(Vector3(-21.5, -4, -31), Vector3(-7, -4, -31), 3.5)
	_edge(Vector3(-30, -4, -31), Vector3(-30, -4, -44), 3.5)
	_edge(Vector3(-30, -4, -44), Vector3(-7, -4, -44), 3.5)
	_edge(Vector3(-7, -4, -31), Vector3(-7, -4, -38), 3.5)
	_edge(Vector3(-7, -4, -42), Vector3(-7, -4, -44), 3.5)
	_edge(Vector3(-8, 8, -43), Vector3(-8, 8, -24), 1.5)
	_edge(Vector3(-8, 8, -24), Vector3(7, 8, -24), 1.5)
	_edge(Vector3(7, 8, -24), Vector3(7, 8, -32.5), 1.5)
	_edge(Vector3(7, 8, -37.5), Vector3(7, 8, -43), 1.5)
	_edge(Vector3(-8, 8, -43), Vector3(-7, 8, -43), 1.5)
	_edge(Vector3(-3, 8, -43), Vector3(7, 8, -43), 1.5)
	_edge(Vector3(7, 8, -32.5), Vector3(8.7, 8, -32.5), 1.5)
	_edge(Vector3(13.3, 8, -32.5), Vector3(15, 8, -32.5), 1.5)
	_edge(Vector3(7, 8, -37.5), Vector3(15, 8, -37.5), 1.5)
	_edge(Vector3(15, 8, -32.5), Vector3(15, 8, -34.1), 1.5)
	_edge(Vector3(14, 0, -34), Vector3(29.5, 0, -34), 2.7)
	_edge(Vector3(34.5, 0, -34), Vector3(36, 0, -34), 2.7)
	_edge(Vector3(36, 0, -34), Vector3(36, 0, -55), 2.7)
	_edge(Vector3(36, 0, -55), Vector3(14, 0, -55), 2.7)
	_edge(Vector3(14, 0, -55), Vector3(14, 0, -34), 2.7)
	# The basin is far below playable floors; exterior blocks read as a hillside city.
	_box("Hillside", Vector3(1, -11, -14), Vector3(80, 10, 100), Color("23373c"))

func _floor(label: String, center: Vector3, size: Vector2) -> void:
	_box(label + "Slab", center - Vector3(0, 0.55, 0), Vector3(size.x, 1.1, size.y), STONE, true)
	for index in range(maxi(1, int(size.y / 3))):
		_box("DrainageJoint", center + Vector3(0, 0.015, -size.y / 2 + index * 3), Vector3(size.x - 0.1, 0.022, 0.018), STONE.darkened(0.2))

func _ramp(label: String, start: Vector3, finish: Vector3, width: float) -> void:
	var flat := Vector3(finish.x - start.x, 0, finish.z - start.z)
	var perpendicular := Vector3(-flat.z, 0, flat.x).normalized()
	var bottom := minf(start.y, finish.y) - 0.6
	var shape := ConvexPolygonShape3D.new()
	var points := PackedVector3Array()
	for p: Vector3 in [start, finish]:
		for side: float in [-1.0, 1.0]:
			var corner := p + perpendicular * width * 0.5 * side
			points.append(corner)
			points.append(Vector3(corner.x, bottom, corner.z))
	shape.points = points
	var body := StaticBody3D.new()
	body.name = label + "SmoothCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	_geometry.add_child(body)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	var step_count := maxi(12, int(absf(finish.y - start.y) / 0.17))
	var depth := flat.length() / step_count
	for index in range(step_count):
		var a := start.lerp(finish, float(index) / step_count)
		var b := start.lerp(finish, float(index + 1) / step_count)
		var p := (a + b) * 0.5
		p.y = maxf(a.y, b.y) - 0.13
		var step := _box(label + "Tread", p, Vector3(width, 0.26, depth + 0.03), STONE.lightened(0.05) if index % 2 else STONE)
		step.rotation.y = atan2(flat.x, flat.z)
	for side: float in [-1.0, 1.0]:
		var a := start + perpendicular * (width / 2 + 0.1) * side
		var b := finish + perpendicular * (width / 2 + 0.1) * side
		# Sloping solid parapets leave neither holes beside the steps nor invisible floors.
		_beam(a + Vector3(0, 0.8, 0), b + Vector3(0, 0.8, 0), 0.2, 1.6, TEAL, true)
		_cylinder_between(a + Vector3(0, 1.65, 0), b + Vector3(0, 1.65, 0), 0.045, RUST)

func _edge(a: Vector3, b: Vector3, height: float) -> void:
	if a.distance_to(b) < 0.05:
		return
	_beam(a + Vector3(0, height / 2, 0), b + Vector3(0, height / 2, 0), 0.32, height, BRICK, true)
	_beam(a + Vector3(0, height, 0), b + Vector3(0, height, 0), 0.43, 0.09, PLASTER)

func _build_architecture() -> void:
	# The patio keeps the player and Faro visible; neighboring volumes frame it closely.
	_house(Vector3(-10, 0, 18.5), Vector3(4, 7.7, 11), BRICK, true)
	_house(Vector3(8.3, 0, 22.4), Vector3(6.8, 5.1, 4.5), TEAL, false)
	_house(Vector3(-4.5, 0, 3.5), Vector3(7, 8.7, 4), PLASTER, true)
	_house(Vector3(16.5, 0, 17), Vector3(6, 11.8, 9), BRICK, false)
	_box("PatioCanopy", Vector3(-6.6, 3.8, 15.5), Vector3(5, 0.16, 7), RUST)
	_sign("FERRO DO MORRO", Vector3(-6.0, 3.05, 17.1), 3.8)
	_sign("JARDIM  ↓", Vector3(-5.5, 2.1, 24.78), 3.8, PI)
	_bench(Vector3(-3.8, 0, 21.6))
	_bench(Vector3(3.5, 0, 6))
	_puddle(Vector3(1.3, 0.022, 13.2), Vector2(4.8, 2.5))
	_puddle(Vector3(-5.5, 0.023, 8.2), Vector2(3.5, 1.7))
	_lamp(Vector3(-6.5, 3.2, 16.5), WARM, 9)
	_lamp(Vector3(4.5, 3.3, 23), WARM, 9)
	_lamp(Vector3(-0.7, 4.5, 4.7), Color("9ddbe1"), 7)
	# Market traffic turns around a central occupied building and through a covered room.
	_house(Vector3(-21, 0, -4.7), Vector3(7, 8.3, 7.5), TEAL, true)
	_house(Vector3(-29, 0, -5), Vector3(3.5, 10.4, 9), BRICK, false)
	_house(Vector3(-12, 0, -12.8), Vector3(5, 5.4, 3.5), PLASTER, true)
	_house(Vector3(-29, 0, 6), Vector3(4, 6.3, 3), TEAL, false)
	_room(Vector3(-14, 0, -3), Vector2(6, 7), 3.6, "market")
	_box("PassageRoof", Vector3(-15, 3.5, 8), Vector3(14, 0.22, 6), DARK)
	for x: float in [-20, -13, -7]:
		_box("PassagePillar", Vector3(x, 1.65, 10.2), Vector3(0.25, 3.3, 0.25), RUST, true)
	_stall(Vector3(-27, 0, 3.3))
	_sign("BECO DAS MARÉS", Vector3(-21, 3, 5), 4.5)
	_puddle(Vector3(-25.5, 0.025, -10), Vector2(2.8, 4))
	_lamp(Vector3(-26, 3.5, 3), WARM, 9)
	_lamp(Vector3(-13.5, 2.8, -4), Color("83cad3"), 7)
	# Workshop: three exits, including the bridge to the cinema service stair.
	_room(Vector3(20.5, 4, -6), Vector2(11, 14), 4.3, "workshop", true)
	_box("WorkshopBench", Vector3(24, 4.6, -11), Vector3(1.0, 1.2, 2), RUST, true)
	for z: float in [-11.6, -10.2, -8.8]:
		_box("ToolBoard", Vector3(25.75, 6.2, z), Vector3(0.08, 1.1, 0.8), DARK)
	_house(Vector3(17, 4, 3.5), Vector3(7, 7.4, 3), BRICK, false)
	_sign("OFICINA SUSPENSA", Vector3(20, 7.3, 1.06), 5.5)
	_lamp(Vector3(20.4, 7.6, -6), WARM, 10)
	# A roofed basement below street level; the deep entrance remains visible from above.
	_box("GalleryCeiling", Vector3(-18.5, 0.2, -37.5), Vector3(23, 0.45, 13), BRICK, true)
	for x: float in [-27, -20, -12]:
		_box("GalleryPillar", Vector3(x, -2, -33), Vector3(0.4, 4, 0.4), TEAL, true)
	for z: float in [-43, -32]:
		_cylinder_between(Vector3(-29, -0.8, z), Vector3(-8, -0.8, z), 0.14, RUST)
	_box("GalleryPartition", Vector3(-19, -2.5, -39.5), Vector3(0.35, 3, 5), BRICK, true)
	_box("GalleryGrate", Vector3(-22.8, -3.975, -35.3), Vector3(3.4, 0.04, 0.9), DARK)
	_sign("GALERIA DA CHUVA", Vector3(-24, 1.5, -15.05), 4.5)
	_lamp(Vector3(-25, -0.7, -35), Color("77cdd0"), 8)
	_lamp(Vector3(-11, -0.7, -41), WARM, 8)
	# Inhabited rooftops form a second circulation layer, with accessible tank platforms.
	_box("RoofShed", Vector3(-5.8, 9.7, -34), Vector3(3.3, 3.4, 5), TEAL, true)
	_box("ShedRoof", Vector3(-5.8, 11.45, -34), Vector3(3.8, 0.12, 5.5), RUST)
	_cylinder("Tank", Vector3(4.8, 9, -33), 1.3, 2, TEAL, true)
	_cylinder("TankLid", Vector3(4.8, 10.06, -33), 1.42, 0.12, DARK)
	_cylinder_between(Vector3(1.5, 8, -41), Vector3(1.5, 16, -41), 0.07, PLASTER)
	for y: float in [12, 14.4, 15.5]:
		_cylinder_between(Vector3(-0.4, y, -41), Vector3(3.4, y, -41), 0.035, DARK)
	_box("RooftopAwning", Vector3(0, 10.8, -27), Vector3(8, 0.12, 4), RUST)
	_cable(Vector3(-6, 12.3, -31), Vector3(6, 12.0, -30))
	for index in range(5):
		var cloth := _box("ResidentLaundry", Vector3(-3.4 + index * 1.45, 10.95, -30.5), Vector3(0.9, 1.15, 0.04), [PLASTER, RUST, TEAL, BRICK, PLASTER][index])
		cloth.rotation.y = -0.08 + index * 0.035
	_lamp(Vector3(-0.5, 10.4, -27.5), WARM, 8)
	# Enclosed sports court: its entrance descent and upper bridge offer two approaches.
	_box("CourtSurface", Vector3(25, 0.02, -44.5), Vector3(19.5, 0.035, 18.5), Color("344e52"))
	for x: float in [16, 34]:
		_box("CourtLine", Vector3(x, 0.045, -44.5), Vector3(0.1, 0.02, 17), Color("8b9990"))
	for z: float in [-36, -53, -44.5]:
		_box("CourtLine", Vector3(25, 0.045, z), Vector3(18, 0.02, 0.1), Color("8b9990"))
	for x: float in [14.1, 35.9]:
		for z in range(-54, -34, 3):
			_cylinder_between(Vector3(x, 2.6, z), Vector3(x, 5.2, z), 0.03, DARK)
		_cylinder_between(Vector3(x, 5.2, -54), Vector3(x, 5.2, -35), 0.04, DARK)
	_box("GoalBackboard", Vector3(25, 3.9, -54.7), Vector3(4, 1.9, 0.16), PLASTER)
	_sign("QUADRA DO ECO", Vector3(25, 2.1, -54.77), 5)
	_lamp(Vector3(34, 5.6, -49), Color("e3a091"), 12)
	# Architectural density continues beyond the collision edges, without extra bodies.
	for spec: Array in [[-36, 0, -7, 7, 14, 15], [-34, 1, -27, 6, 17, 12], [-18, 2, -50, 13, 12, 7], [21, 4, -25, 9, 14, 11], [42, 0, -40, 9, 18, 18], [-25, 1, 31, 12, 9, 7], [-18, 0, 24, 7, 13, 10]]:
		var p := Vector3(spec[0], spec[1], spec[2])
		var size := Vector3(spec[3], spec[4], spec[5])
		_box("BeyondTheDistrict", p + Vector3(0, size.y / 2, 0), size, BRICK.darkened(0.15))
		for floor_index in range(1, int(size.y / 2.8)):
			_box("DistantWindow", p + Vector3(0, floor_index * 2.6, size.z / 2 + 0.03), Vector3(0.8, 1.2, 0.04), Color("9c805e"), false, 0.45)
	for ends: Array in [[Vector3(-9, 7, 19), Vector3(12, 9, 15)], [Vector3(-29, 9, -6), Vector3(-10, 8, -9)], [Vector3(3, 12, -27), Vector3(24, 11, -12)], [Vector3(-11, 5, 6), Vector3(-25, 6, 2)]]:
		_cable(ends[0], ends[1])
	for p: Vector3 in [Vector3(-6, 0, 23), Vector3(-16, 0, 10), Vector3(26.5, 4, 2), Vector3(6, 8, -41)]:
		_planter(p)

func _room(center: Vector3, size: Vector2, height: float, label: String, east_exit: bool = false) -> void:
	# Door gaps remain in collision; interiors are destinations, not facade textures.
	_box(label + "Roof", center + Vector3(0, height, 0), Vector3(size.x, 0.25, size.y), DARK, true)
	_box(label + "RearWall", center + Vector3(0, height / 2, -size.y / 2), Vector3(size.x, height, 0.3), PLASTER, true)
	if east_exit:
		for side: float in [-1.0, 1.0]:
			_box(label + "EastDoorPier", center + Vector3(size.x / 2, height / 2, side * (size.y / 4 + 1)), Vector3(0.3, height, size.y / 2 - 2), BRICK, true)
	else:
		_box(label + "SideWall", center + Vector3(size.x / 2, height / 2, 0), Vector3(0.3, height, size.y), BRICK, true)
	for side: float in [-1.0, 1.0]:
		_box(label + "FrontPier", center + Vector3(side * (size.x / 4 + 0.75), height / 2, size.y / 2), Vector3(size.x / 2 - 1.5, height, 0.3), TEAL, true)
		_box(label + "SidePier", center + Vector3(-size.x / 2, height / 2, side * (size.y / 4 + 0.9)), Vector3(0.3, height, size.y / 2 - 1.8), TEAL, true)
	_box(label + "DoorLintel", center + Vector3(0, height - 0.25, size.y / 2), Vector3(3.1, 0.5, 0.3), RUST, true)

func _house(p: Vector3, size: Vector3, color: Color, left: bool) -> void:
	_box("OccupiedHouse", p + Vector3(0, size.y / 2, 0), size, color, true)
	_box("RoofRim", p + Vector3(0, size.y + 0.12, 0), Vector3(size.x + 0.18, 0.25, size.z + 0.18), DARK)
	for floor_index in range(maxi(1, int(size.y / 2.6))):
		var y := p.y + 1.4 + floor_index * 2.6
		for offset: float in [-0.25, 0.25]:
			var wp := Vector3(p.x + size.x * offset, y, p.z + size.z / 2 + 0.025)
			_box("WindowRecess", wp, Vector3(1.0, 1.3, 0.065), DARK)
			_box("WindowGlow", wp + Vector3(0, 0, 0.04), Vector3(0.78, 1.08, 0.035), Color("bc946a") if floor_index % 2 == 0 else Color("507277"), false, 0.6 if floor_index % 2 == 0 else 0.15)
			_box("WindowMullion", wp + Vector3(0, 0, 0.075), Vector3(0.06, 1.1, 0.05), DARK)
	var side := 1.0 if left else -1.0
	_box("SideDoor", p + Vector3(side * (size.x / 2 + 0.04), 1.15, 1), Vector3(0.08, 2.3, 1.25), DARK)
	_cylinder_between(p + Vector3(side * (size.x / 2 + 0.1), 0.2, -size.z / 2 + 0.3), p + Vector3(side * (size.x / 2 + 0.1), size.y, -size.z / 2 + 0.3), 0.07, RUST)
	for line_index in range(1, int(size.y / 0.8)):
		_box("PlasterCourse", p + Vector3(0, line_index * 0.8, size.z / 2 + 0.012), Vector3(size.x, 0.025, 0.02), color.darkened(0.09))

func _build_interactables() -> void:
	for point: Dictionary in points_of_interest:
		var p: Vector3 = point.position
		p.y -= 0.2
		match String(point.type):
			"chest":
				# Offset the prop so the interaction point itself remains a walkable destination.
				_box("SupplyChest", p + Vector3(0.85, 0.38, 0), Vector3(1.05, 0.7, 0.7), RUST, true)
				_box("ChestBand", p + Vector3(0.85, 0.75, 0), Vector3(1.08, 0.07, 0.74), DARK)
				_box("ChestLatch", p + Vector3(0.85, 0.46, 0.37), Vector3(0.13, 0.2, 0.035), WARM, false, 0.8)
			"cache":
				_box("SupplyCase", p + Vector3(0.8, 0.24, 0), Vector3(0.7, 0.48, 0.6), TEAL, true)
				_box("CacheMark", p + Vector3(0.8, 0.5, 0), Vector3(0.35, 0.03, 0.3), Color("83cbc1"), false, 0.6)
			"forge":
				_box("ForgeBench", p + Vector3(-1.0, 0.4, 0), Vector3(1, 0.8, 2), RUST, true)
				_box("Anvil", p + Vector3(-1.0, 1.0, 0), Vector3(0.7, 0.35, 1), DARK)
			"challenge":
				_cylinder("SignalBase", p + Vector3(0.8, 0.38, 0), 0.32, 0.7, TEAL, true)
				_cylinder("SignalLamp", p + Vector3(0.8, 0.83, 0), 0.11, 0.2, Color("8ae2dc"), false, 1.4)
			"boss":
				_cylinder("EchoReceiver", p + Vector3(1.1, 0.5, 0), 0.4, 1, DARK, true)
				_box("EchoEye", p + Vector3(1.1, 1.04, 0), Vector3(0.22, 0.12, 0.22), Color("dc7466"), false, 1.0)

func _build_gates() -> void:
	_gate("oficina", Vector3(10, 0.65, 11.4), 5.2, false, "porta_oficina_patio")
	_gate("oficina", Vector3(11, 4.568, -19.2), 4.6, false, "porta_oficina_lajes")
	_gate("galeria", Vector3(-24, -0.335, -16.8), 5, false, "porta_galeria_mercado")
	_gate("galeria", Vector3(-7.7, -3.08, -40), 4, true, "porta_galeria_lajes")
	_gate("lajes", Vector3(11, 7.381, -30.1), 4.6, false, "porta_lajes_oficina")
	_gate("lajes", Vector3(-5, 7.44, -44.4), 4, false, "porta_lajes_galeria")
	_gate("lajes", Vector3(16.7, 7.03, -36), 3.8, true, "porta_lajes_quadra")
	_gate("quadra", Vector3(32, 0.3, -32.8), 5, false, "porta_quadra_oficina")
	_gate("quadra", Vector3(27.4, 0.914, -36), 3.8, true, "porta_quadra_lajes")
	Expansion.gates(self)
	_apply_gate_state()

func _gate(region_id: String, p: Vector3, width: float, along_z: bool, poi_id: String) -> void:
	var node := Node3D.new()
	node.name = "Gate_" + region_id
	node.position = p
	if along_z:
		node.rotation.y = PI / 2
	add_child(node)
	var body := StaticBody3D.new()
	body.collision_layer = GATE_COLLISION_LAYER
	body.collision_mask = 0
	node.add_child(body)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, 3.7, 0.22)
	collider.shape = shape
	collider.position.y = 1.85
	body.add_child(collider)
	for index in range(int(width / 0.35) + 1):
		var visual := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.075, 3.5, 0.09)
		visual.mesh = mesh
		visual.material_override = _material(TEAL.lightened(0.12))
		visual.position = Vector3(-width / 2 + index * 0.35, 1.75, 0)
		node.add_child(visual)
	for y: float in [0.5, 2.7]:
		var visual := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(width, 0.14, 0.12)
		visual.mesh = mesh
		visual.material_override = _material(RUST)
		visual.position.y = y
		node.add_child(visual)
	if not _gates.has(region_id):
		_gates[region_id] = []
	_gates[region_id].append({"node": node, "collider": collider, "poi_id": poi_id})

func _apply_gate_state() -> void:
	for region_id: String in _gates:
		var opened := unlocked_regions.has(region_id) and not (_boss_arena and region_id == "quadra")
		for gate: Dictionary in _gates[region_id]:
			gate.node.visible = not opened
			gate.collider.set_deferred("disabled", opened)

func _build_lighting() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	_environment = environment
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("15232e")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("9dc1d0")
	environment.ambient_light_energy = 0.38
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("243c46")
	environment.fog_light_energy = 0.85
	environment.fog_density = 0.008
	environment_node.environment = environment
	add_child(environment_node)
	var moon := DirectionalLight3D.new()
	_moon = moon
	moon.rotation_degrees = Vector3(-48, -33, 0)
	moon.light_color = Color("a6cbdc")
	moon.light_energy = 0.28
	moon.shadow_enabled = true
	moon.set_meta("authored_shadow_enabled", true)
	moon.directional_shadow_max_distance = 90
	add_child(moon)

func _build_rain() -> void:
	var rain := MultiMeshInstance3D.new()
	_rain = rain
	rain.name = "BoundedRain"
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.015, 0.62, 0.012)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_custom_data = true
	multi.mesh = mesh
	multi.instance_count = 850
	var rng := RandomNumberGenerator.new()
	rng.seed = 417
	for index in range(multi.instance_count):
		var x := rng.randf_range(-34, 74)
		var z := rng.randf_range(-59, 76)
		if index < 200:
			x = rng.randf_range(-7, 12)
			z = rng.randf_range(5, 25)
		# Roofed interiors and the gallery remain dry below their ceilings.
		var base := 1.0 if x < -7 and z < -30 and z > -45 else -1.0
		if x > 14 and x < 27 and z > -14 and z < 2:
			base = 8.5
		if x < -10 and x > -18 and z > -7 and z < 1:
			base = 4.0
		if x >= 24 and z >= 24: base = 10.2
		elif x >= 30 and z >= -14: base = 8.4
		elif x > -13 and x < -3 and z > 56 and z < 66: base = 4.3
		elif x > 11 and x < 15 and z > 64 and z < 69: base = 3.2
		multi.set_instance_transform(index, Transform3D(Basis.IDENTITY, Vector3(x, base, z)))
		multi.set_instance_custom_data(index, Color(rng.randf(), 0, 0, 1))
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded, cull_disabled, shadows_disabled; uniform float rain_speed = 13.0; uniform float rain_alpha = 0.22; void vertex(){ VERTEX.y += mod(INSTANCE_CUSTOM.x * 21.0 - TIME * rain_speed, 21.0); VERTEX.x += VERTEX.y * 0.075; } void fragment(){ ALBEDO=vec3(0.57,0.73,0.79); ALPHA=rain_alpha; }"
	var material := ShaderMaterial.new()
	_rain_material = material
	material.shader = shader
	rain.multimesh = multi
	rain.material_override = material
	rain.custom_aabb = AABB(Vector3(-38, -3, -62), Vector3(120, 45, 142))
	add_child(rain)

func _material(color: Color, emission: float = 0) -> StandardMaterial3D:
	var key := color.to_html() + str(emission)
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	if emission <= 0 and color != DARK and color != WARM and color != RUST:
		if _surface_grain == null:
			var noise := FastNoiseLite.new()
			noise.seed = 9237
			noise.frequency = 0.09
			noise.fractal_octaves = 4
			var ramp := Gradient.new()
			ramp.colors = PackedColorArray([Color(0.75, 0.75, 0.75), Color(0.9, 0.9, 0.9)])
			_surface_grain = NoiseTexture2D.new()
			_surface_grain.width = 256
			_surface_grain.height = 256
			_surface_grain.seamless = true
			_surface_grain.color_ramp = ramp
			_surface_grain.noise = noise
		material.albedo_texture = _surface_grain
		material.uv1_triplanar = true
		material.uv1_world_triplanar = true
		material.uv1_scale = Vector3(0.45, 0.45, 0.45)
		if color == STONE:
			material.roughness = 0.48
	if emission > 0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission * lerpf(0.15, 1.0, _effect_level)
		_emissive_materials.append({"material":material,"energy":emission})
	_materials[key] = material
	return material

func _box(label: String, p: Vector3, size: Vector3, color: Color, collision: bool = false, emission: float = 0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.position = p
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = _material(color, emission)
	_geometry.add_child(node)
	if collision:
		var shape := BoxShape3D.new()
		shape.size = size
		_attach_collision(node, shape)
	return node

func _attach_collision(node: Node3D, shape: Shape3D) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	node.add_child(body)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)

func _beam(a: Vector3, b: Vector3, width: float, height: float, color: Color, collision: bool = false) -> void:
	var node := _box("ParapetOrLintel", (a + b) / 2, Vector3(width, height, a.distance_to(b)), color, collision)
	node.look_at_from_position((a + b) / 2, b)

func _cylinder(label: String, p: Vector3, radius: float, length: float, color: Color, collision: bool = false, emission: float = 0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.position = p
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 10
	node.mesh = mesh
	node.material_override = _material(color, emission)
	_geometry.add_child(node)
	if collision:
		var shape := CylinderShape3D.new()
		shape.height = length
		shape.radius = radius
		_attach_collision(node, shape)
	return node

func _cylinder_between(a: Vector3, b: Vector3, radius: float, color: Color) -> void:
	var node := _cylinder("PipeOrCable", (a + b) / 2, radius, a.distance_to(b), color)
	node.quaternion = Quaternion(Vector3.UP, (b - a).normalized())

func _cable(a: Vector3, b: Vector3) -> void:
	var previous := a
	for index in range(1, 11):
		var t := index / 10.0
		var next := a.lerp(b, t) - Vector3(0, sin(t * PI) * 1.2, 0)
		_cylinder_between(previous, next, 0.025, DARK)
		previous = next

func _sign(value: String, p: Vector3, width: float, rotation_y: float = 0) -> void:
	var backing := _box("PaintedSign", p, Vector3(width, 0.7, 0.09), DARK)
	backing.rotation.y = rotation_y
	var label := Label3D.new()
	label.text = value
	label.font_size = 40
	label.pixel_size = width / maxf(120, value.length() * 26)
	label.modulate = Color("cfbea3")
	label.outline_size = 0
	label.position = Vector3(0, 0, 0.055)
	backing.add_child(label)

func _lamp(p: Vector3, color: Color, radius: float) -> void:
	_box("LampHousing", p, Vector3(0.5, 0.2, 0.3), DARK)
	_box("LampBulb", p - Vector3(0, 0.13, 0), Vector3(0.34, 0.06, 0.2), color, false, 1.5)
	var light := OmniLight3D.new()
	light.position = p - Vector3(0, 0.25, 0)
	light.light_color = color
	light.light_energy = 2.0
	light.omni_range = radius
	light.omni_attenuation = 1.3
	light.shadow_enabled = _lights.size() < 2
	light.set_meta("authored_shadow_enabled", _lights.size() < 2)
	add_child(light)
	_lights.append(light)

func _puddle(p: Vector3, size: Vector2) -> void:
	var node := MeshInstance3D.new()
	node.name = "RainPuddle"
	node.position = p
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(28):
		var a := index * TAU / 28.0
		var b := (index + 1) * TAU / 28.0
		var radius_a := 0.88 + sin(a * 5.0) * 0.08 + cos(a * 3.0) * 0.04
		var radius_b := 0.88 + sin(b * 5.0) * 0.08 + cos(b * 3.0) * 0.04
		for vertex: Vector3 in [Vector3.ZERO, Vector3(cos(b) * size.x * 0.5, 0, sin(b) * size.y * 0.5) * radius_b, Vector3(cos(a) * size.x * 0.5, 0, sin(a) * size.y * 0.5) * radius_a]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(vertex)
	node.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("3c5058")
	material.roughness = 0.13
	material.metallic = 0.38
	node.material_override = material
	_geometry.add_child(node)
	_puddles.append(node)

func _bench(p: Vector3) -> void:
	_box("BenchSeat", p + Vector3(0, 0.55, 0), Vector3(2.6, 0.14, 0.65), RUST, true)
	_box("BenchBack", p + Vector3(0, 0.98, -0.28), Vector3(2.6, 0.8, 0.1), RUST)
	for side: float in [-1, 1]:
		_box("BenchLeg", p + Vector3(side, 0.26, 0), Vector3(0.12, 0.52, 0.48), DARK)

func _stall(p: Vector3) -> void:
	_box("MerchantCounter", p + Vector3(0, 0.6, 0.8), Vector3(3, 1.2, 1), RUST, true)
	_box("MerchantAwning", p + Vector3(0, 2.8, 0.5), Vector3(3.8, 0.12, 3.2), TEAL)
	for x: float in [-1.7, 1.7]:
		_cylinder("StallPost", p + Vector3(x, 1.4, 1.9), 0.05, 2.8, RUST)
	for x: float in [-0.8, 0, 0.8]:
		_box("MarketCrate", p + Vector3(x, 1.4, 0.8), Vector3(0.62, 0.4, 0.65), PLASTER)

func _planter(p: Vector3) -> void:
	_box("ResidentPlanter", p + Vector3(0, 0.3, 0), Vector3(0.8, 0.6, 0.8), RUST, true)
	for side: float in [-1, 0, 1]:
		var leaf := _box("BroadLeaf", p + Vector3(side * 0.18, 0.9, 0), Vector3(0.24, 1.1, 0.05), Color("416359"))
		leaf.rotation.z = side * 0.4
		_vegetation.append(leaf)

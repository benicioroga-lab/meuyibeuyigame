extends SceneTree
## Integration checks use the real baked map and native physics, without mocks.

const World = preload("res://scripts/world.gd")

var _world: Node3D
var _checks: int = 0
var _failures: Array[String] = []
var _routes: int = 0
var _finished: bool = false
var _map: RID
var _start: Vector3


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(40.0, true).timeout.connect(_timeout)
	seed(394726)
	_world = World.new()
	root.add_child(_world)
	current_scene = _world
	for frame in range(600):
		await physics_frame
		if _world.navigation_ready:
			break
	_check(_world.navigation_ready, "The world finishes baking a native navigation mesh")
	if not _world.navigation_ready:
		await _finish()
		return
	_map = _world.get_world_3d().navigation_map
	_check_manifold_navigation()
	NavigationServer3D.map_force_update(_map)
	_start = NavigationServer3D.map_get_closest_point(_map, _world.spawn_position)
	_check(_start.distance_to(_world.spawn_position) < 1.0, "Player spawn lies on native navigation")
	_check_ground(_world.spawn_position, "Player spawn")
	for index in range(_world.spawn_points.size()):
		_check_destination(_world.spawn_points[index], "Enemy spawn %d" % index)
	for shop: Dictionary in _world.shops:
		_check_destination(shop["position"], "Shop %s" % shop["id"])
	_check(_world.regions.size() == 9, "Nine distinct districts exist")
	for region: Dictionary in _world.regions:
		_check(_world.get_region_id(region.center) == region.id, "District centers identify their region: " + region.id)
		_check_destination(region.center, "District " + region.id)
	for point: Dictionary in _world.points_of_interest:
		_check_destination(point.position, "POI " + point.id)
	for landmark: String in World.Expansion.LANDMARKS:
		_check_destination(World.Expansion.LANDMARKS[landmark], "Interior " + landmark)
	for index in range(100):
		var spawn: Vector3 = _world.get_spawn_near(Vector3(50, 8, -80), 9999)
		_check(_world.unlocked_regions.has(_world.get_region_id(spawn)), "Spawn fallback stays in an unlocked district")
	_check(not _world.unlock_region("invalid"), "Unknown district unlock is rejected")
	var initial_state: Dictionary = _world.export_state()
	for region: Dictionary in _world.regions:
		if region.id in ["patio", "mercado"]:
			continue
		for gate: Dictionary in _world._gates[region.id]:
			_check(not gate.collider.disabled, "Locked gate has a physical barrier: " + region.id)
			_check_gate_physics(gate, true)
			for side: float in [-1.0, 1.0]:
				var observer: Vector3 = gate.node.global_position + gate.node.global_basis.z * side * 2.0
				var found := false
				for poi: Dictionary in _world.interactables(observer):
					if poi.id != gate.poi_id: continue
					found = true
					_check((Vector3(poi.position) - gate.node.global_position).dot(gate.node.global_basis.z) * side > 0.5, "Gate interaction appears on the observer's physical side: " + gate.poi_id)
					_check_ground(poi.position, "Bidirectional gate " + gate.poi_id)
				_check(found, "A locked gate can be purchased from either side: " + gate.poi_id)
		_check(_world.unlock_region(region.id), "Known district unlock succeeds: " + region.id)
		await physics_frame
		await physics_frame
		for gate: Dictionary in _world._gates[region.id]:
			_check(gate.collider.disabled and not gate.node.visible, "Unlocked gate clears collision and mesh: " + region.id)
			_check_gate_physics(gate, false)
	_world.set_boss_arena(true)
	for region: Dictionary in _world.regions:
		for sample in range(12):
			var spawn: Vector3 = _world.get_spawn_near(region.center, 8)
			_check(_world.get_region_id(spawn) == region.id, "Local spawns retain combat pressure in " + region.id)
	await physics_frame
	await physics_frame
	for gate: Dictionary in _world._gates["quadra"]:
		_check(not gate.collider.disabled, "Boss encounter physically closes each arena exit")
		_check_gate_physics(gate, true)
	_check(not _world.can_purchase_region("quadra"), "Boss arena gates cannot be bought to bypass the encounter")
	_world.set_boss_arena(false)
	await physics_frame
	await physics_frame
	for gate: Dictionary in _world._gates["quadra"]:
		_check(gate.collider.disabled, "Boss completion reopens each arena exit")
	# Sample the actual walk collider, catching slabs that accidentally cap a ramp.
	var flights: Array = [
		[Vector3(10, 0, 14), Vector3(10, 4, -2)],
		[Vector3(-24, 0, -15.5), Vector3(-24, -4, -31)],
		[Vector3(11, 4, -17), Vector3(11, 8, -32.5)],
		[Vector3(32, 4, -18), Vector3(32, 0, -34)],
		[Vector3(15, 8, -36), Vector3(29, 0, -36)],
		[Vector3(-10, -4, -40), Vector3(0, 0, -40)],
		[Vector3(2, 0, -42), Vector3(2, 4, -52)],
		[Vector3(-5, 4, -53), Vector3(-5, 8, -43)]
	]
	flights.append_array(World.Expansion.STAIRS)
	for index in range(flights.size()):
		var begin: Vector3 = flights[index][0]
		var end: Vector3 = flights[index][1]
		for sample in range(65):
			var expected_surface := begin.lerp(end, sample / 64.0)
			_check_ground(expected_surface + Vector3.UP * 0.25, "Stair flight %d sample %d" % [index, sample])
			var query := PhysicsRayQueryParameters3D.create(expected_surface + Vector3.UP * 0.7, expected_surface + Vector3.DOWN * 1.5, 1)
			var hit := _world.get_world_3d().direct_space_state.intersect_ray(query)
			_check(not hit.is_empty() and absf(float(hit.get("position", Vector3.ZERO).y) - expected_surface.y) < 0.025, "Stair flight %d sample %d has no slab lip above its smooth collider" % [index, sample])
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_world.export_state()))
	_check(_world.import_state(initial_state), "Initial region state can be restored")
	_check(_world.unlocked_regions.size() == 2, "A new run restores precisely two initial districts")
	_check(_world.import_state(saved), "JSON save state restores opened districts")
	_check(_world.unlocked_regions.size() == 9, "All nine unlocked districts survive JSON persistence")
	_check(not _world.import_state({"unlocked_regions": ["bogus"]}), "Invalid saved region identifiers are rejected")
	_world.set_event("storm")
	_check(_world._environment.fog_density > 0.01, "Storm materially changes fog")
	_world.set_event("blackout")
	_check(_world._lights[0].light_energy < 0.2, "Blackout materially changes local lighting")
	_world.set_event("none")
	_world.apply_settings({"particles": 0.0, "vegetation": false, "fog": false, "shadows": 0})
	_check(not _world._rain.visible and not _world._environment.fog_enabled, "Graphics controls change rain and fog")
	_check(not _world._moon.shadow_enabled, "Graphics controls change directional shadows")
	_world.apply_graphics({"effects":0.0,"shadows":0})
	_world._process(0.13)
	for puddle: MeshInstance3D in _world._puddles:
		_check(not puddle.visible, "Effects zero removes decorative puddles")
	var glow: Dictionary = _world._emissive_materials[0]
	_check(float(glow.material.emission_energy_multiplier) < float(glow.energy) * 0.2, "Effects zero reduces decorative glow")
	_check(is_equal_approx(_world._lights[0].light_energy, 2.0), "Effects zero stops flicker while retaining readable base lighting")
	_world.apply_graphics({"effects":1.0,"shadows":3})
	_world._process(0.17)
	_check(_world._puddles[0].visible and is_equal_approx(float(glow.material.emission_energy_multiplier), float(glow.energy)), "Effects one restores puddles and authored glow")
	_check(not is_equal_approx(_world._lights[0].light_energy, 2.0), "Effects one restores graduated light flicker")
	_check(_world._moon.shadow_enabled and _world._lights[0].shadow_enabled and not _world._lights[2].shadow_enabled, "Low to high restores only authored shadow casting lights")
	_world.apply_graphics({"effects":0.0,"shadows":0})
	_check(not _world._moon.shadow_enabled and not _world._lights[0].shadow_enabled, "High to low disables shadows again")
	_check(bool(_world._moon.get_meta("authored_shadow_enabled")) and bool(_world._lights[0].get_meta("authored_shadow_enabled")), "Authored shadow metadata survives setting changes")
	await _finish()

func _check_gate_physics(gate: Dictionary, closed: bool) -> void:
	var center: Vector3 = gate.node.global_position + Vector3.UP * 1.2
	var normal: Vector3 = gate.node.global_basis.z.normalized()
	var space := _world.get_world_3d().direct_space_state
	var body: Node3D = gate.collider.get_parent()
	_check(body.collision_layer == 32, "Gate bodies occupy the movement-only collision layer")
	for side: float in [-1.0, 1.0]:
		var from := center + normal * side * 1.5
		var to := center - normal * side * 1.5
		var movement_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1 | 32))
		_check((movement_hit.get("collider") == body) == closed, "Gate movement collision matches its state from both faces: " + gate.poi_id)
		var ballistic_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
		_check(ballistic_hit.is_empty(), "Ballistic rays pass through the gate from either face: " + gate.poi_id)

func _check_manifold_navigation() -> void:
	var mesh: NavigationMesh = _world.navigation_region.navigation_mesh
	var vertices := mesh.get_vertices()
	var edges: Dictionary = {}
	for index in range(mesh.get_polygon_count()):
		var polygon := mesh.get_polygon(index)
		for corner in range(polygon.size()):
			var a := str(vertices[polygon[corner]].snapped(Vector3.ONE * 0.0001))
			var b := str(vertices[polygon[(corner + 1) % polygon.size()]].snapped(Vector3.ONE * 0.0001))
			var key := a + "|" + b if a < b else b + "|" + a
			edges[key] = int(edges.get(key, 0)) + 1
	var valid := true
	for count: int in edges.values():
		if count > 2: valid = false
	_check(valid, "Stacked interiors bake without overlapping or non-manifold navigation edges")


func _check_destination(target: Vector3, label: String) -> void:
	var closest := NavigationServer3D.map_get_closest_point(_map, target)
	_check(closest.distance_to(target) < 1.0, "%s lies on walkable navigation at %s" % [label, target])
	var path := NavigationServer3D.map_get_path(_map, _start, closest, true)
	_check(not path.is_empty(), "%s has a native route from the player spawn" % label)
	if not path.is_empty():
		_check(path[0].distance_to(_start) < 0.5, "%s route starts at the player spawn" % label)
		_check(path[-1].distance_to(closest) < 0.5, "%s route reaches its destination at %s" % [label, target])
		_routes += 1
	_check_ground(target, label)


func _check_ground(point: Vector3, label: String) -> void:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP, point + Vector3.DOWN * 3.0, 1)
	var hit := _world.get_world_3d().direct_space_state.intersect_ray(query)
	_check(not hit.is_empty(), "%s has a physical floor beneath it" % label)
	if not hit.is_empty():
		var ground: Vector3 = hit["position"]
		var normal: Vector3 = hit["normal"]
		_check(absf(ground.y - point.y) < 0.6, "%s spawn height matches the physical floor" % label)
		_check(normal.dot(Vector3.UP) > 0.7, "%s rests on a walkable physical slope" % label)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		printerr("FAIL: " + message)


func _timeout() -> void:
	if _finished:
		return
	printerr("FAIL: World integration did not complete within 40 seconds")
	quit(1)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("WORLD_INTEGRATION checks=%d routes=%d failures=%d" % [_checks, _routes, _failures.size()])
	if is_instance_valid(_world):
		_world.queue_free()
		await process_frame
	quit(0 if _failures.is_empty() else 1)

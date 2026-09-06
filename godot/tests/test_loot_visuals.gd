extends SceneTree

const Visuals = preload("res://scripts/loot_visuals.gd")
const Drop = preload("res://scripts/loot_drop.gd")
const Loot = preload("res://data/loot_data.gd")
const Data = preload("res://data/game_data.gd")
var checks := 0
var failures: Array[String] = []
var peak_triangles := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_silhouettes_and_batching()
	_test_attachments()
	_test_cache_bound()
	await _test_drops_and_persistence()
	if failures.is_empty():
		print("PASS: %d ground-loot visual checks; peak %d triangles/model; max 5 surfaces, 7 Nodes/drop; cache %s" % [checks, peak_triangles, Visuals.cache_stats()])
		quit(0)
	else:
		printerr("FAIL: %d/%d ground-loot visual checks" % [failures.size(), checks])
		quit(1)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _test_silhouettes_and_batching() -> void:
	var shapes: Dictionary = {}
	for id: String in Data.WEAPONS:
		var item := Loot.make_weapon(id, 4, "rare", 771)
		var mesh := Visuals.model("weapon", item)
		var faces := mesh.get_faces()
		_check(mesh.get_surface_count() == 1, "%s batches every piece into one surface" % id)
		_check(not shapes.has(hash(faces)), "%s has a distinct physical silhouette" % id)
		shapes[hash(faces)] = true
		_check(mesh.get_aabb().size.x > 0.45 and mesh.get_aabb().size.x < 2.3, "%s has a readable ground-weapon scale" % id)
		var triangles := Visuals.triangle_count(mesh)
		peak_triangles = maxi(peak_triangles, triangles)
		_check(triangles < 2200, "%s has a bounded polygon budget" % id)
		var duplicate := item.duplicate(true)
		duplicate.uid = "other-instance"
		duplicate.level = 100
		duplicate.rolls.damage = 1.03
		_check(Visuals.model("weapon", duplicate) == mesh, "%s instances share geometry despite different numeric rolls" % id)
		_check(mesh.surface_get_material(0) is ShaderMaterial, "%s uses shared vertex material channels" % id)
	var ammo := Visuals.model("ammo", {"amount":24})
	_check(ammo.get_aabb().size.x > 0.6 and ammo.get_aabb().size.y > 0.35, "Ammo has a visible open-box-and-cartridge profile")
	_check(Visuals.triangle_count(ammo) > 250 and Visuals.triangle_count(ammo) < 1500, "Ammo includes shaped cartridge casings and tips without a high polygon budget")
	_check(Visuals.model("ammo", {"amount":128}) == ammo, "Ammo quantities share one physical model")
	for kind: String in ["attachment", "currency", "powerup"]:
		var payload := {"id":"scope" if kind == "attachment" else "frenzy", "rarity":"epic"}
		_check(Visuals.model(kind, payload).get_surface_count() == 1, "%s presentation remains one draw surface" % kind)

func _test_attachments() -> void:
	var original := Loot.starter_weapon()
	var base := Visuals.model("weapon", original)
	for id: String in ["scope", "suppressor", "extended_mag", "laser", "heavy_receiver"]:
		var item := original.duplicate(true)
		var slot: String = Loot.ATTACHMENTS[id].slot
		item.attachments[slot] = {"uid":"part-" + id,"id":id,"slot":slot,"rarity":"common","roll":1.0}
		var fitted := Visuals.model("weapon", item)
		_check(hash(fitted.get_faces()) != hash(base.get_faces()), "%s changes the physical ground weapon" % id)
		if id == "scope": _check(fitted.get_aabb().size.y > base.get_aabb().size.y, "Scope is visibly above the receiver")
		if id == "suppressor": _check(fitted.get_aabb().size.x > base.get_aabb().size.x, "Suppressor visibly extends the barrel")
		if id == "extended_mag": _check(fitted.get_aabb().size.y > base.get_aabb().size.y, "Extended magazine visibly protrudes from the pistol grip")
		_check(fitted.get_surface_count() == 1, "%s adds no draw surfaces" % id)

func _test_cache_bound() -> void:
	for index in range(180):
		var id: String = Data.WEAPONS.keys()[index % Data.WEAPONS.size()]
		var item := Loot.make_weapon(id, 8, Loot.RARITY_ORDER[index % 6], index + 8100)
		Visuals.model("weapon", item)
	_check(int(Visuals.cache_stats().models) <= Visuals.MAX_CACHED_MODELS, "Long runs cannot grow the mesh cache without limit")

func _test_drops_and_persistence() -> void:
	var first := Drop.new()
	var payload := Loot.make_weapon("lookout", 12, "legendary", 2701)
	first.setup("weapon", payload)
	root.add_child(first)
	first.position = Vector3(3, 4, 5)
	first.set_process(false)
	var saved := first.export_state()
	var original_root := first.position
	first.set_highlighted(true)
	first._process(1.0)
	_check(first.position == original_root, "Bob and rotation never move the physical/save root")
	_check(JSON.stringify(first.payload) == JSON.stringify(payload), "Building and animating a drop never mutate gameplay data")
	_check(first._pivot.position.y > 0.4 and not is_equal_approx(first._pivot.rotation.y, 0.0), "The weapon rotates and floats at pickup height")
	_check(first.export_state().position == saved.position and first.lifetime >= 1.0, "Saved placement is stable and lifetime continues")
	_check(first.get_meta("visual_family") == "sniper", "Native world UI can identify the rendered weapon family")
	var budget := first.visual_budget()
	_check(int(budget.surfaces) <= 5 and int(budget.nodes) <= 7, "Legendary presentation remains bounded to five surfaces and seven Nodes")
	_check(int(budget.lights) == 0 and int(budget.particles) == 0, "A drop allocates neither real-time lights nor particle emitters")
	first.apply_settings({"effects":0.0,"reduced_flashes":true})
	_check(not first._beam.visible and not first._core.visible and first._badge.visible and first._halo.visible, "Low effects preserves item and rarity identification while disabling beams")
	var badges: Dictionary = {}
	var instances: Array[Node3D] = [first]
	for rank in range(6):
		var drop := Drop.new()
		drop.setup("weapon", Loot.make_weapon("biscuit", 1, Loot.RARITY_ORDER[rank], 904))
		root.add_child(drop)
		drop.set_process(false)
		instances.append(drop)
		var shape: int = hash(drop._badge.mesh.get_faces())
		_check(not badges.has(shape), "Rarity rank %d has a distinct geometric symbol independent of color" % rank)
		badges[shape] = true
	for index in range(89):
		var drop := Drop.new()
		drop.setup("ammo", {"amount":24})
		root.add_child(drop)
		drop.set_process(false)
		instances.append(drop)
		_check(drop._model.mesh == Visuals.model("ammo", {"amount":48}), "Ammo pile %d reuses mesh data" % index)
		_check(drop.visual_budget().nodes <= 7, "Ammo pile %d keeps a fixed node budget" % index)
	_check(instances.size() == 96, "Full ground-loot capacity can be represented")
	var nodes_before := 0
	for drop in instances: nodes_before += int(drop.visual_budget().nodes)
	for frame in range(120):
		for drop in instances: drop._process(1.0 / 60.0)
	var nodes_after := 0
	for drop in instances: nodes_after += int(drop.visual_budget().nodes)
	_check(nodes_after == nodes_before and nodes_after <= 672, "Animating 96 drops creates no accumulating Nodes")
	for drop in instances: drop.queue_free()
	await process_frame
	await process_frame

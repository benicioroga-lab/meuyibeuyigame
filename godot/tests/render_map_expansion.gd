extends SceneTree
## Actual renderer, authored viewpoints and isolated state; no real player saves.
const World = preload("res://scripts/world.gd")
var world: Node3D
var camera: Camera3D
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	root.size = Vector2i(1440, 900)
	world = World.new()
	root.add_child(world)
	while not world.navigation_ready: await physics_frame
	for region: Dictionary in world.regions: world.unlock_region(region.id)
	camera = Camera3D.new()
	camera.fov = 80
	camera.far = 240
	world.add_child(camera)
	camera.make_current()
	world.apply_graphics({"particles":0.5,"effects":0.8,"shadows":2})
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test-output/map-expansion"))
	for view: Array in [
		["01-garden", Vector3(-1, 2.0, 35), Vector3(7, 1.7, 55)],
		["02-greenhouse", Vector3(-8, 1.7, 64), Vector3(-8, 1.5, 58)],
		["03-mall", Vector3(39, 1.8, 53), Vector3(54, 3, 46)],
		["04-mezzanine", Vector3(67, 5.9, 65), Vector3(45, 2.7, 46)],
		["05-cinema", Vector3(57, 1.8, 12), Vector3(57, 2.8, -10)],
		["06-foyer", Vector3(53, 1.8, 17), Vector3(65, 1.6, 22)],
		["07-pharmacy", Vector3(32, 1.7, 34), Vector3(32, 1.6, 27)],
		["08-overview", Vector3(95, 125, 135), Vector3(15, 0, 12)]
	]:
		camera.position = view[1]
		camera.look_at(view[2])
		await create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		var result := root.get_texture().get_image().save_png("res://test-output/map-expansion/" + view[0] + ".png")
		assert(result == OK)
		print("MAP_RENDER ", view[0])
	world.queue_free()
	await process_frame
	quit()

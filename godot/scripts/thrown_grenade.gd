extends Node3D

var game: Node
var owner_peer_id := 1
var config: Dictionary
var velocity := Vector3.ZERO
var fuse := 1.15
var settled := false
var _detonated := false

func _ready() -> void:
	add_to_group("run_grenades")
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var shell := MeshInstance3D.new()
	var shape := SphereMesh.new()
	shape.radius = 0.085
	shape.height = 0.21
	shape.radial_segments = 12
	shape.rings = 6
	shell.mesh = shape
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(config.color)
	material.emission_enabled = true
	material.emission = Color(config.color)
	material.emission_energy_multiplier = 1.5
	shell.material_override = material
	add_child(shell)

func _physics_process(delta: float) -> void:
	fuse -= delta
	if not settled:
		velocity.y -= 16 * delta
		var next := global_position + velocity * delta
		var query := PhysicsRayQueryParameters3D.create(global_position, next, 1 | 8 | 32)
		query.collide_with_areas = true
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty(): global_position = next
		else:
			global_position = Vector3(hit.position) + Vector3(hit.normal) * 0.08
			settled = true
	if fuse <= 0: detonate()

func detonate() -> void:
	if is_instance_valid(game.get("coop")) and game.coop.is_host() and owner_peer_id != game.coop.current_peer_id and (owner_peer_id == 1 or game.coop.peers.has(owner_peer_id)):
		game.coop.with_peer(owner_peer_id, detonate)
		return
	if _detonated: return
	_detonated = true
	set_physics_process(false)
	var radius := float(config.radius)
	for enemy: Node in game.enemies.duplicate():
		if not is_instance_valid(enemy) or enemy.dead: continue
		var point: Vector3 = enemy.global_position + Vector3.UP * 0.8
		var distance := global_position.distance_to(point)
		if distance > radius: continue
		var query := PhysicsRayQueryParameters3D.create(global_position, point, 1)
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty(): continue
		enemy.take_damage(float(config.damage) * (1.0 + 0.09 * game.round_number) * lerpf(1.0, 0.4, distance / radius), "body", "grenade")
		if not enemy.dead and config.element != "explosive": enemy.apply_status(config.element, 0.8, 3.0)
	game.audio.play("explosion")
	if is_instance_valid(game.get("coop")) and game.coop.is_host(): game.coop.grenade_feedback(global_position, Color(config.color), radius)
	var pulse := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 16
	sphere.rings = 8
	pulse.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(Color(config.color), 0.24)
	pulse.material_override = material
	add_child(pulse)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(pulse, "scale", Vector3.ONE * radius * 2, 0.23)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.3)
	tween.chain().tween_callback(queue_free)

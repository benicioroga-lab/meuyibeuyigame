class_name MeyuiEnemy
extends CharacterBody3D

## Liga do Ruído: feet-driven native actors with independent ballistic hit zones.
const ActorVisual = preload("res://scripts/actor_visual.gd")
const Data = preload("res://data/enemy_data.gd")

var game: Node
var kind: String = "grunt"
var health: float = 42.0
var max_health: float = 42.0
var dead: bool = false
var speed: float = 2.2
var speed_max: float = 3.8
var elite: String = ""
var boss_id: String = ""
var boss_phase: int = 1
var statuses: Dictionary = {}
var gait: float = 0.0
var reward: int = 16
var _damage: float = 22.0
var _attack_interval: float = 1.15
var _attack_windup: float = 0.3
var _reach: float = 1.4
var _round: int = 1
var _agent: NavigationAgent3D
var _visual: Dictionary = {}
var _model: Node3D
var _hit_areas: Array[Area3D] = []
var _path_timer: float = 0.0
var _attack_cooldown: float = 0.7
var _windup: float = 0.0
var _hurt_timer: float = 0.0
var _stagger: float = 0.0
var _death_time: float = 0.0
var _knockback: Vector3 = Vector3.ZERO
var _aggro_target: Node3D
var _aggro_timer: float = 0.0
var _dog_retaliation_cooldown: float = 0.0
var _boss_cooldown: float = 6.0
var _boss_windup: float = 0.0
var _boss_phase_two: bool = false
var _shock_ring: MeshInstance3D
var _definition: Dictionary = {}
var _size: float = 1.0
var _status_tick: float = 0.0
var _status_pending_damage: float = 0.0
var _special: String = ""
var _special_time: float = 0.0
var _special_duration: float = 1.0
var _special_cooldown: float = 2.5
var _aim_position: Vector3 = Vector3.ZERO
var _charge_direction: Vector3 = Vector3.ZERO
var _charge_time: float = 0.0
var _charge_hit: bool = false
var _projectiles: Array[Dictionary] = []
var _telegraph_line: MeshInstance3D
var _elite_aura: MeshInstance3D
var _last_hit_zone: String = "body"
var _reveal_time: float = 0.0
var _fire_time: float = 0.0
var _fire_tick: float = 0.0
var _fire_target: Node3D
var _turn_lean: float = 0.0
var _last_yaw: float = 0.0


func setup(owner_game: Node, enemy_kind: String, round_index: int, difficulty: float = 1.0) -> void:
	game = owner_game
	kind = enemy_kind
	if kind.begins_with("boss_"):
		boss_id = kind.trim_prefix("boss_")
		kind = "boss"
	if not Data.ARCHETYPES.has(kind):
		kind = "grunt"
	_round = maxi(round_index, 1)
	var escalation: float = 1.0 + float(_round - 1) * 0.09
	_definition = Data.definition(kind)
	max_health = float(_definition["health"]) * escalation * maxf(0.1, difficulty)
	speed_max = float(_definition["cap"])
	speed = minf(float(_definition["speed"]) + float(_round - 1) * 0.055, speed_max)
	_damage = float(_definition["damage"])
	_attack_interval = float(_definition.get("attack_interval", 1.15))
	_attack_windup = float(_definition.get("windup", 0.3))
	reward = int(_definition["reward"])
	_reach = float(_definition["reach"])
	_size = float(_definition["scale"])
	if kind == "boss":
		max_health = (650.0 + float(maxi(_round - 5, 0)) * 55.0) * maxf(0.1, difficulty)
		if not Data.BOSSES.has(boss_id):
			boss_id = Data.boss_for_round(_round)
	health = max_health
	_damage *= 1.0 + minf(float(_round - 1) * 0.035, 0.6)
	_attack_cooldown = randf_range(0.25, 0.5)
	_path_timer = randf_range(0.0, 0.3)
	_special_cooldown = randf_range(1.6, 3.3)


func _ready() -> void:
	name = "Enemy_" + kind
	add_to_group("meyui_enemies")
	collision_layer = 4
	collision_mask = 1 | 2 | 4 | 32
	floor_snap_length = 0.55
	floor_max_angle = deg_to_rad(50.0)
	floor_stop_on_slope = true
	var body_shape := CapsuleShape3D.new()
	body_shape.radius = 0.31 * _size
	body_shape.height = 1.75 * _size
	var body_collision := CollisionShape3D.new()
	body_collision.shape = body_shape
	body_collision.position.y = body_shape.height * 0.5
	add_child(body_collision)
	_visual = ActorVisual.build_enemy(self, kind)
	_model = _visual.get("root") as Node3D
	_model.scale = Vector3.ONE * _size
	var visual_scale: float = _size
	_add_hit_zone("head", Vector3(0, 1.55, 0) * visual_scale, Vector3(0.245, 0.245, 0.245) * visual_scale, true)
	_add_hit_zone("body", Vector3(0, 1.03, 0) * visual_scale, Vector3(0.7, 0.66, 0.43) * visual_scale)
	_add_hit_zone("leg", Vector3(0, 0.37, 0) * visual_scale, Vector3(0.58, 0.61, 0.39) * visual_scale)
	_agent = NavigationAgent3D.new()
	# Arrival stays inside the baked corner clearance, including the ~0.1 m
	# navigation surface offset, instead of cutting across a solid parapet end.
	_agent.path_desired_distance = 0.22
	# Baking lifts floor vertices by two 5 cm voxels. Compare feet against the
	# physical surface so uphill waypoints can be consumed before overshooting.
	_agent.path_height_offset = 0.1
	_agent.target_desired_distance = 0.95
	_agent.path_max_distance = 2.4
	_agent.radius = body_shape.radius
	_agent.height = body_shape.height
	_agent.avoidance_enabled = false
	add_child(_agent)
	_create_shock_ring()
	_create_telegraph_line()
	_refresh_elite_visual()


func configure_difficulty(damage_multiplier: float, speed_multiplier: float, chaos: bool = false) -> void:
	_damage *= maxf(0.1, damage_multiplier)
	speed = minf(speed * maxf(0.1, speed_multiplier), speed_max)
	if chaos:
		_boss_cooldown = 4.0


func configure_elite(id: String) -> void:
	if elite == id or not elite.is_empty() or not Data.ELITES.has(id):
		return
	elite = id
	var data: Dictionary = Data.ELITES[id]
	var ratio: float = health / maxf(1.0, max_health)
	max_health *= float(data["health"])
	health = max_health * ratio
	_damage *= float(data["damage"])
	reward = roundi(float(reward) * 1.7)
	if is_inside_tree():
		_refresh_elite_visual()


func configure_boss(id: String) -> void:
	if kind == "boss" and Data.BOSSES.has(id):
		boss_id = id


func taunt(target: Node3D, duration: float = 2.0) -> void:
	if not dead and is_instance_valid(target):
		_aggro_target = target
		_aggro_timer = maxf(_aggro_timer, duration)


func apply_status(id: String, power: float, duration: float) -> void:
	if dead or duration <= 0.0:
		return
	if id == "frost":
		id = "cryo"
	if id not in ["burn", "corrosive", "bleed", "cryo", "shock", "freeze", "frenzy"]:
		return
	var previous: Dictionary = statuses.get(id, {})
	statuses[id] = {"power": maxf(float(previous.get("power", 0.0)), maxf(power, 0.0)), "duration": maxf(float(previous.get("duration", 0.0)), minf(duration, 30.0))}
	if id == "shock":
		_stagger = maxf(_stagger, 0.12 if kind != "boss" else 0.035)
	if id == "freeze":
		# Frozen casts do not commit their attack until the effect expires.
		velocity.x = 0.0
		velocity.z = 0.0


func get_effective_speed() -> float:
	var multiplier: float = 1.0
	if Data.ELITES.has(elite):
		multiplier *= float(Data.ELITES[elite]["speed"])
		if elite == "frenzy":
			multiplier *= 1.0 + (1.0 - health / maxf(max_health, 1.0)) * 0.32
	if statuses.has("frenzy"):
		multiplier *= 1.0 + minf(float(statuses["frenzy"]["power"]), 0.6)
	var slow: float = 0.0
	for id in ["cryo", "shock"]:
		if statuses.has(id):
			slow = maxf(slow, clampf(float(statuses[id]["power"]), 0.0, 0.85))
	if statuses.has("freeze"):
		return 0.0
	return clampf(speed * multiplier * (1.0 - slow), 0.0, speed_max)


func _add_hit_zone(zone: String, center: Vector3, size: Vector3, sphere: bool = false) -> void:
	var area := Area3D.new()
	area.name = "Hit_" + zone
	area.collision_layer = 8
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = false
	area.set_meta("enemy", self)
	area.set_meta("zone", zone)
	var collision := CollisionShape3D.new()
	if sphere:
		var sphere_shape := SphereShape3D.new()
		sphere_shape.radius = size.x
		collision.shape = sphere_shape
	else:
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		collision.shape = box_shape
	area.position = center
	area.add_child(collision)
	add_child(area)
	_hit_areas.append(area)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(game) or not game.running or game.paused:
		return
	if dead:
		_death_time += delta
		_model.rotation.z = lerpf(_model.rotation.z, 1.45, delta * 6.5)
		_model.position.y = lerpf(_model.position.y, 0.18, delta * 5.0)
		if _death_time > 0.82:
			queue_free()
		return
	_hurt_timer = maxf(0.0, _hurt_timer - delta)
	_stagger = maxf(0.0, _stagger - delta)
	_reveal_time = maxf(0.0, _reveal_time - delta)
	_update_statuses(delta)
	if dead:
		return
	_update_projectiles(delta)
	_update_fire(delta)
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	_aggro_timer = maxf(0.0, _aggro_timer - delta)
	_dog_retaliation_cooldown = maxf(0.0, _dog_retaliation_cooldown - delta)
	var target: Node3D = _combat_target()
	if not is_instance_valid(target):
		return
	var to_target: Vector3 = target.global_position - global_position
	var flat: Vector3 = Vector3(to_target.x, 0, to_target.z)
	var flat_distance: float = flat.length()
	if flat_distance > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(-flat.x, -flat.z), delta * 8.0)
	var frozen: bool = statuses.has("freeze")
	if not frozen:
		if kind == "boss":
			_update_boss(delta, target, flat_distance)
		else:
			_update_special(delta, target, flat_distance)
	if dead:
		return
	if _windup > 0.0 and not frozen:
		_windup -= delta
		if _windup <= 0.0:
			if flat_distance < _reach + 0.48 and absf(to_target.y) < 1.3 and _clear_sight(target, true):
				_deal_damage(target, _damage)
			# The interval includes the visible windup; it is not an extra delay.
			var interval: float = _attack_interval * (0.72 if elite == "frenzy" else 1.0)
			_attack_cooldown = maxf(0.35, interval - _attack_windup)
	elif not frozen and _attack_cooldown <= 0.0 and _boss_windup <= 0.0 and _special_time <= 0.0 and flat_distance < _reach and absf(to_target.y) < 1.15 and _clear_sight(target, true):
		_windup = _attack_windup
	var direction: Vector3 = Vector3.ZERO
	var reached_target: bool = flat_distance <= _reach * 0.8 and absf(to_target.y) < 1.15
	if not frozen and _windup <= 0.0 and _boss_windup <= 0.0 and _special_time <= 0.0 and _stagger <= 0.0 and not reached_target:
		direction = _navigation_direction(target.global_position, delta)
		if kind == "spitter" and flat_distance < 5.2 and _clear_sight(target):
			direction *= -0.55 if flat_distance < 3.0 else 0.0
		elif kind == "summoner" and flat_distance < 6.0:
			direction *= 0.1
		elif kind == "parasite" and flat_distance > 2.0 and flat_distance < 7.0:
			direction = (direction + Vector3(-direction.z, 0, direction.x) * sin(gait * 0.4) * 0.42).normalized()
		# Mild separation keeps a crowd readable without unstable RVO on stairs.
		var separation: Vector3 = Vector3.ZERO
		for other in game.enemies:
			if other == self or not is_instance_valid(other) or other.dead:
				continue
			var offset: Vector3 = global_position - other.global_position
			if absf(offset.y) > 1.0:
				continue
			offset.y = 0.0
			var distance: float = offset.length()
			if distance > 0.05 and distance < 0.82:
				separation += offset / distance * (0.82 - distance) * 0.8
		direction = (direction + separation).limit_length(1.0)
	if _charge_time > 0.0 and not frozen:
		_charge_time -= delta
		direction = _charge_direction
		if not _charge_hit and flat_distance < _reach + 0.3 and absf(to_target.y) < 1.6 and _clear_sight(target, true):
			_deal_damage(target, _damage * 1.25)
			_charge_hit = true
	var effective_speed: float = get_effective_speed()
	if _charge_time > 0.0 and not frozen:
		effective_speed = minf(effective_speed * 1.8, speed_max)
	var desired: Vector3 = (direction * effective_speed + _knockback).limit_length(speed_max)
	velocity.x = move_toward(velocity.x, desired.x, delta * 13.0)
	velocity.z = move_toward(velocity.z, desired.z, delta * 13.0)
	_knockback = _knockback.move_toward(Vector3.ZERO, delta * 14.0)
	var horizontal: Vector2 = Vector2(velocity.x, velocity.z).limit_length(speed_max)
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	if not is_on_floor():
		velocity.y -= 22.0 * delta
	elif velocity.y <= 0.0:
		velocity.y = -0.3
	move_and_slide()
	_animate(delta)


func _combat_target() -> Node3D:
	if _aggro_timer > 0.0 and is_instance_valid(_aggro_target) and float(_aggro_target.get("health")) > 0.0:
		return _aggro_target
	if is_instance_valid(game.player) and game.player.health > 0.0:
		return game.player as Node3D
	return null


func _navigation_direction(target_position: Vector3, delta: float) -> Vector3:
	_path_timer -= delta
	var waypoint: Vector3 = target_position
	if is_instance_valid(game.world) and game.world.navigation_ready and NavigationServer3D.map_get_iteration_id(_agent.get_navigation_map()) > 0:
		if _path_timer <= 0.0:
			_path_timer = 0.28 + randf_range(0.0, 0.1)
			_agent.target_position = target_position
		if not _agent.is_navigation_finished():
			waypoint = _agent.get_next_path_position()
	var direction: Vector3 = waypoint - global_position
	direction.y = 0.0
	# Arrival belongs to NavigationAgent3D. A wide planar dead zone can stop the
	# body while the elevated 3D waypoint still remains outside its arrival radius.
	return direction.normalized() if direction.length_squared() > 0.000025 else Vector3.ZERO


func _clear_sight(target: Node3D, block_gates: bool = false) -> bool:
	var target_height: float = 0.35 if target.is_in_group("meyui_companion") else 1.0
	# Bars stop bodies and contact attacks, while ranged attacks pass between them.
	var mask: int = 1 | 32 if block_gates else 1
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.15, target.global_position + Vector3.UP * target_height, mask)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func take_damage(amount: float, zone: String = "body", source: String = "player") -> float:
	if dead or amount <= 0.0:
		return 0.0
	var multiplier: float = 1.75 if zone == "head" else (0.65 if zone == "leg" else 1.0)
	if zone != "head" and source != "status" and not statuses.has("corrosive"):
		if kind == "armored":
			multiplier *= 0.48
		elif kind == "tank" or (kind == "boss" and boss_id == "bulwark"):
			multiplier *= 0.78
	var actual: float = minf(health, amount * multiplier)
	health = maxf(health - actual, 0.0)
	_last_hit_zone = zone
	_reveal_time = 2.0
	_hurt_timer = 0.16
	_stagger = 0.12 if kind != "boss" else 0.035
	if zone == "leg" and kind != "boss":
		_stagger = 0.3
	if source == "faro" and is_inside_tree():
		# Ordinary bites cannot renew aggro faster than it expires and permanently
		# distract the whole horde. The Guardian's explicit taunt remains separate.
		var player_close: bool = is_instance_valid(game.player) and global_position.distance_to(game.player.global_position) < _reach + 0.35
		if not player_close and _dog_retaliation_cooldown <= 0.0:
			taunt(get_tree().get_first_node_in_group("meyui_companion") as Node3D, 0.8)
			_dog_retaliation_cooldown = 4.0
	if is_instance_valid(game) and game.has_method("on_enemy_damaged"):
		game.on_enemy_damaged(self, actual, zone, source)
	if health <= 0.0:
		_die(source)
	return actual


func knock_back(direction: Vector3, strength: float = 3.0) -> void:
	direction.y = 0.0
	_knockback = direction.normalized() * strength * (0.25 if kind == "boss" else 1.0)


func _update_statuses(delta: float) -> void:
	var has_dot: bool = false
	for id in statuses.keys():
		var effect: Dictionary = statuses[id]
		var active: float = minf(delta, float(effect["duration"]))
		if id in ["burn", "corrosive", "bleed"]:
			var resistance: float = 0.4 if id == "burn" and elite == "fire" else 1.0
			_status_pending_damage += float(effect["power"]) * active * resistance
			has_dot = true
		effect["duration"] = float(effect["duration"]) - delta
		if float(effect["duration"]) <= 0.0:
			statuses.erase(id)
	_status_tick += delta
	if _status_pending_damage > 0.0 and (_status_tick >= 0.35 or not has_dot):
		var amount: float = _status_pending_damage
		_status_pending_damage = 0.0
		_status_tick = 0.0
		take_damage(amount, "body", "status")


func _deal_damage(target: Node3D, amount: float) -> float:
	if not is_instance_valid(target) or not target.has_method("take_damage"):
		return 0.0
	var before: float = maxf(0.0, float(target.get("health")))
	if target == game.player:
		target.take_damage(amount, self)
	else:
		target.take_damage(amount)
	var actual: float = maxf(0.0, before - maxf(0.0, float(target.get("health"))))
	if elite == "vampiric" and actual > 0.0:
		health = minf(max_health, health + actual * 0.45)
	if elite == "fire" and actual > 0.0:
		_fire_target = target
		_fire_time = 2.0
		_fire_tick = 0.0
	return actual


func _update_fire(delta: float) -> void:
	if _fire_time <= 0.0 or not is_instance_valid(_fire_target):
		return
	_fire_time -= delta
	_fire_tick += delta
	if _fire_tick >= 0.6:
		_fire_tick = 0.0
		if float(_fire_target.get("health")) > 0.0 and _fire_target.has_method("take_damage"):
			if _fire_target == game.player:
				_fire_target.take_damage(2.0, self)
			else:
				_fire_target.take_damage(2.0)


func _update_special(delta: float, target: Node3D, distance: float) -> void:
	_special_cooldown = maxf(0.0, _special_cooldown - delta)
	if _special_time > 0.0:
		_special_time -= delta
		_update_special_telegraph()
		if _special_time <= 0.0:
			_finish_special(target)
		return
	if _special_cooldown > 0.0 or _windup > 0.0 or absf(target.global_position.y - global_position.y) > 5.5:
		return
	match kind:
		"exploder":
			if distance < 2.6 and _clear_sight(target):
				_begin_special("explode", 1.05, target.global_position)
		"spitter":
			if distance > 2.8 and distance < 16.0 and _clear_sight(target):
				_begin_special("spit", 0.7, target.global_position + Vector3.UP * 0.9)
		"screamer":
			if distance < 13.0:
				_begin_special("scream", 0.95, target.global_position)
		"hunter":
			if distance > 2.5 and distance < 7.5 and _clear_sight(target):
				_begin_special("leap", 0.72, target.global_position)
		"summoner":
			if distance < 18.0:
				_begin_special("summon", 1.2, target.global_position)


func _begin_special(id: String, duration: float, aim: Vector3) -> void:
	_special = id
	_special_duration = duration
	_special_time = duration
	_aim_position = aim
	_reveal_time = maxf(_reveal_time, duration + 0.6)
	_charge_direction = (aim - global_position) * Vector3(1, 0, 1)
	_charge_direction = _charge_direction.normalized()
	if is_instance_valid(_telegraph_line) and id in ["spit", "leap", "charge", "volley"]:
		var distance: float = clampf(global_position.distance_to(aim), 1.0, 16.0)
		_telegraph_line.visible = true
		_telegraph_line.top_level = true
		_telegraph_line.global_position = global_position + Vector3.UP * 0.07 + _charge_direction * distance * 0.5
		_telegraph_line.global_rotation.y = atan2(-_charge_direction.x, -_charge_direction.z)
		_telegraph_line.scale = Vector3(1.0, 1.0, distance)
	_update_special_telegraph()


func _update_special_telegraph() -> void:
	if not is_instance_valid(_shock_ring):
		return
	var progress: float = clampf(1.0 - _special_time / maxf(0.01, _special_duration), 0.0, 1.0)
	_shock_ring.visible = _special in ["explode", "scream", "summon"]
	var radius: float = 3.0 if _special == "explode" else (7.0 if _special == "scream" else 2.1)
	_shock_ring.scale = Vector3(radius / 3.7, 1.0, radius / 3.7)
	var color: Color = Color("ff755c") if _special == "explode" else Color("b191ff")
	color.a = 0.12 + progress * 0.35
	(_shock_ring.material_override as StandardMaterial3D).albedo_color = color


func _finish_special(target: Node3D) -> void:
	_shock_ring.visible = false
	_telegraph_line.visible = false
	_attack_cooldown = maxf(_attack_cooldown, 0.65)
	match _special:
		"explode":
			_radial_attack(3.0, _damage, 1.5)
			health = 0.0
			reward = 0
			_die("self")
		"spit", "volley":
			var direction: Vector3 = (_aim_position - (global_position + Vector3.UP * 1.2 * _size)).normalized()
			_launch_projectile(direction, _damage, Color("a5ed69"))
			if _special == "volley":
				_launch_projectile(direction.rotated(Vector3.UP, 0.17), _damage * 0.72, Color("bf8ff5"))
				_launch_projectile(direction.rotated(Vector3.UP, -0.17), _damage * 0.72, Color("bf8ff5"))
			_special_cooldown = 2.2 if kind != "boss" else 2.8
		"scream":
			for ally in game.enemies:
				if is_instance_valid(ally) and not ally.dead and ally != self and global_position.distance_to(ally.global_position) < 7.0:
					ally.apply_status("frenzy", 0.32, 5.0)
			_summon_adds(1, "runner")
			_special_cooldown = 9.0
		"summon":
			_summon_adds(2 if kind != "boss" else boss_phase + 1, "parasite" if kind == "boss" else "grunt")
			_special_cooldown = 10.0 if kind != "boss" else 7.0
		"leap", "charge":
			_charge_time = 0.95 if _special == "leap" else 1.4
			_charge_hit = false
			if _special == "leap":
				velocity.y = 5.8
			_special_cooldown = 6.2
	_special = ""
	_special_time = 0.0
	if is_instance_valid(target):
		_path_timer = 0.0


func _radial_attack(radius: float, amount: float, jump_height: float = 0.68) -> void:
	var targets: Array[Node3D] = []
	if is_instance_valid(game.player):
		targets.append(game.player as Node3D)
	var dog := get_tree().get_first_node_in_group("meyui_companion") as Node3D
	if is_instance_valid(dog):
		targets.append(dog)
	for target in targets:
		var offset: Vector3 = target.global_position - global_position
		if Vector2(offset.x, offset.z).length() < radius and offset.y > -1.0 and offset.y < jump_height and _clear_sight(target):
			_deal_damage(target, amount)


func _summon_adds(count: int, add_kind: String) -> void:
	if not game.has_method("spawn_add"):
		return
	var active: int = 0
	for enemy in game.enemies:
		if is_instance_valid(enemy) and not enemy.dead:
			active += 1
	for index in mini(count, maxi(24 - active, 0)):
		var angle: float = float(index) * 2.4 + rotation.y
		var at: Vector3 = global_position + Vector3(sin(angle), 0.0, cos(angle)) * 1.7
		if is_instance_valid(game.world) and game.world.navigation_ready and NavigationServer3D.map_get_iteration_id(_agent.get_navigation_map()) > 0:
			at = NavigationServer3D.map_get_closest_point(_agent.get_navigation_map(), at)
		game.spawn_add(add_kind, at + Vector3.UP * 0.12)


func _launch_projectile(direction: Vector3, amount: float, color: Color) -> void:
	if _projectiles.size() >= 3 or direction.length_squared() < 0.1:
		return
	var node := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	sphere.radial_segments = 10
	sphere.rings = 5
	node.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.top_level = true
	node.global_position = global_position + Vector3.UP * 1.2 * _size + direction * 0.42
	_projectiles.append({"node": node, "velocity": direction * 8.5, "life": 3.2, "damage": amount})


func _update_projectiles(delta: float) -> void:
	for index in range(_projectiles.size() - 1, -1, -1):
		var shot: Dictionary = _projectiles[index]
		var node := shot["node"] as MeshInstance3D
		if not is_instance_valid(node):
			_projectiles.remove_at(index)
			continue
		var start: Vector3 = node.global_position
		var end: Vector3 = start + Vector3(shot["velocity"]) * delta
		var query := PhysicsRayQueryParameters3D.create(start, end, 1 | 2 | 16)
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		shot["life"] = float(shot["life"]) - delta
		if not hit.is_empty() or float(shot["life"]) <= 0.0:
			if not hit.is_empty() and hit["collider"] is Node3D and hit["collider"].has_method("take_damage"):
				_deal_damage(hit["collider"] as Node3D, float(shot["damage"]))
			node.queue_free()
			_projectiles.remove_at(index)
		else:
			node.global_position = end


func _die(source: String) -> void:
	if dead:
		return
	dead = true
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	for area in _hit_areas:
		area.collision_layer = 0
		for child in area.get_children():
			if child is CollisionShape3D:
				child.set_deferred("disabled", true)
	if is_instance_valid(_shock_ring):
		_shock_ring.visible = false
	if is_instance_valid(_telegraph_line):
		_telegraph_line.visible = false
	for shot in _projectiles:
		if is_instance_valid(shot.get("node")):
			shot["node"].queue_free()
	_projectiles.clear()
	statuses.clear()
	_fire_time = 0.0
	_special_time = 0.0
	if is_instance_valid(game) and game.has_method("on_enemy_killed"):
		game.on_enemy_killed(self, reward, source)


func _animate(delta: float) -> void:
	var moving: float = Vector2(velocity.x, velocity.z).length()
	gait += delta * moving * 4.2
	var step: float = sin(gait)
	var amount: float = minf(moving / 2.5, 1.0)
	var left_leg := _visual.get("left_leg") as Node3D
	var right_leg := _visual.get("right_leg") as Node3D
	var left_arm := _visual.get("left_arm") as Node3D
	var right_arm := _visual.get("right_arm") as Node3D
	if is_instance_valid(left_leg):
		left_leg.rotation.x = step * 0.48 * amount
	if is_instance_valid(right_leg):
		right_leg.rotation.x = -step * 0.48 * amount
	var attack_pose: bool = _windup > 0.0 or _boss_windup > 0.0 or _special_time > 0.0
	if is_instance_valid(left_arm):
		left_arm.rotation.x = lerpf(left_arm.rotation.x, -1.5 if attack_pose else -step * 0.4 * amount, delta * 16.0)
	if is_instance_valid(right_arm):
		right_arm.rotation.x = lerpf(right_arm.rotation.x, -1.75 if attack_pose else step * 0.4 * amount, delta * 16.0)
	_model.position.y = absf(cos(gait)) * 0.035 * amount
	var local_floor: Vector3 = global_basis.inverse() * get_floor_normal() if is_on_floor() else Vector3.UP
	var slope_lean: float = clampf(atan2(local_floor.z, maxf(0.1, local_floor.y)), -0.4, 0.4)
	_turn_lean = lerpf(_turn_lean, clampf(angle_difference(_last_yaw, rotation.y) / maxf(delta, 0.001) * -0.035, -0.16, 0.16), delta * 7.0)
	_last_yaw = rotation.y
	_model.rotation.z = _turn_lean
	_model.rotation.x = lerpf(_model.rotation.x, -0.065 * amount + slope_lean * 0.25 + 0.12 * float(_stagger > 0.0), delta * 10.0)
	var head := _visual.get("head") as Node3D
	if is_instance_valid(head):
		head.rotation.z = lerpf(head.rotation.z, 0.2 if _hurt_timer > 0.0 and _last_hit_zone == "head" else 0.0, delta * 18.0)
	var materials: Array = _visual.get("materials", [])
	var colors: Array = _visual.get("default_colors", [])
	var effect_color: Color = Color("ff841f") if statuses.has("burn") else Color("b4eb75")
	var effect_mix: float = 0.17 if statuses.has("burn") or statuses.has("corrosive") else 0.0
	if statuses.has("cryo") or statuses.has("freeze") or statuses.has("shock"):
		effect_color = Color("81d7ff") if not statuses.has("shock") else Color("d3a5ff")
		effect_mix = 0.4 if statuses.has("freeze") else 0.22
	var camouflaged: bool = kind == "stealth" and _reveal_time <= 0.0 and _windup <= 0.0 and is_instance_valid(game.player) and global_position.distance_to(game.player.global_position) > 4.5
	for index in mini(materials.size(), colors.size()):
		var mat := materials[index] as StandardMaterial3D
		var base: Color = colors[index]
		base = base.lerp(effect_color, effect_mix)
		mat.albedo_color = base.lerp(Color(1.0, 0.16, 0.08), clampf(_hurt_timer * 5.0, 0.0, 0.7))
		if kind == "stealth":
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color.a = 0.24 if camouflaged else 1.0


func _create_shock_ring() -> void:
	_shock_ring = MeshInstance3D.new()
	_shock_ring.name = "PulseTelegraph"
	var circle := CylinderMesh.new()
	circle.top_radius = 3.7
	circle.bottom_radius = 3.7
	circle.height = 0.018
	circle.radial_segments = 48
	_shock_ring.mesh = circle
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.18, 0.38, 0.24)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = false
	_shock_ring.material_override = material
	_shock_ring.position.y = 0.055
	_shock_ring.visible = false
	add_child(_shock_ring)


func _update_boss(delta: float, target: Node3D, distance: float) -> void:
	var next_phase: int = 3 if health < max_health * 0.33 else (2 if health < max_health * 0.66 else 1)
	if next_phase > boss_phase:
		boss_phase = next_phase
		_boss_phase_two = boss_phase >= 2
		speed = minf(speed + 0.3, speed_max)
		_damage += 4.0
		if game.has_method("notify"):
			game.notify("%s · fase %d!" % [Data.BOSSES.get(boss_id, Data.BOSSES["captain"])["name"], boss_phase])
		_refresh_elite_visual()
	_boss_cooldown -= delta
	if _special_time > 0.0:
		_special_time -= delta
		_update_special_telegraph()
		if _special_time <= 0.0:
			_finish_special(target)
			_boss_cooldown = maxf(3.0, 7.5 - float(boss_phase))
		return
	if _boss_windup > 0.0:
		_boss_windup -= delta
		_shock_ring.visible = true
		var progress: float = 1.0 - _boss_windup / 1.05
		_shock_ring.scale = Vector3(0.35 + progress * 0.65, 1.0, 0.35 + progress * 0.65)
		var material := _shock_ring.material_override as StandardMaterial3D
		material.albedo_color.a = 0.18 + progress * 0.32
		if _boss_windup <= 0.0:
			_shock_ring.visible = false
			_boss_cooldown = 9.0 - float(boss_phase - 1) * 1.75
			_radial_attack(3.7, 34.0 + float(boss_phase - 1) * 8.0)
	elif _boss_cooldown <= 0.0 and distance < 18.0 and _windup <= 0.0:
		if boss_id == "conductor":
			_begin_special("summon" if randi() % 2 == 0 else "volley", 1.15, target.global_position + Vector3.UP)
		elif boss_id == "bulwark" and distance > 3.0:
			_begin_special("charge", 1.1, target.global_position)
		elif distance > 6.0:
			_begin_special("volley", 0.85, target.global_position + Vector3.UP)
		else:
			_boss_windup = 1.05
			(_shock_ring.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.18, 0.38, 0.24)
			if game.has_method("notify"):
				game.notify("Pulso do chefe! Salte ou saia do círculo.")


func _create_telegraph_line() -> void:
	_telegraph_line = MeshInstance3D.new()
	_telegraph_line.name = "AimTelegraph"
	var strip := BoxMesh.new()
	strip.size = Vector3(0.18, 0.016, 1.0)
	_telegraph_line.mesh = strip
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.64, 0.27, 0.42)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_telegraph_line.material_override = material
	_telegraph_line.visible = false
	_telegraph_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_telegraph_line)


func _refresh_elite_visual() -> void:
	if elite.is_empty() and kind != "boss":
		return
	if not is_instance_valid(_elite_aura):
		_elite_aura = MeshInstance3D.new()
		_elite_aura.name = "EliteSignal"
		var ring := TorusMesh.new()
		ring.inner_radius = 0.39 * _size
		ring.outer_radius = 0.46 * _size
		ring.rings = 24
		ring.ring_segments = 6
		_elite_aura.mesh = ring
		_elite_aura.position.y = 0.055
		_elite_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_elite_aura)
	var material := StandardMaterial3D.new()
	var color: Color = Data.ELITES[elite]["color"] if Data.ELITES.has(elite) else Data.BOSSES.get(boss_id, Data.BOSSES["captain"])["color"]
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_elite_aura.material_override = material
	_elite_aura.scale = Vector3.ONE * (1.0 + float(boss_phase - 1) * 0.15)


func export_state() -> Dictionary:
	return {"balance_version": Data.BALANCE_VERSION, "kind": kind, "round": _round, "health": health, "max_health": max_health,
		"position": [global_position.x, global_position.y, global_position.z], "rotation_y": rotation.y,
		"elite": elite, "boss_id": boss_id, "boss_phase": boss_phase, "statuses": statuses.duplicate(true),
		"speed": speed, "damage": _damage, "reward": reward, "attack_cooldown": _attack_cooldown,
		"special_cooldown": _special_cooldown, "boss_cooldown": _boss_cooldown,
		"dog_retaliation_cooldown": _dog_retaliation_cooldown}


func import_state(state: Dictionary) -> void:
	if state.get("position") is Array and state["position"].size() == 3:
		var at: Array = state["position"]
		global_position = Vector3(float(at[0]), float(at[1]), float(at[2]))
	rotation.y = float(state.get("rotation_y", rotation.y))
	max_health = maxf(1.0, float(state.get("max_health", max_health)))
	health = clampf(float(state.get("health", max_health)), 0.0, max_health)
	var saved_elite: String = str(state.get("elite", ""))
	elite = saved_elite if Data.ELITES.has(saved_elite) else ""
	configure_boss(str(state.get("boss_id", boss_id)))
	boss_phase = clampi(int(state.get("boss_phase", 1)), 1, 3)
	_boss_phase_two = boss_phase >= 2
	speed = clampf(float(state.get("speed", speed)), 0.0, speed_max)
	if int(state.get("balance_version", 1)) >= Data.BALANCE_VERSION:
		_damage = maxf(0.0, float(state.get("damage", _damage)))
	elif kind == "boss":
		_damage += float(boss_phase - 1) * 4.0
	reward = maxi(0, int(state.get("reward", reward)))
	_attack_cooldown = maxf(0.3, float(state.get("attack_cooldown", 0.5)))
	_special_cooldown = maxf(0.6, float(state.get("special_cooldown", 1.0)))
	_boss_cooldown = maxf(1.05, float(state.get("boss_cooldown", 2.0)))
	_dog_retaliation_cooldown = clampf(float(state.get("dog_retaliation_cooldown", 0.0)), 0.0, 4.0)
	statuses.clear()
	if state.get("statuses") is Dictionary:
		for id in state["statuses"]:
			var value: Variant = state["statuses"][id]
			if value is Dictionary:
				apply_status(str(id), float(value.get("power", 0.0)), float(value.get("duration", 0.0)))
	if is_inside_tree():
		_refresh_elite_visual()

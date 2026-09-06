extends CharacterBody3D
class_name MeyuiPlayer

## Feet-origin controller. Gameplay state and ammunition stay independent of visuals.
const Data = preload("res://data/game_data.gd")
const WeaponView = preload("res://scripts/weapon_view.gd")
const WORLD_COLLISION_LAYER: int = 1
const GATE_COLLISION_LAYER: int = 32
const PHYSICAL_WORLD_MASK: int = WORLD_COLLISION_LAYER | GATE_COLLISION_LAYER
# Gates stop bodies and cameras, while bullets and their secondary effects pass.
const SHOT_MASK: int = WORLD_COLLISION_LAYER | 8
const NORMAL_ENEMY_HIT_FRACTION: float = 0.4
const HIT_GRACE_SECONDS: float = 0.30
const WEAPON_IDS: Array[String] = ["biscuit", "boardwalk", "hammer"]

var game: Node
var health: float = 100.0
var max_health: float = 100.0
var camera: Camera3D
var third_person: bool = false
var weapon_id: String = "biscuit"
var active_item_uid: String = ""
var magazine: int = 12
var reserve: int = 84
var owned_weapons: Dictionary = {}
var upgrade_state: Dictionary = {}
var reloading: bool = false
var reload_remaining: float = 0.0
var reload_duration: float = 0.0
var time: float = 0.0
var aiming: bool = false
var sprinting: bool = false
var dash_remaining: float = 0.0
var dash_cooldown: float = 0.0
var damage_cooldown: float = 0.0
var fire_cooldown: float = 0.0
var _empty_click_cooldown: float = 0.0
var shot_count: int = 0
var mouse_sensitivity: float = 0.0022
var view_pivot: Node3D
var weapon_view: Node3D
var hero: Node3D
var _pitch: float = 0.0
var _camera_recoil: float = 0.0
var _bob_time: float = 0.0
var _dash_direction: Vector3 = Vector3.ZERO
var _hero_legs: Array[Node3D] = []
var _dead: bool = false
var flashlight: SpotLight3D
var flashlight_on: bool = false
var _aim_toggle: bool = false
var _sprint_toggle: bool = false
var _burst_remaining: int = 0
var _burst_firing: bool = false
var _inspect_remaining: float = 0.0
var _combat_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _frenzy_remaining: float = 0.0
var _haste_remaining: float = 0.0
var _heat: float = 0.0
var _freeze_hits: Dictionary = {}
var _reload_was_empty: bool = false
var _trigger_counts: Dictionary = {}
var _last_combat_stats: Dictionary = {}
var _effect_nodes: Array[MeshInstance3D] = []
var _effect_times: Array[float] = []
var _effect_cursor: int = 0


func setup(owner_game: Node) -> void:
	game = owner_game
	if owned_weapons.is_empty():
		_grant_weapon("biscuit")
		_load_ammo()
	_combat_rng.randomize()
	sync_inventory()


func _ready() -> void:
	name = "MeyuiPlayer"
	collision_layer = 2
	collision_mask = PHYSICAL_WORLD_MASK | 4
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(48.0)
	floor_stop_on_slope = true
	safe_margin = 0.025
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.29
	capsule.height = 1.55
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.name = "BodyCollider"
	collider.shape = capsule
	collider.position.y = 0.775
	add_child(collider)
	view_pivot = Node3D.new()
	view_pivot.name = "ViewPivot"
	view_pivot.position.y = 1.35
	add_child(view_pivot)
	camera = Camera3D.new()
	camera.name = "PlayerCamera"
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = _target_fov(get_weapon_stats())
	camera.near = 0.035
	camera.far = 300.0
	camera.current = true
	view_pivot.add_child(camera)
	flashlight = SpotLight3D.new()
	flashlight.name = "TacticalFlashlight"
	flashlight.position = Vector3(0.13, -0.08, -0.15)
	flashlight.light_color = Color("ffe9ca")
	flashlight.light_energy = 2.8
	flashlight.spot_range = 28.0
	flashlight.spot_angle = 28.0
	flashlight.spot_angle_attenuation = 0.8
	flashlight.shadow_enabled = true
	flashlight.visible = flashlight_on
	camera.add_child(flashlight)
	weapon_view = WeaponView.new()
	weapon_view.name = "WeaponView"
	camera.add_child(weapon_view)
	weapon_view.call("set_weapon", weapon_id, get_weapon_stats())
	_build_hero()
	_sync_perspective()
	for index: int in range(12):
		var effect: MeshInstance3D = MeshInstance3D.new()
		effect.name = "CombatEffect%02d" % index
		var sphere: SphereMesh = SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = 1.0
		sphere.radial_segments = 8
		sphere.rings = 4
		effect.mesh = sphere
		var effect_material: StandardMaterial3D = StandardMaterial3D.new()
		effect_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		effect_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		effect_material.albedo_color = Color(0.5, 0.85, 1.0, 0.35)
		effect.material_override = effect_material
		effect.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(effect)
		effect.top_level = true
		effect.visible = false
		_effect_nodes.append(effect)
		_effect_times.append(0.0)


func _active() -> bool:
	return is_instance_valid(game) and bool(game.get("running")) and not bool(game.get("paused")) and not _dead


func _unhandled_input(event: InputEvent) -> void:
	if not _active():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		var sensitivity: float = float(_option("mouse_sensitivity", mouse_sensitivity)) * (float(_option("ads_sensitivity", 0.64)) if aiming else 1.0)
		rotate_y(-motion.relative.x * sensitivity)
		_pitch = clampf(_pitch - motion.relative.y * sensitivity, -1.35, 1.30)
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("view_toggle"):
		third_person = not third_person
		_sync_perspective()
		_notify("Câmera em terceira pessoa" if third_person else "Câmera em primeira pessoa")
	if event.is_action_pressed("reload"):
		start_reload()
	if _event_action(event, "flashlight"):
		flashlight_on = not flashlight_on
		if is_instance_valid(flashlight):
			flashlight.visible = flashlight_on
	if _event_action(event, "weapon_inspect") and not reloading:
		_inspect_remaining = 2.25
	if event.is_action_pressed("aim") and bool(_option("toggle_aim", false)):
		_aim_toggle = not _aim_toggle
	if event.is_action_pressed("sprint") and bool(_option("toggle_sprint", false)):
		_sprint_toggle = not _sprint_toggle
	for index: int in range(WEAPON_IDS.size()):
		if event.is_action_pressed("weapon_%d" % (index + 1)):
			var inventory: Object = _inventory()
			if inventory != null:
				var items: Array = inventory.get("items")
				if index < items.size():
					equip_weapon(str(items[index].get("uid", "")))
			else:
				equip_weapon(WEAPON_IDS[index])


func _physics_process(delta: float) -> void:
	if not _active():
		return
	time += delta
	_tick_weapon(delta)
	_inspect_remaining = maxf(0.0, _inspect_remaining - delta)
	_frenzy_remaining = maxf(0.0, _frenzy_remaining - delta)
	_haste_remaining = maxf(0.0, _haste_remaining - delta)
	_heat = maxf(0.0, _heat - delta * 2.0)
	var modifiers: Dictionary = _player_modifiers()
	max_health = 100.0 * maxf(0.1, float(modifiers.get("max_health", 1.0)))
	health = minf(max_health, health + maxf(0.0, float(modifiers.get("regen", 0.0))) * delta)
	damage_cooldown = maxf(0.0, damage_cooldown - delta)
	dash_cooldown = maxf(0.0, dash_cooldown - delta)
	dash_remaining = maxf(0.0, dash_remaining - delta)
	aiming = (_aim_toggle if bool(_option("toggle_aim", false)) else Input.is_action_pressed("aim")) and not reloading
	var move_input: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = global_transform.basis * Vector3(move_input.x, 0.0, move_input.y)
	direction.y = 0.0
	direction = direction.normalized()
	var sprint_requested: bool = _sprint_toggle if bool(_option("toggle_sprint", false)) else Input.is_action_pressed("sprint")
	sprinting = (sprint_requested or bool(_option("auto_sprint", false))) and not aiming and direction.length_squared() > 0.1
	if Input.is_action_just_pressed("sprint") and dash_cooldown <= 0.0 and direction.length_squared() > 0.1 and not aiming:
		dash_remaining = 0.19
		dash_cooldown = 1.4
		_dash_direction = direction
	var speed: float = 8.0 if sprinting else 5.8
	if aiming:
		speed = 3.65
	var stats: Dictionary = get_weapon_stats()
	var weapon_mobility: float = clampf(1.0 - (float(stats.get("weight", 0.8)) - 0.8) * 0.22, 0.72, 1.05)
	speed *= float(modifiers.get("move_speed", 1.0)) * weapon_mobility
	if _haste_remaining > 0.0:
		speed *= 1.22
	var target_velocity: Vector3 = direction * speed
	if dash_remaining > 0.0:
		target_velocity = _dash_direction * 13.0
	var acceleration: float = 36.0 if is_on_floor() else 15.0
	velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = 6.2 * float(modifiers.get("jump", 1.0))
	else:
		velocity.y = -0.15
	move_and_slide()
	if global_position.y < -24.0:
		take_damage(max_health * 10.0)
	_update_view(delta, move_input.length())
	var fire_mode: String = str(stats.get("fire_mode", "auto"))
	var trigger: bool = Input.is_action_just_pressed("fire") if fire_mode in ["semi", "burst", "bolt", "pump"] else Input.is_action_pressed("fire")
	if trigger and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		shoot()


func _tick_weapon(delta: float) -> void:
	for index: int in range(_effect_nodes.size()):
		_effect_times[index] = maxf(0.0, _effect_times[index] - delta)
		_effect_nodes[index].visible = _effect_times[index] > 0.0
	fire_cooldown = maxf(0.0, fire_cooldown - delta)
	_empty_click_cooldown = maxf(0.0, _empty_click_cooldown - delta)
	if _burst_remaining > 0 and fire_cooldown <= 0.0 and not reloading:
		_burst_firing = true
		_burst_remaining -= 1
		shoot()
		_burst_firing = false
	if reloading:
		reload_remaining = maxf(0.0, reload_remaining - delta)
		if reload_remaining <= 0.0:
			var stats: Dictionary = get_weapon_stats()
			var transfer: int = mini(int(stats["magazine_size"]) - magazine, reserve)
			magazine += transfer
			reserve -= transfer
			reloading = false
			_save_ammo()
			_play_sound("reload_insert")
			if "reload_blast" in stats.get("modifiers", []):
				_secondary_damage(global_position + Vector3.UP, null, float(stats["damage"]) * 1.4, 5.0, 8, "explosive")


func apply_settings(values: Dictionary) -> void:
	# Settings are edited while the scene tree is paused, so do not wait for physics.
	if is_instance_valid(camera):
		camera.fov = _target_fov(get_weapon_stats(), values)


func _target_fov(stats: Dictionary, values: Dictionary = {}) -> float:
	var base_fov: float = clampf(float(values.get("fov", _option("fov", 76.0))), 60.0, 110.0)
	if aiming:
		return clampf(base_fov / maxf(1.15, float(stats.get("zoom", 1.29))), 20.0, base_fov)
	return base_fov + (4.0 if sprinting else 0.0)


func _update_view(delta: float, movement: float) -> void:
	_camera_recoil = move_toward(_camera_recoil, 0.0, delta * 0.09)
	view_pivot.rotation.x = _pitch
	var grounded_motion: float = movement if is_on_floor() else 0.0
	_bob_time += delta * (13.5 if sprinting else 9.0) * grounded_motion
	var bob: float = sin(_bob_time * 2.0) * 0.017 * grounded_motion * float(_option("head_bob", 1.0))
	view_pivot.position.y = lerpf(view_pivot.position.y, 1.35 + bob, 1.0 - exp(-delta * 14.0))
	var stats: Dictionary = get_weapon_stats()
	var target_fov: float = _target_fov(stats)
	var handling_speed: float = clampf(float(stats.get("handling", 70.0)) / 70.0, 0.4, 1.5)
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-delta * 10.0 * handling_speed))
	camera.rotation.z = sin(time * 42.0) * _camera_recoil * 0.3 * float(_option("camera_shake", 1.0))
	if third_person:
		var desired: Vector3 = view_pivot.to_global(Vector3(0.52, 0.32, 3.2))
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(view_pivot.global_position, desired, PHYSICAL_WORLD_MASK, [get_rid()])
		var wall: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if not wall.is_empty():
			desired = wall["position"] + wall["normal"] * 0.22
		camera.global_position = desired
	else:
		camera.position = Vector3.ZERO
	if is_instance_valid(weapon_view):
		weapon_view.call("set_visual_options", float(_option("visual_recoil", 1.0)), float(_option("weapon_effects", 1.0)), bool(_option("reduced_flashes", false)), _inspect_remaining)
		var reload_progress: float = 1.0 - reload_remaining / maxf(0.01, reload_duration) if reloading else 0.0
		weapon_view.call("animate_view", delta, aiming, grounded_motion, sprinting, _bob_time, reload_progress, reloading)
	if third_person and is_instance_valid(hero):
		hero.position.y = absf(sin(_bob_time)) * 0.045 * grounded_motion
		for index: int in range(_hero_legs.size()):
			_hero_legs[index].rotation.x = sin(_bob_time + (PI if index % 2 == 0 else 0.0)) * 0.45 * grounded_motion


func shoot() -> bool:
	if not _active() or reloading or fire_cooldown > 0.0:
		return false
	var infinite_ammo: bool = bool(_player_modifiers().get("infinite_ammo", false))
	if magazine <= 0 and not infinite_ammo:
		if not start_reload() and _empty_click_cooldown <= 0.0:
			_play_sound("empty")
			_empty_click_cooldown = 0.32
		return false
	if not is_inside_tree() or not is_instance_valid(camera):
		return false
	var stats: Dictionary = get_weapon_stats()
	if not infinite_ammo:
		magazine -= 1
	_inspect_remaining = 0.0
	fire_cooldown = 1.0 / maxf(0.1, float(stats["fire_rate"]))
	if str(stats.get("fire_mode", "auto")) == "burst" and not _burst_firing:
		_burst_remaining = maxi(0, int(stats.get("burst_count", 3)) - 1)
	shot_count += 1
	var trigger_key: String = active_item_uid if not active_item_uid.is_empty() else weapon_id
	_trigger_counts[trigger_key] = int(_trigger_counts.get(trigger_key, 0)) + 1
	if _trigger_counts.size() > 128:
		for old_key: String in _trigger_counts.keys():
			if old_key != trigger_key and (_inventory() == null or _inventory().call("find_item", old_key).is_empty()):
				_trigger_counts.erase(old_key)
				if _trigger_counts.size() <= 128:
					break
	var mods: Array = stats.get("modifiers", [])
	var damage_multiplier: float = 1.0
	if "third_strike" in mods and int(_trigger_counts[trigger_key]) % 3 == 0:
		damage_multiplier *= 2.0
	if "last_word" in mods and magazine == 0:
		damage_multiplier *= 4.0
	if "heat" in mods:
		_heat = minf(10.0, _heat + 1.0)
		damage_multiplier *= 1.0 + _heat * 0.035
	if "desperate" in mods:
		damage_multiplier *= 1.0 + clampf(1.0 - health / max_health, 0.0, 1.0) * 0.7
	stats["damage"] = float(stats["damage"]) * damage_multiplier
	_last_combat_stats = stats
	var ray_origin: Vector3 = camera.global_position
	var direction: Vector3 = -camera.global_transform.basis.z.normalized()
	if _inventory() != null and not aiming and int(stats.get("pellets", 1)) == 1:
		var spread: float = float(stats.get("spread", 0.0))
		var spread_angle: float = _combat_rng.randf() * TAU
		var spread_radius: float = sqrt(_combat_rng.randf()) * spread
		direction = (direction + camera.global_basis.x * cos(spread_angle) * spread_radius + camera.global_basis.y * sin(spread_angle) * spread_radius).normalized()
	var muzzle: Vector3 = view_pivot.global_position - global_transform.basis.z * 0.48 + global_transform.basis.x * 0.21 - Vector3.UP * 0.2
	if not third_person and is_instance_valid(weapon_view):
		muzzle = weapon_view.call("get_muzzle_position")
	var endpoint: Vector3 = ray_origin + direction * float(stats.get("range", 110.0))
	var hit_enemy: bool = false
	var headshot: bool = false
	var critical: bool = false
	var applied_damage: float = 0.0
	var pellets: int = clampi(int(stats.get("pellets", 1)), 1, 16)
	var shots: int = 2 if "double_shot" in mods and _combat_rng.randf() < 0.25 else 1
	for shot_index: int in range(shots):
		for pellet: int in range(pellets):
			var pellet_direction: Vector3 = direction
			# Every pattern has one exact reticle ray; ADS never shifts its center.
			if pellet > 0:
				var radius: float = sqrt(float(pellet) / float(maxi(1, pellets - 1))) * float(stats.get("spread", 0.06)) * (0.68 if aiming else 1.0)
				var angle: float = float(pellet) * 2.399963 + float(shot_count % 6) * 0.18
				pellet_direction = (direction + camera.global_basis.x * cos(angle) * radius + camera.global_basis.y * sin(angle) * radius).normalized()
			var result: Dictionary = _trace_projectile(ray_origin, pellet_direction, muzzle, stats)
			if pellet == 0 and shot_index == 0:
				endpoint = result["point"]
			hit_enemy = hit_enemy or bool(result["hit"])
			headshot = headshot or bool(result["head"])
			critical = critical or bool(result["critical"])
			applied_damage += float(result["damage"])
	if not infinite_ammo and critical and "critical_refund" in mods and _combat_rng.randf() < 0.35:
		magazine = mini(magazine + 1, int(stats["magazine_size"]))
	stats["applied_damage"] = applied_damage
	stats["critical"] = critical
	stats["pellets_fired"] = pellets * shots
	_save_ammo()
	# Mechanical recoil lives in aim pitch. Visual sliders affect only roll/viewmodel.
	var kick: float = float(stats["recoil"]) * (0.60 if aiming else 1.0)
	_pitch = clampf(_pitch + kick, -1.35, 1.30)
	_camera_recoil = minf(0.065, _camera_recoil + kick)
	if is_instance_valid(weapon_view):
		weapon_view.call("fire", float(stats["recoil"]), aiming)
	if is_instance_valid(game) and game.has_method("on_shot"):
		game.call("on_shot", stats, muzzle, endpoint, hit_enemy, headshot)
	if magazine <= 0 and reserve > 0 and not infinite_ammo:
		start_reload()
	return true


func _trace_projectile(origin: Vector3, direction: Vector3, muzzle: Vector3, stats: Dictionary) -> Dictionary:
	var range_limit: float = float(stats.get("range", 110.0))
	var target: Vector3 = origin + direction * range_limit
	var result: Dictionary = {"point": target, "hit": false, "head": false, "critical": false, "damage": 0.0}
	var excluded: Array[RID] = [get_rid()]
	var mods: Array = stats.get("modifiers", [])
	var penetration: int = clampi(maxi(int(stats.get("penetration", stats.get("pierce", 0))), 1 if "pierce" in mods else 0), 0, 5)
	var trace_origin: Vector3 = origin
	for pass_index: int in range(penetration + 1):
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(trace_origin, target, SHOT_MASK, excluded)
		query.collide_with_areas = true
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		var point: Vector3 = hit.get("position", target)
		if pass_index == 0:
			var barrel_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(muzzle, point, WORLD_COLLISION_LAYER, [get_rid()])
			barrel_query.hit_from_inside = true
			var obstruction: Dictionary = get_world_3d().direct_space_state.intersect_ray(barrel_query)
			if not obstruction.is_empty() and muzzle.distance_to(obstruction["position"]) + 0.035 < muzzle.distance_to(point):
				hit = obstruction
				point = obstruction["position"]
			result["point"] = point
		if hit.is_empty():
			break
		var collider: Object = hit.get("collider")
		if not is_instance_valid(collider) or not collider.has_meta("enemy"):
			if str(stats.get("element", "none")) == "explosive":
				_secondary_damage(point, null, float(stats["damage"]) * 0.55, 3.5, 8, "explosive")
			break
		var enemy: Node3D = collider.get_meta("enemy") as Node3D
		if not is_instance_valid(enemy) or not enemy.has_method("take_damage"):
			break
		var zone: String = str(collider.get_meta("zone", "body"))
		var crit: bool = _combat_rng.randf() < float(stats.get("critical_chance", 0.0))
		var amount: float = float(stats["damage"]) * pow(0.76, pass_index) * (float(stats.get("critical_multiplier", 1.5)) if crit else 1.0)
		if zone == "head" and _inventory() != null:
			# Actor supplies the universal 1.75 head multiplier; optics and receivers
			# improve that multiplier without applying the actor bonus twice.
			amount *= float(stats.get("critical_multiplier", 1.75)) / 1.75
		var actual_result: Variant = enemy.call("take_damage", amount, zone, "player")
		var actual: float = float(actual_result) if actual_result != null else 0.0
		if actual > 0.0:
			result["hit"] = true
			result["head"] = bool(result["head"]) or zone == "head"
			result["critical"] = bool(result["critical"]) or crit
			result["damage"] = float(result["damage"]) + actual
			_apply_hit_effects(enemy, point, stats, zone, crit)
		# Exclude every zone of this actor so a penetrating shot hits each actor once.
		if collider is CollisionObject3D:
			excluded.append((collider as CollisionObject3D).get_rid())
		for child: Node in enemy.get_children():
			if child is CollisionObject3D:
				excluded.append((child as CollisionObject3D).get_rid())
		trace_origin = point + direction * 0.025
	return result


func _apply_hit_effects(enemy: Node3D, point: Vector3, stats: Dictionary, zone: String, critical: bool) -> void:
	var mods: Array = stats.get("modifiers", [])
	var element: String = str(stats.get("element", "none"))
	var amount: float = float(stats["damage"])
	if enemy.has_method("apply_status") and not bool(enemy.get("dead")):
		if element == "fire" or "burn" in mods:
			enemy.call("apply_status", "burn", amount * 0.16, 3.0)
		if element == "corrosive":
			enemy.call("apply_status", "corrosive", amount * 0.12, 4.0)
		if element == "cryo" or "cryo" in mods:
			enemy.call("apply_status", "cryo", 0.38, 3.0)
		if element == "shock" or "shock" in mods:
			enemy.call("apply_status", "shock", 0.25, 1.1)
		if "freeze" in mods:
			var key: int = enemy.get_instance_id()
			_freeze_hits[key] = int(_freeze_hits.get(key, 0)) + 1
			if int(_freeze_hits[key]) % 3 == 0:
				enemy.call("apply_status", "freeze", 1.0, 1.3)
			if _freeze_hits.size() > 256:
				_freeze_hits.clear()
	if element == "explosive" or (critical and "critical_blast" in mods):
		_secondary_damage(point, enemy, amount * 0.5, 3.5, 8, "explosive")
	if element == "shock" or "shock" in mods:
		_secondary_damage(point, enemy, amount * 0.38, 5.5, 2, "shock")
	elif "split_shot" in mods:
		_secondary_damage(point, enemy, amount * 0.32, 5.0, 2, "ricochet")
	elif "ricochet" in mods or "seeker" in mods:
		_secondary_damage(point, enemy, amount * 0.45, 6.0, 1, "ricochet")
	if zone == "head" and "headshot_haste" in mods:
		_haste_remaining = 3.5


func _secondary_damage(origin: Vector3, excluded_enemy: Node3D, amount: float, radius: float, target_limit: int, effect: String) -> void:
	if not is_instance_valid(game) or not is_inside_tree():
		return
	var enemies_value: Variant = game.get("enemies")
	if not enemies_value is Array:
		return
	var candidates: Array[Node3D] = []
	for value: Variant in enemies_value:
		var enemy: Node3D = value as Node3D
		if is_instance_valid(enemy) and enemy != excluded_enemy and not bool(enemy.get("dead")) and enemy.global_position.distance_to(origin) <= radius:
			candidates.append(enemy)
	candidates.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.global_position.distance_squared_to(origin) < b.global_position.distance_squared_to(origin))
	var count: int = 0
	if effect == "explosive":
		_combat_effect(origin, origin, Color("eeac6c"), radius * 0.8)
	for enemy: Node3D in candidates:
		if count >= target_limit or not is_instance_valid(enemy):
			break
		var target: Vector3 = enemy.global_position + Vector3.UP * 0.85
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 0.035, target, WORLD_COLLISION_LAYER)
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			continue
		enemy.call("take_damage", amount, "body", "proc")
		if effect == "shock" and enemy.has_method("apply_status"):
			enemy.call("apply_status", "shock", 0.2, 0.8)
		if effect != "explosive":
			_combat_effect(origin, target, Color("a6ddfa") if effect == "shock" else Color("efcd88"), 0.045)
		count += 1


func on_enemy_killed(enemy: Node, source: String = "player") -> void:
	if is_instance_valid(enemy):
		_freeze_hits.erase(enemy.get_instance_id())
	if source not in ["player", "status", "weapon"]:
		return
	var stats: Dictionary = _last_combat_stats if not _last_combat_stats.is_empty() else get_weapon_stats()
	var mods: Array = stats.get("modifiers", [])
	if "kill_frenzy" in mods:
		_frenzy_remaining = 4.0
	if "vampiric" in mods:
		heal(5.0)
	if "death_blast" in mods and is_instance_valid(enemy) and enemy is Node3D:
		_secondary_damage((enemy as Node3D).global_position + Vector3.UP * 0.6, enemy as Node3D, float(stats["damage"]) * 0.8, 4.2, 8, "explosive")


func _combat_effect(from: Vector3, to: Vector3, color: Color, radius: float) -> void:
	if _effect_nodes.is_empty() or float(_option("weapon_effects", 1.0)) <= 0.0:
		return
	var node: MeshInstance3D = _effect_nodes[_effect_cursor]
	var material: StandardMaterial3D = node.material_override as StandardMaterial3D
	material.albedo_color = Color(color, 0.12 if bool(_option("reduced_flashes", false)) else 0.38)
	node.global_position = (from + to) * 0.5
	node.scale = Vector3.ONE * radius
	if from.distance_to(to) > 0.01:
		node.look_at(to, Vector3.UP if absf((to - from).normalized().dot(Vector3.UP)) < 0.98 else Vector3.RIGHT)
		node.scale = Vector3(radius, radius, from.distance_to(to))
	node.visible = true
	_effect_times[_effect_cursor] = 0.13
	_effect_cursor = (_effect_cursor + 1) % _effect_nodes.size()


func start_reload() -> bool:
	if not _active():
		return false
	var stats: Dictionary = get_weapon_stats()
	if reloading or reserve <= 0 or magazine >= int(stats["magazine_size"]):
		return false
	reloading = true
	_inspect_remaining = 0.0
	_burst_remaining = 0
	_reload_was_empty = magazine == 0
	reload_duration = float(stats["reload_time"]) * (float(stats.get("reload_empty_multiplier", 1.15)) if magazine == 0 else 1.0)
	reload_remaining = reload_duration
	_play_sound("reload")
	return true


func equip_weapon(id: String) -> bool:
	var inventory: Object = _inventory()
	if inventory != null:
		_save_ammo()
		var chosen: Dictionary = inventory.call("find_item", id)
		if chosen.is_empty():
			for item: Dictionary in inventory.get("items"):
				if str(item.get("model_id", "")) == id:
					chosen = item
					break
		if chosen.is_empty() or not bool(inventory.call("equip", str(chosen["uid"]))):
			return false
		sync_inventory()
		_notify(str(get_weapon_stats().get("name", weapon_id)))
		return true
	if not owned_weapons.has(id):
		_notify("Compre esta arma no Armeiro · TAB")
		return false
	if id == weapon_id:
		return true
	_save_ammo()
	reloading = false
	reload_remaining = 0.0
	weapon_id = id
	_load_ammo()
	# A slow weapon cannot be accelerated by switching away and back.
	fire_cooldown = maxf(fire_cooldown, 0.28)
	if is_instance_valid(weapon_view):
		weapon_view.call("set_weapon", weapon_id, get_weapon_stats())
	_notify(str(get_weapon_stats()["name"]))
	return true


func buy_weapon(id: String) -> bool:
	if not Data.WEAPONS.has(id) or owned_weapons.has(id) or not is_instance_valid(game):
		return false
	var stats: Dictionary = Data.WEAPONS[id]
	if int(game.get("round_number")) < int(stats["unlock_round"]):
		_notify("Disponível na rodada %d" % int(stats["unlock_round"]))
		return false
	var cost: int = int(stats["price"])
	if not _spend(cost):
		return false
	_grant_weapon(id)
	equip_weapon(id)
	return true


func _grant_weapon(id: String) -> void:
	var stats: Dictionary = Data.WEAPONS[id]
	owned_weapons[id] = {"magazine": int(stats["magazine_size"]), "reserve": int(stats["reserve_ammo"])}
	upgrade_state[id] = {"damage": 0}


func _save_ammo() -> void:
	var inventory: Object = _inventory()
	if inventory != null and not active_item_uid.is_empty():
		var item: Dictionary = inventory.call("find_item", active_item_uid)
		if not item.is_empty():
			item["magazine"] = magazine
			item["reserve"] = reserve
		return
	if owned_weapons.has(weapon_id):
		owned_weapons[weapon_id]["magazine"] = magazine
		owned_weapons[weapon_id]["reserve"] = reserve


func _load_ammo() -> void:
	magazine = int(owned_weapons[weapon_id]["magazine"])
	reserve = int(owned_weapons[weapon_id]["reserve"])


func get_weapon_stats() -> Dictionary:
	var stats: Dictionary = {}
	var inventory: Object = _inventory()
	if inventory != null:
		var item: Dictionary = inventory.call("find_item", active_item_uid) if not active_item_uid.is_empty() else inventory.call("equipped")
		if not item.is_empty():
			stats = inventory.call("stats", item)
			stats = stats.duplicate(true)
	if stats.is_empty():
		stats = Data.WEAPONS.get(weapon_id, Data.WEAPONS["biscuit"]).duplicate(true)
		var levels: Dictionary = upgrade_state.get(weapon_id, {"damage": 0})
		var level: int = int(levels.get("damage", 0))
		stats["damage"] = float(stats["damage"]) * Data.upgrade_multiplier(level)
		stats["damage_level"] = level
	stats["id"] = weapon_id
	var modifiers: Dictionary = _player_modifiers()
	stats["damage"] = float(stats["damage"]) * float(modifiers.get("damage", 1.0))
	stats["fire_rate"] = float(stats["fire_rate"]) * maxf(0.1, float(modifiers.get("fire_rate", 1.0)))
	stats["reload_time"] = float(stats["reload_time"]) / maxf(0.1, float(modifiers.get("reload", 1.0)))
	stats["max_reserve"] = roundi(float(stats["max_reserve"]) * maxf(0.1, float(modifiers.get("ammo_capacity", 1.0))))
	stats["critical_chance"] = clampf(float(stats.get("critical_chance", stats.get("crit_chance", 0.0))) + float(modifiers.get("crit_chance", 0.0)), 0.0, 1.0)
	stats["critical_multiplier"] = maxf(1.0, float(stats.get("critical_multiplier", stats.get("crit_multiplier", 1.5))) * float(modifiers.get("crit_multiplier", 1.0)))
	if _frenzy_remaining > 0.0:
		stats["fire_rate"] = float(stats["fire_rate"]) * 1.35
	if not str(modifiers.get("overcharge", "")).is_empty():
		stats["element"] = str(modifiers["overcharge"])
	if inventory != null and not stats.has("fire_mode"):
		stats["fire_mode"] = {"pistol": "semi", "revolver": "semi", "sniper": "bolt", "shotgun": "pump", "special": "semi"}.get(str(stats.get("family", "rifle")), "auto")
	stats["dps"] = float(stats["damage"]) * float(stats["fire_rate"]) * int(stats.get("pellets", 1))
	return stats


func _inventory() -> Object:
	if not is_instance_valid(game):
		return null
	var inventory: Object = game.get("inventory") as Object
	return inventory if is_instance_valid(inventory) and inventory.has_method("equipped") else null


func sync_inventory() -> void:
	var inventory: Object = _inventory()
	if inventory == null:
		return
	var item: Dictionary = inventory.call("equipped")
	if item.is_empty():
		return
	var changed: bool = active_item_uid != str(item.get("uid", ""))
	active_item_uid = str(item.get("uid", ""))
	weapon_id = str(item.get("model_id", "biscuit"))
	var stats: Dictionary = get_weapon_stats()
	magazine = clampi(int(item.get("magazine", 0)), 0, int(stats["magazine_size"]))
	reserve = clampi(int(item.get("reserve", 0)), 0, int(stats["max_reserve"]))
	reloading = false
	reload_remaining = 0.0
	_burst_remaining = 0
	if changed:
		_inspect_remaining = 0.0
		_heat = 0.0
		var draw_time: float = 0.15 + (100.0 - float(stats.get("handling", 70.0))) * 0.003 + float(stats.get("weight", 1.0)) * 0.035
		fire_cooldown = maxf(fire_cooldown, draw_time / maxf(0.1, float(_player_modifiers().get("equip_speed", 1.0))))
	if is_instance_valid(weapon_view):
		weapon_view.call("set_weapon", weapon_id, stats)
	_save_ammo()


func _player_modifiers() -> Dictionary:
	if is_instance_valid(game) and game.has_method("get_player_modifiers"):
		var result: Variant = game.call("get_player_modifiers")
		if result is Dictionary:
			return result
	return {}


func _option(key: String, fallback: Variant) -> Variant:
	if is_instance_valid(game):
		var settings: Object = game.get("settings") as Object
		if is_instance_valid(settings):
			var data: Variant = settings.get("data")
			if data is Dictionary:
				return data.get(key, fallback)
	return fallback


func _event_action(event: InputEvent, action: String) -> bool:
	return InputMap.has_action(action) and event.is_action_pressed(action)


func snapshot() -> Dictionary:
	_save_ammo()
	return {"version": 1, "health": health, "max_health": max_health, "position": [position.x, position.y, position.z], "yaw": rotation.y, "pitch": _pitch, "third_person": third_person, "weapon_id": weapon_id, "active_item_uid": active_item_uid, "magazine": magazine, "reserve": reserve, "owned_weapons": owned_weapons.duplicate(true), "upgrade_state": upgrade_state.duplicate(true), "flashlight_on": flashlight_on,
		"velocity": [velocity.x, velocity.y, velocity.z], "dash_remaining": dash_remaining, "dash_direction": [_dash_direction.x, _dash_direction.y, _dash_direction.z], "time": time,
		"shot_count": shot_count, "trigger_counts": _trigger_counts.duplicate(), "heat": _heat, "frenzy_remaining": _frenzy_remaining, "haste_remaining": _haste_remaining, "fire_cooldown": fire_cooldown, "damage_cooldown": damage_cooldown, "dash_cooldown": dash_cooldown, "reloading": reloading, "reload_remaining": reload_remaining, "reload_duration": reload_duration, "reload_was_empty": _reload_was_empty, "burst_remaining": _burst_remaining, "aim_toggle": _aim_toggle, "sprint_toggle": _sprint_toggle,
		# Decimal strings preserve all 64 RNG bits across a JSON save/load round trip.
		"rng_seed": str(_combat_rng.seed), "rng_state": str(_combat_rng.state), "last_combat": {"damage": float(_last_combat_stats.get("damage", get_weapon_stats()["damage"])), "modifiers": _last_combat_stats.get("modifiers", []).duplicate()}}


func restore(state: Dictionary) -> bool:
	if state.is_empty() or not _valid_combat_snapshot(state):
		return false
	var saved_position: Variant = state.get("position", [])
	if not saved_position is Array or saved_position.size() != 3:
		return false
	for value: Variant in saved_position:
		if not (value is float or value is int) or not is_finite(float(value)):
			return false
	position = Vector3(float(saved_position[0]), float(saved_position[1]), float(saved_position[2]))
	var saved_yaw: float = float(state.get("yaw", 0.0))
	var saved_pitch: float = float(state.get("pitch", 0.0))
	rotation.y = saved_yaw if is_finite(saved_yaw) else 0.0
	_pitch = clampf(saved_pitch, -1.35, 1.3) if is_finite(saved_pitch) else 0.0
	max_health = 100.0 * maxf(0.1, float(_player_modifiers().get("max_health", 1.0)))
	var saved_health: float = float(state.get("health", max_health))
	health = clampf(saved_health, 0.0, max_health) if is_finite(saved_health) else max_health
	_dead = health <= 0.0
	third_person = bool(state.get("third_person", false))
	flashlight_on = bool(state.get("flashlight_on", false))
	if _inventory() != null:
		var uid: String = str(state.get("active_item_uid", ""))
		if not uid.is_empty():
			_inventory().call("equip", uid)
		sync_inventory()
	else:
		var saved_owned: Variant = state.get("owned_weapons", {})
		if saved_owned is Dictionary:
			for id: String in saved_owned:
				if Data.WEAPONS.has(id) and not owned_weapons.has(id):
					_grant_weapon(id)
		var saved_upgrade: Variant = state.get("upgrade_state", {})
		if saved_upgrade is Dictionary:
			for id: String in saved_upgrade:
				if owned_weapons.has(id) and saved_upgrade[id] is Dictionary:
					upgrade_state[id]["damage"] = maxi(0, int(saved_upgrade[id].get("damage", 0)))
		equip_weapon(str(state.get("weapon_id", "biscuit")))
	var stats: Dictionary = get_weapon_stats()
	magazine = clampi(int(state.get("magazine", magazine)), 0, int(stats["magazine_size"]))
	reserve = clampi(int(state.get("reserve", reserve)), 0, int(stats["max_reserve"]))
	shot_count = clampi(int(state.get("shot_count", 0)), 0, 1000000000)
	_trigger_counts = state.get("trigger_counts", {}).duplicate()
	_heat = clampf(float(state.get("heat", 0.0)), 0.0, 10.0)
	_frenzy_remaining = clampf(float(state.get("frenzy_remaining", 0.0)), 0.0, 30.0)
	_haste_remaining = clampf(float(state.get("haste_remaining", 0.0)), 0.0, 30.0)
	fire_cooldown = clampf(float(state.get("fire_cooldown", 0.0)), 0.0, 30.0)
	damage_cooldown = clampf(float(state.get("damage_cooldown", 0.0)), 0.0, 30.0)
	dash_cooldown = clampf(float(state.get("dash_cooldown", 0.0)), 0.0, 30.0)
	reload_duration = clampf(float(state.get("reload_duration", 0.0)), 0.0, 120.0)
	reload_remaining = clampf(float(state.get("reload_remaining", 0.0)), 0.0, reload_duration)
	reloading = bool(state.get("reloading", false)) and reload_remaining > 0.0 and reserve > 0 and magazine < int(stats["magazine_size"])
	if not reloading:
		reload_remaining = 0.0
	_reload_was_empty = bool(state.get("reload_was_empty", false))
	_burst_remaining = 0 if reloading else clampi(int(state.get("burst_remaining", 0)), 0, 5)
	_aim_toggle = bool(state.get("aim_toggle", false))
	_sprint_toggle = bool(state.get("sprint_toggle", false))
	if state.has("rng_seed"):
		_combat_rng.seed = int(state["rng_seed"])
	if state.has("rng_state"):
		_combat_rng.state = int(state["rng_state"])
	_last_combat_stats = state.get("last_combat", {}).duplicate(true)
	var saved_velocity: Array = state.get("velocity", [0.0, 0.0, 0.0])
	velocity = Vector3(float(saved_velocity[0]), float(saved_velocity[1]), float(saved_velocity[2])).limit_length(60.0)
	var saved_dash: Array = state.get("dash_direction", [0.0, 0.0, 0.0])
	_dash_direction = Vector3(float(saved_dash[0]), 0.0, float(saved_dash[2])).normalized()
	dash_remaining = clampf(float(state.get("dash_remaining", 0.0)), 0.0, 0.3)
	time = maxf(0.0, float(state.get("time", 0.0)))
	_save_ammo()
	_sync_perspective()
	if is_instance_valid(flashlight):
		flashlight.visible = flashlight_on
	return true


func _valid_combat_snapshot(state: Dictionary) -> bool:
	if state.has("active_item_uid"):
		var uid: Variant = state["active_item_uid"]
		if not uid is String or str(uid).length() > 128:
			return false
		if not str(uid).is_empty() and _inventory() != null and _inventory().call("find_item", str(uid)).is_empty():
			return false
	for key: String in ["health", "yaw", "pitch", "magazine", "reserve", "shot_count", "heat", "frenzy_remaining", "haste_remaining", "fire_cooldown", "damage_cooldown", "dash_cooldown", "reload_duration", "reload_remaining", "burst_remaining", "dash_remaining", "time"]:
		if state.has(key):
			var value: Variant = state[key]
			if not (value is int or value is float) or not is_finite(float(value)):
				return false
	for key: String in ["velocity", "dash_direction"]:
		if state.has(key):
			var vector: Variant = state[key]
			if not vector is Array or vector.size() != 3:
				return false
			for value: Variant in vector:
				if not (value is int or value is float) or not is_finite(float(value)):
					return false
	var triggers: Variant = state.get("trigger_counts", {})
	if not triggers is Dictionary or triggers.size() > 128:
		return false
	for key: Variant in triggers:
		var value: Variant = triggers[key]
		if not key is String or str(key).length() > 128 or not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0.0 or float(value) > 1000000000.0:
			return false
	for key: String in ["rng_seed", "rng_state"]:
		if state.has(key) and (not state[key] is String or str(state[key]).length() > 20 or not str(state[key]).is_valid_int()):
			return false
	var last_combat: Variant = state.get("last_combat", {})
	if not last_combat is Dictionary:
		return false
	if not last_combat.is_empty():
		var damage: Variant = last_combat.get("damage", 0.0)
		var modifiers: Variant = last_combat.get("modifiers", [])
		if not (damage is float or damage is int) or not is_finite(float(damage)) or float(damage) < 0.0 or not modifiers is Array or modifiers.size() > 32:
			return false
		for modifier: Variant in modifiers:
			if not modifier is String or str(modifier).length() > 64:
				return false
	return true


func get_upgrade_cost() -> int:
	var levels: Dictionary = upgrade_state.get(weapon_id, {"damage": 0})
	var level: int = int(levels.get("damage", 0))
	return Data.upgrade_cost(level)


func get_ammo() -> Dictionary:
	return {"magazine": magazine, "reserve": reserve, "reloading": reloading, "reload_remaining": reload_remaining, "reload_duration": reload_duration}


func upgrade_damage() -> bool:
	if not _spend(get_upgrade_cost()):
		return false
	upgrade_state[weapon_id]["damage"] = int(upgrade_state[weapon_id]["damage"]) + 1
	_notify("Melhoria %d · dano %.1f" % [int(upgrade_state[weapon_id]["damage"]), float(get_weapon_stats()["damage"])])
	return true


func get_refill_cost() -> int:
	return 75 + int(Data.WEAPONS[weapon_id]["unlock_round"]) * 15


func refill() -> bool:
	var stats: Dictionary = get_weapon_stats()
	if reserve >= int(stats["max_reserve"]) and magazine >= int(stats["magazine_size"]):
		_notify("Munição completa")
		return false
	if not _spend(get_refill_cost()):
		return false
	reserve = int(stats["max_reserve"])
	magazine = int(stats["magazine_size"])
	reloading = false
	reload_remaining = 0.0
	_save_ammo()
	_notify("Munição reabastecida")
	return true


func add_ammo(amount: int) -> void:
	reserve = mini(int(get_weapon_stats()["max_reserve"]), reserve + maxi(0, amount))
	_save_ammo()


func heal(amount: float) -> void:
	health = minf(max_health, health + maxf(0.0, amount))


func revive_from_companion(amount: float) -> void:
	_dead = false
	health = clampf(amount, 1.0, max_health)
	damage_cooldown = 1.5
	reloading = false
	reload_remaining = 0.0


func take_damage(amount: float, source: Node3D = null) -> void:
	if _dead or health <= 0.0 or not is_finite(amount) or amount <= 0.0 or damage_cooldown > 0.0 or dash_remaining > 0.0:
		return
	var normal_enemy: bool = is_instance_valid(source) and source.is_in_group("meyui_enemies") and str(source.get("kind")) != "boss" and str(source.get("boss_id")).is_empty()
	# Incoming enemy damage already includes attack, round, difficulty and elite
	# scaling. Cap that threat first so armor and Faro still help at high rounds.
	var hit_limit: float = maxf(0.0, max_health * NORMAL_ENEMY_HIT_FRACTION)
	var incoming: float = minf(amount, hit_limit) if normal_enemy else amount
	var applied: float = incoming * (1.0 - clampf(float(_player_modifiers().get("resistance", 0.0)), 0.0, 0.8))
	var before_shield: float = applied
	var source_world: Vector3 = source.global_position if is_instance_valid(source) and source.is_inside_tree() else Vector3.INF
	if is_instance_valid(game):
		var dog: Object = game.get("companion") as Object
		if is_instance_valid(dog) and dog.has_method("absorb_damage"):
			applied = clampf(float(dog.call("absorb_damage", applied)), 0.0, before_shield)
	var absorbed: float = before_shield - applied
	if normal_enemy:
		applied = minf(applied, hit_limit)
	applied = minf(applied, health)
	if applied <= 0.0:
		damage_cooldown = 0.15
		if absorbed > 0.0 and is_instance_valid(game) and game.has_method("on_player_damaged"):
			game.call("on_player_damaged", absorbed, source_world, true)
		return
	health = maxf(0.0, health - applied)
	damage_cooldown = HIT_GRACE_SECONDS
	if is_instance_valid(game) and game.has_method("on_player_damaged"):
		game.call("on_player_damaged", applied, source_world, false)
	if health <= 0.0:
		_dead = true
		reloading = false
		if is_instance_valid(game) and game.has_method("on_player_died"):
			game.call("on_player_died")


func _spend(amount: int) -> bool:
	if not is_instance_valid(game) or int(game.get("coins")) < amount:
		_notify("Petiscos insuficientes")
		return false
	game.set("coins", int(game.get("coins")) - amount)
	return true


func _notify(message: String) -> void:
	if is_instance_valid(game) and game.has_method("notify"):
		game.call("notify", message)


func _play_sound(sound_id: String) -> void:
	if not is_instance_valid(game):
		return
	var game_audio: Object = game.get("audio") as Object
	if is_instance_valid(game_audio) and game_audio.has_method("play"):
		game_audio.call("play", sound_id)


func _sync_perspective() -> void:
	if is_instance_valid(hero):
		hero.visible = third_person
	if is_instance_valid(weapon_view):
		weapon_view.visible = not third_person
	if is_instance_valid(camera) and not third_person:
		camera.position = Vector3.ZERO


func _hero_part(part_name: String, pos: Vector3, size: Vector3, color: Color, parent: Node3D = null) -> MeshInstance3D:
	var mesh_node: MeshInstance3D = MeshInstance3D.new()
	mesh_node.name = part_name
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	mesh_node.mesh = mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	mesh_node.material_override = material
	mesh_node.position = pos
	(parent if parent != null else hero).add_child(mesh_node)
	return mesh_node


func _build_hero() -> void:
	hero = Node3D.new()
	hero.name = "MeyuiDachshund"
	add_child(hero)
	var fur: Color = Color("915330")
	var dark: Color = Color("482e28")
	var tan: Color = Color("d8a373")
	_hero_part("LongBody", Vector3(0.0, 0.68, 0.12), Vector3(0.46, 0.45, 1.03), fur)
	_hero_part("TealJacket", Vector3(0.0, 0.74, 0.2), Vector3(0.48, 0.36, 0.57), Color("477e77"))
	_hero_part("Head", Vector3(0.0, 1.08, -0.40), Vector3(0.42, 0.45, 0.43), fur)
	_hero_part("Muzzle", Vector3(0.0, 0.99, -0.70), Vector3(0.28, 0.21, 0.31), tan)
	_hero_part("Nose", Vector3(0.0, 1.05, -0.87), Vector3(0.19, 0.12, 0.07), dark)
	_hero_part("LeftEar", Vector3(-0.25, 0.91, -0.32), Vector3(0.13, 0.49, 0.23), dark).rotation.z = -0.12
	_hero_part("RightEar", Vector3(0.25, 0.91, -0.32), Vector3(0.13, 0.49, 0.23), dark).rotation.z = 0.12
	_hero_part("EyeLeft", Vector3(-0.135, 1.19, -0.622), Vector3(0.065, 0.067, 0.035), Color("201f25"))
	_hero_part("EyeRight", Vector3(0.135, 1.19, -0.622), Vector3(0.065, 0.067, 0.035), Color("201f25"))
	_hero_part("Bandana", Vector3(0.0, 0.88, -0.45), Vector3(0.44, 0.12, 0.19), Color("eead61"))
	_hero_part("Tail", Vector3(0.0, 0.9, 0.73), Vector3(0.10, 0.12, 0.50), fur).rotation.x = -0.45
	for index: int in range(4):
		var leg: Node3D = Node3D.new()
		leg.name = "Leg%d" % index
		leg.position = Vector3(-0.17 if index % 2 == 0 else 0.17, 0.5, -0.22 if index < 2 else 0.43)
		hero.add_child(leg)
		_hero_part("Paw", Vector3(0.0, -0.22, -0.03), Vector3(0.16, 0.43, 0.23), fur, leg)
		_hero_legs.append(leg)

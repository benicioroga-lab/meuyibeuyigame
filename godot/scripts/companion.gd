class_name MeyuiCompanion
extends CharacterBody3D

## Faro follows native navigation paths and commits short, readable bite attacks.
const ActorVisual = preload("res://scripts/actor_visual.gd")
const Data = preload("res://data/dog_data.gd")

var game: Node
var health: float = 70.0
var max_health: float = 70.0
var level: int = 1
var mode: String = "hunt"
var follow_only: bool = false
var damage: float = 12.0
var attack_interval: float = 1.6
var archetype: String = "combat"
var levels: Dictionary = {"attack": 0, "survival": 0, "loot": 0, "support": 0}
var owned_archetypes: Array[String] = ["combat"]
var shield: float = 0.0
var shield_max: float = 0.0
var stats: Dictionary = {}
var _agent: NavigationAgent3D
var _visual: Dictionary = {}
var _model: Node3D
var _enemy_target: Node3D
var _search_timer: float = 0.0
var _path_timer: float = 0.0
var _attack_timer: float = 0.4
var _bite_time: float = 0.0
var _downed_time: float = 0.0
var _hurt_time: float = 0.0
var _gait: float = 0.0
var _ability_timer: float = 0.0
var _heal_timer: float = 0.0
var _taunt_timer: float = 0.0
var _shield_delay: float = 0.0
var _revive_cooldown: float = 0.0
var _gear: Node3D
var _shield_visual: MeshInstance3D


func setup(owner_game: Node) -> void:
	game = owner_game
	_merge_profile_unlocks()
	_recalculate_stats()


func _ready() -> void:
	name = "Faro"
	add_to_group("meyui_companion")
	collision_layer = 16
	collision_mask = 1 | 4 | 32
	floor_snap_length = 0.55
	floor_max_angle = deg_to_rad(50.0)
	floor_stop_on_slope = true
	var shape := CapsuleShape3D.new()
	shape.radius = 0.24
	shape.height = 0.64
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = 0.34
	add_child(collision)
	_visual = ActorVisual.build_dog(self)
	_model = _visual.get("root") as Node3D
	_agent = NavigationAgent3D.new()
	_agent.path_desired_distance = 0.22
	_agent.path_height_offset = 0.1
	_agent.target_desired_distance = 0.85
	_agent.path_max_distance = 2.4
	_agent.radius = 0.27
	_agent.height = 0.7
	_agent.avoidance_enabled = false
	add_child(_agent)
	_refresh_upgrade_visual()


func toggle_mode() -> void:
	follow_only = not follow_only
	mode = "follow" if follow_only else "hunt"
	_enemy_target = null
	_bite_time = 0.0
	_search_timer = 0.0
	_path_timer = 0.0
	if is_instance_valid(game) and game.has_method("notify"):
		game.notify("Faro está seguindo você." if follow_only else "Faro está caçando a Liga do Ruído.")


func get_upgrade_cost() -> int:
	return branch_cost("attack")


func upgrade() -> bool:
	return upgrade_branch("attack")


func branch_cost(branch: String) -> int:
	return Data.branch_cost(branch, int(levels.get(branch, 0)))


func upgrade_branch(branch: String) -> bool:
	if not Data.BRANCHES.has(branch) or not is_instance_valid(game):
		return false
	var cost: int = branch_cost(branch)
	if int(game.coins) < cost:
		_notify("A melhoria %s custa %d moedas." % [Data.BRANCHES[branch]["name"], cost])
		return false
	game.coins -= cost
	levels[branch] = int(levels[branch]) + 1
	var previous_max: float = max_health
	_recalculate_stats()
	if health > 0.0:
		health = minf(max_health, health + maxf(0.0, max_health - previous_max))
	_refresh_upgrade_visual()
	_notify("Faro · %s nível %d" % [Data.BRANCHES[branch]["name"], int(levels[branch])])
	return true


func switch_archetype(id: String) -> bool:
	if not Data.ARCHETYPES.has(id) or not is_instance_valid(game):
		return false
	_merge_profile_unlocks()
	if not owned_archetypes.has(id):
		var cost: int = int(Data.ARCHETYPES[id]["cost"])
		if int(game.coins) < cost:
			_notify("Essa especialização custa %d moedas." % cost)
			return false
		game.coins -= cost
		owned_archetypes.append(id)
	var ratio: float = health / maxf(1.0, max_health)
	archetype = id
	_recalculate_stats()
	health = max_health * ratio
	shield = minf(shield, shield_max)
	_enemy_target = null
	_bite_time = 0.0
	_search_timer = 0.0
	_refresh_upgrade_visual()
	_notify(str(Data.ARCHETYPES[id]["name"]))
	return true


func _recalculate_stats() -> void:
	stats = Data.stats(levels, archetype)
	level = 1
	for branch in levels:
		level += int(levels[branch])
	damage = float(stats["damage"])
	max_health = float(stats["max_health"])
	attack_interval = float(stats["interval"])
	shield_max = float(stats["shield_max"])
	health = minf(health, max_health)
	shield = minf(shield, shield_max)


func _merge_profile_unlocks() -> void:
	if not is_instance_valid(game):
		return
	var profile: Variant = game.get("profile")
	if not profile is Dictionary:
		return
	var unlocks: Variant = profile.get("unlocks", [])
	if unlocks is Array:
		for id in unlocks:
			var key: String = str(id).trim_prefix("dog_")
			if Data.ARCHETYPES.has(key) and not owned_archetypes.has(key):
				owned_archetypes.append(key)


func get_progression() -> Dictionary:
	var branches: Array[Dictionary] = []
	for id in Data.BRANCHES:
		var info: Dictionary = Data.BRANCHES[id]
		var upgraded: Dictionary = levels.duplicate()
		upgraded[id] = int(upgraded[id]) + 1
		var next_stats: Dictionary = Data.stats(upgraded, archetype)
		var stat: String = {"attack": "damage", "survival": "max_health", "loot": "loot_radius", "support": "heal"}[id]
		branches.append({"id": id, "name": info["name"], "level": int(levels[id]), "cost": branch_cost(id), "description": info["description"], "value": stats[stat], "next_value": next_stats[stat]})
	var archetypes: Array[Dictionary] = []
	for id in Data.ARCHETYPES:
		var info: Dictionary = Data.ARCHETYPES[id]
		archetypes.append({"id": id, "name": info["name"], "cost": 0 if owned_archetypes.has(id) else int(info["cost"]), "owned": owned_archetypes.has(id), "unlocked": owned_archetypes.has(id), "active": archetype == id, "description": info["description"]})
	return {"archetype": archetype, "name": Data.ARCHETYPES[archetype]["name"], "level": level, "levels": levels.duplicate(),
		"branches": branches, "archetypes": archetypes, "owned_archetypes": owned_archetypes.duplicate(), "stats": stats.duplicate(),
		"damage": damage, "health": health, "max_health": max_health, "shield": shield,
		"revive_cooldown": _revive_cooldown, "revive_ready": _can_revive() and _revive_cooldown <= 0.0, "status": get_status()}


func get_status() -> String:
	if _downed_time > 0.0:
		return "Faro Nv.%d · recuperando %ds" % [level, ceili(_downed_time)]
	if follow_only:
		return "Faro Nv.%d · seguindo" % level
	var action: String = {"combat": "caçando", "collector": "farejando", "support": "cuidando", "guardian": "protegendo"}.get(archetype, "caçando")
	return "Faro Nv.%d · %s" % [level, action]


func _physics_process(delta: float) -> void:
	if not is_instance_valid(game) or not game.running or game.paused or not is_instance_valid(game.player):
		return
	_hurt_time = maxf(0.0, _hurt_time - delta)
	_revive_cooldown = maxf(0.0, _revive_cooldown - delta)
	if _downed_time > 0.0:
		_downed_time -= delta
		_model.rotation.z = lerpf(_model.rotation.z, 1.25, delta * 8.0)
		velocity.x = move_toward(velocity.x, 0.0, delta * 16.0)
		velocity.z = move_toward(velocity.z, 0.0, delta * 16.0)
		_apply_gravity(delta)
		move_and_slide()
		if _downed_time <= 0.0:
			health = max_health
			collision_layer = 16
			if game.has_method("notify"):
				game.notify("Faro se recuperou e voltou à ação.")
		return
	_update_abilities(delta)
	_model.rotation.z = lerpf(_model.rotation.z, 0.0, delta * 8.0)
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_search_timer -= delta
	if _search_timer <= 0.0:
		_search_timer = 0.38
		_select_target()
	var attacking: bool = is_instance_valid(_enemy_target) and not bool(_enemy_target.get("dead")) and not follow_only
	var goal: Vector3 = game.player.global_position
	if attacking:
		goal = _enemy_target.global_position
	var to_goal: Vector3 = goal - global_position
	var flat: Vector3 = Vector3(to_goal.x, 0, to_goal.z)
	var distance: float = flat.length()
	var stop_distance: float = 0.93 if attacking else 1.8
	if _bite_time > 0.0:
		_bite_time -= delta
		if _bite_time <= 0.0 and attacking and distance < 1.45 and absf(to_goal.y) < 1.3 and _clear_sight(_enemy_target):
			_enemy_target.take_damage(damage, "body", "faro")
			if archetype == "combat" and int(levels["attack"]) >= 2 and is_instance_valid(_enemy_target) and _enemy_target.has_method("apply_status"):
				_enemy_target.apply_status("shock", 0.18, 0.65)
			if game.has_method("on_dog_attack"):
				game.on_dog_attack(_enemy_target)
			_attack_timer = attack_interval
	elif attacking and _attack_timer <= 0.0 and distance < 1.18 and absf(to_goal.y) < 1.15 and _clear_sight(_enemy_target):
		_bite_time = 0.18
		_attack_timer = attack_interval
	var direction: Vector3 = Vector3.ZERO
	if (distance > stop_distance or absf(to_goal.y) > 0.6) and _bite_time <= 0.0:
		direction = _navigation_direction(goal, delta)
	var move_speed: float = float(stats.get("speed", 4.1))
	if not attacking and distance > 7.0:
		move_speed = 5.7
	velocity.x = move_toward(velocity.x, direction.x * move_speed, delta * 18.0)
	velocity.z = move_toward(velocity.z, direction.z * move_speed, delta * 18.0)
	_apply_gravity(delta)
	move_and_slide()
	var facing: Vector3 = direction if direction.length_squared() > 0.05 else flat.normalized()
	if facing.length_squared() > 0.05 and (attacking or direction.length_squared() > 0.05):
		rotation.y = lerp_angle(rotation.y, atan2(-facing.x, -facing.z), delta * 11.0)
	_animate(delta)


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 22.0 * delta
	else:
		velocity.y = -0.3


func _select_target() -> void:
	_enemy_target = null
	if follow_only or global_position.distance_to(game.player.global_position) > 17.0:
		return
	var closest: float = 12.0 if archetype == "combat" else (7.0 if archetype == "guardian" else 3.2)
	for enemy in game.enemies:
		if not is_instance_valid(enemy) or enemy.dead:
			continue
		var distance: float = global_position.distance_to(enemy.global_position)
		if distance < closest and enemy.global_position.distance_to(game.player.global_position) < 18.0:
			_enemy_target = enemy as Node3D
			closest = distance
	_path_timer = 0.0


func _navigation_direction(goal: Vector3, delta: float) -> Vector3:
	_path_timer -= delta
	var waypoint: Vector3 = goal
	if is_instance_valid(game.world) and game.world.navigation_ready and NavigationServer3D.map_get_iteration_id(_agent.get_navigation_map()) > 0:
		if _path_timer <= 0.0:
			_path_timer = 0.3
			_agent.target_position = goal
		if not _agent.is_navigation_finished():
			waypoint = _agent.get_next_path_position()
	var direction: Vector3 = waypoint - global_position
	direction.y = 0.0
	return direction.normalized() if direction.length_squared() > 0.000025 else Vector3.ZERO


func _clear_sight(target: Node3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.38, target.global_position + Vector3.UP * 0.8, 1 | 32)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func take_damage(amount: float) -> void:
	if _downed_time > 0.0 or amount <= 0.0:
		return
	health = maxf(0.0, health - amount * (1.0 - float(stats.get("resistance", 0.0))))
	_hurt_time = 0.18
	if health <= 0.0:
		_downed_time = float(stats.get("recover_time", 5.0))
		_bite_time = 0.0
		_enemy_target = null
		collision_layer = 0
		if is_instance_valid(game) and game.has_method("notify"):
			game.notify("Faro caiu. Ele está se recuperando.")


func _update_abilities(delta: float) -> void:
	_ability_timer -= delta
	_heal_timer -= delta
	_taunt_timer -= delta
	_shield_delay = maxf(0.0, _shield_delay - delta)
	if shield_max > 0.0 and _shield_delay <= 0.0:
		shield = minf(shield_max, shield + delta * (4.0 + sqrt(float(levels["survival"]))))
	if _ability_timer <= 0.0:
		_ability_timer = 0.75
		if (archetype == "collector" or int(levels["loot"]) > 0) and game.has_method("collect_nearby_drops"):
			game.collect_nearby_drops(global_position, float(stats["loot_radius"]))
	if _heal_timer <= 0.0 and float(stats["heal"]) > 0.0:
		_heal_timer = 4.0
		if global_position.distance_to(game.player.global_position) <= 7.0 and game.player.health > 0.0:
			if game.player.has_method("heal"):
				game.player.heal(float(stats["heal"]))
			else:
				game.player.health = minf(game.player.max_health, game.player.health + float(stats["heal"]))
	if archetype == "guardian" and _taunt_timer <= 0.0:
		_taunt_timer = 4.8
		var count: int = 0
		for enemy in game.enemies:
			if count >= 4:
				break
			if is_instance_valid(enemy) and not enemy.dead and enemy.global_position.distance_to(global_position) < 5.0 and enemy.has_method("taunt"):
				enemy.taunt(self, 2.7)
				count += 1


func absorb_damage(amount: float) -> float:
	if amount <= 0.0 or health <= 0.0 or _downed_time > 0.0 or shield <= 0.0 or archetype != "guardian":
		return maxf(0.0, amount)
	if not is_instance_valid(game) or not is_instance_valid(game.player) or global_position.distance_to(game.player.global_position) > 7.0:
		return amount
	var absorbed: float = minf(shield, amount * 0.45)
	shield -= absorbed
	_shield_delay = 4.0
	return maxf(0.0, amount - absorbed)


func _can_revive() -> bool:
	return archetype in ["support", "guardian"] or int(levels["support"]) >= 3


func try_revive() -> bool:
	if not _can_revive() or _revive_cooldown > 0.0 or health <= 0.0 or _downed_time > 0.0:
		return false
	if not is_instance_valid(game) or not is_instance_valid(game.player) or game.player.health > 0.0:
		return false
	if global_position.distance_to(game.player.global_position) > 12.0:
		return false
	var restored: float = maxf(1.0, game.player.max_health * 0.35)
	if game.player.has_method("revive_from_companion"):
		game.player.revive_from_companion(restored)
	else:
		game.player.health = restored
	_revive_cooldown = float(stats.get("revive_delay", 100.0))
	_notify("Faro te resgatou! Volte para a luta.")
	return true


func export_state() -> Dictionary:
	return {"version": 2, "archetype": archetype, "levels": levels.duplicate(), "owned_archetypes": owned_archetypes.duplicate(),
		"health": health, "max_health": max_health, "level": level, "mode": mode, "follow_only": follow_only,
		"position": [global_position.x, global_position.y, global_position.z], "rotation_y": rotation.y,
		"shield": shield, "shield_delay": _shield_delay, "revive_cooldown": _revive_cooldown, "downed_time": _downed_time,
		"attack_timer": _attack_timer, "heal_timer": _heal_timer, "ability_timer": _ability_timer}


func import_state(state: Dictionary) -> void:
	for branch in Data.BRANCHES:
		var saved: Variant = state.get("levels", {})
		levels[branch] = maxi(0, int(saved.get(branch, 0))) if saved is Dictionary else 0
	if not state.has("levels"):
		levels["attack"] = maxi(0, int(state.get("level", 1)) - 1)
	owned_archetypes = ["combat"]
	var unlocked: Variant = state.get("owned_archetypes", [])
	if unlocked is Array:
		for id in unlocked:
			if Data.ARCHETYPES.has(str(id)) and not owned_archetypes.has(str(id)):
				owned_archetypes.append(str(id))
	_merge_profile_unlocks()
	var saved_type: String = str(state.get("archetype", "combat"))
	archetype = saved_type if owned_archetypes.has(saved_type) else "combat"
	_recalculate_stats()
	health = clampf(float(state.get("health", max_health)), 0.0, max_health)
	follow_only = bool(state.get("follow_only", state.get("mode", "hunt") == "follow"))
	mode = "follow" if follow_only else "hunt"
	shield = clampf(float(state.get("shield", 0.0)), 0.0, shield_max)
	_shield_delay = clampf(float(state.get("shield_delay", 0.0)), 0.0, 4.0)
	_revive_cooldown = clampf(float(state.get("revive_cooldown", 0.0)), 0.0, 150.0)
	_downed_time = clampf(float(state.get("downed_time", 0.0)), 0.0, 5.0)
	if health <= 0.0:
		_downed_time = maxf(0.1, _downed_time)
	_attack_timer = maxf(0.2, float(state.get("attack_timer", 0.4)))
	_heal_timer = maxf(0.1, float(state.get("heal_timer", 0.5)))
	_ability_timer = maxf(0.1, float(state.get("ability_timer", 0.2)))
	_enemy_target = null
	_bite_time = 0.0
	if state.get("position") is Array and state["position"].size() == 3:
		var at: Array = state["position"]
		global_position = Vector3(float(at[0]), float(at[1]), float(at[2]))
	rotation.y = float(state.get("rotation_y", 0.0))
	if is_inside_tree():
		collision_layer = 0 if _downed_time > 0.0 else 16
		_refresh_upgrade_visual()


func _notify(message: String) -> void:
	if is_instance_valid(game) and game.has_method("notify"):
		game.notify(message)


func _animate(delta: float) -> void:
	var moving: float = Vector2(velocity.x, velocity.z).length()
	_gait += delta * moving * 6.5
	var amount: float = minf(moving / 2.0, 1.0)
	var legs: Array = _visual.get("legs", [])
	for index in legs.size():
		var leg := legs[index] as Node3D
		var offset: float = PI if index == 1 or index == 2 else 0.0
		leg.rotation.x = sin(_gait + offset) * 0.56 * amount
	var tail := _visual.get("tail") as Node3D
	if is_instance_valid(tail):
		tail.rotation.y = sin(_gait * 0.7 + Time.get_ticks_msec() * 0.007) * 0.38
	var ears: Array = _visual.get("ears", [])
	for entry in ears:
		var ear := entry as Node3D
		ear.rotation.x = sin(_gait) * 0.14 * amount
	_model.position.y = absf(sin(_gait)) * 0.022 * amount + sin(clampf(_bite_time / 0.18, 0.0, 1.0) * PI) * 0.16
	if is_instance_valid(_shield_visual):
		_shield_visual.visible = shield > 0.5
	var materials: Array = _visual.get("materials", [])
	var colors: Array = _visual.get("default_colors", [])
	for index in mini(materials.size(), colors.size()):
		var material := materials[index] as StandardMaterial3D
		var color: Color = colors[index]
		material.albedo_color = color.lerp(Color(1.0, 0.2, 0.15), clampf(_hurt_time * 4.0, 0.0, 0.65))


func _refresh_upgrade_visual() -> void:
	var collar := _visual.get("collar") as MeshInstance3D
	if not is_instance_valid(collar):
		return
	var material := collar.material_override as StandardMaterial3D
	if not is_instance_valid(material):
		return
	var color: Color = Data.ARCHETYPES[archetype]["color"]
	material.albedo_color = color
	material.metallic = minf(0.7, 0.15 + float(level - 1) * 0.04)
	material.emission_enabled = level >= 3
	material.emission = color * 0.25
	var materials: Array = _visual.get("materials", [])
	var base_colors: Array = _visual.get("default_colors", [])
	var index: int = materials.find(material)
	if index >= 0 and index < base_colors.size():
		base_colors[index] = color
	_refresh_gear(color)


func _refresh_gear(color: Color) -> void:
	if not is_instance_valid(_model):
		return
	if is_instance_valid(_gear):
		_gear.visible = false
		_gear.queue_free()
	_gear = Node3D.new()
	_gear.name = "FaroEquipment"
	_model.add_child(_gear)
	_shield_visual = null
	var tier: int = mini(4, 1 + floori(log(1.0 + float(level - 1)) / log(3.0)))
	for index in tier:
		_gear_box("CollarRank", Vector3(0.0, 0.525, -0.28 + float(index) * 0.064), Vector3(0.085, 0.026, 0.028), color.lightened(0.15))
	if int(levels["survival"]) > 0 or archetype == "guardian":
		_gear_box("BackArmor", Vector3(0.0, 0.49, 0.04), Vector3(0.25, 0.11, 0.53), Color("39434c"))
		_gear_box("ArmorStripe", Vector3(0.0, 0.551, 0.04), Vector3(0.095, 0.015, 0.42), color)
		if int(levels["survival"]) >= 5:
			_gear_box("ChestPlate", Vector3(0.0, 0.26, -0.38), Vector3(0.23, 0.18, 0.075), Color("4b5c69"))
	if int(levels["loot"]) > 0 or archetype == "collector":
		for side in [-1.0, 1.0]:
			_gear_box("SupplyPouch", Vector3(side * 0.215, 0.34, 0.15), Vector3(0.135, 0.19, 0.28), Color("655546"))
			_gear_box("PouchBuckle", Vector3(side * 0.29, 0.365, 0.15), Vector3(0.014, 0.057, 0.047), color)
	if int(levels["support"]) > 0 or archetype == "support":
		_gear_box("SupportPack", Vector3(0.0, 0.565, 0.15), Vector3(0.23, 0.13, 0.22), color.darkened(0.12))
		_gear_box("PackMark", Vector3(0.0, 0.638, 0.15), Vector3(0.115, 0.018, 0.03), Color("f4eedf"))
		_gear_box("PackMark", Vector3(0.0, 0.638, 0.15), Vector3(0.03, 0.018, 0.115), Color("f4eedf"))
	if archetype == "guardian":
		_shield_visual = MeshInstance3D.new()
		var ring := TorusMesh.new()
		ring.inner_radius = 0.43
		ring.outer_radius = 0.47
		ring.rings = 24
		ring.ring_segments = 6
		_shield_visual.mesh = ring
		_shield_visual.scale.z = 1.55
		_shield_visual.position.y = 0.05
		var ring_material := StandardMaterial3D.new()
		ring_material.albedo_color = Color(0.55, 0.73, 1.0, 0.5)
		ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shield_visual.material_override = ring_material
		_shield_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_gear.add_child(_shield_visual)


func _gear_box(node_name: String, at: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.75
	mesh.material_override = material
	mesh.position = at
	_gear.add_child(mesh)

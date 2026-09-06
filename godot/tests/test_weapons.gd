extends SceneTree

# Run with: godot --headless --path godot --script res://tests/test_weapons.gd
const PlayerScript = preload("res://scripts/player.gd")
const GameData = preload("res://data/game_data.gd")
const InventoryScript = preload("res://scripts/inventory.gd")
const LootData = preload("res://data/loot_data.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const EnemyData = preload("res://data/enemy_data.gd")
const CompanionScript = preload("res://scripts/companion.gd")


class FakeGame:
	extends Node

	var running: bool = true
	var paused: bool = false
	var coins: int = 1000000
	var round_number: int = 1
	var notifications: Array[String] = []
	var shots: int = 0
	var audio: Node = null
	var inventory: Object = null
	var modifiers: Dictionary = {}
	var damage_taken: float = 0.0
	var damage_events: Array[Dictionary] = []
	var deaths: int = 0
	var shot_results: Array[Dictionary] = []
	var enemies: Array[Node3D] = []
	var companion: Object = null
	var settings: Object = null
	var player: Node = null

	func get_player_modifiers() -> Dictionary:
		return modifiers.duplicate(true)

	func notify(message: String) -> void:
		notifications.append(message)

	func on_player_damaged(amount: float, source_world: Vector3 = Vector3.INF, absorbed: bool = false) -> void:
		if not absorbed:
			damage_taken += amount
		damage_events.append({"amount": amount, "source": source_world, "absorbed": absorbed})

	func on_player_died() -> void:
		deaths += 1

	func on_shot(stats: Dictionary, origin: Vector3, point: Vector3, hit_enemy: bool, headshot: bool) -> void:
		shots += 1
		shot_results.append({"stats": stats.duplicate(true), "origin": origin, "point": point, "hit_enemy": hit_enemy, "headshot": headshot})


class DummyEnemy:
	extends Node3D

	var dead: bool = false
	var hits: int = 0
	var last_zone: String = ""
	var last_source: String = ""
	var total_damage: float = 0.0
	var remaining_health: float = 10000000.0
	var statuses: Array[Dictionary] = []
	var game: FakeGame = null

	func apply_status(id: String, power: float, duration: float) -> void:
		statuses.append({"id": id, "power": power, "duration": duration})

	func take_damage(amount: float, zone: String, source: String) -> float:
		if dead:
			return 0.0
		hits += 1
		last_zone = zone
		last_source = source
		var actual: float = minf(amount, remaining_health)
		total_damage += actual
		remaining_health -= actual
		if remaining_health <= 0.0:
			dead = true
			if game != null and is_instance_valid(game.player):
				game.player.on_enemy_killed(self, source)
		return actual


class FakeSettings:
	extends RefCounted
	var data: Dictionary = {}


class Guardian:
	extends RefCounted
	var shield: float = 30.0
	func absorb_damage(amount: float) -> float:
		var absorbed: float = minf(shield, amount)
		shield -= absorbed
		return amount - absorbed


class DamageSource:
	extends Node3D
	var kind: String = "grunt"
	var boss_id: String = ""


var _checks: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_initial_loadout()
	_test_tactical_reload()
	_test_finite_reserve_and_reload_rejections()
	_test_switch_cancels_reload_and_preserves_ammo()
	_test_weapon_purchase_gates()
	_test_repeatable_damage_upgrades()
	_test_refill_transactions()
	_test_combat_action_gates()
	await _test_firing_cadence_and_reload()
	await _test_ads_reticle_and_dead_target()
	await _test_wall_obstruction()
	await _test_muzzle_obstruction()
	await _test_gate_shots_and_physical_obstruction()
	_test_inventory_instances_and_snapshot()
	_test_player_perks_and_guardian()
	_test_normal_enemy_damage_cap_and_feedback()
	await _test_native_families_and_attachments()
	await _test_native_pellets_crit_and_powerups()
	await _test_native_penetration()
	await _test_status_and_proximity_modifiers()
	await _test_trigger_and_kill_modifiers()
	await _test_visual_settings_and_flashlight()
	await _test_fov_initialization_pause_and_ads()
	await _test_combat_snapshot_resume()
	_finish()


func _new_player(game: FakeGame) -> PlayerScript:
	var player: PlayerScript = PlayerScript.new()
	player.setup(game)
	return player


func _dispose(player: PlayerScript, game: FakeGame) -> void:
	player.free()
	game.free()


func _set_ammo(player: PlayerScript, magazine: int, reserve: int) -> void:
	player.magazine = magazine
	player.reserve = reserve


func _expect_ammo(player: PlayerScript, magazine: int, reserve: int, context: String) -> void:
	var ammo: Dictionary = player.get_ammo()
	_check(int(ammo.magazine) == magazine, "%s: magazine should be %d, got %s" % [context, magazine, ammo.magazine])
	_check(int(ammo.reserve) == reserve, "%s: reserve should be %d, got %s" % [context, reserve, ammo.reserve])


func _test_initial_loadout() -> void:
	var game: FakeGame = FakeGame.new()
	var player: PlayerScript = _new_player(game)
	var stats: Dictionary = player.get_weapon_stats()
	_check(String(stats.id) == "biscuit", "The starter weapon must be equipped")
	_expect_ammo(player, int(GameData.WEAPONS.biscuit.magazine_size), int(GameData.WEAPONS.biscuit.reserve_ammo), "Initial loadout")
	_check(not player.equip_weapon("hammer"), "An unowned weapon cannot be equipped")
	_check(not player.equip_weapon("missing-weapon"), "An unknown weapon cannot be equipped")
	_dispose(player, game)


func _test_tactical_reload() -> void:
	var game: FakeGame = FakeGame.new()
	var player: PlayerScript = _new_player(game)
	var stats: Dictionary = player.get_weapon_stats()
	var capacity: int = int(stats.magazine_size)
	var duration: float = float(stats.reload_time)
	_set_ammo(player, capacity - 4, 7)
	_check(player.start_reload(), "A partial magazine with reserve can reload")
	_expect_ammo(player, capacity - 4, 7, "Starting a reload transfers no ammunition")
	_check(not player.start_reload(), "A reload cannot be restarted while already reloading")
	player._tick_weapon(duration * 0.25)
	_expect_ammo(player, capacity - 4, 7, "An unfinished reload transfers no ammunition")
	_check(not player.shoot(), "Firing is blocked during reload")
	player._tick_weapon(duration + 1.0)
	_expect_ammo(player, capacity, 3, "Tactical reload transfers exactly four reserve rounds")
	player._tick_weapon(20.0)
	_expect_ammo(player, capacity, 3, "A completed reload cannot transfer twice")
	_dispose(player, game)


func _test_finite_reserve_and_reload_rejections() -> void:
	var game: FakeGame = FakeGame.new()
	var player: PlayerScript = _new_player(game)
	var capacity: int = int(player.get_weapon_stats().magazine_size)
	_set_ammo(player, capacity, 9)
	_check(not player.start_reload(), "A full magazine cannot reload")
	_expect_ammo(player, capacity, 9, "Rejected full-magazine reload")
	_set_ammo(player, 0, 3)
	_check(player.start_reload(), "An empty magazine can reload from a short reserve")
	player._tick_weapon(20.0)
	_expect_ammo(player, 3, 0, "Reloading with three reserve rounds supplies only three rounds")
	_check(not player.start_reload(), "An empty reserve cannot start a reload")
	player._tick_weapon(20.0)
	_expect_ammo(player, 3, 0, "Rejected empty-reserve reload creates no ammunition")
	_dispose(player, game)


func _test_switch_cancels_reload_and_preserves_ammo() -> void:
	var game: FakeGame = FakeGame.new()
	game.round_number = 4
	var player: PlayerScript = _new_player(game)
	_check(player.buy_weapon("boardwalk"), "The second weapon can be purchased for the switch test")
	_check(player.equip_weapon("boardwalk"), "An owned second weapon can be equipped")
	player._tick_weapon(20.0)
	_set_ammo(player, 7, 19)
	_check(player.equip_weapon("biscuit"), "The starter can be re-equipped")
	player._tick_weapon(20.0)
	_set_ammo(player, 2, 11)
	_check(player.start_reload(), "The starter begins its reload before switching")
	player._tick_weapon(float(player.get_weapon_stats().reload_time) * 0.25)
	_check(player.equip_weapon("boardwalk"), "Switching to an owned weapon succeeds during reload")
	player._tick_weapon(20.0)
	_expect_ammo(player, 7, 19, "Switching retains the second weapon's own ammunition")
	_check(player.equip_weapon("biscuit"), "Switching back succeeds")
	player._tick_weapon(20.0)
	_expect_ammo(player, 2, 11, "The canceled reload does not complete in the background")
	_check(player.start_reload(), "A canceled reload can be started again")
	player._tick_weapon(20.0)
	_expect_ammo(player, 12, 1, "The restarted reload uses only the starter's reserve")
	_dispose(player, game)


func _test_weapon_purchase_gates() -> void:
	var game: FakeGame = FakeGame.new()
	var player: PlayerScript = _new_player(game)
	var price: int = int(GameData.WEAPONS.boardwalk.price)
	var balance: int = game.coins
	_check(not player.buy_weapon("boardwalk"), "A weapon locked by round cannot be purchased")
	_check(game.coins == balance, "A round-locked purchase spends no coins")
	_check(not player.equip_weapon("boardwalk"), "A rejected purchase does not grant ownership")
	game.round_number = int(GameData.WEAPONS.boardwalk.unlock_round)
	game.coins = price - 1
	_check(not player.buy_weapon("boardwalk"), "One coin below the price is insufficient")
	_check(game.coins == price - 1, "An unaffordable purchase spends no coins")
	game.coins = price
	_check(player.buy_weapon("boardwalk"), "The unlock round and exact price permit purchase")
	_check(game.coins == 0, "A successful purchase charges exactly the listed price")
	game.coins = 10000
	_check(not player.buy_weapon("boardwalk"), "An owned weapon cannot be purchased twice")
	_check(game.coins == 10000, "A duplicate purchase spends no coins")
	_check(not player.buy_weapon("missing-weapon"), "An unknown weapon purchase is rejected")
	_check(game.coins == 10000, "An unknown weapon purchase spends no coins")
	_check(player.equip_weapon("boardwalk"), "The successful purchase grants ownership")
	_dispose(player, game)


func _test_repeatable_damage_upgrades() -> void:
	var game: FakeGame = FakeGame.new()
	game.round_number = 4
	var player: PlayerScript = _new_player(game)
	var original_damage: float = float(player.get_weapon_stats().damage)
	var previous_damage: float = original_damage
	var previous_cost: int = player.get_upgrade_cost()
	var initial_cost: int = previous_cost
	_check(previous_cost > 0, "The initial damage upgrade has a positive price")
	for level: int in range(24):
		var balance: int = game.coins
		_check(player.upgrade_damage(), "Damage upgrade %d remains purchasable" % (level + 1))
		var damage: float = float(player.get_weapon_stats().damage)
		var next_cost: int = player.get_upgrade_cost()
		_check(game.coins == balance - previous_cost, "Damage upgrade %d charges its displayed price" % (level + 1))
		_check(damage > previous_damage, "Damage upgrade %d increases damage" % (level + 1))
		_check(damage - previous_damage <= original_damage * 0.2, "Damage upgrade %d keeps the damage increment small" % (level + 1))
		_check(next_cost > previous_cost, "Damage upgrade %d increases the next price" % (level + 1))
		previous_damage = damage
		previous_cost = next_cost
	var saved_damage: float = previous_damage
	var saved_cost: int = previous_cost
	game.coins = saved_cost - 1
	_check(not player.upgrade_damage(), "Insufficient funds reject the next damage upgrade")
	_check(game.coins == saved_cost - 1, "Rejected damage upgrade spends no coins")
	_check(is_equal_approx(float(player.get_weapon_stats().damage), saved_damage), "Rejected damage upgrade leaves damage unchanged")
	_check(player.get_upgrade_cost() == saved_cost, "Rejected damage upgrade leaves its level unchanged")
	game.coins = 1000000
	_check(player.buy_weapon("boardwalk"), "The second weapon can be bought after repeated upgrades")
	_check(player.equip_weapon("boardwalk"), "The second weapon can be equipped after repeated upgrades")
	_check(is_equal_approx(float(player.get_weapon_stats().damage), float(GameData.WEAPONS.boardwalk.damage)), "The second weapon does not inherit starter damage upgrades")
	_check(player.get_upgrade_cost() == initial_cost, "The second weapon starts at its own first upgrade price")
	_check(player.upgrade_damage(), "The second weapon can receive its own upgrade")
	_check(player.equip_weapon("biscuit"), "The upgraded starter can be re-equipped")
	_check(is_equal_approx(float(player.get_weapon_stats().damage), saved_damage), "Damage upgrades persist on the original weapon")
	_check(player.get_upgrade_cost() == saved_cost, "The original weapon's upgrade price persists")
	_dispose(player, game)


func _test_refill_transactions() -> void:
	var game: FakeGame = FakeGame.new()
	var player: PlayerScript = _new_player(game)
	var stats: Dictionary = player.get_weapon_stats()
	_set_ammo(player, 2, 0)
	var price: int = player.get_refill_cost()
	_check(price > 0, "Refilling ammunition has a positive price")
	game.coins = price - 1
	_check(not player.refill(), "Insufficient funds reject an ammunition refill")
	_check(game.coins == price - 1, "A rejected refill spends no coins")
	_expect_ammo(player, 2, 0, "A rejected refill changes no ammunition")
	game.coins = price
	_check(player.refill(), "The exact refill price buys ammunition")
	_check(game.coins == 0, "A refill charges exactly the displayed price")
	_expect_ammo(player, int(stats.magazine_size), int(stats.max_reserve), "A purchased refill restores the weapon to capacity")
	game.coins = 10000
	_check(not player.refill(), "A full weapon cannot buy an unnecessary refill")
	_check(game.coins == 10000, "A full-ammunition refill attempt spends no coins")
	_dispose(player, game)


func _test_combat_action_gates() -> void:
	var game: FakeGame = FakeGame.new()
	var player: PlayerScript = _new_player(game)
	_set_ammo(player, 2, 9)
	game.paused = true
	_check(not player.shoot(), "Shooting is blocked while paused")
	_check(not player.start_reload(), "Reloading is blocked while paused")
	_expect_ammo(player, 2, 9, "Paused action attempts preserve ammunition")
	game.paused = false
	game.running = false
	_check(not player.shoot(), "Shooting is blocked when the run is inactive")
	_check(not player.start_reload(), "Reloading is blocked when the run is inactive")
	_expect_ammo(player, 2, 9, "Inactive action attempts preserve ammunition")
	game.running = true
	_set_ammo(player, 0, 0)
	_check(not player.shoot(), "An empty weapon cannot fire")
	_expect_ammo(player, 0, 0, "An empty trigger pull creates no ammunition")
	_dispose(player, game)


func _test_firing_cadence_and_reload() -> void:
	var game: FakeGame = FakeGame.new()
	var player: PlayerScript = _new_player(game)
	root.add_child(player)
	player.set_physics_process(false)
	await physics_frame
	var interval: float = 1.0 / float(player.get_weapon_stats().fire_rate)
	_set_ammo(player, 3, 2)
	_check(player.shoot(), "A ready weapon fires into the real physics world")
	_expect_ammo(player, 2, 2, "One shot consumes exactly one magazine round")
	_check(game.shots == 1, "One valid shot emits one game callback")
	_check(not player.shoot(), "The fire cooldown rejects an immediate second shot")
	player._tick_weapon(interval * 0.5)
	_check(not player.shoot(), "The weapon cannot fire before its cadence interval expires")
	_expect_ammo(player, 2, 2, "Rejected cooldown shots consume no ammunition")
	_check(game.shots == 1, "Rejected cooldown shots emit no game callbacks")
	player._tick_weapon(interval)
	_check(player.shoot(), "The weapon fires again after its cadence interval")
	_expect_ammo(player, 1, 2, "A second valid shot consumes one further round")
	player._tick_weapon(interval)
	_check(player.shoot(), "The final magazine round can be fired")
	_expect_ammo(player, 0, 2, "The final shot preserves the finite reserve")
	_check(player.reloading, "An empty magazine with reserve automatically begins reloading")
	_check(not player.shoot(), "Automatic reload blocks further shots")
	player._tick_weapon(20.0)
	_expect_ammo(player, 2, 0, "Automatic reload transfers only the two available reserve rounds")
	_check(game.shots == 3, "Only the three successful shots emit callbacks")
	_dispose(player, game)


func _target_at(position: Vector3, zone: String = "head", size: Vector3 = Vector3(0.18, 0.18, 0.18)) -> DummyEnemy:
	var enemy: DummyEnemy = DummyEnemy.new()
	enemy.position = position
	var area: Area3D = Area3D.new()
	area.collision_layer = 8
	area.collision_mask = 0
	area.set_meta("enemy", enemy)
	area.set_meta("zone", zone)
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	area.add_child(collision)
	enemy.add_child(area)
	root.add_child(enemy)
	return enemy


func _wall_at(position: Vector3, size: Vector3, layer: int = 1) -> StaticBody3D:
	var wall: StaticBody3D = StaticBody3D.new()
	wall.position = position
	wall.collision_layer = layer
	wall.collision_mask = 0
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	wall.add_child(collision)
	root.add_child(wall)
	return wall


func _test_ads_reticle_and_dead_target() -> void:
	var game: FakeGame = FakeGame.new()
	var player: PlayerScript = _new_player(game)
	root.add_child(player)
	player.set_physics_process(false)
	player.rotation.y = 0.38
	player.aiming = true
	player._update_view(0.5, 0.0)
	var origin: Vector3 = player.camera.global_position
	var direction: Vector3 = -player.camera.global_transform.basis.z.normalized()
	var enemy: DummyEnemy = _target_at(origin + direction * 12.0)
	await physics_frame
	await process_frame
	_check(player.shoot(), "An ADS shot fires at the reticle-centered target")
	_check(enemy.hits == 1, "ADS hits a small target centered on the rotated camera's reticle")
	_check(enemy.last_zone == "head", "A head hitbox sends the head region to damage resolution")
	_check(enemy.last_source == "player", "The damage source identifies the player")
	var live_result: Dictionary = game.shot_results.back()
	_check(bool(live_result.hit_enemy), "A live target taking damage reports an enemy hit")
	_check(bool(live_result.headshot), "A live target taking head damage reports a headshot")
	enemy.dead = true
	player._tick_weapon(20.0)
	_check(player.shoot(), "Shooting at a lingering corpse still consumes a shot")
	_check(enemy.hits == 1, "A dead target accepts no additional damage")
	var dead_result: Dictionary = game.shot_results.back()
	_check(not bool(dead_result.hit_enemy), "A corpse returning zero damage does not report an enemy hit")
	_check(not bool(dead_result.headshot), "A corpse returning zero damage does not report a headshot")
	enemy.free()
	_dispose(player, game)


func _test_wall_obstruction() -> void:
	var game: FakeGame = FakeGame.new()
	var player: PlayerScript = _new_player(game)
	root.add_child(player)
	player.set_physics_process(false)
	var origin: Vector3 = player.camera.global_position
	var enemy: DummyEnemy = _target_at(origin + Vector3(0.0, 0.0, -12.0))
	var wall: StaticBody3D = _wall_at(origin + Vector3(0.0, 0.0, -4.0), Vector3(3.0, 3.0, 0.2))
	await physics_frame
	await process_frame
	_check(player.shoot(), "A shot facing a wall still consumes ammunition")
	_check(enemy.hits == 0, "A world wall blocks damage to the enemy behind it")
	var result: Dictionary = game.shot_results.back()
	_check(not bool(result.hit_enemy), "A shot blocked by a wall reports no enemy hit")
	var endpoint: Vector3 = result.point
	_check(origin.distance_to(endpoint) < 5.0, "The shot endpoint stops at the intervening wall")
	wall.free()
	enemy.free()
	_dispose(player, game)


func _test_muzzle_obstruction() -> void:
	var game: FakeGame = FakeGame.new()
	var player: PlayerScript = _new_player(game)
	root.add_child(player)
	player.set_physics_process(false)
	var origin: Vector3 = player.camera.global_position
	var target_point: Vector3 = origin + Vector3(0.0, 0.0, -12.0)
	var enemy: DummyEnemy = _target_at(target_point)
	var muzzle: Vector3 = player.weapon_view.call("get_muzzle_position")
	var wall: StaticBody3D = _wall_at(muzzle.lerp(target_point, 0.10), Vector3(0.1, 0.1, 0.1))
	await physics_frame
	await process_frame
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, target_point, 1 | 8, [player.get_rid()])
	query.collide_with_areas = true
	var sightline: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	_check(not sightline.is_empty() and sightline.get("collider") is Area3D, "The reticle has a clear sightline while the barrel is obstructed")
	_check(player.shoot(), "An obstructed barrel still fires a round")
	_check(enemy.hits == 0, "A barrel obstruction blocks a target visible through the reticle")
	var result: Dictionary = game.shot_results.back()
	_check(not bool(result.hit_enemy), "A barrel obstruction reports no enemy hit")
	var endpoint: Vector3 = result.point
	_check(muzzle.distance_to(endpoint) < 2.0, "The trace stops at the obstacle directly ahead of the barrel")
	wall.free()
	enemy.free()
	_dispose(player, game)


func _test_gate_shots_and_physical_obstruction() -> void:
	var game: FakeGame = FakeGame.new()
	var player: PlayerScript = _new_player(game)
	root.add_child(player)
	player.set_physics_process(false)
	_neutral_aim(player)
	var origin: Vector3 = player.camera.global_position
	var target: Vector3 = origin + Vector3(0, 0, -12)
	var enemy: DummyEnemy = _target_at(target)
	var gate: StaticBody3D = _wall_at(origin + Vector3(0, 0, -4), Vector3(3, 3, 0.2), 32)
	gate.name = "ClosedMovementGate"
	await physics_frame
	_check(player.test_move(player.global_transform, Vector3(0, 0, -5)), "A closed gate still physically blocks player movement")
	_check(player.shoot() and enemy.hits == 1, "An ADS shot crosses a closed gate and damages the enemy behind it")
	_check(bool(game.shot_results.back().hit_enemy) and bool(game.shot_results.back().headshot), "A hit through a gate retains actual head-hit feedback")
	_check(origin.distance_to(game.shot_results.back().point) > 10.0, "A closed gate does not truncate the shot endpoint")
	var wall: StaticBody3D = _wall_at(origin + Vector3(0, 0, -7), Vector3(3, 3, 0.2))
	await physics_frame
	_neutral_aim(player)
	_check(player.shoot() and enemy.hits == 1, "A solid wall beyond a pass-through gate still blocks damage")
	_check(origin.distance_to(game.shot_results.back().point) < 8.0, "The shot stops at the solid wall beyond the gate")
	wall.free()
	gate.free()
	_neutral_aim(player)
	var muzzle: Vector3 = player.weapon_view.call("get_muzzle_position")
	var contact: StaticBody3D = _wall_at(muzzle, Vector3(0.07, 0.07, 0.07), 32)
	await physics_frame
	_check(player.shoot() and enemy.hits == 2, "A muzzle touching the gate can still shoot through it")
	_neutral_aim(player)
	contact.position = player.weapon_view.call("get_muzzle_position")
	contact.collision_layer = 1
	await physics_frame
	var sight: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, target, 1 | 8, [player.get_rid()])
	sight.collide_with_areas = true
	var visible_target: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(sight)
	_check(visible_target.get("collider") is Area3D, "The reticle remains clear when a small solid wall encloses only the muzzle")
	_check(player.shoot() and enemy.hits == 2, "A muzzle already inside solid geometry cannot shoot through the wall")
	_check(not bool(game.shot_results.back().hit_enemy), "Solid muzzle contact reports an obstruction instead of a false hit")
	contact.free()
	var rear_gate: StaticBody3D = _wall_at(origin + Vector3(0, 0, 1.4), Vector3(4, 4, 0.2), 32)
	await physics_frame
	player.third_person = true
	player._sync_perspective()
	player._update_view(0.5, 0.0)
	_check(player.camera.global_position.z < 1.3, "The third-person camera retracts in front of a closed physical gate")
	rear_gate.free()
	enemy.free()
	_dispose(player, game)


func _native_game(model_id: String = "biscuit") -> FakeGame:
	var game: FakeGame = FakeGame.new()
	var inventory: InventoryScript = InventoryScript.new()
	inventory.create_starter()
	game.inventory = inventory
	game.modifiers = {"crit_chance": -1.0}
	if model_id != "biscuit":
		var item: Dictionary = LootData.make_weapon(model_id, 1, "common", 482)
		item["manufacturer"] = "independent"
		item["rolls"] = {}
		item["modifiers"] = []
		item["attachments"] = {}
		inventory.add_item(item)
		inventory.equip(str(item["uid"]))
	return game


func _native_player(game: FakeGame) -> PlayerScript:
	var player: PlayerScript = _new_player(game)
	root.add_child(player)
	player.set_physics_process(false)
	game.player = player
	player.aiming = true
	player.fire_cooldown = 0.0
	player._update_view(0.5, 0.0)
	return player


func _neutral_aim(player: PlayerScript) -> void:
	player._pitch = 0.0
	player._camera_recoil = 0.0
	player.aiming = true
	player.fire_cooldown = 0.0
	player.reloading = false
	player._update_view(0.5, 0.0)


func _set_native_mods(game: FakeGame, player: PlayerScript, ids: Array) -> void:
	var item: Dictionary = game.inventory.equipped()
	item["modifiers"] = ids.duplicate()
	item["element"] = "none"
	player.sync_inventory()
	_neutral_aim(player)


func _test_inventory_instances_and_snapshot() -> void:
	var game: FakeGame = _native_game()
	var player: PlayerScript = _new_player(game)
	var first_uid: String = player.active_item_uid
	var twin: Dictionary = LootData.starter_weapon()
	twin["uid"] = "second-biscuit"
	twin["magazine"] = 3
	twin["reserve"] = 7
	_check(game.inventory.add_item(twin), "A second instance of the same model enters the real inventory")
	_set_ammo(player, 4, 11)
	_check(player.equip_weapon("second-biscuit"), "An instance UID selects the second pistol")
	_expect_ammo(player, 3, 7, "Each instance has its own ammunition")
	player.magazine = 1
	player.reserve = 6
	_check(player.equip_weapon(first_uid), "The original instance can be selected again")
	_expect_ammo(player, 4, 11, "Original instance ammunition survives a same-model switch")
	_check(int(game.inventory.find_item("second-biscuit").magazine) == 1, "Leaving the second pistol saves its magazine")
	player.magazine = 2
	player._save_ammo()
	game.inventory.equipped()["magazine"] = 8
	game.inventory.equipped()["reserve"] = 19
	player.sync_inventory()
	_expect_ammo(player, 8, 19, "External bench/refill mutations are read without stale overwrites")
	player.health = 63.5
	player.position = Vector3(2.0, 3.0, -7.0)
	player.rotation.y = 0.5
	player._pitch = -0.2
	player.flashlight_on = true
	var saved: Dictionary = player.snapshot()
	var inventory_saved: Dictionary = game.inventory.export_state()
	var restored_game: FakeGame = _native_game()
	_check(restored_game.inventory.import_state(inventory_saved), "Inventory state validates before restoring the player")
	var restored: PlayerScript = _new_player(restored_game)
	_check(restored.restore(saved), "A native player snapshot restores successfully")
	_check(is_equal_approx(restored.health, 63.5) and restored.position.is_equal_approx(player.position), "Snapshot restores health and world position")
	_check(restored.active_item_uid == first_uid and restored.flashlight_on, "Snapshot restores item identity and flashlight state")
	_expect_ammo(restored, 8, 19, "Snapshot restores the active magazine and reserve")
	_check(int(restored_game.inventory.find_item("second-biscuit").magazine) == 1, "Snapshot keeps the other same-model instance's ammo")
	var excessive: Dictionary = saved.duplicate(true)
	excessive["magazine"] = 99999
	excessive["reserve"] = 99999
	excessive["health"] = 99999.0
	_check(restored.restore(excessive), "Finite over-cap values are clamped during player restoration")
	_expect_ammo(restored, 12, 96, "Restoration cannot exceed weapon ammunition capacities")
	_check(is_equal_approx(restored.health, 100.0), "Restoration cannot exceed maximum health")
	var invalid: Dictionary = saved.duplicate(true)
	invalid["position"] = [NAN, 0.0, 0.0]
	_check(not restored.restore(invalid), "A non-finite position is rejected")
	_dispose(restored, restored_game)
	_dispose(player, game)


func _test_player_perks_and_guardian() -> void:
	var game: FakeGame = _native_game()
	var player: PlayerScript = _new_player(game)
	var base: Dictionary = game.inventory.stats()
	game.modifiers = {"damage": 2.0, "fire_rate": 1.5, "reload": 2.0, "ammo_capacity": 1.5, "crit_chance": 0.1, "crit_multiplier": 1.2, "resistance": 0.25}
	var stats: Dictionary = player.get_weapon_stats()
	_check(is_equal_approx(float(stats.damage), float(base.damage) * 2.0), "Damage perks multiply real inventory stats")
	_check(is_equal_approx(float(stats.fire_rate), float(base.fire_rate) * 1.5), "Fire-rate powerups multiply real inventory stats")
	_check(is_equal_approx(float(stats.reload_time), float(base.reload_time) / 2.0), "A reload speed bonus shortens reload time")
	_check(int(stats.max_reserve) == int(base.max_reserve) * 1.5, "Ammo capacity perks increase reserve capacity")
	_check(is_equal_approx(float(stats.critical_chance), float(base.critical_chance) + 0.1), "Crit chance perks are added once")
	player.magazine = 4
	_check(player.start_reload(), "A perk-modified tactical reload starts")
	_check(is_equal_approx(player.reload_duration, float(base.reload_time) / 2.0), "Reload timer uses the perk-modified time")
	player.reloading = false
	player.magazine = 0
	player.start_reload()
	_check(is_equal_approx(player.reload_duration, float(base.reload_time) / 2.0 * float(stats.reload_empty_multiplier)), "Empty reload keeps its extra chambering time")
	game.companion = Guardian.new()
	player.take_damage(80.0)
	_check(is_equal_approx(player.health, 70.0), "Resistance applies before the finite dog shield")
	player.damage_cooldown = 0.0
	player.health = 100.0
	game.modifiers = {}
	game.companion.shield = 30.0
	player.take_damage(200.0)
	_check(player.health == 0.0 and player._dead, "A lethal hit is not clipped before shield absorption")
	player.revive_from_companion(40.0)
	_check(is_equal_approx(player.health, 40.0) and not player._dead and player.damage_cooldown > 0.0, "Dog revival restores health and a brief grace period")
	_dispose(player, game)


func _reset_damage_target(player: PlayerScript, maximum: float = 100.0) -> void:
	player.max_health = maximum
	player.health = maximum
	player._dead = false
	player.damage_cooldown = 0.0
	player.dash_remaining = 0.0


func _test_normal_enemy_damage_cap_and_feedback() -> void:
	var game: FakeGame = FakeGame.new()
	var player: PlayerScript = _new_player(game)
	var source: DamageSource = DamageSource.new()
	source.add_to_group("meyui_enemies")
	root.add_child(source)
	source.position = Vector3(-6, 1, 4)
	# Real enemy configurations supply scaled attack values; the final cap must
	# survive every normal archetype, difficulty and extreme round/health pairing.
	for kind: String in EnemyData.ARCHETYPES:
		if kind == "boss":
			continue
		for round_index: int in [1, 50, 1000000]:
			for difficulty_id: String in GameData.DIFFICULTIES:
				var enemy: EnemyScript = EnemyScript.new()
				var difficulty: Dictionary = GameData.DIFFICULTIES[difficulty_id]
				enemy.setup(game, kind, round_index, float(difficulty.health))
				enemy.configure_difficulty(float(difficulty.damage), float(difficulty.speed))
				enemy.configure_elite("fire")
				source.kind = kind
				for maximum: float in [10.0, 100.0, 350.0]:
					_reset_damage_target(player, maximum)
					var incoming: float = enemy._damage
					player.take_damage(incoming, source)
					var actual: float = maximum - player.health
					_check(actual <= maximum * 0.4 + 0.00001 and actual > 0.0, "Normal %s round %d %s never exceeds 40%% of %.0f max HP" % [kind, round_index, difficulty_id, maximum])
				enemy.free()
	source.kind = "grunt"
	game.modifiers = {}
	for maximum: float in [1.0, 100.0, 10000.0]:
		_reset_damage_target(player, maximum)
		player.take_damage(1e12, source)
		_check(is_equal_approx(player.health, maximum * 0.6), "Even an extreme normal hit is capped against maximum health")
		player.damage_cooldown = 0.0
		player.take_damage(1e12, source)
		_check(is_equal_approx(player.health, maximum * 0.2), "The hit cap uses maximum HP rather than shrinking with current health")
		player.damage_cooldown = 0.0
		player.take_damage(1e12, source)
		_check(player.health == 0.0 and player._dead, "Three capped undefended hits remain lethal without an artificial health floor")
	_reset_damage_target(player)
	game.modifiers = {"resistance": 0.25}
	player.take_damage(1e12, source)
	_check(is_equal_approx(player.health, 70.0), "Resistance still reduces an extreme normal hit below the 40-percent cap")
	var event: Dictionary = game.damage_events.back()
	_check(is_equal_approx(event.amount, 30.0) and not event.absorbed and event.source.is_equal_approx(source.global_position), "Damage feedback carries actual health loss and the attacker's world position")
	_check(player.damage_cooldown <= 0.3, "Regular hits use a brief grace period instead of long invulnerability")
	var event_count: int = game.damage_events.size()
	player.take_damage(1e12, source)
	_check(is_equal_approx(player.health, 70.0) and game.damage_events.size() == event_count, "Same-impact hits inside the grace period do not duplicate damage or feedback")
	player.damage_cooldown = 0.0
	player.dash_remaining = 0.1
	player.take_damage(1e12, source)
	_check(is_equal_approx(player.health, 70.0), "A real dash still protects against the incoming hit")
	_reset_damage_target(player)
	game.modifiers = {"resistance": 100.0}
	player.take_damage(1e12, source)
	_check(is_equal_approx(player.health, 92.0), "Even excessive resistance remains useful but is bounded to 80-percent mitigation")
	_reset_damage_target(player)
	game.modifiers = {"resistance": -5.0}
	player.take_damage(1e12, source)
	_check(is_equal_approx(player.health, 60.0), "Invalid negative resistance cannot amplify a normal hit above its cap")
	_reset_damage_target(player)
	game.modifiers = {"resistance": 0.25}
	var shield: Guardian = Guardian.new()
	shield.shield = 100.0
	game.companion = shield
	player.take_damage(1e12, source)
	event = game.damage_events.back()
	_check(is_equal_approx(player.health, 100.0) and is_equal_approx(shield.shield, 70.0), "The finite shield absorbs only capped, resistance-adjusted damage")
	_check(event.absorbed and is_equal_approx(event.amount, 30.0) and event.source.is_equal_approx(source.global_position), "A fully shielded hit still provides directional protection feedback")
	_reset_damage_target(player)
	shield.shield = 10.0
	player.take_damage(1e12, source)
	event = game.damage_events.back()
	_check(is_equal_approx(player.health, 80.0) and shield.shield == 0.0 and not event.absorbed and is_equal_approx(event.amount, 20.0), "Partial shield absorption reports only the health that was actually lost")
	game.companion = null
	game.modifiers = {}
	_reset_damage_target(player)
	source.kind = "boss"
	source.boss_id = "captain"
	player.take_damage(65.0, source)
	_check(is_equal_approx(player.health, 35.0), "Explicit bosses retain their separate damage budget")
	_reset_damage_target(player)
	player.take_damage(1000000.0)
	event = game.damage_events.back()
	_check(player._dead and player.health == 0.0 and not event.source.is_finite(), "A source-less lethal fall is not capped or assigned a false attack direction")
	_reset_damage_target(player)
	player.take_damage(NAN, source)
	player.take_damage(INF, source)
	_check(is_equal_approx(player.health, 100.0), "Invalid damage cannot poison player health with a non-finite value")
	# Exercise the actual guardian implementation, including its range restriction.
	root.add_child(player)
	player.set_physics_process(false)
	game.player = player
	var dog: CompanionScript = CompanionScript.new()
	dog.game = game
	root.add_child(dog)
	dog.set_physics_process(false)
	dog.archetype = "guardian"
	dog.shield = 100.0
	dog.position = Vector3(1, 0, 0)
	game.companion = dog
	game.modifiers = {"resistance": 0.25}
	source.kind = "grunt"
	source.boss_id = ""
	player.take_damage(1e12, source)
	_check(is_equal_approx(player.health, 83.5) and is_equal_approx(dog.shield, 86.5), "Native Faro absorbs 45 percent after the normal-hit cap and resistance")
	_reset_damage_target(player)
	dog.position = Vector3(20, 0, 0)
	player.take_damage(1e12, source)
	_check(is_equal_approx(player.health, 70.0) and is_equal_approx(dog.shield, 86.5), "A distant native guardian cannot absorb the capped damage remotely")
	dog.free()
	source.free()
	_dispose(player, game)


func _test_native_families_and_attachments() -> void:
	var game: FakeGame = _native_game()
	var player: PlayerScript = _native_player(game)
	for model_id: String in GameData.WEAPONS:
		var item: Dictionary = LootData.make_weapon(model_id, 1, "common", 4321 + GameData.WEAPONS.keys().find(model_id))
		item["manufacturer"] = "independent"
		item["rolls"] = {}
		item["modifiers"] = []
		item["attachments"] = {}
		_check(game.inventory.add_item(item), "Native model %s can be granted" % model_id)
		_check(player.equip_weapon(str(item.uid)), "Native model %s can be equipped" % model_id)
		var stats: Dictionary = player.get_weapon_stats()
		_check(player.weapon_id == model_id and player.active_item_uid == str(item.uid), "Native model %s keeps its UID" % model_id)
		_check(str(player.weapon_view.family) == str(stats.family), "Native model %s uses its own visual family" % model_id)
		player.weapon_view.call("set_visual_options", 1.0, 1.0, false, 1.0)
		player.weapon_view.call("animate_view", 0.1, true, 1.0, false, 0.7, 0.0, false)
		player.weapon_view.call("animate_view", 0.1, false, 0.0, false, 0.7, 0.5, true)
		player.weapon_view.call("fire", float(stats.recoil), false)
		var muzzle: Vector3 = player.weapon_view.call("get_muzzle_position")
		_check(muzzle.is_finite(), "Native model %s has a finite muzzle transform" % model_id)
	_check(player.equip_weapon("starter-biscuit"), "Attachments are tested on the real starter instance")
	for attachment_id: String in LootData.ATTACHMENTS:
		var config: Dictionary = LootData.ATTACHMENTS[attachment_id]
		var part: Dictionary = {"uid": "test-part-" + attachment_id, "id": attachment_id, "slot": str(config.slot), "rarity": "common", "roll": 1.0}
		_check(game.inventory.add_attachment(part), "Attachment %s enters the real inventory" % attachment_id)
		player._save_ammo()
		_check(game.inventory.install(player.active_item_uid, str(part.uid)), "Attachment %s installs into its actual slot" % attachment_id)
		player.sync_inventory()
		var stats: Dictionary = player.get_weapon_stats()
		_check(str(stats.attachments[config.slot].id) == attachment_id, "Attachment %s reaches combat/viewmodel stats" % attachment_id)
		_check(player.magazine <= int(stats.magazine_size) and player.reserve <= int(stats.max_reserve), "Attachment %s respects revised ammo capacities" % attachment_id)
	await process_frame
	_dispose(player, game)


func _test_native_pellets_crit_and_powerups() -> void:
	var game: FakeGame = _native_game("doorman")
	var player: PlayerScript = _native_player(game)
	var enemy: DummyEnemy = _target_at(player.camera.global_position + Vector3(0, 0, -5), "body", Vector3(4, 4, 0.3))
	await physics_frame
	await process_frame
	var stats: Dictionary = player.get_weapon_stats()
	var before: int = player.magazine
	_check(player.shoot(), "A native shotgun trigger fires")
	_check(enemy.hits == int(stats.pellets), "A shotgun emits all seven separate damage-bearing pellets")
	_check(is_equal_approx(enemy.total_damage, float(stats.damage) * int(stats.pellets)), "Shotgun damage is per pellet, matching inventory DPS")
	_check(player.magazine == before - 1 and game.shots == 1, "Multiple pellets consume one shell and one trigger callback")
	game.modifiers = {"infinite_ammo": true, "crit_chance": -1.0, "fire_rate": 1.8, "overcharge": "shock"}
	player.magazine = 0
	player.reserve = 0
	_neutral_aim(player)
	_check(player.shoot(), "Infinite ammo allows an empty weapon to fire while the powerup is active")
	_expect_ammo(player, 0, 0, "Infinite ammo does not manufacture permanent ammunition")
	_check(str(player.get_weapon_stats().element) == "shock", "Overcharge supplies a functional shock element")
	game.modifiers = {"crit_chance": -1.0}
	_neutral_aim(player)
	_check(not player.shoot(), "An empty gun stops firing when infinite ammo expires")
	enemy.free()
	_dispose(player, game)
	game = _native_game("lookout")
	player = _native_player(game)
	enemy = _target_at(player.camera.global_position + Vector3(0, 0, -10), "head")
	await physics_frame
	await process_frame
	stats = player.get_weapon_stats()
	_check(player.shoot(), "A native sniper ADS ray hits a small head hitbox")
	_check(is_equal_approx(enemy.total_damage, float(stats.damage) * float(stats.critical_multiplier) / 1.75), "Sniper critical multiplier improves head damage before the actor's universal head factor")
	game.modifiers = {"crit_chance": 1.0}
	_neutral_aim(player)
	var previous: float = enemy.total_damage
	_check(player.shoot(), "A guaranteed critical sniper shot fires")
	_check(bool(game.shot_results.back().stats.critical), "Guaranteed critical hits are reported in the shot callback")
	_check(is_equal_approx(enemy.total_damage - previous, float(stats.damage) * pow(float(stats.critical_multiplier), 2.0) / 1.75), "Random critical damage and head-region scaling are applied once each")
	enemy.free()
	_dispose(player, game)


func _test_native_penetration() -> void:
	var game: FakeGame = _native_game()
	var player: PlayerScript = _native_player(game)
	_set_native_mods(game, player, ["pierce"])
	var origin: Vector3 = player.camera.global_position
	var first: DummyEnemy = _target_at(origin + Vector3(0, 0, -4), "body", Vector3(1, 1, 0.4))
	var second: DummyEnemy = _target_at(origin + Vector3(0, 0, -7), "body", Vector3(1, 1, 0.4))
	var extra_area: Area3D = first.get_child(0).duplicate() as Area3D
	extra_area.set_meta("enemy", first)
	extra_area.position.z = -0.25
	first.add_child(extra_area)
	await physics_frame
	await process_frame
	_check(player.shoot(), "A penetrating native shot fires")
	_check(first.hits == 1 and second.hits == 1, "Penetration damages each actor once despite multiple zones")
	_check(is_equal_approx(second.total_damage, first.total_damage * 0.76), "The second penetration hit has explicit damage attenuation")
	var wall: StaticBody3D = _wall_at(origin + Vector3(0, 0, -5.5), Vector3(3, 3, 0.25))
	_neutral_aim(player)
	await physics_frame
	await process_frame
	player.shoot()
	_check(first.hits == 2 and second.hits == 1, "Penetration stops at world geometry between enemies")
	wall.free()
	first.free()
	second.free()
	_dispose(player, game)


func _test_status_and_proximity_modifiers() -> void:
	var game: FakeGame = _native_game()
	var player: PlayerScript = _native_player(game)
	var origin: Vector3 = player.camera.global_position + Vector3(0, 0, -3)
	var primary: DummyEnemy = _target_at(origin, "body")
	var near_one: DummyEnemy = _target_at(origin + Vector3(1.4, 0, 0), "body")
	var near_two: DummyEnemy = _target_at(origin + Vector3(-2.0, 0, 0), "body")
	var blocked: DummyEnemy = _target_at(origin + Vector3(0, 0, -2.0), "body")
	var wall: StaticBody3D = _wall_at(origin + Vector3(0, 0, -1), Vector3(0.6, 4, 0.2))
	game.enemies = [primary, near_one, near_two, blocked]
	await physics_frame
	await process_frame
	for entry: Dictionary in [{"mod": "burn", "status": "burn"}, {"mod": "cryo", "status": "cryo"}, {"mod": "shock", "status": "shock"}]:
		var stats: Dictionary = player.get_weapon_stats()
		stats["modifiers"] = [entry.mod]
		primary.statuses.clear()
		player._apply_hit_effects(primary, origin, stats, "body", false)
		_check(primary.statuses.size() == 1 and str(primary.statuses[0].id) == str(entry.status), "Modifier %s applies its actual enemy status" % entry.mod)
		_check(float(primary.statuses[0].power) > 0.0 and float(primary.statuses[0].duration) > 0.0, "Modifier %s carries a positive status strength and duration" % entry.mod)
	for element: String in ["fire", "corrosive", "cryo", "shock"]:
		var stats: Dictionary = player.get_weapon_stats()
		stats["element"] = element
		primary.statuses.clear()
		player._apply_hit_effects(primary, origin, stats, "body", false)
		_check(not primary.statuses.is_empty(), "Element %s applies a runtime status" % element)
	var freeze_stats: Dictionary = player.get_weapon_stats()
	freeze_stats["modifiers"] = ["freeze"]
	primary.statuses.clear()
	for index: int in range(3):
		player._apply_hit_effects(primary, origin, freeze_stats, "body", false)
	_check(primary.statuses.size() == 1 and str(primary.statuses[0].id) == "freeze", "Freeze triggers only after three successive hits")
	for mod_id: String in ["ricochet", "split_shot", "seeker", "shock", "critical_blast"]:
		near_one.hits = 0
		near_two.hits = 0
		blocked.hits = 0
		var stats: Dictionary = player.get_weapon_stats()
		stats["modifiers"] = [mod_id]
		player._apply_hit_effects(primary, origin, stats, "body", true)
		var expected: int = 1 if mod_id in ["ricochet", "seeker"] else 2
		_check(near_one.hits + near_two.hits == expected, "Modifier %s reaches its intended number of nearby targets" % mod_id)
		_check(blocked.hits == 0, "Modifier %s respects walls for secondary damage" % mod_id)
		_check(near_one.last_source == "proc", "Modifier %s marks secondary damage to prevent recursive chains" % mod_id)
	var explosion: Dictionary = player.get_weapon_stats()
	explosion["element"] = "explosive"
	var before_hits: int = near_one.hits
	player._apply_hit_effects(primary, origin, explosion, "body", false)
	_check(near_one.hits == before_hits + 1, "Explosive elemental hits deal real splash damage")
	_set_native_mods(game, player, ["reload_blast"])
	player.magazine = 1
	player.reserve = 4
	before_hits = primary.hits
	_check(player.start_reload(), "Reload-blast modifier starts a finite tactical reload")
	player._tick_weapon(20.0)
	_check(primary.hits == before_hits + 1, "Completing reload-blast damages a nearby enemy")
	_expect_ammo(player, 5, 0, "Reload-blast does not bypass ammunition conservation")
	_check(player._effect_nodes.size() == 12, "Secondary combat effects use a bounded twelve-node pool")
	player._tick_weapon(1.0)
	var visible_effects: int = 0
	for effect: MeshInstance3D in player._effect_nodes:
		if effect.visible:
			visible_effects += 1
	_check(visible_effects == 0, "Expired combat effects disappear without growing the node pool")
	wall.free()
	for enemy: DummyEnemy in [primary, near_one, near_two, blocked]:
		enemy.free()
	_dispose(player, game)


func _test_trigger_and_kill_modifiers() -> void:
	var game: FakeGame = _native_game()
	var player: PlayerScript = _native_player(game)
	var enemy: DummyEnemy = _target_at(player.camera.global_position + Vector3(0, 0, -4), "body", Vector3(2, 2, 0.3))
	var neighbor: DummyEnemy = _target_at(enemy.global_position + Vector3(1.5, 0, 0), "body")
	game.enemies = [enemy, neighbor]
	await physics_frame
	await process_frame
	var base_damage: float = float(player.get_weapon_stats().damage)
	_set_native_mods(game, player, ["third_strike"])
	var damages: Array[float] = []
	for index: int in range(3):
		_neutral_aim(player)
		player.shoot()
		damages.append(float(game.shot_results.back().stats.applied_damage))
	_check(is_equal_approx(damages[0], base_damage) and is_equal_approx(damages[1], base_damage) and is_equal_approx(damages[2], base_damage * 2.0), "Third-strike doubles exactly every third trigger")
	_set_native_mods(game, player, ["last_word"])
	player.magazine = 1
	player.reserve = 0
	player.shoot()
	_check(is_equal_approx(float(game.shot_results.back().stats.applied_damage), base_damage * 4.0), "Last-word quadruples the actual last magazine round")
	_set_native_mods(game, player, ["heat"])
	player.magazine = 12
	player.shoot()
	var first_heat: float = float(game.shot_results.back().stats.applied_damage)
	_neutral_aim(player)
	player.shoot()
	_check(float(game.shot_results.back().stats.applied_damage) > first_heat, "Heat raises damage on consecutive shots")
	_set_native_mods(game, player, ["desperate"])
	player.health = 20.0
	player.shoot()
	_check(is_equal_approx(float(game.shot_results.back().stats.applied_damage), base_damage * 1.56), "Desperate damage scales with missing health")
	_set_native_mods(game, player, ["critical_refund"])
	game.modifiers = {"crit_chance": 1.0}
	player._combat_rng.seed = 917
	var refunded: int = 0
	for index: int in range(40):
		_neutral_aim(player)
		player.magazine = 2
		player.reserve = 0
		player.shoot()
		if player.magazine == 2:
			refunded += 1
	_check(refunded > 0 and refunded < 40, "Critical-refund returns ammunition on some guaranteed critical hits")
	_set_native_mods(game, player, ["double_shot"])
	game.modifiers = {"crit_chance": -1.0}
	player._combat_rng.seed = 819
	var doubled: int = 0
	for index: int in range(40):
		_neutral_aim(player)
		player.magazine = 2
		player.shoot()
		_check(player.magazine == 1, "Double-shot still consumes exactly one magazine round")
		if int(game.shot_results.back().stats.pellets_fired) == 2:
			doubled += 1
	_check(doubled > 0 and doubled < 40, "Double-shot sometimes emits an additional actual ray")
	_set_native_mods(game, player, ["headshot_haste"])
	player._apply_hit_effects(enemy, enemy.global_position, player.get_weapon_stats(), "head", false)
	_check(player._haste_remaining > 0.0, "Headshot-haste activates a temporary movement bonus")
	_set_native_mods(game, player, ["kill_frenzy", "vampiric", "death_blast"])
	player._last_combat_stats = player.get_weapon_stats()
	var neighbor_before: int = neighbor.hits
	player.health = 50.0
	player.on_enemy_killed(enemy, "player")
	_check(player._frenzy_remaining > 0.0 and float(player.get_weapon_stats().fire_rate) > float(game.inventory.stats().fire_rate), "Kill-frenzy changes the actual weapon cadence")
	_check(is_equal_approx(player.health, 55.0), "Vampiric heals exactly five health on a credited kill")
	_check(neighbor.hits == neighbor_before + 1, "Death-blast damages neighbors of a credited kill")
	neighbor_before = neighbor.hits
	player.on_enemy_killed(enemy, "proc")
	_check(neighbor.hits == neighbor_before and is_equal_approx(player.health, 55.0), "Proc kills cannot recursively trigger death explosions or healing")
	enemy.free()
	neighbor.free()
	_dispose(player, game)


func _test_visual_settings_and_flashlight() -> void:
	var game: FakeGame = _native_game()
	var settings: FakeSettings = FakeSettings.new()
	game.settings = settings
	settings.data = {"fov": 90.0, "head_bob": 0.0, "camera_shake": 0.0, "visual_recoil": 0.0, "weapon_effects": 0.0, "reduced_flashes": true}
	var player: PlayerScript = _native_player(game)
	player.aiming = false
	player._update_view(1.0, 0.0)
	_check(absf(player.camera.fov - 90.0) < 0.1, "Configured FOV is applied to the actual camera")
	_check(player.flashlight is SpotLight3D and player.flashlight.spot_range >= 20.0, "The flashlight is an actual camera-mounted world light")
	player.flashlight_on = true
	player.flashlight.visible = true
	player.third_person = true
	player._sync_perspective()
	_check(not player.weapon_view.visible and player.flashlight.visible, "Third-person view hides the weapon without losing the independent flashlight")
	player.third_person = false
	player._sync_perspective()
	await physics_frame
	player.fire_cooldown = 0.0
	player.shoot()
	var disabled_pitch: float = player._pitch
	player.weapon_view.call("animate_view", 0.01, false, 0.0, false, 0.0, 0.0, false)
	_check(is_zero_approx(player.weapon_view.model.rotation.x) and not player.weapon_view.flash.visible, "Reduced visual settings suppress model kick and muzzle flashes")
	settings.data["visual_recoil"] = 1.0
	settings.data["weapon_effects"] = 1.0
	settings.data["reduced_flashes"] = false
	player._pitch = 0.0
	player.fire_cooldown = 0.0
	player._update_view(0.1, 0.0)
	player.shoot()
	_check(is_equal_approx(player._pitch, disabled_pitch), "Visual recoil settings never alter mechanical aim recoil")
	_dispose(player, game)


func _test_fov_initialization_pause_and_ads() -> void:
	var game: FakeGame = _native_game()
	var settings: FakeSettings = FakeSettings.new()
	settings.data = {"fov": 101.0}
	game.settings = settings
	var player: PlayerScript = _new_player(game)
	root.add_child(player)
	player.set_physics_process(false)
	_check(is_equal_approx(player.camera.fov, 101.0), "The first rendered camera already uses the saved FOV before any physics frame")
	_check(player.camera.keep_aspect == Camera3D.KEEP_HEIGHT, "The FOV preference consistently represents vertical field of view")
	var before_time: float = player.time
	var before_ammo: int = player.magazine
	game.paused = true
	paused = true
	settings.data.fov = 60.0
	player.apply_settings(settings.data)
	_check(is_equal_approx(player.camera.fov, 60.0), "Applying the FOV slider immediately changes the camera while the scene tree is paused")
	var viewport_size: Vector2 = player.get_viewport().get_visible_rect().size
	var side_pixel: Vector2 = Vector2(0, viewport_size.y * 0.5)
	var forward: Vector3 = -player.camera.global_basis.z.normalized()
	var narrow_angle: float = player.camera.project_ray_normal(side_pixel).angle_to(forward)
	settings.data.fov = 110.0
	player.apply_settings(settings.data)
	var wide_angle: float = player.camera.project_ray_normal(side_pixel).angle_to(forward)
	_check(wide_angle > narrow_angle + 0.15, "FOV changes the actual camera projection during pause, not only the displayed value")
	_check(player.camera.project_ray_normal(viewport_size * 0.5).dot(forward) > 0.99999, "Changing FOV preserves the exact reticle-center shooting direction")
	player.aiming = true
	player.apply_settings(settings.data)
	var wide_ads: float = player.camera.fov
	_check(wide_ads > 80.0 and wide_ads < 110.0, "High-FOV ADS retains weapon zoom without flattening all high slider values to 80 degrees")
	settings.data.fov = 100.0
	player.apply_settings(settings.data)
	var lower_ads: float = player.camera.fov
	_check(lower_ads < wide_ads - 5.0, "The FOV slider continues to change ADS at the upper end of its range")
	player.third_person = true
	player._sync_perspective()
	player.apply_settings(settings.data)
	_check(is_equal_approx(player.camera.fov, lower_ads), "Third-person settings application preserves the active ADS zoom")
	player.sprinting = true
	player.apply_settings(settings.data)
	_check(is_equal_approx(player.camera.fov, lower_ads), "ADS takes priority over the sprint FOV offset")
	player.aiming = false
	player.apply_settings(settings.data)
	_check(is_equal_approx(player.camera.fov, 104.0), "An active sprint keeps its four-degree offset when settings change")
	player.sprinting = false
	player.apply_settings(settings.data)
	_check(is_equal_approx(player.camera.fov, 100.0), "Leaving ADS and sprint returns to the configured base FOV")
	_check(is_equal_approx(player.time, before_time) and player.magazine == before_ammo, "Applying camera preferences while paused does not advance gameplay or consume ammunition")
	paused = false
	game.paused = false
	player.third_person = false
	player._sync_perspective()
	player._update_view(0.2, 0.0)
	_check(is_equal_approx(player.camera.fov, 100.0), "Resuming runtime view updates does not overwrite the immediately applied FOV")
	_dispose(player, game)
	await physics_frame


func _test_combat_snapshot_resume() -> void:
	var game: FakeGame = _native_game()
	var player: PlayerScript = _native_player(game)
	_set_native_mods(game, player, ["third_strike", "heat"])
	player.magazine = 8
	player.reserve = 9
	player._combat_rng.seed = 71182391
	var enemy: DummyEnemy = _target_at(player.camera.global_position + Vector3(0, 0, -4), "body", Vector3(2, 2, 0.3))
	await physics_frame
	await process_frame
	player.shoot()
	_neutral_aim(player)
	player.shoot()
	player._frenzy_remaining = 2.75
	player._haste_remaining = 1.4
	player.velocity = Vector3(3.0, 4.0, -2.0)
	player.dash_remaining = 0.1
	player._dash_direction = Vector3.FORWARD
	var saved: Dictionary = JSON.parse_string(JSON.stringify(player.snapshot()))
	var restored_game: FakeGame = _native_game()
	_check(restored_game.inventory.import_state(game.inventory.export_state()), "A combat checkpoint restores the exact live inventory")
	var restored: PlayerScript = _native_player(restored_game)
	_check(restored.restore(saved), "Combat timing and RNG survive a JSON snapshot round trip")
	_check(restored.shot_count == 2 and int(restored._trigger_counts[restored.active_item_uid]) == 2, "Checkpoint keeps the trigger sequence on each weapon instance")
	_check(is_equal_approx(restored._heat, player._heat) and is_equal_approx(restored._frenzy_remaining, 2.75) and is_equal_approx(restored._haste_remaining, 1.4), "Checkpoint keeps heat, frenzy and haste timers")
	_check(restored.velocity.is_equal_approx(player.velocity) and is_equal_approx(restored.dash_remaining, 0.1), "Checkpoint preserves jump momentum and the remaining dash")
	_check(not restored.shoot(), "Restoring does not bypass an outstanding fire cooldown")
	for index: int in range(8):
		_check(player._combat_rng.randi() == restored._combat_rng.randi(), "Checkpoint preserves every RNG bit for future combat rolls")
	_neutral_aim(player)
	_neutral_aim(restored)
	player.shoot()
	restored.shoot()
	var original_damage: float = float(game.shot_results.back().stats.applied_damage)
	var restored_damage: float = float(restored_game.shot_results.back().stats.applied_damage)
	_check(is_equal_approx(original_damage, restored_damage) and original_damage > 44.0, "The first resumed trigger is the same heated third-strike as uninterrupted play")
	_check(player.magazine == restored.magazine, "Resumed combat consumes exactly the same ammunition")
	player.reloading = false
	player.magazine = 2
	player.reserve = 3
	player.start_reload()
	player._tick_weapon(player.reload_duration * 0.4)
	var partial_remaining: float = player.reload_remaining
	var reloading_saved: Dictionary = JSON.parse_string(JSON.stringify(player.snapshot()))
	_check(restored_game.inventory.import_state(game.inventory.export_state()), "The partially reloaded inventory can be reconstructed")
	_check(restored.restore(reloading_saved), "A save made during reload resumes that reload")
	_check(restored.reloading and is_equal_approx(restored.reload_remaining, partial_remaining), "Reload resumes with its actual remaining duration")
	_expect_ammo(restored, 2, 3, "Resuming a partial reload transfers no ammunition early")
	_check(not restored.shoot(), "A resumed reload still blocks firing")
	restored._tick_weapon(partial_remaining * 0.5)
	_expect_ammo(restored, 2, 3, "An incomplete resumed reload still transfers no ammunition")
	restored._tick_weapon(partial_remaining)
	_expect_ammo(restored, 5, 0, "The resumed reload conserves a short finite reserve")
	var corrupted: Dictionary = saved.duplicate(true)
	corrupted["rng_state"] = "not-an-integer"
	var unchanged_health: float = restored.health
	_check(not restored.restore(corrupted) and is_equal_approx(restored.health, unchanged_health), "Malformed combat RNG is rejected before mutating the player")
	corrupted = saved.duplicate(true)
	corrupted["trigger_counts"] = {"starter-biscuit": INF}
	_check(not restored.restore(corrupted), "Non-finite per-weapon trigger counters are rejected")
	enemy.free()
	_dispose(restored, restored_game)
	_dispose(player, game)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: %d weapon regression checks" % _checks)
		quit(0)
	else:
		printerr("FAIL: %d of %d weapon regression checks" % [_failures.size(), _checks])
		quit(1)

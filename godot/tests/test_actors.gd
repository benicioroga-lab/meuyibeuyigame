extends SceneTree

const Enemy = preload("res://scripts/enemy.gd")
const Companion = preload("res://scripts/companion.gd")
const EnemyData = preload("res://data/enemy_data.gd")
const NativeWorld = preload("res://scripts/world.gd")

class DummyPlayer extends CharacterBody3D:
	var health: float = 100.0
	var max_health: float = 100.0
	var damage_events: Array[Dictionary] = []
	var simulation_time: float = 0.0
	func take_damage(amount: float, source: Node3D = null) -> void:
		health -= amount
		damage_events.append({"amount": amount, "source": source, "time": simulation_time})

class DummyWorld extends Node3D:
	var navigation_ready: bool = false

class DummyGame extends Node3D:
	var player: DummyPlayer
	var world: DummyWorld
	var enemies: Array = []
	var running: bool = false
	var paused: bool = false
	var coins: int = 1000
	var kills: int = 0
	var bites: int = 0
	var damages: Array[Dictionary] = []
	var profile: Dictionary = {"unlocks": []}
	var spawn_budget: int = 2
	var summoned: int = 0
	var collected: int = 0
	func on_enemy_killed(_enemy: Node, _reward: int, _source: String) -> void:
		kills += 1
	func on_dog_attack(_enemy: Node) -> void:
		bites += 1
	func on_enemy_damaged(_enemy: Node, actual: float, zone: String, source: String) -> void:
		damages.append({"actual": actual, "zone": zone, "source": source})
	func spawn_add(kind: String, at: Vector3) -> void:
		if spawn_budget <= 0:
			return
		spawn_budget -= 1
		summoned += 1
		var actor := Enemy.new()
		actor.setup(self, kind, 1)
		add_child(actor)
		actor.position = at
		enemies.append(actor)
	func collect_nearby_drops(_position: Vector3, radius: float) -> void:
		if radius >= 1.0:
			collected += 1
	func notify(_text: String) -> void:
		pass

class NavigationGame extends Node3D:
	var player: DummyPlayer
	var world: Node3D
	var enemies: Array = []
	var running: bool = true
	var paused: bool = false
	func notify(_text: String) -> void:
		pass

class SteeringEnemy extends Enemy:
	var route_requests: int = 0
	func _navigation_direction(_target: Vector3, _delta: float) -> Vector3:
		route_requests += 1
		return Vector3.RIGHT

class SteeringCompanion extends Companion:
	var route_requests: int = 0
	func _navigation_direction(_target: Vector3, _delta: float) -> Vector3:
		route_requests += 1
		return Vector3.RIGHT

var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAILED: " + message)

func run() -> void:
	var game := DummyGame.new()
	root.add_child(game)
	game.player = DummyPlayer.new()
	game.add_child(game.player)
	game.player.collision_layer = 2
	var player_shape := CapsuleShape3D.new()
	player_shape.radius = 0.3
	player_shape.height = 1.8
	var player_collision := CollisionShape3D.new()
	player_collision.position.y = 0.9
	player_collision.shape = player_shape
	game.player.add_child(player_collision)
	game.player.position = Vector3(0, 0, 6)
	game.world = DummyWorld.new()
	game.add_child(game.world)
	var floor_body := StaticBody3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(40, 1, 40)
	var floor_collision := CollisionShape3D.new()
	floor_collision.shape = floor_shape
	floor_body.position.y = -0.5
	floor_body.add_child(floor_collision)
	game.add_child(floor_body)
	var enemy := Enemy.new()
	enemy.setup(game, "grunt", 1)
	game.add_child(enemy)
	game.enemies.append(enemy)
	var dog := Companion.new()
	dog.setup(game)
	game.add_child(dog)
	dog.position = Vector3(4, 0, 0)
	await physics_frame
	await physics_frame
	for pair in [["head", 1.55], ["body", 1.0], ["leg", 0.35]]:
		var query := PhysicsRayQueryParameters3D.create(Vector3(0, pair[1], -3), Vector3(0, pair[1], 3), 1 | 8)
		query.collide_with_areas = true
		var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty(), "ballistic hit " + pair[0])
		if not hit.is_empty():
			check(hit.collider.get_meta("zone", "") == pair[0], "correct hit zone " + pair[0])
	check(is_equal_approx(enemy.take_damage(10.0, "head"), 17.5), "head multiplier")
	check(is_equal_approx(enemy.take_damage(10.0, "body"), 10.0), "body multiplier")
	check(is_equal_approx(enemy.take_damage(10.0, "leg"), 6.5), "leg multiplier")
	check(is_equal_approx(enemy.take_damage(100.0), 8.0), "capped fatal damage")
	check(enemy.dead and game.kills == 1, "one death reward")
	check(enemy.take_damage(100.0) == 0.0 and game.kills == 1, "no repeated death reward")
	check(dog.upgrade() and dog.level == 2 and game.coins == 820 and dog.damage == 18.0, "first Faro upgrade")
	check(dog.upgrade() and dog.level == 3 and game.coins == 361, "scaled Faro upgrade")
	check(not dog.upgrade() and game.coins == 361, "Faro insufficient balance")
	dog.toggle_mode()
	check(dog.follow_only and dog.mode == "follow", "follow mode")
	dog.toggle_mode()
	check(not dog.follow_only and dog.mode == "hunt", "hunt mode")
	var target := Enemy.new()
	target.setup(game, "tank", 1)
	game.add_child(target)
	target.position = Vector3(4.85, 0, 0)
	target.speed = 0.0
	game.enemies.append(target)
	game.running = true
	for frame in 130:
		await physics_frame
	check(game.bites > 0 and target.health < target.max_health, "Faro native bite")
	check(not is_instance_valid(enemy), "death animation releases actor")
	game.running = false
	var boss := Enemy.new()
	boss.setup(game, "boss", 5)
	game.add_child(boss)
	boss.position = Vector3(8, 0, 0)
	game.player.position = Vector3(11, 0, 0)
	var previous_health: float = game.player.health
	boss._boss_windup = 0.01
	boss._update_boss(0.02, game.player, 3.0)
	check(is_equal_approx(previous_health - game.player.health, 34.0), "boss pulse hits nearby ground target")
	previous_health = game.player.health
	game.player.position.y = 1.0
	boss._boss_windup = 0.01
	boss._update_boss(0.02, game.player, 3.0)
	check(is_equal_approx(game.player.health, previous_health), "jump dodges boss pulse")
	dog.take_damage(999.0)
	check(dog.health == 0.0 and dog.get_status().contains("recuperando"), "Faro recoverable downed state")
	game.running = true
	dog._downed_time = 0.01
	await physics_frame
	await physics_frame
	check(dog.health == dog.max_health, "Faro recovery")
	game.running = false
	await expanded_actors(game, dog)
	var kills: int = game.kills
	var bites: int = game.bites
	game.queue_free()
	await process_frame
	await contact_damage_regression()
	await gate_combat_regression()
	await native_corner_regression()
	print("ACTORS_SMOKE checks=%d failures=%d kills=%d bites=%d" % [checks, failures, kills, bites])
	quit(1 if failures > 0 else 0)


func make_actor(game: DummyGame, kind: String, at: Vector3) -> CharacterBody3D:
	var actor := Enemy.new()
	actor.setup(game, kind, 1)
	game.add_child(actor)
	actor.position = at
	game.enemies.append(actor)
	return actor


func expanded_actors(game: DummyGame, dog: CharacterBody3D) -> void:
	check(game.damages.size() >= 4 and game.damages[0]["zone"] == "head" and game.damages[0]["actual"] == 17.5, "damage callbacks expose actual zone damage")
	var actors: Dictionary = {}
	var index: int = 0
	for id in EnemyData.ARCHETYPES:
		var actor: CharacterBody3D = make_actor(game, id, Vector3(-13 + index * 1.8, 0, 10))
		actors[id] = actor
		check(actor.kind == id and actor.health > 0 and actor._hit_areas.size() == 3, "archetype rig " + id)
		index += 1
	var armored: CharacterBody3D = actors["armored"]
	check(is_equal_approx(armored.take_damage(10.0), 4.8), "armor mitigates body shot")
	check(is_equal_approx(armored.take_damage(10.0, "head"), 17.5), "head bypasses armor")
	armored.apply_status("corrosive", 2.0, 4.0)
	check(is_equal_approx(armored.take_damage(10.0), 10.0), "corrosion strips armor")
	var runner: CharacterBody3D = actors["runner"]
	runner.configure_difficulty(2.0, 100.0, true)
	runner.configure_elite("frenzy")
	runner.apply_status("frenzy", 0.6, 5.0)
	check(runner.get_effective_speed() <= runner.speed_max, "final elite and buff speed cap")
	runner.apply_status("frost", 0.5, 2.0)
	check(runner.statuses.has("cryo") and runner.get_effective_speed() < runner.speed_max, "frost alias slows")
	runner.apply_status("freeze", 1.0, 0.2)
	check(runner.get_effective_speed() == 0.0, "freeze prevents movement")
	runner._update_statuses(0.21)
	check(not runner.statuses.has("freeze") and runner.get_effective_speed() > 0.0, "freeze expires")
	var grunt: CharacterBody3D = actors["grunt"]
	var before: float = grunt.health
	grunt.apply_status("burn", 10.0, 1.0)
	grunt._update_statuses(0.4)
	check(is_equal_approx(before - grunt.health, 4.0), "burn uses elapsed seconds")
	grunt._update_statuses(0.7)
	check(is_equal_approx(before - grunt.health, 10.0) and not grunt.statuses.has("burn"), "burn lifetime caps damage")
	check(game.damages.back()["source"] == "status", "status damage reported once through actor")
	var vamp: CharacterBody3D = actors["tank"]
	vamp.configure_elite("vampiric")
	vamp.health -= 30.0
	before = vamp.health
	game.player.health = 100.0
	vamp._deal_damage(game.player, 10.0)
	check(is_equal_approx(vamp.health - before, 4.5), "vampiric heals from actual outgoing damage")
	var fire: CharacterBody3D = actors["hunter"]
	fire.configure_elite("fire")
	fire._deal_damage(game.player, 5.0)
	before = game.player.health
	fire._update_fire(0.65)
	check(is_equal_approx(before - game.player.health, 2.0), "fire elite leaves a short burn")
	check(game.player.damage_events.back()["source"] == fire, "fire damage retains the enemy source for player cap and feedback")
	fire._begin_special("leap", 0.72, game.player.global_position)
	check(fire._special_time > 0.0 and fire._charge_time == 0.0, "hunter telegraphs before jumping")
	fire._finish_special(game.player)
	check(fire.velocity.y > 0.0 and fire._charge_time > 0.0, "hunter commits a bounded leap")
	var screamer: CharacterBody3D = actors["screamer"]
	screamer.position = grunt.position + Vector3(1, 0, 0)
	screamer._begin_special("scream", 0.95, game.player.global_position)
	screamer._finish_special(game.player)
	check(grunt.statuses.has("frenzy") and game.summoned == 1, "screamer buffs nearby allies and calls reinforcement")
	var summoner: CharacterBody3D = actors["summoner"]
	summoner._summon_adds(4, "parasite")
	check(game.summoned == 2 and game.spawn_budget == 0, "summons respect director finite budget")
	while game.enemies.filter(func(actor: Variant) -> bool: return is_instance_valid(actor) and not actor.dead).size() < 24:
		make_actor(game, "grunt", Vector3(15, 0, 14))
	game.spawn_budget = 5
	summoner._summon_adds(4, "grunt")
	check(game.summoned == 2 and game.spawn_budget == 5, "summoner respects 24 active actor cap")
	var spitter: CharacterBody3D = actors["spitter"]
	spitter.position = Vector3.ZERO
	game.player.position = Vector3(0, 0, -6)
	game.player.health = 100.0
	await physics_frame
	await physics_frame
	spitter._begin_special("spit", 0.7, game.player.global_position + Vector3.UP * 0.9)
	check(spitter._projectiles.is_empty() and spitter._telegraph_line.visible, "ranged shot has visible windup")
	game.player.position.x = 3.0
	await physics_frame
	spitter._finish_special(game.player)
	spitter._update_projectiles(1.0)
	check(game.player.health == 100.0, "moving away dodges aimed projectile")
	spitter._update_projectiles(4.0)
	game.player.position.x = 0.0
	await physics_frame
	await physics_frame
	spitter._begin_special("spit", 0.7, game.player.global_position + Vector3.UP * 0.9)
	spitter._finish_special(game.player)
	spitter._update_projectiles(1.0)
	check(game.player.health < 100.0, "native swept projectile collides with player")
	check(game.player.damage_events.back()["source"] == spitter, "projectile damage retains its living enemy source")
	for shot in 8:
		spitter._launch_projectile(Vector3.FORWARD, 3.0, Color.GREEN)
	check(spitter._projectiles.size() <= 3, "projectiles are bounded per actor")
	spitter.take_damage(9999.0)
	check(spitter._projectiles.is_empty(), "death removes hostile projectiles")
	var exploder: CharacterBody3D = actors["exploder"]
	exploder.position = Vector3.ZERO
	game.player.position = Vector3(0, 0, -2)
	exploder._begin_special("explode", 1.05, game.player.global_position)
	check(exploder._shock_ring.visible and not exploder.dead, "exploder visibly arms before blast")
	before = game.player.health
	game.player.position.z = -5.0
	exploder._finish_special(game.player)
	check(exploder.dead and exploder.reward == 0 and game.player.health == before, "explosion can be avoided and never pays self reward")
	var stealth: CharacterBody3D = actors["stealth"]
	stealth.position = Vector3(12, 0, 10)
	stealth._animate(0.1)
	check(stealth._visual["materials"][0].albedo_color.a < 0.3, "stealth shimmers at range")
	stealth.take_damage(1.0)
	stealth._animate(0.1)
	check(stealth._visual["materials"][0].albedo_color.a == 1.0, "hit reveals stealth enemy")
	var boss: CharacterBody3D = actors["boss"]
	boss.health = boss.max_health * 0.5
	boss._update_boss(0.01, game.player, 10.0)
	check(boss.boss_phase == 2, "boss second phase")
	boss.health = boss.max_health * 0.2
	boss._update_boss(0.01, game.player, 10.0)
	check(boss.boss_phase == 3 and boss.speed <= boss.speed_max, "boss final phase keeps speed capped")
	boss.configure_boss("bulwark")
	boss._boss_cooldown = 0.0
	boss._update_boss(0.01, game.player, 7.0)
	check(boss._special == "charge" and boss._special_time > 0.0, "bulwark has charge telegraph")
	boss._special_time = 0.0
	boss.configure_boss("conductor")
	boss._boss_cooldown = 0.0
	boss._update_boss(0.01, game.player, 7.0)
	check(boss._special in ["summon", "volley"], "conductor uses ranged or summoned pressure")
	runner._dog_retaliation_cooldown = 2.4
	var enemy_state: Dictionary = JSON.parse_string(JSON.stringify(runner.export_state()))
	var restored: CharacterBody3D = make_actor(game, "runner", Vector3.ZERO)
	restored.import_state(enemy_state)
	check(restored.elite == "frenzy" and is_equal_approx(restored.health, runner.health) and restored.statuses.has("cryo"), "enemy snapshot restores elite health and statuses")
	check(restored.global_position.is_equal_approx(runner.global_position), "enemy snapshot restores native position")
	check(is_equal_approx(restored._damage, runner._damage) and is_equal_approx(restored._dog_retaliation_cooldown, 2.4), "enemy snapshot preserves current damage and Faro retaliation cooldown")
	var legacy: CharacterBody3D = make_actor(game, "grunt", Vector3(0, 0, 16))
	legacy.configure_difficulty(1.25, 1.0)
	legacy.import_state({"damage": 7.0})
	check(is_equal_approx(legacy._damage, 27.5) and legacy._dog_retaliation_cooldown == 0.0, "legacy snapshot adopts new damage balance without losing selected difficulty")
	await expanded_dog(game, dog)
	# Path routing, not an XZ-only radius, decides how to reach another floor.
	var overhead_enemy := SteeringEnemy.new()
	overhead_enemy.setup(game, "grunt", 1)
	game.add_child(overhead_enemy)
	overhead_enemy.set_physics_process(false)
	overhead_enemy.position = Vector3(-17, 0.1, -17)
	game.player.position = overhead_enemy.position + Vector3.UP * 4.0
	game.running = true
	overhead_enemy._physics_process(1.0 / 60.0)
	check(overhead_enemy.route_requests > 0 and overhead_enemy.velocity.x > 0.0, "enemy follows a route when target is directly on another floor")
	game.running = false
	var overhead_dog := SteeringCompanion.new()
	overhead_dog.setup(game)
	game.add_child(overhead_dog)
	overhead_dog.set_physics_process(false)
	overhead_dog.position = Vector3(-18, 0.1, -17)
	overhead_dog.follow_only = true
	game.player.position = overhead_dog.position + Vector3.UP * 4.0
	game.running = true
	overhead_dog._physics_process(1.0 / 60.0)
	check(overhead_dog.route_requests > 0 and overhead_dog.velocity.x > 0.0, "Faro follows a route when owner is directly on another floor")
	game.running = false


func expanded_dog(game: DummyGame, dog: CharacterBody3D) -> void:
	game.player.position = dog.position + Vector3(0, 0, 2)
	game.player.health = 60.0
	game.coins = 100000
	var previous: float = dog.damage
	check(dog.upgrade_branch("attack") and dog.damage > previous and dog.damage - previous < 6.0, "attack improvements have diminishing gain")
	for step in 5:
		dog.upgrade_branch("attack")
	check(dog.level > 5 and dog.branch_cost("attack") > 0, "dog levels continue beyond former cap")
	var balance: int = game.coins
	check(not dog.upgrade_branch("missing") and game.coins == balance, "invalid dog branch never spends currency")
	check(dog.upgrade_branch("survival") and dog.max_health > 70.0, "survival increases actual health pool")
	game.profile["unlocks"] = ["collector", "support", "guardian"]
	balance = game.coins
	check(dog.switch_archetype("collector") and game.coins == balance, "permanent profile unlock does not charge run coins")
	dog._ability_timer = 0.0
	dog._update_abilities(0.1)
	check(game.collected > 0, "collector invokes real nearby drop collection")
	check(dog.switch_archetype("support"), "support specialization available")
	dog._heal_timer = 0.0
	var before: float = game.player.health
	dog._update_abilities(0.1)
	check(game.player.health > before and game.player.health <= game.player.max_health, "support heals actual player health")
	check(dog.switch_archetype("guardian"), "guardian specialization available")
	dog._shield_delay = 0.0
	dog._update_abilities(8.0)
	check(dog.shield > 0.0 and dog.absorb_damage(20.0) < 20.0, "guardian shield absorbs damage")
	var shield_before: float = dog.shield
	dog._update_abilities(0.1)
	check(dog.shield == shield_before, "shield waits after a hit before recharging")
	var aggro: CharacterBody3D = game.enemies.filter(func(actor: Variant) -> bool: return is_instance_valid(actor) and not actor.dead)[0]
	aggro.position = dog.position + Vector3(1, 0, 0)
	dog._taunt_timer = 0.0
	dog._update_abilities(0.1)
	check(aggro._aggro_target == dog, "guardian redirects hostile attention")
	game.player.health = 0.0
	check(dog.try_revive() and game.player.health == 35.0, "Faro rescues the downed player")
	game.player.health = 0.0
	check(not dog.try_revive(), "revive has a long cooldown")
	game.player.health = 35.0
	var saved: Dictionary = JSON.parse_string(JSON.stringify(dog.export_state()))
	var clone := Companion.new()
	clone.setup(game)
	game.add_child(clone)
	clone.import_state(saved)
	check(clone.levels == dog.levels and clone.archetype == dog.archetype and is_equal_approx(clone.damage, dog.damage), "dog progression survives JSON save roundtrip")
	check(clone._revive_cooldown > 60.0 and clone.owned_archetypes.has("collector"), "save retains rescue cooldown and unlocked variants")
	var progress: Dictionary = clone.get_progression()
	check(progress["branches"].size() == 4 and progress["archetypes"].size() == 4 and progress["branches"][0]["next_value"] > progress["branches"][0]["value"], "shop progression has actual comparisons and all choices")
	check(is_instance_valid(clone._gear) and clone._gear.get_child_count() > 2, "progression creates visible dog equipment")
	clone.queue_free()
	await process_frame


func contact_damage_regression() -> void:
	var previous_hz: int = Engine.physics_ticks_per_second
	var previous_scale: float = Engine.time_scale
	var previous_steps: int = Engine.max_physics_steps_per_frame
	Engine.physics_ticks_per_second = 180
	Engine.max_physics_steps_per_frame = 16
	Engine.time_scale = 6.0
	for case in [
		{"kind": "grunt", "hits": 5, "damage": 22.0, "interval": 1.15, "dog": false},
		{"kind": "runner", "hits": 6, "damage": 18.0, "interval": 1.0, "dog": false},
		{"kind": "tank", "hits": 4, "damage": 32.0, "interval": 1.35, "dog": false},
		{"kind": "grunt", "hits": 5, "damage": 22.0, "interval": 1.15, "dog": true},
	]:
		var game := make_contact_game()
		var actor: CharacterBody3D = make_actor(game, str(case["kind"]), Vector3(0, 0.02, 1.0))
		actor._attack_cooldown = 0.35
		var dog: CharacterBody3D
		if case["dog"]:
			dog = Companion.new()
			dog.setup(game)
			game.add_child(dog)
			dog.position = Vector3(1.0, 0.02, 1.0)
		await physics_frame
		game.running = true
		for frame in 480:
			await physics_frame
			game.player.simulation_time += game.player.get_physics_process_delta_time()
			if game.player.health <= 0.0:
				break
		game.running = false
		var events: Array[Dictionary] = game.player.damage_events
		var label: String = str(case["kind"]) + (" with active Faro" if case["dog"] else " solo")
		check(game.player.health <= 0.0 and events.size() == int(case["hits"]), "%s defeats idle 100 HP player in expected 4-6 hits" % label)
		if not events.is_empty():
			var elapsed: float = float(events.back()["time"])
			check(elapsed >= 4.5 and elapsed <= 8.0, "%s contact defeat takes 4.5-8 seconds, got %.2f" % [label, elapsed])
			check(float(events.front()["time"]) >= actor._attack_windup, "%s keeps the visible initial attack windup" % label)
			var correct_impacts: bool = true
			var correct_cadence: bool = true
			for index in events.size():
				correct_impacts = correct_impacts and is_equal_approx(float(events[index]["amount"]), float(case["damage"])) and events[index]["source"] == actor
				if index > 0:
					var interval: float = float(events[index]["time"]) - float(events[index - 1]["time"])
					correct_cadence = correct_cadence and absf(interval - float(case["interval"])) < 0.12
			check(correct_impacts, "%s every impact has its balanced damage and enemy source" % label)
			check(correct_cadence, "%s measured cadence includes windup instead of adding it again" % label)
			print("CONTACT_DAMAGE kind=%s hits=%d seconds=%.2f bites=%d" % [label, events.size(), elapsed, game.bites])
		if case["dog"]:
			check(game.bites >= 2 and dog.health > 0.0, "active unupgraded Faro attacks without permanently stealing contact aggro")
		game.queue_free()
		await process_frame
	# A telegraph must still commit against the target's current position.
	var game := make_contact_game()
	var actor: CharacterBody3D = make_actor(game, "grunt", Vector3(0, 0.02, 1.0))
	actor._attack_cooldown = 0.0
	game.running = true
	for frame in 30:
		await physics_frame
		if actor._windup > 0.0:
			break
	check(actor._windup > 0.0 and game.player.damage_events.is_empty(), "contact attack visibly winds up before applying damage")
	game.player.position = Vector3(0, 0, -5)
	for frame in 15:
		await physics_frame
	game.running = false
	check(game.player.damage_events.is_empty(), "leaving melee reach during its telegraph avoids the hit")
	var dog := Companion.new()
	dog.setup(game)
	game.add_child(dog)
	dog.position = actor.position + Vector3.RIGHT
	actor.take_damage(1.0, "body", "faro")
	check(is_equal_approx(actor._aggro_timer, 0.8) and is_equal_approx(actor._dog_retaliation_cooldown, 4.0), "ordinary Faro retaliation is short with a separate four-second cooldown")
	actor._aggro_timer = 0.2
	actor._dog_retaliation_cooldown = 3.4
	actor.take_damage(1.0, "body", "faro")
	check(is_equal_approx(actor._aggro_timer, 0.2), "a repeated Faro bite cannot extend ordinary retaliation")
	actor.taunt(dog, 2.7)
	actor.take_damage(1.0, "body", "faro")
	check(is_equal_approx(actor._aggro_timer, 2.7) and actor._combat_target() == dog, "Guardian's explicit taunt remains authoritative")
	game.queue_free()
	await process_frame
	Engine.time_scale = previous_scale
	Engine.physics_ticks_per_second = previous_hz
	Engine.max_physics_steps_per_frame = previous_steps


func make_contact_game() -> DummyGame:
	var game := DummyGame.new()
	root.add_child(game)
	game.world = DummyWorld.new()
	game.add_child(game.world)
	game.player = DummyPlayer.new()
	game.player.collision_layer = 2
	game.add_child(game.player)
	var player_shape := CapsuleShape3D.new()
	player_shape.radius = 0.3
	player_shape.height = 1.8
	var player_collision := CollisionShape3D.new()
	player_collision.shape = player_shape
	player_collision.position.y = 0.9
	game.player.add_child(player_collision)
	var floor_body := StaticBody3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(24, 1, 24)
	var floor_collision := CollisionShape3D.new()
	floor_collision.shape = floor_shape
	floor_body.position.y = -0.5
	floor_body.add_child(floor_collision)
	game.add_child(floor_body)
	return game


func gate_combat_regression() -> void:
	var game := DummyGame.new()
	root.add_child(game)
	game.world = DummyWorld.new()
	game.add_child(game.world)
	game.player = DummyPlayer.new()
	game.add_child(game.player)
	game.player.collision_layer = 2
	game.player.collision_mask = 1 | 32
	var player_shape := CapsuleShape3D.new()
	player_shape.radius = 0.3
	player_shape.height = 1.8
	var player_collision := CollisionShape3D.new()
	player_collision.shape = player_shape
	player_collision.position.y = 0.9
	game.player.add_child(player_collision)
	var floor_body := StaticBody3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(20, 1, 20)
	var floor_collision := CollisionShape3D.new()
	floor_collision.shape = floor_shape
	floor_body.position.y = -0.5
	floor_body.add_child(floor_collision)
	game.add_child(floor_body)
	var barrier := StaticBody3D.new()
	barrier.collision_layer = 32
	barrier.collision_mask = 0
	barrier.position.y = 1.5
	var gate_shape := BoxShape3D.new()
	gate_shape.size = Vector3(8, 3, 0.16)
	var gate_collision := CollisionShape3D.new()
	gate_collision.shape = gate_shape
	barrier.add_child(gate_collision)
	game.add_child(barrier)
	var enemy := Enemy.new()
	enemy.setup(game, "grunt", 1)
	game.add_child(enemy)
	game.enemies.append(enemy)
	var dog := Companion.new()
	dog.setup(game)
	dog.follow_only = true
	game.add_child(dog)
	game.player.position = Vector3(0, 0, -3)
	enemy.position = Vector3(0, 0.05, 2)
	dog.position = Vector3(2, 0.05, 2)
	game.running = true
	for frame in 90:
		await physics_frame
	game.running = false
	check(enemy.position.z > 0.35, "closed layer-32 gate blocks enemy movement")
	check(dog.position.z > 0.3, "closed layer-32 gate blocks Faro movement")
	enemy.position = Vector3(0, 0.05, 0.65)
	enemy.velocity = Vector3.ZERO
	dog.position = Vector3(2, 0.05, 2)
	game.player.position = Vector3(0, 0.05, -0.5)
	await physics_frame
	await physics_frame
	check(enemy._clear_sight(game.player), "enemy ranged line passes through gate bars")
	check(not enemy._clear_sight(game.player, true), "enemy contact line is blocked by gate")
	var before: float = game.player.health
	enemy._windup = 0.001
	game.running = true
	await physics_frame
	await physics_frame
	game.running = false
	check(game.player.health == before, "committed enemy melee cannot damage through closed gate")
	enemy._launch_projectile(Vector3.FORWARD, 7.0, Color.GREEN)
	enemy._update_projectiles(0.2)
	check(is_equal_approx(before - game.player.health, 7.0), "native enemy projectile crosses closed gate and hits player")
	enemy.position = Vector3(0, 0.05, -0.5)
	dog.position = Vector3(0, 0.05, 0.65)
	game.player.position = Vector3(3, 0.05, 2)
	await physics_frame
	await physics_frame
	check(not dog._clear_sight(enemy), "Faro bite line is blocked by gate")
	before = enemy.health
	dog.follow_only = false
	dog._enemy_target = enemy
	dog._search_timer = 10.0
	dog._bite_time = 0.001
	game.running = true
	await physics_frame
	await physics_frame
	game.running = false
	check(enemy.health == before, "committed Faro bite cannot damage through closed gate")
	dog.follow_only = true
	dog.position = Vector3(2, 0.05, 2)
	enemy.position = Vector3(0, 0.05, 0.65)
	game.player.position = Vector3(0, 0.05, -0.5)
	barrier.collision_layer = 1
	await physics_frame
	await physics_frame
	check(not enemy._clear_sight(game.player) and not enemy._clear_sight(game.player, true), "solid wall blocks both ranged and contact lines")
	before = game.player.health
	enemy._launch_projectile(Vector3.FORWARD, 7.0, Color.GREEN)
	enemy._update_projectiles(0.2)
	check(game.player.health == before and enemy._projectiles.is_empty(), "native projectile stops at solid wall")
	game.player.position = Vector3(0, 0, -3)
	enemy.position = Vector3(0, 0.05, 2)
	enemy.velocity = Vector3.ZERO
	dog.position = Vector3(2, 0.05, 2)
	dog.velocity = Vector3.ZERO
	game.running = true
	for frame in 90:
		await physics_frame
	game.running = false
	check(enemy.position.z > 0.35 and dog.position.z > 0.3, "solid walls remain impassable for both actors")
	barrier.collision_layer = 0
	game.running = true
	for frame in 90:
		await physics_frame
	game.running = false
	check(enemy.position.z < -0.2 and dog.position.z < -0.2, "opening gate releases native actor movement")
	game.queue_free()
	await process_frame


func native_corner_regression() -> void:
	# Captured from the seeded round-25 endurance failure: a tank pressed into
	# the sloping PassarelaDoEco parapet forever while its path stayed reachable.
	var game := NavigationGame.new()
	root.add_child(game)
	game.player = DummyPlayer.new()
	game.player.health = 100000.0
	game.add_child(game.player)
	game.world = NativeWorld.new()
	game.world.setup(game)
	game.add_child(game.world)
	for frame in 360:
		if game.world.navigation_ready:
			break
		await physics_frame
	check(game.world.navigation_ready, "native corner regression has baked world navigation")
	if not game.world.navigation_ready:
		game.queue_free()
		await process_frame
		return
	for region in game.world.regions:
		game.world.unlock_region(str(region.id))
	await physics_frame
	var previous_hz: int = Engine.physics_ticks_per_second
	var previous_scale: float = Engine.time_scale
	var previous_steps: int = Engine.max_physics_steps_per_frame
	Engine.physics_ticks_per_second = 180
	Engine.max_physics_steps_per_frame = 16
	Engine.time_scale = 6.0
	var cases: Array[Dictionary] = [
		{"kind": "tank", "start": Vector3(29.64454, 0.000837, -38.34859), "target": Vector3(9.1537, 7.8027, -32.2081), "frames": 420},
		{"kind": "tank", "start": Vector3(29.74511, 0.000089, -37.89217), "target": Vector3(0.29191, 0.02247, 14.03255), "frames": 1080},
		{"kind": "boss_bulwark", "start": Vector3(29.64454, 0.000837, -38.34859), "target": Vector3(9.1537, 7.8027, -32.2081), "frames": 420},
		{"kind": "grunt", "start": Vector3(9.471, 7.813, -32.214), "target": Vector3(0.775, 3.616, -51.698), "frames": 960},
		{"kind": "hunter", "start": Vector3(25.63218, 1.971872, -36.48517), "target": Vector3(15, 8, -36), "frames": 480},
		{"kind": "grunt", "start": Vector3(28.15115, 0.532485, -35.11043), "target": Vector3(15, 8, -36), "frames": 480},
	]
	for case in cases:
		game.player.position = case["target"]
		var actor := Enemy.new()
		actor.setup(game, str(case["kind"]), 25, 1.25)
		actor.configure_difficulty(1.3, 1.2)
		actor._boss_cooldown = 1000.0
		actor._special_cooldown = 1000.0
		game.add_child(actor)
		actor.position = case["start"]
		game.enemies.append(actor)
		var departed: bool = false
		for frame in int(case["frames"]):
			await physics_frame
			if frame <= 150 and actor.position.distance_to(case["start"]) > 3.0:
				departed = true
			if actor.position.distance_to(game.player.position) < 2.1 and absf(actor.position.y - game.player.position.y) < 0.8:
				break
		check(departed, "%s physically leaves captured parapet corner" % case["kind"])
		check(actor.position.distance_to(game.player.position) < 2.5, "%s reaches player by a native physical route: %s" % [case["kind"], actor.position])
		check(absf(actor.position.y - game.player.position.y) < 0.8, "%s reaches correct destination floor" % case["kind"])
		game.enemies.erase(actor)
		actor.queue_free()
		await physics_frame
	# Faro previously stopped halfway up this flight: its 14 cm planar dead zone
	# was reached before a sloped 3D waypoint entered the 22 cm arrival sphere.
	game.player.position = Vector3(15, 8, -36)
	var dog := Companion.new()
	dog.setup(game)
	dog.follow_only = true
	game.add_child(dog)
	dog.position = Vector3(29.8, 0.12, -36)
	var dog_departed: bool = false
	for frame in 540:
		await physics_frame
		if frame <= 150 and dog.position.distance_to(Vector3(29.8, 0.12, -36)) > 3.0:
			dog_departed = true
		if dog.position.distance_to(game.player.position) < 2.1 and absf(dog.position.y - game.player.position.y) < 0.8:
			break
	check(dog_departed, "Faro physically climbs the PassarelaDoEco flight")
	check(dog.position.distance_to(game.player.position) < 2.5, "Faro consumes sloped waypoints and reaches owner: %s" % dog.position)
	check(absf(dog.position.y - game.player.position.y) < 0.8, "Faro reaches the upper landing floor")
	Engine.time_scale = previous_scale
	Engine.physics_ticks_per_second = previous_hz
	Engine.max_physics_steps_per_frame = previous_steps
	game.queue_free()
	await process_frame

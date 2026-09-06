extends SceneTree

const World = preload("res://scripts/world.gd")
const Exploration = preload("res://scripts/exploration.gd")
const Loot = preload("res://data/loot_data.gd")

class TestUI extends RefCounted:
	var messages: Array = []
	func announce(title: String, body: String) -> void: messages.append([title, body])

class TestAudio extends RefCounted:
	var calls: Array[String] = []
	func play(id: String) -> void: calls.append(id)

class TestSettings extends RefCounted:
	var data := {"effects":0.0, "reduced_flashes":true}

class TestPlayer extends Node3D:
	var camera: Camera3D
	var reserve := 60
	func _ready() -> void:
		camera = Camera3D.new()
		camera.position.y = 1.55
		add_child(camera)
	func add_ammo(amount: int) -> void: reserve = mini(100, reserve + maxi(0, amount))
	func get_weapon_stats() -> Dictionary: return {"name":"Arma de teste", "max_reserve":100}

class TestGame extends Node3D:
	var world: Node3D
	var player: TestPlayer
	var inventory = preload("res://scripts/inventory.gd").new()
	var ui := TestUI.new()
	var audio := TestAudio.new()
	var settings: Variant = null
	var running := false
	var paused := false
	var active_powerups: Dictionary = {}
	var boss_zone: Dictionary = {}
	var coins := 0
	var round_number := 1
	var rng := RandomNumberGenerator.new()
	var notices: Array[String] = []
	var powerups: Array[String] = []
	var recorded: Array[String] = []
	var saves := 0
	var inventory_opened := ""
	func add_coins(amount: int, _source: String = "") -> void: coins += amount
	func notify(message: String) -> void: notices.append(message)
	func schedule_save() -> void: saves += 1
	func spend(cost: int) -> bool:
		if cost < 0 or coins < cost: return false
		coins -= cost
		return true
	func open_inventory(id: String) -> void: inventory_opened = id
	func start_boss(poi: Dictionary) -> void: boss_zone = poi.duplicate()
	func loot_quality() -> float: return 1.0
	func record_weapon(item: Dictionary) -> void: recorded.append(str(item.uid))
	func award_profile(_id: String, _amount: int) -> void: pass
	func activate_powerup(id: String) -> void:
		powerups.append(id)
		if id == "jackpot": coins += 250 + round_number * 30

var game: TestGame
var exploration: Node3D
var checks := 0
var failures: Array[String] = []
var item_seed := 29000
var finished := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(40, true).timeout.connect(func():
		if not finished:
			printerr("EXPLORATION timed out")
			quit(1))
	game = TestGame.new()
	root.add_child(game)
	game.inventory.create_starter()
	game.rng.seed = 937
	game.world = World.new()
	game.add_child(game.world)
	game.player = TestPlayer.new()
	game.add_child(game.player)
	exploration = Exploration.new()
	exploration.setup(game)
	game.add_child(exploration)
	while not game.world.navigation_ready: await physics_frame
	await _check_pov_and_doors()
	await _check_bidirectional_gates()
	await _check_hover_context()
	await _check_aim_selection()
	await _check_new_drop_settings()
	await _check_capacity_and_compensation()
	await _check_pending_and_restore()
	await _check_pickup_feedback()
	await _check_challenge_and_ground()
	await _check_expansion_challenges()
	finished = true
	print("EXPLORATION_INTEGRATION checks=%d failures=%d" % [checks, failures.size()])
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _check_pov_and_doors() -> void:
	_aim(Vector3(-6.8, 0.25, 16), Vector3(-6.8, 1.2, 14))
	exploration._scan()
	_check(exploration.target.get("type") == "forge", "Forge is interactable from its physical approach")
	exploration.interact()
	_check(game.inventory_opened == "forge", "E opens the visible forge")
	_aim(Vector3(10, 0.25, 14), Vector3(10, 1.55, 12.4))
	exploration._scan()
	_check(exploration.target.get("type") == "door", "Gate interaction point is visible in front of the physical gate")
	game.coins = 250
	game.round_number = 1
	exploration.interact()
	_check(game.coins == 250 and not game.world.unlocked_regions.has("oficina"), "Round requirement prevents charging or opening early")
	_check(game.notices[-1].contains("round 2"), "Gate reports its actual round requirement")
	game.round_number = 2
	game.coins = 100
	exploration.interact()
	_check(game.coins == 100 and not game.world.unlocked_regions.has("oficina"), "Insufficient funds do not mutate the gate")
	game.coins = 200
	exploration.interact()
	await physics_frame
	await physics_frame
	_check(game.coins == 20 and game.world.unlocked_regions.has("oficina"), "Eligible E interaction charges exactly 180 and opens the region")
	for gate: Dictionary in game.world._gates.oficina:
		_check(gate.collider.disabled, "Purchased access disables every real workshop gate collider")
	exploration.interact()
	_check(game.coins == 20, "Opened gates cannot charge the player twice")
	var terms: Dictionary = exploration._door_terms({"region_id":"oficina", "cost":-900, "unlock_round":0})
	_check(terms.cost == 180 and terms.round == 2, "Region data remains authoritative for price and round")
	_check(not exploration._available({"type":"door", "region_id":"unknown"}), "Unknown gates cannot become interactions")
	_aim(Vector3(0, 0.25, 17), Vector3(0, 0.45, 14.6))
	var drop: Node3D = exploration.drop_item("weapon", _weapon("common"), Vector3(0, 0.1, 14.6))
	var barrier := StaticBody3D.new()
	barrier.collision_layer = 1
	barrier.collision_mask = 0
	barrier.position = Vector3(0, 1.1, 15.8)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2, 2.2, 0.2)
	collider.shape = shape
	barrier.add_child(collider)
	game.add_child(barrier)
	await physics_frame
	await physics_frame
	exploration._scan()
	_check(exploration.target.is_empty(), "A real collision wall occludes a nearby loot prompt")
	game.player.camera.global_position = Vector3(2.5, 1.8, 17)
	game.player.camera.look_at(drop.global_position + Vector3.UP * 0.4)
	_check(not exploration._visible(drop.global_position + Vector3.UP * 0.4), "Third person camera peeking cannot collect through the player's wall")
	barrier.queue_free()
	await physics_frame
	await physics_frame
	_aim(Vector3(0, 0.25, 17), drop.global_position + Vector3.UP * 0.4)
	exploration._scan()
	_check(exploration.target.get("node") == drop, "Removing the physical obstruction restores the correct loot target")
	game.player.camera.look_at(Vector3(0, 1.5, 22))
	exploration._scan()
	_check(exploration.target.is_empty(), "Loot behind the viewing direction cannot receive E")
	_aim(Vector3(0, 0.25, 17), drop.global_position + Vector3.UP * 0.4)
	var count: int = game.inventory.items.size()
	exploration.interact()
	_check(game.inventory.items.size() == count + 1 and not exploration.drops.has(drop), "Visible E pickup transfers one item and removes exactly its drop")
	await _clear()

func _check_capacity_and_compensation() -> void:
	_fill("common", 96)
	var original_count: int = game.inventory.items.size()
	var common := _weapon("common")
	_check(not exploration.can_accept_drop("weapon", common), "Equal-rarity saturated ground refuses a discarded item before inventory removal")
	_check(game.inventory.items.size() == original_count and exploration.drops.size() == 96, "Discard precheck has no inventory or drop mutations")
	var legendary := _weapon("legendary")
	var before: int = game.coins
	var compensation: int = game.inventory.stats(exploration.drops[0].payload).value
	_check(exploration.can_accept_drop("weapon", legendary), "Strictly better loot can replace inferior ground loot")
	var reward: Node3D = exploration.drop_item("weapon", legendary, Vector3(0, 0, 17))
	_check(is_instance_valid(reward) and exploration.drops.size() == 96, "Legendary replacement preserves the active cap")
	_check(game.coins == before + compensation, "Replaced inferior equipment pays its full sale value")
	_check(game.notices[-1].contains("+%d petiscos" % compensation), "Replacement compensation is explicit to the player")
	_check(not exploration.can_accept_drop("unknown", {}) and not exploration.can_accept_drop("ammo", {"amount":-1}), "Invalid drop requests fail without mutation")
	await _clear()
	_fill("common", 95)
	var pile: Node3D = exploration.drop_item("currency", {"amount":20}, Vector3(0, 0, 17))
	var merged: Node3D = exploration.drop_item("currency", {"amount":30}, Vector3(1, 0, 17))
	_check(merged == pile and int(pile.payload.amount) == 50 and exploration.drops.size() == 96, "Currency piles merge losslessly at the cap")
	before = game.coins
	exploration.drop_item("weapon", _weapon("legendary"), Vector3(0, 0, 17))
	_check(game.coins == before + 50 and exploration.drops.size() == 96, "Replacing a resource pile preserves its accumulated currency")
	await _clear()

func _check_bidirectional_gates() -> void:
	var initial := {"unlocked_regions":["patio","mercado"]}
	for gates: Array in game.world._gates.values():
		for gate: Dictionary in gates:
			for side: float in [-1.0, 1.0]:
				game.world.import_state(initial)
				await physics_frame
				await physics_frame
				var observer: Vector3 = _standing_point(gate.node.global_position + gate.node.global_basis.z * side * 2.0)
				var poi: Dictionary = {}
				for candidate: Dictionary in game.world.interactables(observer):
					if candidate.id == gate.poi_id: poi = candidate
				_check(not poi.is_empty(), "Both sides expose the same purchasable gate identity: " + gate.poi_id)
				if poi.is_empty(): continue
				_aim(observer, poi.position + Vector3.UP)
				exploration._scan()
				_check(exploration.target.get("poi", {}).get("id") == gate.poi_id, "Physical E targeting works on both gate faces: " + gate.poi_id)
				if gate.poi_id == "porta_quadra_oficina" and side < 0:
					_check(game.world.get_region_id(observer) == "quadra" and not game.world.unlocked_regions.has("quadra"), "The regression starts inside a still-locked Quadra after a fall")
				game.round_number = 25
				game.coins = 1000
				var price: int = exploration._door_terms(poi).cost
				exploration.interact()
				await physics_frame
				await physics_frame
				_check(game.coins == 1000 - price and game.world.unlocked_regions.has(poi.region_id), "Either-side purchase charges the authoritative cost exactly once: " + gate.poi_id)
				_check(gate.collider.disabled, "Either-side purchase opens the actual movement collider: " + gate.poi_id)
				var saved: Dictionary = JSON.parse_string(JSON.stringify(game.world.export_state()))
				game.world.import_state(initial)
				game.world.import_state(saved)
				await physics_frame
				await physics_frame
				_check(game.world.unlocked_regions.has(poi.region_id) and gate.collider.disabled, "An inside or outside purchase remains open after JSON save restoration: " + gate.poi_id)
				exploration.interact()
				_check(game.coins == 1000 - price, "A restored opened gate cannot charge again: " + gate.poi_id)
	game.world.import_state(initial)
	await physics_frame
	await physics_frame
	var gate: Dictionary = game.world._gates.oficina[0]
	var observer := _standing_point(gate.node.global_position + gate.node.global_basis.z * 2.0)
	var loot_position: Vector3 = gate.node.global_position - gate.node.global_basis.z * 0.65
	var loot: Node3D = exploration.drop_item("currency", {"amount":99}, loot_position)
	_aim(observer, loot.global_position + Vector3.UP * 0.3)
	_check(not exploration._visible(loot.global_position + Vector3.UP * 0.3), "Loot pickup LOS still respects a movement gate")
	_check(exploration._visible(loot.global_position + Vector3.UP * 0.3, true), "Door-only interaction LOS can look through the same gate")
	var before: int = game.coins
	exploration.collect_nearby(observer, 8)
	_check(game.coins == before and exploration.drops.has(loot), "Magnet collection cannot steal loot through a closed gate")
	game.world.unlock_region("oficina")
	await physics_frame
	await physics_frame
	exploration.collect_nearby(observer, 8)
	_check(game.coins == before + 99, "Opening the movement gate allows normal nearby collection")
	game.world.import_state(initial)
	game.world.set_boss_arena(true)
	await physics_frame
	await physics_frame
	_check(not game.world.can_purchase_region("quadra"), "An active boss arena cannot be bypassed by purchasing a gate")
	for candidate: Dictionary in game.world.interactables(Vector3(32, 0.25, -34.8)):
		_check(not (candidate.type == "door" and candidate.region_id == "quadra"), "Boss barrier exposes no purchase interaction from inside")
	game.world.set_boss_arena(false)
	await _clear()

func _standing_point(at: Vector3) -> Vector3:
	var hit := game.world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2, at + Vector3.DOWN * 3, 1))
	return Vector3(hit.get("position", at)) + Vector3.UP * 0.25

func _check_hover_context() -> void:
	var at := Vector3(0, 0, 14.6)
	var observer := Vector3(0, 0.25, 17)
	var weapon: Node3D = exploration.drop_item("weapon", _weapon("rare"), at)
	_aim(observer, weapon.global_position + Vector3.UP * .4)
	exploration._scan()
	var context: Dictionary = exploration.get_context()
	_check(context.type == "weapon" and context.comparison.type == "weapon", "A physical weapon target exposes the existing comparison contract and explicit type")
	_check(context.comparison.item == weapon.payload and context.comparison.stats == game.inventory.stats(weapon.payload), "Weapon hover preserves its exact rolled payload and computed stats")
	_check(context.comparison.current == game.player.get_weapon_stats(), "Weapon comparison preserves current player weapon stats")
	_check(context.distance < context.range and context.range == 3.4 and not context.has("node"), "Hover exposes its real reach without leaking scene nodes to the UI")
	context.comparison.item["level"] = 999
	_check(weapon.payload.level != 999, "Formatting a comparison cannot mutate the actual ground weapon")
	await _clear()
	game.player.reserve = 90
	var ammo: Node3D = exploration.drop_item("ammo", {"amount":25}, at)
	_aim(observer, ammo.global_position + Vector3.UP * .4)
	exploration._scan()
	context = exploration.get_context()
	_check(context.type == "ammo" and context.amount == 25 and context.name.contains("25"), "Ammo hover shows the actual pile quantity and name")
	_check(context.comparison.stats.reserve == 90 and context.comparison.stats.max_reserve == 100 and context.comparison.stats.collectable == 10, "Ammo hover reports real reserve capacity and partial pickup size")
	_check(context.description.contains("90 / 100") and ammo.payload.amount == 25, "Ammo preview explains reserve state without consuming the pile")
	exploration.collect_drop(ammo)
	exploration._scan()
	context = exploration.get_context()
	_check(context.amount == 15 and context.comparison.stats.collectable == 0, "Hover updates after partial pickup and reports a full reserve accurately")
	_aim(Vector3(0, .25, 20), ammo.global_position + Vector3.UP * .4)
	exploration._scan()
	_check(exploration.get_context().is_empty(), "The hover card disappears outside physical pickup range")
	await _clear()
	var part := {"uid":"hover-part", "id":"extended_mag", "slot":"magazine", "rarity":"rare", "roll":1.05}
	var attachment: Node3D = exploration.drop_item("attachment", part, at)
	_aim(observer, attachment.global_position + Vector3.UP * .4)
	var before: Dictionary = game.inventory.export_state()
	exploration._scan()
	context = exploration.get_context()
	_check(context.type == "attachment" and context.slot == "magazine" and context.name == "Reserva extra", "Attachment hover resolves the real attachment name and compatible slot")
	_check(context.comparison.item.uid == part.uid and context.comparison.item.roll == part.roll and context.rarity == "rare", "Attachment preview preserves its unique roll and rarity")
	var installed = game.inventory.get_script().new()
	_check(installed.import_state(before) and installed.add_attachment(part) and installed.install(installed.equipped_id, part.uid), "Comparison fixture installs the actual rolled attachment through normal inventory APIs")
	var installed_stats: Dictionary = installed.stats()
	for key: String in ["damage", "fire_rate", "magazine_size", "max_reserve", "reload_time", "critical_chance", "dps"]:
		_check(is_equal_approx(float(context.comparison.stats[key]), float(installed_stats[key])), "Attachment hover matches real installation behavior for " + key)
	_check(context.comparison.current == game.inventory.stats() and game.inventory.export_state() == before, "Attachment comparison leaves the real equipped item and inventory unchanged")
	_check(context.comparison.modifiers.magazine_size > 1.4 and context.comparison.modifiers.reload_time == 1.15, "Attachment hover includes rolled benefits and the real fixed reload penalty")
	await _clear()
	game.round_number = 7
	for id: String in Exploration.POWERUPS:
		var powerup: Node3D = exploration.drop_item("powerup", {"id":id}, at)
		_aim(observer, powerup.global_position + Vector3.UP * .4)
		exploration._scan()
		context = exploration.get_context()
		_check(context.type == "powerup" and context.name == Exploration.POWERUP_NAMES[id] and not str(context.description).is_empty(), "Every power-up provides its actual name and effect description: " + id)
		_check(context.duration == (0 if id in ["nuke", "jackpot"] else 24), "Power-up hover distinguishes instant effects from actual duration: " + id)
		if id == "jackpot": _check(context.amount == 460, "Fortuna hover displays the exact current-round petisco payout")
		if id == "nuke": _check(context.amount == 304, "Pulso Zero hover displays the exact current-round damage")
		await _clear()

func _check_aim_selection() -> void:
	var observer := Vector3(0, .25, 17)
	var farther: Node3D = exploration.drop_item("weapon", _weapon("rare"), Vector3(-.33, 0, 14.3))
	var nearer: Node3D = exploration.drop_item("weapon", _weapon("common"), Vector3(.24, 0, 15.4))
	_aim(observer, farther.global_position + Vector3.UP * .4)
	exploration._scan()
	_check(exploration.target.get("node") == farther, "A nearer weapon cannot steal hover from the farther model under the reticle")
	_check(exploration.get_context().comparison.item.uid == farther.payload.uid, "The card describes the same farther weapon selected by physical aim")
	_aim(observer, nearer.global_position + Vector3.UP * .4)
	exploration._scan()
	_check(exploration.target.get("node") == nearer, "Turning the reticle onto the nearby model changes hover to that exact weapon")
	var ammo: Node3D = exploration.drop_item("ammo", {"amount":34}, Vector3(.65, 0, 14.6))
	_aim(observer, ammo.global_position + Vector3.UP * .4)
	exploration._scan()
	_check(exploration.target.get("node") == ammo and exploration.get_context().amount == 34, "Aim priority selects an ammo model even with two closer overlapping equipment choices")
	_aim(observer, Vector3(-2.5, .4, 14.5))
	exploration._scan()
	_check(exploration.get_context().is_empty(), "Turning away from the actual model silhouettes hides the loot card")
	var before: int = game.inventory.items.size()
	_aim(observer, farther.global_position + Vector3.UP * .4)
	exploration.interact()
	_check(game.inventory.items.size() == before + 1 and not game.inventory.find_item(farther.payload.uid).is_empty(), "E collects the aimed farther item rather than the closer neighbor")
	_check(exploration.drops.has(nearer) and exploration.drops.has(ammo), "Aim pickup leaves the neighboring weapon and ammo untouched")
	await _clear()

func _check_new_drop_settings() -> void:
	game.settings = TestSettings.new()
	var drop: Node3D = exploration.drop_item("weapon", _weapon("legendary"), Vector3(0, 0, 15))
	_check_drop_options(drop, "New reward")
	var state: Dictionary = JSON.parse_string(JSON.stringify(exploration.export_state()))
	game.audio.calls.clear()
	game.ui.messages.clear()
	exploration.import_state(state)
	_check_drop_options(exploration.drops[0], "Restored reward")
	_check(game.audio.calls.is_empty() and game.ui.messages.is_empty(), "Applying settings during restoration never replays legendary feedback")
	await _clear()
	exploration.import_state({"pending_rewards":state.drops})
	exploration._flush_pending()
	_check(exploration.drops.size() == 1 and exploration.pending_drops.is_empty(), "A saved pending reward materializes through the normal drop creation path")
	_check_drop_options(exploration.drops[0], "Materialized pending reward")
	await process_frame
	_check(not exploration.drops[0]._beam.visible and exploration.drops[0]._reduced_flashes, "The first animation frame retains the active low-effects accessibility options")
	game.settings = null
	await _clear()

func _check_drop_options(drop: Node3D, source: String) -> void:
	_check(drop._effects == 0.0 and drop._reduced_flashes, source + " inherits current effects and reduced-flash preferences immediately")
	_check(not drop._beam.visible and not drop._core.visible, source + " has no beam before its first rendered frame")
	_check(drop._model.visible and drop._halo.visible and drop._badge.visible, source + " keeps its item model and rarity identification visible")

func _check_pending_and_restore() -> void:
	_fill("mythic", 96)
	var legendary := _weapon("legendary")
	var result: Node3D = exploration.drop_item("weapon", legendary, Vector3(1, 0, 17))
	_check(result == null and exploration.drops.size() == 96, "A legendary never evicts equal or better equipment")
	_check(exploration.pending_drops.size() == 1 and exploration.pending_drops[0].payload.uid == legendary.uid, "The exact protected reward is banked when the ground cannot accept it")
	exploration.drop_item("powerup", {"id":"jackpot"}, Vector3(2, 0, 17))
	_check(exploration.pending_drops.size() == 2, "Jackpot rewards also survive saturated ground")
	exploration.drops[0].lifetime = 21.25
	var state: Dictionary = JSON.parse_string(JSON.stringify(exploration.export_state()))
	game.ui.messages.clear()
	game.audio.calls.clear()
	game.notices.clear()
	exploration.import_state(state)
	_check(is_equal_approx(float(exploration.drops[0].lifetime), 21.25), "Drop lifetime resumes exactly before the next simulation frame")
	await process_frame
	_check(game.ui.messages.is_empty() and game.audio.calls.is_empty() and game.notices.is_empty(), "Restoring legendary/mythic drops never replays sound, announcements, or notices")
	_check(exploration.drops.size() == 96 and exploration.pending_drops.size() == 2, "Save restoration preserves both active and pending counts")
	_check(exploration.pending_drops[0].payload == state.pending_rewards[0].payload, "Banked weapon rolls and attachments survive JSON restoration exactly")
	var first: Node3D = exploration.drops[0]
	_check(exploration.collect_drop(first), "Collecting one protected floor item succeeds")
	_check(exploration.drops.size() == 96 and exploration.pending_drops.size() == 1, "Freeing a floor slot materializes one pending reward without exceeding 96")
	var found := false
	for drop: Node3D in exploration.drops:
		if str(drop.payload.get("uid", "")) == str(legendary.uid): found = true
	_check(found, "The materialized drop retains the banked legendary UID")
	exploration.collect_drop(exploration.drops[0])
	var jackpot: Node3D
	for drop: Node3D in exploration.drops:
		if drop.kind == "powerup": jackpot = drop
	var coins_before: int = game.coins
	_check(is_instance_valid(jackpot) and exploration.collect_drop(jackpot), "The banked jackpot becomes a collectable power-up")
	_check(game.coins == coins_before + 250 + game.round_number * 30, "Banked jackpot pays the exact original power-up formula")
	await _clear()
	_fill("mythic", 96)
	for index in range(512):
		exploration.pending_drops.append({"kind":"powerup","payload":{"id":"jackpot"},"position":[0,0.07,17],"lifetime":0.0})
	coins_before = game.coins
	exploration.drop_item("powerup", {"id":"jackpot"}, Vector3(0, 0, 17))
	_check(exploration.pending_drops.size() == 512 and exploration.drops.size() == 96, "Both active and data reserve caps remain bounded")
	_check(game.coins == coins_before + 250 + game.round_number * 30, "Extreme reserve overflow still awards jackpot directly")
	var direct := _weapon("legendary")
	exploration.drop_item("weapon", direct, Vector3(0, 0, 17))
	_check(not game.inventory.find_item(direct.uid).is_empty(), "A full reserve delivers protected equipment into available inventory")
	game.inventory.capacity = game.inventory.items.size()
	var converted := _weapon("legendary")
	var expected: int = game.inventory.stats(converted).value
	coins_before = game.coins
	exploration.drop_item("weapon", converted, Vector3(0, 0, 17))
	_check(game.coins == coins_before + expected and game.notices[-1].contains("convertida"), "Only total storage saturation converts the incoming reward transparently to its full value")
	game.inventory.capacity = 24
	await _clear()

func _check_pickup_feedback() -> void:
	_aim(Vector3(0, 0.25, 17), Vector3(0, 0.4, 16))
	game.notices.clear()
	game.audio.calls.clear()
	var before: int = game.coins
	for index in range(20):
		exploration.drop_item("currency", {"amount":5}, Vector3((index % 5) * 0.14, 0, 16.4 - (index / 5) * 0.13))
	exploration.collect_nearby(game.player.global_position, 3)
	_check(game.coins == before + 100 and exploration.drops.is_empty(), "Nearby pickups preserve every coin in a burst")
	_check(game.notices.is_empty() and game.audio.calls.size() <= 1, "Currency bursts do not spam UI messages or overlapping pickup sounds")
	game.player.reserve = 90
	var ammo: Node3D = exploration.drop_item("ammo", {"amount":25}, Vector3(0, 0, 16))
	_check(exploration.collect_drop(ammo) and game.player.reserve == 100, "Ammo fills only available reserve space")
	_check(is_instance_valid(ammo) and int(ammo.payload.amount) == 15 and exploration.drops.has(ammo), "Unused ammo remains in its ground pile")
	_check(not exploration.collect_drop(ammo) and int(ammo.payload.amount) == 15, "Full reserve leaves the ammo pickup unchanged")
	game.player.reserve = 50
	_check(exploration.collect_drop(ammo) and game.player.reserve == 65 and exploration.drops.is_empty(), "Remaining ammo can be collected later without loss")
	_check(game.notices.is_empty(), "Automatic ammo collection does not create notification spam")
	await _clear()

func _check_challenge_and_ground() -> void:
	game.round_number = 7
	game.ui.messages.clear()
	exploration.challenge = {"region":"patio","kills":11,"target":12}
	var enemy := Node3D.new()
	game.add_child(enemy)
	enemy.global_position = Vector3(0, 0.25, 17)
	var before: int = game.coins
	exploration.on_kill(enemy)
	_check(game.coins == before + 475 and exploration.challenge.is_empty(), "Challenge pays 300 + 25 per current round exactly once")
	_check(game.ui.messages[-1][1].contains("+475 petiscos"), "Challenge completion text matches the actual payment")
	_check(exploration.drops.size() == 1 and exploration.drops[0].payload.rarity == "epic", "Challenge equipment reward remains guaranteed epic")
	exploration.on_kill(enemy)
	_check(game.coins == before + 475, "Subsequent kills cannot award a completed challenge again")
	enemy.queue_free()
	await _clear()
	var chest_top: Node3D = exploration.drop_item("weapon", _weapon("rare"), Vector3(4.9, 0.2, 19.2))
	_check(chest_top.global_position.y > 0.65, "Loot created over a real chest settles on its upper surface instead of inside its collider")
	_aim(Vector3(4.9, 0.25, 17.2), chest_top.global_position + Vector3.UP * 0.4)
	_check(exploration._visible(chest_top.global_position + Vector3.UP * 0.4), "Loot on top of a real prop remains reachable by a physical view ray")
	await _clear()

func _aim(at: Vector3, point: Vector3) -> void:
	game.player.global_position = at
	game.player.camera.position = Vector3(0, 1.55, 0)
	game.player.camera.look_at(point)

func _check_expansion_challenges() -> void:
	for id: String in ["desafio_nascente", "desafio_cinema"]:
		var poi: Dictionary = {}
		for candidate: Dictionary in game.world.points_of_interest:
			if candidate.id == id: poi = candidate
		game.world.unlock_region(poi.region_id)
		await physics_frame
		await physics_frame
		_aim(poi.position + Vector3(0, 0.05, 2), poi.position + Vector3.UP)
		exploration.interact()
		_check(exploration.challenge.get("id", "") == id, "Authored district challenge starts from physical E interaction: " + id)
		_check(exploration.challenge.get("name", "") == str(poi.name).to_upper() and exploration.challenge.get("target", 0) == poi.target and exploration.challenge.get("remaining", 0) == poi.duration, "Challenge uses its authored name, goal and time")
		var enemy := Node3D.new()
		game.add_child(enemy)
		enemy.global_position = Vector3.ZERO
		exploration.on_kill(enemy)
		_check(exploration.challenge.get("kills", -1) == 0, "Kills outside the district do not complete its challenge")
		enemy.global_position = poi.position
		var coins_before := game.coins
		for index in range(int(poi.target)): exploration.on_kill(enemy)
		_check(exploration.challenge.is_empty() and game.coins > coins_before, "Completing the local objective pays run currency")
		_check(exploration.drops.size() == 1 and exploration.drops[0].payload.rarity == "epic", "The new objective produces a real epic weapon drop")
		enemy.queue_free()
		await _clear()

func _weapon(rarity: String) -> Dictionary:
	item_seed += 1
	return Loot.make_weapon("biscuit", 4, rarity, item_seed)

func _fill(rarity: String, count: int) -> void:
	for index in range(count):
		exploration._create_drop("weapon", _weapon(rarity), Vector3(-2 + (index % 8) * 0.3, 0, 12 + (index / 8) * 0.25), true)

func _clear() -> void:
	exploration.import_state({})
	await process_frame

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)

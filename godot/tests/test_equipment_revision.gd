extends SceneTree

const Inventory = preload("res://scripts/inventory.gd")
const Loot = preload("res://data/loot_data.gd")
const Save = preload("res://scripts/save_manager.gd")
const Settings = preload("res://scripts/game_settings.gd")
var checks := 0
var failures: Array[String] = []
var game: Node

class BlastTarget:
	extends Node3D
	var dead := false
	var health := 1000.0
	func take_damage(amount: float, _zone: String, _source: String) -> void: health -= amount
	func apply_status(_element: String, _potency: float, _duration: float) -> void: pass

func _initialize() -> void: call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var inventory := Inventory.new()
	inventory.create_starter()
	for i: int in range(5): inventory.add_item(Loot.make_weapon("boardwalk", 3, "rare", 891+i))
	check(inventory.weapon_slots.size() == 4 and not inventory.weapon_slots.has(""), "four distinct quick slots auto-fill")
	check(inventory.assign_slot(inventory.items[5].uid, 2), "backpack weapon assigned to a specific slot")
	check(inventory.select_slot(2) and inventory.equipped_id == inventory.items[5].uid, "quick selection uses the loadout, not backpack order")
	inventory.equipped().magazine = 3
	inventory.equipped().reserve = 17
	inventory.capacity = inventory.items.size()
	var old := inventory.equipped().duplicate(true)
	var fresh := Loot.make_weapon("hammer", 5, "epic", 5001)
	var dropped := inventory.swap_held(fresh)
	check(dropped == old and inventory.equipped_id == fresh.uid and inventory.items.size() == inventory.capacity, "full backpack swap is atomic and preserves outgoing ammo")
	var before := inventory.export_state()
	check(inventory.swap_held(inventory.items[0]).is_empty() and inventory.export_state() == before, "duplicate pickup cannot destroy equipped weapon")
	var restored := Inventory.new()
	check(restored.import_state(JSON.parse_string(JSON.stringify(before))), "JSON restores complete loadout and utilities")
	check(restored.weapon_slots == inventory.weapon_slots and restored.supplies == inventory.supplies, "equipment survives round trip")
	var invalid := before.duplicate(true)
	var restored_before := restored.export_state()
	invalid.weapon_slots[1] = invalid.weapon_slots[0]
	check(not restored.import_state(invalid) and restored.export_state() == restored_before, "duplicate quick slots rejected transactionally")
	invalid = before.duplicate(true)
	invalid.supplies.grenade = 7
	check(not restored.import_state(invalid), "excess grenade charges rejected")
	invalid = before.duplicate(true)
	invalid.module_id = "guardian"
	check(not restored.import_state(invalid), "unowned equipment rejected")
	var legacy := before.duplicate(true)
	legacy.version = 1
	for id: String in ["weapon_slots","active_weapon_slot","supplies","grenade_id","module_id","owned_grenades","owned_modules"]: legacy.erase(id)
	check(restored.import_state(legacy) and restored.equipped_id == before.equipped_id, "old native saves migrate to four slots without losing active item")
	var mesh := preload("res://scripts/weapon_geometry.gd").chamfer_box(Vector3.ONE)
	var arrays := mesh.surface_get_arrays(0)
	for i: int in range(arrays[Mesh.ARRAY_VERTEX].size()):
		check(Vector3(arrays[Mesh.ARRAY_VERTEX][i]).dot(arrays[Mesh.ARRAY_NORMAL][i]) > 0, "machined weapon surface faces outwards")
	var rng := RandomNumberGenerator.new()
	rng.seed = 754876
	var rare_count := 0
	var mythic_count := 0
	for i: int in range(50000):
		var rarity := Loot.roll_rarity(rng, 4)
		if rarity == "legendary": rare_count += 1
		if rarity == "mythic": mythic_count += 1
	check(rare_count > 0 and rare_count < 650 and mythic_count > 0 and mythic_count < 80, "even maximum luck keeps legendary below 1.3% and mythic below .16% per natural weapon")
	game = load("res://scenes/main.tscn").instantiate()
	var path := "user://equipment_test_%d" % OS.get_process_id()
	game.save_manager = Save.new(path + "/run")
	game._profile_store = Save.new(path + "/profile")
	game.settings = Settings.new(path + "/settings")
	game.settings.set_value("master", 0)
	game.settings.save_settings()
	root.add_child(game)
	game.start_run("normal", false, 1)
	game.set_process(false)
	game.exploration.set_process(false)
	game.companion.set_physics_process(false)
	for frame: int in range(40): await physics_frame
	game.player.set_physics_process(false)
	await _test_runtime()
	for id: String in ["tidecaller","night_express","final_frame"]:
		var item := Loot.make_weapon(id,12,"legendary",1543)
		var stats: Dictionary = game.inventory.stats(item)
		var view: Node3D = game.player.weapon_view
		view.set_weapon(id,stats)
		var rest: Vector3 = view.magazine_mesh.rotation
		var visible_before: bool = view.magazine_mesh.visible
		view.animate_view(0.1,false,0,false,0,0.35,true)
		view.animate_view(0.1,false,0,false,0,0,false)
		check(view.magazine_mesh.rotation.is_equal_approx(rest) and view.magazine_mesh.visible==visible_before,"Reload preserves unique magazine orientation and visibility: "+id)
		check(not game.buy_weapon(id),"Exclusive legendary cannot be acquired from ordinary weapon catalogue: "+id)
	await _test_grenades_and_creatures()
	game.running = false
	paused = false
	await game.audio.shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	print("EQUIPMENT REVISION: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_runtime() -> void:
	game.coins = 20000
	for i: int in range(4): game.inventory.add_item(Loot.make_weapon("boardwalk", 4, "rare", 991+i))
	var start_coins: int = game.coins
	game.buy_equipment("module", "assault")
	check(game.inventory.module_id == "assault" and game.coins == start_coins - 450, "module purchase uses run economy")
	check(game.get_player_modifiers().fire_rate > 1 and game.get_player_modifiers().reload < 1, "module bonus and tradeoff both affect combat")
	start_coins = game.coins
	game.buy_equipment("module", "assault")
	check(game.coins == start_coins, "owned module equips for free")
	game.player.health = 20
	var charges: int = game.inventory.supplies.medkit
	check(game.use_supply("medkit") and game.player.health == 65 and game.inventory.supplies.medkit == charges-1, "healing is finite and matches the utility card")
	check(not game.use_supply("medkit"), "empty supply cannot activate")
	game.open_weapon_wheel()
	check(game.paused and game.weapon_wheel.visible and paused, "holding T opens and pauses the selection wheel")
	game.weapon_wheel.selected = 2
	game.close_weapon_wheel(true)
	check(not game.paused and game.inventory.active_weapon_slot == 2 and not game.weapon_wheel.visible, "release equips selected quick slot and resumes")
	game.open_weapon_wheel()
	game.weapon_wheel.selected = 3
	game.close_weapon_wheel(false)
	check(game.inventory.active_weapon_slot == 2, "cancel leaves active weapon unchanged")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_T
	key.pressed = true
	game._input(key)
	check(game.paused and game.weapon_wheel.selected == -1, "physical T starts with a neutral selection")
	key.pressed = false
	game._input(key)
	check(not game.paused and game.inventory.active_weapon_slot == 2, "release in the center preserves active equipment")
	key.pressed = true
	game._input(key)
	game.weapon_wheel.selected = 3
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(game.paused and game._menu_kind != "wheel" and game.inventory.active_weapon_slot == 2, "focus loss cancels the wheel and pauses safely")
	game.resume_game()
	check(game.player.set_crouched(true), "crouch reduces actual body collision")
	check(game.player.get_node("BodyCollider").shape.height < 1, "crouched body fits low cover")
	var ceiling := StaticBody3D.new()
	ceiling.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2,0.15,2)
	shape.shape = box
	ceiling.add_child(shape)
	game.add_child(ceiling)
	ceiling.global_position = game.player.global_position + Vector3.UP * 1.3
	await physics_frame
	await physics_frame
	check(not game.player.set_crouched(false), "cannot stand through a low ceiling")
	ceiling.queue_free()
	await physics_frame
	await physics_frame
	check(game.player.set_crouched(false), "can stand again when overhead space clears")
	check(game.player.start_dive(Vector3.FORWARD), "grounded player can dive")
	check(not game.player.start_dive(Vector3.FORWARD), "dive cannot be spammed")
	game.player.dive_remaining = 0
	game.player.set_crouched(false)
	var at: Vector3 = game.player.global_position + Vector3(0,0,-2)
	var drop: Node3D = game.exploration.drop_item("weapon", Loot.make_weapon("hammer",5,"epic",4437),at,true)
	await physics_frame
	game.player.camera.look_at(drop.global_position + Vector3.UP * 0.4)
	var previous_uid: String = game.inventory.equipped_id
	var new_uid: String = drop.payload.uid
	game.inventory.capacity = game.inventory.items.size()
	check(game.exploration.swap_ground_weapon(), "F swaps the targeted ground weapon with a full backpack")
	check(game.inventory.equipped_id == new_uid and game.exploration.drops.any(func(value: Node3D) -> bool: return value.payload.get("uid") == previous_uid), "swap leaves the exact held instance on the floor")
	game.world.set_event("blackout")
	check(game.world._environment.ambient_light_energy < 0.01 and game.world._moon.light_energy < 0.01, "blackout cuts global lighting")
	check(game.world._lights.all(func(light: OmniLight3D) -> bool: return light.light_energy == 0), "blackout cuts all world street/interior lamps")
	game.world.apply_graphics(game.settings.data)
	check(game.world._environment.ambient_light_energy < 0.01, "graphics settings cannot silently undo blackout")
	game.world.set_event("")
	check(game.world._environment.ambient_light_energy < 0.2 and game.world._environment.ambient_light_energy > 0.1, "normal night stays darker but recovers after event")
	for branch: String in ["elemental","control","resupply","bond"]:
		check(game.companion.upgrade_branch(branch), "new dog branch can be purchased: " + branch)
	check(game.companion.choose_element("cryo") and game.companion.element == "cryo", "dog element is an actual selected loadout option")
	var state: Dictionary = game.snapshot_state()
	check(game.apply_snapshot(state), "complete run with new equipment, movement and dog traits resumes")

func _test_grenades_and_creatures() -> void:
	game.resume_game()
	game.player.set_physics_process(false)
	game.companion.set_physics_process(false)
	game.player.global_position = Vector3(900, 20, 900)
	var charges: int = game.inventory.supplies.grenade
	check(game.use_supply("grenade") and game.inventory.supplies.grenade == charges - 1, "a physical grenade consumes exactly one charge")
	check(not game.use_supply("grenade") and game.inventory.supplies.grenade == charges - 1, "grenade cooldown rejects repeated input without consuming charges")
	var grenade: Node3D = get_first_node_in_group("run_grenades")
	if not is_instance_valid(grenade): return
	grenade.set_physics_process(false)
	grenade.global_position = Vector3(900, 21, 900)
	var exposed := BlastTarget.new()
	game.add_child(exposed)
	exposed.global_position = Vector3(902,20.2,900)
	var covered := BlastTarget.new()
	game.add_child(covered)
	covered.global_position = Vector3(898,20.2,900)
	game.enemies.append(exposed)
	game.enemies.append(covered)
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.3,4,4)
	collider.shape = shape
	wall.add_child(collider)
	game.add_child(wall)
	wall.global_position = Vector3(899,21,900)
	await physics_frame
	await physics_frame
	grenade.detonate()
	check(exposed.health < 1000 and covered.health == 1000, "grenade splash damages exposed enemies but respects solid cover")
	var health := exposed.health
	grenade.detonate()
	check(exposed.health == health, "a grenade cannot apply its explosion twice")
	await create_timer(0.4).timeout
	check(get_nodes_in_group("run_grenades").is_empty(), "grenade geometry and effects retire after detonation")
	for target: Node in [exposed,covered]:
		game.enemies.erase(target)
		target.queue_free()
	wall.queue_free()
	for kind: String in ["grunt","runner","tank","exploder","spitter","screamer","hunter","armored","parasite","summoner","stealth"]:
		var enemy := preload("res://scripts/enemy.gd").new()
		enemy.setup(game, kind, 1)
		game.add_child(enemy)
		enemy.global_position = Vector3(1000,20,1000)
		enemy.set_physics_process(false)
		await physics_frame
		await physics_frame
		var head: Area3D = enemy.get_node("Hit_head")
		var ray := PhysicsRayQueryParameters3D.create(head.global_position + Vector3.FORWARD * 3, head.global_position, 8)
		ray.collide_with_areas = true
		var hit := enemy.get_world_3d().direct_space_state.intersect_ray(ray)
		check(not hit.is_empty() and hit.collider.get_meta("zone", "") == "head", "visible head of " + kind + " has a matching ballistic hit region")
		check(String(enemy._visual.root.name).begins_with("Creature_"), kind + " uses a nonhuman silhouette")
		enemy.queue_free()
		await physics_frame
	for cue: String in ["door_unlock","weapon_drop","loot_legendary","loot_mythic","step_run","step_grass","dive","land","mag_out","mag_in","chamber","explosion"]:
		check(game.audio._streams.has(cue) and game.audio._streams[cue].get_length() > 0.05, "original cue is available: " + cue)
	check(game.audio._streams.loot_mythic.get_length() > game.audio._streams.loot_legendary.get_length() and game.audio._streams.loot_legendary.get_length() > game.audio._streams.weapon_drop.get_length(), "rare drop cues have progressively longer distinct signatures")

extends SceneTree
## Native integration regression: real menu/coordinator/director/actors/world/loot.
## Only director delays and live actor movement are controlled for deterministic QA.
## Save/settings/profile stores are redirected before _ready, never user data.
const MainScene = preload("res://scenes/main.tscn")
const Saves = preload("res://scripts/save_manager.gd")
const Settings = preload("res://scripts/game_settings.gd")
const Loot = preload("res://data/loot_data.gd")
const Data = preload("res://data/game_data.gd")
const Validator = preload("res://scripts/snapshot_validator.gd")
var _game: Node3D
var _directory: String
var _checks: int = 0
var _failures: Array[String] = []
var _finished: bool = false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(90.0, true).timeout.connect(_timeout)
	_directory = "user://integration_expedition_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_game = MainScene.instantiate()
	_game.save_manager = Saves.new(_directory + "/saves")
	_game._profile_store = Saves.new(_directory + "/profile")
	_game.settings = Settings.new(_directory + "/settings")
	_game.settings.set_value("fps_limit", 0)
	_game.settings.set_value("master", 0.0)
	_game.settings.set_value("reduced_flashes", true)
	_game.settings.save_settings()
	root.add_child(_game)
	current_scene = _game
	_game.set_process(false)
	for frame in range(480):
		if _game.world.navigation_ready:
			break
		await process_frame
	_check(_game.world.navigation_ready, "Night districts bake real native navigation")
	if not _game.world.navigation_ready:
		await _finish()
		return
	_test_menu_and_start()
	_test_combat_wave()
	await _test_purchases_and_pause()
	_test_powerups()
	await _test_snapshot()
	_test_legacy_enemy_snapshot()
	_test_reward_budget()
	_test_rejected_snapshots()
	_test_safe_resume()
	_test_game_over()
	await _finish()

func _test_menu_and_start() -> void:
	_check(not _game.running and _game.paused, "Main menu opens without simulating a live run")
	_check(_game.player.camera != root.get_camera_3d(), "The main menu has a cinematic camera")
	_check(_game.inventory.items.size() == 1 and not _game.save_manager.has_save(), "Menu starts with starter preview and empty isolated slots")
	_check(InputMap.has_action("shop") and InputMap.has_action("flashlight") and InputMap.has_action("inventory"), "Native input includes upgrade menu, flashlight and inventory")
	_game.start_run("hard", true, 1)
	_freeze_actors()
	_check(_game.running and not _game.paused and not paused, "Starting enters an unpaused expedition")
	_check(_game.difficulty_id == "hard" and _game.chaos_active, "Difficulty and Chaos reach the live run")
	_check(_game.director.difficulty_id == "hard" and _game.director.chaos_level == 1, "Director uses the selected difficulty and Chaos")
	_check(_game.coins == 250 and _game.round_number == 1 and _game.active_slot == 1, "Starting balance, round and chosen save slot initialize together")
	_check(_game.player.camera == root.get_camera_3d() and not _game.player.third_person, "Run begins in first person")
	_check(_game.inventory.equipped_id == _game.player.active_item_uid, "Player and inventory share equipped weapon identity")
	_check(_game.player.magazine == int(_game.player.get_weapon_stats().magazine_size) and _game.player.reserve > 0, "Starter has a finite loaded magazine and reserve")
	_game.start_run("easy", false, 2)
	_check(_game.difficulty_id == "hard" and _game.active_slot == 1, "Duplicate start cannot replace a running expedition")
	_game.director.phase_time = 0.0
	_game._process(0.01)
	_check(_game.phase == "combat" and _game.wave_total >= 6, "Preparation enters the real first wave")

func _test_combat_wave() -> void:
	_game.director._spawn_clock = 0.0
	_game._process(0.01)
	_check(_game.enemies.size() == 1 and _game.wave_spawned == 1, "Coordinator instantiates an actual enemy from director action")
	if _game.enemies.is_empty():
		return
	var first: CharacterBody3D = _game.enemies[0]
	first.set_physics_process(false)
	_check(first.is_in_group("meyui_enemies") and first._hit_areas.size() >= 3, "Enemy participates in real hit detection groups and regions")
	_check(first.global_position.distance_to(_game.player.global_position) > 9.0, "Initial enemy spawns outside the immediate player area")
	var before_health: float = first.health
	var before_coins: int = _game.coins
	first.take_damage(16.0, "body", "player")
	_check(first.health < before_health and _game.stats.damage >= 16, "Damage is immediate and contributes to run statistics")
	_check(_game.coins > before_coins, "Damage contributes to the run economy")
	first.take_damage(100000.0, "body", "player")
	_check(first.dead and _game.kills == 1 and _game.wave_killed == 1, "A kill removes its live wave slot exactly once")
	_check(_game.exploration.drops.size() >= 1, "First kill guarantees a meaningful ground-loot reward")
	var after_reward: int = _game.coins
	_game.on_enemy_killed(first, 100, "player")
	_check(_game.coins == after_reward and _game.kills == 1, "Duplicate kill callbacks cannot duplicate rewards")
	var count: int = 0
	while _game.phase == "combat" and count < 60:
		_game.director._spawn_clock = 0.0
		_game._process(0.02)
		for enemy: Node in _game.enemies.duplicate():
			enemy.set_physics_process(false)
			enemy.take_damage(100000.0, "body", "player")
		count += 1
	_check(_game.phase == "rest" and _game.enemies.is_empty(), "The final real kill transitions the director into strategic rest")
	_check(_game.wave_spawned == _game.wave_total and _game.wave_killed == _game.wave_total, "Completed wave counters remain consistent")
	_check(_game._save_pending or _game.save_manager.has_save(), "Round completion schedules or commits an autosave")
	var coins: int = _game.coins
	_game._process(0.1)
	_check(_game.coins == coins, "Round completion reward is not repeated every frame")
	_game.director.phase_time = 0.0
	_game._process(0.01)
	_check(_game.round_number == 2 and _game.phase == "combat" and _game.wave_killed == 0, "The next round opens with fresh counters")

func _test_purchases_and_pause() -> void:
	_game.player.magazine = 3
	_game.player.reserve = 20
	_game.player._save_ammo()
	_check(_game.player.start_reload(), "Real reload begins before opening the pause menu")
	_game.player.set_physics_process(true)
	_game.pause_game()
	_check(_game.paused and paused, "Pause freezes the native scene tree")
	var remaining: float = _game.director.phase_time
	var play_time: float = _game.elapsed
	_game._process(2.0)
	_check(_game.elapsed == play_time and _game.director.phase_time == remaining, "Paused menus do not advance survival time")
	var reload_time: float = _game.player.reload_remaining
	for frame in range(3):
		await physics_frame
	_check(is_equal_approx(_game.player.reload_remaining, reload_time), "Native pause preserves the remaining reload duration")
	_game.resume_game()
	for frame in range(3):
		await physics_frame
	_check(_game.player.reload_remaining < reload_time, "Native reload resumes after leaving pause")
	_game.pause_game()
	_game.player.set_physics_process(false)
	_check(not _game.player.shoot(), "Weapons cannot shoot through paused menus")
	_game.open_shop()
	_check(_game.paused and _game._menu_kind == "inventory", "Upgrade menu uses the shared inventory and pauses combat")
	_game.coins = 0
	var count: int = _game.inventory.items.size()
	_game.buy_weapon("boardwalk")
	_check(_game.inventory.items.size() == count and _game.coins == 0, "Unaffordable weapon purchase has no partial effect")
	_game.coins = 1000000
	_game.buy_weapon("hammer")
	_check(_game.inventory.items.size() == count, "Round lock prevents premature heavy weapon purchase")
	_game.buy_weapon("boardwalk")
	_check(_game.inventory.items.size() == count + 1 and _game.player.weapon_id == "boardwalk", "Unlocked purchase creates and equips a rolled weapon")
	var weapon_uid: String = _game.inventory.equipped_id
	_check(_game.inventory.find_item(weapon_uid).rarity == "uncommon", "Bought weapon retains its instance rarity")
	var before_damage: float = _game.player.get_weapon_stats().damage
	var before_coins: int = _game.coins
	_game.upgrade_weapon(weapon_uid)
	_check(_game.player.get_weapon_stats().damage > before_damage and _game.coins < before_coins, "Forge spends money and increases actual equipped damage")
	_game.inventory.find_item(weapon_uid).upgrade_level = 1000
	before_damage = _game.player.get_weapon_stats().damage
	_game.coins = 2000000000
	_game.upgrade_weapon(weapon_uid)
	_check(_game.inventory.find_item(weapon_uid).upgrade_level == 1001 and _game.player.get_weapon_stats().damage > before_damage, "Forge continues beyond the previous end of progression")
	_game.buy_attachment("ember_barrel")
	var part: Dictionary = _game.inventory.attachments.back()
	_game.install_attachment(weapon_uid, part.uid)
	_check(_game.inventory.equipped().attachments.has("barrel") and _game.player.get_weapon_stats().modifiers.has("burn"), "Installed barrel changes weapon behavior through live combat stats")
	_game.uninstall_attachment(weapon_uid, "barrel")
	_check(not _game.inventory.equipped().attachments.has("barrel"), "Removing a part updates the weapon and returns it to inventory")
	_game.install_attachment(weapon_uid, part.uid)
	var before_element: String = _game.inventory.equipped().element
	_game.reroll_weapon(weapon_uid, "element")
	_check(_game.inventory.equipped().element != before_element and _game.inventory.equipped().reroll_count == 1, "Element reroll changes its rolled item and tracks increasing future cost")
	var before_mod: float = _game.get_player_modifiers().damage
	_game.buy_perk("force")
	_check(_game.get_player_modifiers().damage > before_mod, "Character perk joins the same weapon-damage calculation")
	var max_health: float = _game.player.max_health
	_game.buy_perk("heart")
	_check(_game.player.max_health > max_health, "Survival perk updates actual maximum health")
	var dog_level: int = _game.companion.level
	_game.upgrade_dog("attack")
	_check(_game.companion.level > dog_level, "Companion branch purchase changes its progression")
	_game.player.magazine = 2
	_game.player.reserve = 0
	before_coins = _game.coins
	_game.refill_ammo()
	_check(_game.player.reserve > 0 and _game.coins < before_coins, "Ammunition is a real paid resource")
	_check(not _game.player.reloading, "Paid refill ends a suspended reload consistently")
	before_coins = _game.coins
	_game.refill_ammo()
	_check(_game.coins == before_coins, "Buying ammunition while already full is free of accidental charges")
	_game.resume_game()
	_freeze_actors()
	_check(not _game.paused and not paused and _game.player.camera == root.get_camera_3d(), "Leaving inventory resumes the same character and perspective")

func _test_powerups() -> void:
	var baseline: float = _game.get_player_modifiers().damage
	_game.activate_powerup("double_damage")
	_check(is_equal_approx(_game.get_player_modifiers().damage, baseline * 2.0), "Temporary powerup multiplies the current build rather than replacing it")
	_game.activate_powerup("infinite_ammo")
	_check(_game.get_player_modifiers().infinite_ammo, "Temporary infinite ammo is an explicit bounded powerup")
	_game.active_powerups.double_damage = 0.01
	_game.active_powerups.infinite_ammo = 0.01
	_game._process(0.02)
	_check(not _game.active_powerups.has("double_damage") and not _game.get_player_modifiers().infinite_ammo, "Temporary effects expire without permanent stat inflation")
	var coins: int = _game.coins
	_game.activate_powerup("jackpot")
	_check(_game.coins > coins and not _game.active_powerups.has("jackpot"), "Instant currency powerup rewards once without a lingering modifier")

func _test_snapshot() -> void:
	_game.pause_game()
	_game.director.phase = "combat"
	_game.director.round_number = 9
	_game.director.wave_total = 24
	_game.director.spawned = _game.enemies.size()
	_game.director.killed = 0
	_game._sync_director()
	var actions: Array = _game.director.force_event("blackout")
	for action: Dictionary in actions:
		_game._director_action(action)
	_game.director.active_event.remaining = 19.25
	if _game.enemies.is_empty():
		_game._spawn_enemy_data({"kind":"runner", "position":_game.player.global_position + Vector3(3, 0, -5), "wave_enemy":true})
		_game.director.spawned = 1
	_game._sync_director()
	var enemy: Node3D = _game.enemies[0]
	enemy.health *= 0.65
	enemy._dog_retaliation_cooldown = 2.75
	enemy.apply_status("cryo", 2.0, 8.0)
	enemy.apply_status("frenzy", 0.2, 6.0)
	_game.player.magazine = 3
	_game.player.reserve = 37
	_game.player.health = 71.0
	_game.player._heat = 0.75
	_game.player._trigger_counts[_game.player.active_item_uid] = 14
	_game.player._frenzy_remaining = 2.5
	_game.player._last_combat_stats = {"damage": 32.0, "modifiers":["burn", "third_strike"]}
	_game.player.reloading = true
	_game.player.reload_duration = 1.2
	_game.player.reload_remaining = 0.4
	_game.companion._heal_timer = -123.45
	_game.elapsed = 937.5
	_game.coins = 34781
	_game.exploration.discovered = ["patio", "mercado"]
	_game.exploration.used_pois = {"integration_chest":9}
	_game.exploration.bosses_defeated = ["integration_old_boss"]
	_game.active_powerups.frenzy = 11.25
	var ground_item: Dictionary = Loot.make_weapon("hammer", 9, "legendary", 913752)
	_game.exploration.drop_item("weapon", ground_item, _game.player.global_position + Vector3(2, 0, 1))
	_game.exploration.drop_item("attachment", Loot.roll_attachment(_game.rng, 2.0, "sight"), _game.player.global_position + Vector3(-2, 0, 1))
	var queued_item: Dictionary = Loot.make_weapon("biscuit", 9, "legendary", 975311)
	_game.exploration.pending_drops.append({"kind":"weapon","payload":queued_item,"position":[0,0.07,17],"lifetime":11.0})
	_game.exploration.pending_drops.append({"kind":"powerup","payload":{"id":"jackpot"},"position":[1,0.07,17],"lifetime":0.0})
	_game.start_boss({"id":"integration_boss", "region_id":"quadra", "position":_game.player.global_position + Vector3(0, 0, -10)})
	_freeze_actors()
	var snapshot: Dictionary = _game.snapshot_state()
	_check(snapshot.enemies.size() == _game.enemies.size(), "Snapshot includes every living ordinary and optional boss actor")
	_check(snapshot.inventory.items.size() == _game.inventory.items.size() and snapshot.player.magazine == 3, "Snapshot captures independent weapon instances and current magazine")
	_check(snapshot.exploration.drops.size() == _game.exploration.drops.size(), "Uncollected rolled equipment is included in the save")
	var saved: bool = _game.save_game(1)
	_check(saved, "Full live expedition serializes through the real atomic slot manager")
	if not saved:
		printerr("Full save failure: ", _game.save_manager.save_slot(1, snapshot))
		printerr("Top-level run validation: ", _game.save_manager._valid_state(snapshot))
		for key in snapshot:
			_game.save_manager._node_count = 0
			if not _game.save_manager._safe_json(snapshot[key]):
				printerr("Invalid section: ", key)
		_print_non_json(snapshot, "snapshot")
		return
	var loaded: Dictionary = _game.save_manager.load_slot(1)
	_check(loaded.ok and loaded.metadata.round == 9 and loaded.metadata.dog_level == _game.companion.level, "Slot metadata identifies the real saved expedition")
	_check(loaded.state.player.magazine == 3 and loaded.state.player.reserve == 37, "Disk save preserves limited ammunition")
	_check(loaded.state.inventory.items.size() >= 2 and loaded.state.perks.levels.force == 1, "Disk save preserves equipment and character build")
	var saved_uid: String = _game.inventory.equipped_id
	_game.coins = 1
	_game.player.health = 1
	_game.inventory.equipped().magazine = 0
	_game.progression.levels.force = 50
	_check(_game.apply_snapshot(loaded.state), "A validated real checkpoint can reconstruct a running scene")
	_freeze_actors()
	_check(_game.coins == 34781 and _game.elapsed == 937.5 and _game.round_number == 9, "Restoring recovers run economy, time and round")
	_check(_game.inventory.equipped_id == saved_uid and _game.player.active_item_uid == saved_uid, "Restored player uses the exact equipped item instance")
	_check(_game.player.magazine == 3 and _game.player.reserve == 37 and _game.player.health == 71, "Health and ammunition restore without free refills")
	_check(_game.player.reloading and is_equal_approx(_game.player.reload_remaining, 0.4), "An in-progress reload resumes from its exact saved remaining duration")
	_check(_game.player._heat == 0.75 and _game.player._trigger_counts.get(saved_uid) == 14 and _game.player._frenzy_remaining == 2.5, "Heat, per-weapon trigger rhythm and kill-frenzy duration survive together")
	_check(_game.enemies[0].statuses.has("frenzy"), "A Screamer's legitimate frenzy status does not invalidate the save")
	_check(is_equal_approx(_game.enemies[0]._dog_retaliation_cooldown, 2.75), "Enemy retaliation cooldown resumes with the same remaining time")
	_check(is_equal_approx(_game.enemies[0].export_state().damage, snapshot.enemies[0].damage), "Current-balance enemy damage does not reset or double during continuation")
	_check(_game.progression.levels.force == 1 and _game.inventory.equipped().upgrade_level == 1001, "Run perks and unlimited weapon refinements survive together")
	_check(_game.inventory.equipped().attachments.barrel.id == "ember_barrel", "Fitted behavior-changing attachment survives continuation")
	_check(_game.enemies.size() == snapshot.enemies.size() and _game.director.spawned == snapshot.director.spawned, "Live enemies and director slots restore consistently")
	_check(_game.director.active_event.id == "blackout" and is_equal_approx(_game.director.active_event.remaining, 19.25), "Active event resumes from its saved remaining time")
	_check(is_equal_approx(_game.active_powerups.frenzy, 11.25), "Temporary build buff duration survives continuation")
	_check(_game.exploration.used_pois.integration_chest == 9 and _game.exploration.bosses_defeated.has("integration_old_boss"), "Collected chest and completed boss history cannot reroll by reloading")
	_check(_game.boss_zone.id == "integration_boss", "Active boss arena lock survives loading")
	_check(_game.exploration.drops.size() == snapshot.exploration.drops.size(), "Restore does not duplicate or lose ground loot")
	_check(_game.exploration.pending_drops.size() == 2 and _game.exploration.pending_drops[0].payload.uid == queued_item.uid, "A protected queued legendary retains its exact roll through full scene continuation")
	_check(_game.exploration.pending_drops[1].payload.id == "jackpot" and _game.exploration.pending_drops[0].lifetime == 11.0, "Queued jackpot and reward lifetime survive without being consumed during load")
	var found: bool = false
	for drop: Node3D in _game.exploration.drops:
		if drop.kind == "weapon" and str(drop.payload.uid) == str(ground_item.uid):
			found = true
	_check(found, "The same legendary roll remains on the ground after loading")
	_check(_game.running and _game.paused, "Checkpoint reconstruction pauses safely before explicit resume")
	await process_frame

func _test_rejected_snapshots() -> void:
	var clean: Dictionary = _game.snapshot_state()
	var mutations: Array = []
	var bad: Dictionary = clean.duplicate(true)
	bad.inventory.equipped_id = "missing-item"
	mutations.append(["Missing equipped weapon", bad])
	bad = clean.duplicate(true)
	bad.director.spawned = int(bad.director.wave_total) + 1
	mutations.append(["Impossible director counts", bad])
	bad = clean.duplicate(true)
	bad.player.position = [NAN, 0, 0]
	mutations.append(["Nonfinite player position", bad])
	bad = clean.duplicate(true)
	bad.enemies.clear()
	mutations.append(["Missing live wave actors", bad])
	bad = clean.duplicate(true)
	bad.perks.levels = []
	mutations.append(["Wrong nested perk type", bad])
	bad = clean.duplicate(true)
	bad.world.unlocked_regions = {}
	mutations.append(["Wrong nested region type", bad])
	bad = clean.duplicate(true)
	bad.exploration.discovered = {}
	mutations.append(["Wrong discovery collection type", bad])
	bad = clean.duplicate(true)
	bad.exploration.challenge = []
	mutations.append(["Wrong challenge type", bad])
	bad = clean.duplicate(true)
	bad.player.health = NAN
	mutations.append(["Nonfinite player health", bad])
	bad = clean.duplicate(true)
	bad.powerups["unknown"] = 10
	mutations.append(["Unknown powerup", bad])
	var fields: Array = [
		["dog.shield_delay", {}], ["dog.attack_timer", []], ["dog.heal_timer", "later"],
		["dog.ability_timer", []], ["dog.rotation_y", {}], ["dog.level", 1.5],
		["director.metrics.pressure", []], ["director.metrics.spawn_interval", 0.0],
		["director.metrics.relief", "true"], ["director.active_event.remaining", {}],
		["director.active_event.id", "unknown_event"], ["director.wave_total", 2.5],
		["player.velocity", [0, "bad", 0]], ["player.dash_direction", []],
		["player.trigger_counts", []], ["player.last_combat", {"damage":[],"modifiers":[]}],
		["player.last_combat", {"damage":1.0,"modifiers":["unknown_effect"]}],
		["player.rng_state", {}], ["player.reloading", "false"],
		["player.reload_remaining", 100.0], ["player.burst_remaining", 1.5],
		["player.active_item_uid", "missing_item"], ["player.heat", INF],
		["player.active_item_uid", StringName(clean.player.active_item_uid)],
		["run_seed", StringName(clean.run_seed)],
		["exploration.challenge", {"id":"partial"}],
		["exploration.challenge", {"id":"x","name":[],"region":"patio","remaining":12,"kills":0,"target":2}],
		["exploration.challenge", {"id":"x","name":"Run","region":"unknown","remaining":12,"kills":0,"target":2}],
		["boss_zone", {"region":"quadra"}], ["boss_zone", {"id":"orphan","region":"quadra"}],
	]
	for field: Array in fields:
		bad = clean.duplicate(true)
		var keys: PackedStringArray = str(field[0]).split(".")
		var parent: Dictionary = bad
		for index in range(keys.size() - 1):
			parent = parent[keys[index]]
		parent[keys[-1]] = field[1]
		mutations.append(["Malformed " + str(field[0]), bad])
	for fixture: Array in [["ammo", {"amount":{}}], ["currency", {"amount":-5}], ["currency", {"amount":1.5}], ["powerup", {"id":"unknown"}], ["attachment", {"uid":"bad_part","id":"missing","slot":"sight","rarity":"rare","roll":1.0}]]:
		bad = clean.duplicate(true)
		bad.exploration.drops.append({"kind":fixture[0],"payload":fixture[1],"position":[0,0,0],"lifetime":0})
		mutations.append(["Malformed ground " + str(fixture[0]), bad])
	for pending: Variant in [{}, [{"kind":"powerup","payload":{"id":"unknown"},"position":[0,0,0],"lifetime":0}], [{"kind":"currency","payload":{"amount":1},"position":[INF,0,0],"lifetime":0}]]:
		bad = clean.duplicate(true)
		bad.exploration["pending_rewards"] = pending
		mutations.append(["Malformed queued reward", bad])
	for cooldown: Variant in [-0.1, 4.01, {}, "soon", NAN]:
		bad = clean.duplicate(true)
		bad.enemies[0]["dog_retaliation_cooldown"] = cooldown
		mutations.append(["Malformed dog retaliation cooldown", bad])
	for version: Variant in [0, 1.5, {}, "current"]:
		bad = clean.duplicate(true)
		bad.enemies[0]["balance_version"] = version
		mutations.append(["Malformed enemy balance version", bad])
	bad = clean.duplicate(true)
	bad.exploration["pending_rewards"] = []
	for index in range(513):
		bad.exploration.pending_rewards.append({"kind":"currency","payload":{"amount":1},"position":[0,0,0],"lifetime":0})
	mutations.append(["Queued reward limit", bad])
	bad = clean.duplicate(true)
	bad.exploration["pending_rewards"] = [{"kind":"weapon","payload":clean.inventory.items[0].duplicate(true),"position":[0,0,0],"lifetime":0}]
	mutations.append(["Duplicate owned item queued as reward", bad])
	for entry: Array in mutations:
		var player_id: int = _game.player.get_instance_id()
		var coins: int = _game.coins
		var uid: String = _game.inventory.equipped_id
		var director: Dictionary = _game.director.export_state()
		_check(not _game.apply_snapshot(entry[1]), "Reject before replacing run: " + entry[0])
		_check(_game.player.get_instance_id() == player_id and _game.coins == coins and _game.inventory.equipped_id == uid and _game.director.export_state() == director, "Rejected checkpoint preserves the entire active identity: " + entry[0])

func _test_reward_budget() -> void:
	var full: Dictionary = _game.snapshot_state()
	full.exploration["pending_rewards"] = []
	for index in range(512):
		full.exploration.pending_rewards.append({"kind":"weapon","payload":Loot.make_weapon("boardwalk", 100, "mythic", 400000 + index),"position":[0,0,0],"lifetime":0.0})
	_check(Validator.valid(full), "The maximum bank of 512 fully rolled rewards is a valid recoverable state")
	_check(_game.save_manager.save_slot(3, full).ok, "Maximum queued reward bank fits the real file and JSON-node budget")
	var saved: Dictionary = _game.save_manager.load_slot(3)
	_check(saved.ok and saved.state.exploration.pending_rewards.size() == 512, "All 512 queued rolled weapons survive the atomic save format")
	_game.save_manager.delete_slot(3)

func _test_legacy_enemy_snapshot() -> void:
	var current: Dictionary = _game.snapshot_state()
	var legacy: Dictionary = current.duplicate(true)
	for enemy: Dictionary in legacy.enemies:
		enemy.erase("dog_retaliation_cooldown")
		enemy.erase("balance_version")
		enemy["damage"] = 7.0
	_check(Validator.valid(legacy), "Checkpoints from before retaliation cooldowns remain schema-compatible")
	_check(_game.apply_snapshot(legacy), "A pre-balance checkpoint restores through the actual scene coordinator")
	_freeze_actors()
	_check(_game.enemies[0]._dog_retaliation_cooldown == 0.0, "Old checkpoints receive the documented absent cooldown default")
	_check(_game.enemies[0].export_state().damage > 7.0, "Legacy enemy damage migrates to the current encounter balance")
	_check(_game.apply_snapshot(current), "Restoring the current checkpoint after legacy migration succeeds")
	_freeze_actors()
	_check(is_equal_approx(_game.enemies[0]._dog_retaliation_cooldown, 2.75), "Current cooldown remains intact after repeat loads")

func _test_safe_resume() -> void:
	_game.resume_game()
	_freeze_actors()
	_check(not paused and not _game.paused, "Restored run resumes native processing")
	_check(_game.save_game(), "An updated restored checkpoint saves back to its selected slot")
	_game.return_to_menu()
	_check(not _game.running and _game.paused and _game.player.camera != root.get_camera_3d(), "Returning to menu safely saves and restores cinematic perspective")
	_game.continue_game()
	_freeze_actors()
	_check(_game.running and not _game.paused and _game.active_slot == 1, "Continue selects and resumes the newest valid slot")
	_check(_game.round_number == 9 and _game.player.magazine == 3, "Continue preserves exact progress rather than starting a new wave")
	_check(is_equal_approx(_game.enemies[0]._dog_retaliation_cooldown, 2.75), "Main-menu Continue cannot reset an enemy's retaliation protection")

func _test_game_over() -> void:
	_game.player.damage_cooldown = 0.0
	_game.player.dash_remaining = 0.0
	_game.player.take_damage(10000000.0)
	_check(_game.player.health == 0.0 and not _game.running and _game.paused and paused, "Fatal native damage ends and pauses the expedition")
	var coins: int = _game.coins
	var elapsed: float = _game.elapsed
	_game.resume_game()
	_game.open_shop()
	_game._process(5.0)
	_check(not _game.running and paused and _game._menu_kind == "dead", "Pause and inventory actions cannot revive a defeated run")
	_check(_game.coins == coins and _game.elapsed == elapsed, "Defeat stops income and round progression")
	_check(not _game.player.shoot() and not _game.player.start_reload(), "Defeated players cannot fire or reload")
	_check(not _game.save_game(), "Dead state cannot overwrite a healthy continuation checkpoint")
	_check(_game.save_manager.load_slot(1).state.player.health > 0, "Defeat preserves the last usable checkpoint")

func _freeze_actors() -> void:
	_game.player.set_physics_process(false)
	_game.companion.set_physics_process(false)
	_game.exploration.set_process(false)
	for enemy: Node in _game.enemies:
		enemy.set_physics_process(false)

func _finish() -> void:
	if _finished:
		return
	_finished = true
	paused = false
	Engine.time_scale = 1.0
	Engine.max_fps = 0
	if is_instance_valid(_game):
		_game.running = false
		_game.audio.set_active(false)
		_game.queue_free()
	await process_frame
	await process_frame
	# The native audio mixer retires cached playback on its next mix cycle.
	await create_timer(0.2, true).timeout
	for folder in ["saves", "profile", "settings"]:
		var directory: String = ProjectSettings.globalize_path(_directory + "/" + folder)
		if DirAccess.dir_exists_absolute(directory):
			for file: String in DirAccess.get_files_at(directory):
				DirAccess.remove_absolute(directory.path_join(file))
			DirAccess.remove_absolute(directory)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_directory))
	print("EXPEDITION TESTS: %d checks, %d failures" % [_checks, _failures.size()])
	for failure in _failures:
		printerr(failure)
	quit(0 if _failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)

func _print_non_json(value: Variant, path: String) -> void:
	if value is Dictionary:
		for key in value:
			if not key is String:
				printerr("Non-string JSON key: ", path, ".", key, " type=", typeof(key))
			_print_non_json(value[key], path + "." + str(key))
	elif value is Array:
		for index in range(value.size()):
			_print_non_json(value[index], path + "[%d]" % index)
	elif typeof(value) not in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
		printerr("Non-JSON value: ", path, " type=", typeof(value))
	elif value is float and not is_finite(value):
		printerr("Nonfinite number: ", path)

func _timeout() -> void:
	if _finished:
		return
	_failures.append("Integrated native run exceeded its 90-second deadline")
	_finish()

extends SceneTree
## Launch this script twice via run_coop_test.ps1. All gameplay traffic uses real ENet.
const Main = preload("res://scenes/main.tscn")
const Saves = preload("res://scripts/save_manager.gd")
const Settings = preload("res://scripts/game_settings.gd")
var game: Node
var role := "host"
var port := 27943
var output := "res://test-output/coop"
var checks := 0
var failures: Array[String] = []
var ended := false
var enemy: Node3D
var base_hp := 0.0
var base_speed := 0.0
var remote_id := 0
var _last_elapsed := 0.0

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--role="): role = arg.trim_prefix("--role=")
		if arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	call_deferred("run")

func run() -> void:
	create_timer(65, true).timeout.connect(func(): fail("Timeout"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var directory := output + "/" + role
	game = Main.instantiate()
	game.coop_identity_path = directory + "_identity.cfg"
	game.save_manager = Saves.new(directory + "/saves")
	game._profile_store = Saves.new(directory + "/profile")
	game.settings = Settings.new(directory + "/settings")
	game.settings.set_value("master", 0.0)
	game.settings.set_value("fps_limit", 120)
	game.settings.set_value("reduced_flashes", true)
	game.settings.save_settings()
	root.add_child(game)
	current_scene = game
	while not game.world.navigation_ready: await process_frame
	if role == "host": await run_host()
	else: await run_client()

func run_host() -> void:
	game.start_run("normal", false, 1)
	# Keep a single deterministic native target; the real Coop physics and Main clocks run.
	game.director.phase = "prepare"
	game.director.phase_time = 600.0
	game.companion.follow_only = true
	enemy = game._spawn_enemy_data({"kind":"grunt", "position":Vector3(1.8, 0.1, 11), "wave_enemy":false})
	enemy.set_physics_process(false)
	base_hp = enemy.max_health
	base_speed = enemy.speed
	check(game.coop.host_game(port) == OK, "Real ENet server opened")
	var ready := FileAccess.open(output + "/ready", FileAccess.WRITE)
	ready.store_string("ready")
	ready.close()
	while game.coop.peers.is_empty(): await process_frame
	remote_id = int(game.coop.peers.keys()[0])
	var entry: Dictionary = game.coop.peers[remote_id]
	entry.companion.follow_only = true
	check(game.coop.player_count() == 2, "Handshake creates a real second authoritative player")
	check(is_equal_approx(enemy.max_health, base_hp * 1.8), "Two players give exactly +80% enemy HP")
	check(is_equal_approx(enemy.speed, base_speed), "Co-op never increases enemy speed")
	var initial: Vector3 = entry.player.global_position
	while entry.player.global_position.distance_to(initial) < 1.2: await process_frame
	check(true, "Client controls move its actual host CharacterBody3D")
	var host_coins: int = game.coins
	game.exploration.drop_item("currency", {"amount":4321}, entry.player.global_position)
	while int(game.coop.peers[remote_id].coins) < 4000: await process_frame
	check(game.coins == host_coins, "Guest pickup belongs only to its own wallet")
	while game.kills < 1: await process_frame
	check(int(game.coop.peers[remote_id].player.shot_count) > 0, "Remote fire executes native weapon logic on host")
	check(game.coop.peers[remote_id].player.magazine < 12, "Host consumes guest ammo")
	check(float(game.coop.peers[remote_id].stats.damage) > 0, "Host raycast validates enemy damage and kill")
	check(game.stats.damage == 0, "Guest combat credit does not alter host statistics")
	while int(game.coop.peers[remote_id].progression.levels.get("force", 0)) < 1: await process_frame
	while int(game.coop.peers[remote_id].companion.levels.attack) < 1: await process_frame
	check(game.progression.levels.get("force", 0) == 0 and game.companion.levels.attack == 0, "Perk and Faro purchases are individual")
	while not FileAccess.file_exists(output + "/ui_stable_ready"): await process_frame
	game.coop.with_peer(remote_id, func():
		game.player.magazine = 0
		game.player.reserve -= 1
		game.player.health -= 3
		game.player._save_ammo()
		game.player.start_reload()
	)
	while not FileAccess.file_exists(output + "/client_purchases"): await process_frame
	entry.player.global_position = Vector3(5, 0.2, 14)
	_mark("station_ready")
	while int(game.coop.peers[remote_id].progression.station_levels.get("shelter", 0)) < 1: await process_frame
	var resistance: float = game.coop.with_peer(remote_id, func(): return game.get_player_modifiers().resistance)
	check(resistance > 0 and float(game.get_player_modifiers().resistance) == 0, "Guest E buys a real regional perk and modifies only its own combat stats")
	var guest_coins: int = game.coop.peers[remote_id].coins
	game.director.round_number = 2
	game._sync_director()
	entry.player.global_position = Vector3(10, 0.2, 14.4)
	_mark("door_ready")
	while not game.world.unlocked_regions.has("oficina"): await process_frame
	check(game.coop.peers[remote_id].coins == guest_coins - 180, "Guest E pays authoritative door cost once")
	check(game.world.unlocked_regions.has("oficina"), "Guest door purchase opens the shared region on host")
	entry.player.global_position = Vector3(0, 0.2, 17)
	var item: Dictionary = game.Loot.make_weapon("hammer", 2, "rare", 73547)
	item.uid = "coop-qa-ground-weapon"
	game.exploration.drop_item("weapon", item, Vector3(0, 0.1, 15), true)
	_mark("loot_ready")
	while game.coop.peers[remote_id].inventory.find_item(item.uid).is_empty(): await process_frame
	check(game.inventory.find_item(item.uid).is_empty(), "Guest E collects ground weapon exclusively into its own inventory")
	while not FileAccess.file_exists(output + "/client_world_verified"): await process_frame
	var grenade_target: Node3D = game._spawn_enemy_data({"kind":"grunt", "position":Vector3(0, 0.1, 14), "wave_enemy":false})
	grenade_target.set_physics_process(false)
	_mark("grenade_ready")
	while game.kills < 2: await process_frame
	check(game.coop.peers[remote_id].inventory.supplies.grenade == 2, "Guest grenade consumes its authoritative personal charge")
	check(game.stats.damage == 0 and game.coop.peers[remote_id].stats.damage > base_hp * 1.8, "Delayed grenade damage and reward remain attributed to the guest")
	var host_before_round: int = game.coins
	var guest_before_round: int = game.coop.peers[remote_id].coins
	game._director_action({"type":"round_complete", "reward":100})
	check(game.coins == host_before_round + 100 and game.coop.peers[remote_id].coins == guest_before_round + 100, "Authoritative round completion rewards each wallet independently")
	var drops_before: int = game.exploration.drops.size()
	host_before_round = game.coins
	guest_before_round = game.coop.peers[remote_id].coins
	game.exploration.challenge = {"id":"coop_qa_challenge", "name":"Coop QA", "region":"patio", "remaining":30.0,"kills":1,"target":1}
	game.coop.with_peer(remote_id, func(): game.exploration._finish_challenge(Vector3(0, 0.1, 13)))
	check(game.coins == host_before_round + 350 and game.coop.peers[remote_id].coins == guest_before_round + 350, "Guest completes shared challenge and rewards both wallets once")
	check(game.exploration.drops.size() == drops_before + 1, "Shared challenge emits one ground reward without duplication")
	game.pause_game()
	check(not paused and not game.simulation_paused(), "Host pause menu leaves authoritative world running")
	var health: float = game.player.health
	game.player.damage_cooldown = 0
	game.player.take_damage(5)
	await create_timer(0.5, true).timeout
	game.player.take_damage(5)
	check(game.player.health <= health - 10, "Paused host remains vulnerable after grace expires")
	game.resume_game()
	check(game.save_game(), "Host atomically saves personal states and shared world")
	var saved: Dictionary = game.save_manager.load_slot(1).get("state", {})
	check(saved.get("coop", {}).get("players", {}).size() == 1, "Save includes reconnect record for guest identity")
	var token: String = entry.token
	var malformed: Dictionary = saved.duplicate(true)
	malformed.coop.players[token].inventory = {"items":"invalid"}
	check(not game._valid_snapshot(malformed), "Malformed personal reconnect record rejects the checkpoint before mutation")
	var saved_coins := int(game.coop.peers[remote_id].coins)
	var saved_ammo := int(game.coop.peers[remote_id].player.magazine)
	var signal_file := FileAccess.open(output + "/host_verified", FileAccess.WRITE)
	signal_file.store_string("done")
	signal_file.close()
	while game.coop.peers.has(remote_id): await process_frame
	check(game.coop.records.has(token), "Disconnect caches the exact personal state")
	game.coop.stop()
	check(game.apply_snapshot(saved), "Reloading the host checkpoint restores the shared expedition")
	game.resume_game()
	check(game.coop.host_game(port) == OK, "Reloaded expedition can reopen the real host socket")
	while game.coop.peers.is_empty(): await process_frame
	var reconnected: Dictionary = game.coop.peers[game.coop.peers.keys()[0]]
	check(reconnected.token == token, "Reconnect reclaims identity with a new ENet peer")
	check(reconnected.coins == saved_coins, "Reconnect preserves wallet")
	check(reconnected.player.magazine == saved_ammo, "Reconnect preserves consumed ammunition")
	check(reconnected.progression.levels.force == 1 and reconnected.companion.levels.attack == 1, "Reconnect preserves independent perks and Faro branches")
	check(reconnected.progression.station_levels.shelter == 1 and not reconnected.inventory.find_item(item.uid).is_empty(), "Reload and reconnect preserve regional perk and collected weapon")
	await create_timer(1.0, true).timeout
	await finish()

func run_client() -> void:
	check(game.coop.join_game("127.0.0.1", port, "Convidado QA") == OK, "Real ENet client begins connection")
	while game.coop.mode != "client": await process_frame
	check(game.coop.peers.has(1), "Client renders a replicated host")
	check(game.enemies.size() == 1, "Client receives the host enemy")
	var menu: Node = game.get_node("CoopMenu")
	menu.open()
	await process_frame
	check(menu.panel.visible, "Connected guest can reopen the co-op menu and disconnect")
	menu.close()
	var initial: Vector3 = game.player.global_position
	# Move away from host so the currency fixture cannot legitimately be collected by host first.
	game.coop.test_input = {"move":Vector2(1, 0), "yaw":0.0,"pitch":0.0}
	await create_timer(0.5, true).timeout
	game.coop.test_input = {"move":Vector2.ZERO}
	while game.coins < 4000: await process_frame
	check(game.player.global_position.distance_to(initial) > 0.1, "Host positions replicate back to guest")
	check(game.coins == 4571, "Host grants collectible currency once")
	var before: int = game.player.magazine
	while game.kills < 1:
		if not game.enemies.is_empty():
			var target: Vector3 = game.enemies[0].global_position + Vector3.UP * 1.0
			var direction: Vector3 = (target - game.player.camera.global_position).normalized()
			game.player.rotation.y = atan2(-direction.x, -direction.z)
			game.player._pitch = asin(direction.y)
			game.coop.test_input = {"move":Vector2.ZERO, "buttons":{"aim":true}, "pressed":{"fire":true}, "yaw":float(game.player.rotation.y), "pitch":float(game.player._pitch)}
		await create_timer(0.25, true).timeout
	game.coop.test_input = {"move":Vector2.ZERO,"buttons":{},"pressed":{}}
	check(game.player.magazine < before, "Guest sees authoritative ammunition depletion")
	game.pause_game()
	check(not paused, "Guest inventory/pause affects only its own controls")
	game.buy_perk("force")
	game.upgrade_dog("attack")
	while int(game.progression.levels.get("force", 0)) < 1 or game.companion.levels.attack < 1: await process_frame
	check(true, "Reliable purchase requests update guest perk and Faro UI data")
	var coins: int = game.coins
	game.buy_weapon("does_not_exist")
	await create_timer(0.3, true).timeout
	check(game.coins == coins, "Invalid purchase cannot spend currency")
	await _test_snapshot_ui()
	game.resume_game()
	_mark("client_purchases")
	while not FileAccess.file_exists(output + "/station_ready") or game.player.global_position.distance_to(Vector3(5, 0.2, 14)) > 1.0: await process_frame
	await _aim_and_interact(Vector3(5, 1.2, 12))
	while int(game.progression.station_levels.get("shelter", 0)) < 1: await process_frame
	check(float(game.get_player_modifiers().resistance) > 0, "Guest station interaction receives its actual regional modifier")
	while not FileAccess.file_exists(output + "/door_ready") or game.player.global_position.distance_to(Vector3(10, 0.2, 14.4)) > 1.0: await process_frame
	await _aim_and_interact(Vector3(10, 1.55, 12.4))
	while not game.world.unlocked_regions.has("oficina"): await process_frame
	check(true, "Shared gate state replicates to guest")
	while not FileAccess.file_exists(output + "/loot_ready") or game.player.global_position.distance_to(Vector3(0, 0.2, 17)) > 1.0: await process_frame
	await _aim_and_interact(Vector3(0, 0.47, 15))
	while game.inventory.find_item("coop-qa-ground-weapon").is_empty(): await process_frame
	check(true, "Guest weapon pickup travels through host validation and inventory replication")
	coins = game.coins
	_mark("client_world_verified")
	while not FileAccess.file_exists(output + "/grenade_ready"): await process_frame
	game.player.rotation.y = 0.0
	game.player._pitch = -0.55
	game.coop.test_input = {"move":Vector2.ZERO,"buttons":{},"pressed":{},"yaw":0.0,"pitch":-0.55}
	await create_timer(0.25, true).timeout
	game.use_supply("grenade")
	while game.kills < 2: await process_frame
	check(game.inventory.supplies.grenade == 2, "Guest sees host grenade detonation and consumed supply")
	while not FileAccess.file_exists(output + "/host_verified"): await process_frame
	await create_timer(0.25, true).timeout
	coins = game.coins
	var ammo: int = game.player.magazine
	game.coop.stop("QA reconnect")
	await create_timer(0.5, true).timeout
	check(game.coop.join_game("127.0.0.1", port, "Convidado QA") == OK, "Reconnect opens a fresh ENet transport")
	while game.coop.mode != "client": await process_frame
	check(game.coins == coins and game.player.magazine == ammo, "Guest restores exact wallet and ammo from host record")
	check(game.progression.levels.force == 1 and game.companion.levels.attack == 1, "Guest restores purchased build after reconnect")
	check(game.progression.station_levels.shelter == 1 and game.world.unlocked_regions.has("oficina"), "Guest restores regional perk and shared unlocked map")
	await create_timer(0.3, true).timeout
	await finish()

func check(condition: bool, message: String) -> void:
	checks += 1
	print("COOP_%s %s %s" % [role.to_upper(), "PASS" if condition else "FAIL", message])
	if not condition: failures.append(message)

func _mark(id: String) -> void:
	var file := FileAccess.open(output + "/" + id, FileAccess.WRITE)
	file.store_string("ready")
	file.close()

func _aim_and_interact(point: Vector3) -> void:
	var direction: Vector3 = (point - game.player.camera.global_position).normalized()
	game.player.rotation.y = atan2(-direction.x, -direction.z)
	game.player._pitch = asin(direction.y)
	game.coop.test_input = {"move":Vector2.ZERO,"buttons":{},"pressed":{},"yaw":float(game.player.rotation.y),"pitch":float(game.player._pitch)}
	await create_timer(0.25, true).timeout
	game.coop.request_action("interact")

func _test_snapshot_ui() -> void:
	game.open_inventory("forge")
	await create_timer(0.25, true).timeout
	var shop: Node = game.ui.shop
	var scroll := shop._body.get_child(0) as ScrollContainer
	check(is_instance_valid(scroll), "Native forge exposes its real scroll container")
	if not is_instance_valid(scroll): return
	scroll.scroll_vertical = 65
	await process_frame
	var scroll_position := scroll.scroll_vertical
	var body_id := scroll.get_instance_id()
	var rig_id: int = game.player.weapon_view.model.get_instance_id()
	var replica_rig_id: int = game.coop.peers[1].player.weapon_view.model.get_instance_id()
	var health: float = game.player.health
	var sequence: int = game.coop._last_state_sequence
	_mark("ui_stable_ready")
	await create_timer(0.7, true).timeout
	check(game.coop._last_state_sequence >= sequence + 4, "Stable-menu check receives multiple real ENet snapshots")
	check(shop._body.get_child(0).get_instance_id() == body_id, "Ammo, health and reload snapshots preserve the existing forge UI nodes")
	check(scroll_position > 0 and is_instance_valid(scroll) and scroll.scroll_vertical == scroll_position, "Scrolling survives repeated snapshots without reconstruction")
	check(game.player.weapon_view.model.get_instance_id() == rig_id and game.coop.peers[1].player.weapon_view.model.get_instance_id() == replica_rig_id, "Local and remote weapon rigs survive unchanged snapshots")
	check(game.player.health < health and game.player.magazine == 0, "Dynamic player health and ammunition still synchronize")
	check(game.player.reloading and game.player._reload_was_empty, "Authoritative empty-reload state reaches the client animation")
	while game.player.reloading: await process_frame
	check(game.player.magazine > 0 and game.player.reload_remaining == 0 and shop._body.get_child(0).get_instance_id() == body_id, "Reload completion resets animation without rebuilding the forge")
	var coins_before: int = game.coins
	game.buy_attachment("suppressor")
	while not game.inventory.attachments.any(func(part: Dictionary) -> bool: return part.id == "suppressor"): await process_frame
	await process_frame
	await process_frame
	check(game.coins == coins_before - 125 and shop._body.get_child(0).get_instance_id() != body_id, "Confirmed attachment purchase refreshes wallet and forge content")
	body_id = shop._body.get_child(0).get_instance_id()
	var part_uid := ""
	for part: Dictionary in game.inventory.attachments:
		if part.id == "suppressor": part_uid = str(part.uid)
	var equipped_uid: String = game.player.active_item_uid
	game.install_attachment(equipped_uid, part_uid)
	while game.inventory.equipped().get("attachments", {}).get("barrel", {}).get("id", "") != "suppressor": await process_frame
	await process_frame
	await process_frame
	check(game.player.active_item_uid == equipped_uid and game.player.weapon_view.model.get_instance_id() != rig_id and game.player.weapon_view.model.has_node("AttachmentBarrel_suppressor"), "Same-UID attachment install updates the actual local weapon geometry")
	check(shop._body.get_child(0).get_instance_id() != body_id, "Same-UID attachment configuration updates the forge preview")
	body_id = shop._body.get_child(0).get_instance_id()
	rig_id = game.player.weapon_view.model.get_instance_id()
	await create_timer(0.4, true).timeout
	check(shop._body.get_child(0).get_instance_id() == body_id and game.player.weapon_view.model.get_instance_id() == rig_id, "New configuration remains stable in subsequent snapshots")

func fail(message: String) -> void:
	if ended: return
	check(false, message)
	finish()

func finish() -> void:
	if ended: return
	ended = true
	var result := {"role":role, "checks":checks, "failures":failures, "ok":failures.is_empty()}
	var file := FileAccess.open(output + "/" + role + "_result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	game._save_pending = false
	game.running = false
	game.coop.stop()
	await game.audio.shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	print("COOP_%s_RESULT %s" % [role.to_upper(), JSON.stringify(result)])
	quit(0 if failures.is_empty() else 1)

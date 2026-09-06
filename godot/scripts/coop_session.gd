extends Node
## ENet authority: only inputs/actions cross from guests. All economy and combat run here.
const PROTOCOL := 1
const DEFAULT_PORT := 27842
const MAX_PLAYERS := 4
const LOCAL_KEYS := ["inventory", "progression", "coins", "player", "companion", "stats", "profile", "active_powerups", "_damage_credit", "_last_damage", "_last_kill", "_kill_chain", "_grenade_ready_at"]
const ACTIONS := {"buy_weapon":1, "equip_item":1, "equip_to_slot":2, "buy_equipment":2, "buy_supply":1, "use_supply":1, "auto_equip":0, "set_item_flag":2, "discard_item":1, "sell_item":1, "salvage_item":1, "install_attachment":2, "uninstall_attachment":2, "buy_attachment":1, "upgrade_weapon":1, "reroll_weapon":2, "buy_perk":1, "upgrade_dog":1, "select_dog":1, "choose_dog_element":1, "refill_ammo":0, "interact":0, "swap_ground_weapon":0, "reload":0, "dog_mode":0, "select_slot":1}
var game: Node
var mode := "offline"
var status := "Solo"
var peers: Dictionary = {}
var records: Dictionary = {}
var current_peer_id := 1
var identity := ""
var nickname := "Jogador"
var last_address := "127.0.0.1"
var port := DEFAULT_PORT
var _send_clock := 0.0
var _input_clock := 0.0
var _autosave_clock := 0.0
var _sequence := 0
var _last_state_sequence := -1
var _next_enemy_id := 1
var _next_drop_id := 1
var _world_hash := 0
var _initial_state := true
var _pending_pressed: Dictionary = {}
var _last_buttons: Dictionary = {}
var _identity_path := "user://coop_identity.cfg"
var _last_state_time := 0
var _connecting_at := 0
var _team_wiped := false
var _rewarding_group := false
var test_input: Dictionary = {}
var _grenade_visuals: Dictionary = {}
var _local_ui_signature := 0

func setup(owner_game: Node) -> void:
	game = owner_game
	_identity_path = game.coop_identity_path
	name = "Coop"
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(_identity_path) == OK:
		identity = str(config.get_value("identity", "token", ""))
		nickname = str(config.get_value("identity", "name", nickname))
	if identity.length() != 64:
		identity = Crypto.new().generate_random_bytes(32).hex_encode()
		config.set_value("identity", "token", identity)
		config.save(_identity_path)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(_connection_failed)
	multiplayer.server_disconnected.connect(_server_disconnected)
	multiplayer.peer_disconnected.connect(_peer_left)

func is_online() -> bool: return mode in ["host", "client", "connecting"]
func is_host() -> bool: return mode == "host"
func is_client() -> bool: return mode in ["client", "connecting"]
func player_count() -> int: return 1 + peers.size() if is_host() else maxi(1, peers.size() + 1)
func health_multiplier() -> float: return 1.0 + 0.8 * float(player_count() - 1)

func host_game(requested_port: int = DEFAULT_PORT) -> Error:
	if is_online() or not game.running: return ERR_BUSY
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_server(requested_port, MAX_PLAYERS - 1)
	if result != OK:
		status = "Não foi possível abrir UDP %d (%s)" % [requested_port, error_string(result)]
		return result
	peer.host.compress(ENetConnection.COMPRESS_FASTLZ)
	port = requested_port
	multiplayer.multiplayer_peer = peer
	mode = "host"
	_team_wiped = false
	_host_respawn_at = 0
	status = "Host · UDP %d · 1/%d" % [port, MAX_PLAYERS]
	game.get_tree().paused = false
	game.player.network_peer_id = 1
	game.companion.network_peer_id = 1
	game.notify("Cooperativo aberto · até 4 jogadores · UDP %d" % port)
	return OK

func join_game(address: String, requested_port: int = DEFAULT_PORT, display_name: String = "Jogador") -> Error:
	if is_online() or game.running: return ERR_BUSY
	if address.strip_edges().is_empty(): return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_client(address.strip_edges(), requested_port)
	if result != OK:
		status = "Falha ao entrar (%s)" % error_string(result)
		return result
	peer.host.compress(ENetConnection.COMPRESS_FASTLZ)
	last_address = address.strip_edges()
	port = requested_port
	nickname = display_name.strip_edges().left(24)
	if nickname.is_empty(): nickname = "Jogador"
	multiplayer.multiplayer_peer = peer
	mode = "connecting"
	status = "Conectando a %s:%d…" % [last_address, port]
	_connecting_at = Time.get_ticks_msec()
	_initial_state = true
	_last_state_sequence = -1
	return OK

func _connected() -> void:
	_register.rpc_id(1, PROTOCOL, identity, nickname)

func _connection_failed() -> void:
	stop("Conexão falhou. Confira IP, UDP %d, firewall e LAN/VPN." % port)

func _server_disconnected() -> void:
	stop("Host desconectou. Volte a entrar no mesmo host para recuperar seu personagem.")

func stop(reason: String = "Sessão encerrada") -> void:
	var was_client := is_client()
	var previous_multiplier := health_multiplier()
	if is_host():
		for id: int in peers.keys(): _cache_peer(id)
	for entry: Dictionary in peers.values(): _free_actor(entry)
	peers.clear()
	for visual: Node3D in _grenade_visuals.values():
		if is_instance_valid(visual): visual.queue_free()
	_grenade_visuals.clear()
	if multiplayer.multiplayer_peer != null: multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = "offline"
	_pending_pressed.clear()
	_local_ui_signature = 0
	if not was_client:
		for enemy: Node in game.enemies:
			if is_instance_valid(enemy):
				enemy.max_health /= previous_multiplier
				enemy.health /= previous_multiplier
	current_peer_id = 1
	status = reason
	game.get_tree().paused = false
	if is_instance_valid(game.player):
		game.player.network_peer_id = 1
		game.player.network_replica = false
	if was_client:
		game.running = false
		game.paused = true
		game._clear_run()
		game._menu_kind = "main"
		game._menu_camera.make_current()
		game.player.hide()
		game.ui.show_menu()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.notify(reason)

func _free_actor(entry: Dictionary) -> void:
	for key: String in ["player", "companion"]:
		if is_instance_valid(entry.get(key)): entry[key].queue_free()

@rpc("any_peer", "call_remote", "reliable", 0)
func _register(version: int, token: String, display_name: String) -> void:
	if not is_host(): return
	var id := multiplayer.get_remote_sender_id()
	if version != PROTOCOL or token.length() != 64 or not token.is_valid_hex_number(false) or peers.has(id) or peers.size() >= MAX_PLAYERS - 1:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	for entry: Dictionary in peers.values():
		if entry.token == token:
			multiplayer.multiplayer_peer.disconnect_peer(id)
			return
	if not records.has(token) and records.size() >= 64:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	var previous := health_multiplier()
	var entry := _new_actor(id)
	entry.token = token
	entry.nickname = display_name.left(24)
	peers[id] = entry
	if records.has(token):
		with_peer(id, func(): _restore_personal(records[token]))
		if entry.player.health <= 0: entry.respawn_at = game.elapsed + 10.0
	else:
		entry.player.global_position = game.player.global_position + Vector3(1.8 * peers.size(), 0.2, 0)
		entry.companion.global_position = entry.player.global_position + Vector3(0, 0, 1.5)
	_rescale_enemies(previous)
	entry.player.hero.show()
	entry.player.weapon_view.hide()
	entry.player.camera.current = false
	game.player.camera.make_current()
	status = "Host · UDP %d · %d/%d" % [port, player_count(), MAX_PLAYERS]
	game.notify("%s entrou · inimigos com %.0f%% de vida" % [entry.nickname, health_multiplier() * 100.0])
	game.schedule_save()
	_send_state()

func _new_actor(id: int) -> Dictionary:
	var entry: Dictionary = {}
	for key: String in LOCAL_KEYS: entry[key] = game.get(key)
	entry.inventory = game.Inventory.new()
	entry.inventory.create_starter()
	entry.progression = game.Progression.new()
	entry.coins = 250
	entry.stats = {"damage":0.0,"headshots":0,"shots":0,"earned":0,"purchases":0,"bosses":0}
	entry.profile = {"sigils":0,"record":0,"weapons":[],"enemies":[],"achievements":[],"unlocks":[],"awarded":[]}
	entry.active_powerups = {}
	entry._damage_credit = 0.0
	entry._last_damage = -30.0
	entry._last_kill = -10.0
	entry._kill_chain = 0
	entry._grenade_ready_at = 0.0
	entry.player = game.Player.new()
	entry.companion = game.Companion.new()
	entry.input = {}
	entry.last_input = Time.get_ticks_msec()
	entry.last_sequence = -1
	entry.action_window = 0
	entry.action_count = 0
	entry.respawn_at = 0.0
	var saved := _capture_context()
	_apply_context(entry)
	entry.player.network_peer_id = id
	entry.player.network_controlled = true
	entry.player.setup(game)
	game.add_child(entry.player)
	entry.player.name = "PeerPlayer_%d" % id
	entry.player.set_physics_process(false)
	entry.player.camera.current = false
	entry.player.hero.show()
	entry.player.weapon_view.hide()
	entry.companion.network_peer_id = id
	entry.companion.setup(game)
	game.add_child(entry.companion)
	entry.companion.name = "PeerFaro_%d" % id
	entry.companion.set_physics_process(false)
	_apply_context(saved)
	game.player.camera.make_current()
	return entry

func _capture_context() -> Dictionary:
	var result: Dictionary = {}
	for key: String in LOCAL_KEYS: result[key] = game.get(key)
	return result

func _apply_context(value: Dictionary) -> void:
	for key: String in LOCAL_KEYS: game.set(key, value[key])

func with_peer(id: int, operation: Callable) -> Variant:
	if is_client():
		if not peers.has(id): return operation.call()
		var local := _capture_context()
		_apply_context(peers[id])
		var value: Variant = operation.call()
		peers[id].merge(_capture_context(), true)
		_apply_context(local)
		return value
	if id == current_peer_id: return operation.call()
	if id != 1 and not peers.has(id): return null
	# Nested damage callbacks may target the host while another player's tick is running.
	var previous := _capture_context()
	var previous_id := current_peer_id
	if previous_id != 1: peers[previous_id].merge(previous, true)
	else: _host_context = previous
	_apply_context(_host_context if id == 1 else peers[id])
	current_peer_id = id
	var result: Variant = operation.call()
	var updated := _capture_context()
	if id == 1: _host_context = updated
	else: peers[id].merge(updated, true)
	_apply_context(_host_context if previous_id == 1 else peers[previous_id])
	current_peer_id = previous_id
	return result

var _host_context: Dictionary = {}

func _peer_left(id: int) -> void:
	if not peers.has(id): return
	var previous := health_multiplier()
	if is_host(): _cache_peer(id)
	_free_actor(peers[id])
	peers.erase(id)
	if is_host():
		_rescale_enemies(previous)
		game.schedule_save()
		status = "Host · UDP %d · %d/%d" % [port, player_count(), MAX_PLAYERS]

func _rescale_enemies(previous: float) -> void:
	for enemy: Node in game.enemies:
		if not is_instance_valid(enemy) or enemy.dead: continue
		var ratio: float = enemy.health / maxf(1, enemy.max_health)
		enemy.max_health = enemy.max_health / previous * health_multiplier()
		enemy.health = enemy.max_health * ratio

func _cache_peer(id: int) -> void:
	with_peer(id, func(): records[peers[id].token] = personal_snapshot())

func personal_snapshot() -> Dictionary:
	return {"inventory":game.inventory.export_state(), "perks":game.progression.export_state(), "coins":game.coins, "player":game.player.snapshot(), "dog":game.companion.export_state(), "stats":game.stats.duplicate(true), "profile":game.profile.duplicate(true), "powerups":game.active_powerups.duplicate(true)}

func _restore_personal(data: Dictionary) -> void:
	if not game.inventory.import_state(data.get("inventory", {})): return
	game.progression.import_state(data.get("perks", {}))
	game.coins = maxi(0, int(data.get("coins", 250)))
	game.stats = data.get("stats", {}).duplicate(true)
	game.profile = data.get("profile", game.profile).duplicate(true)
	game.active_powerups = data.get("powerups", {}).duplicate(true)
	game.player.restore(data.get("player", {}))
	game.companion.import_state(data.get("dog", {}))

func export_state() -> Dictionary:
	if is_host():
		for id: int in peers: _cache_peer(id)
	return {"version": PROTOCOL, "players":records.duplicate(true), "enemy_multiplier":health_multiplier() if is_host() else 1.0}

func import_state(data: Dictionary) -> void:
	records.clear()
	var saved: Variant = data.get("players", {})
	if saved is Dictionary:
		for token: Variant in saved:
			if token is String and str(token).length() == 64 and saved[token] is Dictionary:
				records[token] = saved[token].duplicate(true)
	# Saves can be resumed solo and then hosted again. Preserve health percentages.
	var old_multiplier := maxf(1.0, float(data.get("enemy_multiplier", 1.0)))
	for enemy: Node in game.enemies:
		if is_instance_valid(enemy):
			enemy.max_health /= old_multiplier
			enemy.health /= old_multiplier

func request_action(action: String, args: Array = []) -> bool:
	if not is_client(): return false
	if mode == "client" and ACTIONS.has(action): _action.rpc_id(1, action, args)
	return true

@rpc("any_peer", "call_remote", "reliable", 0)
func _action(action: String, args: Array) -> void:
	if not is_host() or not game.running: return
	var id := multiplayer.get_remote_sender_id()
	if not peers.has(id) or not ACTIONS.has(action) or args.size() != int(ACTIONS[action]): return
	for arg: Variant in args:
		if not (arg is String or arg is int) or str(arg).length() > 128: return
	for index: int in range(args.size()):
		var needs_integer := action == "select_slot" or (action == "equip_to_slot" and index == 1)
		if needs_integer and not args[index] is int: return
		if not needs_integer and not args[index] is String: return
	var entry: Dictionary = peers[id]
	var window := Time.get_ticks_msec() / 1000
	if entry.action_window != window:
		entry.action_window = window
		entry.action_count = 0
	entry.action_count += 1
	if entry.action_count > 30 or entry.player.health <= 0: return
	with_peer(id, func(): execute_action(action, args))
	_send_clock = 0

func execute_action(action: String, args: Array) -> void:
	var previous_pause: bool = game.paused
	game.paused = false
	match action:
		"interact", "swap_ground_weapon": game.exploration.callv(action, args)
		"reload": game.player.start_reload()
		"dog_mode": game.companion.toggle_mode()
		"select_slot":
			game.player._save_ammo()
			if game.inventory.select_slot(clampi(int(args[0]), 0, 3)): game.player.sync_inventory()
		_: game.callv(action, args)
	game.paused = previous_pause

func open_remote_inventory(tab: String) -> bool:
	if is_host() and current_peer_id != 1:
		_open_inventory.rpc_id(current_peer_id, tab)
		return true
	return false

@rpc("authority", "call_remote", "reliable", 0)
func _open_inventory(tab: String) -> void:
	game.open_inventory(tab)

func _input(event: InputEvent) -> void:
	if not is_client() or not game.running or game.paused: return
	for action: String in ["jump", "dive", "sprint", "fire"]:
		if event.is_action_pressed(action): _pending_pressed[action] = true

func _physics_process(delta: float) -> void:
	if not is_online(): return
	if mode == "connecting":
		if Time.get_ticks_msec() - _connecting_at > 12000: _connection_failed()
		return
	if is_client():
		if not game.running: return
		if Time.get_ticks_msec() - _last_state_time > 15000:
			stop("Sem resposta do host. Entre novamente para recuperar seu personagem.")
			return
		for id: int in peers:
			with_peer(id, func():
				var actor: Node3D = game.player
				_interpolate_actor(actor, delta)
				actor._update_view(delta, minf(1.0, actor.velocity.length() / 5.8))
				_interpolate_actor(game.companion, delta)
				game.companion._animate(delta)
			)
		_interpolate_actor(game.companion, delta)
		game.companion._animate(delta)
		_input_clock -= delta
		if _input_clock <= 0:
			_input_clock = 1.0 / 30.0
			var controls := _capture_input()
			_input_packet.rpc_id(1, controls)
			_pending_pressed.clear()
		return
	if not game.running: return
	for id: int in peers.keys():
		with_peer(id, func():
			var entry: Dictionary = peers[id]
			var previous_pause: bool = game.paused
			game.paused = false
			game.player.network_input = entry.input if Time.get_ticks_msec() - entry.last_input < 500 else {}
			game.player._physics_process(delta)
			entry.input["pressed"] = {}
			game.companion._physics_process(delta)
			game.exploration.collect_nearby(game.player.global_position, 1.6)
			var region: String = game.world.get_region_id(game.player.global_position)
			if not region.is_empty() and not game.exploration.discovered.has(region) and game.world.unlocked_regions.has(region):
				game.exploration.discovered.append(region)
				game.add_coins(40, "exploration")
				game.notify("Nova área · " + game.world.district(game.player.global_position))
				game.schedule_save()
			for key: String in game.active_powerups.keys():
				game.active_powerups[key] = maxf(0.0, float(game.active_powerups[key]) - delta)
				if float(game.active_powerups[key]) <= 0: game.active_powerups.erase(key)
			game.paused = previous_pause
		)
	_tick_respawns()
	_send_clock -= delta
	if _send_clock <= 0:
		_send_clock = 0.10
		_send_state()
	_autosave_clock += delta
	if _autosave_clock >= 10:
		_autosave_clock = 0
		game.schedule_save()

func _capture_input() -> Dictionary:
	_sequence += 1
	var buttons: Dictionary = {}
	for action: String in ["crouch", "sprint", "aim", "fire"]:
		buttons[action] = Input.is_action_pressed(action) and not game.paused
	if not game.paused:
		if bool(game.settings.data.get("toggle_aim", false)): buttons.aim = game.player._aim_toggle
		if bool(game.settings.data.get("toggle_sprint", false)): buttons.sprint = game.player._sprint_toggle
		if bool(game.settings.data.get("auto_sprint", false)): buttons.sprint = true
	var move := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if not game.paused else Vector2.ZERO
	var packet := {"seq":_sequence, "move":move, "buttons":buttons, "pressed":_pending_pressed.duplicate() if not game.paused else {}, "yaw":game.player.rotation.y, "pitch":game.player._pitch, "third_person":game.player.third_person, "flashlight":game.player.flashlight_on}
	if not test_input.is_empty(): packet.merge(test_input, true)
	return packet

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _input_packet(packet: Dictionary) -> void:
	if not is_host(): return
	var id := multiplayer.get_remote_sender_id()
	if not peers.has(id) or packet.size() > 9: return
	if not packet.get("move") is Vector2 or not packet.get("buttons") is Dictionary or not packet.get("pressed") is Dictionary: return
	if not packet.get("yaw") is float or not packet.get("pitch") is float or not packet.get("seq") is int: return
	if not packet.move.is_finite() or not is_finite(packet.yaw) or not is_finite(packet.pitch): return
	if packet.buttons.size() > 4 or packet.pressed.size() > 4: return
	for button: Variant in packet.buttons:
		if button not in ["crouch", "sprint", "aim", "fire"] or not packet.buttons[button] is bool: return
	for button: Variant in packet.pressed:
		if button not in ["jump", "dive", "sprint", "fire"] or not packet.pressed[button] is bool: return
	if int(packet.seq) <= int(peers[id].last_sequence): return
	peers[id].last_sequence = packet.seq
	peers[id].last_input = Time.get_ticks_msec()
	packet.move = packet.move.limit_length(1)
	packet.pitch = clampf(packet.pitch, -1.35, 1.30)
	packet.yaw = wrapf(packet.yaw, -PI, PI)
	# A short press must survive arrival between two host physics steps.
	var pressed: Dictionary = peers[id].input.get("pressed", {}).duplicate()
	pressed.merge(packet.pressed, true)
	packet.pressed = pressed
	peers[id].input = packet

func combat_targets(include_dogs: bool = false) -> Array[Node3D]:
	var result: Array[Node3D] = []
	var host_player: Node3D = _host_context.player if current_peer_id != 1 else game.player
	var host_dog: Node3D = _host_context.companion if current_peer_id != 1 else game.companion
	if is_instance_valid(host_player) and host_player.health > 0: result.append(host_player)
	if include_dogs and is_instance_valid(host_dog) and host_dog.health > 0: result.append(host_dog)
	for entry: Dictionary in peers.values():
		if is_instance_valid(entry.player) and entry.player.health > 0: result.append(entry.player)
		if include_dogs and is_instance_valid(entry.companion) and entry.companion.health > 0: result.append(entry.companion)
	return result

func on_died() -> void:
	if game.companion.try_revive(): return
	game.notify("Caído · retorno em 10s enquanto um parceiro sobreviver")
	if current_peer_id == 1: _host_respawn_at = game.elapsed + 10.0
	else: peers[current_peer_id].respawn_at = game.elapsed + 10.0

var _host_respawn_at := 0.0

func _tick_respawns() -> void:
	var alive := combat_targets()
	if alive.is_empty():
		if not _team_wiped:
			_team_wiped = true
			_team_defeat.rpc()
			game.running = false
			game.paused = true
			game._save_pending = false
			game._menu_kind = "dead"
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			game.ui.show_game_over(game.round_number, game.coins)
		return
	for id: int in [1] + peers.keys():
		var at := _host_respawn_at if id == 1 else float(peers[id].respawn_at)
		if at <= 0 or game.elapsed < at: continue
		with_peer(id, func():
			game.player.global_position = alive[0].global_position + Vector3(1.2, 0.25, 0)
			game.player.revive_from_companion(game.player.max_health * 0.6)
			game.player.damage_cooldown = 2.5
			game.notify("De volta com a equipe")
		)
		if id == 1: _host_respawn_at = 0
		else: peers[id].respawn_at = 0.0

@rpc("authority", "call_remote", "reliable", 0)
func _team_defeat() -> void:
	game.running = false
	game.paused = true
	game._menu_kind = "dead"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.ui.show_game_over(game.round_number, game.coins)

func reward_others(amount: int, source: String) -> void:
	if not is_host() or _rewarding_group: return
	_rewarding_group = true
	var origin := current_peer_id
	for id: int in [1] + peers.keys():
		if id == origin: continue
		with_peer(id, func():
			game.add_coins(amount, source)
			if source == "round":
				game.player.heal(12)
				game.player.add_ammo(12)
		)
	_rewarding_group = false

func notice(message: String) -> bool:
	if is_host() and current_peer_id != 1:
		_notice.rpc_id(current_peer_id, message)
		return true
	return false

func relay_announcement(title: String, subtitle: String) -> bool:
	if not is_host(): return false
	if current_peer_id != 1 and title not in ["DESAFIO COMPLETO", "CAMINHO ABERTO", "BOSS DERROTADO"]:
		_announcement.rpc_id(current_peer_id, title, subtitle)
		return true
	_announcement.rpc(title, subtitle)
	return false

@rpc("authority", "call_remote", "reliable", 0)
func _announcement(title: String, subtitle: String) -> void:
	game.ui.announce(title, subtitle)

@rpc("authority", "call_remote", "reliable", 0)
func _notice(message: String) -> void:
	game.ui.show_notice(message)

func damage_feedback(amount: float, source: Vector3, absorbed: bool) -> bool:
	if is_host() and current_peer_id != 1:
		_damage_feedback.rpc_id(current_peer_id, amount, source, absorbed)
		return true
	return false

@rpc("authority", "call_remote", "reliable", 0)
func _damage_feedback(amount: float, source: Vector3, absorbed: bool) -> void:
	game.on_player_damaged(amount, source, absorbed)

func shot_feedback(weapon: Dictionary, origin: Vector3, point: Vector3, hit: bool, head: bool) -> void:
	if is_host():
		var visual := {"model_id":weapon.get("model_id", weapon.get("id", "biscuit")), "recoil":weapon.get("recoil", 0.02), "critical":weapon.get("critical", false)}
		_shot_feedback.rpc(current_peer_id, visual, origin, point, hit, head)

@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _shot_feedback(id: int, weapon: Dictionary, origin: Vector3, point: Vector3, hit: bool, head: bool) -> void:
	game.on_shot(weapon, origin, point, hit if id == multiplayer.get_unique_id() else false, head)
	if id == multiplayer.get_unique_id():
		game.player.weapon_view.call("fire", float(weapon.get("recoil", 0.02)), game.player.aiming)
		game.player._pitch = clampf(game.player._pitch + float(weapon.get("recoil", 0.02)) * (0.6 if game.player.aiming else 1), -1.35, 1.30)

func grenade_feedback(at: Vector3, color: Color, radius: float) -> void:
	_grenade_feedback.rpc(at, color, radius)

@rpc("authority", "call_remote", "reliable", 2)
func _grenade_feedback(at: Vector3, color: Color, radius: float) -> void:
	game.audio.play("explosion")
	var pulse := _projectile_visual(color, radius)
	game.add_child(pulse)
	pulse.global_position = at
	game._track_effect(pulse, 0.25)

func _send_state() -> void:
	if not is_host() or peers.is_empty(): return
	_sequence += 1
	var actors: Dictionary = {1:personal_snapshot()}
	actors[1]["nickname"] = "Host"
	for id: int in peers:
		with_peer(id, func(): actors[id] = personal_snapshot())
		actors[id]["nickname"] = peers[id].get("nickname", "Jogador")
	var enemies: Array = []
	for enemy: Node in game.enemies:
		if not is_instance_valid(enemy) or enemy.dead: continue
		if not enemy.has_meta("net_id"):
			enemy.set_meta("net_id", _next_enemy_id)
			_next_enemy_id += 1
		var state: Dictionary = enemy.export_state()
		state["net_id"] = enemy.get_meta("net_id")
		state["special"] = enemy._special
		state["special_time"] = enemy._special_time
		state["special_duration"] = enemy._special_duration
		state["boss_windup"] = enemy._boss_windup
		state["windup"] = enemy._windup
		state["aim_position"] = enemy._aim_position
		var projectiles: Array = []
		for shot: Dictionary in enemy._projectiles:
			if is_instance_valid(shot.node): projectiles.append({"position":shot.node.global_position,"velocity":shot.velocity,"color":shot.node.material_override.albedo_color})
		state["projectiles"] = projectiles
		enemies.append(state)
	var exploration: Dictionary = game.exploration.export_state()
	var drops: Array = []
	for drop: Node3D in game.exploration.drops:
		if not is_instance_valid(drop) or drop.collected: continue
		if not drop.has_meta("net_id"):
			drop.set_meta("net_id", _next_drop_id)
			_next_drop_id += 1
		var state: Dictionary = drop.export_state()
		state["net_id"] = drop.get_meta("net_id")
		drops.append(state)
	exploration.drops = drops
	# Wallet, combat statistics and profile are sent only to their owning peer.
	var shared := {"seq":_sequence,"round":game.round_number,"elapsed":game.elapsed,"kills":game.kills,"difficulty":game.difficulty_id,"chaos":game.chaos_active,"seed":game.run_seed,"director":game.director.export_state(),"world":game.world.export_state(),"exploration":exploration,"enemies":enemies,"boss_zone":game.boss_zone}
	var grenades: Array = []
	for grenade: Node3D in get_tree().get_nodes_in_group("run_grenades"):
		if not grenade._detonated: grenades.append({"id":grenade.get_instance_id(),"position":grenade.global_position,"color":Color(grenade.config.color)})
	shared["grenades"] = grenades
	for recipient: int in peers:
		var roster: Dictionary = {}
		for id: int in actors:
			var actor: Dictionary = actors[id]
			roster[id] = actor if id == recipient else {"player":actor.player,"dog":actor.dog,"nickname":actor.nickname,"inventory":actor.inventory,"perks":actor.perks}
		_receive_state.rpc_id(recipient, shared, roster)

@rpc("authority", "call_remote", "reliable", 0)
func _receive_state(shared: Dictionary, roster: Dictionary) -> void:
	if not is_client() or int(shared.get("seq", -1)) <= _last_state_sequence: return
	var mine := multiplayer.get_unique_id()
	if not roster.has(mine): return
	_last_state_sequence = int(shared.seq)
	_last_state_time = Time.get_ticks_msec()
	mode = "client"
	if _initial_state: game._clear_run()
	game.difficulty_id = str(shared.difficulty)
	game.chaos_active = bool(shared.chaos)
	game.run_seed = int(shared.seed)
	game.elapsed = float(shared.elapsed)
	game.kills = int(shared.kills)
	game.director.import_state(shared.director)
	game._sync_director()
	var new_world_hash := hash(shared.world)
	if _initial_state or new_world_hash != _world_hash:
		_world_hash = new_world_hash
		game.world.import_state(shared.world)
	game.boss_zone = shared.boss_zone.duplicate(true)
	game.world.set_boss_arena(not game.boss_zone.is_empty())
	game.world.set_event(str(game.director.active_event.get("id", "")))
	if _initial_state:
		game._create_actors()
		game.player.network_peer_id = mine
		game.companion.network_peer_id = mine
		game.companion.network_replica = true
		_restore_personal(roster[mine])
		_local_ui_signature = _progression_signature(roster[mine])
		game.player.set_meta("network_equipment_signature", _equipment_signature(roster[mine]))
		game.running = true
		game.paused = false
		game._menu_kind = ""
		game.ui.hide_menus()
		game.player.show()
		game.player.camera.make_current()
		game.get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_initial_state = false
	else:
		_sync_local(roster[mine])
	for id: int in roster:
		if id == mine: continue
		if not peers.has(id):
			peers[id] = _new_actor(id)
			peers[id].player.network_replica = true
			peers[id].companion.network_replica = true
		with_peer(id, func():
			game.inventory.import_state(roster[id].inventory)
			game.progression.import_state(roster[id].perks)
			_sync_replica(game.player, roster[id].player, _equipment_signature(roster[id]))
			_sync_dog(game.companion, roster[id].dog)
		)
	for id: int in peers.keys():
		if not roster.has(id):
			_free_actor(peers[id])
			peers.erase(id)
	_sync_enemies(shared.enemies)
	_sync_grenades(shared.get("grenades", []))
	_sync_exploration(shared.exploration)
	status = "%s:%d · %d/%d jogadores · HP inimigos %.0f%%" % [last_address, port, roster.size(), MAX_PLAYERS, (1 + 0.8 * (roster.size() - 1)) * 100]

func _sync_local(data: Dictionary) -> void:
	var actor: Node = game.player
	var state: Dictionary = data.player
	var ui_signature := _progression_signature(data)
	var equipment_signature := _equipment_signature(data)
	var was_reloading: bool = actor.reloading
	game.inventory.import_state(data.inventory)
	game.progression.import_state(data.perks)
	game.coins = int(data.coins)
	game.stats = data.stats.duplicate(true)
	game.profile = data.profile.duplicate(true)
	game.active_powerups = data.powerups.duplicate(true)
	actor.health = float(state.health)
	actor.max_health = float(state.max_health)
	actor._dead = actor.health <= 0
	if int(actor.get_meta("network_equipment_signature", 0)) != equipment_signature:
		actor.sync_inventory()
		actor.set_meta("network_equipment_signature", equipment_signature)
	actor.magazine = int(state.magazine)
	actor.reserve = int(state.reserve)
	actor.reloading = bool(state.reloading)
	actor.reload_remaining = float(state.reload_remaining) if actor.reloading else 0.0
	actor.reload_duration = float(state.reload_duration)
	actor._reload_was_empty = bool(state.get("reload_was_empty", false))
	if actor.reloading and not was_reloading:
		actor._reload_phase = 0
		actor._play_sound("reload")
	elif not actor.reloading: actor._reload_phase = 0
	actor.shot_count = int(state.shot_count)
	actor._save_ammo()
	var at := _vector(state.position)
	# Client predicts its own movement. Authority corrects drift and handles respawns.
	var distance: float = actor.global_position.distance_to(at)
	if distance > 2.5 or actor._dead: actor.global_position = at
	elif distance > 0.35: actor.global_position = actor.global_position.lerp(at, 0.18)
	_sync_dog(game.companion, data.dog)
	if ui_signature != _local_ui_signature:
		_local_ui_signature = ui_signature
		if game._menu_kind == "inventory": game.ui.refresh_progression()

func _sync_replica(actor: Node3D, state: Dictionary, equipment_signature: int) -> void:
	_set_actor_target(actor, _vector(state.position), float(state.yaw))
	actor._pitch = float(state.pitch)
	actor.health = float(state.health)
	actor.max_health = float(state.max_health)
	actor.velocity = _vector(state.get("velocity", [0, 0, 0]))
	actor._dead = actor.health <= 0
	actor.set_crouched(bool(state.get("crouching", false)))
	if int(actor.get_meta("network_equipment_signature", 0)) != equipment_signature:
		actor.sync_inventory()
		actor.set_meta("network_equipment_signature", equipment_signature)
	actor.hero.visible = true
	actor.hero.rotation.z = 1.2 if actor._dead else 0.0
	actor.weapon_view.hide()
	actor.camera.current = false
	actor.third_person = true

func _sync_dog(dog: Node3D, state: Dictionary) -> void:
	var signature := hash(_dog_configuration(state))
	if int(dog.get_meta("network_configuration_signature", 0)) != signature:
		dog.import_state(state)
		dog.set_meta("network_configuration_signature", signature)
	var destination := _vector(state.position)
	dog.velocity = (destination - dog.global_position) / 0.1
	_set_actor_target(dog, destination, float(state.rotation_y))
	dog.health = float(state.health)
	dog.max_health = float(state.max_health)
	dog.shield = float(state.shield)
	dog._downed_time = float(state.downed_time)

func _weapon_configuration(item: Dictionary) -> Dictionary:
	var configuration := item.duplicate(true)
	# Ammunition is live HUD data; it must not rebuild a rig, preview or scroll tree.
	configuration.erase("magazine")
	configuration.erase("reserve")
	return configuration

func _inventory_configuration(state: Dictionary) -> Dictionary:
	var configuration := state.duplicate(true)
	var items: Array = []
	for item: Dictionary in state.get("items", []): items.append(_weapon_configuration(item))
	configuration["items"] = items
	return configuration

func _dog_configuration(state: Dictionary) -> Dictionary:
	var configuration: Dictionary = {}
	for key: String in ["levels", "archetype", "element", "owned_archetypes", "follow_only", "mode"]:
		configuration[key] = state.get(key)
	return configuration

func _equipment_signature(data: Dictionary) -> int:
	var inventory: Dictionary = data.inventory
	var uid: String = str(data.player.get("active_item_uid", inventory.get("equipped_id", "")))
	var equipped: Dictionary = {}
	for item: Dictionary in inventory.get("items", []):
		if str(item.get("uid", "")) == uid:
			equipped = _weapon_configuration(item)
			# Marking a favorite does not change the weapon model or its combat build.
			equipped.erase("favorite")
			equipped.erase("junk")
			break
	return hash([uid, equipped, data.perks, inventory.get("module_id", "balanced"), data.get("powerups", {}).has("overcharge")])

func _progression_signature(data: Dictionary) -> int:
	# Deliberately exclude health, pose, ammo, combat totals, cooldowns and timers.
	# Same-UID attachments/rolls, station perks, wallet, supplies and unlocks matter.
	return hash([_inventory_configuration(data.inventory), data.perks, data.coins,
		_dog_configuration(data.dog), data.profile.get("unlocks", []), game.round_number,
		game.difficulty_id, game.chaos_active, game.world.get_region_id(_vector(data.player.position))])

func _sync_enemies(states: Array) -> void:
	var existing: Dictionary = {}
	for enemy: Node in game.enemies:
		if is_instance_valid(enemy): existing[int(enemy.get_meta("net_id", -1))] = enemy
	var retained: Array = []
	for state: Dictionary in states:
		var id := int(state.net_id)
		var enemy: Node3D = existing.get(id)
		if not is_instance_valid(enemy):
			enemy = game._spawn_enemy_data({"kind":state.kind,"position":_vector(state.position),"wave_enemy":false})
			enemy.network_replica = true
			enemy.set_meta("net_id", id)
			enemy.import_state(state)
		var destination := _vector(state.position)
		enemy.velocity = (destination - enemy.global_position) / 0.1
		_set_actor_target(enemy, destination, float(state.rotation_y))
		enemy.health = float(state.health)
		enemy.max_health = float(state.max_health)
		enemy._special = str(state.special)
		enemy._special_time = float(state.special_time)
		enemy._special_duration = float(state.special_duration)
		enemy._boss_windup = float(state.boss_windup)
		enemy.boss_phase = int(state.boss_phase)
		enemy._windup = float(state.windup)
		enemy._aim_position = state.aim_position
		enemy._update_special_telegraph()
		if enemy._boss_windup > 0 and is_instance_valid(enemy._shock_ring):
			var progress: float = clampf(1.0 - enemy._boss_windup / 1.05, 0, 1)
			enemy._shock_ring.visible = true
			enemy._shock_ring.scale = Vector3(0.35 + progress * 0.65, 1, 0.35 + progress * 0.65)
			enemy._shock_ring.material_override.albedo_color.a = 0.18 + progress * 0.32
		_sync_projectiles(enemy, state.get("projectiles", []))
		retained.append(enemy)
	for enemy: Node in game.enemies:
		if is_instance_valid(enemy) and enemy not in retained: enemy.queue_free()
	game.enemies = retained

func _sync_exploration(state: Dictionary) -> void:
	var exploration: Node = game.exploration
	for key: String in ["used_pois", "discovered", "bosses_defeated", "challenge"]:
		exploration.set(key, state.get(key, {} if key in ["used_pois", "challenge"] else []).duplicate(true))
	var existing: Dictionary = {}
	for drop: Node3D in exploration.drops:
		if is_instance_valid(drop): existing[int(drop.get_meta("net_id", -1))] = drop
	var retained: Array[Node3D] = []
	for entry: Dictionary in state.drops:
		var drop: Node3D = existing.get(int(entry.net_id))
		if not is_instance_valid(drop):
			drop = exploration._create_drop(str(entry.kind), entry.payload, _vector(entry.position) - Vector3.UP * 0.07, true, false)
			drop.set_meta("net_id", int(entry.net_id))
		drop.payload = entry.payload.duplicate(true)
		retained.append(drop)
	for drop: Node3D in exploration.drops:
		if is_instance_valid(drop) and drop not in retained: drop.queue_free()
	exploration.drops = retained

func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _set_actor_target(actor: Node3D, at: Vector3, yaw: float) -> void:
	if not actor.has_meta("network_position") or actor.global_position.distance_to(at) > 6:
		actor.global_position = at
		actor.rotation.y = yaw
	actor.set_meta("network_position", at)
	actor.set_meta("network_yaw", yaw)

func _interpolate_actor(actor: Node3D, delta: float) -> void:
	if not actor.has_meta("network_position"): return
	actor.global_position = actor.global_position.lerp(actor.get_meta("network_position"), 1.0 - exp(-delta * 20.0))
	actor.rotation.y = lerp_angle(actor.rotation.y, float(actor.get_meta("network_yaw")), 1.0 - exp(-delta * 20.0))

func _projectile_visual(color: Color, radius: float = 0.12) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2
	sphere.radial_segments = 10
	sphere.rings = 5
	node.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color, 0.45) if radius > 1 else color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if radius > 1 else BaseMaterial3D.TRANSPARENCY_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = material
	return node

func _sync_projectiles(enemy: Node3D, states: Array) -> void:
	while enemy._projectiles.size() > states.size():
		var shot: Dictionary = enemy._projectiles.pop_back()
		if is_instance_valid(shot.node): shot.node.queue_free()
	for index: int in range(states.size()):
		var state: Dictionary = states[index]
		if index >= enemy._projectiles.size():
			var node := _projectile_visual(state.color)
			enemy.add_child(node)
			node.top_level = true
			enemy._projectiles.append({"node":node,"velocity":state.velocity})
		enemy._projectiles[index].node.global_position = state.position
		enemy._projectiles[index].velocity = state.velocity

func _sync_grenades(states: Array) -> void:
	var retained: Array = []
	for state: Dictionary in states:
		var id := int(state.id)
		if not _grenade_visuals.has(id):
			var node := _projectile_visual(state.color, 0.085)
			game.add_child(node)
			_grenade_visuals[id] = node
		_grenade_visuals[id].global_position = state.position
		retained.append(id)
	for id: int in _grenade_visuals.keys():
		if id not in retained:
			_grenade_visuals[id].queue_free()
			_grenade_visuals.erase(id)

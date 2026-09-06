class_name MeyuiSnapshotValidator
extends RefCounted
## Validate all nested containers before a live scene is replaced.
const REGIONS := ["patio","mercado","oficina","galeria","lajes","quadra"] + preload("res://scripts/world_expansion.gd").REGION_IDS
const KINDS := ["grunt","runner","tank","exploder","spitter","screamer","hunter","armored","parasite","summoner","stealth","boss","boss_captain","boss_bulwark","boss_conductor"]
const DOGS := ["combat","collector","support","guardian"]
const STATUS := ["burn","corrosive","bleed","cryo","frost","freeze","shock","frenzy"]
const POWERUPS := ["infinite_ammo","double_damage","frenzy","nuke","magnet","jackpot","overcharge"]
const Data = preload("res://data/game_data.gd")
const Loot = preload("res://data/loot_data.gd")
const Inventory = preload("res://scripts/inventory.gd")
const Progression = preload("res://scripts/run_progression.gd")
const Director = preload("res://scripts/run_director.gd")
const Dog = preload("res://data/dog_data.gd")

static func valid(state: Dictionary) -> bool:
	if not _json(state, 0): return false
	for key: String in ["inventory","director","player","perks","dog","world","exploration","stats","powerups","boss_zone"]:
		if not state.get(key) is Dictionary: return false
	if not _strict_nested(state): return false
	for key: String in ["coins","elapsed","kills","round_number"]:
		if not _number(state.get(key), 0): return false
	if not str(state.get("run_seed", "")).is_valid_int() or not str(state.get("rng_state", "")).is_valid_int(): return false
	var player: Dictionary = state["player"]
	if not position(player.get("position")) or not _number(player.get("health"), 0.001): return false
	for key: String in ["yaw","pitch","max_health","magazine","reserve"]:
		if player.has(key) and not _number(player[key], -2 if key == "pitch" else (-1e9 if key == "yaw" else 0)): return false
	for key: String in ["owned_weapons","upgrade_state"]:
		if player.has(key) and not player[key] is Dictionary: return false
	var perks: Dictionary = state["perks"]
	if not perks.get("levels", {}) is Dictionary: return false
	for value: Variant in perks.get("levels", {}).values():
		if not _number(value, 0): return false
	if not _enum_array(state["world"].get("unlocked_regions"), REGIONS): return false
	var dog: Dictionary = state["dog"]
	if dog.has("archetype") and not dog["archetype"] in DOGS: return false
	if dog.has("position") and not position(dog["position"]): return false
	for key: String in ["owned_archetypes","unlocked_archetypes"]:
		if dog.has(key) and not _enum_array(dog[key], DOGS): return false
	for key: String in ["health","max_health","level","revive_cooldown","downed_time","shield"]:
		if dog.has(key) and not _number(dog[key], 0): return false
	if dog.has("levels"):
		if not dog["levels"] is Dictionary: return false
		for value: Variant in dog["levels"].values():
			if not _number(value, 0): return false
	var director: Dictionary = state["director"]
	for key: String in ["round_number","wave_total","spawned","killed","version","phase_time","spawn_clock","elapsed","last_supply","chaos_level","summons","last_event_round","last_alive"]:
		if director.has(key) and not _number(director[key], -1e12): return false
	if not director.get("metrics", {}) is Dictionary or not director.get("active_event", {}) is Dictionary: return false
	var event: Dictionary = director.get("active_event", {})
	for key: String in ["remaining","duration"]:
		if event.has(key) and not _number(event[key], 0): return false
	if not state.get("enemies") is Array or state["enemies"].size() > 24: return false
	var wave_actors := 0
	for enemy: Variant in state["enemies"]:
		if not enemy is Dictionary or not str(enemy.get("kind", "")) in KINDS: return false
		if not position(enemy.get("position")) or not _number(enemy.get("health"), 0.001): return false
		# Both fields are optional in pre-retaliation checkpoints. The importer
		# supplies their legacy defaults only when absent, never for malformed data.
		if enemy.has("balance_version") and not _integer(enemy.balance_version, 1, 1000000): return false
		if enemy.has("dog_retaliation_cooldown"):
			if not _number(enemy.dog_retaliation_cooldown, 0) or float(enemy.dog_retaliation_cooldown) > 4.0: return false
		for key: String in ["max_health","round","speed","damage","reward","attack_cooldown","special_cooldown","boss_cooldown","boss_phase","rotation_y"]:
			if enemy.has(key) and not _number(enemy[key], -1e9 if key == "rotation_y" else 0): return false
		if not str(enemy.get("elite", "")) in ["","fire","vampiric","frenzy"]: return false
		if not str(enemy.get("boss_id", "")) in ["","captain","bulwark","conductor"]: return false
		if not enemy.get("statuses", {}) is Dictionary: return false
		for id: String in enemy.get("statuses", {}):
			var effect: Variant = enemy["statuses"][id]
			if not id in STATUS or not effect is Dictionary: return false
			if not _number(effect.get("power", 0), 0) or not _number(effect.get("duration", 0), 0): return false
		if bool(enemy.get("wave_enemy", true)): wave_actors += 1
	if wave_actors != int(director.get("spawned", 0)) - int(director.get("killed", 0)): return false
	var exploration: Dictionary = state["exploration"]
	for key: String in ["used_pois","challenge"]:
		if not exploration.get(key, {}) is Dictionary: return false
	for opened: Variant in exploration.get("used_pois", {}).values():
		if not _number(opened, 0): return false
	if not _enum_array(exploration.get("discovered", []), REGIONS): return false
	if not exploration.get("bosses_defeated", []) is Array: return false
	for boss: Variant in exploration.get("bosses_defeated", []):
		if not boss is String: return false
	var challenge: Dictionary = exploration.get("challenge", {})
	for key: String in ["remaining","kills","target"]:
		if challenge.has(key) and not _number(challenge[key], 0): return false
	if not exploration.get("drops", []) is Array or exploration.get("drops", []).size() > 96: return false
	for drop: Variant in exploration.get("drops", []):
		if not drop is Dictionary or not position(drop.get("position")): return false
		if not str(drop.get("kind", "")) in ["weapon","attachment","ammo","currency","powerup"]: return false
		if not drop.get("payload") is Dictionary or not _number(drop.get("lifetime", 0), 0): return false
	for value: Variant in state["stats"].values():
		if not _number(value, 0): return false
	return true

static func _enum_array(value: Variant, allowed: Array) -> bool:
	if not value is Array: return false
	for entry: Variant in value:
		if not entry is String or not entry in allowed: return false
	return true
static func _number(value: Variant, minimum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= 1e18
static func position(value: Variant) -> bool:
	if not value is Array or value.size() != 3: return false
	for component: Variant in value:
		if not _number(component, -10000) or float(component) > 10000: return false
	return true
static func _json(value: Variant, depth: int) -> bool:
	if depth > 30: return false
	if value is Dictionary:
		if value.size() > 10000: return false
		for key: Variant in value:
			if not _text(key, 256) or not _json(value[key], depth + 1): return false
		return true
	if value is Array:
		if value.size() > 10000: return false
		for item: Variant in value:
			if not _json(item, depth + 1): return false
		return true
	return value == null or value is bool or _text(value, 16384) or _number(value, -1e18)


static func _strict_nested(state: Dictionary) -> bool:
	if not _integer(state.get("round_number"), 1, 1000000000) or not _integer(state.get("coins"), 0, 1e18) or not _integer(state.get("kills"), 0, 1e18): return false
	if not _enum(state.get("difficulty"), Data.DIFFICULTIES.keys()) or not state.get("chaos", false) is bool: return false
	if not _rng_id(state.get("run_seed")) or not _rng_id(state.get("rng_state")): return false
	var inventory = Inventory.new()
	if not inventory.import_state(state.inventory): return false
	if not _player_state(state.player, inventory) or not _dog_state(state.dog): return false
	if not _director_state(state.director) or int(state.director.round_number) != int(state.round_number): return false
	if state.director.get("difficulty_id", "normal") != state.difficulty: return false
	if not state.perks.get("levels", {}) is Dictionary: return false
	for id: Variant in state.perks.get("levels", {}):
		if not Progression.PERKS.has(id) or not _integer(state.perks.levels[id], 0, 100000): return false
	if not _exploration_state(state.exploration, inventory): return false
	for id: Variant in state.powerups:
		if not _enum(id, POWERUPS) or not _number(state.powerups[id], 0) or float(state.powerups[id]) > 120: return false
	var zone: Dictionary = state.boss_zone
	if not zone.is_empty():
		if not _identifier(zone.get("id")) or not _enum(zone.get("region"), REGIONS): return false
	if not state.get("enemies") is Array: return false
	var zone_bosses: int = 0
	for enemy: Variant in state.enemies:
		if not enemy is Dictionary: return false
		if enemy.has("wave_enemy") and not enemy.wave_enemy is bool: return false
		if not _text(enemy.get("boss_zone_id", ""), 128): return false
		if not str(enemy.get("boss_zone_id", "")).is_empty():
			if zone.is_empty() or enemy.boss_zone_id != zone.id or not str(enemy.get("kind", "")).begins_with("boss"): return false
			zone_bosses += 1
		for key in ["round","reward","boss_phase"]:
			if enemy.has(key) and not _integer(enemy[key], 1 if key in ["round","boss_phase"] else 0, 1e18): return false
		if enemy.has("boss_phase") and int(enemy.boss_phase) > 3: return false
	if not zone.is_empty() and zone_bosses != 1: return false
	return true


static func _player_state(player: Dictionary, inventory: RefCounted) -> bool:
	if player.has("version") and not _integer(player.version, 1, 1): return false
	if not _enum(player.get("weapon_id"), Data.WEAPONS.keys()): return false
	# Match the player's own importer: typed identity values are ordinary strings.
	# Dictionary keys may still be StringNames because Godot normalizes them in JSON.
	if not player.get("active_item_uid", "") is String or not _text(player.get("active_item_uid", ""), 128): return false
	var uid: String = str(player.get("active_item_uid", ""))
	if not uid.is_empty() and (inventory.find_item(uid).is_empty() or uid != inventory.equipped_id): return false
	if inventory.equipped().get("model_id", "") != player.weapon_id: return false
	for key in ["third_person","flashlight_on","reloading","reload_was_empty","aim_toggle","sprint_toggle"]:
		if player.has(key) and not player[key] is bool: return false
	for key in ["heat","frenzy_remaining","haste_remaining","fire_cooldown","damage_cooldown","dash_cooldown","reload_remaining","reload_duration","dash_remaining","time"]:
		if player.has(key) and not _number(player[key], 0): return false
	for key in ["magazine","reserve","shot_count","burst_remaining"]:
		if player.has(key) and not _integer(player[key], 0, 1000000000): return false
	if int(player.get("burst_remaining", 0)) > 5: return false
	if float(player.get("reload_remaining", 0)) > float(player.get("reload_duration", 0)): return false
	for key in ["velocity","dash_direction"]:
		if player.has(key) and not position(player[key]): return false
	for key in ["rng_seed","rng_state"]:
		if player.has(key) and not _rng_id(player[key]): return false
	var triggers: Variant = player.get("trigger_counts", {})
	if not triggers is Dictionary or triggers.size() > 128: return false
	for id: Variant in triggers:
		if not id is String or not _identifier(id) or not _integer(triggers[id], 0, 1000000000): return false
	var combat: Variant = player.get("last_combat", {})
	if not combat is Dictionary: return false
	if not combat.is_empty():
		if not _number(combat.get("damage", 0), 0) or not _enum_array(combat.get("modifiers", []), Loot.MODIFIERS.keys()): return false
		if combat.get("modifiers", []).size() > 32: return false
	for key in ["owned_weapons","upgrade_state"]:
		if not player.get(key, {}) is Dictionary: return false
		for id: Variant in player.get(key, {}):
			if not Data.WEAPONS.has(id) or not player[key][id] is Dictionary: return false
			for value: Variant in player[key][id].values():
				if not _integer(value, 0, 1000000000): return false
	return true


static func _dog_state(dog: Dictionary) -> bool:
	if dog.has("version") and not _integer(dog.version, 1, 2): return false
	if dog.has("mode") and not _enum(dog.mode, ["hunt","follow"]): return false
	if dog.has("follow_only") and not dog.follow_only is bool: return false
	for key in ["shield_delay","attack_timer","heal_timer","ability_timer","rotation_y"]:
		# A companion with no healing ability legitimately has an elapsed negative
		# heal timer; import clamps that timer when an ability becomes available.
		if dog.has(key) and not _number(dog[key], -1e18 if key in ["heal_timer","rotation_y"] else 0): return false
	if dog.has("levels"):
		if not dog.levels is Dictionary: return false
		for id: Variant in dog.levels:
			if not Dog.BRANCHES.has(id) or not _integer(dog.levels[id], 0, 1000000000): return false
	if dog.has("level") and not _integer(dog.level, 1, 10000000000): return false
	if dog.has("owned_archetypes") and not _enum_array(dog.owned_archetypes, DOGS): return false
	if dog.has("archetype") and dog.has("owned_archetypes") and not dog.archetype in dog.owned_archetypes: return false
	return true


static func _director_state(director: Dictionary) -> bool:
	for key in ["round_number","wave_total","spawned","killed","version"]:
		if not director.has(key): return false
	for key in ["round_number","wave_total","spawned","killed","version","chaos_level","summons","last_event_round","last_alive"]:
		if director.has(key) and not _integer(director[key], 0, 1000000000): return false
	if not _enum(director.get("phase"), ["prepare","combat","rest"]): return false
	if director.has("event_boss_pending") and not director.event_boss_pending is bool: return false
	var metrics: Variant = director.get("metrics", {})
	if not metrics is Dictionary: return false
	for key in ["pressure","elapsed","spawn_interval"]:
		if metrics.has(key) and not _number(metrics[key], 0): return false
	if metrics.has("pressure") and float(metrics.pressure) > 1: return false
	if metrics.has("spawn_interval") and float(metrics.spawn_interval) <= 0: return false
	if metrics.has("region_id") and not _enum(metrics.region_id, REGIONS + [""]): return false
	if metrics.has("relief") and not metrics.relief is bool: return false
	var event: Variant = director.get("active_event", {})
	if not event is Dictionary: return false
	if not event.is_empty():
		if not _enum(event.get("id"), Director.EVENTS.keys()) or not _integer(event.get("round"), 1, 1000000000): return false
		if not _number(event.get("remaining"), 0): return false
		if event.has("name") and not _text(event.name, 256): return false
	return true


static func _exploration_state(exploration: Dictionary, inventory: RefCounted) -> bool:
	var challenge: Variant = exploration.get("challenge", {})
	if not challenge is Dictionary: return false
	if not challenge.is_empty():
		if not _identifier(challenge.get("id")) or not _text(challenge.get("name"), 256) or str(challenge.name).is_empty(): return false
		if not _enum(challenge.get("region"), REGIONS): return false
		if not _number(challenge.get("remaining"), 0) or not _integer(challenge.get("kills"), 0, 1000000000) or not _integer(challenge.get("target"), 1, 1000000000): return false
	if not exploration.get("used_pois", {}) is Dictionary: return false
	for id: Variant in exploration.get("used_pois", {}):
		if not _identifier(id) or not _integer(exploration.used_pois[id], 0, 1000000000): return false
	var drops: Variant = exploration.get("drops", [])
	if not drops is Array or drops.size() > 96: return false
	var pending: Variant = exploration.get("pending_rewards", [])
	if not pending is Array or pending.size() > 512: return false
	var all_rewards: Array = drops.duplicate()
	all_rewards.append_array(pending)
	var ids: Dictionary = {}
	for item: Dictionary in inventory.items:
		ids[item.uid] = true
		for part: Dictionary in item.attachments.values(): ids[part.uid] = true
	for part: Dictionary in inventory.attachments: ids[part.uid] = true
	for drop: Variant in all_rewards:
		if not drop is Dictionary or not drop.get("payload") is Dictionary: return false
		if not position(drop.get("position")) or not _number(drop.get("lifetime", 0), 0): return false
		var payload: Dictionary = drop.payload
		match str(drop.get("kind", "")):
			"weapon":
				if not inventory._valid_weapon(payload): return false
				if ids.has(payload.uid): return false
				ids[payload.uid] = true
				for part: Dictionary in payload.attachments.values():
					if ids.has(part.uid): return false
					ids[part.uid] = true
			"attachment":
				if not inventory._valid_attachment(payload) or ids.has(payload.uid): return false
				ids[payload.uid] = true
			"ammo", "currency":
				if not _integer(payload.get("amount"), 1, 1e18): return false
			"powerup":
				if not _enum(payload.get("id"), POWERUPS): return false
			_:
				return false
	return true


static func _text(value: Variant, maximum: int) -> bool:
	return (value is String or value is StringName) and str(value).length() <= maximum

static func _identifier(value: Variant) -> bool:
	return _text(value, 128) and not str(value).is_empty()

static func _enum(value: Variant, options: Array) -> bool:
	return _text(value, 128) and str(value) in options

static func _integer(value: Variant, minimum: float, maximum: float) -> bool:
	return _number(value, minimum) and float(value) <= maximum and float(value) == floor(float(value))

static func _rng_id(value: Variant) -> bool:
	return value is String and _text(value, 20) and str(value).is_valid_int()

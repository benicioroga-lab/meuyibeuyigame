class_name MeyuiRunDirector
extends RefCounted
## The coordinator performs each returned action once. Spawn actions reserve their
## wave slot immediately; saves restore both these counters and live actor snapshots.

const Data = preload("res://data/game_data.gd")
const MAX_ALIVE: int = 24
const MAX_SUMMONS: int = 4
const EVENTS: Dictionary = {
	"blackout": {"id": "blackout", "name": "Apagão", "duration": 32.0},
	"storm": {"id": "storm", "name": "Tempestade de cinzas", "duration": 38.0},
	"elite_invasion": {"id": "elite_invasion", "name": "Caçada dos marcados", "duration": 35.0},
	"double_loot": {"id": "double_loot", "name": "Maré de espólios", "duration": 30.0},
	"supply": {"id": "supply", "name": "Suprimentos esquecidos", "duration": 18.0},
	"boss_hunt": {"id": "boss_hunt", "name": "A criatura do morro", "duration": 45.0},
}
const UNLOCKS: Array = [
	[1, "grunt"], [2, "runner"], [3, "tank"], [4, "exploder"],
	[6, "spitter"], [8, "screamer"], [10, "hunter"], [12, "armored"],
	[14, "parasite"], [17, "summoner"], [20, "stealth"], [23, "elite"],
]

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var difficulty_id: String = "normal"
var chaos_level: int = 0
var round_number: int = 1
var phase: String = "prepare"
var phase_time: float = 3.0
var wave_total: int = 6
var spawned: int = 0
var killed: int = 0
var active_event: Dictionary = {}
var metrics: Dictionary = {}
var _spawn_clock: float = 0.0
var _summons: int = 0
var _elapsed: float = 0.0
var _last_supply: float = -90.0
var _last_event_round: int = 0
var _event_boss_pending: bool = false
var _last_alive: int = 0


func start(selected_difficulty: String, selected_chaos_level: int = 0, run_seed: int = 0) -> void:
	difficulty_id = selected_difficulty if Data.DIFFICULTIES.has(selected_difficulty) else "normal"
	chaos_level = clampi(selected_chaos_level, 0, 10)
	if run_seed == 0:
		rng.randomize()
	else:
		rng.seed = run_seed
	round_number = 1
	phase = "prepare"
	phase_time = 3.0
	wave_total = _population(1)
	spawned = 0
	killed = 0
	active_event.clear()
	metrics = {"pressure": 0.0, "relief": false, "elapsed": 0.0, "region_id": "", "spawn_interval": 1.3}
	_spawn_clock = 0.0
	_summons = 0
	_elapsed = 0.0
	_last_supply = -90.0
	_last_event_round = 0
	_event_boss_pending = false
	_last_alive = 0


func tick(delta: float, state: Dictionary) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if not is_finite(delta) or delta <= 0.0:
		return actions
	var dt := minf(delta, 5.0)
	_elapsed += dt
	_last_alive = maxi(0, int(state.get("alive", maxi(0, spawned - killed))))
	_update_metrics(dt, state)
	_update_event(dt, actions)
	if phase == "prepare" or phase == "rest":
		phase_time = maxf(0.0, phase_time - dt)
		if phase_time <= 0.0:
			if phase == "rest":
				round_number += 1
				wave_total = _population(round_number)
				spawned = 0
				killed = 0
				_summons = 0
			phase = "combat"
			_spawn_clock = 0.15
			actions.append({"type": "round_start", "round": round_number, "total": wave_total})
			_start_round_event(actions)
		return actions
	if phase != "combat":
		return actions
	if spawned >= wave_total and killed >= wave_total and _last_alive == 0:
		phase = "rest"
		phase_time = 8.0 + (4.0 if bool(metrics.get("relief", false)) else 0.0)
		actions.append({"type": "round_complete", "round": round_number, "reward": _round_reward()})
		return actions
	# Low resources grant breathing room and a real supply event, at most once per 90s.
	if bool(metrics.get("relief", false)) and active_event.is_empty() and _elapsed - _last_supply >= 90.0:
		_begin_event("supply", actions)
	_spawn_clock -= dt
	var available := mini(MAX_ALIVE - _last_alive, wave_total - spawned)
	var batch := 0
	while _spawn_clock <= 0.0 and available > 0 and batch < 3:
		var kind := _choose_kind()
		var elite: bool = kind == "elite" or (active_event.get("id", "") == "elite_invasion" and spawned % 3 == 0)
		var world_boss := round_number >= 25 and kind.begins_with("boss") and rng.randf() < 0.16
		actions.append({"type": "spawn", "kind": kind, "elite": elite, "wave_enemy": true, "world_boss": world_boss})
		spawned += 1
		available -= 1
		batch += 1
		_spawn_clock += float(metrics["spawn_interval"])
	# A full street never accumulates a burst larger than the bounded next batch.
	_spawn_clock = maxf(_spawn_clock, -float(metrics["spawn_interval"]))
	_last_alive += batch
	return actions


func register_kill(wave_enemy: bool = true) -> void:
	if wave_enemy and phase == "combat":
		killed = mini(spawned, killed + 1)
	_last_alive = maxi(0, _last_alive - 1)


func add_summon() -> bool:
	if phase != "combat" or _summons >= MAX_SUMMONS or _last_alive >= MAX_ALIVE:
		return false
	_summons += 1
	wave_total += 1
	spawned += 1
	_last_alive += 1
	return true


func force_rest(seconds: float = 8.0) -> void:
	phase = "rest"
	phase_time = clampf(seconds, 0.0, 120.0) if is_finite(seconds) else 8.0
	spawned = wave_total
	killed = wave_total
	_last_alive = 0


func force_event(event_id: String) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if EVENTS.has(event_id) and active_event.is_empty():
		_begin_event(event_id, actions)
	return actions


func get_modifiers() -> Dictionary:
	var result := {"loot": 1.0 + chaos_level * 0.12, "reward": 1.0 + chaos_level * 0.15,
		"enemy_damage": 1.0 + chaos_level * 0.06, "enemy_speed": 1.0 + minf(chaos_level * 0.025, 0.2),
		"visibility": 1.0, "ambient": 1.0, "supply": false, "boss_hunt": false}
	match str(active_event.get("id", "")):
		"blackout":
			result["visibility"] = 0.38
			result["ambient"] = 0.22
			result["reward"] *= 1.3
		"storm":
			result["visibility"] = 0.68
			result["enemy_speed"] *= 0.9
			result["loot"] *= 1.25
		"elite_invasion":
			result["loot"] *= 1.5
		"double_loot":
			result["loot"] *= 2.0
		"supply":
			result["supply"] = true
		"boss_hunt":
			result["boss_hunt"] = true
			result["reward"] *= 1.5
	return result


func export_state() -> Dictionary:
	return {"version": 1, "difficulty_id": difficulty_id, "chaos_level": chaos_level,
		"round_number": round_number, "phase": phase, "phase_time": phase_time,
		"wave_total": wave_total, "spawned": spawned, "killed": killed,
		"active_event": active_event.duplicate(true), "metrics": metrics.duplicate(true),
		"rng_seed": str(rng.seed), "rng_state": str(rng.state), "spawn_clock": _spawn_clock,
		"summons": _summons, "elapsed": _elapsed, "last_supply": _last_supply,
		"last_event_round": _last_event_round, "event_boss_pending": _event_boss_pending, "last_alive": _last_alive}


func import_state(state: Dictionary) -> bool:
	# Validate before mutation so a rejected save leaves the current run intact.
	for key in ["version", "wave_total", "spawned", "killed", "round_number"]:
		if not _valid_number(state.get(key)):
			return false
	for key in ["phase_time", "spawn_clock", "elapsed", "last_supply", "summons", "last_event_round", "last_alive", "chaos_level"]:
		if state.has(key) and not _valid_number(state[key]):
			return false
	var saved_phase := str(state.get("phase", ""))
	var total := int(state.get("wave_total", 0))
	var sent := int(state.get("spawned", -1))
	var dead := int(state.get("killed", -1))
	var round_value := int(state.get("round_number", 0))
	var event: Variant = state.get("active_event", {})
	if int(state.get("version", 0)) != 1 or not saved_phase in ["prepare", "combat", "rest"]:
		return false
	if round_value < 1 or total < 1 or dead < 0 or sent < dead or sent > total:
		return false
	if not event is Dictionary or (not event.is_empty() and not EVENTS.has(str(event.get("id", "")))):
		return false
	if not event.is_empty():
		if not _valid_number(event.get("remaining")) or not _valid_number(event.get("round")):
			return false
	for key in ["phase_time", "spawn_clock", "elapsed", "last_supply"]:
		if not is_finite(float(state.get(key, 0.0))):
			return false
	if not str(state.get("rng_seed", "")).is_valid_int() or not str(state.get("rng_state", "")).is_valid_int():
		return false
	start(str(state.get("difficulty_id", "normal")), int(state.get("chaos_level", 0)), int(state["rng_seed"]))
	rng.state = int(state["rng_state"])
	round_number = round_value
	phase = saved_phase
	phase_time = maxf(0.0, float(state.get("phase_time", 0.0)))
	wave_total = total
	spawned = sent
	killed = dead
	if not event.is_empty():
		active_event = EVENTS[str(event["id"])].duplicate(true)
		active_event["remaining"] = clampf(float(event.get("remaining", 0.0)), 0.0, float(active_event["duration"]))
		active_event["round"] = maxi(1, int(event.get("round", round_number)))
	var saved_metrics: Variant = state.get("metrics", {})
	if saved_metrics is Dictionary:
		metrics.merge(saved_metrics, true)
	_spawn_clock = float(state.get("spawn_clock", 0.0))
	_summons = clampi(int(state.get("summons", 0)), 0, MAX_SUMMONS)
	_elapsed = maxf(0.0, float(state.get("elapsed", 0.0)))
	_last_supply = float(state.get("last_supply", -90.0))
	_last_event_round = maxi(0, int(state.get("last_event_round", 0)))
	_event_boss_pending = bool(state.get("event_boss_pending", false))
	_last_alive = clampi(int(state.get("last_alive", sent - dead)), 0, MAX_ALIVE)
	return true


func _valid_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))


func _population(number: int) -> int:
	var count_scale := float(Data.DIFFICULTIES[difficulty_id].get("count", 1.0))
	var growth := float(number - 1)
	return maxi(4, roundi((6.0 + growth * 1.65 + pow(growth, 1.12) * 0.12) * count_scale * (1.0 + chaos_level * 0.05)))


func _round_reward() -> int:
	return roundi((65.0 + round_number * 22.0) * float(Data.DIFFICULTIES[difficulty_id].get("reward", 1.0)) * float(get_modifiers()["reward"]))


func _update_metrics(dt: float, state: Dictionary) -> void:
	var health := clampf(float(state.get("health_ratio", 1.0)), 0.0, 1.0)
	var ammo := clampf(float(state.get("ammo_ratio", 1.0)), 0.0, 1.0)
	var relief := health < 0.28 or ammo < 0.12
	var target := clampf(float(_last_alive) / MAX_ALIVE * 0.6 + (1.0 - health) * 0.4, 0.0, 1.0)
	metrics["pressure"] = lerpf(float(metrics.get("pressure", 0.0)), target, 1.0 - exp(-dt * 1.5))
	metrics["relief"] = relief
	metrics["elapsed"] = _elapsed
	metrics["region_id"] = str(state.get("region_id", ""))
	var interval := maxf(0.38, 1.3 / (1.0 + log(float(round_number)) * 0.28))
	if relief:
		interval *= 1.8
	elif float(state.get("kills_per_second", 0.0)) > 1.1 and float(state.get("seconds_without_damage", 0.0)) > 10.0:
		interval *= 0.86
	metrics["spawn_interval"] = interval


func _choose_kind() -> String:
	if spawned == 0 and round_number % 5 == 0:
		return ["boss", "boss_bulwark", "boss_conductor"][int(round_number / 5 - 1) % 3]
	if _event_boss_pending:
		_event_boss_pending = false
		return "boss_bulwark" if round_number >= 15 else "boss"
	# Theme waves produce recognizable threats while keeping a majority of basics.
	if spawned % 3 == 1:
		if round_number >= 12 and round_number % 7 == 0:
			return "armored"
		if round_number >= 4 and round_number % 6 == 0:
			return "exploder"
		if round_number >= 3 and round_number % 4 == 0:
			return "runner"
	if rng.randf() < 0.48:
		return "grunt"
	var available: Array[String] = []
	for entry: Array in UNLOCKS:
		if round_number >= int(entry[0]):
			available.append(str(entry[1]))
	return available[rng.randi_range(0, available.size() - 1)]


func _start_round_event(actions: Array[Dictionary]) -> void:
	if not active_event.is_empty() or round_number < 3 or _last_event_round == round_number:
		return
	if round_number % 3 != 0 and rng.randf() > 0.14 + chaos_level * 0.02:
		return
	var options: Array[String] = ["blackout", "storm", "elite_invasion", "double_loot", "supply"]
	if round_number >= 8 and round_number % 5 != 0:
		options.append("boss_hunt")
	_begin_event(options[rng.randi_range(0, options.size() - 1)], actions)


func _begin_event(event_id: String, actions: Array[Dictionary]) -> void:
	active_event = EVENTS[event_id].duplicate(true)
	active_event["remaining"] = float(active_event["duration"])
	active_event["round"] = round_number
	_last_event_round = round_number
	if event_id == "supply":
		_last_supply = _elapsed
	if event_id == "boss_hunt":
		_event_boss_pending = true
	actions.append({"type": "event_start", "event": active_event.duplicate(true), "reward": 0})


func _update_event(dt: float, actions: Array[Dictionary]) -> void:
	if active_event.is_empty():
		return
	active_event["remaining"] = maxf(0.0, float(active_event.get("remaining", 0.0)) - dt)
	if float(active_event["remaining"]) <= 0.0:
		var finished := active_event.duplicate(true)
		active_event.clear()
		_event_boss_pending = false
		var reward := 0 if finished["id"] in ["supply", "double_loot"] else roundi(35.0 + round_number * 9.0)
		actions.append({"type": "event_complete", "event": finished, "reward": reward})

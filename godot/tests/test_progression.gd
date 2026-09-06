extends SceneTree
## Long-run progression invariants, actual stat gains and JSON continuation.
const Progression = preload("res://scripts/run_progression.gd")
var _checks: int = 0
var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var progression = Progression.new()
	_check(progression.modifiers().damage == 1.0 and progression.modifiers().resistance == 0.0, "New runs start at base damage without free armor")
	_check(not progression.increment("unknown") and progression.cost("unknown") == 0, "Unknown upgrades cannot change a build")
	for id: String in Progression.PERKS:
		var branch = Progression.new()
		var stat: String = Progression.PERKS[id].stat
		var start_value: float = branch.modifiers()[stat]
		var start_cost: int = branch.cost(id)
		_check(branch.increment(id), "First purchase exists: " + id)
		_check(float(branch.modifiers()[stat]) > start_value, "First rank changes its advertised stat: " + id)
		_check(branch.cost(id) > start_cost, "Next rank becomes more expensive: " + id)
		for rank in range(999):
			branch.increment(id)
		var high_value: float = branch.modifiers()[stat]
		var high_cost: int = branch.cost(id)
		_check(int(branch.levels[id]) == 1000 and is_finite(high_value) and high_cost > start_cost, "Rank 1000 remains finite and purchasable: " + id)
		branch.increment(id)
		_check(float(branch.modifiers()[stat]) > high_value and branch.cost(id) > high_cost, "Rank 1001 still has an actual gain: " + id)
		progression.levels[id] = 1000
	var stats: Dictionary = progression.modifiers()
	_check(stats.move_speed < 1.52 and stats.jump < 1.4, "Late mobility keeps map traversal readable")
	_check(stats.resistance < 0.45 and stats.crit_chance < 0.34, "Defensive and crit branches retain bounded probabilities")
	_check(stats.damage > 1.8 and stats.max_health > 3.0 and stats.reload > 2.4, "Long builds substantially improve offense, health and handling")
	var before: Dictionary = progression.export_state()
	var rows: Array = progression.describe()
	_check(rows.size() == Progression.PERKS.size() and before == progression.export_state(), "Previewing every branch neither buys nor removes levels")
	for row: Dictionary in rows:
		_check(row.has("value") and row.has("next_value") and row.has("cost") and row.has("icon"), "Upgrade row carries comparison and shared icon: " + row.id)
	var restored = Progression.new()
	restored.import_state(JSON.parse_string(JSON.stringify(progression.export_state())))
	_check(restored.modifiers() == progression.modifiers(), "All branch ranks round trip through JSON")
	var exported: Dictionary = restored.export_state()
	exported.levels.force = 1
	_check(restored.levels.force == 1000, "Snapshot does not alias active progression")
	print("PROGRESSION TESTS: %d checks, %d failures" % [_checks, _failures.size()])
	for failure in _failures:
		printerr(failure)
	quit(0 if _failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)

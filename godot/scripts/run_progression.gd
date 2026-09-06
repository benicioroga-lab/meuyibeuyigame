class_name MeyuiRunProgression
extends RefCounted

## Each branch changes an actual player modifier; no hard purchase ceiling.
const PERKS: Dictionary = {
	"fleet": {"name":"Passo leve", "icon":"speed", "branch":"mobility", "cost":100, "stat":"move_speed", "format":"×%.2f"},
	"spring": {"name":"Salto de telhado", "icon":"jump", "branch":"mobility", "cost":100, "stat":"jump", "format":"×%.2f"},
	"hands": {"name":"Mãos rápidas", "icon":"reload", "branch":"handling", "cost":125, "stat":"reload", "format":"×%.2f"},
	"switch": {"name":"Saque ligeiro", "icon":"weapon", "branch":"handling", "cost":90, "stat":"equip_speed", "format":"×%.2f"},
	"heart": {"name":"Fôlego de ferro", "icon":"heart", "branch":"survival", "cost":135, "stat":"max_health", "format":"×%.2f"},
	"regen": {"name":"Segundo fôlego", "icon":"heal", "branch":"survival", "cost":160, "stat":"regen", "format":"%.1f/s"},
	"armor": {"name":"Casca grossa", "icon":"shield", "branch":"survival", "cost":180, "stat":"resistance", "format":"%.2f"},
	"eye": {"name":"Olho clínico", "icon":"critical", "branch":"critical", "cost":145, "stat":"crit_chance", "format":"+%.2f"},
	"execution": {"name":"Ponto fraco", "icon":"target", "branch":"critical", "cost":190, "stat":"crit_multiplier", "format":"×%.2f"},
	"pockets": {"name":"Bolsos fundos", "icon":"ammo", "branch":"scavenger", "cost":110, "stat":"ammo_capacity", "format":"×%.2f"},
	"fortune": {"name":"Faro de fortuna", "icon":"star", "branch":"scavenger", "cost":170, "stat":"loot_luck", "format":"×%.2f"},
	"force": {"name":"Impacto persistente", "icon":"damage", "branch":"power", "cost":180, "stat":"damage", "format":"×%.2f"}
}
var levels: Dictionary = {}

func cost(id: String) -> int:
	if not PERKS.has(id): return 0
	var level := int(levels.get(id, 0))
	return roundi(float(PERKS[id]["cost"]) * (1.0 + level * 0.55 + pow(float(level), 1.25) * 0.3))

func increment(id: String) -> bool:
	if not PERKS.has(id): return false
	levels[id] = int(levels.get(id, 0)) + 1
	return true

func modifiers() -> Dictionary:
	return {"damage":1.0 + _log_level("force") * 0.09,
		"move_speed":1.0 + 0.52 * _soft("fleet", 6.0),
		"jump":1.0 + 0.4 * _soft("spring", 6.0),
		"reload":1.0 + _log_level("hands") * 0.16,
		"equip_speed":1.0 + _log_level("switch") * 0.2,
		"max_health":1.0 + _log_level("heart") * 0.22,
		"regen":_log_level("regen") * 0.8,
		"resistance":0.45 * _soft("armor", 7.0),
		"crit_chance":0.34 * _soft("eye", 7.0),
		"crit_multiplier":1.0 + _log_level("execution") * 0.13,
		"ammo_capacity":1.0 + _log_level("pockets") * 0.22,
		"loot_luck":1.0 + _log_level("fortune") * 0.15}

func describe() -> Array:
	var result: Array = []
	var current := modifiers()
	for id: String in PERKS:
		var row: Dictionary = PERKS[id].duplicate()
		row["id"] = id
		row["level"] = int(levels.get(id, 0))
		row["cost"] = cost(id)
		row["value"] = str(PERKS[id]["format"]) % float(current[row["stat"]])
		levels[id] = row["level"] + 1
		row["next_value"] = str(PERKS[id]["format"]) % float(modifiers()[row["stat"]])
		levels[id] = row["level"]
		result.append(row)
	return result

func export_state() -> Dictionary:
	return {"levels":levels.duplicate(true)}

func import_state(data: Dictionary) -> void:
	levels.clear()
	var source: Dictionary = data.get("levels", {})
	for id: String in PERKS:
		levels[id] = clampi(int(source.get(id, 0)), 0, 100000)

func _log_level(id: String) -> float:
	return log(1.0 + float(levels.get(id, 0))) / log(2.0)

func _soft(id: String, scale: float) -> float:
	var level := float(levels.get(id, 0))
	return level / (level + scale)

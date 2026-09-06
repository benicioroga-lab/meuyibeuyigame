class_name MeyuiEnemyData
extends RefCounted

## All hostile silhouettes and equipment belong to the fictional Liga do Ruído.
const BALANCE_VERSION: int = 2
const ARCHETYPES: Dictionary = {
	"grunt": {"name": "Batedor", "health": 42.0, "speed": 2.2, "cap": 3.8, "damage": 22.0, "attack_interval": 1.15, "windup": 0.3, "reward": 16, "reach": 1.4, "scale": 1.0, "special": ""},
	"runner": {"name": "Corredor", "health": 30.0, "speed": 3.2, "cap": 4.5, "damage": 18.0, "attack_interval": 1.0, "windup": 0.3, "reward": 18, "reach": 1.3, "scale": 0.95, "special": ""},
	"tank": {"name": "Brutamontes", "health": 110.0, "speed": 1.7, "cap": 2.8, "damage": 32.0, "attack_interval": 1.35, "windup": 0.38, "reward": 32, "reach": 1.6, "scale": 1.12, "special": ""},
	"exploder": {"name": "Estopim", "health": 40.0, "speed": 2.5, "cap": 3.6, "damage": 36.0, "attack_interval": 1.2, "windup": 0.34, "reward": 25, "reach": 1.3, "scale": 1.0, "special": "explode"},
	"spitter": {"name": "Corrosivo", "health": 48.0, "speed": 2.0, "cap": 3.1, "damage": 22.0, "attack_interval": 1.2, "windup": 0.3, "reward": 26, "reach": 1.2, "scale": 1.0, "special": "spit"},
	"screamer": {"name": "Alarme", "health": 58.0, "speed": 2.05, "cap": 3.1, "damage": 20.0, "attack_interval": 1.2, "windup": 0.32, "reward": 30, "reach": 1.3, "scale": 1.04, "special": "scream"},
	"hunter": {"name": "Caçador", "health": 65.0, "speed": 2.8, "cap": 4.5, "damage": 26.0, "attack_interval": 1.15, "windup": 0.34, "reward": 30, "reach": 1.5, "scale": 1.02, "special": "leap"},
	"armored": {"name": "Blindado", "health": 90.0, "speed": 1.95, "cap": 3.0, "damage": 28.0, "attack_interval": 1.2, "windup": 0.36, "reward": 34, "reach": 1.5, "scale": 1.08, "special": ""},
	"parasite": {"name": "Parasita", "health": 24.0, "speed": 3.3, "cap": 4.7, "damage": 18.0, "attack_interval": 1.0, "windup": 0.3, "reward": 17, "reach": 1.1, "scale": 0.62, "special": ""},
	"summoner": {"name": "Sintonizador", "health": 85.0, "speed": 1.6, "cap": 2.7, "damage": 20.0, "attack_interval": 1.2, "windup": 0.34, "reward": 42, "reach": 1.3, "scale": 1.07, "special": "summon"},
	"stealth": {"name": "Vulto", "health": 38.0, "speed": 2.7, "cap": 4.0, "damage": 28.0, "attack_interval": 1.15, "windup": 0.34, "reward": 30, "reach": 1.3, "scale": 0.98, "special": ""},
	"boss": {"name": "Capitão do Ruído", "health": 650.0, "speed": 2.15, "cap": 3.7, "damage": 42.0, "attack_interval": 1.35, "windup": 0.42, "reward": 180, "reach": 1.9, "scale": 1.3, "special": "boss"},
}

const ELITES: Dictionary = {
	"fire": {"name": "Incendiário", "health": 1.35, "damage": 1.16, "speed": 1.0, "color": Color("ff9d45")},
	"vampiric": {"name": "Vampírico", "health": 1.3, "damage": 1.0, "speed": 1.04, "color": Color("ef739e")},
	"frenzy": {"name": "Frenético", "health": 1.16, "damage": 1.12, "speed": 1.24, "color": Color("c4a1ff")},
}

const BOSSES: Dictionary = {
	"captain": {"name": "Capitão do Ruído", "pattern": "pulse", "color": Color("ffb966")},
	"bulwark": {"name": "Muralha da Liga", "pattern": "charge", "color": Color("80b7ef")},
	"conductor": {"name": "Maestro da Estática", "pattern": "summon", "color": Color("c997ff")},
}

static func definition(id: String) -> Dictionary:
	return Dictionary(ARCHETYPES.get(id, ARCHETYPES["grunt"])).duplicate(true)

static func boss_for_round(round_number: int) -> String:
	return ["captain", "bulwark", "conductor"][posmod(round_number / 5 - 1, 3)]

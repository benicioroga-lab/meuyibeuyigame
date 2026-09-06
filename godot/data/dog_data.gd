class_name MeyuiDogData
extends RefCounted

const BRANCHES: Dictionary = {
	"attack": {"name": "Ataque", "base_cost": 180, "description": "Mordida mais forte, ataques frequentes e mobilidade."},
	"survival": {"name": "Sobrevivência", "base_cost": 160, "description": "Mais vida, resistência e recuperação rápida."},
	"loot": {"name": "Farejador", "base_cost": 150, "description": "Recolhe recursos próximos com alcance crescente."},
	"support": {"name": "Apoio", "base_cost": 190, "description": "Cura periódica. Nível 3 libera resgate de emergência."},
	"elemental": {"name":"Afinidade", "base_cost":240, "description":"Mordidas elementais. Escolha fogo, choque ou gelo; aumente a potência."},
	"control": {"name":"Caçador", "base_cost":210, "description":"Mordidas interrompem ataques. Nível 3 alcança também um inimigo próximo."},
	"resupply": {"name":"Intendente", "base_cost":220, "description":"Gera pequena reserva de munição periodicamente quando perto de você."},
	"bond": {"name":"Vínculo vital", "base_cost":250, "description":"Mordidas recuperam sua vida e a do Faro. Combina com ataque rápido."},
}

const ARCHETYPES: Dictionary = {
	"combat": {"name": "Faro · Combatente", "cost": 0, "color": Color("e6b766"), "description": "Avança contra a Liga e interrompe inimigos."},
	"collector": {"name": "Faro · Coletor", "cost": 320, "color": Color("89d7a0"), "description": "Fareja e recolhe recursos enquanto acompanha você."},
	"support": {"name": "Faro · Apoio", "cost": 480, "color": Color("7ec5ef"), "description": "Cura você e pode resgatar após um golpe fatal."},
	"guardian": {"name": "Faro · Guardião", "cost": 560, "color": Color("b4a0e4"), "description": "Atrai a horda e absorve dano com um escudo recarregável."},
}

static func branch_cost(branch: String, branch_level: int) -> int:
	if not BRANCHES.has(branch):
		return -1
	# Polynomial prices keep unlimited levels useful without exponential overflow.
	return maxi(1, roundi(minf(9.0e15, float(BRANCHES[branch]["base_cost"]) * pow(1.0 + float(maxi(0, branch_level)), 1.35))))

static func stats(levels: Dictionary, archetype: String) -> Dictionary:
	var attack: float = log(1.0 + float(maxi(0, int(levels.get("attack", 0))))) / log(2.0)
	var survival: float = sqrt(float(maxi(0, int(levels.get("survival", 0)))))
	var loot: float = sqrt(float(maxi(0, int(levels.get("loot", 0)))))
	var support: float = log(1.0 + float(maxi(0, int(levels.get("support", 0))))) / log(2.0)
	var elemental := log(1.0 + float(maxi(0, int(levels.get("elemental", 0))))) / log(2.0)
	var control := sqrt(float(maxi(0, int(levels.get("control", 0)))))
	var resupply := log(1.0 + float(maxi(0, int(levels.get("resupply", 0))))) / log(2.0)
	var bond := log(1.0 + float(maxi(0, int(levels.get("bond", 0))))) / log(2.0)
	var damage: float = (12.0 + attack * 6.0) * (0.75 if archetype in ["collector", "support"] else 1.0)
	var max_health: float = (70.0 + survival * 18.0) * (1.25 if archetype == "guardian" else 1.0)
	return {"damage": damage, "max_health": max_health, "speed": minf(5.6, 4.1 + attack * 0.13 + loot * 0.04),
		"element_power":elemental * 4.0, "stun_duration":minf(1.5, control * 0.25), "cleave_targets":mini(4, floori(control / 1.7)),
		"ammo_amount":0 if resupply == 0 else maxi(2, roundi(resupply * 2)), "ammo_interval":maxf(14, 38 - resupply * 4), "bond_heal":minf(4.0, bond * 0.8),
		"interval": maxf(0.52, 1.6 / (1.0 + attack * 0.2)), "resistance": minf(0.45, survival * 0.035),
		"loot_radius": minf(12.0, (3.2 if archetype == "collector" else 1.4) + loot * 1.1),
		"heal": (3.0 if archetype == "support" else 0.0) + support * 1.2,
		"shield_max": 25.0 + survival * 5.0 + support * 3.0 if archetype == "guardian" else 0.0,
		"recover_time": maxf(2.5, 5.0 / (1.0 + survival * 0.12)),
		"revive_delay": maxf(70.0, 100.0 - support * 3.0)}

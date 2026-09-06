class_name MeyuiLootData
extends RefCounted

## Save files contain IDs and rolled scalars, never Nodes, Resources or Colors.
const Data = preload("res://data/game_data.gd")
const RARITY_ORDER: Array[String] = ["common", "uncommon", "rare", "epic", "legendary", "mythic"]
const SLOTS: Array[String] = ["sight", "barrel", "underbarrel", "magazine", "internal"]
const RARITIES: Dictionary = {
	"common":{"name":"Comum", "color":"aebac2", "icon":"•", "rank":0, "power":1.0, "modifiers":0, "parts":0, "weight":54.0},
	"uncommon":{"name":"Incomum", "color":"77cba2", "icon":"◆", "rank":1, "power":1.06, "modifiers":1, "parts":0, "weight":27.0},
	"rare":{"name":"Rara", "color":"7fb8f5", "icon":"◆◆", "rank":2, "power":1.14, "modifiers":1, "parts":1, "weight":13.0},
	"epic":{"name":"Épica", "color":"c58bea", "icon":"✦", "rank":3, "power":1.24, "modifiers":2, "parts":2, "weight":4.9},
	"legendary":{"name":"Lendária", "color":"efb55a", "icon":"★", "rank":4, "power":1.38, "modifiers":3, "parts":3, "weight":1.0},
	"mythic":{"name":"Mítica", "color":"f27f9d", "icon":"✺", "rank":5, "power":1.54, "modifiers":4, "parts":4, "weight":0.1}
}
const MANUFACTURERS: Dictionary = {
	"rajada":{"name":"Rajada", "icon":"»", "color":"8bbcaf", "fire_rate":1.22, "damage":0.9, "recoil":1.12, "description":"Cadência veloz · impacto menor"},
	"ferrovelho":{"name":"Ferro Velho", "icon":"⬡", "color":"c58f74", "damage":1.2, "recoil":1.3, "reload_time":1.1, "description":"Impacto bruto · recuo pesado"},
	"vigia":{"name":"Vigia", "icon":"⊕", "color":"b4c5d6", "spread":0.65, "critical_chance":0.07, "fire_rate":0.9, "description":"Precisão e crítico · ritmo lento"},
	"estopim":{"name":"Estopim", "icon":"✹", "color":"e4a371", "damage":1.08, "magazine_size":0.85, "description":"Demolição · pentes curtos"},
	"aurora":{"name":"Aurora", "icon":"ϟ", "color":"93b4e3", "damage":0.96, "reload_time":0.9, "description":"Elementos · recarga fluida"},
	"desvio":{"name":"Desvio", "icon":"⌁", "color":"b4a1ce", "fire_rate":1.08, "spread":1.2, "description":"Experimentos · efeitos incomuns"},
	"lastro":{"name":"Lastro", "icon":"▥", "color":"b0be88", "magazine_size":1.35, "max_reserve":1.25, "reload_time":1.16, "description":"Pentes enormes · recarga demorada"}
}
const MODIFIERS: Dictionary = {
	"ricochet":{"name":"Rebote", "icon":"↪", "description":"Acertos saltam para um alvo próximo.", "cost":200},
	"critical_blast":{"name":"Ponto de ruptura", "icon":"⊕", "description":"Críticos causam explosão curta.", "cost":240},
	"death_blast":{"name":"Despedida", "icon":"✹", "description":"Abates explodem ao redor do alvo.", "cost":220},
	"split_shot":{"name":"Bifurcação", "icon":"⋔", "description":"Acertos dividem dano entre dois vizinhos.", "cost":230},
	"third_strike":{"name":"Trinca", "icon":"Ⅲ", "description":"Cada terceiro disparo causa dano duplo.", "cost":170},
	"pierce":{"name":"Passagem", "icon":"→", "description":"Atravessa inimigos, respeitando paredes.", "cost":180},
	"burn":{"name":"Brasa", "icon":"♨", "description":"Acertos queimam ao longo do tempo.", "cost":160},
	"shock":{"name":"Arco voltaico", "icon":"ϟ", "description":"Eletricidade salta para outros alvos.", "cost":210},
	"cryo":{"name":"Frente fria", "icon":"❄", "description":"Acertos desaceleram inimigos.", "cost":160},
	"freeze":{"name":"Zero absoluto", "icon":"✧", "description":"Acertos repetidos podem congelar.", "cost":210},
	"reload_blast":{"name":"Respiro explosivo", "icon":"⟳", "description":"Completar recarga explode ao seu redor.", "cost":260},
	"kill_frenzy":{"name":"Embalada", "icon":"»", "description":"Abates aumentam cadência por alguns segundos.", "cost":190},
	"critical_refund":{"name":"Bala de volta", "icon":"↶", "description":"Críticos podem devolver uma bala ao pente.", "cost":210},
	"vampiric":{"name":"Sangue novo", "icon":"♥", "description":"Abates recuperam um pouco de vida.", "cost":250},
	"last_word":{"name":"Última palavra", "icon":"!", "description":"A última bala do pente causa dano quádruplo.", "cost":280},
	"heat":{"name":"Aquecimento", "icon":"♨", "description":"Disparos consecutivos aumentam dano.", "cost":220},
	"desperate":{"name":"Contra a parede", "icon":"♥!", "description":"Dano aumenta quando sua vida está baixa.", "cost":200},
	"seeker":{"name":"Eco", "icon":"◎", "description":"Um acerto envia dano secundário ao alvo próximo.", "cost":230},
	"headshot_haste":{"name":"Passo certeiro", "icon":"↟", "description":"Headshots aumentam movimento temporariamente.", "cost":190},
	"double_shot":{"name":"Dose dupla", "icon":"Ⅱ", "description":"Chance de disparar uma bala extra sem custo.", "cost":200}
}
const ATTACHMENTS: Dictionary = {
	"red_dot":{"name":"Ponto limpo", "slot":"sight", "icon":"⊕", "spread":0.84, "handling":4.0, "cost":110},
	"holographic":{"name":"Janela", "slot":"sight", "icon":"▣", "spread":0.75, "critical_chance":0.025, "cost":150},
	"scope":{"name":"Olho longo", "slot":"sight", "icon":"◎", "spread":0.62, "range":1.25, "handling":-7.0, "cost":190},
	"hybrid":{"name":"Duplo foco", "slot":"sight", "icon":"◉", "spread":0.78, "critical_multiplier":0.15, "cost":220},
	"suppressor":{"name":"Sussurro", "slot":"barrel", "icon":"▬", "recoil":0.86, "range":0.9, "cost":125},
	"compensator":{"name":"Contrapeso", "slot":"barrel", "icon":"↔", "recoil":0.7, "handling":-3.0, "cost":150},
	"long_barrel":{"name":"Cano longo", "slot":"barrel", "icon":"→", "range":1.3, "spread":0.8, "handling":-9.0, "cost":175},
	"ember_barrel":{"name":"Forno", "slot":"barrel", "icon":"♨", "modifier":"burn", "element":"fire", "reload_time":1.08, "cost":280},
	"grip":{"name":"Pulso firme", "slot":"underbarrel", "icon":"⊥", "recoil":0.82, "handling":6.0, "cost":130},
	"laser":{"name":"Linha vermelha", "slot":"underbarrel", "icon":"·", "spread":0.7, "critical_chance":0.03, "cost":180},
	"stabilizer":{"name":"Estável", "slot":"underbarrel", "icon":"═", "recoil":0.66, "handling":-8.0, "cost":190},
	"extended_mag":{"name":"Reserva extra", "slot":"magazine", "icon":"▥", "magazine_size":1.4, "max_reserve":1.15, "reload_time":1.15, "cost":180},
	"quick_mag":{"name":"Troca rápida", "slot":"magazine", "icon":"⟳", "reload_time":0.76, "magazine_size":0.9, "cost":175},
	"frost_mag":{"name":"Geada", "slot":"magazine", "icon":"❄", "modifier":"cryo", "element":"cryo", "cost":260},
	"arc_mag":{"name":"Capacitor", "slot":"magazine", "icon":"ϟ", "modifier":"shock", "element":"shock", "magazine_size":0.85, "cost":320},
	"accelerator":{"name":"Gatilho leve", "slot":"internal", "icon":"»", "fire_rate":1.18, "recoil":1.1, "cost":190},
	"heavy_receiver":{"name":"Núcleo denso", "slot":"internal", "icon":"⬡", "damage":1.2, "fire_rate":0.9, "cost":240},
	"critical_receiver":{"name":"Ponto vital", "slot":"internal", "icon":"⊕", "critical_chance":0.07, "critical_multiplier":0.25, "cost":240},
	"echo_receiver":{"name":"Repetidor", "slot":"internal", "icon":"Ⅱ", "modifier":"double_shot", "cost":330},
	"perforator":{"name":"Agulha", "slot":"internal", "icon":"→", "modifier":"pierce", "damage":0.95, "cost":280}
}
const ELEMENTS: Array[String] = ["none", "fire", "shock", "cryo", "corrosive", "explosive"]
const LEGENDARY_NAMES: Dictionary = {"last_word":"Último Recado", "shock":"Trovão Manso", "death_blast":"Hora da Saída", "kill_frenzy":"Sem Freio", "reload_blast":"Portas Abertas", "critical_blast":"Ponto Final"}

static func rarity_rank(rarity: String) -> int:
	return int(RARITIES.get(rarity, RARITIES.common).rank)

static func rarity_color(rarity: String) -> Color:
	return Color(String(RARITIES.get(rarity, RARITIES.common).color))

static func roll_rarity(rng: RandomNumberGenerator, quality: float = 1.0) -> String:
	var quality_bonus: float = clampf(quality, 0.25, 12.0)
	var weights: Array[float] = []
	var total: float = 0.0
	for rarity: String in RARITY_ORDER:
		var weight: float = float(RARITIES[rarity].weight) * pow(quality_bonus, float(rarity_rank(rarity)) * 0.65)
		weights.append(weight)
		total += weight
	var pick: float = rng.randf() * total
	for index: int in range(weights.size()):
		pick -= weights[index]
		if pick <= 0.0:
			return RARITY_ORDER[index]
	return "common"

static func roll_weapon(round_number: int, rng: RandomNumberGenerator, quality: float = 1.0, guaranteed_rarity: String = "") -> Dictionary:
	var available: Array[String] = []
	for id: String in Data.WEAPONS:
		if int(Data.WEAPONS[id].unlock_round) <= maxi(1, round_number):
			available.append(id)
	var rarity: String = guaranteed_rarity if RARITIES.has(guaranteed_rarity) else roll_rarity(rng, quality)
	var model_id: String = available[rng.randi_range(0, available.size() - 1)]
	return make_weapon(model_id, maxi(1, round_number + rng.randi_range(-1, 1)), rarity, int(rng.randi()))

static func make_weapon(model_id: String, level: int = 1, rarity: String = "common", seed_value: int = 1) -> Dictionary:
	if not Data.WEAPONS.has(model_id):
		return {}
	if not RARITIES.has(rarity):
		rarity = "common"
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var manufacturer_ids: Array = MANUFACTURERS.keys()
	var manufacturer: String = String(manufacturer_ids[rng.randi_range(0, manufacturer_ids.size() - 1)])
	var rolls: Dictionary = {}
	for stat: String in ["damage", "fire_rate", "magazine_size", "reload_time", "spread", "recoil", "range"]:
		rolls[stat] = snappedf(rng.randf_range(0.88, 1.12), 0.001)
	rolls["critical_chance"] = snappedf(rng.randf_range(0.0, 0.055), 0.001)
	var modifiers: Array[String] = []
	var choices: Array = MODIFIERS.keys()
	var number: int = int(RARITIES[rarity].modifiers)
	if rarity_rank(rarity) >= 4:
		var special_keys: Array = LEGENDARY_NAMES.keys()
		modifiers.append(String(special_keys[rng.randi_range(0, special_keys.size() - 1)]))
	while modifiers.size() < number:
		var modifier: String = String(choices[rng.randi_range(0, choices.size() - 1)])
		if not modifiers.has(modifier):
			modifiers.append(modifier)
	var element: String = String(Data.WEAPONS[model_id].get("element", "none"))
	if manufacturer == "aurora" or (rarity_rank(rarity) >= 2 and rng.randf() < 0.35):
		element = ELEMENTS[rng.randi_range(1, ELEMENTS.size() - 1)]
	if manufacturer == "estopim" and rarity_rank(rarity) >= 2 and not modifiers.has("death_blast"):
		modifiers.append("death_blast")
	var weapon: Dictionary = {
		"uid":"w-%x-%x-%s" % [seed_value, maxi(1, level), model_id],
		"model_id":model_id, "level":maxi(1, level), "rarity":rarity, "manufacturer":manufacturer,
		"seed":seed_value, "rolls":rolls, "modifiers":modifiers, "element":element,
		"attachments":{}, "magazine":int(Data.WEAPONS[model_id].magazine_size),
		"reserve":int(Data.WEAPONS[model_id].reserve_ammo), "upgrade_level":0, "favorite":false, "junk":false
	}
	for index: int in range(int(RARITIES[rarity].parts)):
		var attachment: Dictionary = roll_attachment(rng, 1.0 + rarity_rank(rarity) * 0.3, SLOTS[index])
		weapon.attachments[SLOTS[index]] = attachment
	return weapon

static func starter_weapon() -> Dictionary:
	var item: Dictionary = make_weapon("biscuit", 1, "common", 719)
	item["uid"] = "starter-biscuit"
	item["manufacturer"] = "independent"
	item["rolls"] = {}
	item["modifiers"] = []
	item["element"] = "none"
	return item

static func roll_attachment(rng: RandomNumberGenerator, quality: float = 1.0, slot: String = "") -> Dictionary:
	var choices: Array[String] = []
	for id: String in ATTACHMENTS:
		if slot.is_empty() or String(ATTACHMENTS[id].slot) == slot:
			choices.append(id)
	if choices.is_empty():
		return {}
	var id: String = choices[rng.randi_range(0, choices.size() - 1)]
	return {"uid":"a-%x-%s" % [rng.randi(), id], "id":id, "slot":String(ATTACHMENTS[id].slot), "rarity":roll_rarity(rng, quality), "roll":snappedf(rng.randf_range(0.9, 1.1), 0.001)}

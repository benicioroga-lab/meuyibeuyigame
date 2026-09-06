extends RefCounted

## These are exploration purchases, deliberately absent from the talent menu.
const PERKS := {
	"shelter":{"name":"Abrigo do farol","region":"patio","stat":"resistance","gain":0.025,"cap":0.10,"cost":180,"icon":"shield","color":"8ac2c7","position":Vector3(5,0.2,12),"label":"RESISTÊNCIA"},
	"smuggler":{"name":"Bolso do contrabandista","region":"mercado","stat":"ammo_capacity","gain":0.10,"cap":0.75,"cost":200,"icon":"ammo","color":"c7ae7e","position":Vector3(-24,0.2,0),"label":"RESERVA"},
	"precision":{"name":"Mola de precisão","region":"oficina","stat":"reload","gain":0.08,"cap":0.6,"cost":260,"icon":"reload","color":"dbb287","position":Vector3(18,4.2,-10),"label":"RECARGA"},
	"filter":{"name":"Pulmão de cobre","region":"galeria","stat":"regen","gain":0.45,"cap":3.5,"cost":300,"icon":"heal","color":"7eba97","position":Vector3(-16,-3.8,-35),"label":"CURA / S"},
	"vantage":{"name":"Olho do horizonte","region":"lajes","stat":"crit_multiplier","gain":0.12,"cap":1.0,"cost":380,"icon":"target","color":"99bde6","position":Vector3(3,8.2,-29),"label":"CRÍTICO"},
	"champion":{"name":"Marca do campeão","region":"quadra","stat":"damage","gain":0.10,"cap":0.8,"cost":450,"icon":"damage","color":"dc8a7a","position":Vector3(20,0.2,-46),"label":"DANO"},
	"pack":{"name":"Pacto da nascente","region":"parque","stat":"dog_damage","gain":0.18,"cap":1.5,"cost":240,"icon":"paw","color":"8abd88","position":Vector3(16,0.2,57),"label":"DANO DE FARO"},
	"collector":{"name":"Achado de vitrine","region":"shopping","stat":"loot_luck","gain":0.12,"cap":0.85,"cost":330,"icon":"star","color":"b69adb","position":Vector3(57,0.2,54),"label":"FORTUNA"},
	"final_cut":{"name":"Último enquadramento","region":"cinema","stat":"crit_chance","gain":0.03,"cap":0.15,"cost":400,"icon":"critical","color":"cb83ad","position":Vector3(44,0.2,9),"label":"CHANCE CRÍTICA"},
	"pressure":{"name":"Coração de pressão","region":"cisterna","stat":"max_health","gain":0.15,"cap":1.2,"cost":480,"icon":"heart","color":"6dcccf","position":Vector3(-39,-1.8,46),"label":"VIDA MÁXIMA"},
	"express":{"name":"Expresso da madrugada","region":"terminal","stat":"move_speed","gain":0.025,"cap":0.15,"cost":520,"icon":"speed","color":"e1bb72","position":Vector3(62,0.2,93),"label":"MOVIMENTO"}
}

static func bonus(id: String, level: int) -> float:
	if not PERKS.has(id): return 0.0
	var p: Dictionary = PERKS[id]
	return float(p.cap) * (1.0 - exp(-float(level) * float(p.gain) / float(p.cap)))

static func cost(id: String, level: int) -> int:
	return roundi(float(PERKS[id].cost) * (1 + level * 0.65 + pow(float(level),1.25) * 0.3)) if PERKS.has(id) else 0

static func preview(id: String, level: int) -> String:
	var p: Dictionary = PERKS[id]
	var factor := 1.0 if p.stat == "regen" else 100.0
	return "%s  +%.1f%s → +%.1f%s" % [p.label, bonus(id,level)*factor, "/s" if p.stat == "regen" else "%", bonus(id,level+1)*factor, "/s" if p.stat == "regen" else "%"]

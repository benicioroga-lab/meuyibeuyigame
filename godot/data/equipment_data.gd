extends RefCounted

## Run equipment: one grenade chassis, one build module and limited supplies.
const GRENADES := {
	"pulse":{"name":"Pulso de impacto", "icon":"blast", "color":"eeb966", "cost":0, "damage":95.0, "radius":4.2, "element":"explosive", "description":"Explosão concentrada · quebra grupos", "rarity":"uncommon"},
	"cryo":{"name":"Névoa polar", "icon":"cryo", "color":"80dfef", "cost":420, "damage":48.0, "radius":5.5, "element":"cryo", "description":"Congela aproximações · controle de área", "rarity":"rare"},
	"arc":{"name":"Arco voltaico", "icon":"shock", "color":"bb94ff", "cost":700, "damage":130.0, "radius":3.4, "element":"shock", "description":"Descarga forte · atordoa o grupo", "rarity":"epic"}
}
const MODULES := {
	"balanced":{"name":"Núcleo livre", "icon":"target", "color":"a4b9bf", "cost":0, "description":"Sem especialização · sem penalidade", "bonuses":{}},
	"assault":{"name":"Cadência", "icon":"bolt", "color":"efb764", "cost":450, "description":"Cadência +18% · recarga +10% de tempo", "bonuses":{"fire_rate":1.18,"reload_time":1.10}},
	"precision":{"name":"Ponto focal", "icon":"target", "color":"7edfc8", "cost":450, "description":"Crítico +12% · movimento −8%", "bonuses":{"critical_chance":0.12,"move_speed":0.92}},
	"guardian":{"name":"Vínculo", "icon":"paw", "color":"bca1f5", "cost":450, "description":"Dano do Faro +30% · vida +10%", "bonuses":{"dog_damage":1.30,"max_health":1.10}}
}
const SUPPLIES := {
	"medkit":{"name":"Kit de campo", "icon":"heart", "key":"H", "cost":110, "max":5, "description":"Recupera 45% da vida", "color":"92d4b3"},
	"ammo":{"name":"Reserva portátil", "icon":"ammo", "key":"J", "cost":95, "max":5, "description":"+2 pentes na reserva da arma atual", "color":"eeb966"},
	"grenade":{"name":"Carga de granada", "icon":"blast", "key":"G", "cost":80, "max":6, "description":"Uma carga para a granada equipada", "color":"a2bbef"}
}

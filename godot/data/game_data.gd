class_name MeyuiData
extends RefCounted

# Values ported from the browser game's configuration. Rates are shots/second.
const WEAPONS: Dictionary = {
	"tidecaller":{"id":"tidecaller","name":"Maré de Íons","family":"experimental","legendary_only":true,"signature":"shock","damage":35.0,"fire_rate":4.6,"magazine_size":21,"reserve_ammo":126,"max_reserve":168,"reload_time":2.05,"price":0,"unlock_round":7,"recoil":0.012,"spread":0.004,"range":80.0,"element":"shock","color":Color("72d9e6")},
	"night_express":{"id":"night_express","name":"Expresso 02:17","family":"smg","legendary_only":true,"signature":"kill_frenzy","damage":17.0,"fire_rate":10.5,"magazine_size":36,"reserve_ammo":216,"max_reserve":288,"reload_time":1.85,"price":0,"unlock_round":9,"recoil":0.01,"spread":0.014,"range":58.0,"element":"fire","color":Color("edb967")},
	"final_frame":{"id":"final_frame","name":"Último Fotograma","family":"sniper","legendary_only":true,"signature":"critical_blast","damage":104.0,"fire_rate":1.05,"magazine_size":6,"reserve_ammo":42,"max_reserve":54,"reload_time":2.45,"price":0,"unlock_round":8,"recoil":0.031,"spread":0.0004,"range":180.0,"critical_multiplier":2.4,"penetration":1,"element":"cryo","color":Color("b7a2ef")},
	"biscuit": {"id":"biscuit", "name":"Biscoiteira 12", "damage":22.0, "fire_rate":3.2, "magazine_size":12, "reserve_ammo":84, "max_reserve":96, "reload_time":1.25, "price":0, "unlock_round":1, "recoil":0.009, "spread":0.002, "range":75.0, "color":Color("eab96f")},
	"boardwalk": {"id":"boardwalk", "name":"Calçadão", "damage":26.0, "fire_rate":5.2, "magazine_size":18, "reserve_ammo":126, "max_reserve":144, "reload_time":1.5, "price":420, "unlock_round":2, "recoil":0.007, "spread":0.005, "range":90.0, "color":Color("8fcab7")},
	"hammer": {"id":"hammer", "name":"Marreta", "family":"revolver", "damage":70.0, "fire_rate":1.3, "magazine_size":6, "reserve_ammo":42, "max_reserve":54, "reload_time":2.1, "price":950, "unlock_round":4, "recoil":0.025, "spread":0.003, "range":105.0, "color":Color("e49478")},
	"sparrow": {"id":"sparrow", "name":"Andorinha", "family":"smg", "damage":13.0, "fire_rate":11.0, "magazine_size":32, "reserve_ammo":192, "max_reserve":256, "reload_time":1.7, "price":680, "unlock_round":3, "recoil":0.006, "spread":0.018, "range":48.0, "color":Color("76c5b7")},
	"lookout": {"id":"lookout", "name":"Atalaia", "family":"sniper", "damage":112.0, "fire_rate":0.85, "magazine_size":5, "reserve_ammo":35, "max_reserve":45, "reload_time":2.3, "price":1350, "unlock_round":6, "recoil":0.032, "spread":0.0005, "range":180.0, "critical_multiplier":2.3, "penetration":1, "color":Color("a4b8ce")},
	"doorman": {"id":"doorman", "name":"Porteira", "family":"shotgun", "damage":17.0, "fire_rate":1.15, "pellets":7, "magazine_size":6, "reserve_ammo":42, "max_reserve":60, "reload_time":2.4, "price":740, "unlock_round":3, "recoil":0.03, "spread":0.065, "range":30.0, "color":Color("d39863")},
	"anchor": {"id":"anchor", "name":"Âncora", "family":"lmg", "damage":21.0, "fire_rate":8.0, "magazine_size":70, "reserve_ammo":210, "max_reserve":350, "reload_time":3.7, "price":1750, "unlock_round":7, "recoil":0.012, "spread":0.027, "range":80.0, "handling":38.0, "color":Color("a0b783")},
	"scrap": {"id":"scrap", "name":"Remendo", "family":"improvised", "damage":38.0, "fire_rate":2.9, "magazine_size":9, "reserve_ammo":63, "max_reserve":81, "reload_time":2.2, "price":430, "unlock_round":2, "recoil":0.02, "spread":0.032, "range":55.0, "color":Color("c18765")},
	"arc": {"id":"arc", "name":"Bobina", "family":"experimental", "damage":32.0, "fire_rate":4.0, "magazine_size":18, "reserve_ammo":108, "max_reserve":144, "reload_time":2.0, "price":2300, "unlock_round":9, "recoil":0.01, "spread":0.008, "range":70.0, "element":"shock", "color":Color("89bade")},
	"comet": {"id":"comet", "name":"Cometa", "family":"special", "damage":95.0, "fire_rate":0.95, "magazine_size":4, "reserve_ammo":24, "max_reserve":36, "reload_time":2.8, "price":3100, "unlock_round":12, "recoil":0.036, "spread":0.006, "range":95.0, "element":"explosive", "color":Color("e2ac74")}
}
const DIFFICULTIES: Dictionary = {
	"easy":{"name":"Fácil", "health":0.78, "damage":0.7, "speed":0.88, "count":0.8, "reward":0.85},
	"normal":{"name":"Normal", "health":1.0, "damage":1.0, "speed":1.0, "count":1.0, "reward":1.0},
	"hard":{"name":"Difícil", "health":1.25, "damage":1.25, "speed":1.12, "count":1.15, "reward":1.35},
	"insane":{"name":"Insano", "health":1.5, "damage":1.45, "speed":1.2, "count":1.3, "reward":1.65},
	"nightmare":{"name":"Pesadelo", "health":1.75, "damage":1.7, "speed":1.3, "count":1.45, "reward":2.0}
}

static func wave_count(round_number: int, difficulty_id: String) -> int:
	var config: Dictionary = DIFFICULTIES.get(difficulty_id, DIFFICULTIES.normal)
	return clampi(roundi((5.0 + round_number * 1.7) * float(config.count)), 5, 80)

static func upgrade_cost(level: int) -> int:
	return roundi(160.0 + level * 75.0 + pow(level, 1.4) * 45.0)

static func upgrade_multiplier(level: int) -> float:
	return 1.0 + log(1.0 + float(level)) / log(2.0) * 0.12

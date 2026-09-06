extends Control

const Icons = preload("res://scripts/ui_icons.gd")
const Equipment = preload("res://data/equipment_data.gd")
const Screen = preload("res://scripts/progression_screen.gd")
var game: Node
var selected: int = -1
var cards: Array[Control] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	for slot: int in range(4):
		var thumb := Screen.WeaponThumbnail.new()
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(thumb)
		cards.append(thumb)
	visible = false

func open(owner_game: Node) -> void:
	game = owner_game
	selected = -1
	visible = true
	for index: int in range(4):
		var item: Dictionary = game.inventory.find_item(game.inventory.weapon_slots[index])
		if not item.is_empty(): cards[index].request_portrait(item, game.inventory.stats(item))
	get_viewport().warp_mouse(size * 0.5)
	queue_redraw()

func _process(_delta: float) -> void:
	if not visible or not is_instance_valid(game): return
	var offset := get_local_mouse_position() - size * 0.5
	selected = -1
	if offset.length() > 60:
		selected = posmod(roundi((offset.angle() + PI * 0.5) / (PI * 0.5)), 4)
	queue_redraw()

func _text(at: Vector2, text: String, font_size: int, color: Color, width: float = 240) -> void:
	draw_string(ThemeDB.fallback_font, at - Vector2(width * 0.5, 0), text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, color)

func _draw() -> void:
	if not is_instance_valid(game): return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.015, 0.025, 0.04, 0.84))
	var center := size * 0.5
	var radius := minf(size.y * 0.25, 205)
	draw_arc(center, radius, 0, TAU, 96, Color("374a55"), 1.5, true)
	_text(center + Vector2(0, -25), "ARSENAL", 21, Color("e7e2d4"))
	_text(center + Vector2(0, 4), "T  •  SEGURE", 12, Color("d9b477"))
	_text(center + Vector2(0, 29), "Solte para equipar", 12, Color("9dadaf"))
	for slot: int in range(4):
		var at := center + Vector2.UP.rotated(slot * PI * 0.5) * radius
		var item: Dictionary = game.inventory.find_item(game.inventory.weapon_slots[slot])
		var stats: Dictionary = game.inventory.stats(item) if not item.is_empty() else {}
		var color := preload("res://data/loot_data.gd").rarity_color(String(item.get("rarity", "common"))) if not item.is_empty() else Color("596a73")
		var rect := Rect2(at - Vector2(110, 64), Vector2(220, 128))
		draw_style_box(Icons.style(Color("263c48") if selected == slot else Color("101c27"), color if selected == slot else Color(color, 0.35), 12), rect)
		cards[slot].position = at - Vector2(87, 27)
		cards[slot].size = Vector2(174, 44)
		cards[slot].visible = not item.is_empty()
		cards[slot].set("family", String(stats.get("family", "pistol")))
		cards[slot].set("tint", color)
		cards[slot].queue_redraw()
		_text(at + Vector2(0, -42), "%d  %s" % [slot + 1, "● ATIVA" if slot == game.inventory.active_weapon_slot else ""], 12, color)
		_text(at + Vector2(0, 37), String(stats.get("name", "Slot livre")).left(25), 14, Color("e7e2d4"), 212)
		_text(at + Vector2(0, 55), "%s  ·  %s / %s" % [stats.get("rarity_name", ""), item.get("magazine", "—"), item.get("reserve", "—")] if not item.is_empty() else "I  •  monte o equipamento", 11, color, 215)
	_text(Vector2(center.x, size.y - 58), "G  %s ×%d     •     H  CURA ×%d     •     J  MUNIÇÃO ×%d" % [Equipment.GRENADES[game.inventory.grenade_id].name, game.inventory.supplies.grenade, game.inventory.supplies.medkit, game.inventory.supplies.ammo], 14, Color("d9b477"), 900)
	_text(Vector2(center.x, size.y - 33), "MÓDULO  ·  " + Equipment.MODULES[game.inventory.module_id].name + "     /     ESC  cancelar", 12, Color("9dadaf"), 800)

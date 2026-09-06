extends Control

signal slot_selected(index: int)
const Icons = preload("res://scripts/ui_icons.gd")
const Loot = preload("res://data/loot_data.gd")
var items: Array[Dictionary] = []
var statistics: Array[Dictionary] = []
var selected := 0
var active := 0
var thumbnails: Array[Control] = []
var _polygons: Array[PackedVector2Array] = []

func _ready() -> void:
	custom_minimum_size = Vector2(330, 354)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	resized.connect(queue_redraw)

func _draw() -> void:
	var center := size * 0.5
	var scale_factor := minf(size.x / 340.0, size.y / 354.0)
	_polygons.clear()
	for slot: int in range(4):
		var polygon := PackedVector2Array()
		for p: Vector2 in [Vector2(-91,-169),Vector2(91,-169),Vector2(113,-143),Vector2(32,-33),Vector2(-32,-33),Vector2(-113,-143)]:
			polygon.append(center + p.rotated(slot * PI * 0.5) * scale_factor)
		_polygons.append(polygon)
		var item: Dictionary = items[slot] if slot < items.size() else {}
		var stats: Dictionary = statistics[slot] if slot < statistics.size() else {}
		var color := Loot.rarity_color(item.get("rarity", "common")) if not item.is_empty() else Color("456171")
		draw_colored_polygon(polygon, Color(color.darkened(0.74), 0.96))
		var outline := polygon.duplicate()
		outline.append(polygon[0])
		draw_polyline(outline, color.lightened(0.25) if selected == slot else Color(color, 0.48), 2 if selected == slot else 1, true)
		var at := center + Vector2.UP.rotated(slot * PI * 0.5) * 112 * scale_factor
		var width := 105.0 * scale_factor
		if slot < thumbnails.size():
			thumbnails[slot].position = at - Vector2(width * 0.5, 18)
			thumbnails[slot].size = Vector2(width, 38)
		var text_color := Color("dce7ea")
		draw_string(ThemeDB.fallback_font, at + Vector2(-width*0.5,-22), "%d%s" % [slot+1, " · ATIVA" if slot == active else ""], HORIZONTAL_ALIGNMENT_CENTER, width, 12, color)
		draw_string(ThemeDB.fallback_font, at + Vector2(-width*0.5,35), String(stats.get("name", "Vazio")).left(18), HORIZONTAL_ALIGNMENT_CENTER, width, 10, text_color)
		draw_string(ThemeDB.fallback_font, at + Vector2(-width*0.5,50), String(stats.get("rarity_name", "Livre")), HORIZONTAL_ALIGNMENT_CENTER, width, 10, color)
	draw_string(ThemeDB.fallback_font, center - Vector2(15,-5), "%02d" % (selected+1), HORIZONTAL_ALIGNMENT_CENTER,30,20,Color("e7bd75"))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for slot: int in range(_polygons.size()):
			if Geometry2D.is_point_in_polygon(event.position, _polygons[slot]):
				slot_selected.emit(slot)
				accept_event()
				return

extends CanvasLayer
class_name MeyuiUI

const ICON = preload("res://scripts/ui_icons.gd")
const LOOT = preload("res://data/loot_data.gd")
const INK := ICON.INK
const GOLD := ICON.GOLD
const CORAL := ICON.CORAL
const PAPER := ICON.PAPER
const MUTED := ICON.MUTED
const HUD_WHITE := Color("f4f7fb")
const HUD_MUTED := Color("b6c5d0")
const DIFFICULTIES := ["easy", "normal", "hard", "insane", "nightmare"]
const DIFFICULTY_NAMES := ["Fácil", "Normal", "Difícil", "Insano", "Pesadelo"]
const CATEGORY_NAMES := {"graphics": "IMAGEM", "gameplay": "CONTROLES", "audio": "ÁUDIO", "accessibility": "ACESSIBILIDADE"}
var game: Node
var root: Control
var hud: Control
var menu: Control
var pause_menu: Control
var shop: Control
var game_over: Control
var detail: Control
var detail_body: VBoxContainer
var detail_title: Label
var detail_kicker: Label
var labels: Dictionary = {}
var health_bar: ProgressBar
var dog_bar: ProgressBar
var reload_bar: ProgressBar
var boss_bar: ProgressBar
var boss_display: Control
var loot_display: Control
var loot_rows: Array[Dictionary] = []
var loot_thumbnail: LootThumbnail
var loot_stats_box: VBoxContainer
var loot_panel_style: StyleBoxFlat
var loot_signature: String = ""
var powerup_display: HBoxContainer
var powerup_labels: Dictionary = {}
var powerup_signature: String = ""
var reticle: AimMark
var damage_screen: DamageVeil
var announcement: VBoxContainer
var difficulty: OptionButton
var chaos: CheckBox
var ui_scale: float = 1.0
var setting_values: Dictionary = {}
var last_hud: Dictionary = {}
var notice_time: float = 0.0
var announcement_time: float = 0.0
var gain_time: float = 0.0
var saved_time: float = 0.0
var elapsed: float = 0.0
var last_health: float = -1.0
var last_coins: int = -1
var detail_return: String = "menu"
var settings_category: String = "graphics"
var selected_slot: int = -1
var new_difficulty: String = "normal"
var new_chaos: bool = false
var continue_button: Button
var menu_tween: Tween
var detail_mode: String = ""
var cancel_confirmation: Callable
var setting_controls: Dictionary = {}

class AimMark extends Control:
	var hit_time: float = 0.0
	var hit_color: Color = Color("d9b477")
	var crosshair_color: Color = Color("e7e2d4")
	var enabled: bool = true
	var hit_enabled: bool = true
	var critical: bool = false
	func _draw() -> void:
		var center := size * 0.5
		if enabled:
			for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
				draw_line(center + direction * 5.5, center + direction * 10.5, crosshair_color, 1.4, true)
			draw_circle(center, 1.1, crosshair_color)
		if hit_enabled and hit_time > 0.0:
			var color := hit_color
			color.a *= minf(1.0, hit_time * 12.0)
			for direction in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				draw_line(center + direction * 7, center + direction * (15 if critical else 12), color, 2.2, true)

class DamageVeil extends Control:
	const VIGNETTE_SHADER := """
shader_type canvas_item;
render_mode unshaded;
uniform vec4 edge_tint : source_color = vec4(0.84, 0.025, 0.018, 1.0);
uniform float edge_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec2 viewport_pixels = vec2(1280.0, 720.0);
void fragment() {
	vec2 distance_to_edge = min(UV, vec2(1.0) - UV) * viewport_pixels;
	float feather = min(viewport_pixels.y * 0.22, 190.0);
	vec2 falloff = vec2(1.0) - smoothstep(vec2(0.0), vec2(feather), distance_to_edge);
	float edge = 1.0 - (1.0 - falloff.x) * (1.0 - falloff.y);
	// A continuous, feathered border leaves every pixel in the center untouched.
	COLOR = vec4(edge_tint.rgb, edge * edge * edge_strength * 0.52);
}
"""
	var amount: float = 0.0
	var shield_amount: float = 0.0
	var danger: float = 0.0
	var pulse_clock: float = 0.0
	var reduced_flashes: bool = false
	var directions: Array[Dictionary] = []
	var vignette: ColorRect
	var vignette_material: ShaderMaterial
	func _ready() -> void:
		vignette = ColorRect.new()
		vignette.name = "ContinuousDamageVignette"
		vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vignette.show_behind_parent = true
		var shader := Shader.new()
		shader.code = VIGNETTE_SHADER
		vignette_material = ShaderMaterial.new()
		vignette_material.shader = shader
		vignette.material = vignette_material
		add_child(vignette)
		vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		resized.connect(_sync_vignette)
		_sync_vignette()
	func _sync_vignette() -> void:
		if not is_instance_valid(vignette): return
		var red_strength := maxf(amount * (.48 if reduced_flashes else 1.0), danger * pulse() * .52)
		var strength := clampf(maxf(red_strength, shield_amount * .5), 0.0, 1.0)
		vignette.visible = strength > .001
		vignette_material.set_shader_parameter("edge_strength", strength)
		vignette_material.set_shader_parameter("edge_tint", Color(.84, .025, .018) if red_strength >= shield_amount * .5 else Color(.20, .72, .76))
		vignette_material.set_shader_parameter("viewport_pixels", size.max(Vector2.ONE))
	func receive(strength: float, direction: Vector2, absorbed: bool) -> void:
		if absorbed: shield_amount = maxf(shield_amount, strength * .7)
		else: amount = maxf(amount, strength)
		_sync_vignette()
		if direction.is_finite() and direction.length_squared() > .001:
			var normal := direction.normalized()
			for hit in directions:
				if hit.direction.dot(normal) > .90 and hit.absorbed == absorbed:
					hit.remaining = .95
					hit.strength = maxf(strength, hit.strength)
					queue_redraw()
					return
			if directions.size() >= 4: directions.pop_front()
			directions.append({"direction": normal, "remaining": .95, "strength": strength, "absorbed": absorbed})
		queue_redraw()
	func tick(delta: float) -> void:
		pulse_clock += delta
		amount = move_toward(amount, 0.0, delta * 1.65)
		shield_amount = move_toward(shield_amount, 0.0, delta * 1.6)
		for index in range(directions.size() - 1, -1, -1):
			directions[index].remaining -= delta
			if directions[index].remaining <= 0: directions.remove_at(index)
		_sync_vignette()
		queue_redraw()
	func pulse() -> float:
		return .64 if reduced_flashes else .56 + .18 * sin(pulse_clock * TAU * .62)
	func clear() -> void:
		amount = 0
		shield_amount = 0
		danger = 0
		directions.clear()
		_sync_vignette()
		queue_redraw()
	func arc_center(index: int) -> Vector2:
		return size * .5 + directions[index].direction * minf(size.y * .145, 115.0)
	func _draw() -> void:
		_sync_vignette()
		var radius := minf(size.y * .145, 115.0)
		for hit in directions:
			var angle: float = hit.direction.angle()
			var fade := minf(1.0, float(hit.remaining) / .3)
			var color := Color("85d1d4") if hit.absorbed else Color("ff4439")
			color.a = fade * (.62 if reduced_flashes else .95)
			var width := 5.0 + float(hit.strength) * 3.0
			var glow := color
			glow.a *= .14
			draw_arc(size * .5, radius, angle - .32, angle + .32, 22, glow, width + 9.0, true)
			draw_arc(size * .5, radius, angle - .29, angle + .29, 22, color, width, true)
			var normal: Vector2 = hit.direction
			var tangent := Vector2(-normal.y, normal.x)
			var tip := size * .5 + normal * (radius - 11.0)
			draw_colored_polygon(PackedVector2Array([tip, tip + normal * 7 + tangent * 4, tip + normal * 7 - tangent * 4]), color)

class LootThumbnail extends Control:
	var kind: String = "weapon"
	var family: String = "pistol"
	var tint: Color = Color("d9b477")
	var rank: int = 0
	func _draw() -> void:
		var origin := Vector2(5, size.y * .48)
		var ink := tint.lightened(.15)
		if kind == "ammo":
			for index in range(3):
				var x := 11.0 + index * 18.0
				draw_rect(Rect2(x, 10, 11, 28), Color("b69e70"))
				draw_colored_polygon(PackedVector2Array([Vector2(x, 10), Vector2(x + 5.5, 3), Vector2(x + 11, 10)]), ink)
				draw_line(Vector2(x - 1, 37), Vector2(x + 12, 37), PAPER, 2)
		elif kind in ["attachment", "powerup"]:
			draw_texture_rect(ICON.texture("bolt" if kind == "powerup" else "chip", tint, 40), Rect2(17, 3, 40, 40), false)
		else:
			var long_gun := family not in ["pistol", "revolver", "improvised"]
			draw_rect(Rect2(origin + Vector2(15, -8), Vector2(39 if long_gun else 35, 12)), ink)
			draw_rect(Rect2(origin + Vector2(49, -5), Vector2(25 if long_gun else 13, 4)), tint)
			draw_colored_polygon(PackedVector2Array([origin + Vector2(23, 0), origin + Vector2(34, 0), origin + Vector2(29, 20), origin + Vector2(18, 20)]), tint.darkened(.12))
			if long_gun:
				draw_colored_polygon(PackedVector2Array([origin + Vector2(15, -4), origin + Vector2(0, -8), origin + Vector2(0, 8), origin + Vector2(15, 3)]), tint.darkened(.16))
			if family == "sniper": draw_rect(Rect2(origin + Vector2(25, -16), Vector2(22, 5)), PAPER)
			elif family == "shotgun": draw_rect(Rect2(origin + Vector2(45, 2), Vector2(19, 5)), tint.darkened(.2))
			elif family in ["smg", "rifle", "lmg"]: draw_rect(Rect2(origin + Vector2(39, 4), Vector2(9, 16)), tint.darkened(.1))
		for index in range(clampi(rank + 1, 1, 6)):
			var at := Vector2(9 + index * 10, size.y - 4)
			draw_colored_polygon(PackedVector2Array([at + Vector2(0,-2), at + Vector2(3,0), at + Vector2(0,2), at + Vector2(-3,0)]), tint)

class Atmosphere extends Control:
	var clock: float = 0.0
	func _draw() -> void:
		var gold := Color(0.67, 0.57, 0.38, 0.14)
		draw_polyline(PackedVector2Array([Vector2(size.x * .025, size.y * .82), Vector2(size.x * .025, size.y * .17), Vector2(size.x * .043, size.y * .13)]), gold, 1.0, true)
		draw_line(Vector2(size.x * .05, size.y * .905), Vector2(size.x * .31, size.y * .905), gold, 1.0, true)
		for index in range(17):
			var x := fmod(float(index) * 83.1 + clock * (3.0 + index % 3), size.x)
			var y := size.y * .2 + fmod(float(index) * 47.7 - clock * 7.0 + size.y * 4, size.y * .7)
			draw_circle(Vector2(x, y), .8 if index % 3 else 1.3, Color(0.74, 0.68, 0.5, .08 + .1 * sin(clock + index)))

func setup(target: Node) -> void:
	game = target
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10

func _ready() -> void:
	root = Control.new()
	root.name = "MeyuiInterface"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = ICON.theme()
	add_child(root)
	_build_hud()
	_build_menu()
	_build_pause()
	_build_detail()
	_build_game_over()
	_build_shop()
	var notice := _label(root, "notice", "", 15, GOLD)
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wrap(notice)
	_position(notice, Vector4(.22, .89, .78, .89), Vector4(0, 0, 0, 45))
	apply_settings(_settings())
	show_menu()

func _settings() -> Dictionary:
	if not is_instance_valid(game): return {}
	var manager: Variant = game.get("settings")
	if manager != null:
		var values: Variant = manager.get("data")
		if values is Dictionary: return values
	return {}

func _call(method: String, args: Array = []) -> Variant:
	if is_instance_valid(game) and game.has_method(method): return game.callv(method, args)
	return null

func _feedback(cue: String = "select") -> void:
	_call("ui_feedback", ["ui_click" if cue in ["select", "confirm", "back"] else cue])

func _label(parent: Node, key: String, text: String, font_size: int = 16, color: Color = PAPER) -> Label:
	var node := Label.new()
	node.text = text
	node.clip_text = not parent is HBoxContainer
	node.set_meta("base_font_size", font_size)
	node.add_theme_font_size_override("font_size", roundi(font_size * ui_scale))
	node.add_theme_color_override("font_color", color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	if not key.is_empty(): labels[key] = node
	return node

func _paragraph(parent: Node, text: String, color: Color = MUTED, font_size: int = 14) -> Label:
	var node := _label(parent, "", text, font_size, color)
	_wrap(node)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node

func _wrap(node: Label) -> Label:
	# Clipped labels report zero wrapped height in containers. Wrapping labels
	# must participate in minimum-height calculation so descriptions stay visible.
	node.clip_text = false
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.custom_minimum_size.y = node.get_theme_font_size("font_size") * 1.3
	return node

func _button(parent: Node, title: String, action: Callable, primary: bool = false, icon_id: String = "") -> Button:
	var node := Button.new()
	node.text = title
	node.alignment = HORIZONTAL_ALIGNMENT_LEFT
	node.custom_minimum_size.y = 42.0 * ui_scale
	node.set_meta("base_font_size", 16)
	node.add_theme_font_size_override("font_size", roundi(16 * ui_scale))
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal := ICON.style(Color(0.055, 0.073, 0.09, .3) if not primary else Color(.20, .18, .135, .9))
	normal.border_width_left = 2 if primary else 0
	normal.border_color = GOLD
	node.add_theme_stylebox_override("normal", normal)
	node.add_theme_color_override("font_color", GOLD if primary else PAPER)
	if not icon_id.is_empty():
		node.icon = ICON.texture(icon_id, GOLD if primary else MUTED, 21)
		node.add_theme_constant_override("h_separation", 14)
	node.pressed.connect(func() -> void:
		_feedback("confirm" if primary else "select")
		action.call())
	node.mouse_entered.connect(func() -> void: _feedback("hover"))
	parent.add_child(node)
	return node

func _box(parent: Node, separation: int = 8) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", separation)
	parent.add_child(box)
	return box

func _row(parent: Node, separation: int = 12) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", separation)
	parent.add_child(row)
	return row

func _icon(parent: Node, id: String, color: Color = GOLD, icon_size: int = 24) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = ICON.texture(id, color, icon_size)
	icon.custom_minimum_size = Vector2(icon_size, icon_size)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(icon)
	return icon

func _position(node: Control, anchors: Vector4, offsets: Vector4) -> void:
	node.anchor_left = anchors.x
	node.anchor_top = anchors.y
	node.anchor_right = anchors.z
	node.anchor_bottom = anchors.w
	node.offset_left = offsets.x
	node.offset_top = offsets.y
	node.offset_right = offsets.z
	node.offset_bottom = offsets.w

func _layer(parent: Node) -> Control:
	var node := Control.new()
	parent.add_child(node)
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

func _gradient(parent: Node, top: Color, bottom: Color, vertical: bool = false) -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0, top)
	gradient.set_color(1, bottom)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2.ZERO
	texture.fill_to = Vector2.DOWN if vertical else Vector2.RIGHT
	var node := TextureRect.new()
	node.texture = texture
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return node

func _menu_backdrop(parent: Node, darker: bool = false) -> void:
	_gradient(parent, Color(.022, .031, .043, .99), Color(.025, .035, .045, .72 if darker else .13))
	var art := Atmosphere.new()
	parent.add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.add_to_group("meyui_menu_art")

func _scroll(parent: Node, anchors: Vector4, offsets: Vector4) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	_position(scroll, anchors, offsets)
	var content := _box(scroll, 9)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	return content

func _build_menu() -> void:
	menu = _layer(root)
	menu.name = "CinematicMainMenu"
	_menu_backdrop(menu)
	var logo := _box(menu, 0)
	_position(logo, Vector4(.058, .068, .4, .068), Vector4(0, 0, 0, 180))
	_label(logo, "", "MORRO DO VENTO  /  DEPOIS DO ÚLTIMO SINAL", 10, GOLD)
	var title := _label(logo, "", "MEYUI\nBEUYI", 65)
	title.add_theme_constant_override("line_spacing", -15)
	_label(logo, "", "NINGUÉM DOMINA A NOITE SOZINHO.", 10, MUTED)
	var nav := _scroll(menu, Vector4(.052, .43, .34, .87), Vector4.ZERO)
	continue_button = _button(nav, "CONTINUAR", func() -> void: _call("continue_game"), true, "play")
	continue_button.name = "ContinueGame"
	_button(nav, "NOVA EXPEDIÇÃO", show_new_game, false, "arrow").name = "NewGame"
	_button(nav, "CARREGAR", func() -> void: _show_slots("load"), false, "save")
	_button(nav, "CONFIGURAÇÕES", func() -> void: show_settings(), false, "settings")
	_button(nav, "ARQUIVO DO MORRO", show_extras, false, "map")
	_button(nav, "SAIR", func() -> void: _call("quit_game"), false, "exit")
	var caption := _label(menu, "menu_save", "SEU CÃO. SUA BUILD. MAIS UMA ESQUINA.", 12, MUTED)
	_position(caption, Vector4(.46, .84, .94, .84), Vector4(0, 0, 0, 50))
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_wrap(caption)
	var footer := _label(menu, "", "WASD  MOVER     MOUSE  OLHAR     TAB  EQUIPAMENTO     ESC  PAUSAR", 10, MUTED)
	_position(footer, Vector4(.055, .935, .95, .935), Vector4(0, 0, 0, 30))

func _build_pause() -> void:
	pause_menu = _layer(root)
	pause_menu.name = "PauseNavigation"
	_menu_backdrop(pause_menu, true)
	var heading := _box(pause_menu, 4)
	_position(heading, Vector4(.058, .11, .4, .11), Vector4(0, 0, 0, 140))
	_label(heading, "", "O MORRO PODE ESPERAR", 11, GOLD)
	_label(heading, "", "RESPIRA.", 48)
	_label(heading, "", "A expedição está pausada.", 14, MUTED)
	var nav := _scroll(pause_menu, Vector4(.052, .34, .36, .90), Vector4.ZERO)
	_button(nav, "VOLTAR À RUA", func() -> void: _call("resume_game"), true, "play")
	_button(nav, "EQUIPAMENTO", func() -> void: _call("open_inventory", ["inventory"]), false, "bag")
	_button(nav, "CONFIGURAÇÕES", func() -> void: show_settings(), false, "settings")
	_button(nav, "SALVAR EXPEDIÇÃO", _save_current, false, "save")
	_button(nav, "CARREGAR", func() -> void: _show_slots("load"), false, "clock")
	_button(nav, "RECOMEÇAR", func() -> void: _confirm("RECOMEÇAR?", "A expedição atual será encerrada. O último save permanece disponível.", func() -> void: _call("restart_run")), false, "restart")
	_button(nav, "VOLTAR AO MENU", func() -> void: _call("return_to_menu"), false, "exit")
	var summary := _box(pause_menu, 17)
	_position(summary, Vector4(.52, .27, .93, .80), Vector4.ZERO)
	_label(summary, "pause_round", "ROUND 01", 40, GOLD)
	_label(summary, "pause_region", "LARGO DA CHEGADA", 18)
	_label(summary, "pause_weapon", "", 23)
	_wrap(_label(summary, "pause_build", "", 14, MUTED))
	_label(summary, "pause_dog", "", 16, ICON.MINT)
	_wrap(_label(summary, "pause_objective", "", 16, MUTED))

func _build_detail() -> void:
	detail = _layer(root)
	detail.name = "MenuDetail"
	_menu_backdrop(detail, true)
	var heading := _box(detail, 5)
	_position(heading, Vector4(.055, .075, .9, .075), Vector4(0, 0, 0, 120))
	detail_kicker = _label(heading, "", "PREPARE A EXPEDIÇÃO", 10, GOLD)
	detail_title = _label(heading, "", "ANTES DA RUA.", 36)
	detail_body = _scroll(detail, Vector4(.06, .245, .93, .855), Vector4(0, 0, 0, 0))
	var back := _button(detail, "VOLTAR", _back, false, "arrow")
	_position(back, Vector4(.057, .91, .24, .91), Vector4(0, 0, 0, 44))

func _clear_detail(title: String, kicker: String) -> void:
	setting_controls.clear()
	for child in detail_body.get_children():
		detail_body.remove_child(child)
		child.queue_free()
	detail_title.text = title
	detail_kicker.text = kicker
	_show(detail)
	var scroll: ScrollContainer = detail_body.get_parent()
	scroll.scroll_vertical = 0

func _slots() -> Array:
	var value: Variant = _call("get_save_slots")
	return value if value is Array else []

func _slot_metadata(slot: int) -> Dictionary:
	for row in _slots():
		if int(row.get("slot", 0)) == slot: return row
	return {"slot": slot, "exists": false, "valid": false, "metadata": {}}

func _duration(seconds: float) -> String:
	return "%02dh %02dmin" % [int(seconds / 3600.0), int(seconds / 60.0) % 60]

func _slot_text(row: Dictionary) -> String:
	var slot := int(row.get("slot", 1))
	if not bool(row.get("exists", false)): return "%02d   /   NOVA HISTÓRIA\nEspaço livre para outra expedição." % slot
	if not bool(row.get("valid", false)): return "%02d   /   SAVE INDISPONÍVEL\n%s" % [slot, str(row.get("error", "Não foi possível ler esta expedição."))]
	var data: Dictionary = row.get("metadata", {})
	var date := str(data.get("date", "")).replace("T", " ").left(16)
	var saved_unix := int(row.get("saved_unix", 0))
	if saved_unix > 0:
		var local_unix := saved_unix + int(Time.get_time_zone_from_system().get("bias", 0)) * 60
		date = Time.get_datetime_string_from_unix_time(local_unix).replace("T", " ").left(16)
	return "%02d   /   ROUND %02d   ·   %s\n%s   /   %s\nFaro nv. %d   ·   %s%s" % [slot, int(data.get("round", 1)), str(data.get("region", "Morro do Vento")), str(data.get("weapon_name", "Arma equipada")), _duration(float(data.get("time", 0))), int(data.get("dog_level", 1)), date, "   ·   RECUPERADO" if row.get("recovered", false) else ""]

func _slot_button(parent: Node, row: Dictionary, action: Callable, selected: bool = false) -> Button:
	var button := _button(parent, _slot_text(row), action, selected, "paw" if row.get("valid", false) else "save")
	button.custom_minimum_size.y = (106 if row.get("exists", false) else 75) * ui_scale
	button.add_theme_font_size_override("font_size", roundi(14 * ui_scale))
	button.set_meta("base_font_size", 14)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return button

func show_new_game() -> void:
	if not is_instance_valid(detail): return
	detail_return = "menu"
	detail_mode = "new"
	if selected_slot < 1:
		for row in _slots():
			if not row.get("exists", false): selected_slot = int(row.slot); break
	_clear_detail("COMO COMEÇA SUA NOITE?", "NOVA EXPEDIÇÃO / ESCOLHA O RISCO")
	var columns := _row(detail_body, 35)
	var left := _box(columns, 12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var right := _box(columns, 10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.0
	right.size_flags_stretch_ratio = 1.1
	_label(left, "", "DIFICULDADE", 11, GOLD)
	difficulty = OptionButton.new()
	difficulty.name = "DifficultySelector"
	difficulty.custom_minimum_size.y = 48 * ui_scale
	for title in DIFFICULTY_NAMES: difficulty.add_item(title)
	difficulty.select(maxi(0, DIFFICULTIES.find(new_difficulty)))
	left.add_child(difficulty)
	difficulty.item_selected.connect(_difficulty_changed)
	_wrap(_label(left, "difficulty_description", "", 16, MUTED))
	_difficulty_changed(difficulty.selected)
	chaos = CheckBox.new()
	chaos.name = "ChaosToggle"
	chaos.text = "INDUTOR DE CAOS"
	chaos.button_pressed = new_chaos
	chaos.toggled.connect(func(value: bool) -> void: new_chaos = value; _feedback("select"))
	left.add_child(chaos)
	_paragraph(left, "A horda chega mais cedo ao limite. Mais pressão, mais recompensas. Sobreviva junto do Faro.", MUTED, 13)
	_button(left, "ENTRAR NA NOITE", _start, true, "play").name = "StartExpedition"
	_label(right, "", "SUA EXPEDIÇÃO / 3 ESPAÇOS", 11, GOLD)
	for number in range(1, 4):
		var row := _slot_metadata(number)
		_slot_button(right, row, func() -> void: selected_slot = number; show_new_game(), selected_slot == number)
	_paragraph(right, "Autosave no progresso importante. Uma expedição existente só será substituída após sua confirmação.", MUTED, 12)

func _difficulty_changed(index: int) -> void:
	new_difficulty = DIFFICULTIES[clampi(index, 0, 4)]
	var descriptions := ["Respire entre as ondas. Mais espaço para conhecer as vielas e montar sua primeira build.", "Pressão constante e recompensas equilibradas. Cada compra abre novas possibilidades.", "Ataques mais perigosos, mais elites e loot melhor. Decida quando lutar e quando recuar.", "A rua quase não descansa. Equipamento, mira e rotas de fuga fazem a diferença.", "O morro cobra tudo. Sobreviva ao risco máximo para disputar as maiores recompensas."]
	if labels.has("difficulty_description"): labels.difficulty_description.text = descriptions[index]

func _start() -> void:
	if selected_slot < 1:
		show_notice("Escolha um dos três espaços para salvar sua expedição.")
		return
	var row := _slot_metadata(selected_slot)
	if row.get("exists", false):
		_confirm("SUBSTITUIR A EXPEDIÇÃO %02d?" % selected_slot, _slot_text(row) + "\n\nO progresso deste espaço será substituído pela nova expedição.", func() -> void: _call("start_run", [new_difficulty, new_chaos, selected_slot]))
	else: _call("start_run", [new_difficulty, new_chaos, selected_slot])

func _show_slots(mode: String) -> void:
	detail_mode = mode
	detail_return = "pause" if pause_menu.visible or (detail.visible and detail_return == "pause") else "menu"
	_clear_detail("RETOME SUA HISTÓRIA." if mode == "load" else "GUARDE SUA HISTÓRIA.", "EXPEDIÇÕES / CARREGAR" if mode == "load" else "EXPEDIÇÕES / SALVAR")
	for number in range(1, 4):
		var row := _slot_metadata(number)
		var button := _slot_button(detail_body, row, func() -> void:
			if mode == "load":
				if detail_return == "pause": _confirm("CARREGAR ESTA EXPEDIÇÃO?", "O progresso não salvo da expedição atual será deixado para trás.", func() -> void: _call("load_game", [number]))
				else: _call("load_game", [number])
			elif row.get("exists", false): _confirm("SUBSTITUIR ESTE SAVE?", _slot_text(row), func() -> void: _call("save_game", [number]); show_pause())
			else: _call("save_game", [number]); show_pause())
		button.disabled = mode == "load" and not row.get("valid", false)

func show_load_game() -> void:
	_show_slots("load")

func _save_current() -> void:
	var result: Variant = _call("save_game", [-1])
	if result == false: show_notice("Não foi possível salvar. Seu save anterior foi preservado.")
	else: saved_time = 2.5; show_notice("Expedição salva.")

func _confirm(title: String, description: String, accept: Callable) -> void:
	if pause_menu.visible: detail_return = "pause"
	var previous_mode := detail_mode
	cancel_confirmation = func() -> void:
		match previous_mode:
			"new": show_new_game()
			"load", "save": _show_slots(previous_mode)
			_: _back()
	detail_mode = "confirm"
	_clear_detail(title, "CONFIRME SUA ESCOLHA")
	_paragraph(detail_body, description, PAPER, 17)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 20
	detail_body.add_child(spacer)
	_button(detail_body, "CONFIRMAR", accept, true, "check")
	_button(detail_body, "CANCELAR", cancel_confirmation, false, "close")

func show_settings() -> void:
	detail_return = "pause" if pause_menu.visible or (detail.visible and detail_return == "pause") else "menu"
	_show_settings_category(settings_category)

func _schema() -> Array:
	var result: Variant = _call("setting_schema")
	if result is Array: return result
	var manager: Variant = game.get("settings")
	if manager != null and manager.has_method("setting_schema"): return manager.setting_schema()
	return []

func _show_settings_category(category: String) -> void:
	detail_mode = "settings"
	settings_category = category
	_clear_detail("DO SEU JEITO.", "CONFIGURAÇÕES / " + str(CATEGORY_NAMES.get(category, category)))
	var tabs := _row(detail_body, 8)
	for id in CATEGORY_NAMES:
		var button := _button(tabs, CATEGORY_NAMES[id], _show_settings_category.bind(id), id == category)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 12)
	_paragraph(detail_body, "Ajustes aplicados e salvos na hora. A cena ao fundo acompanha a imagem e o campo de visão, inclusive durante a pausa.", MUTED, 13)
	for field in _schema():
		if str(field.get("category", "")) != category: continue
		_add_setting(field)

func _add_setting(field: Dictionary) -> void:
	var key := str(field.get("key", ""))
	var row := _row(detail_body, 25)
	row.custom_minimum_size.y = 44 * ui_scale
	var caption := _label(row, "", str(field.get("label", key)), 15)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.size_flags_stretch_ratio = 1.2
	_wrap(caption)
	var value: Variant = _settings().get(key, field.get("default"))
	match str(field.get("type", "toggle")):
		"toggle":
			var input := CheckButton.new()
			setting_controls[key] = input
			input.tooltip_text = str(field.get("label", key))
			input.button_pressed = bool(value)
			input.text = "ATIVADO" if input.button_pressed else "DESATIVADO"
			input.custom_minimum_size.x = 195
			input.toggled.connect(func(enabled: bool) -> void: input.text = "ATIVADO" if enabled else "DESATIVADO"; _change_setting(key, enabled))
			row.add_child(input)
		"slider":
			var controls := _row(row, 14)
			controls.custom_minimum_size.x = 360
			var slider := HSlider.new()
			setting_controls[key] = slider
			slider.tooltip_text = str(field.get("label", key))
			slider.custom_minimum_size.x = 255
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slider.min_value = float(field.get("min", 0))
			slider.max_value = float(field.get("max", 1))
			slider.step = float(field.get("step", .05))
			slider.value = float(value)
			controls.add_child(slider)
			var number := _label(controls, "", _setting_number(key, float(value)), 13, GOLD)
			number.custom_minimum_size.x = 90
			number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			slider.value_changed.connect(func(updated: float) -> void: number.text = _setting_number(key, updated); _change_setting(key, updated))
		"select":
			var input := OptionButton.new()
			setting_controls[key] = input
			input.tooltip_text = str(field.get("label", key))
			input.custom_minimum_size.x = 300
			var options: Array = field.get("options", [])
			input.set_meta("setting_options", options)
			for option in options:
				input.add_item(str(option.get("label", option.get("id", ""))))
				if option.get("id") == value: input.select(input.item_count - 1)
			input.item_selected.connect(func(index: int) -> void:
				if key == "preset": _call("apply_graphics_preset", [options[index].get("id")]); _show_settings_category(category_for_key(key))
				else: _change_setting(key, options[index].get("id")))
			row.add_child(input)
		"color":
			var input := ColorPickerButton.new()
			setting_controls[key] = input
			input.tooltip_text = str(field.get("label", key))
			input.custom_minimum_size = Vector2(195, 36)
			input.color = Color.from_string(str(value), PAPER)
			input.edit_alpha = false
			input.color_changed.connect(func(color: Color) -> void: _change_setting(key, color.to_html(false)))
			row.add_child(input)

func category_for_key(_key: String) -> String:
	return settings_category

func _setting_number(key: String, value: float) -> String:
	if key == "mouse_sensitivity": return "%.4f" % value
	if key == "fov": return "%d°" % roundi(value)
	if key == "render_distance": return "%d m" % roundi(value)
	if key == "fps_limit": return "%d" % roundi(value)
	return "%d%%" % roundi(value * 100)

func _change_setting(key: String, value: Variant) -> void:
	_call("update_setting", [key, value])
	apply_settings(_settings())
	# Manual graphics changes switch the preset to Custom without rebuilding
	# the page underneath a slider drag or losing its keyboard focus.
	var preset: OptionButton = setting_controls.get("preset")
	if is_instance_valid(preset):
		var options: Array = preset.get_meta("setting_options", [])
		for index in range(options.size()):
			if options[index].get("id") == setting_values.get("preset"):
				preset.select(index)
				break

func show_extras() -> void:
	detail_return = "menu"
	detail_mode = "extras"
	_clear_detail("O MORRO LEMBRA.", "ARQUIVO / ESTATÍSTICAS, DESCOBERTAS E HISTÓRIAS")
	var value: Variant = _call("get_extras")
	var data: Dictionary = value if value is Dictionary else {}
	var stats: Dictionary = data.get("stats", {})
	_label(detail_body, "", "RECORDE  %02d     /     %d SIGILOS" % [int(data.get("record", 0)), int(data.get("sigils", 0))], 25, GOLD)
	_paragraph(detail_body, "%d eliminações  ·  %d bosses  ·  %d expedições" % [int(stats.get("kills", 0)), int(stats.get("bosses", 0)), int(stats.get("runs", 0))], PAPER)
	for entry in [["ARMAS DESCOBERTAS", "weapons", "weapon"], ["A LIGA DO RUÍDO", "enemies", "skull"], ["CONQUISTAS", "achievements", "star"]]:
		var line := _row(detail_body)
		_icon(line, entry[2])
		_label(line, "", entry[0], 12, GOLD)
		var values: Variant = data.get(entry[1], [])
		var names := PackedStringArray()
		if values is Array:
			for item in values: names.append(str(item.get("name", item.get("id", ""))) if item is Dictionary else str(item).replace("_", " ").capitalize())
		_paragraph(detail_body, " · ".join(names) if not names.is_empty() else "Sua próxima expedição revela mais deste arquivo.")
	_label(detail_body, "", "O QUE EXISTE ALÉM DO SINAL", 12, GOLD)
	_paragraph(detail_body, "A Liga do Ruído ocupou os relés do Morro do Vento. Meyui e Faro atravessam suas rotas para devolver o bairro a quem vive nele. Os moradores não são a horda; a facção que tomou suas ruas é o inimigo.", PAPER)
	_label(detail_body, "", "COMPANHIAS PARA A PRÓXIMA EXPEDIÇÃO", 12, GOLD)
	var owned: Array = data.get("unlocks", [])
	for option in [["collector", "BATEDOR / busca suprimentos", 3], ["support", "APOIO / sustenta sua build", 5], ["guardian", "GUARDIÃO / protege sua volta", 7]]:
		var id := str(option[0])
		var unlocked := owned.has(id)
		var button := _button(detail_body, str(option[1]) + ("  /  DESBLOQUEADO" if unlocked else "  /  %d SIGILOS" % int(option[2])), func() -> void: _call("unlock_meta", [id]); show_extras(), false, "paw")
		button.disabled = unlocked or int(data.get("sigils", 0)) < int(option[2])
	if data.has("credits"): _paragraph(detail_body, str(data.credits), MUTED, 12)

func _build_shop() -> void:
	var path := "res://scripts/progression_screen.gd"
	if ResourceLoader.exists(path):
		var script: Script = load(path)
		shop = script.new()
		shop.call("setup", game)
		root.add_child(shop)
		shop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		shop = _layer(root)
		_menu_backdrop(shop, true)
		var box := _scroll(shop, Vector4(.1, .15, .8, .8), Vector4.ZERO)
		_label(box, "", "EQUIPAMENTO", 36)
		_button(box, "VOLTAR À RUA", func() -> void: _call("resume_game"), true)
	shop.visible = false

func show_inventory(tab: String = "inventory") -> void:
	notice_time = 0
	labels.notice.text = ""
	_show(shop)
	if shop.has_method("open"): shop.call("open", tab)

func show_shop() -> void:
	show_inventory("forge")

func refresh_progression() -> void:
	if is_instance_valid(shop) and shop.has_method("refresh"): shop.call("refresh")

func update_buttons() -> void:
	refresh_progression()

func _build_game_over() -> void:
	game_over = _layer(root)
	_menu_backdrop(game_over, true)
	var content := _scroll(game_over, Vector4(.1, .21, .65, .85), Vector4.ZERO)
	_label(content, "", "EXPEDIÇÃO ENCERRADA", 11, CORAL)
	_label(content, "", "A GENTE VOLTA.", 50)
	_label(content, "results", "", 24, GOLD)
	_paragraph(content, "O que você descobriu não desaparece. Escolha sua próxima rota, ajuste sua build e encontre o Faro na rua.")
	_button(content, "MAIS UMA EXPEDIÇÃO", func() -> void: _call("restart_run"), true, "restart")
	_button(content, "CARREGAR UM SAVE", func() -> void: _show_slots("load"), false, "save")
	_button(content, "VOLTAR AO MENU", func() -> void: _call("return_to_menu"), false, "exit")

func _build_hud() -> void:
	hud = _layer(root)
	hud.name = "CombatHUD"
	var hud_theme := root.theme.duplicate()
	hud_theme.set_color("font_shadow_color", "Label", Color.TRANSPARENT)
	hud_theme.set_constant("shadow_offset_y", "Label", 0)
	hud.theme = hud_theme
	var bottom_shade := _gradient(hud, Color.TRANSPARENT, Color(.013, .02, .028, .38), true)
	_position(bottom_shade, Vector4(0, .85, 1, 1), Vector4.ZERO)
	var top_shade := _gradient(hud, Color(.013, .02, .028, .24), Color.TRANSPARENT, true)
	_position(top_shade, Vector4(0, 0, 1, .15), Vector4.ZERO)
	damage_screen = DamageVeil.new()
	hud.add_child(damage_screen)
	damage_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	damage_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var round_box := _row(hud, 14)
	round_box.name = "RoundReadout"
	_position(round_box, Vector4.ZERO, Vector4(36, 28, 298, 88))
	_hud_backing(round_box,Color("fa8167"))
	_label(round_box, "round", "01", 46, HUD_WHITE)
	var round_details := _box(round_box, 4)
	round_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	round_details.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_label(round_details, "phase", "ROUND / PREPARE-SE", 10, Color("ffa98f"))
	_label(round_details, "remaining", "PRÓXIMO SINAL EM 8s", 11, HUD_WHITE)
	var district := _label(hud, "district", "MORRO DO VENTO", 12, HUD_WHITE)
	district.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_position(district, Vector4(1, 0, 1, 0), Vector4(-420, 28, -34, 74))
	var saved := _label(hud, "saved", "EXPEDIÇÃO SALVA", 10, ICON.MINT)
	saved.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_position(saved, Vector4(1, 0, 1, 0), Vector4(-320, 78, -35, 107))
	var event_label := _label(hud, "event", "", 12, CORAL)
	event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_position(event_label, Vector4(.32, .035, .68, .035), Vector4(0, 0, 0, 32))
	var money_row := _row(hud, 8)
	_position(money_row, Vector4(0,1,0,1), Vector4(35,-185,301,-145))
	_icon(money_row, "coin", Color("f2c779"), 22)
	_label(money_row, "coins", "0", 26, Color("f2c779"))
	_label(money_row, "coins_gain", "", 15, Color("99edce"))
	var vitals := _box(hud, 10)
	vitals.name = "VitalReadout"
	_position(vitals, Vector4(0, 1, 0, 1), Vector4(36, -132, 300, -32))
	_hud_backing(vitals,Color("73dbc6"))
	var critical := _label(hud, "critical_health", "VIDA CRÍTICA / PROCURE ABRIGO", 10, Color("ff6657"))
	_position(critical, Vector4(0, 1, 0, 1), Vector4(36, -213, 338, -191))
	critical.visible = false
	var life_row := _row(vitals, 10)
	var portrait := HealthPortrait.new()
	portrait.custom_minimum_size = Vector2(48,48)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	life_row.add_child(portrait)
	var life_column := _box(life_row, 0)
	life_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(life_column, "", "MEYUI", 10, HUD_MUTED)
	_label(life_column, "health", "100 / 100", 27, HUD_WHITE)
	health_bar = _bar(life_column, Color("73dbc6"), 6)
	var dog_row := _row(vitals,7)
	_icon(dog_row,"paw",Color("95c6df"),18)
	var dog_column := _box(dog_row,4)
	dog_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(dog_column, "dog", "FARO  ·  NV 1", 10, HUD_MUTED)
	dog_bar = _bar(dog_column, Color("95c6df"), 3)
	var ammo := _box(hud, 1)
	ammo.name = "WeaponReadout"
	_position(ammo, Vector4(1, 1, 1, 1), Vector4(-285, -141, -36, -32))
	_hud_backing(ammo,Color("f2c779"))
	_label(ammo, "weapon_rarity", "", 10, HUD_MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label(ammo, "weapon", "BISCOITEIRA 12", 16, HUD_WHITE).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var ammo_row := _row(ammo,10)
	ammo_row.alignment = BoxContainer.ALIGNMENT_END
	_label(ammo_row,"ammo","12",43,HUD_WHITE).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var reserve := _label(ammo_row,"ammo_reserve","/ 048",19,HUD_MUTED)
	reserve.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	reserve.size_flags_vertical = Control.SIZE_EXPAND_FILL
	reload_bar = _bar(ammo, GOLD, 3)
	_label(ammo, "reload", "R  RECARREGAR", 10, HUD_MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var keys := _label(hud, "", "I  INVENTÁRIO     TAB  MELHORIAS     T  ARSENAL", 10, HUD_MUTED)
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_position(keys, Vector4(.3, 1, .7, 1), Vector4(0, -26, 0, -8))
	var utilities := _row(hud, 8)
	utilities.alignment = BoxContainer.ALIGNMENT_CENTER
	_position(utilities, Vector4(.28, 1, .72, 1), Vector4(0, -83, 0, -40))
	for entry: Array in [["grenade", "blast", "G"], ["medkit", "heart", "H"], ["ammo_supply", "ammo", "J"]]:
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := ICON.style(Color("111d28"),Color("354b5c"),3)
		style.content_margin_left = 9
		style.content_margin_right = 9
		style.content_margin_top = 6
		style.content_margin_bottom = 6
		panel.add_theme_stylebox_override("panel",style)
		utilities.add_child(panel)
		var slot := _row(panel,7)
		_icon(slot, entry[1], HUD_WHITE, 22)
		var count := _box(slot,0)
		count.custom_minimum_size.x = 18
		_label(count,"",entry[2],9,HUD_MUTED)
		_label(count, entry[0] + "_count", "0", 16, HUD_WHITE)
	powerup_display = _row(hud, 18)
	powerup_display.alignment = BoxContainer.ALIGNMENT_CENTER
	_position(powerup_display, Vector4(.31, 1, .69, 1), Vector4(0, -136, 0, -95))
	var objective := _label(hud, "objective", "", 12, HUD_WHITE)
	objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wrap(objective)
	_position(objective, Vector4(.29, 1, .71, 1), Vector4(0, -187, 0, -148))
	var interaction := _label(hud, "interaction", "", 16, GOLD)
	interaction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wrap(interaction)
	_position(interaction, Vector4(.27, .70, .73, .70), Vector4(0, 0, 0, 64))
	reticle = AimMark.new()
	hud.add_child(reticle)
	reticle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	announcement = _box(hud, 5)
	_position(announcement, Vector4(.16, .20, .84, .20), Vector4.ZERO)
	_label(announcement, "announcement_title", "", 38, GOLD).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var subtitle := _label(announcement, "announcement_subtitle", "", 15)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wrap(subtitle)
	boss_display = _box(hud, 3)
	_position(boss_display, Vector4(.31, .095, .69, .095), Vector4(0, 0, 0, 65))
	_label(boss_display, "boss_name", "", 17, CORAL).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_bar = _bar(boss_display, CORAL, 5)
	_label(boss_display, "boss_phase", "", 10, MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_build_loot_comparison()

class HealthPortrait:
	extends Control
	func _draw() -> void:
		var c := size*0.5
		draw_circle(c,20,Color("16333c"))
		draw_arc(c,20,-PI/2,PI*1.35,36,Color("80c9b6"),1.5,true)
		draw_style_box(ICON.style(Color("b7784e"),Color.TRANSPARENT,7),Rect2(c+Vector2(-9,-11),Vector2(17,23)))
		draw_style_box(ICON.style(Color("bf8e5c"),Color.TRANSPARENT,5),Rect2(c+Vector2(0,-3),Vector2(17,11)))
		draw_style_box(ICON.style(Color("6c4934"),Color.TRANSPARENT,5),Rect2(c+Vector2(-12,-7),Vector2(8,23)))
		draw_circle(c+Vector2(5,-4),2,Color("091217"))
		draw_circle(c+Vector2(16,0),3,Color("091217"))

func _hud_backing(control: Control, color: Color) -> void:
	var background := Panel.new()
	background.name = control.name + "Background"
	control.get_parent().add_child(background)
	control.get_parent().move_child(background,control.get_index())
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control.item_rect_changed.connect(_place_hud_backing.bind(control,background))
	_place_hud_backing.call_deferred(control,background)
	# A sibling before the content guarantees that opaque fill never covers text.
	background.set_meta("hud_backing",true)
	var style := ICON.style(Color("101b25"),Color("354756"),3)
	style.border_color = color.darkened(.38)
	style.border_width_left = 3
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_width_right = 1
	background.add_theme_stylebox_override("panel",style)

func _place_hud_backing(control: Control, background: Control) -> void:
	if not is_instance_valid(control) or not is_instance_valid(background): return
	background.set_anchors_preset(Control.PRESET_TOP_LEFT)
	background.position = control.position - Vector2(12,9)
	background.size = control.size + Vector2(24,18)

func _bar(parent: Node, color: Color, height: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.show_percentage = false
	bar.custom_minimum_size.y = height
	var background := ICON.style(Color(.04, .07, .08, .85), Color.TRANSPARENT, 1)
	background.content_margin_top = 0
	background.content_margin_bottom = 0
	bar.add_theme_stylebox_override("background", background)
	var fill := ICON.style(color, Color.TRANSPARENT, 1)
	fill.content_margin_top = 0
	fill.content_margin_bottom = 0
	bar.add_theme_stylebox_override("fill", fill)
	parent.add_child(bar)
	return bar

func _build_loot_comparison() -> void:
	loot_display = PanelContainer.new()
	loot_display.name = "ContextualLoot"
	loot_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(loot_display)
	_position(loot_display, Vector4(.705, .16, .975, .16), Vector4.ZERO)
	loot_panel_style = ICON.style(Color(.025, .035, .044, .96), Color(.4, .4, .35, .34), 3)
	loot_panel_style.border_width_top = 3
	loot_panel_style.content_margin_left = 14
	loot_panel_style.content_margin_right = 14
	loot_panel_style.content_margin_top = 10
	loot_panel_style.content_margin_bottom = 10
	loot_display.add_theme_stylebox_override("panel", loot_panel_style)
	var content := _box(loot_display, 6)
	var heading := _row(content, 5)
	var rarity := _label(heading, "loot_rarity", "", 10, GOLD)
	rarity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(heading, "loot_level", "", 10, MUTED)
	var identity := _row(content, 9)
	loot_thumbnail = LootThumbnail.new()
	loot_thumbnail.custom_minimum_size = Vector2(82, 51)
	loot_thumbnail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.add_child(loot_thumbnail)
	var titles := _box(identity, 2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := _wrap(_label(titles, "loot_name", "", 18))
	title.max_lines_visible = 2
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_label(titles, "loot_maker", "", 10, MUTED)
	var columns := _row(content, 6)
	var column_name := _label(columns, "loot_type", "ATRIBUTO", 8, MUTED)
	column_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(columns, "loot_equipped", "EQUIPADA", 8, MUTED)
	_label(columns, "loot_found", "NO CHÃO", 8, GOLD).custom_minimum_size.x = 77
	loot_stats_box = _box(content, 4)
	for descriptor in [["DANO", "damage", 1], ["CADÊNCIA", "fire_rate", 1], ["PENTE", "magazine_size", 1], ["RECARGA", "reload_time", -1], ["PRECISÃO", "precision", 1]]:
		var stack := _box(loot_stats_box, 1)
		var row := _row(stack, 7)
		var label := _label(row, "", descriptor[0], 10, MUTED)
		label.custom_minimum_size.x = 85
		var before := _label(row, "", "", 11, MUTED)
		before.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		before.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var arrow := _label(row, "", "", 12, GOLD)
		arrow.custom_minimum_size.x = 12
		var after := _label(row, "", "", 12, PAPER)
		after.custom_minimum_size.x = 67
		after.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var meter := _bar(stack, GOLD, 2)
		loot_rows.append({"key": descriptor[1], "direction": descriptor[2], "before": before, "after": after, "arrow": arrow, "meter": meter, "stack": stack})
	var details := _wrap(_label(content, "loot_details", "", 11, ICON.MINT))
	details.max_lines_visible = 2
	details.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_label(content, "loot_prompt", "E  RECOLHER    /    TAB  EQUIPAMENTO", 9, GOLD)
	loot_display.visible = false

func _show(visible_menu: Control) -> void:
	for page in [menu, pause_menu, shop, game_over, detail]:
		if is_instance_valid(page): page.visible = page == visible_menu
	hud.visible = visible_menu == null
	if is_instance_valid(visible_menu):
		if menu_tween and menu_tween.is_valid(): menu_tween.kill()
		visible_menu.modulate.a = .35
		menu_tween = create_tween()
		menu_tween.tween_property(visible_menu, "modulate:a", 1.0, .16)

func show_menu() -> void:
	_show(menu)
	damage_screen.clear()
	labels.critical_health.visible = false
	detail_return = "menu"
	var available := false
	var most_recent: Dictionary = {}
	for row in _slots():
		if row.get("valid", false):
			available = true
			if float(row.get("saved_unix", 0)) >= float(most_recent.get("saved_unix", 0)): most_recent = row
	continue_button.disabled = not available
	if available:
		var metadata: Dictionary = most_recent.get("metadata", {})
		labels.menu_save.text = "SUA ÚLTIMA ROTA\nROUND %02d / %s" % [int(metadata.get("round", 1)), str(metadata.get("region", "Morro do Vento")).to_upper()]
	else: labels.menu_save.text = "SEU CÃO. SUA BUILD.\nMAIS UMA ESQUINA."

func show_pause() -> void:
	_show(pause_menu)
	detail_return = "pause"
	labels.pause_round.text = "ROUND %02d" % int(last_hud.get("round", 1))
	labels.pause_region.text = str(last_hud.get("district", "Morro do Vento")).to_upper()
	labels.pause_weapon.text = str(last_hud.get("weapon_name", "Biscoiteira 12")).to_upper()
	labels.pause_build.text = "%d PETISCOS    /    VIDA %d / %d\nMUNIÇÃO %d / %d\n%s" % [int(last_hud.get("coins", 0)), int(last_hud.get("health", 100)), int(last_hud.get("max_health", 100)), int(last_hud.get("magazine", 0)), int(last_hud.get("reserve", 0)), str(last_hud.get("build", "Toda boa build começa com a próxima escolha."))]
	labels.pause_dog.text = _dog_summary(last_hud)
	labels.pause_objective.text = str(last_hud.get("objective", "Explore as rotas, encontre equipamento e enfrente a Liga."))

func _back() -> void:
	_feedback("back")
	if detail_return == "pause": show_pause()
	else: show_menu()

func hide_menus() -> void:
	_show(null)

func show_game_over(round_number: int, coins: int) -> void:
	labels.results.text = "ROUND %02d / %d PETISCOS" % [round_number, coins]
	detail_return = "menu"
	_show(game_over)

func update_hud(data: Dictionary) -> void:
	var supply_counts: Dictionary = data.get("supplies", {})
	for entry: Array in [["grenade", "grenade", "G"], ["medkit", "medkit", "H"], ["ammo_supply", "ammo", "J"]]:
		if labels.has(entry[0] + "_count"):
			labels[entry[0] + "_count"].text = str(int(supply_counts.get(entry[1], 0)))
	last_hud = data.duplicate()
	if not is_instance_valid(hud): return
	labels.round.text = "%02d" % int(data.get("round", 1))
	var phase_id := str(data.get("phase", "combat"))
	var phase := str({"combat": "NA RUA", "prepare": "PREPARE-SE", "prep": "PREPARE-SE", "preparation": "PREPARE-SE", "rest": "RESPIRO", "intermission": "RESPIRO", "transition": "ROUND COMPLETO", "complete": "ROUND COMPLETO"}.get(phase_id, phase_id.to_upper()))
	var countdown := float(data.get("countdown", data.get("phase_countdown", data.get("seconds", 0))))
	labels.phase.text = "ROUND / " + phase
	labels.remaining.text = "%d INIMIGOS NA RUA" % int(data.get("remaining", 0)) if countdown <= 0 else "PRÓXIMO SINAL EM %ds" % ceili(countdown)
	var coins := int(data.get("coins", 0))
	labels.coins.text = str(coins)
	var gain := int(data.get("coins_gain", 0))
	if last_coins >= 0 and coins > last_coins: gain = coins - last_coins
	if gain > 0: labels.coins_gain.text = "+%d" % gain; gain_time = 1.1
	last_coins = coins
	var health := float(data.get("health", 100))
	var maximum := maxf(1.0, float(data.get("max_health", 100)))
	last_health = health
	labels.health.text = "%d / %d" % [ceili(health), roundi(maximum)]
	health_bar.value = 100 * health / maximum
	damage_screen.danger = clampf(1.0 - health / maximum * 3, 0, 1)
	labels.critical_health.visible = health > 0 and health / maximum < .3
	labels.dog.text = _dog_summary(data)
	dog_bar.value = 100 * float(data.get("dog_health", 100)) / maxf(1.0, float(data.get("dog_max_health", 100)))
	labels.weapon.text = str(data.get("weapon_name", "Biscoiteira 12")).to_upper()
	labels.weapon_rarity.text = str(data.get("weapon_rarity", data.get("rarity", ""))).to_upper()
	if is_instance_valid(game) and game.get("inventory") != null:
		labels.weapon_rarity.text += "   /   SLOT %d" % (int(game.inventory.active_weapon_slot)+1)
		var tint: Color = preload("res://data/loot_data.gd").rarity_color(str(game.inventory.equipped().get("rarity","common")))
		labels.weapon.add_theme_color_override("font_color",tint)
	labels.ammo.text = "%02d" % int(data.get("magazine",0))
	labels.ammo_reserve.text = "/ %03d" % int(data.get("reserve",0))
	labels.ammo.add_theme_color_override("font_color",Color("ff806f") if int(data.get("magazine",0)) <= 2 else HUD_WHITE)
	var progress := float(data.get("reload_progress", 0))
	reload_bar.value = progress * 100
	reload_bar.visible = progress > 0
	labels.reload.text = "RECARREGANDO" if progress > 0 else "R  RECARREGAR"
	var difficulty_id := str(data.get("difficulty", "normal"))
	labels.district.text = "%s\n%s%s" % [str(data.get("district", "MORRO DO VENTO")).to_upper(), DIFFICULTY_NAMES[maxi(0, DIFFICULTIES.find(difficulty_id))].to_upper(), " / CAOS ATIVO" if bool(data.get("chaos", false)) else ""]
	labels.objective.text = str(data.get("objective", ""))
	var event_name := str(data.get("event_name", ""))
	labels.event.text = "%s / %ds" % [event_name.to_upper(), ceili(float(data.get("event_remaining", 0)))] if not event_name.is_empty() else ""
	var boss_name := str(data.get("boss_name", ""))
	boss_display.visible = not boss_name.is_empty()
	labels.boss_name.text = boss_name.to_upper()
	boss_bar.value = 100 * float(data.get("boss_health", 0)) / maxf(1, float(data.get("boss_max_health", 1)))
	labels.boss_phase.text = "FASE %d / %d" % [int(data.get("boss_phase", 1)), int(data.get("boss_phases", 3))]
	var interaction: Dictionary = data.get("interaction", {}) if data.get("interaction", {}) is Dictionary else {}
	labels.interaction.text = "%s  %s%s" % [str(interaction.get("prompt", "E")), str(interaction.get("name", "")), " / %d PETISCOS" % int(interaction.cost) if int(interaction.get("cost", 0)) > 0 else ""] if not interaction.is_empty() else ""
	if not str(interaction.get("description","")).is_empty(): labels.interaction.text += "\n" + str(interaction.description)
	if bool(data.get("saved", false)): saved_time = 2.5
	var comparison: Dictionary = data.get("loot_compare", {}) if data.get("loot_compare", {}) is Dictionary else {}
	if comparison.is_empty() and interaction.get("comparison", {}) is Dictionary: comparison = interaction.get("comparison", {})
	_update_loot(comparison)
	if loot_display.visible: labels.interaction.text = ""
	_update_powerups(data.get("powerups", {}))

func _dog_summary(data: Dictionary) -> String:
	var status := str(data.get("dog_status", "ao seu lado"))
	if status.to_lower().begins_with("faro "): return status.to_upper()
	return "FARO / NV %d · %s" % [int(data.get("dog_level", 1)), status.to_upper()]

func _update_powerups(value: Variant) -> void:
	var active: Dictionary = value if value is Dictionary else {}
	var names := {"infinite_ammo": "SEM LIMITE", "double_damage": "DANO DUPLO", "frenzy": "FRENESI", "magnet": "ÍMÃ", "overcharge": "SOBRECARGA"}
	var ordered := active.keys()
	ordered.sort()
	var signature := str(ordered)
	if signature != powerup_signature:
		powerup_signature = signature
		powerup_labels.clear()
		for child in powerup_display.get_children():
			powerup_display.remove_child(child)
			child.queue_free()
		for index in mini(3, ordered.size()):
			var id := str(ordered[index])
			var entry := _box(powerup_display, 1)
			entry.custom_minimum_size.x = 105
			var line := _row(entry, 5)
			line.alignment = BoxContainer.ALIGNMENT_CENTER
			_icon(line, "bolt" if id in ["frenzy", "overcharge"] else "chip", GOLD, 16)
			_label(line, "", str(names.get(id, id.to_upper())), 9, GOLD)
			var duration := _label(entry, "", "", 10, MUTED)
			duration.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			powerup_labels[id] = duration
		if ordered.size() > 3:
			var overflow := _label(powerup_display, "", "+%d" % (ordered.size() - 3), 12, GOLD)
			overflow.tooltip_text = "Outros efeitos ativos na sua build."
	for id in powerup_labels:
		powerup_labels[id].text = "%ds" % ceili(float(active.get(id, 0)))
	powerup_display.visible = not active.is_empty()

func _update_loot(value: Variant) -> void:
	var data: Dictionary = value if value is Dictionary else {}
	loot_display.visible = not data.is_empty()
	if data.is_empty():
		loot_signature = ""
		return
	var stats: Dictionary = data.get("stats", {})
	var current: Dictionary = data.get("current", {})
	var item: Dictionary = data.get("item", {})
	var kind := str(data.get("type", "weapon"))
	var is_equipment := kind in ["weapon", "attachment"]
	var rarity := str(item.get("rarity", stats.get("rarity", "common")))
	var rarity_data: Dictionary = LOOT.RARITIES.get(rarity, LOOT.RARITIES.common)
	labels.loot_name.text = str(stats.get("name", item.get("name", "EQUIPAMENTO")) if kind == "weapon" else item.get("name", "MUNIÇÃO" if kind == "ammo" else "SUPRIMENTO")).to_upper()
	labels.loot_rarity.text = str(rarity_data.name).to_upper() if is_equipment else "SUPRIMENTO" if kind == "ammo" else "POWER-UP"
	labels.loot_level.text = "NV %d" % int(item.get("level", stats.get("level", 1))) if is_equipment else ""
	var maker := str(stats.get("manufacturer_name", item.get("manufacturer_name", "")))
	if maker.is_empty(): maker = str(LOOT.MANUFACTURERS.get(str(item.get("manufacturer", "")), {}).get("name", ""))
	labels.loot_maker.text = maker.to_upper() if kind == "weapon" else str({"sight":"MIRA", "barrel":"CANO", "underbarrel":"EMPUNHADURA", "magazine":"CARREGADOR", "internal":"MECANISMO"}.get(str(item.get("slot", "")), "RESERVA DA ARMA" if kind == "ammo" else "EFEITO TEMPORÁRIO"))
	labels.loot_maker.visible = not labels.loot_maker.text.is_empty()
	var tint: Color = rarity_color(rarity) if is_equipment else Color("d5b77d") if kind == "ammo" else ICON.MINT
	labels.loot_rarity.add_theme_color_override("font_color", tint)
	labels.loot_found.add_theme_color_override("font_color", tint)
	loot_panel_style.border_color = Color(tint, .66)
	loot_thumbnail.kind = kind
	loot_thumbnail.family = str(stats.get("family", item.get("family", "pistol")))
	loot_thumbnail.tint = tint
	loot_thumbnail.rank = int(rarity_data.rank) if is_equipment else 0
	loot_thumbnail.queue_redraw()
	loot_stats_box.visible = is_equipment
	labels.loot_type.text = "ATRIBUTO" if is_equipment else "QUANTIDADE" if kind == "ammo" else "EFEITO"
	labels.loot_equipped.visible = is_equipment
	labels.loot_found.visible = is_equipment
	labels.loot_found.text = "COM PEÇA" if kind == "attachment" else "NO CHÃO"
	for row in loot_rows:
		var key := str(row.key)
		var before := float(current.get(key, 0))
		var after := float(stats.get(key, 0))
		if key == "magazine_size": before = float(current.get(key, current.get("capacity", current.get("magazine", 0)))); after = float(stats.get(key, stats.get("capacity", stats.get("magazine", 0))))
		row.before.text = _loot_stat_number(key, before)
		row.after.text = _loot_stat_number(key, after)
		var change := (after - before) * int(row.direction)
		row.arrow.text = "↑" if change > .001 else ("↓" if change < -.001 else "=")
		row.after.add_theme_color_override("font_color", ICON.MINT if change > .001 else (CORAL if change < -.001 else PAPER))
		row.arrow.add_theme_color_override("font_color", ICON.MINT if change > .001 else (CORAL if change < -.001 else MUTED))
		row.meter.value = 100 * after / maxf(.01, maxf(before, after) * 1.12)
		row.meter.get_theme_stylebox("fill").bg_color = ICON.MINT if change > .001 else (CORAL if change < -.001 else GOLD)
	labels.loot_prompt.text = "E  RECOLHER    F  TROCAR / DEIXAR ATUAL"
	if kind == "ammo":
		var quantity := int(item.get("amount", stats.get("amount", 0)))
		var accepted := int(stats.get("collectable", quantity))
		labels.loot_details.text = "%d CARTUCHOS\nRESERVA %d / %d" % [quantity, int(stats.get("reserve", current.get("reserve", 0))), int(stats.get("max_reserve", current.get("max_reserve", 0)))]
		if accepted <= 0: labels.loot_prompt.text = "RESERVA CHEIA"
		else: labels.loot_prompt.text = "E  RECOLHER +%d CARTUCHOS" % accepted
	elif kind == "attachment":
		labels.loot_details.text = str(item.get("description", ""))
		if labels.loot_details.text.is_empty(): labels.loot_details.text = _modifier_summary(stats.get("modifiers", []))
		labels.loot_prompt.text = "E  RECOLHER    /    INSTALE NA BANCADA"
	elif kind == "powerup":
		labels.loot_details.text = str(item.get("description", ""))
		var duration := float(stats.get("duration", item.get("duration", 0)))
		labels.loot_level.text = "%ds" % ceili(duration) if duration > 0 else "IMEDIATO"
		labels.loot_prompt.text = "E  ATIVAR POWER-UP"
	else:
		labels.loot_details.text = _modifier_summary(stats.get("modifiers", item.get("modifiers", [])))
	labels.loot_details.visible = not labels.loot_details.text.is_empty()
	var signature := "%s:%s:%s:%s" % [kind, item.get("uid", item.get("id", "")), labels.loot_name.text, labels.loot_details.text]
	if signature != loot_signature:
		loot_signature = signature
		call_deferred("_resize_loot")

func _loot_stat_number(key: String, value: float) -> String:
	if key == "fire_rate": return "%d/min" % roundi(value * 60)
	if key == "reload_time": return "%.1fs" % value
	if key == "precision": return "%d%%" % roundi(value)
	return "%d" % roundi(value)

func _modifier_summary(value: Variant) -> String:
	if not value is Array or value.is_empty(): return ""
	var names := PackedStringArray()
	var first_description := ""
	for index in mini(2, value.size()):
		var entry: Dictionary = value[index] if value[index] is Dictionary else LOOT.MODIFIERS.get(str(value[index]), {})
		if entry.is_empty(): continue
		names.append(str(entry.get("name", "")).to_upper())
		if first_description.is_empty(): first_description = str(entry.get("description", ""))
	if value.size() > 2: names.append("+%d EFEITOS" % (value.size() - 2))
	return " · ".join(names) + ("\n" + first_description if not first_description.is_empty() else "")

func _resize_loot() -> void:
	if not is_instance_valid(loot_display): return
	loot_display.size.y = loot_display.get_combined_minimum_size().y

func rarity_color(id: String) -> Color:
	var palette := {"common": "b3bdb5", "uncommon": "8cbb8d", "rare": "80b6d4", "epic": "b2a0d2", "legendary": "d9b477", "mythic": "d289b0"}
	if str(setting_values.get("colorblind_mode", "normal")) != "normal": palette = {"common": "ccd0cb", "uncommon": "e2bc77", "rare": "72b8e0", "epic": "c9a8ed", "legendary": "f0d984", "mythic": "e4a9cf"}
	return Color(str(palette.get(id, "d9b477")))

func apply_settings(values: Dictionary) -> void:
	setting_values = values.duplicate()
	ui_scale = clampf(float(values.get("ui_scale", 1)), .8, 1.3)
	if not is_instance_valid(root): return
	root.theme.default_font_size = roundi(16 * ui_scale)
	_apply_font_scale(root)
	reticle.enabled = bool(values.get("crosshair", true))
	reticle.hit_enabled = bool(values.get("hitmarkers", true))
	reticle.crosshair_color = Color.from_string(str(values.get("crosshair_color", "e7e2d4")), PAPER)
	reticle.hit_color = Color.from_string(str(values.get("hitmarker_color", "d9b477")), GOLD)
	damage_screen.reduced_flashes = bool(values.get("reduced_flashes", false))
	reticle.queue_redraw()
	root.theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 1 if values.get("high_contrast", false) else .7))
	root.theme.set_constant("shadow_offset_y", "Label", 3 if values.get("high_contrast", false) else 2)
	if is_instance_valid(shop) and shop.has_method("apply_settings"): shop.call("apply_settings", values)

func _apply_font_scale(node: Node) -> void:
	if node is Control and node.has_meta("base_font_size"): node.add_theme_font_size_override("font_size", roundi(int(node.get_meta("base_font_size")) * ui_scale))
	for child in node.get_children(): _apply_font_scale(child)

func show_notice(message: String) -> void:
	if labels.has("notice"): labels.notice.text = message
	notice_time = 3.0

func show_hit(headshot: bool, kill: bool = false) -> void:
	if not reticle.hit_enabled: return
	reticle.critical = headshot
	reticle.hit_time = .24 if kill else .16
	reticle.queue_redraw()

func show_damage(amount: float = 1.0, direction: Vector2 = Vector2.ZERO, absorbed: bool = false) -> void:
	if not is_instance_valid(damage_screen) or not is_finite(amount) or amount <= 0: return
	var maximum := maxf(1.0, float(last_hud.get("max_health", 100)))
	var strength := clampf(.40 + amount / maximum * 2.1, .4, 1.0)
	damage_screen.receive(strength, direction, absorbed)

func announce(title: String, subtitle: String = "") -> void:
	if is_instance_valid(game.get("coop")) and game.coop.has_method("relay_announcement") and game.coop.relay_announcement(title,subtitle): return
	labels.announcement_title.text = title.to_upper()
	labels.announcement_subtitle.text = subtitle
	announcement_time = 2.7
	announcement.modulate.a = 0
	create_tween().tween_property(announcement, "modulate:a", 1.0, .12)

func _process(delta: float) -> void:
	if not is_instance_valid(root): return
	elapsed += delta
	notice_time = maxf(0, notice_time - delta)
	announcement_time = maxf(0, announcement_time - delta)
	gain_time = maxf(0, gain_time - delta)
	saved_time = maxf(0, saved_time - delta)
	labels.notice.modulate.a = minf(1, notice_time * 3)
	labels.coins_gain.modulate.a = minf(1, gain_time * 3)
	labels.saved.modulate.a = minf(1, saved_time * 3)
	if announcement_time < .4: announcement.modulate.a = announcement_time / .4
	if reticle.hit_time > 0: reticle.hit_time = maxf(0, reticle.hit_time - delta); reticle.queue_redraw()
	damage_screen.tick(delta)
	labels.critical_health.modulate.a = damage_screen.pulse() + .25
	for art in get_tree().get_nodes_in_group("meyui_menu_art"):
		if art.is_visible_in_tree(): art.clock = elapsed; art.queue_redraw()

func _input(event: InputEvent) -> void:
	if not is_instance_valid(detail) or not detail.visible or event.is_echo(): return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if detail_mode == "confirm" and cancel_confirmation.is_valid(): cancel_confirmation.call()
		else: _back()
		get_viewport().set_input_as_handled()

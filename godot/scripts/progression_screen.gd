class_name MeyuiProgressionScreen
extends Control

const Icons = preload("res://scripts/ui_icons.gd")
const Preview = preload("res://scripts/preview_stage.gd")
const Data = preload("res://data/game_data.gd")
const Loot = preload("res://data/loot_data.gd")
const Equipment = preload("res://data/equipment_data.gd")
const INK: Color = Color("0c1015")
const PANEL: Color = Color("141c23")
const PAPER: Color = Color("e7e2d4")
const MUTED: Color = Color("839293")
const GOLD: Color = Color("d9b477")
const MINT: Color = Color("80c9b6")
const CORAL: Color = Color("c76c63")
const SLOT_NAMES: Dictionary = {"sight":"MIRA", "barrel":"CANO", "underbarrel":"EMPUNHADURA", "magazine":"CARREGADOR", "internal":"MECANISMO"}
const TAB_NAMES: Dictionary = {"inventory":"ARSENAL", "supplies":"UTILITÁRIOS", "forge":"BANCADA", "perks":"TALENTOS", "dog":"FARO"}
const TAB_ICONS: Dictionary = {"inventory":"bag", "supplies":"ammo", "forge":"forge", "perks":"chip", "dog":"paw"}

var game: Node
var _tab: String = "inventory"
var _selected_uid: String = ""
var _sort: String = "recent"
var _selected_slot: String = "sight"
var _show_stock: bool = false
var _show_details: bool = false
var _selected_perk: String = "force"
var _loadout_target := 0
var _overlay: PanelContainer
var _overlay_kind := ""
var _body: MarginContainer
var _wallet: Label
var _location: Label
var _tab_buttons: Dictionary = {}
var _refresh_pending: bool = false
var _progress: Dictionary = {}
var _ui_scale: float = 1.0


class WeaponThumbnail:
	extends Control
	var family: String = "pistol"
	var tint: Color = Color("80c9b6")
	var portrait: Texture2D
	func set_portrait(value: Texture2D) -> void:
		portrait = value
		queue_redraw()
	func request_portrait(item: Dictionary, stats: Dictionary) -> void:
		preload("res://scripts/weapon_portraits.gd").request(item, stats, self)

	func _draw() -> void:
		if portrait != null:
			draw_texture_rect(portrait, Rect2(Vector2.ZERO, size), false)
			return
		var scale_factor: float = minf(size.x / 230.0, size.y / 58.0)
		draw_set_transform(size * Vector2(0.48, 0.44), 0.0, Vector2.ONE * scale_factor)
		var long_gun: bool = family not in ["pistol", "revolver", "smg", "improvised"]
		var length: float = 72.0 if long_gun else 49.0
		draw_style_box(Icons.style(Color(tint, 0.06), Color.TRANSPARENT, 3), Rect2(-100.0, -21.0, 210.0, 45.0))
		draw_rect(Rect2(-length * 0.5, -10.0, length, 15.0), tint)
		draw_rect(Rect2(length * 0.5, -6.0, 54.0 if long_gun else 30.0, 5.0), tint.lightened(0.15))
		draw_colored_polygon(PackedVector2Array([Vector2(-15, 2), Vector2(0, 2), Vector2(-6, 30), Vector2(-22, 30)]), tint.darkened(0.14))
		if long_gun:
			draw_colored_polygon(PackedVector2Array([Vector2(-36, -6), Vector2(-82, -9), Vector2(-87, 14), Vector2(-40, 5)]), tint.darkened(0.17))
		if family == "revolver":
			draw_circle(Vector2(10, -3), 11, tint.lightened(0.22))
		elif family == "shotgun":
			draw_rect(Rect2(28, 1, 35, 8), tint.darkened(0.2))
		elif family == "sniper":
			draw_rect(Rect2(-18, -22, 43, 9), tint.lightened(0.16))
			draw_line(Vector2(0, -14), Vector2(0, -9), tint, 4.0)
		elif family == "lmg":
			draw_rect(Rect2(8, 5, 26, 23), tint.darkened(0.12))
		elif family in ["experimental", "special", "launcher"]:
			for coil: int in range(4):
				draw_rect(Rect2(23 + coil * 11, -12, 5, 18), tint.lightened(0.32))
		else:
			draw_rect(Rect2(13, 5, 11, 23 if family == "smg" else 15), tint.darkened(0.17))
		draw_line(Vector2(-31, -4), Vector2(8, -4), Color("e7e2d4"), 1.0, true)


class PerkLinks:
	extends Control
	var columns: int = 4
	var counts: Array[int] = []
	var colors: Array[Color] = []
	var ui_scale: float = 1.0
	var group_height: float = 450.0

	func _draw() -> void:
		for branch: int in range(counts.size()):
			var column: int = branch % columns
			var top: float = float(branch / columns) * group_height
			var center_x: float = size.x * (float(column) + 0.5) / float(columns)
			var count: int = counts[branch]
			var color: Color = colors[branch] if branch < colors.size() else Color("80c9b6")
			if count > 0:
				draw_line(Vector2(center_x, top + 47 * ui_scale), Vector2(center_x, top + (74 + (count - 1) * 114) * ui_scale), Color(color, 0.34), 2.0, true)
			for row: int in range(count):
				draw_circle(Vector2(center_x, top + (68 + row * 114) * ui_scale), 3.0 * ui_scale, color)


func setup(target: Node) -> void:
	game = target
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	name = "ProgressionScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_ui_scale = _read_ui_scale()
	theme = Icons.theme()
	theme.default_font_size = roundi(16 * _ui_scale)
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color(0.035, 0.048, 0.064, 0.98)
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame: MarginContainer = MarginContainer.new()
	add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		frame.add_theme_constant_override("margin_" + side, 30)
	for side: String in ["top", "bottom"]:
		frame.add_theme_constant_override("margin_" + side, 20)
	var layout: VBoxContainer = _vbox(frame, 14)
	var header: HBoxContainer = _hbox(layout, 16)
	var title: VBoxContainer = _vbox(header, 2)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(title, "ENTRE UMA ONDA E OUTRA", 10, GOLD)
	_label(title, "Prepare o próximo passo.", 25)
	_wallet = _label(header, "", 17, GOLD)
	_wallet.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_button(header, "VOLTAR", _close_requested, "close").tooltip_text = "Voltar à expedição."
	var navigation: HBoxContainer = _hbox(layout, 8)
	for id: String in TAB_NAMES:
		var tab_button: Button = _button(navigation, TAB_NAMES[id], _switch_tab.bind(id), TAB_ICONS[id])
		tab_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tab_buttons[id] = tab_button
	_body = MarginContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(_body)
	var footer: HBoxContainer = _hbox(layout, 8)
	_location = _label(footer, "MORRO DO VENTO", 10, MUTED)
	_location.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(footer, "INSPECIONE  ·  COMPARE  ·  EVOLUA", 10, MUTED)
	visible = false
	refresh()


func open(tab: String = "inventory") -> void:
	_close_overlay()
	_loadout_target = int(_inventory().active_weapon_slot)
	_tab = tab if TAB_NAMES.has(tab) else "inventory"
	visible = true
	refresh()


func close() -> void:
	_close_overlay()
	hide()


func apply_settings(values: Dictionary) -> void:
	_ui_scale = clampf(float(values.get("ui_scale", 1.0)), 0.8, 1.3)
	if is_node_ready():
		theme.default_font_size = roundi(16 * _ui_scale)
		_apply_scale_tree(self)
		refresh()


func _read_ui_scale() -> float:
	if not is_instance_valid(game):
		return _ui_scale
	var settings: Object = game.get("settings") as Object
	if is_instance_valid(settings):
		var values: Variant = settings.get("data")
		if values is Dictionary:
			return clampf(float(values.get("ui_scale", 1.0)), 0.8, 1.3)
	return _ui_scale


func refresh() -> void:
	if _refresh_pending:
		return
	_refresh_pending = true
	call_deferred("_refresh_now")


func _refresh_now() -> void:
	_refresh_pending = false
	if not is_node_ready() or not is_instance_valid(_body):
		return
	var requested_scale: float = _read_ui_scale()
	if not is_equal_approx(requested_scale, _ui_scale):
		_ui_scale = requested_scale
		theme.default_font_size = roundi(16 * _ui_scale)
		_apply_scale_tree(self)
	_progress = _progression_data()
	_wallet.text = "%s  PETISCOS     /     %s  SUCATA" % [_number(_progress.get("coins", 0)), _number(_progress.get("materials", 0))]
	_location.text = str(_progress.get("current_region", "MORRO DO VENTO")).to_upper()
	for id: String in _tab_buttons:
		var tab_button: Button = _tab_buttons[id]
		tab_button.add_theme_stylebox_override("normal", Icons.style(Color("28302f") if id == _tab else PANEL, GOLD if id == _tab else Color("28323a")))
		tab_button.add_theme_color_override("font_color", GOLD if id == _tab else MUTED)
	for child: Node in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var inventory: Object = _inventory()
	if is_instance_valid(inventory):
		if _find_item(_selected_uid).is_empty():
			var equipped: Dictionary = _equipped()
			_selected_uid = str(equipped.get("uid", ""))
	match _tab:
		"inventory": _build_inventory()
		"supplies": _build_supplies()
		"forge": _build_forge()
		"perks": _build_perks()
		"dog": _build_dog()
	if not _overlay_kind.is_empty(): _build_overlay()


func _switch_tab(id: String) -> void:
	_close_overlay()
	_tab = id
	refresh()


func _close_requested() -> void:
	_close_overlay()
	hide()
	if is_instance_valid(game) and game.has_method("resume_game"):
		game.call("resume_game")


func _action(method: String, args: Array = []) -> void:
	if is_instance_valid(game) and game.has_method(method):
		game.callv(method, args)
	refresh()


func _inventory() -> Object:
	return game.get("inventory") as Object if is_instance_valid(game) else null


func _progression_data() -> Dictionary:
	if is_instance_valid(game) and game.has_method("get_progression_data"):
		var value: Variant = game.call("get_progression_data")
		if value is Dictionary:
			return value
	return {}


func _find_item(uid: String) -> Dictionary:
	var inventory: Object = _inventory()
	if is_instance_valid(inventory) and inventory.has_method("find_item"):
		var value: Variant = inventory.call("find_item", uid)
		if value is Dictionary:
			return value
	return {}


func _equipped() -> Dictionary:
	var inventory: Object = _inventory()
	if is_instance_valid(inventory) and inventory.has_method("equipped"):
		var value: Variant = inventory.call("equipped")
		if value is Dictionary:
			return value
	return {}


func _stats(item: Dictionary) -> Dictionary:
	if item.is_empty():
		return {}
	var inventory: Object = _inventory()
	if is_instance_valid(inventory) and inventory.has_method("stats"):
		var value: Variant = inventory.call("stats", item)
		if value is Dictionary:
			return value
	return Data.WEAPONS.get(str(item.get("model_id", "")), {}).duplicate(true)


func _items() -> Array:
	var inventory: Object = _inventory()
	if not is_instance_valid(inventory):
		return []
	var result: Variant = inventory.call("sorted_items", _sort) if inventory.has_method("sorted_items") else inventory.get("items")
	return result if result is Array else []


func _build_inventory() -> void:
	var columns := _hbox(_body, 16)
	var character := _vbox(columns, 8)
	character.custom_minimum_size.x = 245
	character.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	character.size_flags_stretch_ratio = 0.65
	_label(character, "MEYUI", 25, MINT)
	_label(character, "EXPLORADOR / ÚLTIMO SINAL", 10, MUTED)
	var preview := Preview.new()
	preview.custom_minimum_size = Vector2(210, 220 if _ui_scale > 1.1 else 260)
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	character.add_child(preview)
	if is_instance_valid(game.get("player")): preview.show_character(game.player.hero)
	var selected := _find_item(_selected_uid)
	var stats := _stats(selected)
	var color := _rarity_color(selected.get("rarity", "common"))
	_label(character, String(stats.get("name", "Selecione uma arma")), 17, color, true)
	_label(character, _rarity_stars(selected.get("rarity", "common")) + " " + String(stats.get("rarity_name", "")), 11, color)
	_compare_bars(character, stats, _stats(_equipped()))
	var details := _button(character, "INSPECIONAR ARMA", _open_item_inspector, "eye")
	_set_font(details, 11)
	var equipment := _vbox(columns, 8)
	equipment.custom_minimum_size.x = 340
	_label(equipment, "LOADOUT  /  SLOT %d" % (_loadout_target + 1), 13, MINT)
	_label(equipment, "Selecione a posição para equipar", 10, MUTED)
	var diamond := preload("res://scripts/loadout_display.gd").new()
	equipment.add_child(diamond)
	diamond.selected = _loadout_target
	diamond.active = int(_inventory().active_weapon_slot)
	diamond.custom_minimum_size.y = 300 if _ui_scale > 1.1 else 354
	for index: int in range(4):
		var item := _find_item(String(_inventory().weapon_slots[index]))
		var evaluated := _stats(item)
		diamond.items.append(item)
		diamond.statistics.append(evaluated)
		var thumb := WeaponThumbnail.new()
		thumb.family = evaluated.get("family", "pistol")
		thumb.tint = _rarity_color(item.get("rarity", "common"))
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		thumb.visible = not item.is_empty()
		diamond.add_child(thumb)
		thumb.request_portrait(item, evaluated)
		diamond.thumbnails.append(thumb)
	diamond.slot_selected.connect(_select_loadout)
	var equip := _button(equipment, "EQUIPAR NO SLOT %d" % (_loadout_target + 1), _action.bind("equip_to_slot", [_selected_uid, _loadout_target]), "arrow", true)
	equip.disabled = selected.is_empty() or _inventory().weapon_slots[_loadout_target] == _selected_uid
	var gear_row := _hbox(equipment, 8)
	for pair: Array in [[Equipment.GRENADES, "grenade_id", "GRANADA", "blast"], [Equipment.MODULES, "module_id", "MODIFICADOR", "chip"]]:
		var config: Dictionary = pair[0][_inventory().get(pair[1])]
		var gear_button := _button(gear_row, pair[2] + "\n" + config.name, _switch_tab.bind("supplies"), pair[3])
		gear_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_set_font(gear_button, 10)
		_set_button_height(gear_button, 60)
	_label(equipment, "1–4  TROCA RÁPIDA   /   SEGURE T  RODA", 10, MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var collection := _vbox(columns, 8)
	collection.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	collection.size_flags_stretch_ratio = 1.25
	var toolbar := _hbox(collection, 5)
	_label(toolbar, "MOCHILA  %d / %d" % [_items().size(), _inventory().capacity], 12, MINT).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var auto_button := _button(toolbar, "AUTO", _action.bind("auto_equip", []), "bolt")
	_set_font(auto_button, 10)
	auto_button.tooltip_text = "Equipar melhor dano sustentado automaticamente"
	var sorts := _hbox(collection, 3)
	for pair: Array in [["rarity","RARIDADE"],["damage","DANO"],["recent","RECENTES"]]:
		var button := _button(sorts, pair[1], _sort_items.bind(pair[0]))
		_set_font(button, 10)
		_set_button_height(button, 30)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll := _scroll(collection)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 7)
	grid.add_theme_constant_override("v_separation", 7)
	scroll.add_child(grid)
	for item: Dictionary in _items(): _item_card(grid, item)
	var actions := _hbox(collection, 5)
	for entry: Array in [["star","Favorito","set_item_flag",[_selected_uid,"favorite"]],["coin","Vender","sell_item",[_selected_uid]],["forge","Reciclar","salvage_item",[_selected_uid]],["close","Largar","discard_item",[_selected_uid]]]:
		var button := _button(actions, "", _action.bind(entry[2], entry[3]), entry[0])
		button.tooltip_text = entry[1]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var dealer := _button(collection, "VISITAR ARMEIRO", _open_dealer, "weapon")
	_set_font(dealer, 11)

func _select_loadout(index: int) -> void:
	_loadout_target = index
	refresh()

func _open_item_inspector() -> void:
	_overlay_kind = "inspect"
	_build_overlay()

func _open_dealer() -> void:
	_overlay_kind = "dealer"
	_build_overlay()

func _close_overlay() -> void:
	_overlay_kind = ""
	if is_instance_valid(_overlay):
		remove_child(_overlay)
		_overlay.queue_free()
	_overlay = null

func _build_overlay() -> void:
	var kind := _overlay_kind
	_close_overlay()
	_overlay_kind = kind
	_overlay = PanelContainer.new()
	add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_theme_stylebox_override("panel", Icons.style(Color("09131c"), Color("396070")))
	var scroll := _scroll(_overlay)
	var content := _vbox(scroll, 12)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(content, "VOLTAR AO ARSENAL", _close_overlay, "close")
	if kind == "inspect":
		_build_item_details(content, _find_item(_selected_uid))
	else:
		_build_stock(content)

func _build_supplies() -> void:
	var inventory: Object = _inventory()
	var scroll := _scroll(_body)
	var layout := _vbox(scroll, 16)
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(layout, "PREPARE A PRÓXIMA HORDA", 24, PAPER)
	_label(layout, "Cargas limitadas · use durante o combate · seus equipamentos ficam salvos", 12, MUTED)
	var supplies_row := _hbox(layout, 12)
	for id: String in Equipment.SUPPLIES:
		var config: Dictionary = Equipment.SUPPLIES[id]
		var color := Color(config.color)
		var card := _panel(supplies_row, color)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var content := _vbox(card, 8)
		var top := _hbox(content, 12)
		_icon(top, config.icon, color, 44)
		_label(top, "%02d / %02d" % [int(inventory.supplies[id]), int(config.max)], 28, color)
		_label(content, config.name, 19)
		_label(content, config.description, 12, MUTED, true)
		var charges := ProgressBar.new()
		charges.max_value = config.max
		charges.value = inventory.supplies[id]
		charges.show_percentage = false
		charges.custom_minimum_size.y = 6
		charges.add_theme_stylebox_override("fill", Icons.style(color, Color.TRANSPARENT, 2))
		content.add_child(charges)
		_label(content, "[ %s ]  USAR EM COMBATE" % config.key, 11, color)
		var buy := _button(content, "+1 CARGA  ·  %d" % config.cost, _action.bind("buy_supply", [id]), "coin", true)
		buy.disabled = int(inventory.supplies[id]) >= int(config.max) or int(_progress.get("coins", 0)) < int(config.cost)
	_label(layout, "UMA GRANADA  /  CONTROLE O ESPAÇO", 12, GOLD)
	_equipment_options(layout, "grenade", Equipment.GRENADES, inventory.grenade_id, inventory.owned_grenades)
	_label(layout, "UM MODIFICADOR  /  ESCOLHA A SUA SINERGIA", 12, GOLD)
	_equipment_options(layout, "module", Equipment.MODULES, inventory.module_id, inventory.owned_modules)
	_label(layout, "DROPS TEMPORÁRIOS  /  ATIVAÇÃO AO RECOLHER", 12, GOLD)
	var powers := _hbox(layout, 8)
	for pair: Array in [["ammo", "Munição livre", "24 s"], ["bolt", "Frenesi", "24 s"], ["target", "Dano duplo", "24 s"], ["shock", "Sobrecarga", "24 s"]]:
		var panel := _panel(powers)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var body := _vbox(panel, 5)
		_icon(body, pair[0], MINT, 26)
		_label(body, pair[1], 13)
		_label(body, pair[2] + " · drop em combate", 10, MUTED)

func _equipment_options(parent: Node, kind: String, definitions: Dictionary, active: String, owned: Array) -> void:
	var row := _hbox(parent, 10)
	for id: String in definitions:
		var config: Dictionary = definitions[id]
		var color := Color(config.color)
		var panel := _panel(row, color if id == active else Color("344653"))
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var content := _vbox(panel, 7)
		_icon(content, config.icon, color, 30)
		_label(content, config.name, 16, color, true)
		_label(content, config.description, 12, MUTED, true)
		if kind == "grenade": _label(content, "%.0f DANO  /  %.1f m" % [config.damage, config.radius], 11, PAPER)
		var button := _button(content, "EQUIPADO" if active == id else ("EQUIPAR" if owned.has(id) else "%d PETISCOS" % config.cost), _action.bind("buy_equipment", [kind, id]), "check" if active == id else "arrow")
		_set_font(button, 11)
		button.disabled = active == id or (not owned.has(id) and int(_progress.get("coins", 0)) < int(config.cost))


func _toggle_stock() -> void:
	_show_stock = not _show_stock
	refresh()


func _sort_items(id: String) -> void:
	_sort = id
	refresh()


func _select_item(uid: String) -> void:
	_selected_uid = uid
	refresh()


func _item_card(parent: Node, item: Dictionary) -> void:
	var stats: Dictionary = _stats(item)
	var uid: String = str(item.get("uid", ""))
	var color: Color = _rarity_color(str(item.get("rarity", "common")))
	var card: Button = _button(parent, "", _select_item.bind(uid))
	card.custom_minimum_size.x = 210
	_set_button_height(card, 130)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("normal", Icons.style(Color("20302f") if uid == _selected_uid else PANEL, color if uid == _selected_uid else Color(color, 0.32)))
	card.tooltip_text = "%s\n%s\nDano %.1f · DPS %.1f\nClique para comparar e equipar." % [stats.get("name", "Arma"), _rarity_name(str(item.get("rarity", "common"))), float(stats.get("damage", 0)), _dps(stats)]
	var content: VBoxContainer = VBoxContainer.new()
	card.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 12
	content.offset_right = -12
	content.offset_top = 10
	content.offset_bottom = -8
	content.add_theme_constant_override("separation", 3)
	_ignore_mouse(content)
	var top: HBoxContainer = _hbox(content, 4)
	var name_label: Label = _label(top, str(stats.get("name", "Equipamento")), 14, PAPER)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var equipped: bool = uid == str(_equipped().get("uid", ""))
	if equipped or bool(item.get("favorite", false)):
		_icon(top, "check" if equipped else "star", color, 14)
	var thumbnail: WeaponThumbnail = WeaponThumbnail.new()
	thumbnail.family = str(stats.get("family", "pistol"))
	thumbnail.tint = color
	thumbnail.custom_minimum_size.y = 47 * _ui_scale
	thumbnail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(thumbnail)
	thumbnail.request_portrait(item, stats)
	_label(content, "%s  ·  NÍVEL %d%s" % [_rarity_stars(str(item.get("rarity", "common"))), int(item.get("level", 1)), "  ·  SUCATA" if bool(item.get("junk", false)) else ""], 10, color)
	_label(content, "%.1f dano     %.0f DPS" % [float(stats.get("damage", 0)), _dps(stats)], 11, MUTED)
	_ignore_mouse(content)


func _build_item_details(parent: Node, item: Dictionary) -> void:
	var stats: Dictionary = _stats(item)
	var rarity: String = str(item.get("rarity", "common"))
	var color: Color = _rarity_color(rarity)
	_label(parent, "%s  %s  /  NV. %d" % [_rarity_stars(rarity), _rarity_name(rarity).to_upper(), int(item.get("level", 1))], 11, color)
	_label(parent, str(stats.get("name", "Equipamento")), 25)
	_label(parent, str(stats.get("manufacturer_name", item.get("manufacturer", "Independente"))), 12, MUTED)
	var thumbnail: WeaponThumbnail = WeaponThumbnail.new()
	thumbnail.family = str(stats.get("family", "pistol"))
	thumbnail.tint = color
	thumbnail.custom_minimum_size.y = 64
	parent.add_child(thumbnail)
	thumbnail.request_portrait(item, stats)
	var equipped_stats: Dictionary = _stats(_equipped())
	_label(parent, "COMPARAR COM A ARMA EQUIPADA", 10, MUTED)
	_compare_bars(parent, stats, equipped_stats)
	var uid: String = str(item.get("uid", ""))
	var controls: HBoxContainer = _hbox(parent, 7)
	var is_equipped: bool = uid == str(_equipped().get("uid", ""))
	var equip: Button = _button(controls, "EQUIPADA" if is_equipped else "EQUIPAR", _action.bind("equip_item", [uid]), "check" if is_equipped else "weapon", true)
	equip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	equip.disabled = is_equipped
	_button(controls, "BANCADA", _switch_tab.bind("forge"), "forge").size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var quick: HBoxContainer = _hbox(parent, 5)
	var favorite: Button = _button(quick, "", _action.bind("set_item_flag", [uid, "favorite"]), "star")
	favorite.tooltip_text = "Remover dos favoritos" if bool(item.get("favorite", false)) else "Marcar como favorita"
	var junk: Button = _button(quick, "", _action.bind("set_item_flag", [uid, "junk"]), "chip")
	junk.tooltip_text = "Desmarcar sucata" if bool(item.get("junk", false)) else "Marcar como sucata"
	_button(quick, "Vender %s" % _number(stats.get("value", 0)), _action.bind("sell_item", [uid]), "coin").size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(quick, "Reciclar", _action.bind("salvage_item", [uid]), "forge").tooltip_text = "Transformar esta arma em materiais para a bancada."
	var lower: HBoxContainer = _hbox(parent, 6)
	_button(lower, "Menos detalhes" if _show_details else "Mais detalhes", _toggle_details, "eye").size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var discard: Button = _button(lower, "Descartar", _action.bind("discard_item", [uid]), "close")
	discard.add_theme_color_override("font_color", CORAL)
	discard.tooltip_text = "Remover este equipamento da mochila. Favoritos são protegidos."
	if _show_details:
		_label(parent, "Pente %d  /  reserva %d   ·   recarga %.2fs\nAlcance %.0fm   ·   crítico %.0f%% × %.2f" % [int(stats.get("magazine_size", 0)), int(stats.get("max_reserve", 0)), float(stats.get("reload_time", 0)), float(stats.get("range", 0)), float(stats.get("critical_chance", 0.05)) * 100, float(stats.get("critical_multiplier", 1.75))], 12, MUTED)
		var traits: Array = stats.get("modifiers", []) if stats.get("modifiers", []) is Array else []
		for modifier: Variant in traits:
			var definition: Dictionary = Loot.MODIFIERS.get(str(modifier), {})
			_label(parent, "• " + str(definition.get("name", modifier)), 12, color)
	if is_equipped and is_instance_valid(game) and game.has_method("refill_ammo") and game.has_method("get_shop_data"):
		var shop_data: Dictionary = game.call("get_shop_data")
		var refill_cost: int = int(shop_data.get("ammo_cost", 0))
		var refill: Button = _button(parent, "REABASTECER  ·  %s" % _number(refill_cost), _action.bind("refill_ammo", []), "weapon")
		refill.disabled = refill_cost > int(_progress.get("coins", 0))
		refill.tooltip_text = "Completa o carregador e a reserva da arma equipada."


func _toggle_details() -> void:
	_show_details = not _show_details
	refresh()


func _compare_bars(parent: Node, selected: Dictionary, equipped: Dictionary) -> void:
	var rows: Array = [["DANO", float(selected.get("damage", 0)), float(equipped.get("damage", 0)), 130.0], ["CADÊNCIA", float(selected.get("fire_rate", 0)), float(equipped.get("fire_rate", 0)), 14.0], ["DPS", _dps(selected), _dps(equipped), 360.0], ["PENTE", float(selected.get("magazine_size", 0)), float(equipped.get("magazine_size", 0)), 80.0]]
	for row: Array in rows:
		var line: HBoxContainer = _hbox(parent, 9)
		var title: Label = _label(line, str(row[0]), 10, MUTED)
		title.custom_minimum_size.x = 64 * _ui_scale
		var bar: ProgressBar = ProgressBar.new()
		bar.custom_minimum_size = Vector2(60, 7)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.max_value = maxf(float(row[3]), maxf(float(row[1]), float(row[2])))
		bar.value = float(row[1])
		bar.show_percentage = false
		bar.add_theme_stylebox_override("background", Icons.style(Color("29323a"), Color.TRANSPARENT, 0))
		bar.add_theme_stylebox_override("fill", Icons.style(MINT, Color.TRANSPARENT, 0))
		line.add_child(bar)
		var difference: float = float(row[1]) - float(row[2])
		var detail: String = "%.1f" % float(row[1])
		if absf(difference) > 0.05:
			detail += "  %s%.1f" % ["+" if difference > 0 else "", difference]
		var value: Label = _label(line, detail, 12, MINT if difference > 0.05 else (CORAL if difference < -0.05 else PAPER))
		value.custom_minimum_size.x = 88 * _ui_scale
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _build_stock(parent: Node) -> void:
	_label(parent, "ARMEIRO  /  MODELOS DE FÁBRICA", 11, GOLD)
	var scroll: ScrollContainer = _scroll(parent)
	var list: VBoxContainer = _vbox(scroll, 7)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var entries: Array = _progress.get("stock_weapons", []) if _progress.get("stock_weapons", []) is Array else []
	for value: Variant in entries:
		if not value is Dictionary:
			continue
		var weapon: Dictionary = value
		var panel: PanelContainer = _panel(list)
		var row: HBoxContainer = _hbox(panel, 10)
		var copy: VBoxContainer = _vbox(row, 3)
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_label(copy, str(weapon.get("name", "Equipamento")), 15)
		_label(copy, "%.0f dano  ·  %.1f/s  ·  rodada %d" % [float(weapon.get("damage", 0)), float(weapon.get("fire_rate", 0)), int(weapon.get("unlock_round", 1))], 11, MUTED)
		var cost: int = int(weapon.get("price", 0))
		var button: Button = _button(row, _number(cost), _action.bind("buy_weapon", [str(weapon.get("id", weapon.get("model_id", "")))]), "lock" if bool(weapon.get("locked", false)) else "coin")
		button.disabled = bool(weapon.get("locked", false)) or cost > int(_progress.get("coins", 0))
	if entries.is_empty():
		_empty(list, "O Armeiro está preparando o estoque.", "Continue a expedição para encontrar novas armas.", "weapon")


func _build_forge() -> void:
	var scroll: ScrollContainer = _scroll(_body)
	var layout: VBoxContainer = _vbox(scroll, 12)
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var selected: Dictionary = _find_item(_selected_uid)
	if selected.is_empty():
		_empty(layout, "Cada peça conta.", "Selecione uma arma no inventário para instalar acessórios e aprimorá-la.", "forge")
		_button(layout, "ABRIR INVENTÁRIO", _switch_tab.bind("inventory"), "bag")
		return
	var stats: Dictionary = _stats(selected)
	var toolbar: HBoxContainer = _hbox(layout, 10)
	_label(toolbar, "BANCADA DE PERSONALIZAÇÃO", 11, GOLD).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var selector: OptionButton = OptionButton.new()
	selector.custom_minimum_size = Vector2(260, 36 * _ui_scale)
	_set_font(selector, 14)
	var index: int = 0
	for value: Variant in _items():
		if not value is Dictionary:
			continue
		var item: Dictionary = value
		selector.add_item(str(_stats(item).get("name", "Arma")) + "  · Nv. " + str(item.get("level", 1)))
		selector.set_item_metadata(index, str(item.get("uid", "")))
		if str(item.get("uid", "")) == _selected_uid:
			selector.select(index)
		index += 1
	selector.item_selected.connect(func(chosen: int) -> void: _select_item(str(selector.get_item_metadata(chosen))))
	toolbar.add_child(selector)
	var top: HBoxContainer = _hbox(layout, 14)
	var stage_panel: PanelContainer = _panel(top)
	stage_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_panel.size_flags_stretch_ratio = 1.8
	var stage_layout: VBoxContainer = _vbox(stage_panel, 8)
	_label(stage_layout, str(stats.get("name", "Equipamento")), 22)
	_label(stage_layout, "SELECIONE UMA PEÇA  /  ARRASTE PARA GIRAR", 10, MUTED)
	var stage_row: HBoxContainer = _hbox(stage_layout, 5)
	var left: VBoxContainer = _vbox(stage_row, 12)
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var preview: Preview = Preview.new()
	preview.custom_minimum_size = Vector2(180, 270)
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_row.add_child(preview)
	var right: VBoxContainer = _vbox(stage_row, 12)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var installed: Dictionary = selected.get("attachments", {}) if selected.get("attachments", {}) is Dictionary else {}
	var slot_index: int = 0
	for slot: String in SLOT_NAMES:
		var slot_parent: Node = left if slot_index < 3 else right
		var attachment: Dictionary = installed.get(slot, {}) if installed.get(slot, {}) is Dictionary else {}
		var attachment_name: String = str(Loot.ATTACHMENTS.get(str(attachment.get("id", "")), {}).get("name", "Espaço livre"))
		var slot_button: Button = _button(slot_parent, str(SLOT_NAMES[slot]) + "\n" + attachment_name, _select_slot.bind(slot), "aim" if slot == "sight" else "chip")
		slot_button.custom_minimum_size.x = 143
		_set_button_height(slot_button, 54)
		_set_font(slot_button, 10)
		slot_button.add_theme_stylebox_override("normal", Icons.style(Color("233331") if slot == _selected_slot else Color("10181f"), MINT if slot == _selected_slot else Color("34434a")))
		slot_button.tooltip_text = "Escolher acessórios de " + str(SLOT_NAMES[slot]).to_lower()
		slot_index += 1
	preview.show_weapon(selected, stats)
	var weapon_metrics := _hbox(stage_layout, 16)
	for pair: Array in [["DPS", "%.0f" % _dps(stats), "target"], ["RPM", "%.0f" % (float(stats.fire_rate) * 60), "bolt"], ["RECARGA", "%.2f s" % float(stats.reload_time), "restart"]]:
		var metric := _vbox(weapon_metrics, 4)
		metric.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_icon(metric, pair[2], MINT, 22)
		_label(metric, pair[1], 23, PAPER)
		_label(metric, pair[0], 10, MUTED)
	var upgrade_panel: PanelContainer = _panel(top)
	upgrade_panel.custom_minimum_size.x = 300
	var upgrade: VBoxContainer = _vbox(upgrade_panel, 9)
	_label(upgrade, "REFINAR A SUA FAVORITA", 11, GOLD)
	var next_item: Dictionary = selected.duplicate(true)
	var level: int = int(selected.get("upgrade_level", 0))
	next_item["upgrade_level"] = level + 1
	var next_stats: Dictionary = _stats(next_item)
	_label(upgrade, "MELHORIA %02d  →  %02d" % [level, level + 1], 20)
	_label(upgrade, "Dano  %.1f  →  %.1f" % [float(stats.get("damage", 0)), float(next_stats.get("damage", 0))], 16, MINT)
	_compare_bars(upgrade, next_stats, stats)
	_label(upgrade, "Peças, elemento e munição preservados. Refinamento sem nível máximo.", 11, MUTED, true)
	var base_cost: int = Data.upgrade_cost(level)
	var materials_used: int = mini(int(_progress.get("materials", 0)), floori(base_cost / 4.0))
	var cost: int = base_cost - materials_used
	var improve: Button = _button(upgrade, "APRIMORAR  ·  %s" % _number(cost), _action.bind("upgrade_weapon", [_selected_uid]), "forge", true)
	improve.disabled = cost > int(_progress.get("coins", 0))
	if materials_used > 0:
		_label(upgrade, "+ %d sucata aplicada ao refinamento" % materials_used, 10, MUTED)
	_label(upgrade, "RECOMBINAR", 10, MUTED)
	_reroll_button(upgrade, "Novos traços", "modifiers")
	_reroll_button(upgrade, "Novo fabricante", "manufacturer")
	_label(upgrade, "As peças instaladas aparecem na prévia 3D.", 11, MUTED, true)
	_build_attachments(layout, selected)


func _select_slot(slot: String) -> void:
	_selected_slot = slot
	refresh()


func _reroll_button(parent: Node, title: String, kind: String) -> void:
	var inventory: Object = _inventory()
	var price: int = -1
	if is_instance_valid(inventory) and inventory.has_method("reroll_cost"):
		price = int(inventory.call("reroll_cost", _selected_uid, kind))
	var button: Button = _button(parent, title + ("  ·  %s" % _number(price) if price >= 0 else ""), _action.bind("reroll_weapon", [_selected_uid, kind]), "restart")
	button.tooltip_text = "Gera uma nova combinação para esta arma; o resultado pode melhorar ou alterar seus atributos."
	if price >= 0:
		button.disabled = price > int(_progress.get("coins", 0))


func _build_attachments(parent: Node, selected: Dictionary) -> void:
	var title: HBoxContainer = _hbox(parent, 9)
	_label(title, "ACESSÓRIOS  /  " + str(SLOT_NAMES.get(_selected_slot, _selected_slot)), 11, GOLD).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var installed: Dictionary = selected.get("attachments", {}) if selected.get("attachments", {}) is Dictionary else {}
	if installed.has(_selected_slot):
		_button(title, "REMOVER PEÇA", _action.bind("uninstall_attachment", [_selected_uid, _selected_slot]), "close")
	var options_scroll: ScrollContainer = ScrollContainer.new()
	options_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	options_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	options_scroll.custom_minimum_size.y = 158 * _ui_scale
	_style_scrollbars(options_scroll)
	parent.add_child(options_scroll)
	var options: HBoxContainer = _hbox(options_scroll, 9)
	var inventory: Object = _inventory()
	var attachments: Array = inventory.get("attachments") if is_instance_valid(inventory) and inventory.get("attachments") is Array else []
	var found: int = 0
	for value: Variant in attachments:
		if not value is Dictionary:
			continue
		var attachment: Dictionary = value
		if str(attachment.get("slot", "")) != _selected_slot:
			continue
		var config: Dictionary = Loot.ATTACHMENTS.get(str(attachment.get("id", "")), {})
		_attachment_card(options, config, attachment, false)
		found += 1
	var stock: Array = _progress.get("stock_attachments", []) if _progress.get("stock_attachments", []) is Array else []
	for value: Variant in stock:
		if not value is Dictionary:
			continue
		var config: Dictionary = value
		if str(config.get("slot", "")) != _selected_slot:
			continue
		_attachment_card(options, config, {}, true)
		found += 1
	if found == 0:
		_label(options, "Nenhuma peça para este encaixe. Encontre acessórios durante a expedição.", 13, MUTED, true)


func _attachment_card(parent: Node, config: Dictionary, instance: Dictionary, stock: bool) -> void:
	var rarity := String(instance.get("rarity", "common"))
	var tint := _rarity_color(rarity)
	var panel: PanelContainer = _panel(parent, tint)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size.x = 175
	var content: VBoxContainer = _vbox(panel, 5)
	_icon(content, "aim" if _selected_slot == "sight" else "ammo" if _selected_slot == "magazine" else "chip", tint, 30)
	_label(content, str(config.get("name", "Acessório")), 13)
	_label(content, "ARMEIRO" if stock else _rarity_stars(rarity) + " " + _rarity_name(rarity), 9, tint)
	var effect: String = _attachment_effects(config)
	_label(content, effect, 10, MINT, true)
	if not stock:
		var before := _stats(_find_item(_selected_uid))
		var changed := _find_item(_selected_uid).duplicate(true)
		changed.attachments[_selected_slot] = instance
		var after := _stats(changed)
		var difference := _dps(after) - _dps(before)
		_label(content, "DPS %s %.1f" % ["↑" if difference > 0 else "↓" if difference < 0 else "=", absf(difference)], 12, MINT if difference >= 0 else CORAL)
		_label(content, "Recarga %.2f → %.2f s" % [float(before.reload_time), float(after.reload_time)], 10, MUTED)
	if stock:
		var cost: int = int(config.get("price", config.get("cost", 0)))
		var purchase: Button = _button(content, _number(cost), _action.bind("buy_attachment", [str(config.get("id", ""))]), "coin")
		purchase.disabled = cost > int(_progress.get("coins", 0))
	else:
		_button(content, "INSTALAR", _action.bind("install_attachment", [_selected_uid, str(instance.get("uid", ""))]), "chip")


func _attachment_effects(config: Dictionary) -> String:
	var lines: PackedStringArray = []
	for pair: Array in [["damage", "Dano"], ["fire_rate", "Cadência"], ["reload_time", "Recarga"], ["magazine_size", "Pente"], ["spread", "Dispersão"], ["recoil", "Recuo"], ["range", "Alcance"]]:
		if config.has(str(pair[0])):
			var change: float = (float(config[str(pair[0])]) - 1.0) * 100.0
			lines.append("%s %s%.0f%%" % [pair[1], "+" if change > 0 else "", change])
	if config.has("element"):
		lines.append({"fire":"Incendiário", "shock":"Elétrico", "cryo":"Congelante", "corrosive":"Corrosivo", "explosive":"Explosivo"}.get(str(config.element), str(config.element)))
	if lines.is_empty():
		lines.append("Ajuste especializado")
	return "\n".join(lines)


func _build_perks() -> void:
	var layout: VBoxContainer = _vbox(_body, 9)
	_label(layout, "TALENTOS  /  CONSTRUA O SEU JEITO DE JOGAR", 12, GOLD)
	_label(layout, "Escolha um nó. Veja o ganho. Invista na sua combinação.", 12, MUTED)
	var perks: Array = _progress.get("perks", []) if _progress.get("perks", []) is Array else []
	if perks.is_empty():
		_empty(layout, "Seu caminho começa aqui.", "Os talentos estarão disponíveis ao iniciar uma expedição.", "chip")
		return
	var selected: Dictionary = perks[0]
	for perk: Dictionary in perks:
		if perk.id == _selected_perk: selected = perk
	var inspect := _panel(layout, GOLD)
	var inspect_row := _hbox(inspect, 18)
	_icon(inspect_row, _perk_icon(selected.get("icon", "chip"), selected.get("branch", "power")), GOLD, 48)
	var perk_title := _vbox(inspect_row, 4)
	perk_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(perk_title, String(selected.name).to_upper(), 22)
	_label(perk_title, "%s · nível %d → %d" % [_branch_name(selected.branch), int(selected.level), int(selected.level) + 1], 12, MUTED)
	_label(perk_title, "Sem limite de níveis · ganhos graduais e custo crescente", 10, MUTED)
	var upgrade := _vbox(inspect_row, 4)
	_label(upgrade, "%s   →   %s" % [selected.value, selected.next_value], 23, MINT)
	var purchase := _button(upgrade, "INVESTIR  ·  %s" % _number(selected.cost), _action.bind("buy_perk", [selected.id]), "coin", true)
	purchase.disabled = int(selected.cost) > int(_progress.get("coins", 0))
	var branches: Dictionary = {}
	for value: Variant in perks:
		if value is Dictionary:
			var perk: Dictionary = value
			var branch: String = str(perk.get("branch", "utility"))
			if not branches.has(branch):
				branches[branch] = []
			branches[branch].append(perk)
	var scroll: ScrollContainer = _scroll(layout)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	var graph: PerkLinks = PerkLinks.new()
	graph.columns = mini(3, branches.size()) if _ui_scale > 1.12 else branches.size()
	graph.ui_scale = _ui_scale
	var max_nodes: int = 0
	for branch: String in branches:
		max_nodes = maxi(max_nodes, branches[branch].size())
	graph.group_height = (88 + max_nodes * 114) * _ui_scale
	graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph.custom_minimum_size.x = graph.columns * 200 * _ui_scale
	graph.custom_minimum_size.y = maxf(400, ceili(float(branches.size()) / graph.columns) * graph.group_height)
	scroll.add_child(graph)
	var colors: Array[Color] = [GOLD, MINT, Color("92afd0"), Color("b79acb"), CORAL]
	var column: int = 0
	for branch: String in branches:
		var entries: Array = branches[branch]
		var color: Color = colors[column % colors.size()]
		graph.counts.append(entries.size())
		graph.colors.append(color)
		var group_top: float = float(column / graph.columns) * graph.group_height
		var heading: Label = _label(graph, _branch_name(branch), 13, color)
		_set_column(heading, column % graph.columns, graph.columns, 8, group_top + 4 * _ui_scale, 38 * _ui_scale)
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		for row: int in range(entries.size()):
			var perk: Dictionary = entries[row]
			var level: int = int(perk.get("level", 0))
			var cost: int = int(perk.get("cost", 0))
			var node: Button = _button(graph, "", _select_perk.bind(str(perk.get("id", ""))))
			_set_column(node, column % graph.columns, graph.columns, 10, group_top + (76 + row * 114) * _ui_scale, 94 * _ui_scale)
			node.add_theme_stylebox_override("normal", Icons.style(Color(color, 0.18 if perk.id == _selected_perk else 0.08), Color(color, 1.0 if perk.id == _selected_perk else 0.6 if level > 0 else 0.22)))
			node.disabled = bool(perk.get("locked", false))
			node.tooltip_text = str(perk.get("description", perk.get("name", "Talento"))) + "\nAtual: " + str(perk.get("value", "—")) + "  →  Próximo: " + str(perk.get("next_value", "—"))
			var content: VBoxContainer = VBoxContainer.new()
			node.add_child(content)
			content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			content.offset_left = 12
			content.offset_right = -12
			content.offset_top = 10
			content.offset_bottom = -8
			content.add_theme_constant_override("separation", 4)
			var title: HBoxContainer = _hbox(content, 7)
			_icon(title, _perk_icon(str(perk.get("icon", "chip")), branch), color, 19)
			_label(title, str(perk.get("name", "Talento")), 13)
			_label(content, _level_pips(level) + "  NÍVEL %d" % level, 10, color)
			_label(content, "%s  →  %s     /     %s" % [_short_value(perk.get("value", 0)), _short_value(perk.get("next_value", 0)), _number(cost)], 10, MUTED)
			_ignore_mouse(content)
		column += 1
	graph.resized.connect(graph.queue_redraw)

func _select_perk(id: String) -> void:
	_selected_perk = id
	refresh()


func _build_dog() -> void:
	var scroll: ScrollContainer = _scroll(_body)
	var layout: VBoxContainer = _vbox(scroll, 12)
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var dog: Dictionary = _progress.get("dog", {}) if _progress.get("dog", {}) is Dictionary else {}
	_label(layout, "COMPANHEIRO  /  NUNCA EXPLORE SOZINHO", 12, GOLD)
	var stages: HBoxContainer = _hbox(layout, 16)
	var left: VBoxContainer = _vbox(stages, 13)
	left.custom_minimum_size.x = 230
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var center: PanelContainer = _panel(stages)
	center.custom_minimum_size.x = 330
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_stretch_ratio = 1.5
	var model_layout: VBoxContainer = _vbox(center, 4)
	_label(model_layout, str(dog.get("name", "Faro")), 26).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(model_layout, "SEU PARCEIRO DE EXPEDIÇÃO", 10, MINT).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var preview: Preview = Preview.new()
	preview.custom_minimum_size.y = 240
	model_layout.add_child(preview)
	preview.show_dog(dog)
	_label(model_layout, "Arraste para girar", 10, MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var right: VBoxContainer = _vbox(stages, 13)
	right.custom_minimum_size.x = 230
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dog_branch(left, dog, "attack", "ATAQUE", "weapon", GOLD)
	_dog_branch(left, dog, "survival", "SOBREVIVÊNCIA", "shield", Color("92afd0"))
	_dog_branch(left, dog, "elemental", "AFINIDADE", "shock", Color("c6a6ed"))
	_dog_branch(left, dog, "control", "CAÇADOR", "target", GOLD)
	_dog_branch(right, dog, "loot", "COLETA", "bag", MINT)
	_dog_branch(right, dog, "support", "SUPORTE", "heart", Color("b79acb"))
	_dog_branch(right, dog, "resupply", "INTENDENTE", "ammo", GOLD)
	_dog_branch(right, dog, "bond", "VÍNCULO VITAL", "heart", CORAL)
	_label(model_layout, "MORDIDA ELEMENTAL", 12, GOLD).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for pair: Array in [["fire", "BRASA", "Dano contínuo", "fire"], ["shock", "VOLTAGEM", "Interrompe ataques", "shock"], ["cryo", "GEADA", "Desacelera a perseguição", "cryo"]]:
		var selected_element: bool = String(dog.get("element", "shock")) == pair[0]
		var option := _button(model_layout, ("● " if selected_element else "") + pair[1] + "\n" + pair[2], _action.bind("choose_dog_element", [pair[0]]), pair[3])
		_set_font(option, 12)
		_set_button_height(option, 58)
		option.disabled = int(dog.get("levels", {}).get("elemental", 0)) == 0 or selected_element
	_label(model_layout, "Afinidade Nv. 1 libera as três opções. Troque livremente entre rounds.", 11, MUTED, true)
	_label(layout, "ESCOLHA A ESPECIALIDADE", 11, MUTED)
	var archetypes_row: HBoxContainer = _hbox(layout, 9)
	var archetypes: Array = dog.get("archetypes", []) if dog.get("archetypes", []) is Array else []
	if archetypes.is_empty():
		archetypes = [{"id":"combat", "name":"Combatente", "unlocked":true}, {"id":"collector", "name":"Coletor", "unlocked":false}, {"id":"support", "name":"Apoio", "unlocked":false}, {"id":"guardian", "name":"Guardião", "unlocked":false}]
	var active: String = str(dog.get("archetype", dog.get("selected", "combat")))
	for value: Variant in archetypes:
		if not value is Dictionary:
			continue
		var archetype: Dictionary = value
		var id: String = str(archetype.get("id", "combat"))
		var unlocked: bool = bool(archetype.get("unlocked", false))
		var cost: int = int(archetype.get("cost", archetype.get("unlock_cost", 0)))
		var title: String = str(archetype.get("name", id.capitalize()))
		var status: String = "ATIVO" if id == active else ("SELECIONAR" if unlocked else "DESBLOQUEAR  ·  " + _number(cost))
		var button: Button = _button(archetypes_row, title + "\n" + status, _action.bind("select_dog", [id]), "paw" if unlocked else "lock")
		_set_button_height(button, 64)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_set_font(button, 12)
		button.tooltip_text = str(archetype.get("description", title))
		button.disabled = id == active or (not unlocked and cost > int(_progress.get("coins", 0)))
		if id == active:
			button.add_theme_stylebox_override("disabled", Icons.style(Color("22352f"), MINT))
			button.add_theme_color_override("font_disabled_color", MINT)


func _dog_branch(parent: Node, dog: Dictionary, id: String, title: String, icon: String, color: Color) -> void:
	var branch: Dictionary = {}
	var definitions: Variant = dog.get("branches", {})
	if definitions is Dictionary:
		var entry: Variant = definitions.get(id, {})
		branch = entry if entry is Dictionary else {"level": int(entry)}
	elif definitions is Array:
		for value: Variant in definitions:
			if value is Dictionary and str(value.get("id", "")) == id:
				branch = value
	var panel: PanelContainer = _panel(parent, color)
	var content: VBoxContainer = _vbox(panel, 7)
	var header: HBoxContainer = _hbox(content, 8)
	_icon(header, icon, color, 21)
	_label(header, title, 12, color)
	var level: int = int(branch.get("level", 0))
	_label(content, _level_pips(level) + "  NV. %d" % level, 10, MUTED)
	_label(content, str(branch.get("description", "")), 11, MUTED, true)
	_label(content, "%s  →  %s" % [_short_value(branch.get("value", "—")), _short_value(branch.get("next_value", "—"))], 15, PAPER)
	var cost: int = int(branch.get("cost", 0))
	var button: Button = _button(content, "EVOLUIR  ·  " + _number(cost), _action.bind("upgrade_dog", [id]), "arrow")
	button.disabled = branch.is_empty() or cost > int(_progress.get("coins", 0)) or bool(branch.get("maxed", false))
	button.tooltip_text = str(branch.get("description", "Fortalece " + title.to_lower() + " do companheiro."))


func _panel(parent: Node, border: Color = Color("29363c")) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Icons.style(PANEL, Color(border, 0.52)))
	parent.add_child(panel)
	return panel


func _vbox(parent: Node, separation: int = 8) -> VBoxContainer:
	var container: VBoxContainer = VBoxContainer.new()
	container.add_theme_constant_override("separation", separation)
	parent.add_child(container)
	return container


func _hbox(parent: Node, separation: int = 8) -> HBoxContainer:
	var container: HBoxContainer = HBoxContainer.new()
	container.add_theme_constant_override("separation", separation)
	parent.add_child(container)
	return container


func _scroll(parent: Node) -> ScrollContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_style_scrollbars(scroll)
	parent.add_child(scroll)
	return scroll


func _style_scrollbars(scroll: ScrollContainer) -> void:
	for bar: ScrollBar in [scroll.get_h_scroll_bar(), scroll.get_v_scroll_bar()]:
		var horizontal: bool = bar is HScrollBar
		var track: StyleBoxFlat = StyleBoxFlat.new()
		track.bg_color = Color("111b22")
		track.content_margin_left = 0 if horizontal else 3
		track.content_margin_right = 0 if horizontal else 3
		track.content_margin_top = 3 if horizontal else 0
		track.content_margin_bottom = 3 if horizontal else 0
		bar.add_theme_stylebox_override("scroll", track)
		for state: String in ["grabber", "grabber_highlight", "grabber_pressed"]:
			var grip: StyleBoxFlat = track.duplicate() as StyleBoxFlat
			grip.bg_color = Color("4e6868") if state == "grabber" else MINT
			grip.set_corner_radius_all(3)
			bar.add_theme_stylebox_override(state, grip)


func _set_font(control: Control, base_size: int) -> void:
	control.set_meta("base_font_size", base_size)
	control.add_theme_font_size_override("font_size", roundi(base_size * _ui_scale))


func _set_button_height(button: Button, base_height: float) -> void:
	button.set_meta("progression_base_height", base_height)
	button.custom_minimum_size.y = base_height * _ui_scale


func _apply_scale_tree(node: Node) -> void:
	if node is Control:
		var control: Control = node as Control
		if control.has_meta("base_font_size"):
			control.add_theme_font_size_override("font_size", roundi(int(control.get_meta("base_font_size")) * _ui_scale))
		if control.has_meta("progression_base_height"):
			control.custom_minimum_size.y = float(control.get_meta("progression_base_height")) * _ui_scale
		if control.has_meta("progression_icon"):
			var icon_data: Dictionary = control.get_meta("progression_icon")
			var pixels: int = roundi(int(icon_data.dimension) * _ui_scale)
			if control is Button:
				(control as Button).icon = Icons.texture(str(icon_data.id), icon_data.color, pixels)
			elif control is TextureRect:
				(control as TextureRect).texture = Icons.texture(str(icon_data.id), icon_data.color, pixels)
				control.custom_minimum_size = Vector2(pixels, pixels)
	for child: Node in node.get_children():
		_apply_scale_tree(child)


func _label(parent: Node, text: String, font_size: int = 14, color: Color = PAPER, wrap: bool = false) -> Label:
	var label: Label = Label.new()
	label.text = text
	_set_font(label, font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, action: Callable, icon: String = "", primary: bool = false) -> Button:
	var button: Button = Button.new()
	button.text = text
	_set_button_height(button, 37)
	_set_font(button, 12)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal", Icons.style(GOLD if primary else Color("1b252d"), GOLD if primary else Color("334047")))
	button.add_theme_stylebox_override("hover", Icons.style(Color("ead2a6") if primary else Color("2c3a40"), GOLD))
	button.add_theme_stylebox_override("pressed", Icons.style(Color("394b48"), MINT))
	button.add_theme_color_override("font_color", INK if primary else PAPER)
	button.add_theme_color_override("font_hover_color", INK if primary else PAPER)
	if not icon.is_empty():
		button.set_meta("progression_icon", {"id": icon, "color": INK if primary else GOLD, "dimension": 16})
		button.icon = Icons.texture(icon, INK if primary else GOLD, roundi(16 * _ui_scale))
	button.pressed.connect(func() -> void:
		if is_instance_valid(game) and game.has_method("ui_feedback"):
			game.call("ui_feedback", "ui_click")
	)
	button.pressed.connect(action)
	button.mouse_entered.connect(func() -> void:
		if button.disabled:
			return
		if is_instance_valid(game) and game.has_method("ui_feedback"):
			game.call("ui_feedback", "ui_hover")
		var tween: Tween = button.create_tween()
		tween.tween_property(button, "self_modulate", Color(1.10, 1.10, 1.10), 0.09)
	)
	button.mouse_exited.connect(func() -> void:
		var tween: Tween = button.create_tween()
		tween.tween_property(button, "self_modulate", Color.WHITE, 0.13)
	)
	parent.add_child(button)
	return button


func _icon(parent: Node, id: String, color: Color = GOLD, dimension: int = 24) -> TextureRect:
	var texture: TextureRect = TextureRect.new()
	var pixels: int = roundi(dimension * _ui_scale)
	texture.set_meta("progression_icon", {"id": id, "color": color, "dimension": dimension})
	texture.texture = Icons.texture(id, color, pixels)
	texture.custom_minimum_size = Vector2(pixels, pixels)
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(texture)
	return texture


func _empty(parent: Node, title: String, text: String, icon: String) -> void:
	var box: VBoxContainer = _vbox(parent, 12)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_icon(box, icon, GOLD, 42)
	_label(box, title, 21, PAPER, true).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(box, text, 13, MUTED, true).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children():
		_ignore_mouse(child)


func _set_column(control: Control, column: int, count: int, margin: float, top: float, height: float) -> void:
	control.anchor_left = float(column) / float(count)
	control.anchor_right = float(column + 1) / float(count)
	control.offset_left = margin
	control.offset_right = -margin
	control.offset_top = top
	control.offset_bottom = top + height


func _rarity_color(rarity: String) -> Color:
	return {"common": Color("aab4b1"), "uncommon": MINT, "rare": Color("7faed9"), "epic": Color("b59ace"), "legendary": GOLD, "mythic": CORAL}.get(rarity, MUTED)


func _rarity_name(rarity: String) -> String:
	return {"common":"Comum", "uncommon":"Incomum", "rare":"Rara", "epic":"Épica", "legendary":"Lendária", "mythic":"Mítica"}.get(rarity, rarity.capitalize())


func _rarity_stars(rarity: String) -> String:
	var rank: int = maxi(0, ["common", "uncommon", "rare", "epic", "legendary", "mythic"].find(rarity))
	return "★".repeat(rank + 1)


func _level_pips(level: int) -> String:
	var count: int = mini(5, maxi(0, level))
	return "●".repeat(count) + "○".repeat(5 - count)


func _dps(stats: Dictionary) -> float:
	return float(stats.get("dps", float(stats.get("damage", 0)) * float(stats.get("fire_rate", 0)) * int(stats.get("pellets", 1))))


func _number(value: Variant) -> String:
	var amount: int = int(value) if value is int or value is float else 0
	return "%.1fk" % (float(amount) / 1000.0) if amount >= 10000 else str(amount)


func _short_value(value: Variant) -> String:
	if value is float:
		return "%.2f" % float(value)
	return str(value)


func _branch_name(branch: String) -> String:
	return {"attack":"OFENSIVA", "damage":"OFENSIVA", "offense":"OFENSIVA", "defense":"RESILIÊNCIA", "survival":"RESILIÊNCIA", "mobility":"MOBILIDADE", "utility":"EXPLORAÇÃO", "loot":"FORTUNA", "support":"SUPORTE", "combat":"COMBATE", "handling":"MANUSEIO", "critical":"CRÍTICO", "scavenger":"COLETA", "power":"POTÊNCIA"}.get(branch, branch.to_upper())


func _perk_icon(icon: String, branch: String) -> String:
	if icon in ["weapon", "bag", "paw", "forge", "chip", "shield", "coin", "aim", "arrow", "heart", "bolt", "star", "clock"]:
		return icon
	return {"attack":"weapon", "damage":"weapon", "offense":"weapon", "defense":"shield", "survival":"heart", "mobility":"bolt", "utility":"bag", "loot":"coin"}.get(branch, "chip")

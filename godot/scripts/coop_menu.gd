extends CanvasLayer
const Icons = preload("res://scripts/ui_icons.gd")
## Network entry point kept separate from the existing inventory and HUD.
var game: Node
var panel: PanelContainer
var launcher: Button
var address: LineEdit
var nickname: LineEdit
var port: SpinBox
var description: Label
var host_button: Button
var join_button: Button
var leave_button: Button
var _was_paused := true
var _waiting_join := false
var backdrop: ColorRect

func _ready() -> void:
	name = "CoopMenu"
	layer = 45
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.theme = Icons.theme()
	for state: String in ["normal","read_only","focus"]:
		var field := Icons.style(Color("0c151e"),Icons.MINT if state == "focus" else Color("38505c"),3)
		field.content_margin_top = 10
		field.content_margin_bottom = 10
		root.theme.set_stylebox(state,"LineEdit",field)
	root.theme.set_color("font_color","LineEdit",Icons.PAPER)
	root.theme.set_color("font_placeholder_color","LineEdit",Color("a8bac4"))
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop = ColorRect.new()
	backdrop.color = Color(0.01,0.02,0.03,0.84)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.hide()
	launcher = Button.new()
	launcher.text = "COOPERATIVO · F8"
	root.add_child(launcher)
	launcher.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	launcher.offset_left = -236
	launcher.offset_right = -24
	launcher.offset_top = 20
	launcher.offset_bottom = 62
	launcher.pressed.connect(open)
	panel = PanelContainer.new()
	var panel_style := Icons.style(Color("111c26"),Color("739d9f"),4)
	panel_style.border_width_top = 3
	panel.add_theme_stylebox_override("panel",panel_style)
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -310
	panel.offset_top = -326
	panel.offset_right = 310
	panel.offset_bottom = 326
	var margin := MarginContainer.new()
	for side: String in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	scroll.add_child(column)
	_label(column,"MEYUI / COOPERATIVO",11).add_theme_color_override("font_color",Icons.GOLD)
	_label(column, "A NOITE É DA EQUIPE.", 26)
	_label(column, "Até 4 jogadores · LAN ou VPN · host decide a partida", 15)
	_label(column, "Crie ou carregue uma expedição, pressione F8 e hospede.\nSeu parceiro entra pelo IPv4 da LAN/VPN e pela mesma porta.\nNa internet, use VPN ou encaminhe a porta UDP no roteador.", 14)
	nickname = LineEdit.new()
	nickname.placeholder_text = "Seu nome"
	nickname.text = game.coop.nickname
	nickname.max_length = 24
	column.add_child(nickname)
	address = LineEdit.new()
	address.placeholder_text = "IP do host (ex.: 192.168.1.10 / IP da VPN)"
	address.text = game.coop.last_address
	column.add_child(address)
	var row := HBoxContainer.new()
	column.add_child(row)
	_label(row, "Porta UDP", 15)
	port = SpinBox.new()
	port.min_value = 1024
	port.max_value = 65535
	port.value = game.coop.DEFAULT_PORT
	row.add_child(port)
	host_button = _button(column, "HOSPEDAR EXPEDIÇÃO ATUAL", _host)
	host_button.icon = Icons.texture("play",Icons.GOLD,20)
	join_button = _button(column, "ENTRAR NO HOST", _join)
	join_button.icon = Icons.texture("arrow",Icons.MINT,20)
	leave_button = _button(column, "DESCONECTAR", _leave)
	description = _label(column, "", 14)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size = Vector2(475, 52)
	_label(column, "Inventário, munição, moedas e Faro individuais.\nRegiões e rounds compartilhados. Menus não pausam o combate.", 13)
	_button(column, "VOLTAR", close)
	panel.hide()

func _label(parent: Node, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size.y = font_size * 1.35
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 40
	parent.add_child(button)
	button.pressed.connect(callback)
	return button

func _input(event: InputEvent) -> void:
	if panel.visible and event.is_action_pressed("pause_game"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		if panel.visible: close()
		else: open()
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	backdrop.visible = panel.visible
	launcher.visible = not panel.visible and game._menu_kind in ["main", "pause"]
	if not panel.visible: return
	description.text = game.coop.status
	if not game.running and not game.coop.is_online(): description.text += "\nPara hospedar, inicie ou carregue uma expedição primeiro."
	host_button.disabled = not game.running or game.coop.is_online()
	join_button.disabled = game.running or game.coop.is_online()
	leave_button.visible = game.coop.is_online()
	if _waiting_join and game.coop.mode == "client" and game.running:
		_waiting_join = false
		panel.hide()

func open() -> void:
	_was_paused = game.paused
	if game.running and not game.paused: game.pause_game()
	panel.show()
	backdrop.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	panel.hide()
	backdrop.hide()
	if game.running and not _was_paused: game.resume_game()

func _host() -> void:
	if game.coop.host_game(int(port.value)) == OK:
		panel.hide()
		game.resume_game()

func _join() -> void:
	_waiting_join = game.coop.join_game(address.text, int(port.value), nickname.text) == OK

func _leave() -> void:
	if game.coop.is_host(): game.save_game()
	game.coop.stop("Sessão encerrada. Progresso guardado no host.")

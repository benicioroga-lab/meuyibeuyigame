extends RefCounted
class_name MeyuiIcons

const INK := Color("0c1015")
const PANEL := Color("141c23")
const GOLD := Color("d9b477")
const CORAL := Color("c76c63")
const PAPER := Color("e7e2d4")
const MUTED := Color("839293")
const MINT := Color("8cafab")
static var _cache: Dictionary = {}

static func texture(id: String, tint: Color = PAPER, size: int = 24) -> Texture2D:
	var key := "%s:%s:%d" % [id, tint.to_html(), size]
	if _cache.has(key): return _cache[key]
	var paths: Dictionary = {
		"ammo": '<path d="M4 9l3-6 3 6v12H4zM14 9l3-6 3 6v12h-6zM4 16h6m4 0h6"/>',
		"blast": '<path d="m10 3 4 1v4m0-4 5 2v4M8 8h8l3 7-3 6H8l-3-6zM8 12h8m-7 4h6"/>',
		"cryo": '<path d="M12 2v20M3 7l18 10M3 17 21 7M9 4l3 3 3-3M9 20l3-3 3 3M3 10l4-1V5m14 9-4 1v4"/>',
		"shock": '<path d="m14 2-9 12h6l-1 8L21 9h-7zM3 4l2 2m15 12 2 2"/>',
		"fire": '<path d="M12 2c1 6-5 7-3 11 3-1 4-4 4-5 7 6 7 14-1 14S1 15 6 8c-1 6 3 4 6-6z"/>',
		"target": '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="4"/><path d="M12 1v4m0 14v4M1 12h4m14 0h4"/>',
		"weapon": '<path d="M3 9h14l4 2v3H9l-2 6H4l1-7H3zM16 9V7h3M9 14v3h4v-3"/>',
		"bag": '<path d="M5 7h14l1 14H4zM8 7V5a4 4 0 0 1 8 0v2M4 13h16M9 13v3h6v-3"/>',
		"paw": '<path d="M7 17c0-3 2-6 5-6s5 3 5 6c0 3-3 2-5 2s-5 1-5-2z"/><ellipse cx="5" cy="10" rx="2" ry="3"/><ellipse cx="10" cy="5" rx="2" ry="3"/><ellipse cx="16" cy="5" rx="2" ry="3"/><ellipse cx="20" cy="11" rx="2" ry="3"/>',
		"forge": '<path d="m4 3 6 1 3 4-4 4-6-6zM11 10l9 10M14 3l7 7M4 19h8M6 16v5"/>',
		"chip": '<rect x="6" y="6" width="12" height="12" rx="2"/><path d="M9 1v5m6-5v5M9 18v5m6-5v5M1 9h5m-5 6h5m12-6h5m-5 6h5M10 10h4v4h-4z"/>',
		"shield": '<path d="m12 2 8 3v6c0 5-4 8-8 11-4-3-8-6-8-11V5zM8 12l3 3 5-6"/>',
		"coin": '<path d="m12 2 9 5v10l-9 5-9-5V7zM12 7v10M8 10l4-3 4 3m-8 4 4 3 4-3"/>',
		"aim": '<circle cx="12" cy="12" r="6"/><path d="M12 1v6m0 10v6M1 12h6m10 0h6"/><circle cx="12" cy="12" r="1"/>',
		"arrow": '<path d="M3 12h17m-7-7 7 7-7 7"/>',
		"close": '<path d="m5 5 14 14M19 5 5 19"/>',
		"save": '<path d="M4 3h13l4 4v14H3V3zM7 3v6h10V3M7 21v-8h10v8M14 5v2"/>',
		"settings": '<path d="m9 2-1 4-4 1v4l3 2-1 4 3 3 4-2 4 1 3-3-1-4 2-3-3-3-4 1z"/><circle cx="12" cy="12" r="3"/>',
		"play": '<path d="m7 3 14 9-14 9z"/>',
		"pause": '<path d="M8 4v16M16 4v16"/>',
		"skull": '<path d="M5 15C0 4 6 2 12 2s12 2 7 13l-3 2v4H8v-4zM9 18v3m3-3v3m3-3v3"/><path d="m6 9 4 1-1 3H6zm12 0-4 1 1 3h3zM11 15h2"/>',
		"map": '<path d="m2 5 7-3 6 3 7-3v17l-7 3-6-3-7 3zM9 2v17m6-14v17"/>',
		"lock": '<rect x="5" y="10" width="14" height="12" rx="2"/><path d="M8 10V6a4 4 0 0 1 8 0v4M12 15v3"/>',
		"star": '<path d="m12 2 3 6 7 2-5 5 1 7-6-4-6 4 1-7-5-5 7-2z"/>',
		"clock": '<circle cx="12" cy="12" r="9"/><path d="M12 5v7l5 3"/>',
		"sound": '<path d="M3 9h4l5-5v16l-5-5H3zM16 8c3 3 3 5 0 8m3-11c5 5 5 9 0 14"/>',
		"eye": '<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
		"screen": '<rect x="2" y="3" width="20" height="14" rx="2"/><path d="M8 22h8m-4-5v5"/>',
		"check": '<path d="m4 12 5 5L20 6"/>',
		"unchecked": '<path d="M4 3h13l4 4v14H3V3z"/>',
		"checked": '<path d="M4 3h13l4 4v14H3V3zM6 12l4 4 8-8"/>',
		"heart": '<path d="M12 21 3 12C-2 4 8 0 12 7c4-7 14-3 9 5z"/>',
		"bolt": '<path d="M14 1 4 14h7l-1 9L21 9h-8z"/>',
		"exit": '<path d="M10 3H3v18h7M8 12h14m-5-5 5 5-5 5"/>',
		"restart": '<path d="M4 10a8 8 0 1 1 1 8M4 3v7h7"/>',
	}
	var path: String = str(paths.get(id, paths["star"]))
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 24 24"><g fill="none" stroke="#%s" stroke-width="1.65" stroke-linecap="round" stroke-linejoin="round">%s</g></svg>' % [size, size, tint.to_html(false), path]
	var image := Image.new()
	image.load_svg_from_string(svg)
	var result := ImageTexture.create_from_image(image)
	_cache[key] = result
	return result

static func style(fill: Color, border: Color = Color.TRANSPARENT, radius: int = 4) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(0 if border.a == 0.0 else 1)
	box.set_corner_radius_all(radius)
	box.corner_radius_top_right = radius + 6
	box.corner_radius_bottom_left = radius + 3
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box

static func theme() -> Theme:
	var result := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "DejaVu Sans"])
	result.default_font = font
	result.default_font_size = 16
	result.set_color("font_color", "Label", PAPER)
	result.set_color("font_shadow_color", "Label", Color(0.01, 0.02, 0.03, 0.7))
	result.set_constant("shadow_offset_y", "Label", 2)
	for button_type in ["Button", "OptionButton"]:
		result.set_stylebox("normal", button_type, style(Color(0.055, 0.075, 0.095, 0.64)))
		result.set_stylebox("hover", button_type, style(Color(0.15, 0.19, 0.20, 0.96)))
		result.set_stylebox("pressed", button_type, style(Color(0.24, 0.22, 0.17, 0.95)))
		result.set_stylebox("disabled", button_type, style(Color(0.04, 0.05, 0.07, 0.5)))
		var focus := style(Color.TRANSPARENT)
		focus.border_width_bottom = 2
		focus.border_color = GOLD
		result.set_stylebox("focus", button_type, focus)
		result.set_color("font_color", button_type, PAPER)
		result.set_color("font_hover_color", button_type, GOLD)
		result.set_color("font_disabled_color", button_type, MUTED.darkened(0.4))
	result.set_stylebox("panel", "PanelContainer", style(Color(0.05, 0.07, 0.09, 0.8)))
	result.set_stylebox("panel", "PopupMenu", style(PANEL, Color("394347")))
	result.set_color("font_color", "PopupMenu", PAPER)
	result.set_color("font_hover_color", "PopupMenu", GOLD)
	result.set_stylebox("hover", "PopupMenu", style(Color("263237")))
	for part in ["scroll", "grabber", "grabber_highlight", "grabber_pressed"]:
		var scroll_style := style(Color(0.10, 0.14, 0.16, 0.3) if part == "scroll" else MUTED.darkened(0.35) if part == "grabber" else GOLD, Color.TRANSPARENT, 2)
		scroll_style.content_margin_left = 2
		scroll_style.content_margin_right = 2
		scroll_style.content_margin_top = 4
		scroll_style.content_margin_bottom = 4
		result.set_stylebox(part, "VScrollBar", scroll_style)
	result.set_icon("checked", "CheckBox", texture("checked", GOLD, 22))
	result.set_icon("unchecked", "CheckBox", texture("unchecked", MUTED, 22))
	result.set_color("font_color", "CheckBox", PAPER)
	return result

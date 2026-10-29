class_name UI
extends RefCounted
## Helper grafici condivisi. Tema «fumetto spaziale» preso dal tabellone: verde mostro e verde
## stellato dello spazio, arancio dei corridoi, blu delle stanze, giallo delle pareti, rosso dell'ombra
## del titolo. Bordi neri spessi come nelle vignette. Titoli in Luckiest Guy (le lettere grasse del
## logo), scritte da fumetto in Bangers, testi in Comic Neue. Caratteri liberi (Apache / OFL).

const D = preload("res://scripts/data/agt_data.gd")

const SPACE := Color("#0b1f12")
const SPACE_L := Color("#16351d")
const GREEN := Color("#5cc23a")
const GREEN_D := Color("#2f7a22")
const SLIME := Color("#a8e05a")
const ORANGE := Color("#f26a21")
const ORANGE_L := Color("#ff9a4a")
const BLUE := Color("#2a8fc8")
const BLUE_D := Color("#1b5f8a")
const YELLOW := Color("#ffd923")
const YELLOW_L := Color("#fff17a")
const RED := Color("#d2321e")
const RED_D := Color("#8c1a10")
const CREAM := Color("#fff6d8")
const PAPER := Color("#f4ecd0")
const INK := Color("#141414")
const TEXT := Color("#fff6d8")
const MUTED := Color("#a9c3a0")
const CREW_C := Color("#4fb3ff")
const CYAN := Color("#3ff0ff")
const MON_C := Color("#7be04a")

static var _tex := {}
static var font_title: Font
static var font_comic: Font
static var font_body: Font
static var font_bold: Font


static func init_fonts() -> void:
	if font_title != null:
		return
	font_title = load("res://assets/fonts/LuckiestGuy-Regular.ttf")
	font_comic = load("res://assets/fonts/Bangers-Regular.ttf")
	font_body = load("res://assets/fonts/ComicNeue-Bold.ttf")
	font_bold = load("res://assets/fonts/ComicNeue-Bold.ttf")


static func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path)
	return _tex[path]


static func crew_tex(k: String) -> Texture2D:
	return tex("res://assets/counters/%s.png" % k)


## Specie di mostri della partita in corso (cambia le pedine delle Cose Arancioni e Viola).
static var species := "green"

static func mon_tex(l: String) -> Texture2D:
	if species != "green":
		var p := "res://assets/counters/%s_%s.png" % [species, D.MON[l]["img"]]
		if ResourceLoader.exists(p):
			return tex(p)
	return tex("res://assets/counters/%s.png" % D.MON[l]["img"])


static func weapon_tex(t: String) -> Texture2D:
	return tex("res://assets/weapons/%s.png" % t)


static func gear_tex(t: String) -> Texture2D:
	return tex("res://assets/counters/%s.png" % {"jet": "jet_suit", "mover": "cargo_mover", "soot": "ook_soot"}.get(t, t))


static func chit_tex(k: String) -> Texture2D:
	return tex("res://assets/weapons/%s.png" % D.CHITS[k]["img"])


static func die_tex(v: int) -> Texture2D:
	return tex("res://assets/dice/d%d.png" % clampi(v, 1, 6))


static func seat_col(s: int) -> Color:
	return CREW_C if s == 0 else MON_C


## Riquadro da fumetto: fondo, bordo nero spesso, ombra piena spostata.
static func panel_style(bg: Color, border: Color = INK, bw := 3, radius := 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(12)
	return sb


static func comic_style(bg: Color, radius := 12) -> StyleBoxFlat:
	var sb := panel_style(bg, INK, 4, radius)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 0
	sb.shadow_offset = Vector2(6, 6)
	return sb


static func dark_style(radius := 12, alpha := 0.95) -> StyleBoxFlat:
	var sb := panel_style(Color(SPACE, alpha), INK, 4, radius)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_offset = Vector2(6, 6)
	return sb


static func label(text: String, size := 20, col := TEXT, font: Font = null) -> Label:
	init_fonts()
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if font != null:
		l.add_theme_font_override("font", font)
	return l


## Titolo come il logo: giallo con contorno scuro e ombra rossa.
static func title(text: String, size := 48, col := YELLOW) -> Label:
	init_fonts()
	var l := label(text, size, col, font_title)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", maxi(6, size / 6))
	l.add_theme_color_override("font_shadow_color", RED)
	l.add_theme_constant_override("shadow_offset_x", maxi(3, size / 14))
	l.add_theme_constant_override("shadow_offset_y", maxi(3, size / 14))
	l.add_theme_constant_override("shadow_outline_size", maxi(6, size / 6))
	return l


## Scritta da fumetto (Bangers), per intestazioni e onomatopee.
static func heading(text: String, size := 26, col := YELLOW) -> Label:
	init_fonts()
	var l := label(text, size, col, font_comic)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", 6)
	return l


static func wrap(l: Label, w: float) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = w
	return l


static func icon_rect(t: Texture2D, sz: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = sz
	r.size = sz
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func button(text: String, w := 200.0, h := 50.0, size := 20) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, h)
	b.add_theme_font_size_override("font_size", size)
	return b


## Pulsante principale: arancio corridoio con scritta da fumetto.
static func primary(b: Button) -> Button:
	init_fonts()
	b.add_theme_stylebox_override("normal", comic_style(ORANGE, 10))
	b.add_theme_stylebox_override("hover", comic_style(ORANGE_L, 10))
	b.add_theme_stylebox_override("pressed", comic_style(YELLOW, 10))
	b.add_theme_stylebox_override("disabled", comic_style(Color("#6b5a4a"), 10))
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_color_override("font_outline_color", INK)
	b.add_theme_constant_override("outline_size", 6)
	b.add_theme_font_override("font", font_comic)
	return b


static func make_theme() -> Theme:
	init_fonts()
	var th := Theme.new()
	th.default_font = font_body
	th.default_font_size = 20
	var sb := comic_style(BLUE_D, 8)
	sb.border_width_left = 3
	sb.border_width_top = 3
	sb.border_width_right = 3
	sb.border_width_bottom = 3
	sb.shadow_offset = Vector2(4, 4)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 4
	sb.content_margin_bottom = 6
	th.set_stylebox("normal", "Button", sb)
	var sbh := sb.duplicate()
	sbh.bg_color = BLUE
	th.set_stylebox("hover", "Button", sbh)
	var sbp := sb.duplicate()
	sbp.bg_color = YELLOW
	sbp.shadow_offset = Vector2(1, 1)
	th.set_stylebox("pressed", "Button", sbp)
	var sbd := sb.duplicate()
	sbd.bg_color = Color("#253a33")
	sbd.border_color = Color("#0d1a12")
	th.set_stylebox("disabled", "Button", sbd)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", CREAM)
	th.set_color("font_hover_color", "Button", YELLOW_L)
	th.set_color("font_pressed_color", "Button", INK)
	th.set_color("font_disabled_color", "Button", Color("#6f8379"))
	th.set_font("font", "Button", font_bold)
	th.set_font_size("font_size", "Button", 20)
	th.set_color("font_color", "Label", TEXT)
	var pn := StyleBoxFlat.new()
	pn.bg_color = SPACE
	th.set_stylebox("panel", "Panel", pn)
	th.set_stylebox("panel", "PanelContainer", pn)
	th.set_font("normal_font", "RichTextLabel", font_body)
	th.set_font("bold_font", "RichTextLabel", font_bold)
	th.set_font("italics_font", "RichTextLabel", font_body)
	for k in ["normal_font_size", "bold_font_size", "italics_font_size"]:
		th.set_font_size(k, "RichTextLabel", 20)
	th.set_color("default_color", "RichTextLabel", TEXT)
	th.set_font("font", "LineEdit", font_bold)
	th.set_font_size("font_size", "LineEdit", 24)
	th.set_color("font_color", "LineEdit", INK)
	th.set_color("font_placeholder_color", "LineEdit", Color("#7a7262"))
	th.set_color("caret_color", "LineEdit", INK)
	th.set_stylebox("normal", "LineEdit", panel_style(CREAM, INK, 3, 6))
	th.set_stylebox("focus", "LineEdit", panel_style(YELLOW_L, INK, 3, 6))
	th.set_font("font", "TooltipLabel", font_body)
	th.set_font_size("font_size", "TooltipLabel", 18)
	th.set_color("font_color", "TooltipLabel", INK)
	var tp := panel_style(CREAM, INK, 2, 6)
	tp.set_content_margin_all(8)
	th.set_stylebox("panel", "TooltipPanel", tp)
	var sc := StyleBoxFlat.new()
	sc.bg_color = Color(GREEN, 0.9)
	sc.set_corner_radius_all(4)
	for k in ["grabber", "grabber_highlight", "grabber_pressed"]:
		th.set_stylebox(k, "VScrollBar", sc)
	var sct := StyleBoxFlat.new()
	sct.bg_color = Color(0, 0, 0, 0.3)
	th.set_stylebox("scroll", "VScrollBar", sct)
	# menu a tendina (OptionButton) e il suo elenco
	th.set_stylebox("normal", "OptionButton", sb)
	th.set_stylebox("hover", "OptionButton", sbh)
	th.set_stylebox("pressed", "OptionButton", sbp)
	th.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	th.set_font("font", "OptionButton", font_bold)
	th.set_font_size("font_size", "OptionButton", 18)
	th.set_color("font_color", "OptionButton", CREAM)
	var pm := panel_style(CREAM, INK, 3, 6)
	th.set_stylebox("panel", "PopupMenu", pm)
	th.set_font("font", "PopupMenu", font_bold)
	th.set_font_size("font_size", "PopupMenu", 18)
	th.set_color("font_color", "PopupMenu", INK)
	th.set_color("font_hover_color", "PopupMenu", RED_D)
	var hov := StyleBoxFlat.new()
	hov.bg_color = YELLOW
	th.set_stylebox("hover", "PopupMenu", hov)
	return th


## Sfondo spaziale con stelle e un alone verde (disegnato, nessuna immagine).
class Starfield extends Control:
	var stars := []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var r := RandomNumberGenerator.new()
		r.seed = 7
		for i in 260:
			stars.append([Vector2(r.randf(), r.randf()), r.randf_range(0.6, 2.4), r.randf_range(0.3, 1.0)])
		resized.connect(queue_redraw)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UI.SPACE)
		var c := size * Vector2(0.5, 0.42)
		for i in 10:
			var rad := size.length() * (0.55 - i * 0.05)
			draw_circle(c, rad, Color(0.16, 0.42, 0.14, 0.035))
		for s in stars:
			var p: Vector2 = s[0] * size
			draw_circle(p, s[1], Color(1, 1, 0.85, s[2] * 0.8))

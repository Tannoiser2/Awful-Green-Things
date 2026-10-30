extends Control
## La storia illustrata dell'Epilogo alternativo: a ogni paragrafo la vignetta, il racconto, i tiri di dado
## e chi è ancora a bordo. Le scelte del viaggio si fanno qui; «Avanti» manda avanti il motore.

const D = preload("res://scripts/data/agt_data.gd")
const EP = preload("res://scripts/data/epilogo.gd")

var view                          # la vista di gioco
var engine: AGTEngine
var page: Control
var img: TextureRect
var frame: PanelContainer
var chapter_lbl: Label
var para_lbl: Label
var title_lbl: Label
var story: RichTextLabel
var dice_box: VBoxContainer
var crew_row: HBoxContainer
var btn_box: VBoxContainer
var boat := ""
var years := 0
var _auto_timer: SceneTreeTimer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.1, 0.94)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	add_child(UI.Starfield.new())
	page = Control.new()
	page.size = Vector2(1920, 1080)
	add_child(page)
	_center.call_deferred()
	get_viewport().size_changed.connect(_center)
	# la vignetta, in una cornice da fumetto leggermente storta
	frame = PanelContainer.new()
	var fs := UI.comic_style(UI.INK, 8)
	fs.set_content_margin_all(8)
	frame.add_theme_stylebox_override("panel", fs)
	frame.position = Vector2(44, 120)
	frame.size = Vector2(1176, 800)
	frame.pivot_offset = frame.size * 0.5
	page.add_child(frame)
	img = TextureRect.new()
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.custom_minimum_size = Vector2(1160, 784)
	frame.add_child(img)
	chapter_lbl = UI.title("", 54)
	chapter_lbl.position = Vector2(50, 22)
	page.add_child(chapter_lbl)
	# a destra: il racconto
	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", UI.comic_style(UI.CREAM, 16))
	right.position = Vector2(1250, 40)
	right.size = Vector2(630, 1000)
	page.add_child(right)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	right.add_child(vb)
	para_lbl = UI.heading("", 24, UI.RED)
	vb.add_child(para_lbl)
	title_lbl = UI.title("", 44, UI.ORANGE)
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.custom_minimum_size.x = 590
	vb.add_child(title_lbl)
	story = RichTextLabel.new()
	story.bbcode_enabled = true
	story.fit_content = true
	story.scroll_active = false
	story.custom_minimum_size = Vector2(590, 0)
	story.add_theme_color_override("default_color", UI.INK)
	story.add_theme_font_size_override("normal_font_size", 22)
	story.add_theme_font_override("normal_font", UI.font_bold)
	vb.add_child(story)
	var dice_panel := PanelContainer.new()
	var ds := UI.comic_style(Color("#fde7a0"), 10)
	ds.set_content_margin_all(10)
	dice_panel.add_theme_stylebox_override("panel", ds)
	vb.add_child(dice_panel)
	dice_box = VBoxContainer.new()
	dice_box.add_theme_constant_override("separation", 4)
	dice_panel.add_child(dice_box)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(sp)
	vb.add_child(UI.heading("A bordo", 24, UI.BLUE_D))
	crew_row = HBoxContainer.new()
	crew_row.add_theme_constant_override("separation", 6)
	vb.add_child(crew_row)
	btn_box = VBoxContainer.new()
	btn_box.add_theme_constant_override("separation", 8)
	vb.add_child(btn_box)


func _center() -> void:
	var vs := get_viewport_rect().size
	var k := minf(vs.x / 1920.0, vs.y / 1080.0)
	page.scale = Vector2(k, k)
	page.position = ((vs - Vector2(1920, 1080) * k) * 0.5).floor()


## Inizio del viaggio di una scialuppa.
func chapter(b: String, crew: Array) -> void:
	boat = b
	years = 0
	chapter_lbl.text = "Il viaggio %s" % D.BOATS[b]["of"]
	_crew(crew)


func _crew(ids: Array) -> void:
	for c in crew_row.get_children():
		c.queue_free()
	for id in ids:
		var t := UI.icon_rect(UI.crew_tex(engine.crew[id]["k"]), Vector2(58, 58))
		t.tooltip_text = engine.cname(id)
		crew_row.add_child(t)
	if ids.is_empty():
		crew_row.add_child(UI.label("nessuno…", 22, UI.INK, UI.font_bold))


func _show(para: int) -> void:
	var p: Array = EP.PAGES.get(para, ["", ""])
	img.texture = UI.tex("res://assets/epilogo/epilogo_%02d.webp" % para)
	para_lbl.text = "Paragrafo %d" % para
	title_lbl.text = str(p[0])
	story.text = engine.sp_text(str(p[1]))
	frame.rotation = deg_to_rad(randf_range(-1.2, 1.2))
	frame.modulate.a = 0.0
	var tw := frame.create_tween()
	tw.tween_property(frame, "modulate:a", 1.0, 0.35)
	for c in btn_box.get_children():
		c.queue_free()
	for c in dice_box.get_children():
		c.queue_free()


func _lines(lines: Array) -> void:
	for l in lines:
		var t := str(l)
		if t.begins_with("Epilogo alternativo"):
			continue
		var lb := UI.label(t, 19, UI.INK, UI.font_bold)
		lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lb.custom_minimum_size.x = 560
		dice_box.add_child(lb)
	dice_box.get_parent().visible = dice_box.get_child_count() > 0


## Pagina dopo un paragrafo: vignetta, racconto, tiri e «Avanti».
func show_page(para: int, lines: Array, crew: Array) -> void:
	_show(para)
	_lines(lines)
	_crew(crew)
	_next_button("Avanti", func(): engine.epi_continue())


## Una scelta del viaggio: i pulsanti al posto di «Avanti».
func show_choice(req: Dictionary, submit: Callable) -> void:
	_show(int(req.get("para", 1)))
	dice_box.get_parent().visible = false
	var opts: Array = req["options"]
	for i in opts.size():
		var ii: int = i
		var b := UI.button(str(opts[i]), 590, 56, 22)
		if i == 0:
			UI.primary(b)
		b.pressed.connect(func(): submit.call(ii))
		btn_box.add_child(b)


## Fine del viaggio di una scialuppa.
func show_end(fate: String, survivors: Array, yrs: int) -> void:
	var para := 12 if fate == "home" else (18 if fate == "marooned" else 11)
	_show(para)
	_crew(survivors)
	title_lbl.text = {"home": "A casa!", "marooned": "Naufraghi", "lost": "Perduti"}.get(fate, "Fine")
	var names := []
	for id in survivors:
		names.append(engine.cname(id))
	match fate:
		"home":
			story.text = "Dopo %d anni di viaggio %s atterra su Snudl-1. Tornano a casa: %s." % [yrs, D.BOATS[boat]["name"], ", ".join(names)]
		"marooned":
			story.text = "%s resta su un pianeta sperduto. Sopravvivono %s: contano per metà dei punti." % [String(D.BOATS[boat]["name"]).capitalize(), ", ".join(names)]
		_:
			story.text = "Di %s non si saprà più nulla. Nessuno tornerà a raccontare questa storia." % D.BOATS[boat]["name"]
	dice_box.get_parent().visible = false
	_next_button("Fine del viaggio", func(): engine.epi_continue())


func _next_button(text: String, cb: Callable) -> void:
	var b := UI.primary(UI.button(text, 590, 60, 26))
	b.pressed.connect(func():
		b.disabled = true
		cb.call())
	btn_box.add_child(b)
	# senza nessuno a guardare (solo IA) la storia va avanti da sola
	if view != null and view.local_seats.is_empty():
		get_tree().create_timer(2.5).timeout.connect(func():
			if is_instance_valid(b) and not b.disabled:
				b.disabled = true
				cb.call())

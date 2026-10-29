extends Control
## Vista di gioco: il tabellone della Znutar a sinistra (BoardView), a destra la vignetta della fase con
## le scelte, la vetrina delle armi con gli effetti scoperti, i dadi e il diario. Le onomatopee da
## fumetto sottolineano gli eventi (GNAM!, SPLAT!, KABOOM!).

const D = preload("res://scripts/data/agt_data.gd")
const LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

var main
var config: Dictionary
var engine: AGTEngine
var online = null
var pending: Dictionary = {}
var local_seats: Array = []
var _dirty := false

var board                       # vista attiva: BoardView (2D) o Board3D (3D)
var board2d: BoardView
var board3d: Board3D
var view_btn: Button
var top_lbl: Label
var phase_lbl: Label
var status_lbl: Label
var hint_lbl: Label
var dec_box: VBoxContainer
var dec_scroll: ScrollContainer
var foot_box: HFlowContainer
var info_lbl: RichTextLabel
var dice_box: HBoxContainer
var dice_lbl: Label
var arms_grid: GridContainer
var ticker: RichTextLabel
var log_panel: PanelContainer
var log_text: RichTextLabel
var fx_layer: Control

# scelte in corso
var sel_crew := -1
var sel_area := ""
var sel_mons: Array = []
var setup_sel: Dictionary = {}
var place_l := "A"
var plan: Dictionary = {}           # pianificazione attacco: chiave -> scelta
var plan_area := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	engine = AGTEngine.new()
	add_child(engine)
	online = config.get("online", null)
	if online != null:
		add_child(online)
		online.view = self
		engine.online = online
	engine.setup(config)
	for s in engine.players.size():
		var p: Dictionary = engine.players[s]
		engine.ais[s] = AGTAI.new(int(p["level"]), int(config.get("seed", 0)) * 7 + s + 1 if config.has("seed") else randi())
		if online != null:
			if s == online.seat:
				local_seats.append(s)
		elif not p["ai"]:
			local_seats.append(s)
	engine.ai_delay = float(config.get("ai_delay", 0.6))
	_build()
	engine.changed.connect(_mark)
	engine.log_added.connect(_on_log)
	engine.decision_requested.connect(_on_decision)
	engine.game_ended.connect(_on_end)
	engine.fx.connect(_on_fx)
	board2d.set_engine(engine)
	board3d.set_engine(engine)
	_refresh()
	board2d.fit.call_deferred()
	board3d.fit.call_deferred()
	if online != null and online.role != "host":
		online.heartbeat_loop()
	engine.run.call_deferred()


func _mark() -> void:
	if not _dirty:
		_dirty = true
		_refresh.call_deferred()


# ================================================================ costruzione

func _build() -> void:
	add_child(UI.Starfield.new())
	board2d = BoardView.new()
	board3d = Board3D.new()
	for b in [board2d, board3d]:
		b.view = self
		b.position = Vector2(0, 70)
		b.size = Vector2(1330, 1010)
		add_child(b)
		b.area_clicked.connect(_on_area_click)
		b.piece_clicked.connect(_on_piece_click)
		b.area_hovered.connect(_on_hover)
	var v3: bool = config.get("view3d", true)
	board = board3d if v3 else board2d
	board2d.visible = not v3
	board3d.visible = v3
	# barra in alto
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", UI.panel_style(Color(UI.SPACE_L, 0.97), UI.INK, 0, 0))
	top.position = Vector2.ZERO
	top.size = Vector2(1920, 70)
	add_child(top)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 14)
	top.add_child(th)
	var tt := UI.title("Awful Green Things", 34)
	th.add_child(tt)
	top_lbl = UI.heading("", 28, UI.CREAM)
	top_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	th.add_child(top_lbl)
	view_btn = UI.button("Vista 2D" if v3 else "Vista 3D", 140, 46, 19)
	view_btn.pressed.connect(_toggle_view)
	th.add_child(view_btn)
	for b in [["Centra", func(): board.fit()], ["Regole", _show_rules_popup], ["Diario", func(): log_panel.visible = not log_panel.visible], ["Menu", _confirm_menu]]:
		var btn := UI.button(b[0], 120, 46, 19)
		btn.pressed.connect(b[1])
		th.add_child(btn)
	# colonna di destra
	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", UI.dark_style(14, 0.96))
	right.position = Vector2(1340, 80)
	right.size = Vector2(570, 990)
	add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 8)
	right.add_child(rv)
	phase_lbl = UI.heading("", 34)
	rv.add_child(phase_lbl)
	hint_lbl = UI.wrap(UI.label("", 19, UI.CREAM), 530)
	rv.add_child(hint_lbl)
	status_lbl = UI.wrap(UI.label("", 18, UI.ORANGE_L, UI.font_bold), 530)
	rv.add_child(status_lbl)
	dec_scroll = ScrollContainer.new()
	dec_scroll.custom_minimum_size = Vector2(530, 240)
	dec_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dec_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(dec_scroll)
	dec_box = VBoxContainer.new()
	dec_box.add_theme_constant_override("separation", 6)
	dec_box.custom_minimum_size.x = 520
	dec_scroll.add_child(dec_box)
	foot_box = HFlowContainer.new()
	foot_box.add_theme_constant_override("h_separation", 8)
	foot_box.add_theme_constant_override("v_separation", 6)
	rv.add_child(foot_box)
	info_lbl = RichTextLabel.new()
	info_lbl.bbcode_enabled = true
	info_lbl.fit_content = false
	info_lbl.scroll_active = true
	info_lbl.custom_minimum_size = Vector2(530, 84)
	info_lbl.add_theme_font_size_override("normal_font_size", 17)
	info_lbl.add_theme_font_size_override("bold_font_size", 17)
	rv.add_child(info_lbl)
	# dadi
	var dp := PanelContainer.new()
	dp.add_theme_stylebox_override("panel", UI.panel_style(Color("#0f2a1a"), UI.INK, 3, 8))
	rv.add_child(dp)
	var dv := VBoxContainer.new()
	dp.add_child(dv)
	dice_lbl = UI.label("", 17, UI.MUTED)
	dv.add_child(dice_lbl)
	dice_box = HBoxContainer.new()
	dice_box.add_theme_constant_override("separation", 4)
	dice_box.custom_minimum_size.y = 38
	dv.add_child(dice_box)
	# vetrina delle armi
	rv.add_child(UI.heading("Vetrina delle armi", 22))
	arms_grid = GridContainer.new()
	arms_grid.columns = 6
	arms_grid.add_theme_constant_override("h_separation", 4)
	arms_grid.add_theme_constant_override("v_separation", 6)
	rv.add_child(arms_grid)
	# ultime righe del diario, in basso sopra il tabellone
	ticker = RichTextLabel.new()
	ticker.bbcode_enabled = true
	ticker.scroll_following = true
	ticker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ticker.position = Vector2(12, 984)
	ticker.size = Vector2(1310, 92)
	ticker.add_theme_font_size_override("normal_font_size", 17)
	ticker.add_theme_color_override("font_outline_color", UI.INK)
	ticker.add_theme_constant_override("outline_size", 5)
	add_child(ticker)
	# diario completo
	log_panel = PanelContainer.new()
	log_panel.add_theme_stylebox_override("panel", UI.comic_style(Color(UI.SPACE, 0.97)))
	log_panel.position = Vector2(60, 110)
	log_panel.size = Vector2(1200, 900)
	log_panel.visible = false
	add_child(log_panel)
	var lv := VBoxContainer.new()
	log_panel.add_child(lv)
	var lh := HBoxContainer.new()
	lv.add_child(lh)
	var lt := UI.heading("Diario di bordo", 34)
	lt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lh.add_child(lt)
	var lc := UI.button("Chiudi", 140, 46)
	lc.pressed.connect(func(): log_panel.visible = false)
	lh.add_child(lc)
	log_text = RichTextLabel.new()
	log_text.bbcode_enabled = true
	log_text.scroll_following = true
	log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_text.add_theme_font_size_override("normal_font_size", 18)
	lv.add_child(log_text)
	fx_layer = Control.new()
	fx_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fx_layer)


func _toggle_view() -> void:
	var old = board
	board = board2d if board == board3d else board3d
	for k in ["highlight", "selected_area", "sel_pieces", "tags", "crew_tags"]:
		board.set(k, old.get(k))
	board2d.visible = board == board2d
	board3d.visible = board == board3d
	view_btn.text = "Vista 2D" if board == board3d else "Vista 3D"
	board.fit()
	board.refresh()


func _arms_refresh() -> void:
	for c in arms_grid.get_children():
		c.queue_free()
	for t in D.WEAPON_ORDER:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		var ic := UI.icon_rect(UI.weapon_tex(t), Vector2(70, 70))
		ic.mouse_filter = Control.MOUSE_FILTER_PASS
		var k := engine.effect_of(t)
		var tip: String = D.WEAPONS[t]["name"] + "\n" + _range_text(t)
		var gone := true
		for w in engine.wpn:
			if engine.wpn[w]["t"] == t and not engine.wpn[w]["out"]:
				gone = false
		if k != "":
			tip += "\nEffetto: " + engine.chit_name(k)
			if engine.known2.has(t):
				tip += "\nAltra frequenza: " + engine.chit_name(engine.known2[t])
		else:
			tip += "\nEffetto: da scoprire!"
		var holder := PanelContainer.new()
		var hs := UI.panel_style(UI.CREAM if k != "" else Color("#29493a"), UI.INK, 3, 6)
		hs.set_content_margin_all(3)
		holder.add_theme_stylebox_override("panel", hs)
		holder.tooltip_text = tip
		holder.mouse_filter = Control.MOUSE_FILTER_STOP
		holder.custom_minimum_size = Vector2(76, 100)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 0)
		holder.add_child(vb)
		if gone:
			ic.modulate = Color(0.4, 0.4, 0.4)
		vb.add_child(ic)
		if k != "":
			var ch := UI.icon_rect(UI.chit_tex(k), Vector2(70, 24))
			ch.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			vb.add_child(ch)
		else:
			var q := UI.heading("?", 20, UI.YELLOW)
			q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vb.add_child(q)
		arms_grid.add_child(holder)


static func _range_text(t: String) -> String:
	var w: Dictionary = D.WEAPONS[t]
	var r: String = {"same": "Solo nella stessa area", "adj": "Stessa area o area adiacente", "los": "Qualsiasi area in linea di vista", "none": "Si monta in un'area (un turno fermi)"}[w["range"]]
	var k: String = {"single": "un mostro", "area": "tutti i mostri dell'area", "blast": "tutta la sezione (anche l'equipaggio!)", "fence": "i mostri che entrano o restano nell'area"}[w["kind"]]
	var extra := ""
	if w.has("back"):
		extra = "\nDopo il lancio torna al suo deposito."
	if t == "grenade":
		extra += "\nSull'equipaggio: 5 dadi per stordire."
	if t == "fuel":
		extra += "\nSull'equipaggio: 5 dadi per uccidere."
	return r + ", colpisce " + k + "." + extra


# ================================================================ aggiornamento

func _refresh() -> void:
	_dirty = false
	if not is_inside_tree():
		return
	var ph := {"crew_setup": "Preparazione", "mon_setup": "Le uova", "discovery": "Scoperta!", "discovery_attack": "Scoperta!",
		"grow": "Crescita", "mmove": "Le Cose Verdi si muovono", "mattack": "Le Cose Verdi attaccano", "grab": "Prendere le armi",
		"cmove": "Movimento", "alert": "Allarme!", "cattack": "Attacco dell'equipaggio", "epilogue": "Epilogo", "fine_partita": "Fine"}
	var who := ""
	if engine.phase in ["grow", "mmove", "mattack", "mon_setup"]:
		who = engine.pname(1)
	elif engine.phase != "fine_partita":
		who = engine.pname(engine.cur_team if engine.mutiny() else 0)
	top_lbl.text = "Turno %d · %s%s" % [maxi(engine.turn_no, 0), ph.get(engine.phase, engine.phase), (" · " + who) if who != "" else ""]
	if engine.sd_left > 0:
		top_lbl.text += "  ·  AUTODISTRUZIONE fra %d" % engine.sd_left
	if pending.is_empty():
		phase_lbl.text = ph.get(engine.phase, "")
		if engine.phase != "fine_partita":
			hint_lbl.text = "Tocca a %s…" % who if who != "" else ""
		_clear_box()
		board.highlight = {}
		board.sel_pieces = {}
		board.tags = {}
		board.crew_tags = {}
	_arms_refresh()
	_info(board.hover if board.hover != "" else engine.last_area)
	if engine.last_area != "" and pending.is_empty():
		board.selected_area = engine.last_area
	board.refresh()


func _info(a: String) -> void:
	if a == "" or not engine.AR.has(a):
		info_lbl.text = "[color=#a9c3a0]Passa sopra un'area per vederne il contenuto.[/color]"
		return
	var parts := []
	for c in engine.crew_at(a):
		var s: String = "%s (%d/%d/%d)" % [engine.cname(c), engine.cdef(c)["att"], engine.cdef(c)["con"], engine.cdef(c)["mov"]]
		if engine.crew[c]["w"] >= 0:
			s += " con " + engine.wname(engine.wtype(engine.crew[c]["w"]))
		if not engine.awake(c):
			s += " [stordito]"
		if engine.mutiny():
			var tm := engine.team_of(c)
			s += " [%s]" % ("Capitano" if tm == 0 else ("Primo Uff." if tm == 2 else "senza padrone"))
		parts.append(s)
	var cnt := {}
	var st := 0
	for m in engine.mons_at(a):
		cnt[engine.mon[m]["l"]] = cnt.get(engine.mon[m]["l"], 0) + 1
		if engine.mon[m]["st"]:
			st += 1
	var mp := []
	for l in D.MON_ORDER:
		if cnt.has(l):
			mp.append("%d %s" % [cnt[l], D.MON[l]["plural"] if cnt[l] > 1 else D.MON[l]["name"]])
	var wp := []
	for w in engine.weapons_at(a):
		wp.append(engine.wname(engine.wtype(w)) + (" (acceso)" if engine.wpn[w]["on"] else ""))
	var txt := "[b][color=#ffd923]%s[/color][/b]" % engine.area_name(a)
	var nh: int = (engine.hidden_at(a) as Array).size()
	if nh > 0:
		txt += "\n[color=#9fc48a]%d pedin%s copert%s: Cose Verdi addormentate o equipaggio prigioniero.[/color]" % [nh, "a" if nh == 1 else "e", "a" if nh == 1 else "e"]
	var cap := []
	for c in engine.captives_at(a):
		cap.append(engine.cname(c))
	if not cap.is_empty():
		txt += "\n[color=#9be37a]Prigionieri nella melma:[/color] " + ", ".join(cap)
	if not parts.is_empty():
		txt += "\n[color=#4fb3ff]Equipaggio:[/color] " + ", ".join(parts)
	if not mp.is_empty():
		txt += "\n[color=#7be04a]Cose Verdi:[/color] " + ", ".join(mp) + (" (%d storditi)" % st if st > 0 else "")
	if not wp.is_empty():
		txt += "\n[color=#ff9a4a]A terra:[/color] " + ", ".join(wp)
	info_lbl.text = txt


func _on_hover(a: String) -> void:
	_info(a if a != "" else engine.last_area)


func _on_log(t: String) -> void:
	var col := "#fff6d8"
	if t.begins_with("—"):
		col = "#ffd923"
	elif t.begins_with("■") or t.contains("Divorato") or t.contains("KABOOM"):
		col = "#ff9a4a"
	elif t.begins_with("Scoperto"):
		col = "#7be04a"
	var line := "[color=%s]%s[/color]\n" % [col, t]
	ticker.append_text(line)
	log_text.append_text(line)


# ================================================================ effetti

func _on_fx(kind: String, data: Dictionary) -> void:
	match kind:
		"dice":
			_show_dice(data["dice"], str(data.get("info", "")), int(data.get("total", 0)))
		"kill_crew":
			_pop_word(data["area"], ["GNAM!", "CHOMP!", "SLURP!", "GULP!"].pick_random(), UI.RED)
		"kill_mon":
			_pop_word(data["area"], ["SPLAT!", "SPLOTCH!", "ZOT!", "BLAM!"].pick_random(), UI.YELLOW)
		"frag":
			_pop_word(data["area"], "SPLOOSH!", UI.SLIME)
		"chit":
			_show_chit(str(data["chit"]), str(data.get("t", "")))
		"attack":
			board.flash_area(data["area"])
		"grow":
			_pop_center("CRESCONO!", UI.SLIME)
		"alarm":
			_pop_center("AUTODISTRUZIONE!", UI.RED)
		"explode":
			_pop_center("KA-BOOOM!", UI.ORANGE)
		"alert":
			_pop_word(data["area"], "ALLARME!", UI.ORANGE)
		"free":
			_pop_word(data["area"], "LIBERO!", UI.CREAM)
		"charge_soon":
			_pop_center("SI SVEGLIANO…", UI.ORANGE)
		"charge":
			_pop_center("LA CARICA!", UI.RED)
		"escape":
			_pop_word(data["b"], "WHOOSH!", UI.CREAM)
		"move":
			var path: Array = data.get("path", [])
			if not path.is_empty():
				board.flash_area(path[path.size() - 1])


func _show_dice(vals: Array, info: String, tot: int) -> void:
	for c in dice_box.get_children():
		c.queue_free()
	for v in vals.slice(0, 12):
		var r := UI.icon_rect(UI.die_tex(int(v)), Vector2(36, 36))
		dice_box.add_child(r)
		r.pivot_offset = Vector2(18, 18)
		r.rotation = randf_range(-0.6, 0.6)
		var tw := r.create_tween()
		tw.tween_property(r, "rotation", 0.0, 0.25)
	if vals.size() > 12:
		dice_box.add_child(UI.label("+%d" % (vals.size() - 12), 20, UI.CREAM, UI.font_bold))
	var tl := UI.heading("= %d" % tot, 28, UI.YELLOW)
	dice_box.add_child(tl)
	dice_lbl.text = info


func _pop_word(a: String, word: String, col: Color) -> void:
	if not engine.AR.has(a):
		return
	var p: Vector2 = board.area_center(a) + board.position
	_pop_at(p, word, col)


func _pop_center(word: String, col: Color) -> void:
	_pop_at(board.position + board.size * 0.5, word, col, 96)


func _pop_at(p: Vector2, word: String, col: Color, size := 64) -> void:
	var l := UI.title(word, size, col)
	l.add_theme_color_override("font_shadow_color", UI.INK)
	fx_layer.add_child(l)
	l.position = p - Vector2(size * word.length() * 0.3, size * 0.6)
	l.pivot_offset = Vector2(size * word.length() * 0.3, size * 0.6)
	l.scale = Vector2(0.2, 0.2)
	l.rotation = randf_range(-0.25, 0.25)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2(1.15, 1.15), 0.18).set_trans(Tween.TRANS_BACK)
	tw.tween_property(l, "scale", Vector2(1, 1), 0.1)
	tw.tween_interval(0.7)
	tw.tween_property(l, "modulate:a", 0.0, 0.35)
	tw.tween_callback(l.queue_free)


func _show_chit(ch: String, t: String) -> void:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UI.comic_style(UI.CREAM, 16))
	fx_layer.add_child(pc)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	pc.add_child(hb)
	if t != "" and D.WEAPONS.has(t):
		hb.add_child(UI.icon_rect(UI.weapon_tex(t), Vector2(110, 110)))
	hb.add_child(UI.icon_rect(UI.chit_tex(ch), Vector2(110, 110)))
	var vb := VBoxContainer.new()
	hb.add_child(vb)
	var title := "Piedipiombo è indigesto!" if t == "robot" else ("Prova di armi nuove" if t == "" else ("Scoperto: " + engine.wname(t) if D.WEAPONS.has(t) else ""))
	vb.add_child(UI.label(title, 22, UI.INK, UI.font_bold))
	vb.add_child(UI.heading(engine.chit_name(ch), 40, UI.RED))
	pc.position = Vector2(300, 420)
	pc.modulate.a = 0
	var tw := pc.create_tween()
	tw.tween_property(pc, "modulate:a", 1.0, 0.2)
	tw.tween_interval(1.6)
	tw.tween_property(pc, "modulate:a", 0.0, 0.4)
	tw.tween_callback(pc.queue_free)


# ================================================================ decisioni

func _on_decision(req: Dictionary) -> void:
	pending = req
	sel_crew = -1
	sel_area = ""
	sel_mons = []
	plan = {}
	plan_area = ""
	status_lbl.text = ""
	if req["type"] == "crew_setup":
		setup_sel = {}
		for id in req["options"]:
			setup_sel[int(id)] = req["options"][id][0]
			engine.crew[int(id)]["loc"] = setup_sel[int(id)]   # anteprima sul tabellone
	_build_decision()


func _submit(r) -> void:
	pending = {}
	board.highlight = {}
	board.sel_pieces = {}
	board.tags = {}
	board.crew_tags = {}
	_clear_box()
	engine.provide_decision(r)


func _seat() -> int:
	return int(pending.get("seat", 0))


## Piano d'attacco suggerito dall'IA per un'area (mostri, o avversari nell'ammutinamento).
func _sug_plan(a: String) -> Array:
	var ai: AGTAI = engine.ais[_seat()]
	var p := ai._plan_area(engine, a) if not engine.mons_at(a).is_empty() else []
	if p.is_empty() and engine.mutiny():
		p = ai._plan_crew_area(engine, a)
	return p


func _clear_box() -> void:
	for c in dec_box.get_children():
		c.queue_free()
	for c in foot_box.get_children():
		c.queue_free()


func _add_btn(text: String, cb: Callable, primary := false, w := 520.0) -> Button:
	var b := UI.button(text, w, 50, 19)
	if primary:
		UI.primary(b)
		b.add_theme_font_size_override("font_size", 24)
	b.pressed.connect(cb)
	dec_box.add_child(b)
	return b


## Pulsante fisso sotto l'elenco (sempre visibile, anche quando l'elenco scorre).
func _foot_btn(text: String, cb: Callable, primary := false, w := 256.0) -> Button:
	var b := UI.button(text, w, 52, 19)
	if primary:
		UI.primary(b)
		b.add_theme_font_size_override("font_size", 24)
	b.pressed.connect(cb)
	foot_box.add_child(b)
	return b


func _add_text(t: String, col := UI.CREAM, size := 18) -> Label:
	var l := UI.wrap(UI.label(t, size, col), 510)
	dec_box.add_child(l)
	return l


func _build_decision() -> void:
	_clear_box()
	board.highlight = {}
	board.sel_pieces = {}
	board.tags = {}
	board.crew_tags = {}
	if pending.is_empty():
		_refresh()
		return
	var req := pending
	phase_lbl.text = {"crew_setup": "Ai posti!", "mplace": "Le uova", "grow": "Crescita", "mmove": "Movimento",
		"mattack": "Pappa!", "grab": "Armi!", "cmove": "Scoperta!" if req.get("discovery", false) else "Movimento",
		"cattack": "All'attacco!", "pick": "Decisione", "loc": "Scegli un'area"}.get(req["type"], "")
	hint_lbl.text = str(req.get("title", ""))
	match req["type"]:
		"pick":
			for i in req["options"].size():
				var ii: int = i
				_add_btn(str(req["options"][i]), func(): _submit(ii), i == 0)
		"loc":
			for a in req["allowed"]:
				board.highlight[a] = UI.CYAN
			_add_text("Tocca un'area evidenziata.")
		"crew_setup":
			_build_setup()
		"mplace":
			_build_mplace()
		"grow":
			_build_grow()
		"mmove":
			_build_mmove()
		"mattack":
			_build_mattack()
		"grab":
			_build_grab()
		"cmove":
			_build_cmove()
		"cattack":
			_build_cattack()
	board.refresh()


# ---- preparazione

func _build_setup() -> void:
	_add_text("Ogni membro dell'equipaggio parte in una delle aree indicate. Tocca una pedina sul tabellone per spostarla nell'area successiva, oppure scegli qui.", UI.MUTED)
	var opts: Dictionary = pending["options"]
	for id in opts:
		var cid := int(id)
		if (opts[id] as Array).size() < 2:
			continue
		var hb := HBoxContainer.new()
		hb.add_child(UI.icon_rect(UI.crew_tex(engine.crew[cid]["k"]), Vector2(40, 40)))
		var l := UI.label(engine.cdef(cid)["short"], 18, UI.CREAM, UI.font_bold)
		l.custom_minimum_size.x = 150
		hb.add_child(l)
		var ob := OptionButton.new()
		ob.custom_minimum_size = Vector2(300, 40)
		for a in opts[id]:
			ob.add_item(engine.area_name(a))
		ob.selected = (opts[id] as Array).find(setup_sel[cid])
		ob.item_selected.connect(func(i):
			setup_sel[cid] = opts[id][i]
			engine.crew[cid]["loc"] = setup_sel[cid]
			board.refresh())
		hb.add_child(ob)
		dec_box.add_child(hb)
	_foot_btn("Suggerisci", func():
		var r: Dictionary = engine.ais[_seat()].decide(engine, _seat(), pending)
		for k in r:
			setup_sel[int(k)] = r[k]
			engine.crew[int(k)]["loc"] = r[k]
		_build_decision())
	_foot_btn("Tutti ai posti!", func(): _submit(setup_sel.duplicate()), true)


func _cycle_setup(cid: int) -> void:
	var opts: Array = pending["options"].get(cid, pending["options"].get(str(cid), []))
	if opts.size() < 2:
		return
	var i := (opts.find(setup_sel[cid]) + 1) % opts.size()
	setup_sel[cid] = opts[i]
	engine.crew[cid]["loc"] = opts[i]
	_build_decision()


func _build_mplace() -> void:
	var left: Dictionary = pending["left"]
	if int(left.get(place_l, 0)) <= 0:
		for k in ["A", "B", "E"]:
			if int(left.get(k, 0)) > 0:
				place_l = k
				break
	_add_text("Una Cosa Verde per area, ognuna accanto a un'area già occupata; mai dove c'è l'equipaggio. Scegli il tipo, poi tocca un'area evidenziata.", UI.MUTED)
	for k in ["A", "B", "E"]:
		var n := int(left.get(k, 0))
		var hb := HBoxContainer.new()
		hb.add_child(UI.icon_rect(UI.mon_tex(k), Vector2(48, 48)))
		var kk: String = k
		var b := UI.button("%s: ne restano %d" % [D.MON[k]["plural"], n], 400, 48)
		b.disabled = n <= 0
		if k == place_l:
			UI.primary(b)
		b.pressed.connect(func():
			place_l = kk
			_build_decision())
		hb.add_child(b)
		dec_box.add_child(hb)
	for a in pending["allowed"]:
		board.highlight[a] = UI.SLIME
	_foot_btn("Suggerisci", func(): _submit(engine.ais[1].decide(engine, 1, pending)))


func _build_grow() -> void:
	var what := {"F": "I Frammenti diventano Piccoli", "E": "Le Uova si schiudono: diventano Piccoli", "B": "I Piccoli diventano Adulti", "A": "Ogni Adulto depone un Uovo"}
	var cnt := {}
	for m in engine.mon:
		if not engine.mon[m]["st"]:
			cnt[engine.mon[m]["l"]] = cnt.get(engine.mon[m]["l"], 0) + 1
	_add_text("Scegli un livello: crescono tutte le Cose Verdi sveglie di quel livello (fin dove bastano le pedine).", UI.MUTED)
	for l in pending["options"]:
		var hb := HBoxContainer.new()
		hb.add_child(UI.icon_rect(UI.mon_tex(l), Vector2(52, 52)))
		var ll: String = l
		var b := UI.button("%s (%d)" % [what[l], cnt.get(l, 0)], 450, 52, 18)
		b.pressed.connect(func(): _submit(ll))
		hb.add_child(b)
		dec_box.add_child(hb)
	_foot_btn("Suggerisci", func(): _submit(engine.ais[1].decide(engine, 1, pending)))


# ---- movimento dei mostri

func _build_mmove() -> void:
	# aree con mostri da muovere
	var src := {}
	for m in engine.mon:
		if engine.mon_mobile(m):
			src[engine.mon[m]["loc"]] = true
	if sel_area == "" or sel_mons.is_empty():
		for a in src:
			board.highlight[a] = UI.SLIME
		_add_text("Tocca un'area con Cose Verdi da muovere (in verde). Gli Adulti fanno 2 aree, i Piccoli 1; si fermano entrando dove c'è equipaggio sveglio o un recinto acceso.", UI.MUTED)
	else:
		_add_text("Scegli quali muovere, poi tocca la destinazione (in azzurro).", UI.MUTED)
		for m in engine.mons_at(sel_area):
			if not engine.mon_mobile(m):
				continue
			var cb := CheckBox.new()
			cb.text = "%s" % engine.mname(m)
			cb.button_pressed = sel_mons.has(m)
			cb.add_theme_font_size_override("font_size", 19)
			var mm: int = m
			cb.toggled.connect(func(on):
				if on and not sel_mons.has(mm):
					sel_mons.append(mm)
				elif not on:
					sel_mons.erase(mm)
				_build_decision())
			dec_box.add_child(cb)
		for m in sel_mons:
			board.sel_pieces["m%d" % m] = true
		var dests := engine.mon_moves(sel_mons)
		for a in dests:
			board.highlight[a] = UI.CYAN
		board.selected_area = sel_area
		_add_btn("Annulla selezione", func():
			sel_area = ""
			sel_mons = []
			_build_decision())
	_foot_btn("Suggerisci una mossa", func(): _submit(engine.ais[1].decide(engine, 1, pending)))
	_foot_btn("Fine movimento", func(): _submit({}), true)


# ---- attacchi dei mostri

func _build_mattack() -> void:
	var areas: Array = pending["areas"]
	if plan_area == "" or not (plan_area in areas):
		plan_area = areas[0]
		plan = {}
		var sug: Dictionary = engine.ais[1].decide(engine, 1, {"type": "mattack", "areas": [plan_area]})
		for g in sug.get("atk", []):
			for m in g[0]:
				plan[int(m)] = int(g[1])
	for a in areas:
		board.highlight[a] = UI.RED
	board.selected_area = plan_area
	_add_text("Scontro in %s. Per ogni Cosa Verde scegli chi attacca (i dadi di chi attacca lo stesso membro si sommano). Tocca un'altra area rossa per passare a quella." % engine.area_name(plan_area), UI.MUTED)
	var crew := engine.crew_at(plan_area)
	var rob := engine.robot_id()
	if crew.has(rob):
		crew = [rob]
		_add_text("C'è Piedipiombo: le Cose Verdi qui possono attaccare solo il Robot!", UI.ORANGE_L)
	var ms := engine.mons_at(plan_area).filter(func(m): return not engine.mon[m]["st"] and not engine.attacked.has(m) and engine.matt(m) > 0)
	for i in ms.size():
		board.tags[ms[i]] = LETTERS[i]
		var hb := HBoxContainer.new()
		hb.add_child(UI.icon_rect(UI.mon_tex(engine.mon[ms[i]]["l"]), Vector2(40, 40)))
		var l := UI.label("%s %s (%d dadi)" % [LETTERS[i], engine.mname(ms[i]), engine.matt(ms[i])], 18, UI.CREAM, UI.font_bold)
		l.custom_minimum_size.x = 210
		hb.add_child(l)
		var ob := OptionButton.new()
		ob.custom_minimum_size = Vector2(270, 40)
		ob.add_item("— non attacca")
		for c in crew:
			ob.add_item("%s (cost. %d)" % [engine.cdef(c)["short"], engine.cdef(c)["con"]])
		var cur: int = plan.get(ms[i], -1)
		ob.selected = crew.find(cur) + 1
		var mm: int = ms[i]
		ob.item_selected.connect(func(k):
			if k == 0:
				plan.erase(mm)
			else:
				plan[mm] = crew[k - 1]
			_plan_summary_m())
		hb.add_child(ob)
		dec_box.add_child(hb)
	_plan_summary_m()
	_foot_btn("Attacca!", func():
		var groups := {}
		for m in plan:
			if not groups.has(plan[m]):
				groups[plan[m]] = []
			groups[plan[m]].append(m)
		var atk := []
		for c in groups:
			atk.append([groups[c], c])
		_submit({"area": plan_area, "atk": atk}), true)
	_foot_btn("Nessun attacco qui", func(): _submit({"area": plan_area, "atk": []}))
	_foot_btn("Fine degli attacchi", func(): _submit({}))


func _plan_summary_m() -> void:
	board.crew_tags = {}
	var dice := {}
	for m in plan:
		dice[plan[m]] = dice.get(plan[m], 0) + engine.matt(m)
	for c in dice:
		var p := AGTAI.p_at_least(dice[c], int(engine.cdef(c)["con"]))
		board.crew_tags[c] = "%dd %d%%" % [dice[c], int(round(p * 100))]
	board.refresh()


# ---- armi

func _build_grab() -> void:
	var acts: Array = pending["actions"]
	_add_text("Ogni membro (non la Mascotte) porta un'arma. Si prende solo ciò che è nella propria area; chi è nella stessa area può passarsi le armi.", UI.MUTED)
	for i in acts.size():
		var a: Dictionary = acts[i]
		var ii: int = i
		var hb := HBoxContainer.new()
		if a.has("c"):
			hb.add_child(UI.icon_rect(UI.crew_tex(engine.crew[a["c"]]["k"]), Vector2(40, 40)))
		if a.has("w"):
			hb.add_child(UI.icon_rect(UI.weapon_tex(engine.wtype(a["w"])), Vector2(40, 40)))
		var b := UI.button(str(a["label"]), 420, 46, 17)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.tooltip_text = str(a["label"])
		b.pressed.connect(func(): _submit(ii))
		hb.add_child(b)
		dec_box.add_child(hb)
	_foot_btn("Suggerisci", func(): _submit(engine.ais[_seat()].decide(engine, _seat(), pending)))
	_foot_btn("Armi pronte!", func(): _submit(-1), true)


# ---- movimento dell'equipaggio

func _build_cmove() -> void:
	var disc: bool = pending.get("discovery", false)
	var movable := []
	for c in engine.board_crew():
		if not engine.crew_moves(c).is_empty() or not engine.special_actions(c).is_empty():
			movable.append(c)
	if sel_crew < 0 or not movable.has(sel_crew):
		sel_crew = -1
		for c in movable:
			board.sel_pieces["c%d" % c] = false
			board.highlight[engine.crew[c]["loc"]] = UI.CREW_C
		if disc:
			_add_text("Muovi uno o due membri dentro un'area con le Cose Verdi: attaccheranno a mani nude. Tocca un membro (in blu le aree con chi può farlo).", UI.MUTED)
		else:
			_add_text("Tocca un membro dell'equipaggio per muoverlo (ognuno una volta). Ci si ferma entrando dove ci sono Adulti o Piccoli svegli o un recinto acceso.", UI.MUTED)
	else:
		var c := sel_crew
		board.sel_pieces["c%d" % c] = true
		var hb := HBoxContainer.new()
		hb.add_child(UI.icon_rect(UI.crew_tex(engine.crew[c]["k"]), Vector2(56, 56)))
		hb.add_child(UI.wrap(UI.label("%s — movimento %d%s" % [engine.cname(c), engine.cdef(c)["mov"],
			(", porta: " + engine.wname(engine.wtype(engine.crew[c]["w"]))) if engine.crew[c]["w"] >= 0 else ""], 18, UI.CREAM, UI.font_bold), 440))
		dec_box.add_child(hb)
		var dests := engine.crew_moves(c)
		for a in dests:
			board.highlight[a] = UI.CYAN
		if not dests.is_empty():
			_add_text("Tocca la destinazione (in azzurro).", UI.MUTED)
		for s in engine.special_actions(c):
			var ss: Dictionary = s
			if ss["act"] == "escape":
				_add_btn(str(ss["label"]), func(): _escape_dialog(ss["b"]))
			else:
				var r := ss.duplicate()
				r.erase("label")
				_add_btn(str(ss["label"]), func(): _submit(r))
		_add_btn("Scegli un altro membro", func():
			sel_crew = -1
			_build_decision())
	_foot_btn("Suggerisci una mossa", func(): _submit(engine.ais[_seat()].decide(engine, _seat(), pending)))
	if not disc or engine.moved.size() >= 1:
		_foot_btn("Fine movimento", func(): _submit({}), true)


func _escape_dialog(b: String) -> void:
	_clear_box()
	var here := engine.crew_at(b).filter(func(x): return engine.awake(x))
	var cap: int = D.BOATS[b]["cap"]
	_add_text("Chi sale su %s? %s Il Robot e la Mascotte non contano. Fuggire regala alle Cose Verdi 111 punti (55,5 se la nave sta per autodistruggersi)." % [D.BOATS[b]["name"], ("Posti: %d." % cap) if cap > 0 else "Posti illimitati."], UI.ORANGE_L)
	var chosen := {}
	for c in here:
		var cb := CheckBox.new()
		cb.text = engine.cname(c)
		cb.button_pressed = true
		chosen[c] = true
		var cc: int = c
		cb.toggled.connect(func(on):
			if on:
				chosen[cc] = true
			else:
				chosen.erase(cc))
		dec_box.add_child(cb)
	_foot_btn("Partenza!", func():
		var ids := chosen.keys()
		if not engine.boat_room(b, ids):
			status_lbl.text = "Troppi a bordo!"
			return
		_submit({"act": "escape", "b": b, "ids": ids}), true)
	_foot_btn("Annulla", func(): _build_decision())


# ---- attacchi dell'equipaggio

func _build_cattack() -> void:
	var areas: Array = pending["areas"]
	for a in areas:
		board.highlight[a] = UI.RED
	if plan_area == "" or not (plan_area in areas):
		_add_text("Tocca un'area in rosso per preparare l'attacco: chi può colpirla, con le mani o con l'arma.", UI.MUTED)
		_foot_btn("Suggerisci un attacco", func(): _submit(engine.ais[_seat()].decide(engine, _seat(), pending)))
		_foot_btn("Fine degli attacchi", func(): _submit({}), true)
		return
	board.selected_area = plan_area
	var ms := engine.mons_at(plan_area)
	for i in ms.size():
		board.tags[ms[i]] = LETTERS[i % LETTERS.length()]
	_add_text("Attacco in %s. Tutte le dichiarazioni si risolvono insieme: le armi nuove pescano un gettone (se ne provi due insieme, il gettone vale solo per quest'attacco)." % engine.area_name(plan_area), UI.MUTED)
	var cands := engine.attackers_for(plan_area)
	var by_crew := {}
	for cm in cands:
		if not by_crew.has(cm[0]):
			by_crew[cm[0]] = []
		by_crew[cm[0]].append(cm[1])
	for c in by_crew:
		var opts := [["—", null]]
		var foes: Array = engine.enemies_at(plan_area, c) if engine.mutiny() else []
		for usew in by_crew[c]:
			if usew:
				var t := engine.wtype(engine.crew[c]["w"])
				var kind: String = D.WEAPONS[t]["kind"]
				var k := engine.effect_of(t)
				var eff := (" [" + engine.chit_name(k) + "]") if k != "" else " [?]"
				if kind == "single":
					for i in ms.size():
						opts.append(["%s su %s %s%s" % [D.WEAPONS[t]["short"], LETTERS[i % 26], engine.mname(ms[i]), eff], [c, true, ms[i]]])
					var kc: String = D.VS_CREW.get(t, "none")
					for f in foes:
						opts.append(["%s su %s [%s]" % [D.WEAPONS[t]["short"], engine.cdef(f)["short"], {"kill3": "3 dadi", "kill4": "4 dadi", "kill5": "5 dadi", "stun5": "stordisce", "slow": "rallenta", "none": "nessun effetto"}[kc]], [c, true, f + D.CREW_T]])
				elif not ms.is_empty() or kind == "blast":
					opts.append(["%s su tutta l'area%s" % [D.WEAPONS[t]["short"], eff], [c, true, -1]])
			else:
				for i in ms.size():
					opts.append(["Mani nude (%dd) su %s %s" % [engine.cdef(c)["att"], LETTERS[i % 26], engine.mname(ms[i])], [c, false, ms[i]]])
				for f in foes:
					opts.append(["Mani nude (%dd) su %s (cost. %d)" % [engine.cdef(c)["att"], engine.cdef(f)["short"], engine.cdef(f)["con"]], [c, false, f + D.CREW_T]])
		var hb := HBoxContainer.new()
		hb.add_child(UI.icon_rect(UI.crew_tex(engine.crew[c]["k"]), Vector2(40, 40)))
		var ob := OptionButton.new()
		ob.custom_minimum_size = Vector2(470, 40)
		ob.clip_text = true
		for o in opts:
			ob.add_item("%s: %s" % [engine.cdef(c)["short"], o[0]])
		var cur = plan.get(c, null)
		var sel := 0
		for i in opts.size():
			if opts[i][1] != null and cur != null and opts[i][1] == cur:
				sel = i
		ob.selected = sel
		var cc: int = c
		ob.item_selected.connect(func(i):
			if opts[i][1] == null:
				plan.erase(cc)
			else:
				plan[cc] = opts[i][1]
			_plan_summary_c())
		hb.add_child(ob)
		dec_box.add_child(hb)
	_plan_summary_c()
	_foot_btn("Suggerisci", func():
		plan = {}
		for x in _sug_plan(plan_area):
			plan[int(x[0])] = x
		_build_decision())
	_foot_btn("Attacca!", func():
		var atk := plan.values()
		if atk.is_empty():
			status_lbl.text = "Nessun attacco dichiarato."
			return
		_submit({"area": plan_area, "atk": atk}), true)
	_foot_btn("Cambia area", func():
		plan_area = ""
		plan = {}
		_build_decision())
	_foot_btn("Fine degli attacchi", func(): _submit({}))


func _plan_summary_c() -> void:
	# probabilità indicativa di uccidere ogni mostro con i dadi «a mani nude» e le armi note che uccidono
	board.crew_tags = {}
	var kill := {}
	var fk := {}
	for c in plan:
		var x: Array = plan[c]
		if int(x[2]) >= D.CREW_T:
			var f: int = int(x[2]) - D.CREW_T
			var kc: String = "hand" if not x[1] else D.VS_CREW.get(engine.wtype(engine.crew[c]["w"]), "none")
			if kc == "hand":
				fk[f] = fk.get(f, 0) + int(engine.cdef(c)["att"])
			elif kc.begins_with("kill"):
				fk[f] = fk.get(f, 0) + int(kc.substr(4))
			board.crew_tags[c] = "✓"
			continue
		if not x[1]:
			kill[x[2]] = kill.get(x[2], 0) + int(engine.cdef(c)["att"])
		else:
			var k := engine.effect_of(engine.wtype(engine.crew[c]["w"]))
			if k.begins_with("kill"):
				var targets := [x[2]] if x[2] >= 0 else engine.mons_at(plan_area)
				for m in targets:
					kill[m] = kill.get(m, 0) + int(k.substr(4))
		board.crew_tags[c] = "✓"
	var parts := []
	for m in kill:
		if engine.mon.has(m):
			parts.append("%s %s: %dd → %d%%" % [board.tags.get(m, "?"), engine.mname(m), kill[m], int(round(AGTAI.p_at_least(kill[m], engine.mcon(m)) * 100))])
	for f in fk:
		var pc := int(round(AGTAI.p_at_least(fk[f], int(engine.cdef(f)["con"])) * 100))
		parts.append("%s: %dd → %d%%" % [engine.cdef(f)["short"], fk[f], pc])
		board.crew_tags[f] = "%d%%" % pc
	status_lbl.text = ", ".join(parts)
	board.refresh()


# ================================================================ clic sul tabellone

func _on_piece_click(kind: String, id: int) -> void:
	if pending.is_empty():
		return
	var t: String = pending["type"]
	if kind == "c":
		if t == "crew_setup":
			_cycle_setup(id)
			return
		if t == "cmove":
			if not engine.crew_moves(id).is_empty() or not engine.special_actions(id).is_empty():
				sel_crew = id
				_build_decision()
				return
		_on_area_click(engine.crew[id]["loc"])
		return
	if kind == "m":
		if t == "mmove" and sel_area == engine.mon[id]["loc"] and engine.mon_mobile(id):
			if sel_mons.has(id):
				sel_mons.erase(id)
			else:
				sel_mons.append(id)
			_build_decision()
			return
		_on_area_click(engine.mon[id]["loc"])
		return
	if kind == "w":
		_on_area_click(engine.wpn[id]["loc"])


func _on_area_click(a: String) -> void:
	_info(a)
	if pending.is_empty():
		board.selected_area = a
		board.refresh()
		return
	match pending["type"]:
		"loc":
			if a in pending["allowed"]:
				_submit(a)
		"mplace":
			if a in pending["allowed"]:
				_submit({"area": a, "l": place_l})
		"mmove":
			if not sel_mons.is_empty() and engine.mon_moves(sel_mons).has(a):
				_submit({"ids": sel_mons.duplicate(), "to": a})
				return
			var mob := engine.mons_at(a).filter(func(m): return engine.mon_mobile(m))
			if not mob.is_empty():
				sel_area = a
				sel_mons = mob
				_build_decision()
		"mattack":
			if a in pending["areas"]:
				plan_area = ""
				plan = {}
				var save: Array = pending["areas"]
				pending["areas"] = [a] + save.filter(func(x): return x != a)
				_build_decision()
				pending["areas"] = save
		"cmove":
			if sel_crew >= 0 and engine.crew_moves(sel_crew).has(a):
				_submit({"c": sel_crew, "to": a})
				return
			var who := engine.crew_at(a).filter(func(c): return not engine.crew_moves(c).is_empty() or not engine.special_actions(c).is_empty())
			if who.size() == 1:
				sel_crew = who[0]
				_build_decision()
			elif who.size() > 1:
				_clear_box()
				_add_text("Chi muovi da %s?" % engine.area_name(a), UI.MUTED)
				for c in who:
					var cc: int = c
					_add_btn(engine.cname(c), func():
						sel_crew = cc
						_build_decision())
				_add_btn("Indietro", func(): _build_decision())
		"cattack":
			if a in pending["areas"]:
				plan_area = a
				plan = {}
				for x in _sug_plan(a):
					plan[int(x[0])] = x
				_build_decision()


# ================================================================ menu, regole, fine

func _confirm_menu() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "Abbandonare la partita e tornare al menu?"
	dlg.ok_button_text = "Sì"
	dlg.cancel_button_text = "No"
	add_child(dlg)
	dlg.confirmed.connect(func():
		engine.abort = true
		if online != null:
			online.alive = false
		if pending.size() > 0:
			engine.provide_decision(null)
		main.show_menu())
	dlg.popup_centered()


func _show_rules_popup() -> void:
	var p := preload("res://scripts/ui/rules_view.gd").new()
	p.overlay = true
	add_child(p)


func _on_end(res: Dictionary) -> void:
	pending = {}
	_clear_box()
	if online != null:
		online.finish()
	if engine.abort:
		return
	_refresh()
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.7)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UI.comic_style(UI.CREAM, 20))
	pc.position = Vector2(460, 180)
	pc.custom_minimum_size = Vector2(1000, 0)
	shade.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	pc.add_child(vb)
	var w: String = res.get("winner", "")
	var t := UI.title({"crew": "Vince l'Equipaggio!", "mon": "Vincono le Cose Verdi!", "draw": "Pareggio!",
		"cap": "Vince il Capitano!", "fo": "Vince il Primo Ufficiale!"}.get(w, "Fine"), 72,
		UI.BLUE if w in ["crew", "cap"] else (UI.GREEN if w == "mon" else (UI.ORANGE if w == "fo" else UI.YELLOW)))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var r0 := UI.label(str(res.get("reason", "")), 26, UI.INK, UI.font_bold)
	r0.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(UI.wrap(r0, 960))
	var vp: Array = res.get("vp", [0, 0])
	var sc := UI.heading("Punti vittoria — Equipaggio: %s   ·   Cose Verdi: %s" % [AGTEngine._fmt(vp[0]), AGTEngine._fmt(vp[1])], 32, UI.ORANGE)
	if vp.size() >= 3:
		sc.text = "Punti — Capitano: %s   ·   Primo Ufficiale: %s   ·   Cose Verdi: %s" % [AGTEngine._fmt(vp[0]), AGTEngine._fmt(vp[2]), AGTEngine._fmt(vp[1])]
	sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sc)
	for bt in engine.boats:
		var names := []
		for id in bt["survivors"]:
			names.append(engine.cdef(id)["short"])
		var txt: String = "%s: %s" % [D.BOATS[bt["b"]]["name"].capitalize(), ("a casa con " + ", ".join(names)) if not names.is_empty() else "persa nello spazio"]
		var l := UI.label(txt, 22, UI.INK)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(l)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	var again := UI.primary(UI.button("Torna al menu", 320, 64, 26))
	again.pressed.connect(func(): main.show_menu())
	row.add_child(again)
	var stay := UI.button("Guarda la nave", 300, 64, 22)
	stay.pressed.connect(func(): shade.queue_free())
	row.add_child(stay)
	var lg := UI.button("Diario", 200, 64, 22)
	lg.pressed.connect(func():
		shade.queue_free()
		log_panel.visible = true)
	row.add_child(lg)
	vb.add_child(row)


# ================================================================ online

func online_waiting(s: int, slow: bool) -> void:
	if s < 0:
		status_lbl.text = ""
	else:
		status_lbl.text = "Aspetto %s…%s" % [engine.pname(s), " (lento)" if slow else ""]


func online_status(t: String) -> void:
	status_lbl.text = t


func online_cancel_decision(t: String) -> void:
	pending = {}
	_clear_box()
	status_lbl.text = t
	_refresh()


func online_caught_up() -> void:
	status_lbl.text = "Partita ripresa."

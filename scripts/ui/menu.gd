extends Control
## Menu principale: chi guida l'Equipaggio e chi le Cose Verdi (persona o IA), varianti, velocità
## dell'IA e gioco online.

const D = preload("res://scripts/data/agt_data.gd")
const MODES := ["Persona", "IA facile", "IA normale", "IA difficile"]
const SEAT_KEYS := ["crew", "mon"]
const SEAT_NAMES := ["Equipaggio", "Cose Verdi"]
const VARIANTS := [
	["extra_adult", "Un Adulto in più per le Cose Verdi", "Il regolamento lo suggerisce per aiutare le Cose Verdi se perdono troppo spesso."],
	["beamer2", "Comunicatore a due frequenze", "Variante per aiutare l'Equipaggio: se il primo effetto del Raggio comunicatore delude, si può provare\nl'altra frequenza (un nuovo gettone) e poi scegliere ogni volta il migliore dei due."],
	["grow_eggs", "«Cresce» fa deporre le uova", "Regola delle vecchie edizioni TSR: un Adulto colpito da «Cresce» depone un Uovo.\nNell'8ª edizione no."],
]

var main
var page: Control
var modes := {"crew": 0, "mon": 2}
var names := {"crew": "Equipaggio", "mon": "Cose Verdi"}
var speed := 1
var view3d := 1
var variants := {}
var msg: Label
var seats_box: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var st: Dictionary = main.menu_state
	if not st.is_empty():
		modes = st["modes"].duplicate()
		names = st["names"].duplicate()
		speed = st["speed"]
		variants = st["variants"].duplicate()
		view3d = st.get("view3d", 1)
	page = Control.new()
	page.size = Vector2(1920, 1080)
	add_child(page)
	_center.call_deferred()
	get_viewport().size_changed.connect(_center)

	# a sinistra: il titolo come sulla scatola e il mostro
	var t1 := UI.title("The Awful", 92)
	t1.position = Vector2(70, 40)
	page.add_child(t1)
	var t2 := UI.title("Green Things", 104, UI.SLIME)
	t2.position = Vector2(60, 140)
	page.add_child(t2)
	var t3 := UI.title("from Outer Space", 66)
	t3.position = Vector2(90, 262)
	page.add_child(t3)
	var monster := UI.icon_rect(UI.tex("res://assets/misc/mostro.png"), Vector2(400, 420))
	monster.position = Vector2(150, 360)
	page.add_child(monster)
	_wobble(monster)
	var bubble := PanelContainer.new()
	bubble.add_theme_stylebox_override("panel", UI.comic_style(UI.CREAM, 18))
	bubble.position = Vector2(60, 800)
	bubble.custom_minimum_size = Vector2(620, 0)
	page.add_child(bubble)
	var tag := UI.label("Sulla Znutar le uova si schiudono, i piccoli crescono e gli adulti hanno fame.\nL'equipaggio ha solo armi mai provate… e un robot.", 22, UI.INK, UI.font_bold)
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.add_child(tag)

	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", UI.dark_style(14, 0.92))
	right.position = Vector2(760, 60)
	right.custom_minimum_size = Vector2(1100, 760)
	page.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 14)
	right.add_child(rv)
	rv.add_child(UI.heading("Chi gioca", 40))
	seats_box = VBoxContainer.new()
	seats_box.add_theme_constant_override("separation", 10)
	rv.add_child(seats_box)
	rv.add_child(HSeparator.new())
	rv.add_child(UI.heading("Varianti", 34))
	for v in VARIANTS:
		var cb := CheckBox.new()
		cb.text = v[1]
		cb.tooltip_text = v[2]
		cb.button_pressed = variants.get(v[0], false)
		cb.add_theme_font_size_override("font_size", 21)
		var key: String = v[0]
		cb.toggled.connect(func(on): variants[key] = on)
		rv.add_child(cb)
	rv.add_child(_segmented("Velocità IA", ["Lenta", "Normale", "Veloce", "Istantanea"], speed, func(k): speed = k, 160))
	rv.add_child(_segmented("Vista", ["2D: il tabellone", "3D: le miniature"], view3d, func(k): view3d = k, 330))

	msg = UI.label("", 24, UI.ORANGE_L, UI.font_bold)
	msg.position = Vector2(760, 1000)
	page.add_child(msg)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 18)
	btns.position = Vector2(760, 856)
	page.add_child(btns)
	var b_start := _big_button("Si parte!", 380, true)
	b_start.pressed.connect(_on_start)
	btns.add_child(b_start)
	var b_rules := _big_button("Regole", 250)
	b_rules.pressed.connect(func():
		_store()
		main.show_rules())
	btns.add_child(b_rules)
	var b_online := _big_button("Gioca online", 360)
	b_online.pressed.connect(_online_panel)
	btns.add_child(b_online)
	if not OS.has_feature("web"):
		var b_quit := _big_button("Esci", 150)
		b_quit.pressed.connect(func(): get_tree().quit())
		page.add_child(b_quit)
		b_quit.position = Vector2(1710, 950)
	var credits := UI.label("The Awful Green Things from Outer Space © Tom Wham · Steve Jackson Games · versione digitale per uso privato · F11 schermo intero", 17, UI.MUTED)
	credits.position = Vector2(760, 1046)
	page.add_child(credits)
	_refresh_seats()
	if not main.lobby.is_empty():
		_online_panel.call_deferred()


func _wobble(n: Control) -> void:
	n.pivot_offset = n.size * Vector2(0.5, 1.0)
	var tw := n.create_tween().set_loops()
	tw.tween_property(n, "rotation", 0.05, 1.1).set_trans(Tween.TRANS_SINE)
	tw.tween_property(n, "rotation", -0.05, 1.1).set_trans(Tween.TRANS_SINE)


func _center() -> void:
	var vs := get_viewport_rect().size
	page.position = ((vs - page.size) * 0.5).floor()
	page.position.y = maxf(0.0, page.position.y)


func _store() -> void:
	main.menu_state = {"modes": modes.duplicate(), "names": names.duplicate(), "speed": speed, "variants": variants.duplicate(), "view3d": view3d}


func _refresh_seats() -> void:
	for c in seats_box.get_children():
		c.queue_free()
	for i in 2:
		var k: String = SEAT_KEYS[i]
		var col: Color = UI.BLUE_D if i == 0 else UI.GREEN_D
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UI.comic_style(col, 12))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 14)
		row.add_child(hb)
		hb.add_child(UI.icon_rect(UI.crew_tex("captain") if i == 0 else UI.mon_tex("A"), Vector2(80, 80)))
		var vb := VBoxContainer.new()
		vb.custom_minimum_size.x = 330
		vb.add_child(UI.heading("L'Equipaggio della Znutar" if i == 0 else "Le Cose Verdi", 28, UI.YELLOW if i == 0 else UI.SLIME))
		var le := LineEdit.new()
		le.text = names[k]
		le.max_length = 20
		le.custom_minimum_size = Vector2(300, 42)
		le.add_theme_font_size_override("font_size", 20)
		var kk: String = k
		le.text_changed.connect(func(t): names[kk] = t)
		vb.add_child(le)
		hb.add_child(vb)
		var bar := HBoxContainer.new()
		bar.add_theme_constant_override("separation", 6)
		bar.alignment = BoxContainer.ALIGNMENT_CENTER
		hb.add_child(bar)
		for m in MODES.size():
			var b := Button.new()
			b.text = MODES[m]
			b.custom_minimum_size = Vector2(150, 56)
			b.add_theme_font_size_override("font_size", 19)
			var on: bool = modes[k] == m
			b.add_theme_stylebox_override("normal", UI.panel_style(UI.YELLOW if on else Color("#0f2a1a"), UI.INK, 3, 6))
			b.add_theme_color_override("font_color", UI.INK if on else UI.TEXT)
			b.add_theme_color_override("font_hover_color", UI.INK if on else UI.YELLOW_L)
			var mm := m
			b.pressed.connect(func():
				modes[kk] = mm
				msg.text = ""
				_refresh_seats())
			bar.add_child(b)
		seats_box.add_child(row)


func _segmented(label_text: String, items: Array, cur: int, cb: Callable, w := 200) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	var l := UI.label(label_text, 22, Color.WHITE, UI.font_bold)
	l.custom_minimum_size = Vector2(170, 0)
	hb.add_child(l)
	var btns := []
	for k in range(items.size()):
		var b := Button.new()
		b.text = items[k]
		b.custom_minimum_size = Vector2(w, 48)
		b.add_theme_font_size_override("font_size", 19)
		hb.add_child(b)
		btns.append(b)
	var paint := func(sel: int):
		for k in range(btns.size()):
			var on: bool = k == sel
			btns[k].add_theme_stylebox_override("normal", UI.panel_style(UI.YELLOW if on else Color("#0f2a1a"), UI.INK, 3, 6))
			btns[k].add_theme_color_override("font_color", UI.INK if on else UI.TEXT)
			btns[k].add_theme_color_override("font_hover_color", UI.INK if on else UI.YELLOW_L)
	for k in range(btns.size()):
		btns[k].pressed.connect(func():
			cb.call(k)
			paint.call(k))
	paint.call(cur)
	return hb


func _big_button(text: String, w: float, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 84)
	b.add_theme_font_override("font", UI.font_comic)
	b.add_theme_font_size_override("font_size", 40)
	if primary:
		UI.primary(b)
	return b


## Configurazione scelta nel menu (anche quella che, online, viaggia agli altri).
func _config() -> Dictionary:
	var seats := []
	for i in 2:
		var k: String = SEAT_KEYS[i]
		var m: int = modes[k]
		var nm: String = names[k].strip_edges()
		if nm == "":
			nm = SEAT_NAMES[i]
		seats.append({"name": nm, "ai": m != 0, "level": maxi(0, m - 1)})
	var speeds := [1.2, 0.6, 0.2, 0.0]
	var opts := {}
	for v in VARIANTS:
		if variants.get(v[0], false):
			opts[v[0]] = true
	return {"seats": seats, "ai_delay": speeds[speed], "opts": opts, "view3d": view3d == 1}


func _on_start() -> void:
	_store()
	main.start_game(_config())


# =================================================================== online

var on_panel: Control
var on_name: LineEdit
var on_code: LineEdit
var on_lbl: Label
var on_start: Button
var host_side := 0


func _online_panel() -> void:
	if is_instance_valid(on_panel):
		on_panel.queue_free()
	on_panel = Control.new()
	on_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	on_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(on_panel)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.8)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	on_panel.add_child(shade)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.dark_style(14, 0.98))
	box.position = page.position + Vector2(560, 120)
	box.custom_minimum_size = Vector2(800, 0)
	on_panel.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	box.add_child(vb)
	vb.add_child(UI.title("Gioca online", 56))
	var info := UI.label("Chi crea la stanza sceglie qui quale lato gioca: l'altro è per l'amico, che entra con il codice. Le varianti scelte nel menu valgono per tutti e due.", 20, UI.MUTED)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(760, 0)
	vb.add_child(info)
	var ses: Dictionary = main.get_net().load_session()
	on_name = _line("Il tuo nome", 20)
	on_name.text = str(ses.get("name", ""))
	vb.add_child(on_name)
	vb.add_child(_segmented("Tu giochi", SEAT_NAMES, host_side, func(k): host_side = k, 250))
	var b_create := UI.button("Crea una stanza", 0, 60, 24)
	b_create.pressed.connect(_online_create)
	vb.add_child(b_create)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	on_code = _line("Codice", 4)
	on_code.custom_minimum_size.x = 220
	on_code.text_changed.connect(func(t):
		on_code.text = t.to_upper()
		on_code.caret_column = t.length())
	row.add_child(on_code)
	var b_join := UI.button("Entra", 200, 60, 24)
	b_join.pressed.connect(_online_join)
	row.add_child(b_join)
	vb.add_child(row)
	on_lbl = UI.label("", 21, Color.WHITE)
	on_lbl.custom_minimum_size = Vector2(760, 120)
	on_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(on_lbl)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	on_start = _big_button("Inizia online", 420, true)
	on_start.pressed.connect(_online_start)
	on_start.visible = main.lobby.get("role", "") == "host"
	row2.add_child(on_start)
	var b_close := _big_button("Indietro", 300)
	b_close.pressed.connect(func(): on_panel.queue_free())
	row2.add_child(b_close)
	vb.add_child(row2)
	if not main.lobby.is_empty():
		on_code.text = main.lobby["code"]
		on_lbl.text = "Stanza %s…" % main.lobby["code"]
	elif str(ses.get("room", "")) != "":
		on_code.text = str(ses["room"])
		on_lbl.text = "Eri nella stanza %s: premi Entra per rientrare." % ses["room"]


func _line(ph: String, maxlen: int) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = ph
	le.max_length = maxlen
	le.custom_minimum_size = Vector2(0, 60)
	le.add_theme_font_size_override("font_size", 28)
	return le


func _say(t: String) -> void:
	if is_instance_valid(on_lbl):
		on_lbl.text = t


func _seats_text(room: Dictionary) -> String:
	var seats := Net._as_dict(room.get("seats", {}))
	var parts := []
	for idx in room.get("open", []):
		var k := str(int(idx))
		var who := str(seats[k].get("name", "?")) if seats.has(k) and seats[k] is Dictionary else "libero"
		parts.append("%s: %s" % [SEAT_NAMES[int(idx)], who])
	return ", ".join(parts)


func _online_create() -> void:
	var nm := on_name.text.strip_edges()
	if nm == "":
		_say("Scrivi il tuo nome.")
		return
	var seats := [host_side, 1 - host_side]
	modes[SEAT_KEYS[0]] = 0
	modes[SEAT_KEYS[1]] = 0
	_store()
	_say("Creo la stanza…")
	var net: Net = main.get_net()
	var code := await net.create_room(nm, seats)
	if code == "":
		_say("Non riesco a creare la stanza.\n%s" % net.last_error)
		return
	main.lobby = {"role": "host", "code": code, "seat": seats[0]}
	net.remember_room(code, seats[0])
	net._save({"name": nm})
	if is_instance_valid(on_code):
		on_code.text = code
	if is_instance_valid(on_start):
		on_start.visible = true
	_lobby_poll(code)


func _online_join() -> void:
	var code := on_code.text.strip_edges().to_upper()
	var nm := on_name.text.strip_edges()
	if nm == "" or code.length() != 4:
		_say("Scrivi il tuo nome e il codice di 4 lettere.")
		return
	_say("Entro nella stanza %s…" % code)
	var net: Net = main.get_net()
	var seat := await net.join_room(code, nm)
	if seat == -2:
		_say("Stanza %s non trovata, oppure la partita è già iniziata.%s" % [code, ("\n" + net.last_error) if net.last_error != "" else ""])
		return
	if seat == -1:
		_say("Nella stanza %s non ci sono posti liberi." % code)
		return
	var room: Dictionary = net.last_room
	main.lobby = {"role": "host" if room.get("host", "") == net.uid else "guest", "code": code, "seat": seat}
	net.remember_room(code, seat)
	net._save({"name": nm})
	if room.get("status", "") in ["playing", "over"] and room.has("game"):
		_say("Rientro nella partita della stanza %s…" % code)
		_begin(room["game"], true)
		return
	if is_instance_valid(on_start):
		on_start.visible = main.lobby["role"] == "host"
	_lobby_poll(code)


func _lobby_poll(code: String) -> void:
	var net: Net = main.get_net()
	while is_inside_tree() and main.lobby.get("code", "") == code:
		var room := await net.room(code)
		if not is_inside_tree() or main.lobby.get("code", "") != code:
			return
		if room.is_empty():
			_say("La stanza %s non esiste più." % code)
			main.lobby = {}
			return
		if main.lobby["role"] == "host":
			_say("Stanza [ %s ]: dai il codice al tuo amico.\nPosti: %s.\nQuando c'è premi Inizia online (un posto rimasto libero lo gioca l'IA)." % [code, _seats_text(room)])
		else:
			if room.get("status", "") == "playing" and room.has("game"):
				_begin(room["game"], false)
				return
			_say("Sei nella stanza [ %s ] (giochi: %s).\nAspetta che chi l'ha creata avvii la partita." % [code, SEAT_NAMES[int(main.lobby["seat"])]])
		await get_tree().create_timer(2.0).timeout


## Chi ha creato la stanza avvia: giocatori, varianti e seme valgono per tutti.
func _online_start() -> void:
	var code: String = main.lobby["code"]
	var net: Net = main.get_net()
	var room := await net.room(code)
	if room.is_empty():
		_say("La stanza %s non esiste più." % code)
		main.lobby = {}
		return
	var seats_db := Net._as_dict(room.get("seats", {}))
	var cfg := _config()
	var my_seat := int(main.lobby["seat"])
	if my_seat >= cfg["seats"].size() or not seats_db.has(str(my_seat)) or cfg["seats"][my_seat]["ai"]:
		_say("Hai cambiato i giocatori dopo aver creato la stanza: creane una nuova.")
		return
	for i in cfg["seats"].size():
		var k := str(i)
		if seats_db.has(k) and seats_db[k] is Dictionary and not cfg["seats"][i]["ai"]:
			cfg["seats"][i]["name"] = str(seats_db[k].get("name", cfg["seats"][i]["name"]))
		else:
			cfg["seats"][i]["ai"] = true
	cfg["seed"] = 1 + randi() % 2000000000
	var g := {"cfg": var_to_str(cfg)}
	if not await net.start_room(code, g):
		_say("Non riesco ad avviare la partita (%s)." % net.last_error)
		return
	_begin(g, false)


func _begin(g: Dictionary, rejoin: bool) -> void:
	var net: Net = main.get_net()
	var lob: Dictionary = main.lobby
	var backlog: Array = []
	if rejoin:
		backlog = await net.get_acts(lob["code"])
		net.set_away(lob["code"], int(lob["seat"]), false)
	var cfg = str_to_var(str(g.get("cfg", "")))
	if not (cfg is Dictionary):
		_say("Configurazione della partita non valida.")
		return
	var ses := OnlineSession.new()
	ses.setup(net, lob["code"], int(lob["seat"]), lob["role"], backlog)
	cfg["online"] = ses
	main.lobby = {}
	main.start_game(cfg)

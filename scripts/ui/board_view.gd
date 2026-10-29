class_name BoardView
extends Control
## Il tabellone della Znutar con le pedine. Rotella per lo zoom, trascina col tasto destro (o con il
## sinistro sul vuoto) per spostare. Le aree si evidenziano quando si possono scegliere.

signal area_clicked(a: String)
signal piece_clicked(kind: String, id: int)
signal area_hovered(a: String)

const D = preload("res://scripts/data/agt_data.gd")
const TOK := 60.0
const WTOK := 34.0

var view
var e: AGTEngine
var tex: Texture2D
var zoom := 1.0
var base_scale := 0.7
var offset := Vector2.ZERO
var highlight := {}          # area -> colore
var selected_area := ""
var sel_pieces := {}         # "c12" / "m105" -> true
var tags := {}               # id mostro -> lettera (pianificazione attacchi)
var crew_tags := {}          # id membro -> testo
var hover := ""
var pulse := 0.0
var flash := {}              # area -> tempo residuo
var _hits: Array = []
var _drag := false
var _drag_moved := false
var _drag_from := Vector2.ZERO


func _ready() -> void:
	tex = UI.tex("res://assets/board/nave.webp")
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(fit)


func set_engine(eng: AGTEngine) -> void:
	e = eng
	fit()


func refresh() -> void:
	queue_redraw()


func fit() -> void:
	if tex == null or size.x < 10:
		return
	var bb := _bounds()
	base_scale = minf(size.x / bb.size.x, size.y / bb.size.y)
	zoom = 1.0
	offset = (size - bb.size * base_scale) * 0.5 - bb.position * base_scale
	queue_redraw()


## Rettangolo da inquadrare: il tabellone, più lo scafo e lo spazio con le regole «Fuori dalla Znutar».
func _bounds() -> Rect2:
	var r := Rect2(Vector2.ZERO, tex.get_size())
	if e != null and e.outside():
		for a in e.AR:
			if e.is_out(a):
				for q in e.AR[a]["poly"]:
					r = r.expand(Vector2(q[0], q[1]))
	return r


func sc() -> float:
	return base_scale * zoom


func to_screen(p: Vector2) -> Vector2:
	return offset + p * sc()


func to_board(p: Vector2) -> Vector2:
	return (p - offset) / sc()


func area_at(p: Vector2) -> String:
	if e == null:
		return ""
	var b := to_board(p)
	for a in e.AR:
		var poly := PackedVector2Array()
		for q in e.AR[a]["poly"]:
			poly.append(Vector2(q[0], q[1]))
		if Geometry2D.is_point_in_polygon(b, poly):
			return a
	return ""


func area_center(a: String) -> Vector2:
	var c: Array = e.AR[a]["center"]
	return to_screen(Vector2(c[0], c[1]))


func _process(dt: float) -> void:
	pulse += dt
	var any := not highlight.is_empty() or not flash.is_empty()
	for a in flash.keys():
		flash[a] -= dt
		if flash[a] <= 0:
			flash.erase(a)
	if any:
		queue_redraw()


func _screen_poly(a: String) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for q in e.AR[a]["poly"]:
		poly.append(to_screen(Vector2(q[0], q[1])))
	return poly


func _draw() -> void:
	_hits = []
	if tex == null:
		return
	var outer := e != null and e.outside()
	if outer:
		# lo spazio attorno alla nave
		for a in e.AR:
			if e.is_space(a):
				var sp := _screen_poly(a)
				draw_colored_polygon(sp, Color("#081428"))
				var spl := sp.duplicate()
				spl.append(sp[0])
				draw_polyline(spl, Color("#2d4a7a"), 2.0)
	draw_texture_rect(tex, Rect2(offset, tex.get_size() * sc()), false)
	if e == null:
		return
	if outer:
		for a in e.AR:
			if e.AR[a]["kind"] == "scafo":
				var kp := _screen_poly(a)
				draw_colored_polygon(kp, Color(0.62, 0.68, 0.78, 0.55))
				var kpl := kp.duplicate()
				kpl.append(kp[0])
				draw_polyline(kpl, Color("#20304a"), 2.0)
				var lk: String = str(e.AR[a].get("airlock", ""))
				if lk != "":
					var cc: Array = e.AR[a]["center"]
					_badge(to_screen(Vector2(cc[0], cc[1])) + Vector2(0, -TOK * sc() * 0.62), "🔒" if e.locked.has(lk) else "⇅", Color("#cfe3ff"))
			elif e.is_space(a):
				var c2: Array = e.AR[a]["center"]
				var t: String = String(e.AR[a]["name"]).to_upper()
				var fs := int(clampf(20.0 * zoom, 14, 30))
				var tw := UI.font_comic.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				draw_string(UI.font_comic, to_screen(Vector2(c2[0], c2[1])) - Vector2(tw * 0.5, 0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#5d7fb8"))
	var glow := 0.5 + 0.5 * sin(pulse * 4.0)
	for a in highlight:
		var poly := _screen_poly(a)
		var col: Color = highlight[a]
		draw_colored_polygon(poly, Color(col, 0.16 + 0.14 * glow))
		var pl := poly.duplicate()
		pl.append(poly[0])
		draw_polyline(pl, Color(col, 0.95), 3.0 + 2.0 * glow)
	for a in flash:
		var poly := _screen_poly(a)
		draw_colored_polygon(poly, Color(1, 0.9, 0.3, clampf(flash[a], 0, 1) * 0.45))
	if selected_area != "" and e.AR.has(selected_area):
		var pl := _screen_poly(selected_area)
		pl.append(pl[0])
		draw_polyline(pl, UI.INK, 9.0)
		draw_polyline(pl, UI.YELLOW, 5.0)
	if hover != "" and e.AR.has(hover):
		var pl2 := _screen_poly(hover)
		pl2.append(pl2[0])
		draw_polyline(pl2, Color(1, 1, 1, 0.55), 2.0)
	for a in e.pods_gone:
		draw_colored_polygon(_screen_poly(a), Color(0.05, 0.05, 0.05, 0.8))
	for a in e.webs:
		_draw_web(a)
	var holes_done := {}
	for a in e.extra_adj:
		for b in e.extra_adj[a]:
			var key: String = a + "|" + b if a < b else b + "|" + a
			if holes_done.has(key):
				continue
			holes_done[key] = true
			var hp := to_screen(e.hole_point(a, b))
			draw_circle(hp, 14.0 * sc() / base_scale * 0.6, UI.INK)
			draw_circle(hp, 10.0 * sc() / base_scale * 0.6, Color("#5cc23a"))
	for a in e.AR:
		_draw_area(a)


func _draw_web(a: String) -> void:
	var c: Array = e.AR[a]["center"]
	var p := to_screen(Vector2(c[0], c[1]))
	var r := 70.0 * sc()
	var col := Color(1, 1, 1, 0.75)
	for i in 8:
		var ang := TAU * i / 8.0
		draw_line(p, p + Vector2(cos(ang), sin(ang)) * r, col, 1.5)
	for k in range(1, 4):
		var pts := PackedVector2Array()
		for i in 9:
			var ang2 := TAU * i / 8.0
			pts.append(p + Vector2(cos(ang2), sin(ang2)) * r * k / 3.0)
		draw_polyline(pts, col, 1.5)


func _draw_area(a: String) -> void:
	var items := []
	if e.hidden.has(a):
		items.append(["h", (e.hidden[a] as Array).size()])
	for b in e.bout:
		if e.bout[b]["loc"] == a:
			items.append(["b", b])
	for c in e.crew_at(a):
		items.append(["c", c])
	for c in e.captives_at(a):
		items.append(["p", c])
	var ms := e.seen_mons_at(a) if (view != null and view.fog()) else e.mons_at(a)
	ms.sort_custom(func(x, y): return D.MON_ORDER.find(e.mon[x]["l"]) < D.MON_ORDER.find(e.mon[y]["l"]) or (e.mon[x]["l"] == e.mon[y]["l"] and x < y))
	var slots: Array = e.AR[a]["slots"]
	if items.size() + ms.size() > slots.size():
		# area affollata: le Cose Verdi uguali si impilano in una sola pedina con il numero
		var groups := {}
		var order := []
		for m in ms:
			var k: String = e.mon[m]["l"] + ("s" if e.mon[m]["st"] else "") + str(e.mon[m].get("mega", ""))
			if not groups.has(k):
				groups[k] = []
				order.append(k)
			groups[k].append(m)
		for k in order:
			items.append(["g", groups[k]])
	else:
		for m in ms:
			items.append(["m", m])
	var floor := e.weapons_at(a)
	if e.outside():
		var gseen := {}
		for g in e.gear_at(a):
			var gt: String = e.gear[g]["t"]
			if not gseen.has(gt):
				gseen[gt] = true
				floor.append(-1000 - g)
	var s := sc()
	var tok := TOK * s
	if items.size() > slots.size() and e.AR[a].has("dense"):
		var dense: Array = e.AR[a]["dense"]
		if dense.size() > slots.size():
			slots = dense
			tok = TOK * 0.72 * s
	tok = minf(tok, _spacing(a, slots) * s * 0.96)
	var n := slots.size()
	for i in items.size():
		var sl: Array = slots[i % n]
		var layer := i / n
		var p := to_screen(Vector2(sl[0], sl[1])) + Vector2(7, -7) * layer * s
		var it: Array = items[i]
		var r := Rect2(p - Vector2(tok, tok) * 0.5, Vector2(tok, tok))
		if it[0] == "c":
			_draw_crew(it[1], r)
			_hits.append([r, "c", it[1]])
		elif it[0] == "b":
			var bt: String = it[1]
			var br := r.grow(tok * 0.15)
			draw_rect(br.grow(2), UI.INK)
			draw_texture_rect(UI.tex("res://assets/counters/boat_%s.png" % bt), br, false, Color(1, 1, 1, 0.45) if e.bout[bt]["gone"] else Color.WHITE)
			if e.bout[bt]["gone"]:
				_badge(br.get_center(), "via!", UI.ORANGE)
		elif it[0] == "h":
			var nh: int = it[1]
			for j in range(mini(nh, 4) - 1, -1, -1):
				var rr := Rect2(r.position + Vector2(4, -4) * j, r.size)
				draw_rect(rr.grow(2), UI.INK)
				draw_rect(rr, Color("#3b4a3f"))
			draw_string(UI.font_comic, r.position + Vector2(r.size.x * 0.3, r.size.y * 0.78), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, int(r.size.y * 0.7), Color("#9fc48a"))
			if nh > 1:
				_badge(r.position + Vector2(r.size.x, r.size.y), "×%d" % nh, UI.CREAM)
		elif it[0] == "p":
			draw_rect(r.grow(2), UI.INK)
			draw_texture_rect(UI.crew_tex(e.crew[it[1]]["k"]), r, false, Color(0.55, 0.75, 0.5))
			draw_rect(r, Color(0.3, 0.9, 0.2, 0.3))
			_badge(r.position + Vector2(r.size.x * 0.5, r.size.y * 0.85), "aiuto!", Color("#9be37a"))
		elif it[0] == "m":
			_draw_mon(it[1], r)
			_hits.append([r, "m", it[1]])
		else:
			var g: Array = it[1]
			if g.size() > 1:
				draw_rect(Rect2(r.position + Vector2(6, -6), r.size).grow(2), UI.INK)
				draw_texture_rect(UI.mon_tex(e.mon[g[0]]["l"]), Rect2(r.position + Vector2(6, -6), r.size), false, Color(0.8, 0.8, 0.8))
			_draw_mon(g[0], r, false)
			var sel := false
			for m in g:
				if sel_pieces.has("m%d" % m):
					sel = true
			if sel:
				draw_rect(r.grow(3), UI.YELLOW, false, 4.0)
			if g.size() > 1:
				_badge(r.position + Vector2(r.size.x, r.size.y), "×%d" % g.size(), UI.CREAM)
			var tg := []
			for m in g:
				if tags.has(m):
					tg.append(str(tags[m]))
			if not tg.is_empty():
				_badge(r.position, tg[0] if tg.size() == 1 else "%s-%s" % [tg[0], tg[tg.size() - 1]], UI.ORANGE)
			_hits.append([r, "m", g[0]])
	# armi a terra: una fila in basso nell'area
	if not floor.is_empty():
		var cnt := {}
		var order := []
		for w in floor:
			var t := e.wtype(w) if w >= 0 else "g_" + str(e.gear[-1000 - w]["t"])
			if not cnt.has(t):
				order.append(w)
			cnt[t] = cnt.get(t, 0) + 1
		var c: Array = e.AR[a]["center"]
		var wt := WTOK * s
		var start := to_screen(Vector2(c[0], c[1])) + Vector2(-(order.size() * wt * 1.1) * 0.5, tok * 0.75)
		if not items.is_empty() and n > 0:
			var last: Array = slots[mini(items.size(), n) - 1]
			start.y = maxf(start.y, to_screen(Vector2(last[0], last[1])).y + tok * 0.6)
		for j in order.size():
			var w: int = order[j]
			var r := Rect2(start + Vector2(j * wt * 1.1, 0), Vector2(wt, wt))
			if w <= -1000:
				var gt2: String = e.gear[-1000 - w]["t"]
				var gn := 0
				for g2 in e.gear_at(a):
					if e.gear[g2]["t"] == gt2:
						gn += 1
				draw_rect(r.grow(1.5), UI.INK)
				draw_texture_rect(UI.gear_tex(gt2), r, false)
				if gn > 1:
					_badge(r.position + Vector2(r.size.x, 0), "×%d" % gn, UI.CREAM)
				continue
			var t := e.wtype(w)
			if e.wpn[w]["on"]:
				draw_rect(r.grow(4), Color(1, 0.95, 0.2, 0.6 + 0.4 * sin(pulse * 9.0)))
			draw_rect(r.grow(1.5), UI.INK)
			draw_texture_rect(UI.weapon_tex(t), r, false)
			if cnt[t] > 1:
				_badge(r.position + Vector2(r.size.x, 0), "×%d" % cnt[t], UI.YELLOW)
			_hits.append([r, "w", w])


var _sp := {}
func _spacing(a: String, slots: Array) -> float:
	var key := a + str(slots.size())
	if not _sp.has(key):
		var m := 999.0
		for i in slots.size():
			for j in range(i + 1, slots.size()):
				m = minf(m, Vector2(slots[i][0], slots[i][1]).distance_to(Vector2(slots[j][0], slots[j][1])))
		_sp[key] = minf(m, TOK)
	return _sp[key]


func _draw_crew(c: int, r: Rect2) -> void:
	var sel := sel_pieces.has("c%d" % c)
	if sel:
		draw_rect(r.grow(5), UI.YELLOW)
	if e.mutiny():
		# ammutinamento: cornice blu per il Capitano, arancione per il Primo Ufficiale
		var tm := e.team_of(c)
		draw_rect(r.grow(4), UI.BLUE if tm == 0 else (UI.ORANGE if tm == 2 else UI.MUTED))
	draw_rect(r.grow(2), UI.INK)
	var mod := Color.WHITE
	if not e.awake(c):
		mod = Color(0.55, 0.55, 0.6)
	elif e.moved.has(c) and e.phase in ["cmove", "discovery"]:
		mod = Color(0.82, 0.82, 0.82)
	draw_texture_rect(UI.crew_tex(e.crew[c]["k"]), r, false, mod)
	var w: int = e.crew[c]["w"]
	if w >= 0:
		var wr := Rect2(r.position + r.size * 0.55, r.size * 0.5)
		draw_rect(wr.grow(1.5), UI.INK)
		draw_texture_rect(UI.weapon_tex(e.wtype(w)), wr, false)
	if e.outside() and e.gear_of(c) != "":
		var gr := Rect2(r.position + Vector2(-r.size.x * 0.1, r.size.y * 0.55), r.size * 0.5)
		draw_rect(gr.grow(1.5), UI.INK)
		draw_texture_rect(UI.gear_tex(e.gear_of(c)), gr, false)
	if not e.awake(c):
		_badge(r.position + Vector2(r.size.x * 0.5, r.size.y * 0.3), "zZ", Color("#b9c7ff"))
	if e.busy.has(c):
		_badge(r.position + Vector2(r.size.x * 0.5, 0), "⚡" if e.busy[c] == "fence" else "!!", UI.ORANGE)
	if crew_tags.has(c):
		_badge(r.position + Vector2(0, 0), str(crew_tags[c]), UI.ORANGE)


func _draw_mon(m: int, r: Rect2, with_tag := true) -> void:
	var sel := sel_pieces.has("m%d" % m)
	if sel and with_tag:
		draw_rect(r.grow(5), UI.YELLOW)
	draw_rect(r.grow(2), UI.INK)
	var t := UI.mon_tex(e.mon[m]["l"])
	if e.mon[m]["st"]:
		# stordito: la pedina si capovolge
		draw_set_transform(r.get_center(), PI, Vector2.ONE)
		draw_texture_rect(t, Rect2(-r.size * 0.5, r.size), false, Color(0.75, 0.75, 0.75))
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		_badge(r.position + Vector2(r.size.x * 0.5, r.size.y * 0.3), "zZ", Color("#b9c7ff"))
	else:
		var mod := Color.WHITE
		if e.moved.has(m) and e.phase == "mmove":
			mod = Color(0.8, 0.8, 0.8)
		draw_texture_rect(t, r, false, mod)
	if e.is_mega(m):
		draw_rect(r.grow(3), UI.ORANGE, false, 3.0)
		_badge(r.position + Vector2(r.size.x * 0.5, r.size.y), String(D.MEGA[e.mon[m]["mega"]]["short"]), UI.SLIME)
	if e.mon[m].has("w"):
		var wr := Rect2(r.position + r.size * 0.55, r.size * 0.5)
		draw_rect(wr.grow(1.5), UI.INK)
		draw_texture_rect(UI.weapon_tex(e.wtype(e.mon[m]["w"])), wr, false)
	if tags.has(m) and with_tag:
		_badge(r.position, str(tags[m]), UI.ORANGE)


func _badge(p: Vector2, txt: String, col: Color) -> void:
	var f: Font = UI.font_comic
	var fs := int(clampf(17.0 * zoom, 14, 26))
	var sz := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var r := Rect2(p - Vector2(sz.x * 0.5 + 5, sz.y * 0.5), Vector2(sz.x + 10, sz.y + 2))
	draw_rect(r.grow(2), UI.INK)
	draw_rect(r, col)
	draw_string(f, r.position + Vector2(5, sz.y * 0.82), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UI.INK)


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(mb.position, 1.12)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(mb.position, 1.0 / 1.12)
		elif mb.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_drag = mb.pressed
			_drag_moved = false
			_drag_from = mb.position
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag = true
				_drag_moved = false
				_drag_from = mb.position
			else:
				_drag = false
				if not _drag_moved:
					_click(mb.position)
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if _drag and (mm.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE)) != 0:
			if _drag_moved or mm.position.distance_to(_drag_from) > 8:
				_drag_moved = true
				offset += mm.relative
				queue_redraw()
		var a := area_at(mm.position)
		if a != hover:
			hover = a
			area_hovered.emit(a)
			queue_redraw()
	elif ev is InputEventMagnifyGesture:
		_zoom_at((ev as InputEventMagnifyGesture).position, (ev as InputEventMagnifyGesture).factor)
	elif ev is InputEventPanGesture:
		offset -= (ev as InputEventPanGesture).delta * 12.0
		queue_redraw()


func _zoom_at(p: Vector2, f: float) -> void:
	var b := to_board(p)
	zoom = clampf(zoom * f, 1.0, 3.5)
	offset = p - b * sc()
	queue_redraw()


func _click(p: Vector2) -> void:
	for i in range(_hits.size() - 1, -1, -1):
		var h: Array = _hits[i]
		if (h[0] as Rect2).has_point(p):
			piece_clicked.emit(h[1], h[2])
			return
	var a := area_at(p)
	if a != "":
		area_clicked.emit(a)


func flash_area(a: String) -> void:
	if a != "":
		flash[a] = 1.0
		queue_redraw()

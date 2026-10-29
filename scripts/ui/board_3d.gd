class_name Board3D
extends SubViewportContainer
## Vista 3D della Znutar: il tabellone appoggiato sul tavolo e le miniature stampate in 3D (equipaggio,
## Cose Verdi, armi) colorate come le pedine. Trascina col sinistro per ruotare, col destro (o col
## sinistro tenendo Maiusc) per spostare, rotella per lo zoom. Stessa interfaccia di BoardView.

signal area_clicked(a: String)
signal piece_clicked(kind: String, id: int)
signal area_hovered(a: String)

const D = preload("res://scripts/data/agt_data.gd")
const U := 0.01                    # unità del mondo per pixel del tabellone
const TOK := 60.0                  # lato della basetta, in pixel del tabellone
const MINI_SCALE := 30.0           # le basette da 20 mm diventano larghe ~0,6
const MON_VARIANTS := {"A": ["adult", 8], "B": ["baby", 8], "E": ["egg", 6], "F": ["fragment", 3]}

var view
var e: AGTEngine
var highlight := {}
var selected_area := ""
var sel_pieces := {}
var tags := {}
var crew_tags := {}
var hover := ""

var vp: SubViewport
var cam: Camera3D
var pivot: Node3D
var yaw := 0.0
var pitch := -58.0
var dist := 14.0
var target := Vector3.ZERO
var user_moved := false
var pieces_root: Node3D
var hl_root: Node3D
var labels_root: Node3D
var pieces := {}                   # chiave -> Node3D
var piece_pos := {}                # chiave -> Vector3 (destinazione)
var flash := {}
var pulse := 0.0
var drag_btn := -1
var drag_from := Vector2.ZERO
var drag_moved := false
var _dirty := false
var _scenes := {}
var _hl_mats := []
var board_size := Vector2.ZERO


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	vp = SubViewport.new()
	vp.msaa_3d = Viewport.MSAA_4X
	vp.own_world_3d = true
	vp.handle_input_locally = false
	add_child(vp)
	var env := WorldEnvironment.new()
	var en := Environment.new()
	en.background_mode = Environment.BG_COLOR
	en.background_color = Color("#06140b")
	en.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	en.ambient_light_color = Color("#c9d8c0")
	en.ambient_light_energy = 0.38
	en.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = en
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 32, 0)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	vp.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, -140, 0)
	fill.light_energy = 0.22
	fill.light_color = Color("#bfe8b0")
	vp.add_child(fill)
	pivot = Node3D.new()
	vp.add_child(pivot)
	cam = Camera3D.new()
	cam.fov = 38.0
	cam.near = 0.05
	cam.far = 200.0
	pivot.add_child(cam)
	# il tavolo e il tabellone
	var tex: Texture2D = UI.tex("res://assets/board/nave.webp")
	board_size = Vector2(tex.get_width(), tex.get_height()) * U
	var table := MeshInstance3D.new()
	var tm := PlaneMesh.new()
	tm.size = Vector2(80, 80)
	table.mesh = tm
	table.position = Vector3(board_size.x * 0.5, -0.09, board_size.y * 0.5)
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color("#0d2414")
	tmat.roughness = 0.95
	table.material_override = tmat
	vp.add_child(table)
	var slab := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(board_size.x + 0.12, 0.08, board_size.y + 0.12)
	slab.mesh = bm
	slab.position = Vector3(board_size.x * 0.5, -0.045, board_size.y * 0.5)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color("#141414")
	slab.material_override = smat
	vp.add_child(slab)
	var board := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = board_size
	board.mesh = pm
	board.position = Vector3(board_size.x * 0.5, 0.0, board_size.y * 0.5)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_texture = tex
	bmat.roughness = 0.85
	bmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	board.material_override = bmat
	vp.add_child(board)
	hl_root = Node3D.new()
	vp.add_child(hl_root)
	pieces_root = Node3D.new()
	vp.add_child(pieces_root)
	labels_root = Node3D.new()
	vp.add_child(labels_root)
	target = Vector3(board_size.x * 0.5, 0, board_size.y * 0.5)
	_update_cam()
	resized.connect(func():
		if not user_moved:
			fit())


func set_engine(eng: AGTEngine) -> void:
	e = eng
	refresh()


func refresh() -> void:
	if not _dirty:
		_dirty = true
		_rebuild.call_deferred()


func queue_redraw_board() -> void:
	refresh()


# ================================================================ modelli

func _scene(n: String) -> PackedScene:
	if not _scenes.has(n):
		var p := "res://assets/minis/%s.glb" % n
		_scenes[n] = load(p) if ResourceLoader.exists(p) else null
	return _scenes[n]


## Miniature fatte con Meshy (assets/minis_meshy): se c'è il modello si usa quello al posto della
## miniatura del modulo. Cerca prima il nome esatto (adult_3), poi quello senza variante (adult).
static var use_meshy := false


func _meshy_scene(n: String) -> PackedScene:
	if not use_meshy:
		return null
	for cand in [n, n.rsplit("_", true, 1)[0] if n.rsplit("_", true, 1).size() > 1 and n.rsplit("_", true, 1)[1].is_valid_int() else ""]:
		if cand == "":
			continue
		var key: String = "M|" + cand
		if not _scenes.has(key):
			var p := "res://assets/minis_meshy/%s.glb" % cand
			_scenes[key] = load(p) if ResourceLoader.exists(p) else null
		if _scenes[key] != null:
			return _scenes[key]
	return null


## Altezza delle figure Meshy (le loro basette si aggiungono qui, del colore delle pedine).
func _meshy_height(n: String) -> float:
	if n.begins_with("crew_"):
		return 0.62 if not n in ["crew_robot", "crew_mascot"] else 0.5
	if n.begins_with("adult"):
		return 0.62
	if n.begins_with("baby"):
		return 0.38
	if n.begins_with("egg"):
		return 0.3
	if n.begins_with("fragment"):
		return 0.2
	return 0.3


func _mini(n: String) -> Node3D:
	var holder := Node3D.new()
	var ms := _meshy_scene(n)
	if ms != null:
		var inst: Node3D = ms.instantiate()
		var bb := _aabb(inst, Transform3D.IDENTITY)
		var h := maxf(bb.size.y, 0.001)
		var k := _meshy_height(n) / h
		inst.scale = Vector3.ONE * k
		inst.position = Vector3(-(bb.position.x + bb.size.x * 0.5) * k, 0.03 - bb.position.y * k, -(bb.position.z + bb.size.z * 0.5) * k)
		var body := Node3D.new()
		body.add_child(inst)
		holder.add_child(body)
		# basetta tonda del colore della pedina di cartone
		var base := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		var r := 0.27 if (n.begins_with("crew_") or n.begins_with("adult")) else 0.2
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = 0.03
		base.mesh = cm
		base.position.y = 0.015
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color("#f4ecd0") if n.begins_with("crew_") else (Color("#1b5f8a") if n.begins_with("w_") else Color("#ffd923"))
		base.material_override = bm
		body.add_child(base)
		return holder
	var ps := _scene(n)
	if ps != null:
		var inst2: Node3D = ps.instantiate()
		inst2.scale = Vector3.ONE * MINI_SCALE
		holder.add_child(inst2)
	else:
		var mi := MeshInstance3D.new()
		var cm2 := CylinderMesh.new()
		cm2.top_radius = 0.25
		cm2.bottom_radius = 0.25
		cm2.height = 0.1
		mi.mesh = cm2
		holder.add_child(mi)
	return holder


func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var b := t * (n as MeshInstance3D).mesh.get_aabb()
		out = b
		first = false
	for c in n.get_children():
		var cb := _aabb(c, t)
		if cb.size != Vector3.ZERO:
			out = cb if first else out.merge(cb)
			first = false
	return out


func _model_name(kind: String, id: int) -> String:
	match kind:
		"c":
			return "crew_" + e.crew[id]["k"]
		"m":
			var v: Array = MON_VARIANTS[e.mon[id]["l"]]
			return "%s_%d" % [v[0], (id % int(v[1])) + 1]
		"w":
			return "w_" + e.wtype(id)
	return ""


# ================================================================ disposizione

func bpos(p: Vector2) -> Vector3:
	return Vector3(p.x * U, 0.0, p.y * U)


func _spacing(slots: Array) -> float:
	var m := 999.0
	for i in slots.size():
		for j in range(i + 1, slots.size()):
			m = minf(m, Vector2(slots[i][0], slots[i][1]).distance_to(Vector2(slots[j][0], slots[j][1])))
	return minf(m, TOK)


## Posizioni di tutte le pedine: chiave -> [posizione, scala, tipo, id, modello].
func _layout() -> Dictionary:
	var out := {}
	for a in e.AR:
		var items := []
		for c in e.crew_at(a):
			items.append(["c", c])
		var ms := e.mons_at(a)
		ms.sort_custom(func(x, y): return D.MON_ORDER.find(e.mon[x]["l"]) < D.MON_ORDER.find(e.mon[y]["l"]) or (e.mon[x]["l"] == e.mon[y]["l"] and x < y))
		for m in ms:
			items.append(["m", m])
		var slots: Array = e.AR[a]["slots"]
		if items.size() > slots.size() and e.AR[a].has("dense") and (e.AR[a]["dense"] as Array).size() > slots.size():
			slots = e.AR[a]["dense"]
		var sc := _spacing(slots) / TOK
		var n := slots.size()
		for i in items.size():
			var sl: Array = slots[i % n]
			var layer := i / n
			var p := bpos(Vector2(sl[0], sl[1])) + Vector3(0.06, 0.0, -0.06) * layer + Vector3(0, 0.012 * layer, 0)
			var it: Array = items[i]
			out[it[0] + str(it[1])] = [p, sc, it[0], it[1]]
		# armi a terra: una fila sotto le pedine
		var fl := e.weapons_at(a)
		if not fl.is_empty():
			var c: Array = e.AR[a]["center"]
			var base := Vector2(c[0], c[1])
			if not items.is_empty():
				var last: Array = slots[mini(items.size(), n) - 1]
				base.y = maxf(base.y, last[1] + TOK * sc * 0.75)
			var wsp := 26.0
			for j in fl.size():
				var w: int = fl[j]
				var q := base + Vector2((j - (fl.size() - 1) * 0.5) * wsp, 0)
				out["w" + str(w)] = [bpos(q), 0.55, "w", w]
	return out


func _rebuild() -> void:
	_dirty = false
	if e == null:
		return
	var lay := _layout()
	# pedine sparite
	for k in pieces.keys():
		if not lay.has(k) or pieces[k].get_meta("model") != _model_name(lay[k][2], lay[k][3]):
			pieces[k].queue_free()
			pieces.erase(k)
			piece_pos.erase(k)
	for k in lay:
		var it: Array = lay[k]
		var node: Node3D
		if not pieces.has(k):
			var mn := _model_name(it[2], it[3])
			node = _mini(mn)
			node.set_meta("model", mn)
			node.rotation.y = randf_range(-0.25, 0.25) + (PI if it[2] == "m" else 0.0)
			pieces_root.add_child(node)
			pieces[k] = node
			node.position = it[0]
		else:
			node = pieces[k]
			if not (piece_pos.get(k, it[0]) as Vector3).is_equal_approx(it[0]):
				var tw := node.create_tween()
				var mid: Vector3 = (node.position + it[0]) * 0.5 + Vector3(0, 0.35, 0)
				tw.tween_property(node, "position", mid, 0.18).set_trans(Tween.TRANS_SINE)
				tw.tween_property(node, "position", it[0], 0.18).set_trans(Tween.TRANS_SINE)
		piece_pos[k] = it[0]
		node.scale = Vector3.ONE * float(it[1])
		_decorate(node, it[2], it[3])
	_build_highlights()
	_build_labels(lay)


## Stato visibile della miniatura: stordita (rovesciata), arma in mano, recinto acceso, selezione.
func _decorate(node: Node3D, kind: String, id: int) -> void:
	var inner: Node3D = node.get_child(0) if node.get_child_count() > 0 else null
	if inner == null:
		return
	var stunned := false
	if kind == "c":
		stunned = not e.awake(id)
	elif kind == "m":
		stunned = e.mon[id]["st"]
	inner.rotation.z = (PI * 0.5 if stunned else 0.0)
	inner.position.y = 0.14 if stunned else 0.0
	# arma portata: piccola miniatura accanto
	var held := node.get_node_or_null("arma")
	var w: int = e.crew[id]["w"] if kind == "c" else -1
	var want := ("w_" + e.wtype(w)) if w >= 0 else ""
	if held != null and held.get_meta("model") != want:
		held.queue_free()
		held = null
	if held == null and want != "":
		held = _mini(want)
		held.name = "arma"
		held.set_meta("model", want)
		held.scale = Vector3.ONE * 0.6
		held.position = Vector3(0.24, 0.0, 0.2)
		node.add_child(held)
	# anello di selezione
	var ring := node.get_node_or_null("anello")
	var sel: bool = sel_pieces.get(kind + str(id), false) == true
	if kind == "w":
		sel = bool(e.wpn[id]["on"])
	if sel and ring == null:
		ring = MeshInstance3D.new()
		ring.name = "anello"
		var tm := TorusMesh.new()
		tm.inner_radius = 0.34
		tm.outer_radius = 0.42
		ring.mesh = tm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = UI.YELLOW
		ring.material_override = m
		ring.position.y = 0.02
		node.add_child(ring)
	elif not sel and ring != null:
		ring.queue_free()


func _build_highlights() -> void:
	for c in hl_root.get_children():
		c.queue_free()
	_hl_mats = []
	for a in highlight:
		_area_plate(a, highlight[a], 0.32, true)
	for a in flash:
		_area_plate(a, Color(1, 0.9, 0.3), 0.5, false)
	if selected_area != "" and e.AR.has(selected_area):
		_area_outline(selected_area, UI.YELLOW, 0.07)
	if hover != "" and e.AR.has(hover) and not highlight.has(hover):
		_area_outline(hover, Color(1, 1, 1, 0.7), 0.03)


func _poly(a: String) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for q in e.AR[a]["poly"]:
		poly.append(Vector2(q[0], q[1]))
	return poly


func _area_plate(a: String, col: Color, alpha: float, pulse_it: bool) -> void:
	var poly := _poly(a)
	var idx := Geometry2D.triangulate_polygon(poly)
	if idx.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in idx:
		st.add_vertex(bpos(poly[i]) + Vector3(0, 0.006, 0))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(col, alpha)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hl_root.add_child(mi)
	if pulse_it:
		_hl_mats.append([m, alpha])
	_area_outline(a, col, 0.045)


func _area_outline(a: String, col: Color, w: float) -> void:
	var poly := _poly(a)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in poly.size():
		var p0 := bpos(poly[i]) + Vector3(0, 0.01, 0)
		var p1 := bpos(poly[(i + 1) % poly.size()]) + Vector3(0, 0.01, 0)
		var d := (p1 - p0)
		if d.length() < 0.001:
			continue
		var nrm := Vector3(-d.z, 0, d.x).normalized() * w * 0.5
		st.add_vertex(p0 - nrm)
		st.add_vertex(p1 - nrm)
		st.add_vertex(p1 + nrm)
		st.add_vertex(p0 - nrm)
		st.add_vertex(p1 + nrm)
		st.add_vertex(p0 + nrm)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hl_root.add_child(mi)


func _build_labels(lay: Dictionary) -> void:
	for c in labels_root.get_children():
		c.queue_free()
	for m in tags:
		var k := "m" + str(m)
		if lay.has(k):
			_label(lay[k][0] + Vector3(0, 0.75 * float(lay[k][1]), 0), str(tags[m]), UI.ORANGE)
	for c in crew_tags:
		var k2 := "c" + str(c)
		if lay.has(k2):
			_label(lay[k2][0] + Vector3(0, 0.95 * float(lay[k2][1]), 0), str(crew_tags[c]), UI.ORANGE)
	for c in e.busy:
		var k3 := "c" + str(c)
		if lay.has(k3):
			_label(lay[k3][0] + Vector3(0, 1.0, 0), "⚡" if e.busy[c] == "fence" else "!!", UI.ORANGE)


func _label(p: Vector3, txt: String, col: Color) -> void:
	var l := Label3D.new()
	l.text = txt
	l.font = UI.font_comic
	l.font_size = 64
	l.pixel_size = 0.004
	l.modulate = col
	l.outline_modulate = UI.INK
	l.outline_size = 14
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = p
	labels_root.add_child(l)


# ================================================================ camera e input

func _process(dt: float) -> void:
	pulse += dt
	var glow := 0.5 + 0.5 * sin(pulse * 4.0)
	for hm in _hl_mats:
		var m: StandardMaterial3D = hm[0]
		m.albedo_color.a = float(hm[1]) * (0.55 + 0.6 * glow)
	if not flash.is_empty():
		for a in flash.keys():
			flash[a] -= dt
			if flash[a] <= 0:
				flash.erase(a)
				refresh()


func _update_cam() -> void:
	pivot.position = target
	pivot.rotation_degrees = Vector3(pitch, yaw, 0)
	cam.position = Vector3(0, 0, dist)
	cam.rotation = Vector3.ZERO


func fit() -> void:
	if size.x < 10:
		return
	if Vector2(vp.size) != size:
		vp.size = Vector2i(size)
	user_moved = false
	target = Vector3(board_size.x * 0.5, 0, board_size.y * 0.5 + 0.4)
	yaw = 0.0
	pitch = -60.0
	var pts := [Vector3(0, 0, 0), Vector3(board_size.x, 0, 0), Vector3(0, 0, board_size.y), Vector3(board_size.x, 0, board_size.y)]
	dist = 30.0
	for it in 12:
		_update_cam()
		var mn := Vector2(1e9, 1e9)
		var mx := Vector2(-1e9, -1e9)
		for p in pts:
			var sp := cam.unproject_position(p) / Vector2(vp.size)
			mn = mn.min(sp)
			mx = mx.max(sp)
		var span := maxf(mx.x - mn.x, mx.y - mn.y)
		dist *= clampf(span / 0.94, 0.5, 2.0)
	_update_cam()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			_zoom(0.9 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.11)
			accept_event()
			return
		if mb.pressed and mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			drag_btn = mb.button_index
			drag_from = mb.position
			drag_moved = false
		elif not mb.pressed and mb.button_index == drag_btn:
			if not drag_moved and drag_btn == MOUSE_BUTTON_LEFT:
				_click(mb.position)
			drag_btn = -1
		accept_event()
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if drag_btn >= 0:
			if mm.position.distance_to(drag_from) > 6.0:
				drag_moved = true
			if drag_moved:
				user_moved = true
				if drag_btn == MOUSE_BUTTON_LEFT and not mm.shift_pressed:
					yaw -= mm.relative.x * 0.25
					pitch = clampf(pitch - mm.relative.y * 0.2, -89.0, -12.0)
				else:
					var right := cam.global_transform.basis.x
					right.y = 0
					right = right.normalized()
					var fwd := Vector3(-sin(deg_to_rad(yaw)), 0, -cos(deg_to_rad(yaw)))
					var k := dist * 0.0015
					target += (-right * mm.relative.x + fwd * mm.relative.y) * k
					target.x = clampf(target.x, -2.0, board_size.x + 2.0)
					target.z = clampf(target.z, -2.0, board_size.y + 2.0)
				_update_cam()
		else:
			var a := area_at(mm.position)
			if a != hover:
				hover = a
				area_hovered.emit(a)
				refresh()
	elif ev is InputEventMagnifyGesture:
		_zoom(1.0 / (ev as InputEventMagnifyGesture).factor)
	elif ev is InputEventPanGesture:
		var pg := ev as InputEventPanGesture
		yaw -= pg.delta.x * 2.0
		pitch = clampf(pitch - pg.delta.y * 2.0, -89.0, -12.0)
		user_moved = true
		_update_cam()


func _zoom(f: float) -> void:
	dist = clampf(dist * f, 2.5, 40.0)
	user_moved = true
	_update_cam()


func _screen(p: Vector3) -> Vector2:
	return cam.unproject_position(p) * (size / Vector2(vp.size))


func _board_point(pos: Vector2) -> Vector2:
	var p := pos * (Vector2(vp.size) / size)
	var o := cam.project_ray_origin(p)
	var d := cam.project_ray_normal(p)
	if absf(d.y) < 0.0001:
		return Vector2(-1, -1)
	var t := -o.y / d.y
	var hit := o + d * t
	return Vector2(hit.x, hit.z) / U


func area_at(pos: Vector2) -> String:
	if e == null:
		return ""
	var b := _board_point(pos)
	for a in e.AR:
		if Geometry2D.is_point_in_polygon(b, _poly(a)):
			return a
	return ""


func area_center(a: String) -> Vector2:
	var c: Array = e.AR[a]["center"]
	return _screen(bpos(Vector2(c[0], c[1])) + Vector3(0, 0.3, 0))


func _click(pos: Vector2) -> void:
	# prima le miniature (la più vicina al punto, sullo schermo)
	var best := ""
	var bd := 1e9
	for k in pieces:
		var n: Node3D = pieces[k]
		var sp := _screen(n.position + Vector3(0, 0.25 * n.scale.x, 0))
		var r := _screen(n.position + Vector3(0.3 * n.scale.x, 0.25 * n.scale.x, 0)).distance_to(_screen(n.position + Vector3(0, 0.25 * n.scale.x, 0)))
		var d := sp.distance_to(pos)
		if d < maxf(r, 10.0) and d < bd:
			bd = d
			best = k
	if best != "":
		piece_clicked.emit(best.substr(0, 1), int(best.substr(1)))
		return
	var a := area_at(pos)
	if a != "":
		area_clicked.emit(a)


func flash_area(a: String) -> void:
	if a != "":
		flash[a] = 1.0
		refresh()

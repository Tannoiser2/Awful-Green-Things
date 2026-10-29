extends SceneTree
## Screenshot automatici dell'interfaccia (serve un display: xvfb-run).
## xvfb-run godot --path . -s res://tests/shot.gd -- <modo> [turni]
## modo: menu | rules | crew (Equipaggio persona) | mon (Cose Verdi persona)
## Nelle partite le decisioni della persona le prende l'IA, con uno screenshot alla prima
## richiesta di ogni tipo.

var main
var n := 0
var seen := {}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir() + "/shots")
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func shot(name: String) -> void:
	for i in 4:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	n += 1
	img.save_png(OS.get_user_data_dir() + "/shots/%02d_%s.png" % [n, name])
	print("shot ", name)


func wait(f := 10) -> void:
	for i in range(f):
		await process_frame


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "crew"
	var turns := int(args[1]) if args.size() > 1 else 3
	await wait(8)
	if mode == "menu":
		await shot("menu")
		main.current._online_panel()
		await wait(4)
		await shot("online")
		quit()
		return
	if mode == "rules":
		main.show_rules()
		await wait(5)
		await shot("regole")
		main.current.page = 1
		main.current._fill()
		await wait(5)
		await shot("regole_opzionali")
		quit()
		return
	var seats := [{"name": "Equipaggio", "ai": mode != "crew" and mode != "solo", "level": 1}, {"name": "Cose Verdi", "ai": mode != "mon", "level": 1}]
	var o := {}
	if mode == "solo":
		o["solo"] = true
		seats[1]["ai"] = true
	if mode == "mut":
		o["mutiny"] = true
		seats[0]["ai"] = false
		seats.append({"name": "Primo Ufficiale", "ai": true, "level": 1})
	for k in OS.get_environment("AGT_OPTS").split(",", false):
		o[k] = true
	main.start_game({"seats": seats, "ai_delay": 0.0, "opts": o, "view3d": OS.get_environment("AGT_2D") != "1",
		"seed": int(OS.get_environment("AGT_SEED")) if OS.get_environment("AGT_SEED") != "" else 7})
	await wait(10)
	var view = main.current
	var ai := AGTAI.new(1, 3)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 240000:
		await process_frame
		var e: AGTEngine = view.engine
		if e.phase == "fine_partita":
			await wait(30)
			await shot("fine")
			break
		if e.turn_no > turns:
			await shot("dopo_%d_turni" % turns)
			break
		var req: Dictionary = view.pending
		if req.is_empty():
			continue
		var k: String = req["type"] + ("_scoperta" if req.get("discovery", false) else "")
		var r = ai.decide(e, req["seat"], req)
		if not seen.has(k):
			seen[k] = true
			if OS.get_environment("AGT_ZOOM") != "" and "board3d" in view and not seen.has("_zoom"):
				seen["_zoom"] = true
				view.board3d.dist *= float(OS.get_environment("AGT_ZOOM"))
				view.board3d.pitch = -42.0
				view.board3d.yaw = 25.0
				view.board3d.user_moved = true
				view.board3d._update_cam()
			await wait(6)
			await shot(k)
			# mostra anche la selezione
			if req["type"] == "cmove" and r is Dictionary and r.has("c"):
				view.sel_crew = r["c"]
				view._build_decision()
				await wait(6)
				await shot(k + "_sel")
			if req["type"] == "cattack" and r is Dictionary and r.has("area"):
				view._on_area_click(r["area"])
				await wait(6)
				await shot(k + "_piano")
			if req["type"] == "mmove" and r is Dictionary and r.has("ids"):
				view._on_area_click(e.mon[r["ids"][0]]["loc"])
				await wait(6)
				await shot(k + "_sel")
		view._submit(r)
	quit()

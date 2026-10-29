extends SceneTree
## Prova del gioco online: due istanze (chi crea la stanza guida l'Equipaggio, l'amico le Cose Verdi)
## giocano una partita intera sul finto Firebase (tests/firebase_mock.py), con le decisioni prese dall'IA.
## AGT_ROLE=host|guest, AGT_CODEFILE=file per il codice della stanza. Alla fine ognuno stampa
## l'impronta della partita: devono coincidere.

var main
var t0 := 0
var ai := AGTAI.new(1, 9)

func _init() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	t0 = Time.get_ticks_msec()
	_run()

func _wait(s: float) -> void:
	await create_timer(s).timeout

func _run() -> void:
	await _wait(0.5)
	var role := OS.get_environment("AGT_ROLE")
	var cf := OS.get_environment("AGT_CODEFILE")
	var menu = main.current
	menu.speed = 3
	var need := 2
	if OS.get_environment("AGT_SCEN") == "mut":
		menu.scenario = 2
		need = 3
	menu._online_panel()
	menu.on_name.text = "Host" if role == "host" else "Ospite"
	if role == "host":
		menu.host_side = 0
		await menu._online_create()
		var code: String = main.lobby.get("code", "")
		print("AGTTEST stanza ", code)
		var f := FileAccess.open(cf, FileAccess.WRITE)
		f.store_string(code)
		f.close()
		while true:
			var room: Dictionary = await main.net.room(code)
			if Net._as_dict(room.get("seats", {})).size() >= need:
				break
			await _wait(0.5)
		await menu._online_start()
	else:
		var code := ""
		while code == "":
			if FileAccess.file_exists(cf):
				code = FileAccess.get_file_as_string(cf).strip_edges()
			await _wait(0.3)
		menu.on_code.text = code
		await menu._online_join()
	while true:
		await process_frame
		if Time.get_ticks_msec() - t0 > 600000:
			print("AGTTEST tempo scaduto")
			quit(2)
			return
		var view = main.current
		if view == null or not ("engine" in view) or view.engine == null:
			continue
		var e: AGTEngine = view.engine
		var req: Dictionary = view.pending
		if not req.is_empty() and view.online._mine_pending:
			view._submit(ai.decide(e, req["seat"], req))
		if e.phase == "fine_partita":
			await _wait(0.5)
			print("AGTTEST impronta ", view.online.n, " | ", e.fingerprint())
			quit(0)
			return

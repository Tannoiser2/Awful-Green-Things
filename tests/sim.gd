extends SceneTree
## Partite simulate fra IA, senza grafica: controlla che le regole reggano e misura esiti e durata.
## Uso: godot --headless --path . -s tests/sim.gd -- [partite] [livello Equipaggio] [livello Cose Verdi]
## AGT_LOG=1 stampa il diario della prima partita.

var errors := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 10
	var lc := int(args[1]) if args.size() > 1 else 1
	var lm := int(args[2]) if args.size() > 2 else 1
	_run(games, lc, lm)


func _run(games: int, lc: int, lm: int) -> void:
	await process_frame
	var t0 := Time.get_ticks_msec()
	var wins := {}
	var reasons := {}
	var turns := 0
	var first := int(OS.get_environment("AGT_FIRST")) if OS.get_environment("AGT_FIRST") != "" else 0
	for g in range(first, first + games):
		var eng := AGTEngine.new()
		eng.headless = true
		root.add_child(eng)
		eng.setup({"seats": [{"name": "", "ai": true, "level": lc}, {"name": "", "ai": true, "level": lm}],
			"seed": 1000 + g, "max_turns": 60})
		eng.ais[0] = AGTAI.new(lc, 50 + g * 7)
		eng.ais[1] = AGTAI.new(lm, 51 + g * 7)
		eng.changed.connect(_check.bind(eng))
		if OS.get_environment("AGT_LIVE") == "1":
			eng.log_added.connect(func(t): print(t))
		await eng.run()
		if OS.get_environment("AGT_LOG") == "1" and g == first:
			for l in eng.log_lines.slice(-60):
				print("  ", l)
			for c in eng.board_crew():
				print("  a bordo: ", eng.cname(c), " in ", eng.crew[c]["loc"], " st ", eng.crew[c]["st"])
		wins[eng.winner] = wins.get(eng.winner, 0) + 1
		reasons[eng.end_reason.substr(0, 45)] = reasons.get(eng.end_reason.substr(0, 45), 0) + 1
		turns += eng.turn_no
		print("partita %d: %s al turno %d — %s | PV %s / %s | mostri %d, equipaggio %d, armi note %s" % [g + 1, eng.winner, eng.turn_no,
			eng.end_reason, eng.vp[0], eng.vp[1], eng.mon.size(), eng.board_crew().size(), eng.known])
		eng.queue_free()
	print("vittorie: ", wins, "  turni medi %.1f" % (float(turns) / games))
	print("finali: ", reasons)
	print("errori: %d   tempo %.1f s" % [errors, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if errors > 0 else 0)


func _check(eng: AGTEngine) -> void:
	for l in eng.D.MON:
		if eng.mon_count(l) > int(eng.D.MON[l]["limit"]):
			_err(eng, "troppi %s" % l)
	for w in eng.wpn:
		var x: Dictionary = eng.wpn[w]
		if x["c"] >= 0 and eng.crew[x["c"]]["w"] != w:
			_err(eng, "arma %d portata da %d ma non risulta" % [w, x["c"]])
	for c in eng.crew:
		var w: int = eng.crew[c]["w"]
		if w >= 0 and eng.wpn[w]["c"] != c:
			_err(eng, "membro %d con arma %d incoerente" % [c, w])
		if w >= 0 and eng.crew[c]["k"] == "mascot":
			_err(eng, "la mascotte ha un'arma")


func _err(eng: AGTEngine, t: String) -> void:
	errors += 1
	if errors < 10:
		print("ERRORE turno %d: %s" % [eng.turn_no, t])

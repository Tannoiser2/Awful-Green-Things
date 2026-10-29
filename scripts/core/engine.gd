class_name AGTEngine
extends Node
## Motore delle regole di The Awful Green Things from Outer Space (8ª edizione), senza dipendenze
## dalla UI. Ogni scelta passa da `decide()`: l'IA risponde subito; per le persone viene emesso
## `decision_requested` e si attende `provide_decision()`. Online le scelte viaggiano nel registro di
## mosse (OnlineSession): con lo stesso seme ogni dispositivo gioca la stessa partita.
##
## Posti: 0 = Equipaggio, 1 = Cose Verdi.
## Equipaggio (crew): id = indice in D.CREW -> {k, loc, st, w, state}
##   st: turno in cui è stato stordito dal gas (0 = sveglio); w: arma in mano (-1 = nessuna)
##   state: "ok", "dead" (mangiato o ucciso), "boat" (fuggito su una scialuppa)
## Cose Verdi (mon): id -> {l, loc, st}  l = A/B/E/F, st = stordito
## Armi (wpn): id -> {t, loc, c, on, out}  loc = area a terra, c = chi la porta, on = recinto acceso,
##   out = tolta dal gioco («Nessun effetto»)
##
## Richieste (req["type"]):
##  - "pick": scelta fra options (testi), risposta = indice
##  - "loc": scelta di un'area in "allowed", risposta = area
##  - "crew_setup": options = {id: [aree]}, risposta = {id: area}
##  - "mplace": piazzamento iniziale, allowed + left {A,B,E}, risposta = {"area", "l"}
##  - "grow": options = livelli ammessi, risposta = livello ("" = nessuno)
##  - "mmove": risposta = {"ids": [...], "to": area} oppure {} per finire
##  - "mattack": areas = aree con scontri, risposta = {"area", "atk": [[[mostri], membro]]} oppure {}
##  - "grab": actions = elenco di azioni, risposta = indice (-1 per finire)
##  - "cmove": risposta = {"c", "to"} | {"act": "fence"/"sd", "c"} | {"act": "escape", "b", "ids"} | {}
##  - "cattack": areas = aree bersaglio, risposta = {"area", "atk": [[membro, arma(bool), mostro o -1]]} | {}

signal changed
signal log_added(text: String)
signal decision_requested(req: Dictionary)
signal decision_provided(result)
signal game_ended(result: Dictionary)
signal fx(kind: String, data: Dictionary)

const D = preload("res://scripts/data/agt_data.gd")
const CREW_SEAT := 0
const MON_SEAT := 1

var rng := RandomNumberGenerator.new()
var ai_delay := 0.0
var headless := false
var ais := {}
var online = null
var abort := false

# ---- configurazione
var players: Array = []          # {name, ai, level}
var opts := {}                   # varianti: extra_adult, beamer2, grow_eggs
var max_turns := 0               # 0 = senza limite (le simulazioni ne mettono uno)

# ---- stato
var AR: Dictionary = {}
var crew: Dictionary = {}
var mon: Dictionary = {}
var wpn: Dictionary = {}
var known: Dictionary = {}       # tipo d'arma -> gettone effetto scoperto
var known2: Dictionary = {}      # seconda frequenza del Comunicatore (variante)
var cup: Array = []
var turn_no := 0
var phase := ""
var current := -1
var dice: Array = []             # ultimo tiro (per la UI)
var dice_info := ""
var moved: Dictionary = {}       # pedine già mosse in questa fase
var hot_entry: Dictionary = {}   # membro -> area con mostri in cui è entrato (attacca solo lì)
var attacked: Dictionary = {}    # chi ha già attaccato in questo turno
var busy: Dictionary = {}        # membro -> "fence" / "sd" (resta fermo e non attacca)
var sd_left := -1                # turni dell'equipaggio all'esplosione (-1 = autodistruzione non avviata)
var launched: Dictionary = {}    # scialuppe partite
var boats: Array = []            # {b, crew: [id], survivors: [id], fate}
var discovery := false
var game_over := false
var winner := ""                 # "crew" / "mon" / "draw"
var end_reason := ""
var vp := [0.0, 0.0]
var log_lines: Array = []
var _next_mid := 100
var last_area := ""              # ultima area in cui è successo qualcosa (la UI la evidenzia)


# ================================================================ preparazione

func setup(config: Dictionary) -> void:
	if config.has("seed"):
		rng.seed = int(config["seed"])
	else:
		rng.randomize()
	ai_delay = float(config.get("ai_delay", 0.0))
	max_turns = int(config.get("max_turns", 0))
	opts = config.get("opts", {})
	players = []
	for s in config["seats"]:
		players.append({"name": str(s.get("name", "")), "ai": bool(s.get("ai", false)), "level": int(s.get("level", 1))})
	AR = D.areas()
	crew = {}
	for i in D.CREW.size():
		crew[i] = {"k": D.CREW[i]["k"], "loc": "", "st": 0, "w": -1, "state": "ok"}
	wpn = {}
	var wid := 0
	for t in D.WEAPON_ORDER:
		var st: Dictionary = D.WEAPONS[t]["start"]
		for a in st:
			for n in int(st[a]):
				wpn[wid] = {"t": t, "loc": a, "c": -1, "on": false, "out": false}
				wid += 1
	cup = []
	for k in D.CHITS:
		for n in int(D.CHITS[k]["n"]):
			cup.append(k)
	if solo():
		_solo_setup_weapons()


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


func _fx(kind: String, data: Dictionary) -> void:
	if not headless:
		fx.emit(kind, data)


func log_msg(t: String) -> void:
	log_lines.append(t)
	log_added.emit(t)


func pname(s: int) -> String:
	if s < 0 or s >= players.size():
		return "?"
	var def: String = "Equipaggio" if s == CREW_SEAT else "Cose Verdi"
	var n: String = players[s]["name"]
	return def if n == "" or n == def else "%s (%s)" % [n, def]


func d6() -> int:
	return rng.randi_range(1, 6)


func roll(n: int) -> Array:
	var r := []
	for i in n:
		r.append(d6())
	return r


static func total(a: Array) -> int:
	var t := 0
	for v in a:
		t += int(v)
	return t


func _roll_show(n: int, info: String) -> int:
	dice = roll(n)
	dice_info = info
	var t := total(dice)
	_fx("dice", {"dice": dice.duplicate(), "info": info, "total": t})
	return t


# ================================================================ decisioni

func decide(seat: int, req: Dictionary):
	req["seat"] = seat
	current = seat
	changed.emit()
	if abort:
		return ais[seat].decide(self, seat, req)
	if online != null:
		var r0 = await online.decide(self, seat, req)
		return r0
	if players[seat]["ai"]:
		if ai_delay > 0.0 and not headless and is_inside_tree():
			await get_tree().create_timer(ai_delay).timeout
		return ais[seat].decide(self, seat, req)
	decision_requested.emit(req)
	var r = await decision_provided
	return r


func provide_decision(r) -> void:
	decision_provided.emit(r)


func pick(seat: int, ctx: String, title: String, options: Array, extra := {}) -> int:
	if options.is_empty():
		return -1
	var req := {"type": "pick", "ctx": ctx, "title": title, "options": options}
	for k in extra:
		req[k] = extra[k]
	var c = await decide(seat, req)
	return clampi(int(c) if (c is int or c is float) else 0, 0, options.size() - 1)


func choose_loc(seat: int, ctx: String, title: String, allowed: Array) -> String:
	if allowed.is_empty():
		return ""
	if allowed.size() == 1:
		return allowed[0]
	var c = await decide(seat, {"type": "loc", "ctx": ctx, "title": title, "allowed": allowed})
	var s := str(c) if c != null else ""
	return s if s in allowed else allowed[0]


# ================================================================ interrogazioni

func area_name(a: String) -> String:
	return AR[a]["name"] if AR.has(a) else a


func is_corridor(a: String) -> bool:
	return AR[a]["kind"] == "corridoio"


func adj(a: String) -> Array:
	return AR[a]["adj"]


## Aree in linea di vista (l'area stessa compresa).
func los(a: String) -> Array:
	var out: Array = [a]
	out.append_array(AR[a]["los"])
	return out


## Sezione colpita da gas o carburante: la nube si ferma solo ai portelli, quindi in un corridoio
## riempie tutti i tratti collegati da passaggi aperti.
func section(a: String) -> Array:
	var out := [a]
	var q := [a]
	while not q.is_empty():
		var x: String = q.pop_front()
		for n in AR[x]["open"]:
			if not out.has(n):
				out.append(n)
				q.append(n)
	return out


func cdef(id: int) -> Dictionary:
	return D.CREW[id]


func cname(id: int) -> String:
	return D.CREW[id]["name"]


func on_board(id: int) -> bool:
	return crew[id]["state"] == "ok"


func board_crew() -> Array:
	var out := []
	for id in crew:
		if crew[id]["state"] == "ok":
			out.append(id)
	return out


func crew_at(a: String) -> Array:
	var out := []
	for id in crew:
		if crew[id]["state"] == "ok" and crew[id]["loc"] == a:
			out.append(id)
	return out


func awake(id: int) -> bool:
	return crew[id]["st"] == 0


func mons_at(a: String) -> Array:
	var out := []
	for id in mon:
		if mon[id]["loc"] == a:
			out.append(id)
	out.sort()
	return out


func mcon(id: int) -> int:
	return D.MON[mon[id]["l"]]["con"]


func matt(id: int) -> int:
	return D.MON[mon[id]["l"]]["att"]


func mname(id: int) -> String:
	return D.MON[mon[id]["l"]]["name"]


func mon_count(l := "") -> int:
	var n := 0
	for id in mon:
		if l == "" or mon[id]["l"] == l:
			n += 1
	return n


func avail(l: String) -> int:
	return int(D.MON[l]["limit"]) - mon_count(l) - (hidden_mon(l) if not hidden.is_empty() else 0)


## Per l'equipaggio un'area è «calda» se ci sono Adulti o Piccoli svegli.
func hot_for_crew(a: String) -> bool:
	for id in mons_at(a):
		if mon[id]["l"] in ["A", "B"] and not mon[id]["st"]:
			return true
	return false


## I mostri si fermano dove c'è equipaggio sveglio.
func blocks_mon(a: String) -> bool:
	for id in crew_at(a):
		if awake(id):
			return true
	return false


func fence_at(a: String) -> bool:
	for w in wpn:
		var x: Dictionary = wpn[w]
		if x["t"] == "fence" and x["on"] and not x["out"] and x["c"] == -1 and x["loc"] == a:
			return true
	return false


func weapons_at(a: String) -> Array:
	var out := []
	for w in wpn:
		var x: Dictionary = wpn[w]
		if not x["out"] and x["c"] == -1 and x["loc"] == a:
			out.append(w)
	return out


func wtype(w: int) -> String:
	return wpn[w]["t"] if wpn.has(w) else ""


func wname(t: String) -> String:
	return D.WEAPONS[t]["name"]


func chit_name(k: String) -> String:
	return D.CHITS[k]["name"] if D.CHITS.has(k) else "?"


## Effetto noto di un tipo d'arma (con la variante a due frequenze del Comunicatore si usa la migliore).
func effect_of(t: String) -> String:
	if not known.has(t):
		return ""
	var e: String = known[t]
	if t == "beamer" and known2.has(t):
		var e2: String = known2[t]
		if D.CHIT_ORDER.find(e2) < D.CHIT_ORDER.find(e):
			return e2
	return e


## Aree raggiungibili: area -> percorso (senza l'area di partenza).
## Chi entra in un'area dove deve fermarsi non prosegue; uscire si può sempre.
func reach(from: String, mv: int, for_crew: bool) -> Dictionary:
	var out := {}
	var q := [[from, []]]
	var seen := {from: 0}
	while not q.is_empty():
		var it: Array = q.pop_front()
		var cur: String = it[0]
		var path: Array = it[1]
		if path.size() >= mv:
			continue
		if cur != from and _must_stop(cur, for_crew):
			continue
		for n in adj(cur):
			if n == from or (seen.has(n) and seen[n] <= path.size() + 1):
				continue
			seen[n] = path.size() + 1
			var p := path.duplicate()
			p.append(n)
			if not out.has(n):
				out[n] = p
			q.append([n, p])
	return out


func _must_stop(a: String, for_crew: bool) -> bool:
	if fence_at(a):
		return true
	if for_crew and hidden.has(a):
		return true
	return hot_for_crew(a) if for_crew else blocks_mon(a)


## Distanza in passi (ignorando gli arresti), per l'IA.
var _dist_cache := {}
func dist(a: String, b: String) -> int:
	if a == b:
		return 0
	if not _dist_cache.has(a):
		var d := {a: 0}
		var q := [a]
		while not q.is_empty():
			var x: String = q.pop_front()
			for n in adj(x):
				if not d.has(n):
					d[n] = d[x] + 1
					q.append(n)
		_dist_cache[a] = d
	return _dist_cache[a].get(b, 99)


# ---- equipaggio: movimento e attacco

func crew_can_act(id: int) -> bool:
	return on_board(id) and awake(id) and not busy.has(id)


func crew_moves(id: int) -> Dictionary:
	if not crew_can_act(id) or moved.has(id):
		return {}
	var r := reach(crew[id]["loc"], int(cdef(id)["mov"]), true)
	if discovery:
		var out := {}
		for a in r:
			if not mons_at(a).is_empty():
				out[a] = r[a]
		return out
	return r


func discovery_done() -> int:
	return moved.size()


## Aree che il membro può colpire: con le mani (usew = false) o con l'arma che porta.
func crew_targets(id: int, usew: bool) -> Array:
	if not crew_can_act(id) or attacked.has(id):
		return []
	var loc: String = crew[id]["loc"]
	var out: Array = []
	if not usew:
		out = [loc]
	else:
		var w: int = crew[id]["w"]
		if w < 0 or discovery:
			return []
		var t := wtype(w)
		match D.WEAPONS[t]["range"]:
			"same":
				out = [loc]
			"adj":
				out = [loc]
				out.append_array(adj(loc))
			"los":
				out = los(loc)
			_:
				return []
	if hot_entry.has(id):
		out = out.filter(func(a): return a == hot_entry[id])
	if discovery and not moved.has(id):
		return []
	return out


## Aree con mostri che qualcuno dell'equipaggio può colpire in questo momento.
func crew_attack_areas() -> Array:
	var out := []
	for id in board_crew():
		for usew in [false, true]:
			for a in crew_targets(id, usew):
				if not out.has(a) and _has_targets(a, id, usew):
					out.append(a)
	return out


func _has_targets(a: String, id: int, usew: bool) -> bool:
	if usew and D.WEAPONS[wtype(crew[id]["w"])]["kind"] == "blast":
		for x in section(a):
			if not mons_at(x).is_empty():
				return true
		return false
	return not mons_at(a).is_empty()


## Membri che possono colpire l'area a, con le possibili modalità: [[id, usew]].
func attackers_for(a: String) -> Array:
	var out := []
	for id in board_crew():
		for usew in [false, true]:
			if a in crew_targets(id, usew) and _has_targets(a, id, usew):
				out.append([id, usew])
	return out


# ---- mostri

func mon_mobile(id: int) -> bool:
	return mon.has(id) and int(D.MON[mon[id]["l"]]["mov"]) > 0 and not mon[id]["st"] and not moved.has(id)


func mon_moves(ids: Array) -> Dictionary:
	if ids.is_empty():
		return {}
	var mv := 9
	var loc: String = mon[ids[0]]["loc"]
	for id in ids:
		if not mon_mobile(id) or mon[id]["loc"] != loc:
			return {}
		mv = mini(mv, int(D.MON[mon[id]["l"]]["mov"]))
	return reach(loc, mv, false)


func mon_attack_areas() -> Array:
	var out := []
	for id in mon:
		var a: String = mon[id]["loc"]
		if out.has(a) or attacked.has(id) or mon[id]["st"] or matt(id) == 0:
			continue
		if not crew_at(a).is_empty():
			out.append(a)
	return out


func robot_id() -> int:
	for id in crew:
		if crew[id]["k"] == "robot":
			return id
	return -1


# ================================================================ svolgimento

func run() -> void:
	if solo():
		_setup_solo()
		while not game_over and not abort:
			turn_no += 1
			if max_turns > 0 and turn_no > max_turns:
				_end_timeout()
				break
			await _crew_turn()
			if game_over or abort:
				break
			await _solo_monster_turn()
		if not abort:
			_finish()
		return
	log_msg("La Znutar vaga nello spazio profondo… qualcosa di verde si muove nella stiva.")
	await _setup_crew()
	if abort:
		return
	await _setup_monsters()
	if abort:
		return
	await _discovery()
	while not game_over and not abort:
		turn_no += 1
		if max_turns > 0 and turn_no > max_turns:
			_end_timeout()
			break
		await _monster_turn()
		if game_over or abort:
			break
		await _crew_turn()
	if not abort:
		_finish()


func _setup_crew() -> void:
	phase = "crew_setup"
	var options := {}
	for id in crew:
		options[id] = cdef(id)["start"]
	var r = await decide(CREW_SEAT, {"type": "crew_setup", "options": options,
		"title": "Disponi l'equipaggio nelle aree di partenza"})
	for id in crew:
		var a = r.get(id, r.get(str(id), "")) if r is Dictionary else ""
		if not (a in options[id]):
			a = options[id][0]
		crew[id]["loc"] = a
	log_msg("L'equipaggio prende posto a bordo.")
	changed.emit()


func _setup_monsters() -> void:
	phase = "mon_setup"
	var p := d6()
	var pop: Array = D.POPULATION[p - 1]
	var left := {"E": pop[0], "B": pop[1], "A": pop[2]}
	if opts.get("extra_adult", false):
		left["A"] += 1
	dice = [p]
	dice_info = "Popolazione"
	log_msg("Tiro per la popolazione: %d → %d Uova, %d Piccoli, %d Adulti." % [p, left["E"], left["B"], left["A"]])
	_fx("dice", {"dice": [p], "info": "Popolazione iniziale", "total": p})
	var p2 := d6()
	var first := ""
	if p2 <= 5:
		first = D.FIRST_AREA[p2 - 1]
	if first == "" or not crew_at(first).is_empty():
		var free := D.FIRST_AREA.filter(func(a): return crew_at(a).is_empty())
		if free.is_empty():
			free = D.area_list().filter(func(a): return crew_at(a).is_empty())
		first = await choose_loc(MON_SEAT, "first", "Scegli dove compare la prima Cosa Verde", free)
	log_msg("Tiro per il primo mostro: %d → %s." % [p2, area_name(first)])
	_fx("dice", {"dice": [p2], "info": "Primo mostro: " + area_name(first), "total": p2})
	var placed := 0
	while left["A"] + left["B"] + left["E"] > 0 and not abort:
		var allowed: Array
		if placed == 0:
			allowed = [first]
		else:
			allowed = _placement_areas()
		var r = await decide(MON_SEAT, {"type": "mplace", "allowed": allowed, "left": left.duplicate(),
			"title": "Piazza le Cose Verdi: una per area, accanto a un'area già occupata"})
		var a: String = str(r.get("area", "")) if r is Dictionary else ""
		var l: String = str(r.get("l", "")) if r is Dictionary else ""
		if not (a in allowed):
			a = allowed[0]
		if not left.has(l) or left[l] <= 0:
			for k in ["A", "B", "E"]:
				if left[k] > 0:
					l = k
					break
		_add_mon(l, a)
		left[l] -= 1
		placed += 1
		last_area = a
		changed.emit()
	log_msg("Le Cose Verdi sono a bordo: %d in tutto." % placed)


func _placement_areas() -> Array:
	var occ := {}
	for id in mon:
		occ[mon[id]["loc"]] = true
	var out := []
	for a in occ:
		for n in adj(a):
			if not occ.has(n) and crew_at(n).is_empty() and not out.has(n):
				out.append(n)
	if out.is_empty():
		for a in D.area_list():
			if not occ.has(a) and crew_at(a).is_empty():
				out.append(a)
	out.sort()
	return out


func _add_mon(l: String, a: String) -> int:
	var id := _next_mid
	_next_mid += 1
	mon[id] = {"l": l, "loc": a, "st": false}
	return id


func _discovery() -> void:
	phase = "discovery"
	discovery = true
	moved = {}
	hot_entry = {}
	attacked = {}
	log_msg("Allarme! Uno o due membri dell'equipaggio scoprono le Cose Verdi.")
	await _crew_moves(2)
	if not moved.is_empty():
		phase = "discovery_attack"
		await _crew_attacks()
	discovery = false
	moved = {}
	hot_entry = {}
	attacked = {}
	_check_end()


# ---------------------------------------------------------------- turno dei mostri

func _monster_turn() -> void:
	moved = {}
	attacked = {}
	log_msg("— Turno %d: le Cose Verdi —" % turn_no)
	# 1. crescita
	phase = "grow"
	var opts_g := grow_options()
	if not opts_g.is_empty():
		var g = await decide(MON_SEAT, {"type": "grow", "options": opts_g, "title": "Quale livello fai crescere?"})
		if str(g) in opts_g:
			_apply_grow(str(g))
	changed.emit()
	# 2. movimento
	phase = "mmove"
	var guard := 0
	while not abort and guard < 300:
		guard += 1
		var any := false
		for id in mon:
			if mon_mobile(id):
				any = true
				break
		if not any:
			break
		var r = await decide(MON_SEAT, {"type": "mmove", "title": "Muovi le Cose Verdi (Adulti 2 aree, Piccoli 1)"})
		if not (r is Dictionary) or r.is_empty():
			break
		_apply_mmove(r)
	# recinti elettrici
	_fences()
	_check_end()
	if game_over:
		return
	# 3. attacco
	phase = "mattack"
	guard = 0
	while not abort and not game_over and guard < 100:
		guard += 1
		var areas := mon_attack_areas()
		if areas.is_empty():
			break
		var r = await decide(MON_SEAT, {"type": "mattack", "areas": areas, "title": "Attacca l'equipaggio"})
		if not (r is Dictionary) or r.is_empty():
			break
		_apply_mattack(r)
		_check_end()
	# 4. risveglio
	for id in mon:
		mon[id]["st"] = false
	moved = {}
	attacked = {}
	changed.emit()


func grow_options() -> Array:
	var out := []
	for l in ["F", "E", "B", "A"]:
		var n := 0
		for id in mon:
			if mon[id]["l"] == l and not mon[id]["st"]:
				n += 1
		if n == 0:
			continue
		var target := "E" if l == "A" else ("A" if l == "B" else "B")
		if avail(target) > 0:
			out.append(l)
	return out


func _apply_grow(l: String) -> void:
	var ids := []
	for id in mon:
		if mon[id]["l"] == l and not mon[id]["st"]:
			ids.append(id)
	ids.sort()
	var n := 0
	for id in ids:
		match l:
			"F", "E":
				if avail("B") > 0:
					mon[id]["l"] = "B"
					n += 1
			"B":
				if avail("A") > 0:
					mon[id]["l"] = "A"
					n += 1
			"A":
				if avail("E") > 0:
					_add_mon("E", mon[id]["loc"])
					n += 1
	var what := {"F": "%d Frammenti diventano Piccoli", "E": "%d Uova si schiudono in Piccoli",
		"B": "%d Piccoli diventano Adulti", "A": "Gli Adulti depongono %d Uova"}
	log_msg("Crescita: " + what[l] % n + ".")
	_fx("grow", {"l": l, "n": n})


func _apply_mmove(r: Dictionary) -> void:
	var ids := []
	for x in r.get("ids", []):
		ids.append(int(x))
	var to := str(r.get("to", ""))
	var paths := mon_moves(ids)
	if not paths.has(to):
		# mossa non valida: si fermano dove sono (evita cicli)
		for id in ids:
			moved[id] = true
		return
	var from: String = mon[ids[0]]["loc"]
	for id in ids:
		mon[id]["loc"] = to
		moved[id] = true
	last_area = to
	_fx("move", {"from": from, "path": paths[to], "mon": ids})
	changed.emit()


func _fences() -> void:
	var done := {}
	for w in wpn:
		var x: Dictionary = wpn[w]
		if x["t"] != "fence" or not x["on"] or x["out"] or x["c"] != -1:
			continue
		var a: String = x["loc"]
		if done.has(a) or mons_at(a).is_empty():
			continue
		done[a] = true
		var ch: String
		var learn := false
		if known.has("fence"):
			ch = known["fence"]
		else:
			ch = _draw()
			learn = true
		log_msg("Il Recinto elettrico in %s scarica sulle Cose Verdi." % area_name(a))
		var eff := {}
		for id in mons_at(a):
			eff[id] = _eff_add({}, ch, "fence")
		var rep := _apply_effects(eff)
		if learn:
			if ch in ["frag", "stun5", "kill5", "kill4", "kill3"] and not rep["used"].has("fence"):
				cup.append(ch)
			else:
				_learn("fence", ch)
		last_area = a
	changed.emit()


func _apply_mattack(r: Dictionary) -> void:
	var a := str(r.get("area", ""))
	if not (a in mon_attack_areas()):
		return
	var rob := robot_id()
	var robot_here: bool = on_board(rob) and crew[rob]["loc"] == a
	var used := {}
	var any := false
	for g in r.get("atk", []):
		if not (g is Array) or g.size() < 2:
			continue
		var cid := int(g[1])
		if not on_board(cid) or crew[cid]["loc"] != a:
			continue
		if robot_here and cid != rob:
			continue
		var ms := []
		for x in g[0]:
			var mid := int(x)
			if mon.has(mid) and mon[mid]["loc"] == a and not mon[mid]["st"] and not attacked.has(mid) \
					and not used.has(mid) and matt(mid) > 0:
				ms.append(mid)
				used[mid] = true
		if ms.is_empty():
			continue
		any = true
		var nd := 0
		for mid in ms:
			nd += matt(mid)
			attacked[mid] = true
		var tot := _roll_show(nd, "Cose Verdi contro %s" % cname(cid))
		var con: int = cdef(cid)["con"]
		if tot >= con:
			log_msg("%s %s: %d contro %d. Divorato!" % [_attackers(ms), cname(cid), tot, con])
			_crew_dies(cid)
			_fx("kill_crew", {"c": cid, "area": a})
			if cid == rob:
				_robot_eaten(ms[0])
			else:
				_eat(ms)
		else:
			log_msg("%s %s: %d contro %d. Respinti." % [_attackers(ms), cname(cid), tot, con])
	# i mostri dell'area che non hanno attaccato rinunciano
	for mid in mons_at(a):
		attacked[mid] = true
	if not any:
		log_msg("In %s le Cose Verdi non attaccano." % area_name(a))
	last_area = a
	changed.emit()


func _attackers(ms: Array) -> String:
	var cnt := {}
	for m in ms:
		cnt[mon[m]["l"]] = cnt.get(mon[m]["l"], 0) + 1
	var parts := []
	for l in D.MON_ORDER:
		if cnt.has(l):
			parts.append("%d %s" % [cnt[l], D.MON[l]["plural"] if cnt[l] > 1 else D.MON[l]["name"]])
	return ", ".join(parts) + (" attaccano" if ms.size() > 1 else " attacca")


func _crew_dies(cid: int) -> void:
	var a: String = crew[cid]["loc"]
	var w: int = crew[cid]["w"]
	if w >= 0:
		wpn[w]["c"] = -1
		wpn[w]["loc"] = a
		crew[cid]["w"] = -1
	crew[cid]["state"] = "dead"
	busy.erase(cid)


## Uno dei mostri che hanno ucciso divora il corpo e cresce di un livello (un Adulto depone un Uovo).
func _eat(ms: Array) -> void:
	var best := -1
	# di norma cresce un Piccolo; nel solitario mangia il più grosso che può crescere
	var pref := [["A", "E"], ["B", "A"], ["F", "B"]] if solo() else [["B", "A"], ["A", "E"], ["F", "B"]]
	for p in pref:
		for mid in ms:
			if mon[mid]["l"] == p[0] and avail(p[1]) > 0:
				best = mid
				break
		if best >= 0:
			break
	if best < 0:
		return
	match mon[best]["l"]:
		"B":
			mon[best]["l"] = "A"
			log_msg("Il Piccolo che ha mangiato diventa un Adulto.")
		"A":
			_add_mon("E", mon[best]["loc"])
			log_msg("L'Adulto che ha mangiato depone un Uovo.")
		"F":
			mon[best]["l"] = "B"
			log_msg("Il Frammento che ha mangiato diventa un Piccolo.")


func _robot_eaten(mid: int) -> void:
	var ch := _draw()
	log_msg("Una Cosa Verde prova a mangiare Piedipiombo… effetto: %s!" % chit_name(ch))
	_fx("chit", {"chit": ch, "t": "robot"})
	var eff := {mid: _eff_add({}, ch, "robot")}
	_apply_effects(eff)
	cup.append(ch)


# ---------------------------------------------------------------- turno dell'equipaggio

func _crew_turn() -> void:
	moved = {}
	hot_entry = {}
	attacked = {}
	busy = {}
	log_msg("— Turno %d: l'equipaggio —" % turn_no)
	# 1. prendere le armi
	phase = "grab"
	var guard := 0
	while not abort and guard < 200:
		guard += 1
		var acts := grab_actions()
		if acts.is_empty():
			break
		var r = await decide(CREW_SEAT, {"type": "grab", "actions": acts, "title": "Prendi, lascia o scambia le armi"})
		var i := int(r) if (r is int or r is float) else -1
		if i < 0 or i >= acts.size():
			break
		_apply_grab(acts[i])
	# 2. movimento
	phase = "cmove"
	await _crew_moves(99)
	if game_over or abort:
		return
	if solo():
		await _solo_alert()
		if game_over or abort:
			return
	# 3. attacco
	phase = "cattack"
	await _crew_attacks()
	if game_over or abort:
		return
	# fine turno: recinti montati, autodistruzione, risveglio
	for cid in busy:
		if not on_board(cid):
			continue
		if busy[cid] == "fence":
			var w: int = crew[cid]["w"]
			if w >= 0 and wtype(w) == "fence":
				wpn[w]["c"] = -1
				wpn[w]["loc"] = crew[cid]["loc"]
				wpn[w]["on"] = true
				crew[cid]["w"] = -1
				log_msg("%s attiva il Recinto elettrico in %s." % [cname(cid), area_name(crew[cid]["loc"])])
	if sd_left > 0:
		sd_left -= 1
		if sd_left == 0:
			_explode()
			return
		log_msg("Autodistruzione: mancano %d turni." % sd_left)
	for cid in busy:
		if busy[cid] == "sd" and on_board(cid) and sd_left < 0:
			sd_left = 3
			log_msg("%s avvia l'AUTODISTRUZIONE: la Znutar esploderà alla fine del terzo turno dell'equipaggio!" % cname(cid))
			_fx("alarm", {})
	for cid in crew:
		if crew[cid]["st"] > 0 and crew[cid]["st"] < turn_no:
			crew[cid]["st"] = 0
	busy = {}
	moved = {}
	hot_entry = {}
	attacked = {}
	if solo():
		_solo_free()
		_solo_end_of_turn()
	_check_end()
	changed.emit()


func grab_actions() -> Array:
	var out := []
	for cid in board_crew():
		if not awake(cid):
			continue
		var a: String = crew[cid]["loc"]
		var k: String = crew[cid]["k"]
		var w: int = crew[cid]["w"]
		if k != "mascot":
			var seen := {}
			for fw in weapons_at(a):
				var t := wtype(fw)
				if seen.has(t):
					continue
				seen[t] = true
				var lab := "%s prende %s" % [cdef(cid)["short"], wname(t)]
				if w >= 0:
					lab = "%s lascia %s e prende %s" % [cdef(cid)["short"], wname(wtype(w)), wname(t)]
				if wpn[fw]["on"]:
					lab = "%s smonta il Recinto acceso" % cdef(cid)["short"]
				out.append({"a": "take", "c": cid, "w": fw, "label": lab})
		if w >= 0:
			out.append({"a": "drop", "c": cid, "label": "%s lascia %s" % [cdef(cid)["short"], wname(wtype(w))]})
			for o in crew_at(a):
				if o == cid or o < 0 or not awake(o) or crew[o]["k"] == "mascot":
					continue
				if crew[o]["w"] >= 0 and o < cid:
					continue   # lo scambio fra due armati compare una volta sola
				var lab2 := "%s dà %s a %s" % [cdef(cid)["short"], wname(wtype(w)), cdef(o)["short"]]
				if crew[o]["w"] >= 0:
					lab2 = "%s e %s si scambiano le armi" % [cdef(cid)["short"], cdef(o)["short"]]
				out.append({"a": "swap", "c": cid, "o": o, "label": lab2})
	for fw in wpn:
		var x: Dictionary = wpn[fw]
		if x["t"] == "fence" and x["on"] and not x["out"] and x["c"] == -1:
			out.append({"a": "off", "w": fw, "label": "Spegni a distanza il Recinto in %s" % area_name(x["loc"])})
	return out


func _apply_grab(act: Dictionary) -> void:
	match act["a"]:
		"take":
			var cid: int = act["c"]
			var fw: int = act["w"]
			var old: int = crew[cid]["w"]
			if old >= 0:
				wpn[old]["c"] = -1
				wpn[old]["loc"] = crew[cid]["loc"]
			wpn[fw]["c"] = cid
			wpn[fw]["on"] = false
			crew[cid]["w"] = fw
			log_msg("%s prende: %s." % [cname(cid), wname(wtype(fw))])
		"drop":
			var cid: int = act["c"]
			var w: int = crew[cid]["w"]
			wpn[w]["c"] = -1
			wpn[w]["loc"] = crew[cid]["loc"]
			crew[cid]["w"] = -1
			log_msg("%s lascia: %s." % [cname(cid), wname(wtype(w))])
		"swap":
			var a: int = act["c"]
			var b: int = act["o"]
			var wa: int = crew[a]["w"]
			var wb: int = crew[b]["w"]
			crew[a]["w"] = wb
			crew[b]["w"] = wa
			if wa >= 0:
				wpn[wa]["c"] = b
			if wb >= 0:
				wpn[wb]["c"] = a
			log_msg("%s e %s si passano le armi." % [cname(a), cname(b)])
		"off":
			var fw: int = act["w"]
			wpn[fw]["on"] = false
			log_msg("Il Recinto in %s viene spento a distanza." % area_name(wpn[fw]["loc"]))
	changed.emit()


## Movimento dell'equipaggio (in scoperta al massimo 2 membri, solo verso aree con mostri).
func _crew_moves(limit: int) -> void:
	var guard := 0
	while not abort and guard < 200:
		guard += 1
		if discovery and moved.size() >= limit:
			break
		var any := false
		for cid in board_crew():
			if not crew_moves(cid).is_empty():
				any = true
				break
		if not any and (discovery or not _crew_has_special()):
			break
		var req := {"type": "cmove", "discovery": discovery,
			"title": "Scoperta! Muovi 1 o 2 membri in un'area con le Cose Verdi" if discovery else "Muovi l'equipaggio"}
		var r = await decide(CREW_SEAT, req)
		if not (r is Dictionary) or r.is_empty():
			if discovery and moved.is_empty() and any:
				continue   # la scoperta è obbligatoria
			break
		_apply_cmove(r)
		if game_over:
			return


func _crew_has_special() -> bool:
	for cid in board_crew():
		if not special_actions(cid).is_empty():
			return true
	return false


## Azioni speciali disponibili per un membro: montare il recinto, autodistruzione, fuga.
func special_actions(cid: int) -> Array:
	var out := []
	if discovery or not crew_can_act(cid) or moved.has(cid):
		return out
	var a: String = crew[cid]["loc"]
	var w: int = crew[cid]["w"]
	if w >= 0 and wtype(w) == "fence":
		out.append({"act": "fence", "c": cid, "label": "Monta il Recinto qui"})
	if solo():
		return out
	if crew[cid]["k"] in D.SD_CREW and a in D.BRIDGES and sd_left < 0 and not "sd" in busy.values():
		out.append({"act": "sd", "c": cid, "label": "Avvia l'autodistruzione"})
	if D.BOATS.has(a) and not launched.has(a):
		out.append({"act": "escape", "b": a, "c": cid, "label": "Fuggi con %s" % D.BOATS[a]["name"]})
	return out


func _apply_cmove(r: Dictionary) -> void:
	var act := str(r.get("act", ""))
	if act == "escape":
		_escape(str(r.get("b", "")), r.get("ids", []))
		return
	var cid := int(r.get("c", -1))
	if not crew.has(cid):
		return
	if act == "fence" or act == "sd":
		var ok := false
		for s in special_actions(cid):
			if s["act"] == act:
				ok = true
		if ok:
			busy[cid] = act
			moved[cid] = true
			attacked[cid] = true
			if act == "fence":
				log_msg("%s si ferma a montare il Recinto elettrico." % cname(cid))
			else:
				log_msg("%s inizia la procedura di autodistruzione." % cname(cid))
			changed.emit()
		return
	var to := str(r.get("to", ""))
	var paths := crew_moves(cid)
	if not paths.has(to):
		return
	var from: String = crew[cid]["loc"]
	crew[cid]["loc"] = to
	moved[cid] = true
	if hot_for_crew(to) or discovery:
		hot_entry[cid] = to
	last_area = to
	_fx("move", {"from": from, "path": paths[to], "crew": [cid]})
	changed.emit()


func boat_room(b: String, ids: Array) -> bool:
	var cap: int = D.BOATS[b]["cap"]
	if cap < 0:
		return true
	var n := 0
	for id in ids:
		if not (crew[int(id)]["k"] in ["robot", "mascot"]):
			n += 1
	return n <= cap


func _escape(b: String, ids_in: Array) -> void:
	if not D.BOATS.has(b) or launched.has(b):
		return
	var ids := []
	for x in ids_in:
		var id := int(x)
		if on_board(id) and awake(id) and crew[id]["loc"] == b and not ids.has(id):
			ids.append(id)
	if ids.is_empty() or not boat_room(b, ids):
		return
	var pilots := ids.filter(func(id): return not (crew[id]["k"] in ["robot", "mascot"]))
	if pilots.is_empty():
		return   # il Robot e la Mascotte non sanno pilotare
	launched[b] = true
	var names := []
	for id in ids:
		var w: int = crew[id]["w"]
		if w >= 0:
			wpn[w]["c"] = -1
			wpn[w]["loc"] = b
			crew[id]["w"] = -1
		crew[id]["state"] = "boat"
		crew[id]["loc"] = ""
		names.append(cdef(id)["short"])
	boats.append({"b": b, "crew": ids, "survivors": [], "fate": ""})
	log_msg("FUGA! %s parte con a bordo: %s." % [D.BOATS[b]["name"].capitalize(), ", ".join(names)])
	_fx("escape", {"b": b})
	changed.emit()
	_check_end()


func _crew_attacks() -> void:
	var guard := 0
	while not abort and not game_over and guard < 100:
		guard += 1
		var areas := crew_attack_areas()
		if areas.is_empty():
			break
		var r = await decide(CREW_SEAT, {"type": "cattack", "areas": areas, "discovery": discovery,
			"title": "Attacca le Cose Verdi"})
		if not (r is Dictionary) or r.is_empty():
			break
		_apply_cattack(r)
		_check_end()


# ---------------------------------------------------------------- risoluzione degli attacchi

func _draw() -> String:
	if cup.is_empty():
		for k in D.CHITS:
			for n in int(D.CHITS[k]["n"]):
				cup.append(k)
		for t in known:
			cup.erase(known[t])
	var i := rng.randi_range(0, cup.size() - 1)
	var ch: String = cup[i]
	cup.remove_at(i)
	return ch


## Aggiunge l'effetto di un gettone a quello di un mostro. src = tipo d'arma (per sapere se è servito).
func _eff_add(e: Dictionary, ch: String, src: String) -> Dictionary:
	if e.is_empty():
		e = {"grow": false, "shrink": false, "kill": 0, "frag": false, "stun": 0, "ksrc": [], "fsrc": [], "ssrc": []}
	match ch:
		"grow":
			e["grow"] = true
		"shrink":
			e["shrink"] = true
		"kill5", "kill4", "kill3":
			e["kill"] += int(ch.substr(4))
			e["ksrc"].append(src)
		"frag":
			e["frag"] = true
			e["fsrc"].append(src)
		"stun5":
			e["stun"] += 5
			e["ssrc"].append(src)
	return e


## Applica gli effetti nell'ordine del regolamento: Cresce, Rimpicciolisce, dadi per uccidere,
## Frammenti, dadi per stordire. Restituisce {"used": tipi d'arma che hanno avuto effetto, "killed": n}.
func _apply_effects(eff: Dictionary) -> Dictionary:
	var used := {}
	var killed := 0
	var ids := eff.keys()
	ids.sort()
	var parts := []
	# 1. Cresce
	for id in ids:
		if mon.has(id) and eff[id]["grow"]:
			var l: String = mon[id]["l"]
			if l in ["F", "E"] and avail("B") > 0:
				mon[id]["l"] = "B"
			elif l == "B" and avail("A") > 0:
				mon[id]["l"] = "A"
			elif l == "A" and opts.get("grow_eggs", false) and avail("E") > 0:
				_add_mon("E", mon[id]["loc"])
			parts.append("%s cresce" % D.MON[l]["name"])
	# 2. Rimpicciolisce
	for id in ids:
		if mon.has(id) and eff[id]["shrink"]:
			var l: String = mon[id]["l"]
			var to: String = {"A": "B", "B": "E", "F": "E", "E": ""}[l]
			if to == "" or avail(to) <= 0:
				mon.erase(id)
				killed += 1
				parts.append("%s svanisce" % D.MON[l]["name"])
			else:
				mon[id]["l"] = to
				parts.append("%s rimpicciolisce" % D.MON[l]["name"])
	# 3. dadi per uccidere (comprese le mani)
	for id in ids:
		if mon.has(id) and eff[id]["kill"] > 0:
			for s in eff[id]["ksrc"]:
				used[s] = true
			var nm := mname(id)
			var tot := _roll_show(eff[id]["kill"], "%d dadi contro %s (cost. %d)" % [eff[id]["kill"], nm, mcon(id)])
			if tot >= mcon(id):
				_fx("kill_mon", {"area": mon[id]["loc"], "l": mon[id]["l"]})
				mon.erase(id)
				killed += 1
				parts.append("%s ucciso (%d)" % [nm, tot])
			else:
				parts.append("%s resiste (%d)" % [nm, tot])
	# 4. Frammenti (solo i mostri ancora vivi)
	for id in ids:
		if mon.has(id) and eff[id]["frag"]:
			for s in eff[id]["fsrc"]:
				used[s] = true
			var a: String = mon[id]["loc"]
			var nm := mname(id)
			mon.erase(id)
			killed += 1
			var n := d6()
			var made := 0
			for i in n:
				if avail("F") > 0:
					_add_mon("F", a)
					made += 1
			_fx("frag", {"area": a, "n": made})
			parts.append("%s esplode in %d Frammenti" % [nm, made])
	# 5. dadi per stordire
	for id in ids:
		if mon.has(id) and eff[id]["stun"] > 0:
			for s in eff[id]["ssrc"]:
				used[s] = true
			var nm := mname(id)
			var tot := _roll_show(eff[id]["stun"], "%d dadi per stordire %s" % [eff[id]["stun"], nm])
			if tot >= mcon(id):
				mon[id]["st"] = true
				parts.append("%s stordito (%d)" % [nm, tot])
			else:
				parts.append("%s non si stordisce (%d)" % [nm, tot])
	if not parts.is_empty():
		log_msg("   " + "; ".join(parts) + ".")
	return {"used": used, "killed": killed}


func _learn(t: String, ch: String) -> void:
	if t == "beamer" and opts.get("beamer2", false) and known.has(t) and not known2.has(t):
		known2[t] = ch
	else:
		known[t] = ch
	log_msg("Scoperto: %s → %s." % [wname(t), chit_name(ch)])
	_fx("chit", {"chit": ch, "t": t})
	if ch == "none" and not (t == "beamer" and known2.has(t)):
		# arma inutile: i suoi segnalini lasciano il tabellone
		for w in wpn:
			if wpn[w]["t"] == t and not wpn[w]["out"]:
				var c: int = wpn[w]["c"]
				if c >= 0:
					crew[c]["w"] = -1
				wpn[w]["c"] = -1
				wpn[w]["out"] = true
				wpn[w]["loc"] = ""


func _apply_cattack(r: Dictionary) -> void:
	var x := str(r.get("area", ""))
	if not (x in crew_attack_areas()):
		return
	# dichiarazioni valide
	var entries := []
	var seen := {}
	for e in r.get("atk", []):
		if not (e is Array) or e.size() < 3:
			continue
		var cid := int(e[0])
		var usew := bool(e[1])
		var tgt := int(e[2])
		if not crew.has(cid) or seen.has(cid) or not (x in crew_targets(cid, usew)):
			continue
		var kind := "hand"
		if usew:
			kind = D.WEAPONS[wtype(crew[cid]["w"])]["kind"]
			if kind == "fence":
				continue
		if kind in ["hand", "single"]:
			if not mon.has(tgt) or mon[tgt]["loc"] != x:
				continue
		seen[cid] = true
		entries.append({"c": cid, "usew": usew, "tgt": tgt, "kind": kind, "t": wtype(crew[cid]["w"]) if usew else ""})
	if entries.is_empty():
		return
	last_area = x
	# gettoni per le armi non ancora provate
	var untried := []
	for e in entries:
		if e["usew"] and not known.has(e["t"]) and not untried.has(e["t"]):
			untried.append(e["t"])
	var chit_for := {}
	var shared := ""
	var learn_t := ""
	if untried.size() == 1:
		learn_t = untried[0]
		chit_for[learn_t] = _draw()
	elif untried.size() > 1:
		shared = _draw()
		for t in untried:
			chit_for[t] = shared
		log_msg("Più armi nuove insieme: un solo gettone vale per tutte, solo per questo attacco (%s)." % chit_name(shared))
		_fx("chit", {"chit": shared, "t": ""})
	# beamer a due frequenze: se la prima è nota ma deludente, si prova l'altra
	if opts.get("beamer2", false):
		for e in entries:
			if e["t"] == "beamer" and known.has("beamer") and not known2.has("beamer") and learn_t == "" and shared == "" \
					and D.CHIT_ORDER.find(known["beamer"]) >= D.CHIT_ORDER.find("stun5"):
				learn_t = "beamer"
				chit_for["beamer"] = _draw()
				log_msg("Il Comunicatore viene regolato sull'altra frequenza…")
				break
	for t in known:
		if not chit_for.has(t):
			chit_for[t] = effect_of(t)
	# effetti sui mostri
	var eff := {}
	var gas_done := {}
	var gas_areas := {}
	var fuel_areas := {}
	var desc := []
	for e in entries:
		var cid: int = e["c"]
		if not e["usew"]:
			var tg: int = e["tgt"]
			eff[tg] = _eff_add(eff.get(tg, {}), "", "hand")
			eff[tg]["kill"] += int(cdef(cid)["att"])
			eff[tg]["ksrc"].append("hand")
			desc.append("%s a mani nude su %s" % [cdef(cid)["short"], mname(tg)])
			continue
		var t: String = e["t"]
		var ch: String = chit_for.get(t, "none")
		var targets := []
		match e["kind"]:
			"single":
				targets = [e["tgt"]]
				desc.append("%s usa %s su %s" % [cdef(cid)["short"], wname(t), mname(e["tgt"])])
			"area":
				targets = mons_at(x)
				desc.append("%s usa %s su %s" % [cdef(cid)["short"], wname(t), area_name(x)])
			"blast":
				for s in section(x):
					targets.append_array(mons_at(s))
					if t == "grenade":
						gas_areas[s] = true
					else:
						fuel_areas[s] = fuel_areas.get(s, 0) + 5
				desc.append("%s lancia %s in %s" % [cdef(cid)["short"], wname(t), area_name(x)])
		for tg in targets:
			if t == "grenade":
				if gas_done.has(tg):
					continue
				gas_done[tg] = true
			eff[tg] = _eff_add(eff.get(tg, {}), ch, t)
	log_msg("Attacco in %s: %s." % [area_name(x), "; ".join(desc)])
	_fx("attack", {"area": x, "crew": entries.map(func(e): return e["c"])})
	var rep := _apply_effects(eff)
	# cosa si è imparato
	var unlearned := false
	if learn_t != "":
		var ch: String = chit_for[learn_t]
		if ch in ["frag", "stun5", "kill5", "kill4", "kill3"] and not rep["used"].has(learn_t):
			# tutti i bersagli erano già spariti: l'arma non è stata davvero provata
			cup.append(ch)
			unlearned = true
			log_msg("I bersagli sono spariti prima che %s facesse effetto: l'arma resta da provare." % wname(learn_t))
		else:
			_learn(learn_t, ch)
	if shared != "":
		cup.append(shared)
	# armi da lancio: tornano al loro deposito; il coltello lanciato resta dove è caduto
	for e in entries:
		var cid: int = e["c"]
		attacked[cid] = true
		if not e["usew"]:
			continue
		var w: int = crew[cid]["w"]
		if w < 0 or wpn[w]["out"]:
			continue
		var t: String = e["t"]
		if unlearned and t == learn_t:
			continue
		var back: Array = D.WEAPONS[t].get("back", [])
		if not back.is_empty():
			var dest: String = back[0]
			if back.size() > 1:
				var best := 99
				for b in back:
					var n := 0
					for o in weapons_at(b):
						if wtype(o) == t:
							n += 1
					if n < best:
						best = n
						dest = b
			wpn[w]["c"] = -1
			wpn[w]["loc"] = dest
			crew[cid]["w"] = -1
		elif t == "knife" and x != crew[cid]["loc"]:
			wpn[w]["c"] = -1
			wpn[w]["loc"] = x
			crew[cid]["w"] = -1
	# effetti di gas e carburante sull'equipaggio
	for s in gas_areas:
		for cid in crew_at(s):
			if crew[cid]["k"] == "robot":
				continue
			var tot := _roll_show(5, "Gas contro %s" % cname(cid))
			if tot >= int(cdef(cid)["con"]):
				crew[cid]["st"] = turn_no
				log_msg("   Il gas stordisce anche %s (%d)." % [cname(cid), tot])
	for s in fuel_areas:
		for cid in crew_at(s):
			var tot := _roll_show(fuel_areas[s], "Esplosione contro %s" % cname(cid))
			if tot >= int(cdef(cid)["con"]):
				log_msg("   L'esplosione uccide %s (%d)!" % [cname(cid), tot])
				_crew_dies(cid)
				_fx("kill_crew", {"c": cid, "area": s})
			else:
				log_msg("   %s sopravvive all'esplosione (%d)." % [cname(cid), tot])
	changed.emit()


# ================================================================ solitario (Capitano Yid)
## Regole di Solitaire Rules v1.1: il Capitano torna sulla Znutar e trova tutti addormentati.
## In ogni area ci sono pedine coperte (Cose Verdi in letargo o membri dell'equipaggio prigionieri):
## si scoprono entrando. Le Cose Verdi si muovono da sole con regole fisse.

const SOLO_FINAL := ["dc", "bridge1", "bridge2", "mshop", "aft_ms", "engine"]

var hidden := {}          # area -> [{"c": id} | {"l": livello}, "seen": bool]
var final_charge := -1    # turno dell'equipaggio alla fine del quale si sveglia tutto
var _woke := false        # in questo turno l'equipaggio ha svegliato qualcosa


func solo() -> bool:
	return opts.get("solo", false)


func hidden_at(a: String) -> Array:
	return hidden.get(a, [])


func hidden_mon(l: String) -> int:
	var n := 0
	for a in hidden:
		for t in hidden[a]:
			if t.get("l", "") == l:
				n += 1
	return n


func captives_at(a: String) -> Array:
	var out := []
	for id in crew:
		if crew[id]["state"] == "captive" and crew[id]["loc"] == a:
			out.append(id)
	return out


func _setup_solo() -> void:
	phase = "crew_setup"
	var cap := -1
	var toks := []
	for id in crew:
		if crew[id]["k"] == "captain":
			cap = id
		else:
			toks.append({"c": id})
			crew[id]["state"] = "hidden"
	for l in ["A", "B", "E", "F"]:
		for i in int(D.MON[l]["limit"]):
			toks.append({"l": l})
	_shuffle(toks)
	var plan := {}
	var waeps := {}
	for w in wpn:
		waeps[wpn[w]["loc"]] = true
	for a in D.area_list():
		if D.BOATS.has(a):
			continue
		var n := 1
		if waeps.has(a):
			n += 2
		if a in ["dc", "mshop", "aft_ms"]:
			n += 2
		if a in D.BRIDGES:
			n += 4
		plan[a] = n
	for a in plan:
		hidden[a] = []
		for i in plan[a]:
			if toks.is_empty():
				break
			hidden[a].append(toks.pop_back())
	while not toks.is_empty():
		hidden["engine"].append(toks.pop_back())
	for a in hidden:
		for t in hidden[a]:
			t["seen"] = false
			if t.has("c"):
				crew[int(t["c"])]["loc"] = a
	crew[cap]["loc"] = "saucer"
	log_msg("Il Capitano Yid atterra con il Disco: nessuno risponde. Le Cose Verdi dormono, e l'equipaggio è la loro dispensa.")
	log_msg("Ogni area nasconde pedine coperte: entrando si scopre chi c'è. Attenti al Ponte, all'Officina e alla Sala macchine…")
	changed.emit()


func _solo_setup_weapons() -> void:
	# un Estintore e un Comunicatore escono dal gioco; via il gettone «5 dadi per uccidere»
	for w in wpn.keys():
		if (wpn[w]["t"] == "extinguisher" and wpn[w]["loc"] == "aft_ms") or (wpn[w]["t"] == "beamer" and wpn[w]["loc"] == "sensor2"):
			wpn.erase(w)
	cup.erase("kill5")
	opts["grow_eggs"] = true


## Fase di allarme: si scoprono le pedine nelle aree dove c'è l'equipaggio.
func _solo_alert() -> void:
	phase = "alert"
	var areas := []
	for cid in board_crew():
		var a: String = crew[cid]["loc"]
		if not hidden_at(a).is_empty() and not areas.has(a):
			areas.append(a)
	areas.sort()
	for a in areas:
		_woke = true
		var toks: Array = hidden[a]
		hidden.erase(a)
		var new_m := []
		var found := []
		for t in toks:
			if t.has("l"):
				new_m.append(_add_mon(str(t["l"]), a))
			else:
				found.append(int(t["c"]))
		var parts := []
		for l in D.MON_ORDER:
			var k := new_m.filter(func(m): return mon[m]["l"] == l).size()
			if k > 0:
				parts.append("%d %s" % [k, D.MON[l]["plural"] if k > 1 else D.MON[l]["name"]])
		for c in found:
			parts.append(cname(c))
		log_msg("Allarme in %s! Sotto le pedine: %s." % [area_name(a), ", ".join(parts)])
		for c in found:
			crew[c]["state"] = "captive"
		last_area = a
		_fx("alert", {"area": a})
		changed.emit()
		if a in SOLO_FINAL and final_charge < 0:
			final_charge = turn_no + 1
			log_msg("Il rumore arriva fino agli altri! Alla fine del prossimo turno dell'equipaggio si sveglieranno tutte le Cose Verdi.")
			_fx("charge_soon", {})
		# le Cose Verdi appena svegliate attaccano subito
		if not new_m.is_empty():
			_solo_mattack(a, new_m)
			_check_end()
			if game_over:
				return
		_solo_free()
	changed.emit()


## I prigionieri si liberano quando nella loro area c'è l'equipaggio e non ci sono più Cose Verdi.
func _solo_free() -> void:
	for id in crew:
		if crew[id]["state"] != "captive":
			continue
		var a: String = crew[id]["loc"]
		if mons_at(a).is_empty() and not crew_at(a).is_empty():
			crew[id]["state"] = "ok"
			crew[id]["st"] = 0
			moved[id] = true
			log_msg("%s è libero e si unisce al Capitano!" % cname(id))
			_fx("free", {"c": id, "area": a})
	changed.emit()


## Attacco automatico: tutti insieme sul più debole dell'area (il Robot per primo).
func _solo_mattack(a: String, only := []) -> void:
	var ms := []
	for m in mons_at(a):
		if (only.is_empty() or only.has(m)) and not mon[m]["st"] and matt(m) > 0 and not attacked.has(m):
			ms.append(m)
	var cs := crew_at(a)
	if ms.is_empty() or cs.is_empty():
		return
	var rob := robot_id()
	var target := -1
	if cs.has(rob):
		target = rob
	else:
		var best := []
		var bk := 99999
		for c in cs:
			var k := int(cdef(c)["con"]) * 10 + int(cdef(c)["att"])
			if k < bk:
				bk = k
				best = [c]
			elif k == bk:
				best.append(c)
		target = best[rng.randi_range(0, best.size() - 1)]
	# chi mangia: il livello più alto che può crescere
	var eater := -1
	for want in [["A", "E"], ["B", "A"], ["F", "B"]]:
		for m in ms:
			if mon[m]["l"] == want[0] and avail(want[1]) > 0:
				eater = m
				break
		if eater >= 0:
			break
	if eater >= 0:
		ms.erase(eater)
		ms.push_front(eater)
	_apply_mattack({"area": a, "atk": [[ms, target]]})


func _solo_monster_turn() -> void:
	moved = {}
	attacked = {}
	if mon.is_empty():
		return
	log_msg("— Turno %d: le Cose Verdi —" % turn_no)
	# 1. crescita: tutte, a cominciare dalle più vicine all'equipaggio
	phase = "grow"
	var ids := mon.keys().filter(func(m): return not mon[m]["st"])
	ids.sort_custom(func(x, y): return _near_crew(mon[x]["loc"]) < _near_crew(mon[y]["loc"]) or (_near_crew(mon[x]["loc"]) == _near_crew(mon[y]["loc"]) and x < y))
	var cnt := {"A": 0, "B": 0, "E": 0, "F": 0}
	for m in ids:
		match mon[m]["l"]:
			"A":
				if avail("E") > 0:
					_add_mon("E", mon[m]["loc"])
					cnt["A"] += 1
			"B":
				if avail("A") > 0:
					mon[m]["l"] = "A"
					cnt["B"] += 1
			"E", "F":
				if avail("B") > 0:
					cnt[mon[m]["l"]] += 1
					mon[m]["l"] = "B"
	var gp := []
	if cnt["A"] > 0:
		gp.append("%d Uova deposte" % cnt["A"])
	if cnt["B"] > 0:
		gp.append("%d Piccoli diventano Adulti" % cnt["B"])
	if cnt["E"] > 0:
		gp.append("%d Uova si schiudono" % cnt["E"])
	if cnt["F"] > 0:
		gp.append("%d Frammenti diventano Piccoli" % cnt["F"])
	log_msg("Crescita frenetica: " + (", ".join(gp) if not gp.is_empty() else "niente può crescere") + ".")
	_fx("grow", {"l": "A", "n": cnt["A"] + cnt["B"] + cnt["E"] + cnt["F"]})
	changed.emit()
	# 2. movimento verso l'equipaggio più vicino
	phase = "mmove"
	var order := mon.keys()
	order.sort()
	for m in order:
		if not mon.has(m) or not mon_mobile(m):
			continue
		var to := _solo_dest(m)
		if to != "" and to != mon[m]["loc"]:
			_apply_mmove({"ids": [m], "to": to})
		moved[m] = true
	_fences()
	_check_end()
	if game_over:
		return
	# 3. attacco
	phase = "mattack"
	var areas := mon_attack_areas()
	areas.sort()
	for a in areas:
		_solo_mattack(a)
		for m in mons_at(a):
			attacked[m] = true
		_check_end()
		if game_over:
			return
	_solo_free()
	for id in mon:
		mon[id]["st"] = false
	moved = {}
	attacked = {}
	changed.emit()


func _near_crew(a: String) -> int:
	var d := 99
	for c in board_crew():
		d = mini(d, dist(a, crew[c]["loc"]))
	return d


## Destinazione di una Cosa Verde: verso il membro dell'equipaggio più vicino (a pari distanza il più debole).
func _solo_dest(m: int) -> String:
	var here: String = mon[m]["loc"]
	if not crew_at(here).is_empty():
		return here
	var bd := 99
	var targets := []
	for c in board_crew():
		var d := dist(here, crew[c]["loc"])
		var k := int(cdef(c)["con"]) * 10 + int(cdef(c)["att"])
		if d < bd:
			bd = d
			targets = [[k, crew[c]["loc"]]]
		elif d == bd:
			targets.append([k, crew[c]["loc"]])
	if targets.is_empty():
		return here
	targets.sort_custom(func(x, y): return x[0] < y[0])
	var goal: String = targets[0][1]
	var paths := reach(here, int(D.MON[mon[m]["l"]]["mov"]), false)
	var best := []
	var bdist := dist(here, goal)
	for a in paths:
		var d := dist(a, goal)
		if d < bdist:
			bdist = d
			best = [a]
		elif d == bdist and not best.is_empty():
			best.append(a)
	if best.is_empty():
		return here
	best.sort()
	return best[rng.randi_range(0, best.size() - 1)]


## Fine del turno dell'equipaggio: risveglio spontaneo e carica finale.
func _solo_end_of_turn() -> void:
	if final_charge > 0 and turn_no >= final_charge:
		final_charge = 0
		var n := 0
		for a in hidden.keys():
			for t in hidden[a]:
				if t.has("l"):
					_add_mon(str(t["l"]), a)
					n += 1
				else:
					crew[int(t["c"])]["state"] = "captive"
			hidden.erase(a)
		log_msg("LA CARICA FINALE! Tutta la Znutar si sveglia: %d Cose Verdi affamate escono dal letargo." % n)
		_fx("charge", {})
		_solo_free()
		changed.emit()
		return
	if _woke:
		_woke = false
		return
	# nessuno svegliato: si sveglia da sola la pedina più lontana dall'equipaggio
	var best_a := ""
	var bd := -1
	var bn := 0
	for a in hidden:
		var free: Array = hidden[a].filter(func(t): return not t["seen"])
		if free.is_empty():
			continue
		var d := _near_crew(a)
		if d > bd or (d == bd and hidden[a].size() > bn):
			bd = d
			bn = hidden[a].size()
			best_a = a
	if best_a == "":
		return
	var free2: Array = hidden[best_a].filter(func(t): return not t["seen"])
	var t: Dictionary = free2[rng.randi_range(0, free2.size() - 1)]
	if t.has("c"):
		t["seen"] = true
		log_msg("Qualcosa si muove in %s… ma è solo %s, ancora prigioniero nella melma." % [area_name(best_a), cname(int(t["c"]))])
	else:
		hidden[best_a].erase(t)
		if hidden[best_a].is_empty():
			hidden.erase(best_a)
		_add_mon(str(t["l"]), best_a)
		log_msg("In %s una Cosa Verde si sveglia da sola: %s!" % [area_name(best_a), D.MON[t["l"]]["name"]])
		last_area = best_a
	changed.emit()


# ================================================================ fine partita

func _explode() -> void:
	log_msg("KABOOM! La Znutar esplode: tutte le Cose Verdi sono distrutte, e con loro chi era ancora a bordo.")
	_fx("explode", {})
	mon = {}
	for cid in board_crew():
		_crew_dies(cid)
	sd_left = 0
	_epilogue_and_end("sd")


func _check_end() -> void:
	if game_over:
		return
	if mon.is_empty() and solo() and (hidden_mon("A") + hidden_mon("B") + hidden_mon("E") + hidden_mon("F")) == 0:
		var pts := 0.0
		for cid in crew:
			if crew[cid]["state"] in ["ok", "captive", "hidden"] and not (crew[cid]["k"] in ["robot", "mascot"]):
				pts += float(cdef(cid)["con"])
		vp = [pts, 0.0]
		_end("crew", "Il Capitano Yid ha liberato la Znutar: tutte le Cose Verdi sono state sterminate!")
		return
	if solo():
		if board_crew().is_empty():
			vp = [0.0, D.VP_TAKEOVER]
			_end("mon", "Nessuno è rimasto sveglio: le Cose Verdi tornano a dormire con la dispensa piena.")
		return
	if mon.is_empty():
		var pts := 0.0
		for cid in board_crew():
			if not (crew[cid]["k"] in ["robot", "mascot"]):
				pts += float(cdef(cid)["con"])
		log_msg("Le Cose Verdi sono state sterminate!")
		_epilogue_and_end("exterminated", pts)
		return
	if board_crew().is_empty():
		if boats.is_empty():
			vp = [0.0, D.VP_TAKEOVER]
			_end("mon", "Le Cose Verdi si sono prese la Znutar: tutto l'equipaggio è stato divorato.")
		else:
			if sd_left > 0:
				log_msg("La nave abbandonata esplode poco dopo la fuga.")
				mon = {}
				sd_left = 0
				_epilogue_and_end("sd")
			else:
				_epilogue_and_end("escape")


var _ending := false

func _epilogue_and_end(kind: String, aboard_pts := 0.0) -> void:
	if _ending:
		return
	_ending = true
	game_over = true   # nessun'altra fase; l'epilogo si gioca in _finish
	_pending_end = {"kind": kind, "aboard": aboard_pts}


var _pending_end := {}


func _end(w: String, why: String) -> void:
	game_over = true
	winner = w
	end_reason = why
	log_msg("■ " + why)


func _end_timeout() -> void:
	game_over = true
	winner = "draw"
	end_reason = "Limite di turni raggiunto."
	log_msg("■ " + end_reason)


## Viaggio di ritorno di una scialuppa (Epilogo del regolamento). Restituisce i sopravvissuti.
func _epilogue_boat(bt: Dictionary) -> void:
	var people: Array = bt["crew"].duplicate()
	var bname: String = D.BOATS[bt["b"]]["name"]
	log_msg("Epilogo: il viaggio %s." % D.BOATS[bt["b"]]["of"])
	var step := 1
	var guard := 0
	var years := 0
	while guard < 80 and not abort:
		guard += 1
		var r := 0
		match step:
			1:
				var c := await pick(CREW_SEAT, "epi1", "%s: che rotta?" % bname.capitalize(),
					["Dritti verso Snudl-1", "Verso l'ultimo pianeta visitato"], {"boat": bt["b"]})
				step = 7 if c == 0 else 3
			2:
				years += 1
				r = d6()
				log_msg("   Un anno nello spazio (%d)." % r)
				step = 7 if r <= 3 else 8
			3:
				r = d6()
				log_msg("   Atterraggio su un mondo già esplorato (%d)." % r)
				step = 4 if r <= 4 else 6
			4:
				var c2 := await pick(CREW_SEAT, "epi4", "%s: indigeni ostili! Che fare?" % bname.capitalize(),
					["Combattere", "Scappare"], {"boat": bt["b"]})
				step = 5 if c2 == 0 else 8
			5:
				var n := d6()
				var mine := 0
				for id in people:
					mine += int(cdef(id)["att"])
				var a := total(roll(mine))
				var b := total(roll(n))
				log_msg("   Battaglia con %d indigeni: equipaggio %d, indigeni %d." % [n, a, b])
				if a > b:
					step = 6
				else:
					var v: int = people[rng.randi_range(0, people.size() - 1)]
					people.erase(v)
					log_msg("   %s cade in battaglia." % cname(v))
					if _no_humans(people):
						break
					step = 4
			6:
				r = d6()
				log_msg("   Viveri e carburante riforniti (%d)." % r)
				step = 2 if r <= 4 else 12
			7:
				years += 2
				r = d6()
				log_msg("   Due anni nello spazio (%d)." % r)
				step = 13 if r <= 3 else 14
			8:
				r = d6()
				log_msg("   Persi nello spazio (%d)." % r)
				step = 9 if r <= 3 else 10
			9:
				r = d6()
				log_msg("   Vicino a un buco nero (%d)." % r)
				step = 2 if r <= 3 else 11
			10:
				r = d6()
				log_msg("   Attraverso una nube cosmica (%d)." % r)
				step = 8 if r <= 3 else 15
			11:
				log_msg("   %s scompare nel nulla. Nessuno tornerà." % bname.capitalize())
				people = []
				break
			12:
				log_msg("   %s raggiunge Snudl-1!" % bname.capitalize())
				break
			13:
				r = d6()
				log_msg("   Atterraggio su uno strano planetoide (%d)." % r)
				step = 6 if r <= 3 else 15
			14:
				years += 4
				var c3 := await pick(CREW_SEAT, "epi14", "%s: quattro anni di viaggio, le scorte finiscono. Rotta?" % bname.capitalize(),
					["Verso Snudl-1", "Verso un mondo già esplorato"], {"boat": bt["b"]})
				step = 2 if c3 == 0 else 3
			15:
				log_msg("   Una strana malattia colpisce l'equipaggio.")
				for id in people.duplicate():
					var t := total(roll(4))
					if t >= int(cdef(id)["con"]):
						people.erase(id)
						log_msg("   %s muore (%d)." % [cname(id), t])
				if _no_humans(people):
					break
				r = d6()
				step = 6 if r <= 3 else 7
		if _no_humans(people):
			break
	if guard >= 80:
		log_msg("   Il viaggio non finisce mai… nessuno torna a casa.")
		people = []
	if step != 12:
		people = []
	bt["survivors"] = people
	bt["fate"] = "home" if not people.is_empty() else "lost"


# ---------------------------------------------------------------- epilogo alternativo (variante)

func d10() -> int:
	return rng.randi_range(1, 10)


func _has_k(people: Array, k: String) -> bool:
	for id in people:
		if crew[id]["k"] == k:
			return true
	return false


## Tabella a d10: [[massimo, passo], ...] → il passo del primo massimo che contiene il tiro.
static func _tab(r: int, t: Array) -> int:
	for e in t:
		if r <= int(e[0]):
			return int(e[1])
	return int(t[t.size() - 1][1])


## Epilogo alternativo (35 eventi, d10, stato della scialuppa e bonus dei membri dell'equipaggio).
func _epilogue_alt(bt: Dictionary) -> void:
	var people: Array = bt["crew"].duplicate()
	var bn: String = String(D.BOATS[bt["b"]]["name"]).capitalize()
	var weapons := []
	for w in wpn:
		if wpn[w]["loc"] == bt["b"] and int(wpn[w]["c"]) == -1:
			weapons.append(wpn[w]["t"])
	log_msg("Epilogo alternativo: il viaggio %s." % D.BOATS[bt["b"]]["of"])
	var low := false
	var damaged := false
	var lost := false
	var low_years := 0
	var years := 0
	var attacked := false
	var intelligent := false
	var fate := "lost"
	var step := 1
	var guard := 0
	var x := {"boat": bt["b"]}
	while guard < 120 and not abort:
		guard += 1
		var r := 0
		var yrs := 0
		var set_low := false
		match step:
			1:
				var c := await pick(CREW_SEAT, "alt1", "%s: che rotta?" % bn,
					["Dritti verso Snudl-1", "Verso l'ultimo pianeta visitato", "Verso un sistema inesplorato vicino"], x)
				step = [33, 19, 30][clampi(c, 0, 2)]
			2:
				yrs = 1
				r = d10()
				log_msg("   Un anno nello spazio (%d)." % r)
				step = _tab(r, [[3, 21], [7, 34], [10, 3]])
			3:
				r = d10()
				log_msg("   Atterraggio su un pianeta abitabile (%d)." % r)
				step = _tab(r, [[3, 4], [6, 22], [10, 6]])
			4, 22:
				if step == 4:
					intelligent = false
					log_msg("   Alieni ostili!")
				else:
					intelligent = true
					log_msg("   Segni di vita intelligente!")
				var c2 := await pick(CREW_SEAT, "alt4", "%s: %s Che fare?" % [bn, "alieni ostili!" if step == 4 else "vita intelligente!"],
					["Evitare il contatto", "Attaccare", "Tentare di comunicare"], x)
				step = [35, 5, 24][clampi(c2, 0, 2)]
			5:
				attacked = true
				var n := d6()
				var mine := 0
				for id in people:
					mine += int(cdef(id)["att"])
				var a := total(roll(mine))
				var bonus := ""
				if weapons.has("pistol") or weapons.has("fuel") or weapons.has("grenade"):
					var ks: Array = D.CHITS.keys()
					var ch: String = ks[rng.randi_range(0, ks.size() - 1)]
					if ch.begins_with("kill"):
						var kd := int(ch.substr(4))
						a += total(roll(kd))
						bonus = " (armi: +%d dadi)" % kd
				var b := 0
				for i in n:
					b += d10() if intelligent else d6()
				log_msg("   Battaglia con %d alieni: equipaggio %d%s, alieni %d." % [n, a, bonus, b])
				if a > b:
					step = 6
				else:
					var v: int = people[rng.randi_range(0, people.size() - 1)]
					people.erase(v)
					log_msg("   %s cade in battaglia." % cname(v))
					step = 4
			6:
				low = false
				low_years = 0
				r = d10()
				log_msg("   Viveri e carburante riforniti (%d)." % r)
				step = _tab(r, [[2, 2], [4, 7], [7, 32], [10, 14]])
			7:
				yrs = 2
				r = d10()
				log_msg("   Due anni nello spazio (%d)." % r)
				step = _tab(r, [[2, 10], [4, 13], [8, 34], [10, 3]])
			8:
				lost = true
				r = d10() + (1 if _has_k(people, "pilot_y") or _has_k(people, "pilot_b") else 0)
				log_msg("   Persi nello spazio (%d)." % r)
				step = _tab(r, [[1, 9], [2, 21], [3, 10], [4, 2], [5, 7], [7, 32], [11, 14]])
			9:
				r = d10() - (1 if damaged else 0) + (1 if _has_k(people, "pilot_y") or _has_k(people, "pilot_b") else 0) \
					+ (2 if _has_k(people, "captain") else 0)
				log_msg("   Vicino a un buco nero (%d)." % r)
				step = _tab(r, [[3, 11], [6, 20], [7, 2], [8, 7], [9, 32], [13, 14]])
			10:
				r = d10()
				log_msg("   Attraverso una nube cosmica (%d)." % r)
				step = _tab(r, [[2, 15], [4, 8], [6, 2], [8, 32], [10, 14]])
			11:
				log_msg("   %s scompare nel nulla. Nessuno tornerà." % bn)
				people = []
				break
			12:
				log_msg("   %s raggiunge Snudl-1 dopo %d anni!" % [bn, years])
				fate = "home"
				break
			13:
				r = d10()
				log_msg("   Atterraggio su uno strano planetoide (%d)." % r)
				step = _tab(r, [[3, 23], [5, 15], [7, 4], [9, 22], [10, 6]])
			14:
				yrs = 4
				set_low = true
				r = d10() - (1 if lost else 0)
				log_msg("   Quattro anni nello spazio: le scorte scarseggiano (%d)." % r)
				step = _tab(r, [[2, 9], [3, 8], [4, 34], [5, 3], [6, 16], [10, 12]])
			15:
				var nd := 3 if _has_k(people, "doc") else 4
				var md := 1 if _has_k(people, "medic") else 0
				log_msg("   Una strana malattia colpisce l'equipaggio (%d dadi per uccidere%s)." % [nd, ", -1 con l'Infermiere" if md > 0 else ""])
				for id in people.duplicate():
					if crew[id]["k"] == "robot":
						continue
					var t := total(roll(nd)) - md
					if t >= int(cdef(id)["con"]):
						people.erase(id)
						log_msg("   %s muore (%d)." % [cname(id), t])
				r = d10()
				step = _tab(r, [[1, 2], [3, 7], [6, 32], [10, 14]])
			16:
				var c3 := await pick(CREW_SEAT, "alt16", "%s: un relitto alieno alla deriva!" % bn, ["Passare oltre", "Abbordarlo"], x)
				step = 30 if c3 == 0 else 25
			17:
				r = d10() + (1 if _has_k(people, "eng_officer") else 0) + (2 if _has_k(people, "engineer") else 0)
				log_msg("   Atterraggio per le riparazioni (%d)." % r)
				if r <= 4:
					step = 18
				elif r <= 6:
					yrs = 2
					damaged = false
					log_msg("   Due anni di lavoro: la scialuppa è riparata.")
					step = 30
				else:
					yrs = 1
					damaged = false
					log_msg("   Un anno di lavoro: la scialuppa è riparata.")
					step = 6
			18:
				r = d10()
				if r <= 5:
					log_msg("   Irreparabile: l'equipaggio resta naufrago su un pianeta abitabile (%d). Metà dei punti." % r)
					fate = "marooned"
				else:
					log_msg("   Irreparabile: l'equipaggio naufraga e perisce (%d)." % r)
					people = []
				break
			19:
				yrs = 1
				r = d10()
				log_msg("   Un anno di viaggio verso l'ultimo pianeta visitato (%d)." % r)
				step = _tab(r, [[3, 2], [5, 7], [10, 3]])
			20:
				damaged = true
				r = d10()
				log_msg("   La scialuppa è danneggiata (%d)." % r)
				step = _tab(r, [[6, 17], [7, 2], [8, 7], [9, 32], [10, 14]])
			21:
				r = d10()
				log_msg("   Tempesta ionica (%d)." % r)
				step = _tab(r, [[2, 20], [4, 8], [6, 7], [8, 32], [10, 14]])
			23:
				r = d10() + (2 if _has_k(people, "first_officer") else 0)
				log_msg("   Il planetoide è fatto di materia oscura quantizzata negativamente (%d)." % r)
				if r <= 8:
					log_msg("   Esplosione! La scialuppa è scagliata nello spazio.")
					step = 20
				else:
					step = 22
			24:
				r = d10() - (1 if attacked else 0) + (1 if _has_k(people, "first_officer") else 0)
				log_msg("   Si tenta di comunicare con gli alieni (%d)." % r)
				if r <= 2:
					step = 29
				elif r <= 6:
					log_msg("   Gli alieni respingono l'equipaggio e lo cacciano dal pianeta.")
					step = 30
				else:
					log_msg("   Gli alieni sono amichevoli: riparazioni e provviste!")
					damaged = false
					step = 6
			25:
				r = d10() + (1 if _has_k(people, "sparks") else 0)
				log_msg("   Il relitto ha difese automatiche (%d)." % r)
				if r <= 3:
					log_msg("   Raggi warp tetra-osmici!")
					step = 11
				elif r <= 6:
					log_msg("   Missili a ricerca!")
					step = 20
				else:
					step = 26
			26:
				var c4 := await pick(CREW_SEAT, "alt26", "%s: i computer del relitto sono stranamente alieni." % bn,
					["Andarsene", "Provare a usarli"], x)
				step = 30 if c4 == 0 else 28
			27:
				var c5 := await pick(CREW_SEAT, "alt27", "%s: un antico portale temporale!" % bn, ["Volare via", "Attivare il portale"], x)
				step = 7 if c5 == 0 else 31
			28:
				r = d10() + (1 if _has_k(people, "technician") else 0) + (2 if _has_k(people, "first_officer") else 0)
				log_msg("   I computer del relitto funzionano ancora (%d)." % r)
				if r <= 3:
					log_msg("   I motori del relitto esplodono: nessun superstite.")
					people = []
					break
				log_msg("   L'equipaggio pilota il relitto fino a Snudl-1.")
				step = 12
			29:
				r = d10()
				log_msg("   Gli alieni sono malvagie capre spaziali di antimateria (%d)!" % r)
				if r <= 5:
					step = 20
				else:
					log_msg("   La scialuppa è distrutta.")
					people = []
					break
			30:
				yrs = 1
				r = d10()
				log_msg("   Un anno nello spazio (%d)." % r)
				step = _tab(r, [[3, 2], [5, 7], [7, 13], [9, 34], [10, 3]])
			31:
				r = d10() + (1 if _has_k(people, "first_officer") else 0)
				log_msg("   Il portale temporale si accende (%d)." % r)
				if r <= 3:
					log_msg("   L'equipaggio resta intrappolato nel tempo.")
					people = []
					break
				elif r <= 6:
					log_msg("   I circuiti del portale vanno in corto.")
					step = 32
				else:
					step = 12
			32:
				yrs = 3
				r = d10() - (1 if lost else 0)
				log_msg("   Tre anni nello spazio (%d)." % r)
				step = _tab(r, [[2, 8], [3, 13], [5, 34], [7, 3], [10, 12]])
			33:
				yrs = 2
				r = d10()
				log_msg("   Due anni dritti verso Snudl-1 (%d)." % r)
				step = _tab(r, [[6, 7], [10, 32]])
			34:
				r = d10()
				log_msg("   Atterraggio su un pianeta desolato (%d)." % r)
				step = _tab(r, [[5, 4], [7, 22], [8, 27], [10, 6]])
			35:
				r = d10()
				log_msg("   L'equipaggio evita il contatto (%d)." % r)
				step = _tab(r, [[2, 2], [4, 7], [7, 32], [10, 14]])
		if yrs > 0:
			years += yrs
			if low:
				low_years += yrs
				if low_years > 10:
					log_msg("   Le scorte sono finite: l'equipaggio muore di fame.")
					people = []
					break
		if set_low and not low:
			low = true
			low_years = 0
			log_msg("   Le scorte basteranno ancora dieci anni.")
		if _no_humans(people):
			people = []
			break
	if guard >= 120:
		log_msg("   Il viaggio non finisce mai… nessuno torna a casa.")
		people = []
	if fate == "lost" or people.is_empty():
		people = []
		fate = "lost"
	bt["survivors"] = people
	bt["fate"] = fate


func _no_humans(people: Array) -> bool:
	for id in people:
		if not (crew[id]["k"] in ["robot", "mascot"]):
			return false
	return true


var result := {}

func _finish() -> void:
	if not _pending_end.is_empty():
		var kind: String = _pending_end["kind"]
		phase = "epilogue"
		changed.emit()
		var home := 0.0
		for bt in boats:
			if opts.get("alt_epilogue", false):
				await _epilogue_alt(bt)
			else:
				await _epilogue_boat(bt)
			var mult := 0.5 if bt["fate"] == "marooned" else 1.0
			for id in bt["survivors"]:
				if not (crew[id]["k"] in ["robot", "mascot"]):
					home += float(cdef(id)["con"]) * mult
		match kind:
			"exterminated":
				vp = [float(_pending_end["aboard"]) + home, D.VP_TAKEOVER if not boats.is_empty() else 0.0]
				winner = "crew" if vp[0] > vp[1] else ("mon" if vp[1] > vp[0] else "draw")
				end_reason = "L'equipaggio ha sterminato le Cose Verdi."
			"sd":
				vp = [home, D.VP_SELFDESTRUCT]
				winner = "crew" if vp[0] > vp[1] else ("mon" if vp[1] > vp[0] else "draw")
				end_reason = "La Znutar è esplosa: le Cose Verdi sono distrutte."
			"escape":
				vp = [home, D.VP_TAKEOVER]
				winner = "crew" if vp[0] > vp[1] else ("mon" if vp[1] > vp[0] else "draw")
				end_reason = "L'equipaggio ha abbandonato la nave alle Cose Verdi."
		log_msg("■ " + end_reason)
	var wtxt := {"crew": "Vince l'Equipaggio!", "mon": "Vincono le Cose Verdi!", "draw": "Pareggio."}
	log_msg("Punti vittoria: Equipaggio %s, Cose Verdi %s. %s" % [_fmt(vp[0]), _fmt(vp[1]), wtxt.get(winner, "")])
	phase = "fine_partita"
	result = {"winner": winner, "reason": end_reason, "vp": vp}
	changed.emit()
	game_ended.emit(result)


static func _fmt(v: float) -> String:
	if is_equal_approx(v, floor(v)):
		return str(int(v))
	return ("%.1f" % v).replace(".", ",")


## Impronta della partita (per verificare che due dispositivi online abbiano giocato la stessa).
func fingerprint() -> String:
	var parts := [str(turn_no), winner]
	for id in crew:
		parts.append("%d%s%s" % [id, crew[id]["loc"], crew[id]["state"]])
	var ms := mon.keys()
	ms.sort()
	for id in ms:
		parts.append("%d%s%s" % [id, mon[id]["l"], mon[id]["loc"]])
	return str(hash("|".join(parts))) + " t%d %s" % [turn_no, winner]

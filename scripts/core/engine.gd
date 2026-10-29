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
	gear = {}
	if outside():
		AR = AR.duplicate()
		for a in D.outside_data()["areas"]:
			AR[a["id"]] = a
		var gid := 0
		for t in D.GEAR:
			for a in D.GEAR[t]["start"]:
				for i in int(D.GEAR[t]["start"][a]):
					gear[gid] = {"t": t, "loc": a, "c": -1, "out": false}
					gid += 1
	crew = {}
	for i in D.CREW.size():
		crew[i] = {"k": D.CREW[i]["k"], "loc": "", "st": 0, "w": -1, "state": "ok", "team": 0, "slow": false, "g": -1, "boat": ""}
		if mutiny() and D.MUT_FIRST.has(D.CREW[i]["k"]):
			crew[i]["team"] = 2
	wpn = {}
	var wid := 0
	var wlist: Array = D.WEAPON_ORDER.duplicate()
	if mutiny():
		wlist.append_array(["rcontrol", "jammer"])
	for t in wlist:
		var st: Dictionary = D.WEAPONS[t]["start"]
		if mutiny() and t == "hypo":
			st = {"sick": 1, "life": 1}
		for a in st:
			for n in int(st[a]):
				wpn[wid] = {"t": t, "loc": a, "c": -1, "on": false, "out": false, "team": -1}
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


## Testi con il nome della specie giusta (Cose Arancioni o Viola al posto delle Verdi).
func sp_text(t: String) -> String:
	if species() == "green":
		return t
	var sp: Dictionary = D.SPECIES[species()]
	return t.replace("Cose Verdi", sp["name"]).replace("Cosa Verde", sp["one"]).replace("Piccoli", "Giovani").replace("Piccolo", "Giovane")


func log_msg(t: String) -> void:
	t = sp_text(t)
	log_lines.append(t)
	log_added.emit(t)


func pname(s: int) -> String:
	if s < 0 or s >= players.size():
		return "?"
	var def: String = "Equipaggio" if s == CREW_SEAT else String(D.SPECIES[species()]["name"])
	if mutiny():
		def = ["Il Capitano", "Cose Verdi", "Il Primo Ufficiale"][s]
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
	if extra_adj.is_empty() and pods_gone.is_empty():
		return AR[a]["adj"]
	var out: Array = AR[a]["adj"].duplicate()
	out.append_array(extra_adj.get(a, []))
	return out.filter(func(x): return not pods_gone.has(x))


## Aree in linea di vista (l'area stessa compresa).
func los(a: String) -> Array:
	var out: Array = [a]
	out.append_array(AR[a]["los"])
	return out


## Sezione colpita da gas o carburante: la nube si ferma solo ai portelli, quindi in un corridoio
## riempie tutti i tratti collegati da passaggi aperti.
func section(a: String) -> Array:
	if is_out(a):
		# fuori dalla nave l'esplosione investe tutta la zona di spazio e il suo scafo
		var sp := space_of(a)
		var o := []
		for x in AR:
			if space_of(x) == sp:
				o.append(x)
		return o
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
	var mg: String = mon[id].get("mega", "")
	if mg != "":
		return int(D.MEGA[mg]["con"])
	return mdef(mon[id]["l"])["con"]


func matt(id: int) -> int:
	var mg: String = mon[id].get("mega", "")
	if mg == "breeder":
		for o in mons_at(mon[id]["loc"]):
			if mon[o]["l"] in ["E", "B"]:
				return 5
		return 1
	if mg != "":
		return int(D.MEGA[mg]["att"])
	return mdef(mon[id]["l"])["att"]


func mmov(id: int) -> int:
	var mg: String = mon[id].get("mega", "")
	if mg != "":
		return int(D.MEGA[mg]["mov"])
	return int(mdef(mon[id]["l"])["mov"])


func mname(id: int) -> String:
	var mg: String = mon[id].get("mega", "")
	if mg != "":
		return String(D.MEGA[mg]["short"])
	return mdef(mon[id]["l"])["name"]


func mon_count(l := "") -> int:
	var n := 0
	for id in mon:
		if l == "" or mon[id]["l"] == l:
			n += 1
	return n


func species() -> String:
	return str(opts.get("species", "green")) if not solo() else "green"


func mdef(l: String) -> Dictionary:
	return D.SPECIES[species()]["mon"][l]


## Livelli che esistono per la specie (le Arancioni non hanno uova, le Viola non hanno frammenti).
func levels() -> Array:
	return ["A", "B", "F", "E"].filter(func(l): return int(mdef(l)["limit"]) > 0)


func mlimit(l: String) -> int:
	return int(D.MUT_LIMIT[l]) if (mutiny() and species() == "green") else int(mdef(l)["limit"])


func avail(l: String) -> int:
	return mlimit(l) - mon_count(l) - (hidden_mon(l) if not hidden.is_empty() else 0)


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
func reach(from: String, mv: int, for_crew: bool, mode := "walk", unit := -1) -> Dictionary:
	var out := {}
	var q := [[from, []]]
	var seen := {from: 0}
	if outside() and mv > 0:
		# la camera stagna si attraversa solo partendo accanto, e prende tutto il turno
		var other := lock_other(from)
		if other != "" and mode != "mover" and _lock_open(from, other, for_crew, unit):
			out[other] = [other]
	while not q.is_empty():
		var it: Array = q.pop_front()
		var cur: String = it[0]
		var path: Array = it[1]
		if path.size() >= mv:
			continue
		if cur != from and _must_stop(cur, for_crew) and not (mode != "walk" and is_space(cur)):
			continue
		for n in _nbrs(cur, mode):
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
	if for_crew and webs.has(a):
		return true
	return hot_for_crew(a) if for_crew else blocks_mon(a)


## Vicini per chi cammina, per le tute a reazione (anche lo spazio) e per i carrelli elevatori.
func _nbrs(a: String, mode: String) -> Array:
	if mode == "ooze":
		# le Cose Viola adulte passano anche attraverso le pareti, ma solo per entrare in una stanza
		var o2: Array = adj(a).duplicate()
		for w in walls_of(a):
			if AR[w]["kind"] in ["stanza", "hangar"] and not (w in D.PURPLE_NO_OOZE) and not o2.has(w):
				o2.append(w)
		return o2
	if mode == "walk" or not outside():
		return adj(a)
	if mode == "jet":
		var out: Array = adj(a).duplicate()
		for n in AR[a].get("fly", []):
			if not out.has(n):
				out.append(n)
		if is_space(a):
			return out
		var o := lock_other(a)
		if o != "" and not out.has(o):
			out.append(o)
		return out
	# carrello: solo stiva, hangar e spazio
	if a in D.MOVER_ROOMS:
		return [AR["s_" + a]["space"]]
	if is_space(a):
		var out2: Array = adj(a).duplicate()
		for r in D.MOVER_ROOMS:
			if AR["s_" + r]["space"] == a:
				out2.append(r)
		return out2
	return []


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
			var nb: Array = adj(x)
			if outside():
				nb = nb.duplicate()
				var o := lock_other(x)
				if o != "":
					nb.append(o)
			for n in nb:
				if not d.has(n):
					d[n] = d[x] + 1
					q.append(n)
		_dist_cache[a] = d
	return _dist_cache[a].get(b, 99)


# ---- equipaggio: movimento e attacco

func crew_can_act(id: int) -> bool:
	if mutiny() and team_of(id) != cur_team:
		return false
	if crew[id].get("boat", "") != "" and bout.has(crew[id]["boat"]) and bout[crew[id]["boat"]]["gone"]:
		return false
	return on_board(id) and awake(id) and not busy.has(id)


func crew_moves(id: int) -> Dictionary:
	if not crew_can_act(id) or moved.has(id):
		return {}
	if crew[id].get("boat", "") != "":
		return {}   # chi è su una scialuppa si muove con lei
	var mv := c_mov(id)
	if crew[id].get("slow", false):
		mv = mv / 2
	if mv <= 0:
		return {}
	var r := reach(crew[id]["loc"], mv, true, _mode(id), id)
	if discovery:
		var out := {}
		for a in r:
			if not mons_at(a).is_empty() and (species() != "orange" or a == "mess"):
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
	var bt: String = crew[id].get("boat", "")
	if is_space(loc):
		# dallo spazio si colpisce lo scafo della propria zona: a mani nude solo con tuta o carrello,
		# dalle scialuppe solo con le armi (e non dalla Lancia)
		if bt != "" and (not usew or bt == "cockboat"):
			return []
		if not usew and not (gear_of(id) in ["jet", "mover"]):
			return []
		if usew:
			var w0: int = crew[id]["w"]
			if w0 < 0 or not works_outside(wtype(w0)) or D.WEAPONS[wtype(w0)]["range"] == "none":
				return []
		for x in AR:
			if AR[x]["kind"] == "scafo" and space_of(x) == space_of(loc):
				out.append(x)
		return out
	if not usew:
		out = [loc]
	else:
		var w: int = crew[id]["w"]
		if w < 0 or discovery:
			return []
		var t := wtype(w)
		if outside() and is_out(loc) and not works_outside(t):
			return []
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
	if usew and outside() and not works_outside(wtype(crew[id]["w"])):
		out = out.filter(func(a): return not is_out(a))
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
	if mutiny() and not enemies_at(a, id).is_empty():
		if not usew or D.WEAPONS[wtype(crew[id]["w"])]["kind"] in ["single", "blast"]:
			return true
	if usew and D.WEAPONS[wtype(crew[id]["w"])]["kind"] == "blast":
		for x in section(a):
			if not seen_mons_at(x).is_empty():
				return true
		return false
	return not seen_mons_at(a).is_empty()


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
	return mon.has(id) and mmov(id) > 0 and not mon[id]["st"] and not moved.has(id)


func mon_moves(ids: Array) -> Dictionary:
	if ids.is_empty():
		return {}
	var mv := 9
	var loc: String = mon[ids[0]]["loc"]
	var runner := -1
	for id in ids:
		if is_mega(id, "runner") and mon_mobile(id) and mon[id]["loc"] == loc:
			runner = id
	if runner >= 0 and ids.size() > 1:
		# il Corridore porta con sé uova (mezzo punto) e piccoli (un punto), al massimo 2 punti
		var cost := 0.0
		for id in ids:
			if id == runner:
				continue
			if not mon.has(id) or mon[id]["loc"] != loc or moved.has(id) or mon[id]["st"] or not (mon[id]["l"] in ["E", "B"]):
				return {}
			cost += 0.5 if mon[id]["l"] == "E" else 1.0
		if cost > 2.0:
			return {}
		return reach(loc, mmov(runner) - int(ceil(cost)), false, "walk", runner)
	var all_a := true
	for id in ids:
		if not mon_mobile(id) or mon[id]["loc"] != loc:
			return {}
		mv = mini(mv, mmov(id))
		if mon[id]["l"] != "A":
			all_a = false
	var out := reach(loc, mv, false, "ooze" if (species() == "purple" and all_a) else "walk", ids[0])
	if ids.size() == 1 and is_mega(ids[0], "slimer"):
		for w in walls_of(loc):
			if not out.has(w):
				out[w] = [w]
	return out


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
		if mutiny():
			for t in [0, 2]:
				cur_team = t
				if team_crew(t).is_empty():
					continue
				await _crew_turn()
				if game_over or abort:
					break
			cur_team = 0
		else:
			await _crew_turn()
	if not abort:
		_finish()


var _bridge_turn := 0

func _setup_crew() -> void:
	phase = "crew_setup"
	for t in ([0, 2] if mutiny() else [0]):
		cur_team = t
		var options := {}
		for id in crew:
			if mutiny():
				var tab: Dictionary = D.MUT_CAPTAIN if t == 0 else D.MUT_FIRST
				if tab.has(crew[id]["k"]):
					options[id] = tab[crew[id]["k"]]
			else:
				options[id] = cdef(id)["start"]
				# Cose Arancioni: chi può stare su tutti e due i Ponti si divide fra i due
				if species() == "orange" and "bridge1" in options[id] and "bridge2" in options[id]:
					options[id] = ["bridge1" if (_bridge_turn % 2) == 0 else "bridge2"]
					_bridge_turn += 1
		var r = await decide(t, {"type": "crew_setup", "options": options,
			"title": "Disponi la tua squadra nelle aree di partenza" if mutiny() else "Disponi l'equipaggio nelle aree di partenza"})
		for id in options:
			var a = r.get(id, r.get(str(id), "")) if r is Dictionary else ""
			if not (a in options[id]):
				a = options[id][0]
			crew[id]["loc"] = a
		changed.emit()
	cur_team = 0
	log_msg("L'equipaggio prende posto a bordo.")
	changed.emit()


func _setup_monsters() -> void:
	phase = "mon_setup"
	var p := d6()
	var pop: Array = D.MUT_POP[p - 1] if (mutiny() and species() == "green") else D.POPULATION[p - 1]
	if species() == "purple":
		pop = D.PURPLE_POP[p - 1]
	var left := {"E": pop[0], "B": pop[1], "A": pop[2]}
	if species() == "orange":
		left = {"E": 0, "B": 5, "A": 4}
	if opts.get("extra_adult", false):
		left["A"] += 1
	dice = [p]
	dice_info = "Popolazione"
	if species() == "orange":
		log_msg("Le Cose Arancioni escono dalla Mensa: 6 Frammenti, poi 5 Giovani e 4 Adulti.")
	else:
		log_msg("Tiro per la popolazione: %d → %d Uova, %d Piccoli, %d Adulti." % [p, left["E"], left["B"], left["A"]])
		_fx("dice", {"dice": [p], "info": "Popolazione iniziale", "total": p})
	var p2 := d6()
	var first := ""
	if p2 <= 5:
		first = D.FIRST_AREA[p2 - 1]
	if species() == "orange":
		first = "mess"
		for i in 6:
			_add_mon("F", "mess")
		known["zgwortz"] = "frag"
		log_msg("Lo Zgwortz ha fatto esplodere la prima Cosa Arancione: il suo effetto è noto (1 dado di Frammenti).")
	if species() != "orange" and (first == "" or not crew_at(first).is_empty()):
		var free := D.FIRST_AREA.filter(func(a): return crew_at(a).is_empty())
		if free.is_empty():
			free = D.area_list().filter(func(a): return crew_at(a).is_empty())
		first = await choose_loc(MON_SEAT, "first", "Scegli dove compare la prima Cosa Verde", free)
	log_msg("Tiro per il primo mostro: %d → %s." % [p2, area_name(first)])
	_fx("dice", {"dice": [p2], "info": "Primo mostro: " + area_name(first), "total": p2})
	var placed := 0
	while left["A"] + left["B"] + left["E"] > 0 and not abort:
		var allowed: Array
		if placed == 0 and species() != "orange":
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
		var nb: Array = adj(a).duplicate()
		var lo := lock_other(a)
		if lo != "":
			nb.append(lo)
		for n in nb:
			if not occ.has(n) and crew_at(n).is_empty() and not out.has(n) and not is_space(n):
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
	if species() == "orange" and not crew_at("mess").is_empty():
		log_msg("C'è già l'equipaggio in Mensa: le Cose Arancioni sono scoperte subito.")
	elif mutiny():
		await _discovery_mut()
	else:
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
	if outside():
		await _remote_lock()
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
	if megadults():
		_mega_sync()
		for id in mon.keys():
			if not mon.has(id) or mon[id]["st"]:
				continue
			if is_mega(id, "brainiac"):
				_brainiac_grab(id)
				_brainiac_attack(id)
			elif is_mega(id, "flamer"):
				_flamer_attack(id)
		_check_end()
		if game_over:
			return
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
	if not game_over and (megadults() or opts.get("kitchen", false) or opts.get("eat_weapons", false)):
		await _revenge_after_attack()
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
		if l == "A" and species() == "orange":
			target = "F"
		if avail(target) > 0 or (l == "A" and species() == "orange"):
			out.append(l)
	return out


func _apply_grow(l: String) -> void:
	var tried := false
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
				if species() == "orange":
					_orange_burst(id, "")
					n += 1
					continue
				if megadults() and is_mega(id):
					continue
				if megadults() and not tried:
					tried = true
					_try_mega(id)
					continue
				if avail("E") > 0:
					_add_mon("E", mon[id]["loc"])
					n += 1
	if megadults():
		var fresh := []
		for id in ids:
			if l == "A" and is_mega(id, "breeder"):
				_breeder_grow(id, fresh)
		if l != "A":
			for id in mon.keys():
				if is_mega(id, "breeder") and not mon[id]["st"] and avail("E") > 0:
					_add_mon("E", mon[id]["loc"])
					log_msg("   La Covatrice depone comunque un Uovo.")
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
	if ids.size() == 1 and is_mega(ids[0], "slimer") and to in walls_of(from):
		_make_hole(from, to)
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
			ch = _draw_learn()
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
		var con: int = c_con(cid) + c_shell(cid)
		if hit_crew(cid, tot):
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
			parts.append("%d %s" % [cnt[l], mdef(l)["plural"] if cnt[l] > 1 else mdef(l)["name"]])
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
	if species() == "orange":
		pref = [["B", "A"], ["A", "A"], ["F", "B"]]
	elif species() == "purple":
		pref = [["B", "A"], ["A", "A"]]
	for p in pref:
		for mid in ms:
			if mon[mid]["l"] == p[0] and avail(p[1]) > 0 and (not is_mega(mid) or is_mega(mid, "breeder")):
				best = mid
				break
		if best >= 0:
			break
	if best < 0:
		return
	if megadults() and mon[best]["l"] == "A" and not is_mega(best):
		log_msg("L'Adulto che ha mangiato tenta la metamorfosi.")
		_try_mega(best)
		return
	if species() == "orange" and mon[best]["l"] == "A":
		_orange_burst(best, "L'Adulto che ha mangiato")
		return
	if species() == "purple" and mon[best]["l"] == "A":
		var a3: String = mon[best]["loc"]
		var nb := rng.randi_range(1, 3) + 1
		mon.erase(best)
		var made := 0
		for i in nb:
			if avail("B") > 0:
				_add_mon("B", a3)
				made += 1
		log_msg("L'Adulto che ha mangiato si divide in %d Giovani." % made)
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


## Cose Arancioni: l'Adulto esplode in 1-6 Frammenti.
func _orange_burst(id: int, who: String) -> void:
	var a: String = mon[id]["loc"]
	mon.erase(id)
	var n := d6()
	var made := 0
	for i in n:
		if avail("F") > 0:
			_add_mon("F", a)
			made += 1
	_fx("frag", {"area": a, "n": made})
	log_msg("%s esplode in %d Frammenti." % [who if who != "" else "Un Adulto in " + area_name(a), made])


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
	gear_done = {}
	if outside():
		_boats_back()
	if mutiny():
		log_msg("— Turno %d: %s —" % [turn_no, "la squadra del Capitano" if cur_team == 0 else "la squadra del Primo Ufficiale"])
	else:
		log_msg("— Turno %d: l'equipaggio —" % turn_no)
	# 1. prendere le armi
	phase = "grab"
	var guard := 0
	while not abort and guard < 200:
		guard += 1
		var acts := grab_actions()
		if acts.is_empty():
			break
		var r = await decide(cur_team, {"type": "grab", "actions": acts, "title": "Prendi, lascia o scambia le armi"})
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
				wpn[w]["team"] = cur_team
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
		if mutiny() and team_of(cid) != cur_team and crew[cid]["k"] != "robot":
			continue
		if crew[cid]["st"] > 0 and crew[cid]["st"] < turn_no:
			crew[cid]["st"] = 0
		crew[cid]["slow"] = false
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
		if mutiny() and team_of(cid) != cur_team:
			continue
		var a: String = crew[cid]["loc"]
		var k: String = crew[cid]["k"]
		var w: int = crew[cid]["w"]
		var contested := mutiny() and not enemies_at(a, cid).is_empty()
		if k != "mascot" and not contested:
			var seen := {}
			for fw in weapons_at(a):
				var t := wtype(fw)
				if seen.has(t):
					continue
				if D.WEAPONS[t]["kind"] == "device" and k == "robot":
					continue
				if gear_of(cid) == "mover" and t != "fuel":
					continue
				if gear_done.has(cid) and gear_of(cid) != "":
					continue
				seen[t] = true
				var lab := "%s prende %s" % [cdef(cid)["short"], wname(t)]
				if w >= 0:
					lab = "%s lascia %s e prende %s" % [cdef(cid)["short"], wname(wtype(w)), wname(t)]
				if wpn[fw]["on"]:
					lab = "%s smonta il Recinto acceso" % cdef(cid)["short"]
				out.append({"a": "take", "c": cid, "w": fw, "label": lab})
		if outside():
			out.append_array(gear_actions(cid))
		if w >= 0:
			out.append({"a": "drop", "c": cid, "label": "%s lascia %s" % [cdef(cid)["short"], wname(wtype(w))]})
			for o in crew_at(a):
				if o == cid or o < 0 or not awake(o) or crew[o]["k"] == "mascot":
					continue
				if mutiny() and team_of(o) != cur_team:
					continue
				if crew[o]["k"] == "robot" and D.WEAPONS[wtype(w)]["kind"] == "device":
					continue
				if crew[o]["w"] >= 0 and o < cid:
					continue   # lo scambio fra due armati compare una volta sola
				var lab2 := "%s dà %s a %s" % [cdef(cid)["short"], wname(wtype(w)), cdef(o)["short"]]
				if crew[o]["w"] >= 0:
					lab2 = "%s e %s si scambiano le armi" % [cdef(cid)["short"], cdef(o)["short"]]
				out.append({"a": "swap", "c": cid, "o": o, "label": lab2})
	for fw in wpn:
		var x: Dictionary = wpn[fw]
		if x["t"] == "fence" and x["on"] and not x["out"] and x["c"] == -1 and (not mutiny() or int(x.get("team", -1)) == cur_team):
			out.append({"a": "off", "w": fw, "label": "Spegni a distanza il Recinto in %s" % area_name(x["loc"])})
	return out


func _apply_grab(act: Dictionary) -> void:
	match act["a"]:
		"suit", "unsuit":
			_apply_gear(act)
			return
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
		var r = await decide(cur_team, req)
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
	if webs.has(a) and w >= 0 and wtype(w) == "torch" and not hot_for_crew(a):
		out.append({"act": "unweb", "c": cid, "label": "Brucia la ragnatela con la Saldatrice"})
	var can_sd: bool = crew[cid]["k"] in D.SD_CREW and a in D.BRIDGES
	if mutiny():
		can_sd = D.MUT_SD.has(a) and crew[cid]["k"] in D.MUT_SD[a]
		# il Dottore e l'Infermiere con la Siringa risvegliano un compagno stordito
		if crew[cid]["k"] in ["doc", "medic"] and w >= 0 and wtype(w) == "hypo" and not attacked.has(cid):
			for o in crew_at(a):
				if o != cid and team_of(o) == cur_team and not awake(o) and crew[o]["k"] != "robot":
					out.append({"act": "heal", "c": cid, "t": o, "label": "Siringa: risveglia %s" % cdef(o)["short"]})
	if can_sd and sd_left < 0 and not "sd" in busy.values():
		out.append({"act": "sd", "c": cid, "label": "Avvia l'autodistruzione"})
	if outside():
		var bt: String = crew[cid].get("boat", "")
		if bt != "":
			for n in adj(a):
				if is_space(n):
					out.append({"act": "bmove", "b": bt, "c": cid, "to": n, "label": "%s vola: %s" % [String(D.BOATS[bt]["name"]).capitalize(), area_name(n)]})
			if AR["s_" + bt]["space"] == a:
				out.append({"act": "dock", "b": bt, "c": cid, "label": "%s rientra nel suo hangar" % String(D.BOATS[bt]["name"]).capitalize()})
			if bt in ["scout", "cockboat"]:
				out.append({"act": "blast", "b": bt, "c": cid, "label": "Getto del razzo sullo scafo (%s)" % area_name(a)})
			out.append({"act": "leave", "b": bt, "c": cid, "label": "Rotta per Snudl-1 con %s" % D.BOATS[bt]["name"]})
			return out
		if D.BOATS.has(a) and not launched.has(a) and not bout.has(a) and gear_of(cid) == "":
			out.append({"act": "launch", "b": a, "c": cid, "label": "Decolla con %s" % D.BOATS[a]["name"]})
		return out
	if D.BOATS.has(a) and not launched.has(a):
		out.append({"act": "escape", "b": a, "c": cid, "label": "Fuggi con %s" % D.BOATS[a]["name"]})
	return out


func _apply_cmove(r: Dictionary) -> void:
	var act := str(r.get("act", ""))
	if act == "escape":
		_escape(str(r.get("b", "")), r.get("ids", []))
		return
	if act in ["launch", "bmove", "dock", "blast", "leave"]:
		_boat_act(act, r)
		return
	var cid := int(r.get("c", -1))
	if not crew.has(cid):
		return
	if act == "unweb":
		for s in special_actions(cid):
			if s["act"] == "unweb":
				webs.erase(crew[cid]["loc"])
				moved[cid] = true
				log_msg("%s brucia la ragnatela in %s." % [cname(cid), area_name(crew[cid]["loc"])])
				changed.emit()
		return
	if act == "heal":
		var t := int(r.get("t", -1))
		for s in special_actions(cid):
			if s["act"] == "heal" and int(s["t"]) == t:
				crew[t]["st"] = 0
				moved[cid] = true
				attacked[cid] = true
				log_msg("%s usa la Siringa: %s si riprende." % [cname(cid), cname(t)])
				changed.emit()
				return
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
		if on_board(id) and awake(id) and crew[id]["loc"] == b and not ids.has(id) and (not mutiny() or team_of(id) == cur_team):
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
	boats.append({"b": b, "crew": ids, "survivors": [], "fate": "", "team": cur_team})
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
		var r = await decide(cur_team, {"type": "cattack", "areas": areas, "discovery": discovery,
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
	# 0. morte istantanea (reazione allergica allo Zgwortz)
	for id in ids:
		if mon.has(id) and eff[id].get("dies", false):
			var nm0 := mname(id)
			_fx("kill_mon", {"area": mon[id]["loc"], "l": mon[id]["l"]})
			mon.erase(id)
			killed += 1
			parts.append("%s muore" % nm0)
	# 1. Cresce
	for id in ids:
		if mon.has(id) and eff[id]["grow"]:
			var l: String = mon[id]["l"]
			if l in ["F", "E"] and avail("B") > 0:
				mon[id]["l"] = "B"
			elif l == "B" and avail("A") > 0:
				mon[id]["l"] = "A"
			elif l == "A" and species() == "orange":
				_orange_burst(id, "")
			elif l == "A" and megadults():
				if not is_mega(id):
					_try_mega(id)
			elif l == "A" and opts.get("grow_eggs", false) and avail("E") > 0:
				_add_mon("E", mon[id]["loc"])
			parts.append("%s cresce" % mdef(l)["name"])
	# 2. Rimpicciolisce
	for id in ids:
		if mon.has(id) and eff[id]["shrink"]:
			var l: String = mon[id]["l"]
			var to: String = {"A": "B", "B": "E", "F": "E", "E": ""}[l]
			if species() == "orange":
				to = {"A": "B", "B": "F", "F": "", "E": ""}[l]
			if to == "" or avail(to) <= 0:
				mon.erase(id)
				killed += 1
				parts.append("%s svanisce" % mdef(l)["name"])
			else:
				mon[id]["l"] = to
				parts.append("%s rimpicciolisce" % mdef(l)["name"])
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
		if mon.has(id) and eff[id]["frag"] and species() == "purple":
			# le Cose Viola non fanno frammenti: l'Adulto si divide in 1-3 Giovani, il Giovane in 0-2
			for s in eff[id]["fsrc"]:
				used[s] = true
			var l2: String = mon[id]["l"]
			if l2 == "E":
				continue
			var a2: String = mon[id]["loc"]
			var nb := rng.randi_range(1, 3) - (1 if l2 == "B" else 0)
			mon.erase(id)
			killed += 1
			var made2 := 0
			for i in nb:
				if avail("B") > 0:
					_add_mon("B", a2)
					made2 += 1
			_fx("frag", {"area": a2, "n": made2})
			parts.append("%s si divide in %d Giovani" % [mdef(l2)["name"], made2])
			continue
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
			if outside() and is_out(x) and not works_outside(wtype(crew[cid]["w"])):
				continue
		if kind in ["hand", "single"]:
			if tgt >= D.CREW_T:
				var tc := tgt - D.CREW_T
				if not mutiny() or not crew.has(tc) or not (tc in enemies_at(x, cid)):
					continue
			elif not mon.has(tgt) or mon[tgt]["loc"] != x or not mon_visible(tgt):
				continue
		elif kind == "device":
			continue
		seen[cid] = true
		entries.append({"c": cid, "usew": usew, "tgt": tgt, "kind": kind, "t": wtype(crew[cid]["w"]) if usew else ""})
	if entries.is_empty():
		return
	last_area = x
	var vs_crew := entries.filter(func(e): return e["kind"] in ["hand", "single"] and int(e["tgt"]) >= D.CREW_T)
	if not vs_crew.is_empty():
		entries = entries.filter(func(e): return not vs_crew.has(e))
		_attack_crew(x, vs_crew)
		for e in vs_crew:
			attacked[e["c"]] = true
		if entries.is_empty():
			changed.emit()
			return
	# gettoni per le armi non ancora provate
	var untried := []
	for e in entries:
		if e["usew"] and e["t"] == "zgwortz" and opts.get("kitchen", false):
			continue
		if e["usew"] and not known.has(e["t"]) and not untried.has(e["t"]):
			untried.append(e["t"])
	var chit_for := {}
	var shared := ""
	var learn_t := ""
	if untried.size() == 1:
		learn_t = untried[0]
		chit_for[learn_t] = _draw_learn()
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
	var zg_rolls := {}
	if opts.get("kitchen", false):
		for e in entries:
			if e["usew"] and e["t"] == "zgwortz":
				zg_rolls[e["c"]] = zgwortz_roll()
				log_msg("   Lo Zgwortz di %s: %s." % [cdef(e["c"])["short"], _zg_name(zg_rolls[e["c"]])])
	# effetti sui mostri
	var eff := {}
	var gas_done := {}
	var gas_areas := {}
	var fuel_areas := {}
	var desc := []
	var thrown := []
	for e in entries:
		var cid: int = e["c"]
		if not e["usew"]:
			var tg: int = e["tgt"]
			if gear_of(cid) == "mover" and is_space(crew[cid]["loc"]):
				desc.append("%s afferra %s con le pinze e lo scaglia nello spazio" % [cdef(cid)["short"], mname(tg)])
				thrown.append(tg)
				continue
			eff[tg] = _eff_add(eff.get(tg, {}), "", "hand")
			eff[tg]["kill"] += c_att(cid)
			eff[tg]["ksrc"].append("hand")
			desc.append("%s a mani nude su %s" % [cdef(cid)["short"], mname(tg)])
			continue
		var t: String = e["t"]
		var ch: String = chit_for.get(t, "none")
		if zg_rolls.has(cid):
			ch = zg_rolls[cid]
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
			if ch == "dies":
				eff[tg] = _eff_add(eff.get(tg, {}), "", t)
				eff[tg]["dies"] = true
				continue
			eff[tg] = _eff_add(eff.get(tg, {}), ch, t)
	log_msg("Attacco in %s: %s." % [area_name(x), "; ".join(desc)])
	_fx("attack", {"area": x, "crew": entries.map(func(e): return e["c"])})
	for tg in thrown:
		if mon.has(tg):
			_fx("kill_mon", {"area": mon[tg]["loc"], "l": mon[tg]["l"]})
			mon.erase(tg)
			eff.erase(tg)
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
	for s0 in fuel_areas:
		webs.erase(s0)
	if not fuel_areas.is_empty():
		_pod_check(fuel_areas.keys())
	# effetti di gas e carburante sull'equipaggio
	for s in gas_areas:
		for cid in crew_at(s):
			if gas_proof(cid):
				continue
			var tot := _roll_show(5, "Gas contro %s" % cname(cid))
			if tot >= c_con(cid):
				crew[cid]["st"] = turn_no
				log_msg("   Il gas stordisce anche %s (%d)." % [cname(cid), tot])
	for s in fuel_areas:
		for cid in crew_at(s):
			if crew[cid].get("boat", "") != "":
				continue   # al riparo dentro la scialuppa
			var tot := _roll_show(fuel_areas[s], "Esplosione contro %s" % cname(cid))
			if hit_crew(cid, tot):
				log_msg("   L'esplosione uccide %s (%d)!" % [cname(cid), tot])
				_crew_dies(cid)
				_fx("kill_crew", {"c": cid, "area": s})
			else:
				log_msg("   %s sopravvive all'esplosione (%d)." % [cname(cid), tot])
	changed.emit()


# ================================================================ Revenge of the Awful Green Things
## Regole facoltative di Tom Rhoads e James Sterrett: i Megadulti, la Cucina e la Mensa, le varianti delle
## armi (Frammenti ritirati, armi mangiate, Serbatoi che esplodono) e i mostri nascosti.

var webs := {}            # aree con una ragnatela del Tessitore
var extra_adj := {}       # buchi nelle pareti fatti dal Melmoso: area -> [aree]
var pods_gone := {}       # Serbatoi esplosi
var _walls := []


func hidden_mode() -> bool:
	return opts.get("hidden_mons", false)


## Mostri nascosti: l'equipaggio vede le Cose Verdi nelle aree in linea di vista di qualcuno sveglio;
## le Uova solo nella propria area o lungo i corridoi aperti.
func mon_visible(m: int) -> bool:
	if not hidden_mode() or not mon.has(m):
		return true
	var a: String = mon[m]["loc"]
	var key := ""
	for c in crew:
		if crew[c]["state"] == "ok":
			key += "%s%d," % [crew[c]["loc"], crew[c]["st"]]
	if key != _vis_key:
		_vis_key = key
		_vis_cache = {}
	if not _vis_cache.has(a):
		var v := false
		var ve := false
		for c in board_crew():
			if not awake(c):
				continue
			var ca: String = crew[c]["loc"]
			if ca == a or a in section(ca):
				v = true
				ve = true
				break
			if a in los(ca):
				v = true
		_vis_cache[a] = [v, ve]
	return _vis_cache[a][1] if mon[m]["l"] == "E" else _vis_cache[a][0]


var _vis_cache := {}
var _vis_key := ""


func seen_mons_at(a: String) -> Array:
	return mons_at(a).filter(func(m): return mon_visible(m))


func megadults() -> bool:
	return opts.get("megadults", false) and species() == "green"


func is_mega(id: int, k := "") -> bool:
	if not mon.has(id):
		return false
	var mg: String = mon[id].get("mega", "")
	return mg != "" and (k == "" or mg == k)


## Pareti fra due aree senza portello (dove il Melmoso può aprire un buco).
func walls_of(a: String) -> Array:
	if _walls.is_empty():
		var f := FileAccess.open("res://assets/data/muri.json", FileAccess.READ)
		_walls = JSON.parse_string(f.get_as_text())
	var out := []
	for p in _walls:
		if p[0] == a and not adj(a).has(p[1]):
			out.append(p[1])
		elif p[1] == a and not adj(a).has(p[0]):
			out.append(p[0])
	return out


## Dove disegnare il buco fra due aree: a metà fra i loro due vertici più vicini.
func hole_point(a: String, b: String) -> Vector2:
	var best := Vector2.ZERO
	var bd := 1e18
	for p in AR[a]["poly"]:
		for q in AR[b]["poly"]:
			var d := Vector2(p[0], p[1]).distance_squared_to(Vector2(q[0], q[1]))
			if d < bd:
				bd = d
				best = (Vector2(p[0], p[1]) + Vector2(q[0], q[1])) * 0.5
	return best


func _make_hole(a: String, b: String) -> void:
	for p in [[a, b], [b, a]]:
		if not extra_adj.has(p[0]):
			extra_adj[p[0]] = []
		if not (extra_adj[p[0]] as Array).has(p[1]):
			extra_adj[p[0]].append(p[1])
	_dist_cache = {}
	log_msg("Il Melmoso scioglie la parete fra %s e %s: ora c'è un buco." % [area_name(a), area_name(b)])
	_fx("frag", {"area": b, "n": 0})


## Megadulti già in gioco: i loro gettoni non sono nella tazza.
func _mega_cup() -> Array:
	var alive := {}
	for id in mon:
		if mon[id].get("mega", "") != "":
			alive[mon[id]["mega"]] = true
	return D.MEGA_CHITS.filter(func(k): return not alive.has(k))


## La crescita è certa quando l'equipaggio ha scoperto un'arma ad area che uccide o rimpicciolisce.
func _mega_sure() -> bool:
	for t in known:
		if D.WEAPONS[t]["kind"] in ["area", "blast"] and (str(known[t]).begins_with("kill") or known[t] == "shrink"):
			return true
	return false


## Tentativo di metamorfosi di un Adulto (al posto di deporre l'Uovo). Restituisce true se c'è stato.
func _try_mega(id: int) -> bool:
	if not megadults() or not mon.has(id) or mon[id]["l"] != "A" or is_mega(id):
		return false
	var a: String = mon[id]["loc"]
	var r := d6()
	if not _mega_sure() and r > turn_no:
		log_msg("   L'Adulto in %s tenta la metamorfosi… ma non ce la fa (%d)." % [area_name(a), r])
		return true
	var cup2 := _mega_cup()
	var ch: String = cup2[rng.randi_range(0, cup2.size() - 1)]
	match ch:
		"fail":
			log_msg("   Metamorfosi in %s: fallimento metabolico! L'Adulto si scioglie." % area_name(a))
			_fx("kill_mon", {"area": a, "l": "A"})
			mon.erase(id)
		"eggs2":
			var n := 0
			for i in 2:
				if avail("E") > 0:
					_add_mon("E", a)
					n += 1
			log_msg("   Metamorfosi in %s: qualcosa va storto e l'Adulto depone %d uova." % [area_name(a), n])
		_:
			mon[id]["mega"] = ch
			log_msg("   METAMORFOSI in %s: nasce %s (%s)!" % [area_name(a), D.MEGA[ch]["name"], D.MEGA[ch]["tip"]])
			_fx("mega", {"area": a, "k": ch})
	return true


## La Covatrice quando crescono gli Adulti: fa crescere i Piccoli, schiudere le Uova o depone 1-6 uova.
func _breeder_grow(id: int, fresh: Array) -> void:
	var a: String = mon[id]["loc"]
	var babies := mons_at(a).filter(func(m): return mon[m]["l"] == "B")
	var eggs := mons_at(a).filter(func(m): return mon[m]["l"] == "E" and not fresh.has(m))
	if babies.size() >= 2 and avail("A") > 0:
		var n := 0
		for m in babies:
			if avail("A") > 0:
				mon[m]["l"] = "A"
				n += 1
		log_msg("   La Covatrice fa crescere %d Piccoli in Adulti." % n)
	elif not eggs.is_empty() and avail("B") > 0:
		var n2 := 0
		for m in eggs:
			if avail("B") > 0:
				mon[m]["l"] = "B"
				n2 += 1
		log_msg("   La Covatrice fa schiudere %d Uova." % n2)
	else:
		var r := d6()
		var n3 := 0
		for i in r:
			if avail("E") > 0:
				fresh.append(_add_mon("E", a))
				n3 += 1
		log_msg("   La Covatrice depone %d uova (%d)." % [n3, r])


## Il Lanciafiamme: 12 dadi sull'equipaggio della sua area, o 6 su un'area accanto se nella sua non c'è
## nessuno sveglio. I dadi si dividono fra i bersagli; un Estintore ne toglie 3. Chi brucia non si mangia.
func _flamer_attack(id: int) -> void:
	var a: String = mon[id]["loc"]
	var target_a := ""
	var dice := 0
	if not crew_at(a).filter(func(c): return awake(c)).is_empty():
		target_a = a
		dice = 12
	else:
		var best := 0
		for n in adj(a):
			if is_space(n):
				continue
			var k := crew_at(n).size()
			if k > best:
				best = k
				target_a = n
		dice = 6
	if target_a == "" or (outside() and (is_out(target_a) or is_out(a))):
		return
	var ts := crew_at(target_a)
	if ts.is_empty():
		return
	attacked[id] = true
	ts.sort_custom(func(x, y): return c_con(x) + c_shell(x) < c_con(y) + c_shell(y))
	var alloc := {}
	var left := dice
	for c in ts:
		if left <= 0:
			break
		var need := mini(left, int(ceil(float(c_con(c) + c_shell(c)) / 3.5)) + 1)
		alloc[c] = need
		left -= need
	if left > 0:
		alloc[ts[0]] = alloc.get(ts[0], 0) + left
	# un Estintore in mano a chi non è bersaglio toglie 3 dadi
	for c in crew_at(target_a):
		if crew[c]["w"] >= 0 and wtype(crew[c]["w"]) == "extinguisher" and awake(c):
			var big := -1
			for t in alloc:
				if big < 0 or alloc[t] > alloc[big]:
					big = t
			if big >= 0:
				alloc[big] = maxi(0, alloc[big] - 3)
				log_msg("   %s spegne in parte le fiamme con l'Estintore." % cname(c))
			break
	log_msg("Il Lanciafiamme in %s sputa fuoco su %s (%d dadi)!" % [area_name(a), area_name(target_a), dice])
	_fx("attack", {"area": target_a})
	webs.erase(target_a)
	for c in alloc:
		if alloc[c] <= 0 or not on_board(c):
			continue
		var tot := _roll_show(alloc[c], "Fiamme contro %s" % cname(c))
		if hit_crew(c, tot):
			log_msg("   %s brucia (%d)." % [cname(c), tot])
			var w: int = crew[c]["w"]
			var fuel := w >= 0 and wtype(w) == "fuel"
			_crew_dies(c)
			_fx("kill_crew", {"c": c, "area": target_a})
			if fuel and d6() <= 3:
				_fuel_blast(target_a, "La Tanica di carburante di %s esplode!" % cname(c))
		else:
			log_msg("   %s resiste alle fiamme (%d)." % [cname(c), tot])
			var w2: int = crew[c]["w"]
			if w2 >= 0 and wtype(w2) == "fuel" and d6() <= 3:
				_fuel_blast(target_a, "La Tanica di carburante di %s esplode fra le fiamme!" % cname(c))


## Esplosione di una tanica fuori dalle mani dell'equipaggio: colpisce tutti nell'area.
func _fuel_blast(a: String, why: String) -> void:
	log_msg("   " + why)
	_fx("explode", {})
	var ch: String = known.get("fuel", "")
	if ch == "":
		ch = _draw_learn()
		_learn("fuel", ch)
	var eff := {}
	for m in mons_at(a):
		eff[m] = _eff_add({}, ch, "fuel")
	_apply_effects(eff)
	for c in crew_at(a):
		var tot := _roll_show(5, "Esplosione contro %s" % cname(c))
		if hit_crew(c, tot):
			log_msg("   L'esplosione uccide %s (%d)!" % [cname(c), tot])
			_crew_dies(c)
	webs.erase(a)


## Il Cervellone: raccoglie un'arma che l'equipaggio ha già usato (1-3 su un dado) e la usa.
func _brainiac_grab(id: int) -> void:
	if not is_mega(id, "brainiac") or mon[id].has("w"):
		return
	for w in weapons_at(mon[id]["loc"]):
		var t := wtype(w)
		if known.has(t) and D.WEAPONS[t]["kind"] != "device" and t != "fence":
			var r := d6()
			if r <= 3:
				wpn[w]["c"] = -2
				wpn[w]["loc"] = ""
				wpn[w]["mon"] = id
				mon[id]["w"] = w
				log_msg("Il Cervellone capisce come funziona %s e lo raccoglie (%d)!" % [wname(t), r])
			return


func _brainiac_attack(id: int) -> void:
	if not mon[id].has("w") or attacked.has(id) or mon[id]["st"]:
		return
	var w: int = mon[id]["w"]
	var t := wtype(w)
	var a: String = mon[id]["loc"]
	var rng_a := [a]
	match D.WEAPONS[t]["range"]:
		"adj":
			rng_a.append_array(adj(a))
		"los":
			rng_a = los(a)
	var target := -1
	var tc := 999
	for x in rng_a:
		for c in crew_at(x):
			if c_con(c) < tc and crew[c]["k"] != "robot":
				tc = c_con(c)
				target = c
	if target < 0:
		return
	attacked[id] = true
	var x2: String = crew[target]["loc"]
	log_msg("Il Cervellone usa %s contro %s!" % [wname(t), cname(target)])
	_fx("attack", {"area": x2})
	match t:
		"beamer", "extinguisher":
			log_msg("   …ma non succede niente.")
		"pistol":
			var tot := _roll_show(5, "Pistola del Cervellone")
			if tot >= c_con(target):
				crew[target]["st"] = turn_no
				log_msg("   %s è stordito (%d)." % [cname(target), tot])
		"grenade", "fuel":
			for s2 in section(x2):
				for c in crew_at(s2):
					if t == "grenade" and gas_proof(c):
						continue
					var tot2 := _roll_show(5, "%s contro %s" % [wname(t), cname(c)])
					if t == "grenade" and tot2 >= c_con(c):
						crew[c]["st"] = turn_no
						log_msg("   Il gas stordisce %s (%d)." % [cname(c), tot2])
					elif t == "fuel" and hit_crew(c, tot2):
						log_msg("   L'esplosione uccide %s (%d)!" % [cname(c), tot2])
						_crew_dies(c)
		_:
			var tot3 := _roll_show(3, "%s del Cervellone" % wname(t))
			if hit_crew(target, tot3):
				log_msg("   %s cade (%d)!" % [cname(target), tot3])
				_crew_dies(target)
				_fx("kill_crew", {"c": target, "area": x2})
	# le armi da lancio tornano al deposito
	var back: Array = D.WEAPONS[t].get("back", [])
	if not back.is_empty():
		wpn[w]["c"] = -1
		wpn[w]["loc"] = back[0]
		wpn[w].erase("mon")
		mon[id].erase("w")


## Armi in mano ai mostri morti o cambiati: cadono a terra.
func _mega_sync() -> void:
	for w in wpn:
		if int(wpn[w]["c"]) == -2:
			var m: int = wpn[w].get("mon", -1)
			if not is_mega(m, "brainiac"):
				wpn[w]["c"] = -1
				wpn[w]["loc"] = str(wpn[w].get("mloc", "cargo"))
				wpn[w].erase("mon")
				if mon.has(m):
					mon[m].erase("w")
			else:
				wpn[w]["mloc"] = mon[m]["loc"]
	for id in mon:
		if mon[id].get("mega", "") != "" and mon[id]["l"] != "A":
			mon[id].erase("mega")


## Fine dell'attacco dei mostri: il Tessitore tesse, il Cervellone tenta l'autodistruzione, in Cucina e in
## Mensa si assaggia di tutto, gli Adulti possono mangiare le armi.
func _revenge_after_attack() -> void:
	_mega_sync()
	for id in mon.keys():
		if not mon.has(id) or mon[id]["st"]:
			continue
		var a: String = mon[id]["loc"]
		if is_mega(id, "webber") and crew_at(a).filter(func(c): return awake(c)).is_empty() and not webs.has(a):
			webs[a] = true
			log_msg("Il Tessitore stende una ragnatela in %s." % area_name(a))
		if is_mega(id, "brainiac") and a in D.BRIDGES and sd_left < 0 and not solo():
			var r := d6()
			if r == 1:
				sd_left = 3
				log_msg("Il Cervellone smanetta sul %s… e avvia l'AUTODISTRUZIONE!" % area_name(a))
				_fx("alarm", {})
	if opts.get("kitchen", false):
		await _kitchen()
	if opts.get("eat_weapons", false) or megadults():
		await _eat_weapons()
	_mega_sync()


## Cucina e Mensa: le Cose Verdi senza equipaggio intorno assaggiano cibo, detersivi e posate.
func _kitchen() -> void:
	for a in ["galley", "mess"]:
		if not crew_at(a).is_empty():
			continue
		var eff := {}
		var parts := []
		for m in mons_at(a):
			if mon[m]["st"] or mon[m]["l"] == "E":
				continue
			var r := d6()
			var ch: String = ["grow", "shrink", "kill4", "stun5", "zg", "zg"][r - 1]
			if ch == "zg":
				ch = zgwortz_roll()
			parts.append("%s: %s" % [mname(m), _zg_name(ch)])
			if ch == "dies":
				eff[m] = _eff_add(eff.get(m, {}), "", "food")
				eff[m]["dies"] = true
			else:
				eff[m] = _eff_add(eff.get(m, {}), ch, "food")
		if not eff.is_empty():
			log_msg("In %s le Cose Verdi assaggiano di tutto — %s." % [area_name(a), ", ".join(parts)])
			_apply_effects(eff)
			last_area = a
			changed.emit()


## Lo Zgwortz con la regola della Cucina: ogni barattolo ha un effetto a caso.
func zgwortz_roll() -> String:
	return ["grow", "grow", "none", "kill4", "stun5", "dies"][d6() - 1]


func _zg_name(ch: String) -> String:
	if ch == "dies":
		return "reazione allergica mortale"
	if ch == "none":
		return "niente"
	return chit_name(ch)


## Un Adulto da solo con un'arma già usata contro le Cose Verdi può mangiarla.
func _eat_weapons() -> void:
	var done := {}
	for id in mon.keys():
		if not mon.has(id) or mon[id]["l"] != "A" or mon[id]["st"] or done.has(id):
			continue
		if not (opts.get("eat_weapons", false) or is_mega(id, "slimer")):
			continue
		var a: String = mon[id]["loc"]
		if not crew_at(a).is_empty():
			continue
		for w in weapons_at(a):
			var t := wtype(w)
			if not known.has(t) or D.WEAPONS[t]["kind"] == "device" or wpn[w]["on"]:
				continue
			var c := await pick(MON_SEAT, "eatw", "%s in %s può mangiare %s (effetto: %s). Lo mangia?" % [mname(id), area_name(a), wname(t), chit_name(effect_of(t))],
				["Sì, lo mangia", "No"], {"w": w, "m": id})
			if c != 0:
				continue
			done[id] = true
			var back: Array = D.WEAPONS[t].get("back", [])
			if t in ["zgwortz", "grenade", "fuel"] and not back.is_empty():
				wpn[w]["loc"] = back[0]
			else:
				wpn[w]["out"] = true
				wpn[w]["loc"] = ""
			log_msg("%s in %s mangia %s!" % [mname(id), area_name(a), wname(t)])
			if not is_mega(id, "slimer") or not opts.get("eat_weapons", false):
				var ch := _draw()
				log_msg("   Che indigestione: %s." % chit_name(ch))
				_fx("chit", {"chit": ch, "t": ""})
				_apply_effects({id: _eff_add({}, ch, "eat")})
				cup.append(ch)
			last_area = a
			changed.emit()
			break


## Variante delle armi: il gettone «1 dado di Frammenti» resta solo con 1-2 su un dado, altrimenti se ne pesca un altro.
func _draw_learn() -> String:
	var ch := _draw()
	if ch == "frag" and opts.get("frag_reroll", false):
		var r := d6()
		if r > 2:
			cup.append(ch)
			ch = _draw()
			log_msg("   (Frammenti ritirati: %d)" % r)
	return ch


## Variante delle armi: una tanica che esplode in un Serbatoio fa saltare tutto il Serbatoio.
func _pod_check(sect: Array) -> void:
	if not opts.get("pod_explode", false):
		return
	for p in ["fuel1", "fuel2"]:
		if not (p in sect) or pods_gone.has(p):
			continue
		var cans := weapons_at(p).filter(func(w): return wtype(w) == "fuel")
		if cans.is_empty():
			continue
		pods_gone[p] = true
		log_msg("KABOOM! Le taniche nel %s esplodono tutte insieme: il Serbatoio salta in aria!" % area_name(p))
		_fx("explode", {})
		for w in cans:
			wpn[w]["out"] = true
			wpn[w]["loc"] = ""
		for m in mons_at(p):
			mon.erase(m)
		for c in crew_at(p):
			_crew_dies(c)
		for n in adj(p):
			if is_out(n):
				for m2 in mons_at(n):
					mon.erase(m2)
				for c2 in crew_at(n):
					_crew_dies(c2)
			else:
				_fuel_blast(n, "L'onda d'urto investe %s." % area_name(n))


# ================================================================ fuori dalla Znutar
## Regole «Outside the Znutar» (Dragon / edizione Steve Jackson): lo scafo attorno alla nave, quattro zone
## di spazio, le camere stagne, le tute a reazione, i carrelli elevatori, la tuta della Mascotte e le
## scialuppe che volano attorno alla nave.

var gear := {}            # id -> {t: jet/mover/soot, loc, c: chi la indossa (-1), out: distrutta}
var locked := {}          # camere stagne chiuse dal Ponte: stanza -> true
var bout := {}            # scialuppe nello spazio: b -> {loc, back: turno del rientro dopo il getto, gone}
var gear_done := {}       # chi ha già indossato o lasciato qualcosa in questa fase delle armi


func outside() -> bool:
	return opts.get("outside", false)


func is_out(a: String) -> bool:
	return AR.has(a) and AR[a]["kind"] in ["scafo", "spazio"]


func is_space(a: String) -> bool:
	return AR.has(a) and AR[a]["kind"] == "spazio"


## L'altra parte di una camera stagna: dalla stanza al suo tratto di scafo e viceversa.
func lock_other(a: String) -> String:
	if not outside() or not AR.has(a):
		return ""
	if AR[a]["kind"] == "scafo":
		return str(AR[a].get("airlock", ""))
	if a in D.outside_data()["airlocks"]:
		return "s_" + a
	return ""


## Si può passare la camera stagna? I mostri non entrano se dentro c'è equipaggio sveglio (comando manuale)
## o se il Ponte l'ha chiusa; la Mascotte esce solo con la sua tuta.
func _lock_open(from: String, to: String, for_crew: bool, unit: int) -> bool:
	var room: String = to if not is_out(to) else from
	if locked.has(room):
		return false
	if for_crew:
		if unit >= 0 and crew[unit]["k"] == "mascot" and gear_of(unit) != "soot" and is_out(to):
			return false
		return true
	if is_out(from):
		for c in crew_at(to):
			if awake(c):
				return false
	return true


func gear_of(c: int) -> String:
	var g: int = crew[c].get("g", -1)
	return gear[g]["t"] if g >= 0 and gear.has(g) else ""


func _mode(c: int) -> String:
	var g := gear_of(c)
	return "jet" if g == "jet" else ("mover" if g == "mover" else "walk")


func c_att(c: int) -> int:
	var g := gear_of(c)
	if g in ["jet", "mover"]:
		return int(D.GEAR[g]["att"])
	return int(cdef(c)["att"])


func c_mov(c: int) -> int:
	var g := gear_of(c)
	if g != "":
		return int(D.GEAR[g]["mov"])
	return int(cdef(c)["mov"])


func c_con(c: int) -> int:
	return int(cdef(c)["con"]) * (2 if gear_of(c) == "soot" else 1)


## Costituzione della corazza (tuta a reazione 20, carrello 40): i colpi oltre passano a chi c'è dentro.
func c_shell(c: int) -> int:
	var g := gear_of(c)
	return int(D.GEAR[g]["con"]) if g in ["jet", "mover"] else 0


## Il gas non tocca il Robot, chi è in tuta a reazione e la Mascotte nella sua tuta.
func gas_proof(c: int) -> bool:
	return crew[c]["k"] == "robot" or gear_of(c) in ["jet", "soot"]


## Applica un colpo «da uccidere» a un membro: prima cede la corazza. Restituisce true se muore.
func hit_crew(c: int, tot: int) -> bool:
	var sh := c_shell(c)
	if sh > 0:
		if tot < sh:
			return false
		var g: int = crew[c]["g"]
		log_msg("   %s di %s va in pezzi!" % [D.GEAR[gear[g]["t"]]["name"], cname(c)])
		gear[g]["out"] = true
		gear[g]["c"] = -1
		crew[c]["g"] = -1
		if is_space(crew[c]["loc"]):
			log_msg("   %s resta nel vuoto e si perde fra le stelle." % cname(c))
			return true
		return tot - sh >= c_con(c)
	return tot >= c_con(c)


func gear_at(a: String) -> Array:
	var out := []
	for g in gear:
		if not gear[g]["out"] and gear[g]["c"] == -1 and gear[g]["loc"] == a:
			out.append(g)
	return out


## Azioni con l'equipaggiamento nella fase delle armi.
func gear_actions(cid: int) -> Array:
	var out := []
	if not outside() or crew[cid].get("boat", "") != "" or gear_done.has(cid):
		return out
	var a: String = crew[cid]["loc"]
	var k: String = crew[cid]["k"]
	var mine := gear_of(cid)
	if mine != "":
		var ok := true
		if mine == "jet" and is_space(a):
			ok = false
		if mine == "mover" and not (a in D.MOVER_ROOMS):
			ok = false
		if ok:
			out.append({"a": "unsuit", "c": cid, "label": "%s lascia %s" % [cdef(cid)["short"], D.GEAR[mine]["name"]]})
		return out
	var seen := {}
	for g in gear_at(a):
		var t: String = gear[g]["t"]
		if seen.has(t):
			continue
		if t == "soot" and k != "mascot":
			continue
		if t != "soot" and k == "mascot":
			continue
		seen[t] = true
		out.append({"a": "suit", "c": cid, "g": g, "label": "%s indossa %s" % [cdef(cid)["short"], D.GEAR[t]["name"]]})
	return out


func _apply_gear(act: Dictionary) -> void:
	var cid: int = act["c"]
	gear_done[cid] = true
	if act["a"] == "suit":
		var g: int = act["g"]
		gear[g]["c"] = cid
		crew[cid]["g"] = g
		var w: int = crew[cid]["w"]
		if w >= 0 and gear[g]["t"] in ["jet", "mover"]:
			# entrando nella tuta si posa l'arma (il carrello non tiene che il carburante)
			if gear[g]["t"] == "jet" or wtype(w) != "fuel":
				wpn[w]["c"] = -1
				wpn[w]["loc"] = crew[cid]["loc"]
				crew[cid]["w"] = -1
		log_msg("%s indossa: %s." % [cname(cid), D.GEAR[gear[g]["t"]]["name"]])
	else:
		var g2: int = crew[cid]["g"]
		gear[g2]["c"] = -1
		gear[g2]["loc"] = crew[cid]["loc"]
		crew[cid]["g"] = -1
		log_msg("%s lascia: %s." % [cname(cid), D.GEAR[gear[g2]["t"]]["name"]])
	changed.emit()


## Le scialuppe nello spazio: dove sono e chi c'è a bordo.
func boat_crew(b: String) -> Array:
	var out := []
	for c in board_crew():
		if crew[c].get("boat", "") == b:
			out.append(c)
	return out


## Il gas e l'estintore non funzionano fuori dalla nave.
func works_outside(t: String) -> bool:
	return not (t in ["extinguisher", "grenade"])


## Zona di spazio di un'area esterna.
func space_of(a: String) -> String:
	return str(AR[a].get("space", "")) if is_out(a) else ""


## Chiusura a distanza delle camere stagne: il Capitano o il Primo Ufficiale su un Ponte, all'inizio del
## turno delle Cose Verdi, può chiuderne una (resta chiusa fino al turno successivo dei mostri).
func _remote_lock() -> void:
	locked = {}
	if not outside():
		return
	var who := -1
	for c in board_crew():
		if crew[c]["k"] in ["captain", "first_officer"] and crew[c]["loc"] in D.BRIDGES and awake(c):
			who = c
			break
	if who < 0:
		return
	var cands := []
	for r in D.outside_data()["airlocks"]:
		var sk: String = "s_" + str(r)
		var near := false
		for m in mon:
			var ml: String = mon[m]["loc"]
			if ml == sk or ml == r:
				near = true
		if near:
			cands.append(r)
	if cands.is_empty():
		return
	var seat := team_of(who) if mutiny() else 0
	var opts_l := ["Nessuna"]
	for r in cands:
		opts_l.append(area_name(r))
	phase = "mlock"
	var c2 := await pick(seat, "lock", "%s dal Ponte: chiudi una camera stagna?" % cdef(who)["short"], opts_l, {"rooms": cands})
	if c2 > 0:
		locked[cands[c2 - 1]] = true
		log_msg("%s chiude dal Ponte la camera stagna di %s." % [cname(who), area_name(cands[c2 - 1])])
		changed.emit()


## Le scialuppe fuori dalla nave: decollo dall'hangar, volo fra le zone di spazio, rientro, getto del razzo
## e partenza per Snudl-1.
func _boat_act(act: String, r: Dictionary) -> void:
	var b := str(r.get("b", ""))
	if not D.BOATS.has(b):
		return
	var cid := int(r.get("c", -1))
	var ok := false
	if crew.has(cid):
		for s in special_actions(cid):
			if s["act"] == act and s["b"] == b and (act != "bmove" or s["to"] == str(r.get("to", ""))):
				ok = true
	if not ok and act != "launch":
		return
	var bn: String = String(D.BOATS[b]["name"]).capitalize()
	match act:
		"launch":
			var ids := []
			for x in r.get("ids", []):
				var id := int(x)
				if on_board(id) and awake(id) and crew[id]["loc"] == b and not ids.has(id) and gear_of(id) in ["", "soot"] \
						and (not mutiny() or team_of(id) == cur_team):
					ids.append(id)
			if ids.is_empty() or not boat_room(b, ids) or ids.filter(func(i): return not (crew[i]["k"] in ["robot", "mascot"])).is_empty():
				return
			if launched.has(b) or bout.has(b):
				return
			var sp: String = AR["s_" + b]["space"]
			bout[b] = {"loc": sp, "back": 0, "gone": false, "team": cur_team}
			for id in ids:
				crew[id]["loc"] = sp
				crew[id]["boat"] = b
				moved[id] = true
			log_msg("%s decolla dall'hangar con %s ed esce nello %s." % [bn, ", ".join(ids.map(func(i): return cdef(i)["short"])), area_name(sp).to_lower()])
			last_area = sp
			_fx("escape", {"b": b})
		"bmove":
			var to := str(r.get("to", ""))
			bout[b]["loc"] = to
			for id in boat_crew(b):
				crew[id]["loc"] = to
				moved[id] = true
			log_msg("%s vola: %s." % [bn, area_name(to)])
			last_area = to
		"dock":
			for id in boat_crew(b):
				crew[id]["loc"] = b
				crew[id]["boat"] = ""
				moved[id] = true
			bout.erase(b)
			log_msg("%s rientra nel suo hangar." % bn)
			last_area = b
		"blast":
			var sp2: String = bout[b]["loc"]
			var cans := 2 if b == "cockboat" else 1
			log_msg("%s accende i razzi a pochi metri dallo scafo: getto di fuoco su %s!" % [bn, area_name(sp2)])
			var ch: String
			var learn := false
			if known.has("fuel"):
				ch = known["fuel"]
			else:
				ch = _draw_learn()
				learn = true
			var eff := {}
			for x in AR:
				if AR[x]["kind"] == "scafo" and space_of(x) == sp2:
					for m in mons_at(x):
						for i in cans:
							eff[m] = _eff_add(eff.get(m, {}), ch, "fuel")
			var rep := _apply_effects(eff)
			if learn:
				if ch in ["frag", "stun5", "kill5", "kill4", "kill3"] and not rep["used"].has("fuel"):
					cup.append(ch)
				else:
					_learn("fuel", ch)
			for x in AR:
				if AR[x]["kind"] == "scafo" and space_of(x) == sp2:
					for c in crew_at(x):
						var tot := _roll_show(5 * cans, "Getto del razzo contro %s" % cname(c))
						if hit_crew(c, tot):
							log_msg("   Il getto uccide %s (%d)!" % [cname(c), tot])
							_crew_dies(c)
							_fx("kill_crew", {"c": c, "area": x})
			bout[b]["gone"] = true
			bout[b]["back"] = turn_no + 3
			for id in boat_crew(b):
				moved[id] = true
				attacked[id] = true
			log_msg("%s schizza via nello spazio: tornerà fra tre turni." % bn)
			_fx("explode", {})
			last_area = sp2
		"leave":
			var ids2 := boat_crew(b)
			launched[b] = true
			bout.erase(b)
			for id in ids2:
				var w: int = crew[id]["w"]
				if w >= 0:
					wpn[w]["c"] = -1
					wpn[w]["loc"] = b
					crew[id]["w"] = -1
				crew[id]["state"] = "boat"
				crew[id]["loc"] = ""
				crew[id]["boat"] = ""
			boats.append({"b": b, "crew": ids2, "survivors": [], "fate": "", "team": cur_team})
			log_msg("FUGA! %s fa rotta verso Snudl-1 con %s." % [bn, ", ".join(ids2.map(func(i): return cdef(i)["short"]))])
			_fx("escape", {"b": b})
			changed.emit()
			_check_end()
			return
	changed.emit()
	_check_end()


## All'inizio del turno dell'equipaggio tornano le scialuppe schizzate via col getto del razzo.
func _boats_back() -> void:
	for b in bout:
		if bout[b]["gone"] and turn_no >= int(bout[b]["back"]):
			bout[b]["gone"] = false
			log_msg("%s ritorna: %s." % [String(D.BOATS[b]["name"]).capitalize(), area_name(bout[b]["loc"])])


# ================================================================ ammutinamento (3 giocatori)
## 3-4 Player Rules v1.1: la squadra del Capitano (posto 0) contro quella del Primo Ufficiale (posto 2),
## con le Cose Verdi (posto 1) come nemico comune. Le squadre non cooperano e possono combattersi.

var cur_team := 0         # squadra di turno (posto 0 o 2)


func mutiny() -> bool:
	return opts.get("mutiny", false)


## Squadra di un membro (0 Capitano, 2 Primo Ufficiale); il Robot è di chi lo comanda (-1 nessuno).
func team_of(id: int) -> int:
	if not mutiny():
		return 0
	if crew[id]["k"] == "robot":
		return robot_ctrl()
	return int(crew[id]["team"])


func team_crew(t: int) -> Array:
	return board_crew().filter(func(c): return team_of(c) == t)


## Chi comanda il Robot: chi ha il telecomando e lo vede, se nessun avversario col disturbatore gli sta accanto.
func robot_ctrl() -> int:
	var rob := robot_id()
	if rob < 0 or not on_board(rob):
		return -1
	var ra: String = crew[rob]["loc"]
	var ctrl := -1
	for w in wpn:
		if wpn[w]["t"] == "rcontrol" and int(wpn[w]["c"]) >= 0:
			var h: int = wpn[w]["c"]
			if on_board(h) and awake(h) and ra in los(crew[h]["loc"]):
				ctrl = int(crew[h]["team"])
	if ctrl < 0:
		return -1
	for w in wpn:
		if wpn[w]["t"] == "jammer" and int(wpn[w]["c"]) >= 0:
			var j: int = wpn[w]["c"]
			if on_board(j) and crew[j]["loc"] == ra and int(crew[j]["team"]) != ctrl:
				return -1
	return ctrl


## Avversari nell'area (il Robot senza padrone si può attaccare ma non conta per prendere le armi).
func enemies_at(a: String, cid: int, neutral := true) -> Array:
	var me := team_of(cid) if crew[cid]["k"] != "robot" else robot_ctrl()
	var out := []
	for o in crew_at(a):
		var t := team_of(o)
		if t == me:
			continue
		if t < 0 and not neutral:
			continue
		out.append(o)
	return out


## Scoperta: un dado decide chi scopre le Cose Verdi (1-2 il Capitano, 3-4 il Primo Ufficiale, 5-6 entrambi,
## con un solo membro a testa).
func _discovery_mut() -> void:
	var r := d6()
	var who := [0] if r <= 2 else ([2] if r <= 4 else [0, 2])
	_fx("dice", {"dice": [r], "info": "Chi scopre le Cose Verdi", "total": r})
	var can := {}
	for t in [0, 2]:
		cur_team = t
		can[t] = false
		for c in team_crew(t):
			if not crew_moves(c).is_empty():
				can[t] = true
	who = who.filter(func(t): return can[t])
	if who.is_empty():
		who = [0, 2].filter(func(t): return can[t]).slice(0, 1)
	var names := {0: "la squadra del Capitano", 2: "la squadra del Primo Ufficiale"}
	log_msg("Allarme! Tiro %d: scopre le Cose Verdi %s." % [r, " e ".join(who.map(func(t): return names[t])) if not who.is_empty() else "nessuno"])
	var limit := 1 if who.size() == 2 else 2
	for t in who:
		cur_team = t
		var before := moved.size()
		await _crew_moves(before + limit)
	if not moved.is_empty():
		phase = "discovery_attack"
		for t in who:
			cur_team = t
			await _crew_attacks()
	cur_team = 0


## Attacchi contro l'equipaggio avversario: dadi a mani nude e armi con effetto fisso.
func _attack_crew(x: String, entries: Array) -> void:
	var kill := {}
	var stun := {}
	var slow := {}
	var desc := []
	for e in entries:
		var cid: int = e["c"]
		var tg: int = int(e["tgt"]) - D.CREW_T
		if not on_board(tg) or crew[tg]["loc"] != x:
			continue
		if not e["usew"]:
			kill[tg] = kill.get(tg, 0) + c_att(cid)
			desc.append("%s a mani nude su %s" % [cdef(cid)["short"], cdef(tg)["short"]])
			continue
		var t: String = e["t"]
		var k: String = D.VS_CREW.get(t, "none")
		desc.append("%s usa %s su %s" % [cdef(cid)["short"], wname(t), cdef(tg)["short"]])
		if k.begins_with("kill"):
			kill[tg] = kill.get(tg, 0) + int(k.substr(4))
		elif k == "stun5":
			stun[tg] = stun.get(tg, 0) + 5
		elif k == "slow":
			slow[tg] = true
	if desc.is_empty():
		return
	log_msg("Ammutinamento in %s: %s." % [area_name(x), "; ".join(desc)])
	_fx("attack", {"area": x, "crew": entries.map(func(e): return e["c"])})
	for tg in kill:
		var tot := _roll_show(kill[tg], "%d dadi contro %s (cost. %d)" % [kill[tg], cname(tg), c_con(tg) + c_shell(tg)])
		if hit_crew(tg, tot):
			log_msg("   %s cade (%d)!" % [cname(tg), tot])
			_crew_dies(tg)
			_fx("kill_crew", {"c": tg, "area": x})
		else:
			log_msg("   %s resiste (%d)." % [cname(tg), tot])
	for tg in stun:
		if not on_board(tg) or crew[tg]["k"] == "robot":
			continue
		var tot := _roll_show(stun[tg], "%d dadi per stordire %s" % [stun[tg], cname(tg)])
		if tot >= int(cdef(tg)["con"]):
			crew[tg]["st"] = turn_no
			log_msg("   %s è stordito (%d)." % [cname(tg), tot])
		else:
			log_msg("   %s non si stordisce (%d)." % [cname(tg), tot])
	for tg in slow:
		if on_board(tg) and crew[tg]["k"] != "robot":
			crew[tg]["slow"] = true
			log_msg("   La Siringa intontisce %s: al prossimo turno si muove della metà." % cname(tg))


## Punti di una squadra: costituzione dei vivi a bordo (senza Robot e Mascotte).
func team_aboard(t: int) -> float:
	var pts := 0.0
	for c in board_crew():
		if int(crew[c]["team"]) == t and not (crew[c]["k"] in ["robot", "mascot"]):
			pts += float(cdef(c)["con"])
	return pts


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
	var paths := reach(here, mmov(m), false)
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
	if mon.is_empty() and mutiny():
		log_msg("Le Cose Verdi sono state sterminate!")
		_epilogue_and_end("exterminated", 0.0)
		return
	if mon.is_empty():
		var pts := 0.0
		for cid in board_crew():
			if not (crew[cid]["k"] in ["robot", "mascot"]):
				pts += float(cdef(cid)["con"])
		log_msg("Le Cose Verdi sono state sterminate!")
		_epilogue_and_end("exterminated", pts)
		return
	var nobody: bool = board_crew().is_empty()
	if mutiny() and not nobody and board_crew().filter(func(c): return not (crew[c]["k"] in ["robot", "mascot"])).is_empty():
		nobody = true   # restano solo il Robot senza padrone e la Mascotte
		for c in board_crew():
			_crew_dies(c)
	if nobody:
		if boats.is_empty():
			vp = [0.0, D.VP_TAKEOVER, 0.0] if mutiny() else [0.0, D.VP_TAKEOVER]
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
				var c := await pick(int(bt.get("team", 0)), "epi1", "%s: che rotta?" % bname.capitalize(),
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
				var c2 := await pick(int(bt.get("team", 0)), "epi4", "%s: indigeni ostili! Che fare?" % bname.capitalize(),
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
				var c3 := await pick(int(bt.get("team", 0)), "epi14", "%s: quattro anni di viaggio, le scorte finiscono. Rotta?" % bname.capitalize(),
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
				var c := await pick(int(bt.get("team", 0)), "alt1", "%s: che rotta?" % bn,
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
				var c2 := await pick(int(bt.get("team", 0)), "alt4", "%s: %s Che fare?" % [bn, "alieni ostili!" if step == 4 else "vita intelligente!"],
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
				var c3 := await pick(int(bt.get("team", 0)), "alt16", "%s: un relitto alieno alla deriva!" % bn, ["Passare oltre", "Abbordarlo"], x)
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
				var c4 := await pick(int(bt.get("team", 0)), "alt26", "%s: i computer del relitto sono stranamente alieni." % bn,
					["Andarsene", "Provare a usarli"], x)
				step = 30 if c4 == 0 else 28
			27:
				var c5 := await pick(int(bt.get("team", 0)), "alt27", "%s: un antico portale temporale!" % bn, ["Volare via", "Attivare il portale"], x)
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
		var th := {0: 0.0, 2: 0.0}
		for bt in boats:
			if opts.get("alt_epilogue", false):
				await _epilogue_alt(bt)
			else:
				await _epilogue_boat(bt)
			var mult := 0.5 if bt["fate"] == "marooned" else 1.0
			for id in bt["survivors"]:
				if not (crew[id]["k"] in ["robot", "mascot"]):
					home += float(cdef(id)["con"]) * mult
					th[int(crew[id]["team"])] += float(cdef(id)["con"]) * mult
		if mutiny():
			_finish_mutiny(kind, th)
		else:
			match kind:
				"exterminated":
					var aboard := float(_pending_end["aboard"]) if pods_gone.size() < 2 else 0.0
					vp = [aboard + home, D.VP_TAKEOVER if not boats.is_empty() else 0.0]
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
		if not pods_gone.is_empty():
			var pen := 20.0 * pods_gone.size()
			vp[0] = maxf(0.0, vp[0] - pen)
			if vp.size() >= 3:
				vp[2] = maxf(0.0, vp[2] - pen)
			end_reason += " (Serbatoi esplosi: -%d punti all'equipaggio)" % int(pen)
		log_msg("■ " + end_reason)
	var wtxt := {"crew": "Vince l'Equipaggio!", "mon": "Vincono le Cose Verdi!", "draw": "Pareggio.",
		"cap": "Vince il Capitano!", "fo": "Vince il Primo Ufficiale!"}
	if mutiny() and vp.size() >= 3:
		log_msg("Punti vittoria: Capitano %s, Primo Ufficiale %s, Cose Verdi %s. %s" % [_fmt(vp[0]), _fmt(vp[2]), _fmt(vp[1]), wtxt.get(winner, "")])
	else:
		log_msg("Punti vittoria: Equipaggio %s, Cose Verdi %s. %s" % [_fmt(vp[0]), _fmt(vp[1]), wtxt.get(winner, "")])
	phase = "fine_partita"
	result = {"winner": winner, "reason": end_reason, "vp": vp}
	changed.emit()
	game_ended.emit(result)


func _finish_mutiny(kind: String, th: Dictionary) -> void:
	var cap: float = th[0] + team_aboard(0)
	var fo: float = th[2] + team_aboard(2)
	var m := 0.0
	match kind:
		"exterminated":
			end_reason = "Le Cose Verdi sono state sterminate."
		"sd":
			m = D.VP_SELFDESTRUCT
			end_reason = "La Znutar è esplosa: le Cose Verdi sono distrutte."
		"escape":
			m = D.VP_TAKEOVER
			end_reason = "Gli ammutinati e i lealisti hanno abbandonato la nave alle Cose Verdi."
	vp = [cap, m, fo]
	if m > cap + fo:
		winner = "mon"
		end_reason += " Le Cose Verdi fanno più punti delle due squadre insieme: si parla dell'ammutinamento per anni."
	elif cap > fo:
		winner = "cap"
		end_reason += " Il Capitano denuncia l'ammutinamento e gli ammutinati finiscono sotto processo."
	elif fo > cap:
		winner = "fo"
		end_reason += " La gente sta con il Primo Ufficiale: il Capitano va davanti alla corte marziale."
	else:
		winner = "draw"


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

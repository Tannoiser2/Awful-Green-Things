class_name AGTAI
extends RefCounted
## IA di The Awful Green Things, per l'Equipaggio e per le Cose Verdi.
## Livelli: 0 = facile, 1 = normale, 2 = difficile (più prudente nei calcoli e meno distratta).

const D = preload("res://scripts/data/agt_data.gd")

var level := 1
var rng := RandomNumberGenerator.new()
var _plan := []
var _plan_key := ""
var _stay := {}
static var _p := {}


func _init(lvl := 1, seed := 1) -> void:
	level = lvl
	rng.seed = seed


## Probabilità che n dadi diano almeno k.
static func p_at_least(n: int, k: int) -> float:
	if k <= n:
		return 1.0
	if n <= 0:
		return 0.0
	if k > 6 * n:
		return 0.0
	var key := n * 1000 + k
	if _p.has(key):
		return _p[key]
	var dist := {0: 1.0}
	for i in n:
		var nd := {}
		for s in dist:
			for f in range(1, 7):
				nd[s + f] = nd.get(s + f, 0.0) + dist[s] / 6.0
		dist = nd
	var tot := 0.0
	for s in dist:
		if s >= k:
			tot += dist[s]
	_p[key] = tot
	return tot


## Dadi che servono per avere almeno la probabilità p di arrivare a k.
static func dice_for(k: int, p: float) -> int:
	for n in range(1, 30):
		if p_at_least(n, k) >= p:
			return n
	return 30


func _thr() -> float:
	return [0.45, 0.6, 0.7][clampi(level, 0, 2)]


func decide(e: AGTEngine, s: int, req: Dictionary):
	match req["type"]:
		"pick":
			return _pick(e, req)
		"loc":
			return _loc(e, s, req)
		"crew_setup":
			return _crew_setup(e, req)
		"mplace":
			return _mplace(e, req)
		"grow":
			return _grow(e, req)
		"mmove":
			return _mmove(e)
		"mattack":
			return _mattack(e, req)
		"grab":
			return _grab(e, req)
		"cmove":
			return _cmove(e, req)
		"cattack":
			return _cattack(e, req)
	return null


func _pick(e: AGTEngine, req: Dictionary) -> int:
	match str(req.get("ctx", "")):
		"epi1":
			return 0   # dritti a casa: 50% di arrivare in due tappe
		"epi4":
			return 0 if req.get("boat", "") == "cockboat" else 1
		"epi14":
			return 0
	return 0


func _loc(e: AGTEngine, s: int, req: Dictionary) -> String:
	var allowed: Array = req["allowed"]
	if s == AGTEngine.MON_SEAT:
		# la prima Cosa Verde: vicino all'equipaggio ma non troppo
		var best: String = allowed[0]
		var bv := -999.0
		for a in allowed:
			var v: float = -absf(_crew_dist(e, a) - 2.0) + rng.randf() * 0.5
			if v > bv:
				bv = v
				best = a
		return best
	return allowed[rng.randi_range(0, allowed.size() - 1)]


func _crew_dist(e: AGTEngine, a: String) -> float:
	var d := 99
	for c in e.board_crew():
		d = mini(d, e.dist(a, e.crew[c]["loc"]))
	return float(d)


# ================================================================ Cose Verdi

func _mplace(e: AGTEngine, req: Dictionary) -> Dictionary:
	var left: Dictionary = req["left"]
	var l := "A"
	for k in ["A", "B", "E"]:
		if int(left.get(k, 0)) > 0:
			l = k
			break
	var allowed: Array = req["allowed"]
	var best: String = allowed[0]
	var bv := -999.0
	for a in allowed:
		var d := _crew_dist(e, a)
		var v: float
		if l == "E":
			v = d                       # uova lontano dall'equipaggio
		else:
			v = -absf(d - 1.5)           # adulti e piccoli pronti a colpire
		# lasciare spazio per allargarsi
		var free := 0
		for n in e.adj(a):
			if e.mons_at(n).is_empty() and e.crew_at(n).is_empty():
				free += 1
		v += 0.3 * free + rng.randf() * 0.4
		if v > bv:
			bv = v
			best = a
	return {"area": best, "l": l}


func _grow(e: AGTEngine, req: Dictionary) -> String:
	var opts: Array = req["options"]
	var count := {}
	for id in e.mon:
		if not e.mon[id]["st"]:
			count[e.mon[id]["l"]] = count.get(e.mon[id]["l"], 0) + 1
	var best := ""
	var bv := -1.0
	for l in opts:
		var n: int = count.get(l, 0)
		var v := 0.0
		match l:
			"F":
				v = mini(n, e.avail("B")) * 2.2
			"E":
				v = mini(n, e.avail("B")) * 1.9
			"B":
				v = mini(n, e.avail("A")) * 3.0
			"A":
				v = mini(n, e.avail("E")) * 1.25
		if v > bv:
			bv = v
			best = l
	return best


func _mmove(e: AGTEngine) -> Dictionary:
	var key := "m%d" % e.turn_no
	if _plan_key != key:
		_plan_key = key
		_plan = _plan_monsters(e)
	while not _plan.is_empty():
		var mv: Dictionary = _plan.pop_front()
		var ids := []
		for id in mv["ids"]:
			if e.mon_mobile(id) and e.mon[id]["loc"] == mv["from"]:
				ids.append(id)
		if ids.is_empty():
			continue
		if e.mon_moves(ids).has(mv["to"]):
			return {"ids": ids, "to": mv["to"]}
	return {}


func _bad_fence(e: AGTEngine, a: String) -> bool:
	if not e.fence_at(a):
		return false
	var k: String = e.known.get("fence", "")
	return not (k in ["grow", "none"])


func _plan_monsters(e: AGTEngine) -> Array:
	var mobile := []
	for id in e.mon:
		if e.mon_mobile(id):
			mobile.append(id)
	mobile.sort()
	var reach := {}
	for id in mobile:
		reach[id] = e.mon_moves([id])
	var dest := {}
	var rob := e.robot_id()
	# dadi già presenti in ogni area da mostri che non si muovono (uova, frammenti, storditi esclusi)
	var static_dice := {}
	for id in e.mon:
		if not e.mon_mobile(id) and not e.mon[id]["st"]:
			static_dice[e.mon[id]["loc"]] = static_dice.get(e.mon[id]["loc"], 0) + e.matt(id)
	# bersagli: membri dell'equipaggio, i più deboli e preziosi prima
	var targets := e.board_crew()
	targets.sort_custom(func(a, b): return _target_value(e, a) > _target_value(e, b))
	var area_dice := static_dice.duplicate()
	var committed := {}   # area -> costituzione già «prenotata»
	for c in targets:
		var t: String = e.crew[c]["loc"]
		var con: int = e.cdef(c)["con"]
		if c == rob and e.mon_count("A") < 9:
			continue
		var robot_there: bool = e.on_board(rob) and e.crew[rob]["loc"] == t and c != rob
		if robot_there:
			continue   # dove c'è il Robot si può attaccare solo lui
		var need := dice_for(con, _thr())
		var have: int = area_dice.get(t, 0) - committed.get(t, 0)
		var pick := []
		var cands := mobile.filter(func(id): return not dest.has(id) and (e.mon[id]["loc"] == t or reach[id].has(t)))
		cands.sort_custom(func(a, b): return e.matt(a) > e.matt(b))
		for id in cands:
			if have >= need:
				break
			pick.append(id)
			have += e.matt(id)
		if have >= need or (have >= need - 1 and level == 0):
			for id in pick:
				dest[id] = t
				area_dice[t] = area_dice.get(t, 0) + e.matt(id)
			committed[t] = committed.get(t, 0) + need
	# gli altri: se le Cose Verdi sono già in vantaggio stringono l'assedio, altrimenti si disperdono
	# in zone tranquille, lontano dall'equipaggio, a deporre uova
	var mdice := 0
	for id in e.mon:
		mdice += e.matt(id)
	var ccon := 0
	for c in e.board_crew():
		if c != rob:
			ccon += int(e.cdef(c)["con"])
	var hunt := float(mdice) * 3.5 > float(ccon) * 1.3
	var occupancy := {}
	for id in e.mon:
		occupancy[e.mon[id]["loc"]] = occupancy.get(e.mon[id]["loc"], 0) + 1
	for id in mobile:
		if dest.has(id):
			continue
		var here: String = e.mon[id]["loc"]
		var best := here
		var qv := func(a): return _hunt_value(e, a, occupancy) if hunt else _quiet_value(e, a, occupancy)
		var bv: float = qv.call(here) + 0.5
		if e.on_board(rob) and e.crew[rob]["loc"] == here:
			bv -= 20.0
		for a in reach[id]:
			if _bad_fence(e, a):
				continue
			if not e.crew_at(a).is_empty():
				continue
			var v: float = qv.call(a) + rng.randf() * 0.3
			if v > bv:
				bv = v
				best = a
		if best != here:
			dest[id] = best
			occupancy[here] = occupancy.get(here, 1) - 1
			occupancy[best] = occupancy.get(best, 0) + 1
	# raggruppa le mosse
	var groups := {}
	for id in dest:
		var from: String = e.mon[id]["loc"]
		if dest[id] == from:
			continue
		var k: String = from + ">" + dest[id]
		if not groups.has(k):
			groups[k] = {"from": from, "to": dest[id], "ids": []}
		groups[k]["ids"].append(id)
	var out := groups.values()
	# prima i gruppi che vanno ad attaccare
	out.sort_custom(func(a, b): return e.crew_at(a["to"]).size() > e.crew_at(b["to"]).size())
	return out


func _target_value(e: AGTEngine, c: int) -> float:
	var v := 30.0 - float(e.cdef(c)["con"])
	if e.crew[c]["w"] >= 0:
		v += 6.0
	if e.crew[c]["k"] == "robot":
		v -= 40.0
	if e.crew[c]["k"] == "mascot":
		v -= 4.0
	return v


func _hunt_value(e: AGTEngine, a: String, occ: Dictionary) -> float:
	var d := 99
	var rob := e.robot_id()
	for c in e.board_crew():
		if c != rob:
			d = mini(d, e.dist(a, e.crew[c]["loc"]))
	return -float(d) - 0.2 * float(occ.get(a, 0))


func _quiet_value(e: AGTEngine, a: String, occ: Dictionary) -> float:
	var d := _crew_dist(e, a)
	return minf(d, 4.0) - 0.6 * float(occ.get(a, 0))


func _mattack(e: AGTEngine, req: Dictionary) -> Dictionary:
	var a: String = req["areas"][0]
	var ms := e.mons_at(a).filter(func(id): return not e.mon[id]["st"] and not e.attacked.has(id) and e.matt(id) > 0)
	ms.sort_custom(func(x, y): return e.matt(x) > e.matt(y))
	var cs := e.crew_at(a)
	var rob := e.robot_id()
	if cs.has(rob):
		# si può attaccare solo il Robot: lo si fa solo se c'è qualche speranza
		var nd := 0
		for id in ms:
			nd += e.matt(id)
		if p_at_least(nd, 44) > 0.15:
			return {"area": a, "atk": [[ms, rob]]}
		return {"area": a, "atk": []}
	cs.sort_custom(func(x, y): return _target_value(e, x) > _target_value(e, y))
	var atk := []
	var free := ms.duplicate()
	for c in cs:
		if free.is_empty():
			break
		var con: int = e.cdef(c)["con"]
		var grp := []
		var nd := 0
		while not free.is_empty() and p_at_least(nd, con) < _thr() + 0.1:
			var id: int = free.pop_front()
			grp.append(id)
			nd += e.matt(id)
		if p_at_least(nd, con) < 0.2:
			# troppo pochi: meglio rinforzare un attacco già deciso
			free = grp + free
			break
		atk.append([grp, c])
	if not free.is_empty():
		if atk.is_empty():
			atk.append([free, cs[cs.size() - 1] if level == 0 else cs[0]])
		else:
			atk[0][0].append_array(free)
	return {"area": a, "atk": atk}


# ================================================================ Equipaggio

func _crew_setup(e: AGTEngine, req: Dictionary) -> Dictionary:
	var out := {}
	var opts: Dictionary = req["options"]
	for id in opts:
		var best: String = opts[id][0]
		var bv := -999.0
		for a in opts[id]:
			var v := 0.0
			if not e.weapons_at(a).is_empty():
				v += 2.0
			# baricentro: le aree centrali permettono di accorrere ovunque
			v -= _centrality(e, a) * 0.3
			v += rng.randf() * 0.5
			if v > bv:
				bv = v
				best = a
		out[id] = best
	return out


var _centr := {}
func _centrality(e: AGTEngine, a: String) -> float:
	if not _centr.has(a):
		var t := 0
		for b in D.area_list():
			t += e.dist(a, b)
		_centr[a] = float(t) / D.area_list().size()
	return _centr[a]


func _grab(e: AGTEngine, req: Dictionary) -> int:
	var acts: Array = req["actions"]
	var best := -1
	var bv := 0.5
	for i in acts.size():
		var a: Dictionary = acts[i]
		var v := 0.0
		match a["a"]:
			"take":
				var c: int = a["c"]
				var t: String = e.wtype(a["w"])
				if e.wpn[a["w"]]["on"]:
					continue   # un recinto acceso resta dov'è
				var newv := _weapon_value(e, t, c)
				var oldv := 0.0
				if e.crew[c]["w"] >= 0:
					oldv = _weapon_value(e, e.wtype(e.crew[c]["w"]), c)
				v = newv - oldv
			"drop":
				var t2: String = e.wtype(e.crew[a["c"]]["w"])
				if e.effect_of(t2) in ["grow"]:
					v = 1.0
			"off":
				if e.known.get("fence", "") == "grow":
					v = 5.0
		if v > bv:
			bv = v
			best = i
	return best


func _weapon_value(e: AGTEngine, t: String, c: int) -> float:
	var k := e.effect_of(t)
	var w: Dictionary = D.WEAPONS[t]
	var base := 3.0
	match k:
		"kill5":
			base = 9.0
		"kill4":
			base = 8.0
		"kill3":
			base = 6.5
		"shrink":
			base = 7.0
		"stun5":
			base = 4.0
		"frag":
			base = 0.8
		"grow", "none":
			base = 0.0
	if w["kind"] in ["area", "blast"]:
		base *= 1.4
	if w["range"] == "los":
		base *= 1.2
	if w["kind"] == "fence":
		base *= 0.8
	# i combattenti forti si arrangiano anche a mani nude
	base -= float(e.cdef(c)["att"]) * 0.6
	if e.crew[c]["k"] == "robot":
		base -= 2.0
	return base


func _doom(e: AGTEngine) -> bool:
	var mv := 0.0
	for id in e.mon:
		mv += {"A": 4.0, "B": 2.0, "E": 0.6, "F": 0.8}[e.mon[id]["l"]]
	var cv := 0.0
	for c in e.board_crew():
		cv += float(e.cdef(c)["att"]) + (2.5 if e.crew[c]["w"] >= 0 and e.effect_of(e.wtype(e.crew[c]["w"])) in ["kill5", "kill4", "kill3", "shrink"] else 0.0)
	var humans := 0
	for c in e.board_crew():
		if not (e.crew[c]["k"] in ["robot", "mascot"]):
			humans += 1
	return humans <= 2 or mv > cv * 4.0


func _cmove(e: AGTEngine, req: Dictionary) -> Dictionary:
	if req.get("discovery", false):
		return _discover(e)
	var key := "c%d" % e.turn_no
	if _plan_key != key:
		_plan_key = key
		_stay = {}
	var doom := _doom(e) and e.turn_no > 2
	# azioni speciali
	for c in e.board_crew():
		for s in e.special_actions(c):
			if s["act"] == "escape" and doom:
				var ids := e.crew_at(s["b"]).filter(func(x): return e.awake(x))
				ids.sort_custom(func(x, y): return e.cdef(x)["con"] > e.cdef(y)["con"])
				var take := []
				for x in ids:
					var t2 := take.duplicate()
					t2.append(x)
					if e.boat_room(s["b"], t2):
						take = t2
				if not take.is_empty() and not take.filter(func(x): return not (e.crew[x]["k"] in ["robot", "mascot"])).is_empty():
					return {"act": "escape", "b": s["b"], "ids": take}
			if s["act"] == "sd" and doom:
				return {"act": "sd", "c": c}
			if s["act"] == "fence" and _want_fence(e, c):
				return {"act": "fence", "c": c}
	var order := e.board_crew()
	order.sort()
	for c in order:
		if _stay.has(c) or e.moved.has(c):
			continue
		var paths := e.crew_moves(c)
		if paths.is_empty():
			_stay[c] = true
			continue
		var to := _crew_dest(e, c, paths, doom)
		if to == "" or to == e.crew[c]["loc"]:
			_stay[c] = true
			continue
		return {"c": c, "to": to}
	return {}


func _want_fence(e: AGTEngine, c: int) -> bool:
	var k: String = e.known.get("fence", "")
	if k in ["grow", "none", "frag"]:
		return false
	var a: String = e.crew[c]["loc"]
	if e.hot_for_crew(a):
		return false
	for n in e.adj(a):
		if not e.mons_at(n).is_empty():
			return true
	return false


func _danger(e: AGTEngine, a: String) -> float:
	# dadi d'attacco delle Cose Verdi che possono arrivare qui al prossimo turno
	var d := 0.0
	for id in e.mon:
		var l: String = e.mon[id]["l"]
		if l in ["A", "B"]:
			var dd := e.dist(e.mon[id]["loc"], a)
			if dd <= int(D.MON[l]["mov"]):
				d += float(e.matt(id))
		elif e.mon[id]["loc"] == a:
			d += float(e.matt(id))
	return d


func _crew_dest(e: AGTEngine, c: int, paths: Dictionary, doom: bool) -> String:
	var here: String = e.crew[c]["loc"]
	var k: String = e.crew[c]["k"]
	var w: int = e.crew[c]["w"]
	var t := e.wtype(w) if w >= 0 else ""
	var cands: Array = paths.keys()
	cands.append(here)
	var best := here
	var bv := -9999.0
	for a in cands:
		var v := 0.0
		var dng := _danger(e, a)
		var con := float(e.cdef(c)["con"])
		if doom:
			# verso la scialuppa più vicina ancora disponibile (o il Ponte per l'autodistruzione)
			var dmin := 99
			for b in D.BOATS:
				if not e.launched.has(b):
					dmin = mini(dmin, e.dist(a, b))
			v = -float(dmin) * 3.0
			if k in D.SD_CREW and e.sd_left < 0 and a in D.BRIDGES:
				v += 8.0
			v -= dng * 0.2
		elif k == "mascot":
			v = -dng * 2.0
		elif w < 0 and k != "robot":
			# senza arma: andare a prenderne una
			var wd := 99
			for fw in e.wpn:
				var x: Dictionary = e.wpn[fw]
				if x["out"] or x["c"] != -1 or x["on"] or e.effect_of(x["t"]) in ["grow", "none"]:
					continue
				wd = mini(wd, e.dist(a, x["loc"]))
			v = -float(wd) * 2.0
			if int(e.cdef(c)["att"]) >= 2:
				v += _melee_value(e, a, c) * 0.8
		else:
			var rng_t: String = D.WEAPONS[t]["range"] if t != "" else "same"
			if t == "fence" or k == "robot" or rng_t == "same":
				v = _melee_value(e, a, c) * 1.5 - _approach(e, a) * 1.2
			else:
				# armi a distanza: una posizione da cui colpire senza stare in mezzo ai mostri
				var hit := 0.0
				var tg := [a]
				if rng_t == "adj":
					tg.append_array(e.adj(a))
				else:
					tg = e.los(a)
				for x in tg:
					var n := e.mons_at(x).size()
					if D.WEAPONS[t]["kind"] == "blast" and not e.crew_at(x).is_empty():
						n = 0
					hit = maxf(hit, float(n))
				v = hit * 2.0 - _approach(e, a) * 0.8
				if e.hot_for_crew(a):
					v -= 3.0
		# rischio di essere divorati al prossimo turno delle Cose Verdi
		if k != "robot" and not doom:
			var others := e.crew_at(a).filter(func(x): return x != c).size()
			var risk := p_at_least(int(dng), int(con)) * (0.6 if others > 0 else 1.0)
			v -= risk * (12.0 if int(e.cdef(c)["att"]) <= 1 else 7.0) * (1.4 if level >= 2 else 1.0)
		# un po' di gruppo: insieme si sopravvive
		v += minf(e.crew_at(a).size(), 3) * 0.3
		v += rng.randf() * (1.0 if level == 0 else 0.3)
		if a == here:
			v += 0.2
		if v > bv:
			bv = v
			best = a
	return best


func _melee_value(e: AGTEngine, a: String, c: int) -> float:
	var v := 0.0
	var att := int(e.cdef(c)["att"])
	for id in e.mons_at(a):
		v += p_at_least(att + 2, e.mcon(id)) * (2.0 if e.mon[id]["l"] in ["A", "B"] else 1.2)
	return v


func _approach(e: AGTEngine, a: String) -> float:
	var d := 99
	for id in e.mon:
		d = mini(d, e.dist(a, e.mon[id]["loc"]))
	return float(mini(d, 8))


func _discover(e: AGTEngine) -> Dictionary:
	if e.moved.size() >= 1:
		# un secondo membro solo se raggiunge la stessa area e aiuta davvero
		var first: int = e.moved.keys()[0]
		var a: String = e.crew[first]["loc"]
		var best := -1
		var bv := 0.0
		for c in e.board_crew():
			var p := e.crew_moves(c)
			if p.has(a) and c != e.robot_id():
				var v := float(e.cdef(c)["att"]) - _danger(e, a) * 0.1
				if v > bv:
					bv = v
					best = c
		if best >= 0 and e.mons_at(a).size() > 1:
			return {"c": best, "to": a}
		return {}
	var best_c := -1
	var best_a := ""
	var bv2 := -999.0
	for c in e.board_crew():
		var p := e.crew_moves(c)
		for a in p:
			var v := 0.0
			for id in e.mons_at(a):
				v += p_at_least(int(e.cdef(c)["att"]), e.mcon(id)) * (3.0 if e.mon[id]["l"] in ["A", "B"] else 1.0)
			v -= maxf(0.0, _danger(e, a) * 3.5 - float(e.cdef(c)["con"])) * 0.05
			if e.crew[c]["k"] == "mascot":
				v -= 2.0
			if v > bv2:
				bv2 = v
				best_c = c
				best_a = a
	if best_c < 0:
		return {}
	return {"c": best_c, "to": best_a}


# ---------------------------------------------------------------- attacchi dell'equipaggio

func _good(k: String) -> bool:
	return k in ["kill5", "kill4", "kill3", "shrink"]


func _cattack(e: AGTEngine, req: Dictionary) -> Dictionary:
	var areas: Array = req["areas"]
	for a in areas:
		var atk := _plan_area(e, a)
		if not atk.is_empty():
			return {"area": a, "atk": atk}
	return {}


func _plan_area(e: AGTEngine, a: String) -> Array:
	var cands := e.attackers_for(a)
	var ms := e.mons_at(a)
	var used := {}
	var atk := []
	var kill := {}
	var untried_used := ""
	# 1. armi ad area con effetto buono (o da provare se c'è un solo mostro)
	for cm in cands:
		var c: int = cm[0]
		if not cm[1] or used.has(c):
			continue
		var t := e.wtype(e.crew[c]["w"])
		var kind: String = D.WEAPONS[t]["kind"]
		if not (kind in ["area", "blast"]):
			continue
		var k := e.effect_of(t)
		if kind == "blast":
			var safe := true
			for s in e.section(a):
				for x in e.crew_at(s):
					if t == "grenade" and e.crew[x]["k"] == "robot":
						continue
					if t == "fuel" and e.crew[x]["k"] == "robot":
						continue
					safe = false
			if not safe:
				continue
		if k == "":
			if untried_used != "" or ms.size() > 1 or (ms.size() == 1 and e.mon[ms[0]]["l"] == "E"):
				continue
			untried_used = t
		elif not _good(k) and not (k == "stun5" and _adults(e, a) > 0):
			continue
		used[c] = true
		atk.append([c, true, -1])
		if k.begins_with("kill"):
			for id in ms:
				kill[id] = kill.get(id, 0) + int(k.substr(4))
	# 2. armi a bersaglio singolo e mani nude: si concentrano sui mostri uno alla volta
	var order := ms.duplicate()
	order.sort_custom(func(x, y): return _threat(e, x) > _threat(e, y))
	for id in order:
		var con := e.mcon(id)
		var tries := 0
		while p_at_least(kill.get(id, 0), con) < _thr() + 0.15 and tries < 12:
			tries += 1
			var pickc := -1
			var pickw := false
			var pickd := 0
			var bestv := -1.0
			for cm in cands:
				var c: int = cm[0]
				if used.has(c):
					continue
				var usew: bool = cm[1]
				var dd := 0
				if usew:
					var t := e.wtype(e.crew[c]["w"])
					if D.WEAPONS[t]["kind"] != "single":
						continue
					var k := e.effect_of(t)
					if k == "":
						if untried_used != "" or e.mon[id]["l"] == "E":
							continue
						dd = 3
					elif k.begins_with("kill"):
						dd = int(k.substr(4))
					elif k == "shrink" and e.mon[id]["l"] in ["A", "B"]:
						dd = 6
					elif k == "stun5" and e.mon[id]["l"] == "A":
						dd = 1
					else:
						continue
				else:
					if e.crew[c]["loc"] != a:
						continue
					dd = int(e.cdef(c)["att"])
				var v := float(dd)
				if v > bestv:
					bestv = v
					pickc = c
					pickw = usew
					pickd = dd
			if pickc < 0:
				break
			used[pickc] = true
			atk.append([pickc, pickw, id])
			if pickw and e.effect_of(e.wtype(e.crew[pickc]["w"])) == "":
				untried_used = e.wtype(e.crew[pickc]["w"])
			kill[id] = kill.get(id, 0) + (pickd if (not pickw or e.effect_of(e.wtype(e.crew[pickc]["w"])).begins_with("kill")) else 0)
		if p_at_least(kill.get(id, 0), con) < 0.25 and level > 0:
			# attacco senza speranza: si annulla (tranne le armi da provare)
			atk = atk.filter(func(x): return x[2] != id or (x[1] and e.effect_of(e.wtype(e.crew[x[0]]["w"])) == ""))
			for x in atk:
				pass
			used = {}
			for x in atk:
				used[x[0]] = true
	return atk


func _threat(e: AGTEngine, id: int) -> float:
	return {"A": 4.0, "B": 3.0, "F": 1.0, "E": 1.5}[e.mon[id]["l"]] + (0.0 if e.mon[id]["st"] else 0.5)


func _adults(e: AGTEngine, a: String) -> int:
	var n := 0
	for id in e.mons_at(a):
		if e.mon[id]["l"] == "A":
			n += 1
	return n

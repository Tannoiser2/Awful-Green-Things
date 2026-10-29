class_name OnlineSession
extends Node
## Partita online in lockstep. Ogni decisione del motore (crescita, movimenti, armi, attacchi…)
## diventa una mossa numerata nel database: acts/0, acts/1, …
## Tutti i dispositivi fanno girare lo stesso motore con lo stesso seme e applicano le stesse mosse
## nello stesso ordine, quindi la partita è identica ovunque e sul database viaggiano solo le scelte.
## - la decisione del proprio posto la prende la persona davanti al dispositivo;
## - i posti IA li gioca il dispositivo di chi ha creato la stanza;
## - le altre si aspettano dal database. Se un giocatore tace per un minuto, al suo posto gioca l'IA.

var net: Net
var code := ""
var seat := -1
var role := "guest"
var n := 0                     # prossima mossa da applicare
var backlog: Array = []        # mosse già giocate (rientro in una partita in corso)
var catchup := false
var away := {}
var alive := true
var view                       # vista di gioco: messaggi di attesa e annullamento dei dialoghi
var waiting_seat := -1
var slow := false
var _forced = null
var _mine_pending := false


func setup(p_net: Net, p_code: String, p_seat: int, p_role: String, p_backlog: Array) -> void:
	net = p_net
	code = p_code
	seat = p_seat
	role = p_role
	backlog = p_backlog
	catchup = not backlog.is_empty()


func _exit_tree() -> void:
	alive = false


## Chiamata dal motore al posto della decisione locale.
func decide(eng: AGTEngine, s: int, req: Dictionary):
	if n < backlog.size():
		var a: Dictionary = backlog[n]
		n += 1
		return _val(a)
	if catchup:
		catchup = false
		if view != null:
			view.online_caught_up()
	if s == seat:
		return await _mine(eng, s, req)
	if role == "host":
		if eng.players[s]["ai"]:
			return await _cpu(eng, s, req)
		if away.has(s):
			var st := await net.seat(code, s)
			if not alive:
				return eng.ais[s].decide(eng, s, req)
			if not st.is_empty() and not st.get("away", false):
				away.erase(s)
			else:
				return await _cpu(eng, s, req)
	return await _wait(eng, s, req)


func _val(a: Dictionary):
	return str_to_var(str(a.get("v", "null")))


## Decide la persona davanti a questo dispositivo; intanto si controlla che, durante un'assenza,
## l'IA non abbia già giocato al suo posto.
func _mine(eng: AGTEngine, s: int, req: Dictionary):
	var my_n := n
	_forced = null
	_mine_pending = true
	_watch(eng, my_n)
	eng.decision_requested.emit(req)
	var r = await eng.decision_provided
	_mine_pending = false
	if _forced is Dictionary:
		var a: Dictionary = _forced
		_forced = null
		n = my_n + 1
		return _val(a)
	return await _publish(s, r)


func _watch(eng: AGTEngine, my_n: int) -> void:
	while alive and _mine_pending and n == my_n:
		await get_tree().create_timer(3.0).timeout
		if not alive or not _mine_pending or n != my_n:
			return
		var a := await net.get_act(code, my_n)
		if not alive or not _mine_pending or n != my_n:
			return
		if not a.is_empty() and not a.has("_err"):
			_forced = a
			if view != null:
				view.online_cancel_decision("Eri via: l'IA ha giocato al tuo posto.")
			eng.provide_decision(null)
			return


func _cpu(eng: AGTEngine, s: int, req: Dictionary):
	if eng.ai_delay > 0.0 and not catchup and is_inside_tree():
		await get_tree().create_timer(eng.ai_delay).timeout
	var r = eng.ais[s].decide(eng, s, req)
	return await _publish(s, r)


## Pubblica la decisione e la restituisce. Se la mossa c'è già (l'ha scritta prima un altro
## dispositivo) vale quella.
func _publish(s: int, r):
	var a := {"s": s, "k": "d", "v": var_to_str(r)}
	while alive:
		if await net.post_act(code, n, a):
			n += 1
			return r
		var ex := await net.get_act(code, n)
		if not ex.is_empty() and not ex.has("_err"):
			n += 1
			return _val(ex)
		if view != null:
			view.online_status("Rete non raggiungibile, riprovo… (%s)" % net.last_error)
		await get_tree().create_timer(2.0).timeout
	return r


## Aspetta la decisione di un altro dispositivo. Chi ha creato la stanza controlla anche il segnale
## di presenza: se il giocatore tace da un minuto, gioca l'IA finché non rientra.
func _wait(eng: AGTEngine, s: int, req: Dictionary):
	var my_n := n
	var t0 := Time.get_ticks_msec()
	var last_seen = null
	var seen_t := t0
	var polls := 0
	waiting_seat = s
	slow = false
	if view != null:
		view.online_waiting(s, false)
	while alive:
		var a := await net.get_act(code, my_n)
		if not alive:
			break
		if not a.is_empty() and not a.has("_err"):
			n = my_n + 1
			waiting_seat = -1
			if view != null:
				view.online_waiting(-1, false)
			return _val(a)
		var now := Time.get_ticks_msec()
		if role == "host" and not eng.players[s]["ai"] and polls % 4 == 0:
			var st := await net.seat(code, s)
			if not alive:
				break
			if not st.is_empty():
				var seen = st.get("seen", null)
				if seen != last_seen:
					last_seen = seen
					seen_t = now
				if st.get("away", false) or (now - seen_t > 45000 and now - t0 > 60000):
					await net.set_away(code, s, true)
					away[s] = true
					waiting_seat = -1
					if view != null:
						view.online_waiting(-1, false)
						view.online_status("%s non risponde: per ora gioca l'IA." % eng.pname(s))
					return await _cpu(eng, s, req)
		var sl := now - t0 > 60000
		if sl != slow:
			slow = sl
			if view != null:
				view.online_waiting(s, slow)
		polls += 1
		await get_tree().create_timer(1.2).timeout
	return eng.ais[s].decide(eng, s, req)


## Segnale di presenza ogni 5 secondi (per chi non ha creato la stanza).
func heartbeat_loop() -> void:
	while alive:
		net.heartbeat(code, seat)
		await get_tree().create_timer(5.0).timeout


func finish() -> void:
	if role == "host":
		net.set_status(code, "over")
	net.remember_room("")

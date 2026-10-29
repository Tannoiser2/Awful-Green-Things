extends RefCounted
## Dati del gioco: equipaggio, Cose Verdi, armi, gettoni effetto, tabelle di preparazione.
## Le aree dell'astronave (nomi, collegamenti, linee di vista, punti per le pedine) sono in
## assets/data/aree.json, ricavate dal tabellone con tools/genera_aree.py.

const AREAS_FILE := "res://assets/data/aree.json"

## Equipaggio: att = dadi d'attacco, con = costituzione, mov = movimento, start = aree di partenza.
## «Uno dei Ponti» = bridge1/bridge2; «un Sensore» = sensor1/sensor2; alloggi = i quattro alloggi.
const BRIDGES := ["bridge1", "bridge2"]
const QUARTERS := ["crew_q_nw", "crew_q_ne", "crew_q_se", "crew_q_s"]
const CREW := [
	{"k": "captain", "name": "Capitano Yid", "short": "Capitano", "att": 3, "con": 27, "mov": 3, "start": ["bridge1", "bridge2"], "vip": true},
	{"k": "first_officer", "name": "Primo Ufficiale", "short": "1° Uff.", "att": 2, "con": 19, "mov": 3, "start": ["bridge1", "bridge2"], "vip": true},
	{"k": "comm_officer", "name": "Ufficiale Comunicazioni", "short": "Uff. Com.", "att": 1, "con": 11, "mov": 4, "start": ["bridge1", "bridge2", "computer"]},
	{"k": "ops_officer", "name": "Ufficiale Operativo", "short": "Uff. Op.", "att": 1, "con": 12, "mov": 3, "start": ["life", "officers"]},
	{"k": "eng_officer", "name": "Ufficiale di Macchina", "short": "Uff. Macch.", "att": 1, "con": 12, "mov": 2, "start": ["engine", "pool"], "vip": true},
	{"k": "supply_officer", "name": "Commissario di bordo", "short": "Commiss.", "att": 1, "con": 11, "mov": 2, "start": ["store", "wardroom"]},
	{"k": "doc", "name": "Dottore", "short": "Dottore", "att": 1, "con": 11, "mov": 4, "start": ["sick", "pool"]},
	{"k": "medic", "name": "Infermiere", "short": "Infermiere", "att": 1, "con": 11, "mov": 4, "start": ["sick", "hospital"]},
	{"k": "sparks", "name": "Marconista", "short": "Marconista", "att": 1, "con": 16, "mov": 3, "start": ["bridge1", "bridge2"]},
	{"k": "sarge", "name": "Sergente dei Marine", "short": "Sergente", "att": 3, "con": 21, "mov": 3, "start": ["pool", "mess"]},
	{"k": "marine_g", "name": "Marine (verde)", "short": "Marine V", "att": 2, "con": 19, "mov": 3, "start": ["pool", "sick"]},
	{"k": "marine_b", "name": "Marine (blu)", "short": "Marine B", "att": 2, "con": 18, "mov": 3, "start": ["pool", "sick"]},
	{"k": "cook", "name": "Cuoco", "short": "Cuoco", "att": 1, "con": 21, "mov": 3, "start": ["galley", "wardroom"]},
	{"k": "yeoman", "name": "Furiere", "short": "Furiere", "att": 1, "con": 15, "mov": 3, "start": ["bridge1", "bridge2"]},
	{"k": "technician", "name": "Tecnico", "short": "Tecnico", "att": 1, "con": 11, "mov": 4, "start": ["sensor1", "sensor2"]},
	{"k": "engineer", "name": "Motorista", "short": "Motorista", "att": 2, "con": 13, "mov": 2, "start": ["engine", "mshop", "aft_ms"]},
	{"k": "machinist", "name": "Macchinista", "short": "Macchin.", "att": 2, "con": 14, "mov": 2, "start": ["mshop", "aft_ms"]},
	{"k": "coxswain", "name": "Nostromo", "short": "Nostromo", "att": 2, "con": 18, "mov": 3, "start": ["mess", "sick"]},
	{"k": "pilot_y", "name": "Pilota (giallo)", "short": "Pilota G", "att": 1, "con": 15, "mov": 3, "start": ["crew_q_nw", "crew_q_ne", "crew_q_se", "crew_q_s", "pool"], "vip": true},
	{"k": "pilot_b", "name": "Pilota (blu)", "short": "Pilota B", "att": 1, "con": 12, "mov": 3, "start": ["crew_q_nw", "crew_q_ne", "crew_q_se", "crew_q_s", "pool"], "vip": true},
	{"k": "robot", "name": "Piedipiombo, il Robot", "short": "Robot", "att": 4, "con": 44, "mov": 1, "start": ["mshop", "aft_ms"]},
	{"k": "mascot", "name": "Ook, la Mascotte", "short": "Mascotte", "att": 1, "con": 8, "mov": 4, "start": ["captain"]},
]

## Cose Verdi: A = Adulto, B = Piccolo, E = Uovo, F = Frammento.
const MON := {
	"A": {"name": "Adulto", "plural": "Adulti", "att": 4, "con": 16, "mov": 2, "limit": 12, "img": "adult"},
	"B": {"name": "Piccolo", "plural": "Piccoli", "att": 2, "con": 12, "mov": 1, "limit": 18, "img": "baby"},
	"E": {"name": "Uovo", "plural": "Uova", "att": 0, "con": 5, "mov": 0, "limit": 19, "img": "egg"},
	"F": {"name": "Frammento", "plural": "Frammenti", "att": 1, "con": 8, "mov": 0, "limit": 22, "img": "fragment"},
}
const MON_ORDER := ["A", "B", "F", "E"]

## Popolazione iniziale (tiro di un dado): [uova, piccoli, adulti].
const POPULATION := [[6, 4, 2], [6, 3, 3], [5, 4, 3], [4, 4, 4], [2, 5, 4], [1, 6, 4]]
## Area del primo mostro (tiro di un dado; il 6 lascia scegliere fra queste).
const FIRST_AREA := ["cargo", "science", "scout", "cockboat", "saucer"]

## Armi. range: "same" solo nella stessa area, "adj" stessa area o adiacente, "los" in linea di vista.
## kind: "single" un mostro, "area" tutti i mostri dell'area, "blast" tutta la sezione (si ferma ai
## portelli), "fence" recinto. back: aree dove torna dopo l'uso (armi da lancio a perdere).
const WEAPONS := {
	"acid": {"name": "Bottiglia d'acido", "short": "Acido", "n": 3, "start": {"science": 3}, "range": "adj", "kind": "single", "back": ["science"]},
	"zgwortz": {"name": "Barattolo di Zgwortz", "short": "Zgwortz", "n": 3, "start": {"mess": 2, "galley": 1}, "range": "adj", "kind": "single", "back": ["galley", "mess"]},
	"beamer": {"name": "Raggio comunicatore", "short": "Comunicatore", "n": 2, "start": {"sensor1": 1, "sensor2": 1}, "range": "los", "kind": "area"},
	"fence": {"name": "Recinto elettrico", "short": "Recinto", "n": 2, "start": {"cargo": 2}, "range": "none", "kind": "fence"},
	"extinguisher": {"name": "Estintore", "short": "Estintore", "n": 2, "start": {"mshop": 1, "aft_ms": 1}, "range": "adj", "kind": "area"},
	"grenade": {"name": "Granata a gas", "short": "Granata", "n": 3, "start": {"dc": 3}, "range": "adj", "kind": "blast", "back": ["dc"]},
	"hypo": {"name": "Siringa ipodermica", "short": "Siringa", "n": 2, "start": {"sick": 2}, "range": "same", "kind": "single"},
	"knife": {"name": "Coltello", "short": "Coltello", "n": 3, "start": {"galley": 3}, "range": "los", "kind": "single"},
	"poolstick": {"name": "Stecca da biliardo", "short": "Stecca", "n": 2, "start": {"pool": 2}, "range": "same", "kind": "single"},
	"fuel": {"name": "Tanica di carburante", "short": "Carburante", "n": 3, "start": {"fuel1": 2, "fuel2": 1}, "range": "adj", "kind": "blast", "back": ["fuel1", "fuel2"]},
	"pistol": {"name": "Pistola stordente", "short": "Pistola", "n": 2, "start": {"bridge1": 1, "bridge2": 1}, "range": "los", "kind": "single"},
	"torch": {"name": "Saldatrice", "short": "Saldatrice", "n": 2, "start": {"mshop": 1, "aft_ms": 1}, "range": "same", "kind": "single"},
}
const WEAPON_ORDER := ["acid", "zgwortz", "beamer", "fence", "extinguisher", "grenade", "hypo", "knife", "poolstick", "fuel", "pistol", "torch"]

## Gettoni effetto (15 nella tazza).
const CHITS := {
	"frag": {"name": "1 dado di Frammenti", "n": 4, "img": "chit_fragments"},
	"grow": {"name": "Cresce", "n": 1, "img": "chit_grow"},
	"shrink": {"name": "Rimpicciolisce", "n": 1, "img": "chit_shrink"},
	"stun5": {"name": "5 dadi per stordire", "n": 2, "img": "chit_stun5"},
	"none": {"name": "Nessun effetto", "n": 2, "img": "chit_noeffect"},
	"kill5": {"name": "5 dadi per uccidere", "n": 1, "img": "chit_kill5"},
	"kill4": {"name": "4 dadi per uccidere", "n": 2, "img": "chit_kill4"},
	"kill3": {"name": "3 dadi per uccidere", "n": 2, "img": "chit_kill3"},
}
const CHIT_ORDER := ["kill5", "kill4", "kill3", "shrink", "stun5", "frag", "grow", "none"]

## Scialuppe: hangar e posti (il Robot e la Mascotte non contano; -1 = senza limite).
const BOATS := {
	"scout": {"name": "l'Esploratore", "of": "dell'Esploratore", "cap": 2},
	"saucer": {"name": "il Disco", "of": "del Disco", "cap": 4},
	"cockboat": {"name": "la Lancia", "of": "della Lancia", "cap": -1},
}
## Chi può avviare l'autodistruzione (da uno dei Ponti).
const SD_CREW := ["captain", "first_officer", "eng_officer", "pilot_y", "pilot_b"]

const VP_TAKEOVER := 111.0
const VP_SELFDESTRUCT := 55.5

static var _areas := {}
static var _area_list := []


static func areas() -> Dictionary:
	if _areas.is_empty():
		var f := FileAccess.open(AREAS_FILE, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text())
		for a in d["areas"]:
			_areas[a["id"]] = a
			_area_list.append(a["id"])
	return _areas


static func area_list() -> Array:
	areas()
	return _area_list


static func crew_def(k: String) -> Dictionary:
	for c in CREW:
		if c["k"] == k:
			return c
	return {}

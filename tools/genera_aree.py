#!/usr/bin/env python3
"""Ricava dal tabellone i dati delle aree dell'astronave Znutar (assets/data/aree.json) e
l'immagine del tabellone usata nel gioco (assets/board/nave.webp).

Ingressi (cartella di lavoro, non nel repository):
  board.png  scansione del tabellone dal modulo TTS (3444x1644)
  wsf3.npy   mappa delle aree (0 = parete, 1..45 = area) ottenuta per segmentazione
             delle pareti gialle e watershed (vedi note nel README)
  los.json   linee di vista calcolate tirando raggi dritti sulla mappa (los.py)
Uso: python3 tools/genera_aree.py <cartella di lavoro> <cartella del progetto>
"""
import sys, json, cv2, numpy as np

work, proj = sys.argv[1], sys.argv[2]
X0, SCALE = 860, 0.75          # ritaglio: dalla colonna 860 in poi, ridotto al 75%

# ordine delle aree nella mappa wsf.npy (indice + 1)
IDS = ["crew_q_nw", "captain", "bridge1", "computer", "officers", "wardroom", "galley", "sensor1", "cargo",
       "c_n1", "c_n2", "store", "bridge2", "crew_q_ne", "pool", "fuel1", "engine", "mess", "science", "aft_ms",
       "c_ne_a", "c_ne_b", "c_ne_c", "probe_ctrl", "life", "mshop", "dc", "probe_launch", "saucer", "sick",
       "hospital", "crew_q_se", "crew_q_s", "sensor2", "scout", "cockboat", "fuel2", "c_se1", "c_se2", "c_s",
       "c_m1", "c_m2", "c_m3", "c_m4", "c_m5"]

NAMES = {
    "crew_q_nw": "Alloggi equipaggio A", "captain": "Cabina del Capitano", "bridge1": "Ponte n. 1",
    "computer": "Sala computer", "officers": "Alloggi ufficiali", "wardroom": "Quadrato ufficiali",
    "galley": "Cucina", "sensor1": "Sensore n. 1", "cargo": "Stiva principale", "c_n1": "Corridoio N1",
    "c_n2": "Corridoio N2", "store": "Spaccio di bordo", "bridge2": "Ponte n. 2",
    "crew_q_ne": "Alloggi equipaggio B", "pool": "Sala biliardo", "fuel1": "Serbatoio n. 1",
    "engine": "Sala macchine", "mess": "Mensa", "science": "Laboratorio scientifico",
    "aft_ms": "Officina di poppa", "c_ne_a": "Corridoio E1", "c_ne_b": "Corridoio E3", "c_ne_c": "Corridoio E2",
    "probe_ctrl": "Controllo sonde", "life": "Supporto vitale", "mshop": "Officina",
    "dc": "Controllo danni", "probe_launch": "Lancio sonde", "saucer": "Hangar del Disco",
    "sick": "Infermeria", "hospital": "Corsia ospedaliera", "crew_q_se": "Alloggi equipaggio C",
    "crew_q_s": "Alloggi equipaggio D", "sensor2": "Sensore n. 2", "scout": "Hangar dell'Esploratore",
    "cockboat": "Hangar della Lancia", "fuel2": "Serbatoio n. 2", "c_se1": "Corridoio S2",
    "c_se2": "Corridoio S3", "c_s": "Corridoio S1", "c_m1": "Corridoio C1", "c_m2": "Corridoio C2",
    "c_m3": "Corridoio C3", "c_m4": "Corridoio C4", "c_m5": "Corridoio C5",
}

# porte (portelli) e passaggi aperti fra le aree, verificati sul tabellone
PAIRS = """crew_q_se sensor2|crew_q_se c_se1|scout cockboat|crew_q_s c_se2|c_m1 c_m2|c_m4 c_m5|c_ne_b c_ne_c|
c_ne_a c_ne_c|c_se1 c_se2|c_m2 c_m3|crew_q_nw c_m1|crew_q_se scout|c_s c_m4|saucer cockboat|officers c_m2|
sensor1 c_m1|dc c_m3|probe_ctrl c_m1|mshop c_m2|cargo store|galley mess|engine aft_ms|mess c_m4|science c_m5|
c_m3 c_m4|sick c_m4|sick c_s|mshop dc|cockboat c_s|galley cargo|store mess|wardroom c_n2|aft_ms c_se1|dc saucer|
cargo c_n1|bridge1 c_n1|galley c_n2|sick hospital|bridge2 mess|mshop saucer|bridge2 c_ne_a|c_n2 c_m3|
crew_q_ne c_ne_a|mshop probe_launch|bridge1 officers|fuel1 c_ne_b|captain bridge1|fuel2 c_se2|pool c_ne_b|
engine c_ne_b|engine c_se2|c_ne_c c_m5|c_se1 c_m5|life mshop|captain computer|probe_ctrl probe_launch|c_n1 c_n2"""

# passaggi aperti (linee sottili) fra tratti di corridoio: tutte le altre coppie di PAIRS sono portelli.
# Una nube di gas o un'esplosione si ferma solo ai portelli, quindi riempie l'intera «sezione»
# di corridoi collegati da passaggi aperti; anche la linea di vista prosegue solo attraverso di essi.
OPEN = [("c_m1", "c_m2"), ("c_m2", "c_m3"), ("c_n1", "c_n2"), ("c_n2", "c_m3"), ("c_m4", "c_m5"),
        ("c_s", "c_m4"), ("c_ne_a", "c_ne_c"), ("c_ne_b", "c_ne_c"), ("c_se1", "c_se2")]

KIND = {}
for k in IDS:
    KIND[k] = "corridoio" if k.startswith("c_") else "stanza"
for k in ("saucer", "scout", "cockboat"):
    KIND[k] = "hangar"

ws = np.load(work + "/wsf3.npy").astype(np.int32)
los = json.load(open(work + "/los.json"))
adj = {k: [] for k in IDS}
for p in PAIRS.replace("\n", "").split("|"):
    a, b = p.split()
    adj[a].append(b)
    adj[b].append(a)

areas = []
for i, k in enumerate(IDS):
    m = (ws == i + 1).astype(np.uint8)
    cs, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    c = max(cs, key=cv2.contourArea)
    c = cv2.approxPolyDP(c, 3.0, True)
    poly = [[round((p[0][0] - X0) * SCALE, 1), round(p[0][1] * SCALE, 1)] for p in c]
    # punti per le pedine: griglia dentro l'area, lontano dai bordi, ordinati dal centro
    dist = cv2.distanceTransform(m, cv2.DIST_L2, 5)
    cy, cx = np.unravel_index(np.argmax(dist), dist.shape)
    step = 84
    pts = []
    for y in range(int(cy) % step, m.shape[0], step):
        for x in range(int(cx) % step, m.shape[1], step):
            if dist[y, x] >= 38:
                pts.append((x, y))
    if len(pts) < 6:   # area stretta: griglia più fitta
        step = 62
        pts = [(x, y) for y in range(int(cy) % step, m.shape[0], step)
               for x in range(int(cx) % step, m.shape[1], step) if dist[y, x] >= 28]
    pts.sort(key=lambda p: (p[0] - cx) ** 2 + (p[1] - cy) ** 2)
    slots = [[round((x - X0) * SCALE, 1), round(y * SCALE, 1)] for x, y in pts[:24]]
    # griglia fitta per le aree affollate (pedine più piccole)
    st2 = 52
    pts2 = [(x, y) for y in range(int(cy) % st2, m.shape[0], st2)
            for x in range(int(cx) % st2, m.shape[1], st2) if dist[y, x] >= 24]
    pts2.sort(key=lambda p: (p[0] - cx) ** 2 + (p[1] - cy) ** 2)
    dense = [[round((x - X0) * SCALE, 1), round(y * SCALE, 1)] for x, y in pts2[:60]]
    if not slots:
        slots = [[round((cx - X0) * SCALE, 1), round(cy * SCALE, 1)]]
    areas.append({"id": k, "name": NAMES[k], "kind": KIND[k],
                  "center": [round((cx - X0) * SCALE, 1), round(cy * SCALE, 1)],
                  "poly": poly, "slots": slots, "dense": dense, "adj": sorted(adj[k]),
                  "los": sorted(set(los[k]) | set(adj[k])),
                  "open": sorted([b for a, b in OPEN if a == k] + [a for a, b in OPEN if b == k])})

json.dump({"areas": areas, "scale": SCALE, "x0": X0},
          open(proj + "/assets/data/aree.json", "w"), ensure_ascii=False, separators=(",", ":"))

im = cv2.imread(work + "/board.png")[:, X0:]
im = cv2.resize(im, (int(im.shape[1] * SCALE), int(im.shape[0] * SCALE)), interpolation=cv2.INTER_AREA)
cv2.imwrite(proj + "/assets/board/nave.webp", im, [cv2.IMWRITE_WEBP_QUALITY, 88])
print("aree:", len(areas), "immagine:", im.shape)
for a in areas:
    print(a["id"], len(a["slots"]), len(a["poly"]))

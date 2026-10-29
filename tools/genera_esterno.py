#!/usr/bin/env python3
"""Aree esterne della Znutar per le regole «Fuori dalla Znutar» (assets/data/esterno.json).

Lo scafo (skin) è diviso in una fascia attorno alla nave: ogni stanza sul perimetro ha il suo tratto di
scafo; i due Serbatoi ne hanno due ciascuno, divisi dal confine fra le zone di spazio. Oltre lo scafo ci
sono le quattro zone di spazio: sopra, a prua (fra il Ponte n. 1 e l'Hangar del Disco, esclusi), sotto e
a poppa (fra i due Serbatoi).

Ingressi: wsf3.npy della cartella di lavoro (la stessa mappa delle aree di genera_aree.py).
Uso: python3 tools/genera_esterno.py <cartella di lavoro> <cartella del progetto>
"""
import sys, json, math, cv2, numpy as np
from scipy import ndimage

work, proj = sys.argv[1], sys.argv[2]
X0, SCALE, PAD = 860, 0.75, 420
BAND, RING, GAP = 110, 230, 30   # spessore dello scafo e della fascia di spazio, distacco dalla parete (pixel della scansione)

IDS = ["crew_q_nw", "captain", "bridge1", "computer", "officers", "wardroom", "galley", "sensor1", "cargo",
       "c_n1", "c_n2", "store", "bridge2", "crew_q_ne", "pool", "fuel1", "engine", "mess", "science", "aft_ms",
       "c_ne_a", "c_ne_b", "c_ne_c", "probe_ctrl", "life", "mshop", "dc", "probe_launch", "saucer", "sick",
       "hospital", "crew_q_se", "crew_q_s", "sensor2", "scout", "cockboat", "fuel2", "c_se1", "c_se2", "c_s",
       "c_m1", "c_m2", "c_m3", "c_m4", "c_m5"]
ROOM_NAMES = json.load(open(proj + "/assets/data/aree.json"))["areas"]
ROOM_NAMES = {a["id"]: a["name"] for a in ROOM_NAMES}

# zone di spazio per le stanze del perimetro (i Serbatoi si dividono)
SECTOR = {"pool": "sp_top", "crew_q_ne": "sp_top", "bridge2": "sp_top", "cargo": "sp_top", "bridge1": "sp_top",
          "captain": "sp_bow", "crew_q_nw": "sp_bow", "sensor1": "sp_bow", "probe_ctrl": "sp_bow",
          "probe_launch": "sp_bow", "saucer": "sp_under", "cockboat": "sp_under", "scout": "sp_under",
          "sensor2": "sp_under", "crew_q_s": "sp_under", "engine": "sp_stern"}
SPACE = {"sp_top": "Spazio sopra la nave", "sp_bow": "Spazio a prua", "sp_under": "Spazio sotto la nave",
         "sp_stern": "Spazio a poppa"}
SPACE_ADJ = [("sp_top", "sp_bow"), ("sp_bow", "sp_under"), ("sp_under", "sp_stern"), ("sp_stern", "sp_top")]
# portelli verso l'esterno (camere stagne)
AIRLOCKS = ["cargo", "scout", "saucer", "cockboat", "sensor1", "sensor2", "probe_launch", "engine"]

ws = np.pad(np.load(work + "/wsf3.npy").astype(np.int32), PAD)
m = (ws > 0).astype(np.uint8)
hull = cv2.morphologyEx(m, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (41, 41)))
hull = ndimage.binary_fill_holes(hull).astype(np.uint8)
d_out = cv2.distanceTransform((1 - hull).astype(np.uint8), cv2.DIST_L2, 5)
band = ((d_out > GAP) & (d_out <= GAP + BAND)).astype(np.uint8)
ring = ((d_out > GAP + BAND + 6) & (d_out <= GAP + BAND + RING)).astype(np.uint8)

rooms = np.zeros_like(ws)
for i, k in enumerate(IDS):
    if not k.startswith("c_"):
        rooms[ws == i + 1] = i + 1
_, ind = ndimage.distance_transform_edt(rooms == 0, return_indices=True)
near = rooms[ind[0], ind[1]]

# etichette dello scafo
skin = {}
H, W = ws.shape
yy, xx = np.mgrid[0:H, 0:W]
for v in np.unique(near[band > 0]):
    k = IDS[v - 1]
    mk = (band > 0) & (near == v)
    if k in ("fuel1", "fuel2"):
        r = (ws == v)
        cy, cx = ndimage.center_of_mass(r)
        ang = np.degrees(np.arctan2(-(yy - cy), xx - cx))
        if k == "fuel1":
            top = (ang > 45) | (ang < -135)
            skin["s_fuel1_top"] = (mk & top, k, "sp_top")
            skin["s_fuel1_stern"] = (mk & ~top, k, "sp_stern")
        else:
            under = (ang < -45) | (ang > 135)
            skin["s_fuel2_under"] = (mk & under, k, "sp_under")
            skin["s_fuel2_stern"] = (mk & ~under, k, "sp_stern")
    else:
        skin["s_" + k] = (mk, k, SECTOR[k])

# zone di spazio: il pixel più vicino dello scafo decide la zona
sec_map = np.zeros_like(ws)
SEC_IDS = list(SPACE)
for sid, (mk, room, sec) in skin.items():
    sec_map[mk] = SEC_IDS.index(sec) + 1
_, ind2 = ndimage.distance_transform_edt(sec_map == 0, return_indices=True)
sec_ring = sec_map[ind2[0], ind2[1]] * ring


def to_game(x, y):
    return [round((x - PAD - X0) * SCALE, 1), round((y - PAD) * SCALE, 1)]


def geom(mask, step=84, mind=34):
    mk = mask.astype(np.uint8)
    mk = cv2.morphologyEx(mk, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9)))
    cs, _ = cv2.findContours(mk, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    c = max(cs, key=cv2.contourArea)
    c = cv2.approxPolyDP(c, 4.0, True)
    poly = [to_game(p[0][0], p[0][1]) for p in c]
    dist = cv2.distanceTransform(mk, cv2.DIST_L2, 5)
    cy, cx = np.unravel_index(np.argmax(dist), dist.shape)
    pts = [(x, y) for y in range(int(cy) % step, H, step) for x in range(int(cx) % step, W, step)
           if dist[y, x] >= mind]
    pts.sort(key=lambda p: (p[0] - cx) ** 2 + (p[1] - cy) ** 2)
    slots = [to_game(x, y) for x, y in pts[:24]] or [to_game(cx, cy)]
    st2 = 52
    pts2 = [(x, y) for y in range(int(cy) % st2, H, st2) for x in range(int(cx) % st2, W, st2)
            if dist[y, x] >= 24]
    pts2.sort(key=lambda p: (p[0] - cx) ** 2 + (p[1] - cy) ** 2)
    return poly, to_game(cx, cy), slots, [to_game(x, y) for x, y in pts2[:60]]


# adiacenze lungo lo scafo: due tratti si toccano se, allargati un poco, si sovrappongono
kern = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9))
dil = {sid: cv2.dilate(v[0].astype(np.uint8), kern) for sid, v in skin.items()}
walk = {sid: [] for sid in skin}
ids = sorted(skin)
for i, a in enumerate(ids):
    for b in ids[i + 1:]:
        if (dil[a] & skin[b][0]).sum() > 30:
            walk[a].append(b)
            walk[b].append(a)

areas = []
for sid in ids:
    mk, room, sec = skin[sid]
    poly, center, slots, dense = geom(mk, 62, 26)
    same_sec = [o for o in ids if skin[o][2] == sec and o != sid]
    nm = "Scafo: " + ROOM_NAMES[room]
    if sid.endswith("_top"):
        nm += " (sopra)"
    elif sid.endswith("_stern"):
        nm += " (poppa)"
    elif sid.endswith("_under"):
        nm += " (sotto)"
    areas.append({"id": sid, "name": nm, "kind": "scafo", "room": room, "space": sec,
                  "airlock": room if room in AIRLOCKS else "", "center": center, "poly": poly, "slots": slots,
                  "dense": dense, "adj": sorted(walk[sid]), "fly": [sec] + sorted(walk[sid]),
                  "los": sorted(set(same_sec) | set(walk[sid])), "open": []})
for i, sec in enumerate(SEC_IDS):
    mk = sec_ring == i + 1
    poly, center, slots, dense = geom(mk)
    nadj = sorted([b for a, b in SPACE_ADJ if a == sec] + [a for a, b in SPACE_ADJ if b == sec])
    mine = [o for o in ids if skin[o][2] == sec]
    areas.append({"id": sec, "name": SPACE[sec], "kind": "spazio", "room": "", "space": sec, "airlock": "",
                  "center": center, "poly": poly, "slots": slots, "dense": dense, "adj": nadj,
                  "fly": nadj + mine, "los": sorted(nadj + mine), "open": []})

json.dump({"areas": areas, "airlocks": AIRLOCKS}, open(proj + "/assets/data/esterno.json", "w"),
          ensure_ascii=False, separators=(",", ":"))
for a in areas:
    print(a["id"], a["space"], len(a["slots"]), a["adj"])

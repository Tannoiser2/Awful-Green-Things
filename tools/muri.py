#!/usr/bin/env python3
"""Aree separate solo da una parete (senza portello), per lo Slimer di «Revenge of the Awful Green Things»
che scioglie i muri: assets/data/muri.json = [[a, b], ...].
Uso: python3 tools/muri.py <cartella di lavoro> <cartella del progetto>
"""
import sys, json, cv2, numpy as np

work, proj = sys.argv[1], sys.argv[2]
IDS = ["crew_q_nw", "captain", "bridge1", "computer", "officers", "wardroom", "galley", "sensor1", "cargo",
       "c_n1", "c_n2", "store", "bridge2", "crew_q_ne", "pool", "fuel1", "engine", "mess", "science", "aft_ms",
       "c_ne_a", "c_ne_b", "c_ne_c", "probe_ctrl", "life", "mshop", "dc", "probe_launch", "saucer", "sick",
       "hospital", "crew_q_se", "crew_q_s", "sensor2", "scout", "cockboat", "fuel2", "c_se1", "c_se2", "c_s",
       "c_m1", "c_m2", "c_m3", "c_m4", "c_m5"]
ws = np.load(work + "/wsf3.npy").astype(np.int32)
areas = {a["id"]: a for a in json.load(open(proj + "/assets/data/aree.json"))["areas"]}
k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (61, 61))
dil = {i: cv2.dilate((ws == i + 1).astype(np.uint8), k) for i in range(len(IDS))}
out = []
for i, a in enumerate(IDS):
    for j in range(i + 1, len(IDS)):
        b = IDS[j]
        if b in areas[a]["adj"] or (a, b) in [("fuel1", "c_ne_b"), ("fuel2", "c_se2")]:
            continue
        touch = int((dil[i] & (ws == j + 1)).sum())
        if touch > 400:   # un tratto di parete in comune lungo almeno qualche centimetro
            out.append([a, b])
json.dump(out, open(proj + "/assets/data/muri.json", "w"), separators=(",", ":"))
print(len(out), out)

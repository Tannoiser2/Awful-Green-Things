#!/usr/bin/env python3
"""Converte le miniature STL (Awful_green_things.rar, stampa 3D) in modelli .glb colorati per la vista 3D.
Ogni modello ha due parti: la basetta (colore della pedina di cartone: crema per l'equipaggio, giallo per
le Cose Verdi, blu per le armi) e la figura (colore della razza, verde mostro, colore dell'arma).
Le mesh vengono semplificate per la versione web. Asse verticale Y, unità in metri come Godot (1 mm = 0.001).
Uso: python3 tools/miniature.py <cartella degli STL> <assets/minis> [solo questi modelli...]
"""
import sys, os, numpy as np, trimesh
from trimesh.visual.material import PBRMaterial

src, out = sys.argv[1], sys.argv[2]
ONLY = sys.argv[3:]
YEL, BLU, RED, GRN = "#f2c21b", "#2f7fd1", "#d8342a", "#3f9b3a"
CREW = {
    "captain": ("Captain Yid", YEL), "first_officer": ("1st Officer", BLU), "comm_officer": ("Comm Officer", RED),
    "ops_officer": ("Ops Officer", GRN), "eng_officer": ("Engineer Officer", RED), "supply_officer": ("Supply Officer", RED),
    "doc": ("Doc", RED), "medic": ("Medic", RED), "sparks": ("Sparks", BLU), "sarge": ("Sarge", GRN),
    "marine_g": ("Marine", GRN), "marine_b": ("Marine blue", BLU), "cook": ("Cook", YEL), "yeoman": ("Yeoman", GRN),
    "technician": ("Tech", RED), "engineer": ("Engineer", RED), "machinist": ("Machinist", RED),
    "coxswain": ("Coxswain", YEL), "pilot_y": ("Pilot", YEL), "pilot_b": ("Pilot blue", BLU),
    "robot": ("Robot", "#9aa3ad"), "mascot": ("Mascot", "#3b6fc4"),
}
WEAP = {
    "acid": ("Bottle of Acid", "#4fd16a"), "zgwortz": ("Cannister of Zgwortz", "#e8352b"), "beamer": ("Comm Beamer", "#b8bcc4"),
    "fence": ("Electric Fence", "#f5e43a"), "extinguisher": ("Fire Extinguisher1", "#e8352b"), "grenade": ("Gas Grenade", "#8d939b"),
    "hypo": ("Hypodermic", "#f2f2f2"), "knife": ("Knife", "#d9dde3"), "poolstick": ("Pool Stick", "#a8682d"),
    "fuel": ("Can of Rocket Fuel", "#e0402a"), "pistol": ("Stun Pistol", "#f08a2a"), "torch": ("Welding Torch", "#c9ccd2"),
}
MON = {"adult": ("Adult", 8, "#5cc23a"), "baby": ("Baby", 8, "#7fd34a"), "egg": ("Egg", 6, "#3f9a2f"), "fragment": ("Fragments", 3, "#6cc43c")}


def mat(col, rough=0.6):
    c = trimesh.visual.color.hex_to_rgba(col) / 255.0
    c[:3] = c[:3] ** 2.2          # glTF vuole i colori lineari
    return PBRMaterial(baseColorFactor=list(c), metallicFactor=0.0, roughnessFactor=rough)


def convert(stl, dest, fig_col, base_col, faces):
    if ONLY and dest not in ONLY:
        return 0
    m = trimesh.load(os.path.join(src, stl + ".stl"))
    if len(m.faces) > faces:
        m = m.simplify_quadric_decimation(face_count=faces)
    b = m.bounds
    m.apply_translation([-(b[0][0] + b[1][0]) / 2, -(b[0][1] + b[1][1]) / 2, -b[0][2]])
    # la basetta: le facce entro lo spessore della lastra sul fondo (circa 2 mm)
    z = m.vertices[:, 2]
    top = 2.05
    up = (m.face_normals[:, 2] > 0.95) & (m.triangles_center[:, 2] > 0.5) & (m.triangles_center[:, 2] < 4.0)
    if up.any():
        # il piano della basetta: la quota con più superficie rivolta verso l'alto
        lv = {}
        for zc, ar in zip(np.round(m.triangles_center[up, 2], 1), m.area_faces[up]):
            lv[zc] = lv.get(zc, 0.0) + ar
        top = float(max(lv, key=lv.get)) + 0.05
    fz = z[m.faces].max(axis=1)
    base_mask = fz <= top
    parts = []
    for mask, col, name in [(base_mask, base_col, "basetta"), (~base_mask, fig_col, "figura")]:
        if mask.sum() == 0:
            continue
        sub = m.submesh([np.where(mask)[0]], append=True)
        sub.apply_scale(0.001)
        sub.apply_transform(trimesh.transformations.rotation_matrix(-np.pi / 2, [1, 0, 0]))
        sub.visual = trimesh.visual.TextureVisuals(material=mat(col, 0.75 if name == "basetta" else 0.5))
        parts.append((name, sub))
    sc = trimesh.Scene()
    for name, p in parts:
        sc.add_geometry(p, node_name=name, geom_name=name)
    with open(os.path.join(out, dest + ".glb"), "wb") as f:
        f.write(trimesh.exchange.gltf.export_glb(sc, include_normals=True))
    return len(m.faces)


tot = 0
for k, (f, col) in CREW.items():
    tot += convert(f, "crew_" + k, col, "#f4ecd0", 7000)
for k, (f, col) in WEAP.items():
    tot += convert(f, "w_" + k, col, "#1b5f8a", 1800)
for k, (f, n, col) in MON.items():
    for i in range(1, n + 1):
        tot += convert("%s%d" % (f, i), "%s_%d" % (k, i), col, "#ffd923", 3500)
# l'astronave sul suo supporto e le tre scialuppe (decorazione e fuga)
tot += convert("Znutar", "znutar", "#b8bdc6", "#2a2a2a", 12000)
tot += convert("Znutar Base", "znutar_base", "#2a2a2a", "#2a2a2a", 2000)
for k, f in [("saucer", "Saucer"), ("scout", "Scout"), ("cockboat", "Cockboat")]:
    tot += convert(f, "boat_" + k, "#aab0b9", "#aab0b9", 8000)
# «Fuori dalla Znutar»: tuta a reazione, carrello elevatore e la tuta della Mascotte
for k, f, col in [("jet", "Jet Suit", "#9cc3e6"), ("mover", "Cargo Mover", "#e8c23a"), ("soot", "Ook Suit", "#6f8fd8")]:
    tot += convert(f, "g_" + k, col, "#f4ecd0", 5000)
print("facce totali", tot)

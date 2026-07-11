#!/usr/bin/env python3
"""Convertit des morceaux au format **iReal Pro** (URL irealb://) vers le format
JSON de Rubato (grilles d'accords), et les branche au catalogue.

L'algorithme de dé-brouillage (blocs de 50 caractères, _obfusc50) et le
nettoyage des mesures sont repris de pyRealParser (drs251/pyRealParser, MIT).
Ici on préserve en plus les **sections** (repères *A/*B…) et la **signature
rythmique**, pour coller au modèle de Rubato.

Le contenu iReal Pro est purement harmonique (accords, aucune parole/mélodie).

Usage :
    python3 scripts/import_irealpro.py <fichier.txt>        # depuis un fichier
    pbpaste | python3 scripts/import_irealpro.py -          # depuis stdin
    python3 scripts/import_irealpro.py in.txt --dry-run     # aperçu sans écrire
    python3 scripts/import_irealpro.py in.txt --tags jazz,standard

Par défaut : écrit assets/charts/<id>.json et fusionne les entrées dans
assets/catalog.json (les autres représentations d'un morceau existant — paroles,
mélodie — sont conservées).
"""
import argparse
import json
import os
import re
import sys
import urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

PREFIX = "1r34LbKcu7"
CHORD_RE = re.compile(r'(?<!/)([A-GNn][^A-GN/]*(?:/[A-GN][#b]?)?)')

SECTION_LABELS = {'i': 'Intro', 'v': 'Verse', 'V': 'Verse'}


# ── Dé-brouillage (repris de pyRealParser, MIT) ─────────────────────────────
def _obfusc50(block):
    """Dé-brouille un bloc de 50 caractères par substitution."""
    r = list(block)
    for i in range(5):
        r[i] = block[49 - i]
        r[49 - i] = block[i]
    for i in range(10, 24):
        r[i] = block[49 - i]
        r[49 - i] = block[i]
    return ''.join(r)


def unscramble(s):
    out = ""
    while len(s) > 50:
        chunk = s[:50]
        s = s[50:]
        out += chunk if len(s) < 2 else _obfusc50(chunk)
    return out + s


# ── Nettoyage de la grille (adapté de pyRealParser) ─────────────────────────
def _cleanup(s):
    s = re.sub(r'LZ|K', '|', s)
    s = re.sub(r'cl', 'x', s)
    s = re.sub(r'\*\s*\*', '', s)
    s = re.sub(r'Y+', '', s)
    s = re.sub(r'XyQ|,', ' ', s)
    s = re.sub(r'\|\s*\|', '|', s)
    s = re.sub(r'Z', '|', s)
    s = re.sub(r'\s+', ' ', s)
    return s.strip()


def _strip_annotations(s):
    """Retire commentaires, accords alternatifs, marqueurs cosmétiques.
    Conserve les sections (*X) et la signature (Txy) — traitées ensuite."""
    s = re.sub(r'[\[\]]', '|', s)
    s = re.sub(r'<.*?>', '', s)          # commentaires
    s = re.sub(r'\([^)]*\)', '', s)      # accords alternatifs
    s = re.sub(r'f', '', s)              # point d'orgue
    s = re.sub(r'(?<!a)l(?!t)', '', s)   # taille 'l' (préserve 'alt')
    s = re.sub(r'(?<!su)s(?!us)', '', s) # taille 's' (préserve 'sus')
    s = re.sub(r'U|S|Q|N\d', '', s)      # navigation (coda, segno, fins)
    s = re.sub(r'\|\s*\|', '|', s)
    return s


def _fill_repeats(measures):
    """Remplace les répétitions 1 mesure (x) et 2 mesures (r)."""
    for i in range(1, len(measures)):
        if measures[i] == 'x':
            measures[i] = measures[i - 1]
    i = 2
    while i < len(measures):
        if measures[i] == 'r':
            measures[i:i + 1] = [measures[i - 2], measures[i - 1]]
            i += 1
        i += 1
    return measures


def _chords_of(measure):
    """Liste des accords d'une mesure, slashes (p) retirés, n → N.C."""
    measure = measure.replace('p', '')  # slashes : rien de neuf à afficher
    chords = []
    for tok in CHORD_RE.findall(measure):
        chords.append('N.C.' if tok in ('n', 'nn') else tok)
    return chords


def _measures(content):
    raw = [m.replace(' ', '') for m in re.split(r'[|{}]', content) if m.strip()]
    raw = _fill_repeats(raw)
    bars = []
    for m in raw:
        chords = _chords_of(m)
        if chords:
            bars.append({"chords": chords})
    return bars


def _section_label(marker):
    return SECTION_LABELS.get(marker, marker.upper())


# ── Découpage titre / méta ──────────────────────────────────────────────────
def parse_song(tune_string):
    parts = re.split(r"=+", tune_string)
    if len(parts) < 5:
        raise ValueError("champs insuffisants")
    title, composer, _style, key = parts[0], parts[1], parts[2], parts[3]
    offset = 0 if PREFIX in parts[4] else 1
    music_field = parts[4 + offset]
    if PREFIX not in music_field:
        raise ValueError("préfixe de grille introuvable (format irealbook non géré)")
    scrambled = music_field.split(PREFIX, 1)[1]

    music = _strip_annotations(_cleanup(unscramble(scrambled)))

    # Signature rythmique : premier Txy.
    tsig = re.search(r'T(\d)(\d)', music)
    time = f"{int(tsig.group(1))}/{int(tsig.group(2))}" if tsig else None
    music = re.sub(r'T\d+', '', music)

    # Sections : découpe sur les marqueurs *X.
    chunks = re.split(r'\*(\w)', music)
    raw_sections = []
    if chunks[0].strip(' |'):
        raw_sections.append((None, chunks[0]))
    for i in range(1, len(chunks), 2):
        label = _section_label(chunks[i])
        content = chunks[i + 1] if i + 1 < len(chunks) else ''
        raw_sections.append((label, content))

    sections = []
    for label, content in raw_sections:
        bars = _measures(content)
        if bars:
            sections.append({"label": label, "bars": bars})

    if not sections:
        raise ValueError("aucune mesure exploitable")

    # Tonalité : iReal note le mineur avec '-' → 'm' pour l'affichage.
    if key.endswith('-'):
        key = key[:-1] + 'm'

    return {
        "title": title.strip(),
        "artist": composer.strip() or None,
        "key": key or None,
        "time": time,
        "sections": sections,
    }


def parse_playlist(text):
    m = re.search(r'irealb(?:ook)?://(.+)', text, re.DOTALL)
    if not m:
        raise SystemExit("Chaîne iReal Pro introuvable (attendu 'irealb://…').")
    body = urllib.parse.unquote(m.group(1)).strip()
    songs, errors = [], []
    for chunk in body.split('==='):
        if not chunk.strip():
            continue
        try:
            songs.append(parse_song(chunk))
        except Exception as e:
            # Le dernier segment est souvent le nom de la playlist → ignoré.
            errors.append((chunk[:40], str(e)))
    return songs, errors


# ── Sortie ──────────────────────────────────────────────────────────────────
def slugify(title, taken):
    base = re.sub(r'[^a-z0-9]+', '-', title.lower()).strip('-') or 'morceau'
    sid, n = base, 2
    while sid in taken:
        sid = f"{base}-{n}"
        n += 1
    taken.add(sid)
    return sid


def upsert_catalog(catalog, entry):
    for i, s in enumerate(catalog["songs"]):
        if s["id"] == entry["id"]:
            others = [r for r in s.get("representations", [])
                      if r.get("type") != "chordGrid"]
            entry["representations"] = entry["representations"] + others
            catalog["songs"][i] = entry
            return
    catalog["songs"].append(entry)


def main():
    ap = argparse.ArgumentParser(description="iReal Pro → JSON Rubato")
    ap.add_argument("input", help="fichier contenant la chaîne iReal (ou '-' pour stdin)")
    ap.add_argument("--charts-dir", default=os.path.join(ROOT, "assets", "charts"))
    ap.add_argument("--catalog", default=os.path.join(ROOT, "assets", "catalog.json"))
    ap.add_argument("--tags", default="", help="tags séparés par des virgules")
    ap.add_argument("--dry-run", action="store_true", help="affiche sans écrire")
    ap.add_argument("--no-catalog", action="store_true", help="n'écrit que les charts")
    args = ap.parse_args()

    text = sys.stdin.read() if args.input == '-' else open(args.input, encoding="utf-8").read()
    tags = [t.strip() for t in args.tags.split(',') if t.strip()]

    songs, errors = parse_playlist(text)
    if not songs:
        raise SystemExit("Aucun morceau exploitable trouvé.")

    catalog = {"version": 1, "songs": []}
    if not args.no_catalog and os.path.exists(args.catalog):
        catalog = json.load(open(args.catalog, encoding="utf-8"))

    taken = {s["id"] for s in catalog["songs"]}
    print(f"{len(songs)} morceau(x) parsé(s) :\n")
    for song in songs:
        sid = slugify(song["title"], taken)
        chart = {"key": song["key"], "time": song["time"], "sections": song["sections"]}
        nbars = sum(len(s["bars"]) for s in song["sections"])
        print(f"  • {song['title']:<32} → {sid:<28} "
              f"({len(song['sections'])} section(s), {nbars} mesures)")

        if not args.dry_run:
            os.makedirs(args.charts_dir, exist_ok=True)
            with open(os.path.join(args.charts_dir, f"{sid}.json"), "w",
                      encoding="utf-8") as f:
                json.dump(chart, f, ensure_ascii=False, indent=2)
                f.write("\n")

        entry = {
            "id": sid,
            "title": song["title"],
            "tags": tags,
            "representations": [
                {"id": f"{sid}-grid", "type": "chordGrid",
                 "asset": f"assets/charts/{sid}.json"}
            ],
        }
        if song["artist"]:
            entry["artist"] = song["artist"]
        if not args.no_catalog:
            upsert_catalog(catalog, entry)

    if errors:
        print(f"\n{len(errors)} segment(s) ignoré(s) (dont le nom de playlist).")

    if args.dry_run:
        print("\n[dry-run] rien n'a été écrit.")
        return

    if not args.no_catalog:
        with open(args.catalog, "w", encoding="utf-8") as f:
            json.dump(catalog, f, ensure_ascii=False, indent=2)
            f.write("\n")
        print(f"\ncatalog.json mis à jour → {len(catalog['songs'])} morceaux au total.")
    print("⚠️  Relance le serveur (make web) pour embarquer les nouveaux charts.")


if __name__ == "__main__":
    main()

"""Connecteur The Session — mélodies en notation ABC.

Musique traditionnelle irlandaise = **domaine public** (règle droit d'auteur
du projet : seule source mélodie autorisée). API JSON via ?format=json.
Sortie normalisée : ABC complet (en-tête X/T/R/M/L/K + corps), prêt pour abcjs.
"""
import re

from common import BROWSER_UA

BASE = "https://thesession.org"
_LIMIT = 8
_HEADERS = {"User-Agent": BROWSER_UA}

# Le type de tune détermine la métrique (The Session ne la stocke pas par réglage).
_TYPE_METER = {
    "reel": "4/4", "hornpipe": "4/4", "march": "4/4", "barndance": "4/4",
    "strathspey": "4/4", "jig": "6/8", "slip jig": "9/8", "slide": "12/8",
    "polka": "2/4", "waltz": "3/4", "mazurka": "3/4", "three-two": "3/2",
}


async def search(client, q):
    r = await client.get(f"{BASE}/tunes/search",
                         params={"q": q, "format": "json"}, headers=_HEADERS)
    r.raise_for_status()
    data = r.json()
    out = []
    for t in (data.get("tunes") or [])[:_LIMIT]:
        name = t.get("name")
        if not name:
            continue
        out.append({
            "title": name,
            "artist": "Traditional",
            "type": "score",
            "source": "thesession",
            "ref": str(t.get("id")),
        })
    return out


def _abc_key(key: str) -> str:
    """"Edorian" -> "Edor", "Gmajor" -> "G", "Bminor" -> "Bmin"…"""
    m = re.match(r"([A-Ga-g])([#b]?)(.*)", key or "")
    if not m:
        return "C"
    root = m.group(1).upper() + m.group(2)
    mode = (m.group(3) or "").lower()
    suffix = {
        "": "", "major": "", "minor": "min", "dorian": "dor",
        "mixolydian": "mix", "aeolian": "m", "phrygian": "phr",
        "lydian": "lyd", "locrian": "loc",
    }.get(mode, "")
    return root + suffix


async def fetch_abc(client, ref):
    r = await client.get(f"{BASE}/tunes/{ref}",
                         params={"format": "json"}, headers=_HEADERS)
    r.raise_for_status()
    tune = r.json()
    settings = tune.get("settings") or []
    if not settings:
        return None
    s = settings[0]
    body = (s.get("abc") or "").replace("\r\n", "\n").strip()
    if not body:
        return None
    # The Session utilise "!" comme saut de ligne dans le corps ABC.
    body = re.sub(r"\s*!\s*", "\n", body)
    name = tune.get("name") or "Tune"
    ttype = (tune.get("type") or "").lower()
    meter = _TYPE_METER.get(ttype, "4/4")
    header = ["X:1", f"T:{name}"]
    if ttype:
        header.append(f"R:{ttype}")
    header += [f"M:{meter}", "L:1/8", f"K:{_abc_key(s.get('key') or '')}"]
    return "\n".join(header) + "\n" + body + "\n"

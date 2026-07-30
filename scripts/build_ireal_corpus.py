#!/usr/bin/env python3
"""Construit le corpus iReal Pro servi par le backend (recherche de grilles).

Récupère des threads « méga-playlist » du forum iReal Pro (un seul lien
`irealb://` = des centaines de morceaux), parse via le parseur déjà en place
(`import_irealpro.parse_playlist`) et écrit deux fichiers :

  backend/search/sources/data/ireal-index.json    [{id,title,artist}]  (recherche)
  backend/search/sources/data/ireal-charts.json   {id: {key,time,sections}}

Ces deux fichiers sont **embarqués dans le binaire Go** (go:embed) par la source
`backend/search/sources/irealcorpus.go` : relancer ce script suffit à rafraîchir
le corpus, le backend le reprendra au prochain démarrage.
Usage : python3 scripts/build_ireal_corpus.py
"""
import html
import json
import os
import re
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from import_irealpro import parse_playlist, slugify  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "backend", "search", "sources", "data")
UA = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/125.0 Safari/537.36")

# Threads « méga-playlist » du forum : (url, tags par défaut).
SOURCES = [
    ("https://forums.irealpro.com/threads/jazz-1460-standards.12753/",
     ["jazz", "standard"]),
    ("https://forums.irealpro.com/threads/"
     "parking-lot-pickers-songbook-216-songs.12514/",
     ["folk", "country"]),
]


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=90) as r:
        return r.read().decode("utf-8", "replace")


def biggest_irealb(page):
    links = [html.unescape(m) for m in re.findall(r'href="(irealb://[^"]+)"', page)]
    return max(links, key=len) if links else None


def main():
    taken = set()
    index = []
    charts = {}
    for url, tags in SOURCES:
        try:
            link = biggest_irealb(fetch(url))
        except Exception as e:  # noqa: BLE001
            print(f"⚠️  {url} : {e}")
            continue
        if not link:
            print(f"⚠️  aucun irealb:// dans {url}")
            continue
        songs, errors = parse_playlist(link)
        for s in songs:
            sid = slugify(s["title"], taken)
            index.append({
                "id": sid,
                "title": s["title"],
                "artist": s.get("artist"),
                "tags": tags,
            })
            charts[sid] = {
                "key": s.get("key"),
                "time": s.get("time"),
                "sections": s["sections"],
            }
        print(f"✓ {url}\n    → {len(songs)} morceaux ({len(errors)} segments ignorés)")

    os.makedirs(OUT_DIR, exist_ok=True)
    idx_path = os.path.join(OUT_DIR, "ireal-index.json")
    charts_path = os.path.join(OUT_DIR, "ireal-charts.json")
    with open(idx_path, "w", encoding="utf-8") as f:
        json.dump(index, f, ensure_ascii=False, separators=(",", ":"))
    with open(charts_path, "w", encoding="utf-8") as f:
        json.dump(charts, f, ensure_ascii=False, separators=(",", ":"))

    print(f"\n{len(index)} morceaux au total.")
    print(f"  {idx_path}  ({os.path.getsize(idx_path)//1024} Ko)")
    print(f"  {charts_path}  ({os.path.getsize(charts_path)//1024} Ko)")


if __name__ == "__main__":
    main()

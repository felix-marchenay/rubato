"""Proxy d'agrégation Rubato.

Rôle : offrir à l'app Flutter (web + APK) un point d'entrée unique qui interroge
plusieurs sources en ligne, applique la règle droit d'auteur, normalise vers les
formats pivot de Rubato (chart JSON / ChordPro / ABC) et renvoie du CORS propre.

Endpoints :
  GET /health
  GET /search?q=...            -> candidats agrégés + disponibilité par type
  GET /representation?type=&source=&ref=  -> contenu au format pivot
"""
import asyncio
import time

import httpx
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware

import lrclib
import thesession
from common import USER_AGENT, slugify

app = FastAPI(title="Rubato aggregator proxy", version="0.1")

# Outil perso : on autorise toutes les origines (web dev localhost:8090, APK sans
# origine). À restreindre si le proxy est exposé publiquement.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET"],
    allow_headers=["*"],
)

# Sources de recherche (fan-out parallèle).
_SEARCH = [lrclib.search, thesession.search]
# Récupération d'une représentation : (type, source) -> coroutine(client, ref).
_FETCH = {
    ("lyrics", "lrclib"): (lrclib.fetch_lyrics, "chordpro"),
    ("score", "thesession"): (thesession.fetch_abc, "abc"),
}
# Règle droit d'auteur : la mélodie ne peut venir que de sources domaine public.
_SCORE_SOURCES = {"thesession"}

_client: httpx.AsyncClient | None = None


async def _get_client() -> httpx.AsyncClient:
    global _client
    if _client is None:
        _client = httpx.AsyncClient(
            timeout=12.0,
            headers={"User-Agent": USER_AGENT},
            follow_redirects=True,
        )
    return _client


@app.on_event("shutdown")
async def _shutdown():
    if _client is not None:
        await _client.aclose()


# --- Cache mémoire TTL très simple ---------------------------------------
_CACHE: dict[str, tuple[float, object]] = {}
_TTL = 600.0


def _cache_get(key):
    v = _CACHE.get(key)
    if not v:
        return None
    exp, data = v
    if exp < time.monotonic():
        _CACHE.pop(key, None)
        return None
    return data


def _cache_set(key, data):
    _CACHE[key] = (time.monotonic() + _TTL, data)


@app.get("/health")
async def health():
    return {"ok": True, "sources": ["lrclib", "thesession"]}


@app.get("/search")
async def search(q: str = Query(..., min_length=2)):
    ck = f"search:{q.strip().lower()}"
    cached = _cache_get(ck)
    if cached is not None:
        return cached

    client = await _get_client()
    results = await asyncio.gather(
        *[fn(client, q) for fn in _SEARCH], return_exceptions=True
    )

    agg: dict[tuple[str, str], dict] = {}
    for res in results:
        if isinstance(res, Exception) or not res:
            continue
        for p in res:
            key = (slugify(p["title"]), slugify(p["artist"]))
            cand = agg.get(key)
            if cand is None:
                cand = {
                    "id": "-".join(k for k in key if k),
                    "title": p["title"],
                    "artist": p["artist"],
                    "available": {"chordGrid": False, "lyrics": False, "score": False},
                    "refs": {},
                }
                agg[key] = cand
            cand["available"][p["type"]] = True
            cand["refs"][p["type"]] = {"source": p["source"], "ref": p["ref"]}

    out = {"query": q, "results": list(agg.values())}
    _cache_set(ck, out)
    return out


@app.get("/representation")
async def representation(type: str, source: str, ref: str):
    if type not in ("chordGrid", "lyrics", "score"):
        raise HTTPException(400, "type invalide")
    if type == "score" and source not in _SCORE_SOURCES:
        raise HTTPException(403, "mélodie : sources domaine public uniquement")

    handler = _FETCH.get((type, source))
    if handler is None:
        raise HTTPException(400, f"combinaison type/source non gérée : {type}/{source}")
    fetch, fmt = handler

    ck = f"rep:{type}:{source}:{ref}"
    cached = _cache_get(ck)
    if cached is not None:
        return cached

    client = await _get_client()
    try:
        content = await fetch(client, ref)
    except HTTPException:
        raise
    except Exception as e:  # noqa: BLE001 — remonté tel quel au client
        raise HTTPException(502, f"source indisponible : {e}")
    if not content:
        raise HTTPException(404, "contenu introuvable")

    out = {"type": type, "source": source, "ref": ref, "format": fmt, "content": content}
    _cache_set(ck, out)
    return out

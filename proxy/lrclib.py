"""Connecteur LRCLIB — paroles (contributions communautaires).

Recherche : GET /api/search ; récupération : GET /api/get/{id}.
Sortie normalisée au format pivot Rubato : ChordPro (.pro).
"""

BASE = "https://lrclib.net/api"
_LIMIT = 8


async def search(client, q):
    """Renvoie une liste de candidats partiels {title, artist, type, source, ref}."""
    r = await client.get(f"{BASE}/search", params={"q": q})
    r.raise_for_status()
    data = r.json()
    if not isinstance(data, list):
        return []
    out = []
    for item in data[:_LIMIT]:
        title = item.get("trackName")
        if not title or item.get("instrumental"):
            continue
        if not (item.get("plainLyrics") or "").strip():
            continue
        out.append({
            "title": title,
            "artist": item.get("artistName") or "",
            "type": "lyrics",
            "source": "lrclib",
            "ref": str(item.get("id")),
        })
    return out


async def fetch_lyrics(client, ref):
    """Renvoie les paroles au format ChordPro, ou None."""
    r = await client.get(f"{BASE}/get/{ref}")
    r.raise_for_status()
    item = r.json()
    plain = (item.get("plainLyrics") or "").strip()
    if not plain:
        return None
    title = item.get("trackName") or ""
    artist = item.get("artistName") or ""
    # ChordPro minimal, décodable tel quel par ChordProCodec côté Dart.
    return "\n".join([f"{{title: {title}}}", f"{{artist: {artist}}}", "", plain, ""])

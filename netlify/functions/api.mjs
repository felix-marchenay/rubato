// Backend d'agrégation Rubato — Netlify Function (Node 20, fetch global).
//   GET /health  /search?q=  /representation?type=&source=&ref=
// Sources :
//   - iReal Pro (grilles d'accords) : corpus pré-parsé depuis le forum, embarqué
//     (data/ireal-*.json, régénéré par scripts/build_ireal_corpus.py).
//   - LRCLIB (paroles), en direct.
//   - The Session (mélodie ABC, domaine public), en direct.

// Corpus iReal Pro embarqué (grilles). Index léger pour la recherche + charts.
import irealIndex from "./data/ireal-index.json" with { type: "json" };
import irealCharts from "./data/ireal-charts.json" with { type: "json" };
// Scraping live de suites d'accords (Ultimate Guitar, e-chords, forum iReal).
import { scrapeSearch, SCRAPE_FETCHERS, SCRAPE_SOURCES, decodeEntities } from "./scrapers.mjs";

const USER_AGENT = "Rubato/0.1 (carnet d'accords personnel)";
const BROWSER_UA =
  "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 " +
  "(KHTML, like Gecko) Chrome/125.0 Safari/537.36";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Access-Control-Allow-Headers": "*",
};

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...CORS },
  });
}

function slugify(text) {
  return (
    (text || "")
      .normalize("NFKD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .trim()
      .replace(/[^\w\s-]/g, "")
      .replace(/[\s_-]+/g, "-")
      .replace(/^-+|-+$/g, "") || "untitled"
  );
}

// --- LRCLIB (paroles) → ChordPro ------------------------------------------
const LRCLIB = "https://lrclib.net/api";

async function lrclibSearch(q) {
  const r = await fetch(`${LRCLIB}/search?q=${encodeURIComponent(q)}`, {
    headers: { "User-Agent": USER_AGENT },
  });
  if (!r.ok) return [];
  const data = await r.json();
  if (!Array.isArray(data)) return [];
  return data
    .slice(0, 8)
    .filter((it) => it.trackName && !it.instrumental && (it.plainLyrics || "").trim())
    .map((it) => ({
      title: it.trackName,
      artist: it.artistName || "",
      type: "lyrics",
      source: "lrclib",
      ref: String(it.id),
    }));
}

async function lrclibLyrics(ref) {
  const r = await fetch(`${LRCLIB}/get/${encodeURIComponent(ref)}`, {
    headers: { "User-Agent": USER_AGENT },
  });
  if (!r.ok) return null;
  const it = await r.json();
  const plain = (it.plainLyrics || "").trim();
  if (!plain) return null;
  return [`{title: ${it.trackName || ""}}`, `{artist: ${it.artistName || ""}}`, "", plain, ""].join("\n");
}

// --- The Session (mélodie ABC, domaine public) ----------------------------
const TS = "https://thesession.org";
const TYPE_METER = {
  reel: "4/4", hornpipe: "4/4", march: "4/4", barndance: "4/4",
  strathspey: "4/4", jig: "6/8", "slip jig": "9/8", slide: "12/8",
  polka: "2/4", waltz: "3/4", mazurka: "3/4", "three-two": "3/2",
};

async function tsSearch(q) {
  const r = await fetch(`${TS}/tunes/search?q=${encodeURIComponent(q)}&format=json`, {
    headers: { "User-Agent": BROWSER_UA },
  });
  if (!r.ok) return [];
  const data = await r.json();
  return (data.tunes || [])
    .slice(0, 8)
    .filter((t) => t.name)
    .map((t) => ({
      title: t.name,
      artist: "Traditional",
      type: "score",
      source: "thesession",
      ref: String(t.id),
    }));
}

function abcKey(key) {
  const m = /^([A-Ga-g])([#b]?)(.*)$/.exec(key || "");
  if (!m) return "C";
  const root = m[1].toUpperCase() + m[2];
  const mode = (m[3] || "").toLowerCase();
  const suffix =
    { "": "", major: "", minor: "min", dorian: "dor", mixolydian: "mix",
      aeolian: "m", phrygian: "phr", lydian: "lyd", locrian: "loc" }[mode] ?? "";
  return root + suffix;
}

async function tsAbc(ref) {
  const r = await fetch(`${TS}/tunes/${encodeURIComponent(ref)}?format=json`, {
    headers: { "User-Agent": BROWSER_UA },
  });
  if (!r.ok) return null;
  const tune = await r.json();
  const s = (tune.settings || [])[0];
  if (!s) return null;
  let body = (s.abc || "").replace(/\r\n/g, "\n").trim();
  if (!body) return null;
  body = body.replace(/\s*!\s*/g, "\n"); // The Session : "!" = saut de ligne
  const ttype = (tune.type || "").toLowerCase();
  const meter = TYPE_METER[ttype] || "4/4";
  const header = ["X:1", `T:${tune.name || "Tune"}`];
  if (ttype) header.push(`R:${ttype}`);
  header.push(`M:${meter}`, "L:1/8", `K:${abcKey(s.key || "")}`);
  return header.join("\n") + "\n" + body + "\n";
}

// --- iReal Pro (grilles d'accords) : recherche dans le corpus embarqué -----
const SCORE_SOURCES = new Set(["thesession"]); // mélodie = domaine public only
const IREAL_LIMIT = 15;

function norm(s) {
  return (s || "")
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .trim();
}

function irealSearch(q) {
  const nq = norm(q);
  if (!nq) return [];
  const out = [];
  for (const it of irealIndex) {
    if (out.length >= IREAL_LIMIT) break;
    if (norm(it.title).includes(nq) || (it.artist && norm(it.artist).includes(nq))) {
      out.push({
        title: it.title,
        artist: it.artist || "",
        type: "chordGrid",
        source: "irealpro",
        ref: it.id,
      });
    }
  }
  return out;
}

// --- Agrégation ------------------------------------------------------------
async function handleSearch(q) {
  const settled = await Promise.allSettled([lrclibSearch(q), tsSearch(q), scrapeSearch(q)]);
  // Grilles du corpus iReal embarqué en tête (harmonie fiable, parsée), puis les
  // suites d'accords scrapées en live, puis paroles/mélodie.
  const partials = [...irealSearch(q)];
  for (const res of settled) if (res.status === "fulfilled") partials.push(...res.value);

  const agg = new Map();
  for (const p of partials) {
    if (!p.title) continue;
    // Certaines sources (LRCLIB…) renvoient des libellés HTML-encodés : on
    // décode avant de slugifier (sinon « A &amp; B » → id « a-amp-b »).
    const title = decodeEntities(p.title);
    const artist = decodeEntities(p.artist);
    const key = slugify(title) + "|" + slugify(artist);
    let cand = agg.get(key);
    if (!cand) {
      cand = {
        id: [slugify(title), slugify(artist)].filter(Boolean).join("-"),
        title,
        artist,
        available: { chordGrid: false, lyrics: false, score: false },
        refs: {},
      };
      agg.set(key, cand);
    }
    cand.available[p.type] = true;
    // Première source d'un type gagne : le corpus iReal (poussé en tête) prime
    // sur les scrapers, et parmi les scrapers l'ordre de scrapeSearch décide.
    if (!cand.refs[p.type]) cand.refs[p.type] = { source: p.source, ref: p.ref };
  }
  return { query: q, results: [...agg.values()] };
}

const FETCHERS = {
  // Grille iReal : lue dans le corpus embarqué, renvoyée en JSON (format pivot).
  "chordGrid:irealpro": {
    fn: (ref) => {
      const c = irealCharts[ref];
      return c ? JSON.stringify(c) : null;
    },
    format: "chart-json",
  },
  "lyrics:lrclib": { fn: lrclibLyrics, format: "chordpro" },
  "score:thesession": { fn: tsAbc, format: "abc" },
  // Grilles scrapées en live (Ultimate Guitar, e-chords, forum iReal).
  ...Object.fromEntries(
    SCRAPE_SOURCES.map((src) => [
      `chordGrid:${src}`,
      { fn: SCRAPE_FETCHERS[src], format: "chart-json" },
    ])
  ),
};

export default async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });

  const url = new URL(req.url);
  const path = url.pathname;

  if (path.endsWith("/health")) {
    return json({
      ok: true,
      sources: ["irealpro", ...SCRAPE_SOURCES, "lrclib", "thesession"],
      irealSongs: irealIndex.length,
    });
  }

  if (path.endsWith("/search")) {
    const q = (url.searchParams.get("q") || "").trim();
    if (q.length < 2) return json({ error: "q trop court" }, 400);
    try {
      return json(await handleSearch(q));
    } catch (e) {
      return json({ error: String(e) }, 502);
    }
  }

  if (path.endsWith("/representation")) {
    const type = url.searchParams.get("type");
    const source = url.searchParams.get("source");
    const ref = url.searchParams.get("ref");
    if (!["chordGrid", "lyrics", "score"].includes(type)) {
      return json({ error: "type invalide" }, 400);
    }
    if (type === "score" && !SCORE_SOURCES.has(source)) {
      return json({ error: "mélodie : sources domaine public uniquement" }, 403);
    }
    const h = FETCHERS[`${type}:${source}`];
    if (!h) return json({ error: `combinaison non gérée : ${type}/${source}` }, 400);
    try {
      const content = await h.fn(ref);
      if (!content) return json({ error: "contenu introuvable" }, 404);
      return json({ type, source, ref, format: h.format, content });
    } catch (e) {
      return json({ error: String(e) }, 502);
    }
  }

  return json({ error: "not found" }, 404);
};

// Netlify Functions v2 : routes exactes au niveau racine du site.
export const config = { path: ["/health", "/search", "/representation"] };

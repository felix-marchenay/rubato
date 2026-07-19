// Scrapers de grilles d'accords (« suites d'accords ») pour la recherche live.
//
// Trois sources, toutes en best-effort (tout échec réseau/parse → [] ou null,
// la recherche continue avec les autres sources) :
//   - ultimateguitar : très large couverture pop/rock/soul. Accords balisés
//     [ch]…[/ch] dans un JSON embarqué → texte → détection lignes d'accords.
//   - echords        : e-chords.com, format « accords au-dessus des paroles ».
//     On strippe le HTML puis on détecte les lignes 100 % accords.
//   - irealforum     : forum iReal Pro (live). Les grilles sont des URLs
//     irealb:// chiffrées → parser dédié (porté de scripts/import_irealpro.py).
//
// Droits d'auteur : on n'extrait QUE l'harmonie (accords). Aucune parole ni
// mélodie n'est renvoyée — conforme à la règle projet (les grilles sont OK).
//
// Format de sortie : le format pivot « chart-json » de Rubato,
//   { key, time, sections: [{ label, bars: [{ chords: [...] }] }] }.
// Choix produit : une mesure = un accord (structure simple, robuste ; on ne
// tente pas de reconstruire les vraies barres, sauf pour iReal qui les donne).

const BROWSER_UA =
  "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 " +
  "(KHTML, like Gecko) Chrome/125.0 Safari/537.36";

const RESULT_LIMIT = 8; // candidats max par source

// ─── Utilitaires ────────────────────────────────────────────────────────────

/** fetch texte avec timeout dur (une source lente ne bloque pas la recherche). */
async function fetchText(url, ms = 7000) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), ms);
  try {
    const r = await fetch(url, {
      headers: { "User-Agent": BROWSER_UA, "Accept-Language": "en,fr;q=0.8" },
      signal: ctrl.signal,
      redirect: "follow",
    });
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    return await r.text();
  } finally {
    clearTimeout(timer);
  }
}

function norm(s) {
  return (s || "")
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .trim();
}

const ENTITIES = {
  "&quot;": '"', "&amp;": "&", "&#039;": "'", "&#39;": "'", "&apos;": "'",
  "&lt;": "<", "&gt;": ">", "&nbsp;": " ",
};
export function decodeEntities(s) {
  return (s || "")
    .replace(/&(?:quot|amp|#0?39|apos|lt|gt|nbsp);/g, (m) => ENTITIES[m] ?? m)
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(+n))
    .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)));
}

function stripTags(html) {
  return decodeEntities(
    (html || "")
      .replace(/<br\s*\/?>/gi, "\n")
      .replace(/<\/(?:p|div|li|tr)>/gi, "\n")
      .replace(/<[^>]+>/g, "")
  );
}

function titleCase(s) {
  return s.replace(/\b\w/g, (c) => c.toUpperCase());
}

// ─── Détection d'accords (notation standard) ────────────────────────────────
// Racine A–G + altération + qualité faite uniquement de caractères d'accord.
// Volontairement permissif sur la qualité, strict sur la forme d'ensemble pour
// éviter d'attraper des mots de paroles.
const CHORD_RE =
  /^[A-G][#b]?(?:maj|min|aug|dim|sus|add|alt|omit|no|m|M|Δ|ø|°|\+|-|\d|[#b]|\(|\)|\/[A-G][#b]?)*$/;

function isChord(tok) {
  if (!tok) return false;
  if (tok === "N.C." || tok === "NC" || tok === "%") return true;
  if (tok.length > 12) return false;
  return CHORD_RE.test(tok);
}

/**
 * Convertit un texte « accords au-dessus des paroles » (ou blocs d'accords
 * purs) en sections. Une ligne dont TOUS les tokens sont des accords est une
 * ligne d'accords ; un saut (ligne vide / ligne de paroles) sépare les
 * sections. Un en-tête court ([Verse], "Refrain:", "A") sert de label.
 */
function textToSections(text) {
  const lines = (text || "").split(/\r?\n/).map((l) => l.replace(/[ ​]/g, " "));
  const sections = [];
  let cur = null;
  let pendingLabel = null;
  let gap = true;

  const headerLabel = (t) => {
    const b = /^\[([^\]]{1,30})\]$/.exec(t);
    if (b) return b[1].trim();
    if (
      t.length <= 24 &&
      /^(intro|verse|couplet|chorus|refrain|bridge|pont|pre-?chorus|outro|solo|interlude|coda|ending|part\s|section\s|[a-h])\b/i.test(t)
    ) {
      return t.replace(/[:*\-\d.]+$/, "").trim() || null;
    }
    return null;
  };

  for (const raw of lines) {
    const t = raw.trim();
    if (!t) {
      gap = true;
      continue;
    }
    const tokens = t.split(/\s+/);
    if (tokens.length > 0 && tokens.every(isChord)) {
      if (!cur || gap) {
        cur = { label: pendingLabel, bars: [] };
        sections.push(cur);
        pendingLabel = null;
      }
      for (const c of tokens) cur.bars.push({ chords: [c === "NC" ? "N.C." : c] });
      gap = false;
    } else {
      const h = headerLabel(t);
      if (h) pendingLabel = h;
      gap = true;
    }
  }
  return sections;
}

function buildChart(sections, { key = null, time = "4/4" } = {}) {
  const clean = (sections || []).filter((s) => s.bars && s.bars.length);
  if (!clean.length) return null;
  return { key, time, sections: clean };
}

// ─── Ultimate Guitar ────────────────────────────────────────────────────────
// Les pages UG embarquent tout l'état dans <div class="js-store" data-content="…">
// (JSON HTML-échappé). On y lit les résultats de recherche et le contenu du tab.

function ugStore(html) {
  const m = /class="js-store"[^>]*\sdata-content="([^"]*)"/.exec(html);
  if (!m) return null;
  try {
    return JSON.parse(decodeEntities(m[1]));
  } catch {
    return null;
  }
}

function ugData(obj) {
  return obj?.store?.page?.data ?? obj?.page?.data ?? obj?.data ?? null;
}

async function ugSearch(q) {
  const url = `https://www.ultimate-guitar.com/search.php?search_type=title&value=${encodeURIComponent(q)}`;
  let html;
  try {
    html = await fetchText(url);
  } catch {
    return [];
  }
  const data = ugData(ugStore(html));
  const raw = data?.results || data?.other_tabs || [];
  const out = [];
  const seen = new Set();
  for (const r of raw) {
    if (out.length >= RESULT_LIMIT) break;
    if (String(r.type || "").toLowerCase() !== "chords") continue;
    const ref = r.tab_url || r.url;
    if (!ref || seen.has(ref)) continue;
    seen.add(ref);
    out.push({
      title: r.song_name || r.name || "",
      artist: r.artist_name || "",
      type: "chordGrid",
      source: "ultimateguitar",
      ref,
    });
  }
  return out;
}

async function ugChart(ref) {
  // Les tabs sont servis sur des sous-domaines (tabs.ultimate-guitar.com…).
  if (!/^https?:\/\/(?:[a-z0-9-]+\.)*ultimate-guitar\.com\//i.test(ref || "")) return null;
  let html;
  try {
    html = await fetchText(ref);
  } catch {
    return null;
  }
  const data = ugData(ugStore(html));
  const content = data?.tab_view?.wiki_tab?.content;
  if (typeof content !== "string" || !content) return null;
  // [ch]C[/ch] → C ; on retire les balises [tab] ; les en-têtes [Verse] restent.
  const text = content
    .replace(/\[\/?tab\]/g, "")
    .replace(/\[ch\]([^[]+)\[\/ch\]/g, "$1");
  return buildChart(textToSections(text));
}

// ─── e-chords.com ───────────────────────────────────────────────────────────

async function echordsSearch(q) {
  const url = `https://www.e-chords.com/search-all/${encodeURIComponent(q)}`;
  let html;
  try {
    html = await fetchText(url);
  } catch {
    return [];
  }
  const out = [];
  const seen = new Set();
  const re =
    /<a[^>]+href="(https?:\/\/www\.e-chords\.com\/chords\/[^"?#]+)"[^>]*>([^<]{1,80})<\/a>/g;
  let m;
  while ((m = re.exec(html)) && out.length < RESULT_LIMIT) {
    const href = m[1];
    if (seen.has(href)) continue;
    seen.add(href);
    const seg = href.split("/chords/")[1].split("/");
    out.push({
      title: decodeEntities(m[2]).trim(),
      artist: seg[0] ? titleCase(seg[0].replace(/-/g, " ")) : "",
      type: "chordGrid",
      source: "echords",
      ref: href,
    });
  }
  return out;
}

async function echordsChart(ref) {
  if (!/^https?:\/\/(?:[a-z0-9-]+\.)*e-chords\.com\//i.test(ref || "")) return null;
  let html;
  try {
    html = await fetchText(ref);
  } catch {
    return null;
  }
  const blocks = [...html.matchAll(/<pre[^>]*>([\s\S]*?)<\/pre>/gi)].map((m) => m[1]);
  if (!blocks.length) return null;
  blocks.sort((a, b) => b.length - a.length);
  return buildChart(textToSections(stripTags(blocks[0])));
}

// ─── iReal Pro (forum, live) ────────────────────────────────────────────────
// Parser porté fidèlement de scripts/import_irealpro.py (dé-brouillage repris de
// pyRealParser, MIT). Les grilles iReal donnent de vraies mesures → on les garde.

const IR_PREFIX = "1r34LbKcu7";
const IR_CHORD_RE = /(?<!\/)([A-GNn][^A-GN/]*(?:\/[A-GN][#b]?)?)/g;
const IR_SECTION_LABELS = { i: "Intro", v: "Verse", V: "Verse" };

function irObfusc50(block) {
  const r = block.split("");
  for (let i = 0; i < 5; i++) {
    r[i] = block[49 - i];
    r[49 - i] = block[i];
  }
  for (let i = 10; i < 24; i++) {
    r[i] = block[49 - i];
    r[49 - i] = block[i];
  }
  return r.join("");
}

function irUnscramble(s) {
  let out = "";
  while (s.length > 50) {
    const chunk = s.slice(0, 50);
    s = s.slice(50);
    out += s.length < 2 ? chunk : irObfusc50(chunk);
  }
  return out + s;
}

function irCleanup(s) {
  s = s.replace(/LZ|K/g, "|");
  s = s.replace(/cl/g, "x");
  s = s.replace(/\*\s*\*/g, "");
  s = s.replace(/Y+/g, "");
  s = s.replace(/XyQ|,/g, " ");
  s = s.replace(/\|\s*\|/g, "|");
  s = s.replace(/Z/g, "|");
  s = s.replace(/\s+/g, " ");
  return s.trim();
}

function irStripAnnotations(s) {
  s = s.replace(/[[\]]/g, "|");
  s = s.replace(/<.*?>/g, ""); // commentaires
  s = s.replace(/\([^)]*\)/g, ""); // accords alternatifs
  s = s.replace(/f/g, ""); // point d'orgue
  s = s.replace(/(?<!a)l(?!t)/g, ""); // taille 'l' (préserve 'alt')
  s = s.replace(/(?<!su)s(?!us)/g, ""); // taille 's' (préserve 'sus')
  s = s.replace(/U|S|Q|N\d/g, ""); // navigation (coda, segno, fins)
  s = s.replace(/\|\s*\|/g, "|");
  return s;
}

function irFillRepeats(measures) {
  for (let i = 1; i < measures.length; i++) {
    if (measures[i] === "x") measures[i] = measures[i - 1];
  }
  let i = 2;
  while (i < measures.length) {
    if (measures[i] === "r") {
      measures.splice(i, 1, measures[i - 2], measures[i - 1]);
      i += 1;
    }
    i += 1;
  }
  return measures;
}

function irChordsOf(measure) {
  measure = measure.replace(/p/g, ""); // slashes : rien de neuf à afficher
  const chords = [];
  for (const m of measure.matchAll(IR_CHORD_RE)) {
    const tok = m[1];
    chords.push(tok === "n" || tok === "nn" ? "N.C." : tok);
  }
  return chords;
}

function irMeasures(content) {
  let raw = content
    .split(/[|{}]/)
    .filter((m) => m.trim())
    .map((m) => m.replace(/ /g, ""));
  raw = irFillRepeats(raw);
  const bars = [];
  for (const m of raw) {
    const chords = irChordsOf(m);
    if (chords.length) bars.push({ chords });
  }
  return bars;
}

function irSectionLabel(marker) {
  return IR_SECTION_LABELS[marker] || marker.toUpperCase();
}

function irParseSong(tuneString) {
  const parts = tuneString.split(/=+/);
  if (parts.length < 5) throw new Error("champs insuffisants");
  const title = parts[0];
  const composer = parts[1];
  let key = parts[3];
  const offset = parts[4].includes(IR_PREFIX) ? 0 : 1;
  const musicField = parts[4 + offset];
  if (!musicField || !musicField.includes(IR_PREFIX)) {
    throw new Error("préfixe de grille introuvable");
  }
  const scrambled = musicField.slice(musicField.indexOf(IR_PREFIX) + IR_PREFIX.length);

  let music = irStripAnnotations(irCleanup(irUnscramble(scrambled)));

  const tsig = /T(\d)(\d)/.exec(music);
  const time = tsig ? `${+tsig[1]}/${+tsig[2]}` : null;
  music = music.replace(/T\d+/g, "");

  const chunks = music.split(/\*(\w)/);
  const rawSections = [];
  if (chunks[0].replace(/[ |]/g, "")) rawSections.push([null, chunks[0]]);
  for (let i = 1; i < chunks.length; i += 2) {
    rawSections.push([irSectionLabel(chunks[i]), chunks[i + 1] ?? ""]);
  }

  const sections = [];
  for (const [label, content] of rawSections) {
    const bars = irMeasures(content);
    if (bars.length) sections.push({ label, bars });
  }
  if (!sections.length) throw new Error("aucune mesure exploitable");

  if (key && key.endsWith("-")) key = key.slice(0, -1) + "m";

  return {
    title: title.trim(),
    artist: composer.trim() || null,
    key: key || null,
    time,
    sections,
  };
}

function irUnquote(s) {
  try {
    return decodeURIComponent(s);
  } catch {
    return s.replace(/%([0-9A-Fa-f]{2})/g, (_, h) => String.fromCharCode(parseInt(h, 16)));
  }
}

/** Parse une URL irealb:// (playlist) → [{ chunk, song }] (chunk = brut, réutilisable). */
function irParsePlaylist(text) {
  const m = /irealb(?:ook)?:\/\/(.+)/s.exec(text);
  if (!m) return [];
  const body = irUnquote(m[1]).trim();
  const songs = [];
  for (const chunk of body.split("===")) {
    if (!chunk.trim()) continue;
    try {
      songs.push({ chunk, song: irParseSong(chunk) });
    } catch {
      // dernier segment = nom de la playlist, ou morceau non géré → ignoré
    }
  }
  return songs;
}

function biggestIrealb(html) {
  const links = [...(html || "").matchAll(/irealb(?:ook)?:\/\/[^"'<\s]+/g)].map((m) =>
    decodeEntities(m[0])
  );
  return links.length ? links.reduce((a, b) => (b.length > a.length ? b : a)) : null;
}

// ref auto-porteuse : on embarque le morceau brut (base64url) → /representation
// n'a plus besoin de re-scraper le forum.
function b64urlEncode(s) {
  return Buffer.from(s, "utf8").toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
function b64urlDecode(s) {
  return Buffer.from(s.replace(/-/g, "+").replace(/_/g, "/"), "base64").toString("utf8");
}

async function irealForumSearch(q) {
  const url = `https://forums.irealpro.com/search/?q=${encodeURIComponent(q)}&o=relevance`;
  let html;
  try {
    html = await fetchText(url);
  } catch {
    return []; // forum souvent protégé anti-bot → best-effort
  }
  const threads = [
    ...new Set([...html.matchAll(/href="(\/threads\/[^"#?]+)"/g)].map((m) => m[1])),
  ].slice(0, 2);

  const nq = norm(q);
  const out = [];
  const seen = new Set();
  for (const path of threads) {
    if (out.length >= RESULT_LIMIT) break;
    let page;
    try {
      page = await fetchText(`https://forums.irealpro.com${path}`);
    } catch {
      continue;
    }
    const link = biggestIrealb(page);
    if (!link) continue;
    for (const { chunk, song } of irParsePlaylist(link)) {
      if (out.length >= RESULT_LIMIT) break;
      const key = norm(song.title) + "|" + norm(song.artist || "");
      if (seen.has(key)) continue;
      if (norm(song.title).includes(nq) || (song.artist && norm(song.artist).includes(nq))) {
        seen.add(key);
        out.push({
          title: song.title,
          artist: song.artist || "",
          type: "chordGrid",
          source: "irealforum",
          ref: "b64:" + b64urlEncode(chunk),
        });
      }
    }
  }
  return out;
}

function irealForumChart(ref) {
  if (!ref || !ref.startsWith("b64:")) return null;
  let song;
  try {
    song = irParseSong(b64urlDecode(ref.slice(4)));
  } catch {
    return null;
  }
  return buildChart(song.sections, { key: song.key, time: song.time || "4/4" });
}

// ─── API du module ──────────────────────────────────────────────────────────

/** Recherche live sur toutes les sources scrapées. Renvoie des candidats plats. */
export async function scrapeSearch(q) {
  const settled = await Promise.allSettled([
    ugSearch(q),
    echordsSearch(q),
    irealForumSearch(q),
  ]);
  const out = [];
  for (const r of settled) if (r.status === "fulfilled") out.push(...r.value);
  return out;
}

/** Fetchers /representation par source. Renvoient une chaîne JSON (chart-json) ou null. */
export const SCRAPE_FETCHERS = {
  ultimateguitar: async (ref) => {
    const c = await ugChart(ref);
    return c ? JSON.stringify(c) : null;
  },
  echords: async (ref) => {
    const c = await echordsChart(ref);
    return c ? JSON.stringify(c) : null;
  },
  irealforum: (ref) => {
    const c = irealForumChart(ref);
    return c ? JSON.stringify(c) : null;
  },
};

export const SCRAPE_SOURCES = ["ultimateguitar", "echords", "irealforum"];

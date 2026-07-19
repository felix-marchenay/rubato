// Runner local du backend Netlify (netlify/functions/api.mjs) pour tester la
// recherche/scraping sans déployer. Node uniquement (via Docker : `make backend`).
//
// Il n'y a PAS de serveur : on importe le handler de la function et on l'appelle
// avec une Request synthétique, puis on affiche le statut + le corps (JSON joli).
//
// Paramètres (variables d'env, posées par le Makefile) :
//   ROUTE  chemin complet avec query, ex. "/health", "/representation?type=..."
//   Q      raccourci recherche : si ROUTE est vide, on tape "/search?q=$Q"
//
// Exemples :
//   make backend q='so what'
//   make backend route='/health'
//   make backend route='/representation?type=chordGrid&source=ultimateguitar&ref=<url-encodée>'

import handler from "../netlify/functions/api.mjs";

const arg = process.argv[2] || "";
const route = (process.env.ROUTE || "").trim();
const q = (process.env.Q || "").trim();

let path;
if (route) path = route;
else if (arg) path = arg.startsWith("/") ? arg : `/search?q=${encodeURIComponent(arg)}`;
else if (q) path = `/search?q=${encodeURIComponent(q)}`;
else path = "/health";

if (!path.startsWith("/")) path = "/" + path;

const url = `http://localhost${path}`;
process.stderr.write(`→ GET ${url}\n`);

const res = await handler(new Request(url, { method: "GET" }));
const text = await res.text();

process.stderr.write(`← ${res.status} ${res.headers.get("content-type") || ""}\n`);

// Corps : joli si JSON, brut sinon.
try {
  const data = JSON.parse(text);
  if (data && Array.isArray(data.results)) {
    renderSearch(data);
  } else {
    // Pour /representation, le champ `content` est lui-même du JSON encodé → on
    // le ré-indente pour l'inspecter facilement.
    if (data && typeof data.content === "string" && data.format === "chart-json") {
      try {
        data.content = JSON.parse(data.content);
      } catch {
        /* garde la chaîne */
      }
    }
    process.stdout.write(JSON.stringify(data, null, 2) + "\n");
  }
} catch {
  process.stdout.write(text + "\n");
}

/** Rendu lisible d'une réponse /search : un morceau par ligne + ses sources. */
function renderSearch(data) {
  const rows = data.results;
  process.stdout.write(`\n« ${data.query} » — ${rows.length} résultat(s)\n\n`);
  if (!rows.length) return;
  const label = (r) => `${r.title}${r.artist ? " — " + r.artist : ""}`;
  const width = Math.min(50, Math.max(...rows.map((r) => label(r).length)));
  const sourceOf = (r, t) => (r.refs?.[t] ? r.refs[t].source : null);
  for (const r of rows) {
    const grid = sourceOf(r, "chordGrid");
    const tags = [
      grid ? `grille:${grid}` : null,
      r.available?.lyrics ? "paroles" : null,
      r.available?.score ? "mélodie" : null,
    ].filter(Boolean);
    process.stdout.write(`  ${label(r).padEnd(width).slice(0, width)}  ${tags.join("  ") || "—"}\n`);
  }
  process.stdout.write("\n");
}

process.exit(res.status < 400 ? 0 : 1);

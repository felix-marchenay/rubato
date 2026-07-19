# Backend Rubato sur Netlify

Le backend de recherche de morceaux en ligne est une **Netlify Function** (Node),
car Netlify n'exécute pas de serveur Python persistant.

- `netlify/functions/api.mjs` — la function (routes `/health`, `/search`, `/representation`).
- `netlify/functions/scrapers.mjs` — scrapers live de suites d'accords.
- `netlify/public/index.html` — page d'accueil statique.
- [`../netlify.toml`](../netlify.toml) — config (publish + functions, Node 20).

Sources agrégées :
- **iReal Pro** (grilles d'accords) — corpus pré-parsé depuis le forum, embarqué
  dans `netlify/functions/data/ireal-*.json`. Régénérer avec
  `python3 scripts/build_ireal_corpus.py` puis redéployer.
- **Ultimate Guitar / e-chords / forum iReal Pro** (grilles d'accords) — **scrapés
  en direct** à chaque `/search` (`scrapers.mjs`). On n'extrait que l'harmonie
  (accords), jamais les paroles/mélodie. Une mesure = un accord (structure simple ;
  iReal conserve ses vraies mesures). Toutes best-effort : un échec réseau/parse
  d'une source ne casse pas la recherche (les autres répondent). Le forum iReal
  peut ne rien renvoyer s'il est protégé anti-bot.
- **LRCLIB** (paroles → ChordPro), en direct.
- **The Session** (mélodies → ABC, domaine public), en direct.

Priorité des grilles : le corpus iReal embarqué (parsé, fiable) prime, puis les
sources scrapées dans l'ordre UG → e-chords → forum iReal.

Garde-fou : une mélodie hors source domaine public est refusée (403). Les grilles
(harmonie) n'ont pas cette restriction.

## Déployer (via Git)

Le repo est sur GitHub. Sur https://app.netlify.com :

1. **Add new site → Import an existing project → GitHub → `rubato`**.
2. Netlify lit `netlify.toml` (aucun réglage à saisir). Deploy.
3. Choisir la **branche de production** dans *Site settings → Build & deploy → Branches*.
4. URL du site : `https://<nom>.netlify.app`. Redéploiement auto à chaque push.

Instance actuelle : **https://rubato1.netlify.app** (branche `develop`).

Vérifier :
```
curl https://rubato1.netlify.app/health
curl "https://rubato1.netlify.app/search?q=cooley"
curl "https://rubato1.netlify.app/search?q=so%20what"   # grilles scrapées (UG…)
```

## Déployer (alternative : CLI, nécessite Node local)

```
npm i -g netlify-cli
netlify login
netlify deploy --prod       # depuis la racine du repo
```

## Pointer l'app sur ce backend

C'est déjà le **défaut** (`RUBATO_API=https://rubato1.netlify.app`) pour `make web`
et `make apk`. Pour viser un autre backend :

```
make apk RUBATO_API=https://autre-backend.example
```

## Note

Vérifié en prod : The Session (derrière Cloudflare) répond bien depuis Netlify —
la recherche de mélodies fonctionne. LRCLIB n'est pas concerné.

# Backend Rubato sur Netlify

Le backend de recherche de morceaux en ligne est une **Netlify Function** (Node),
car Netlify n'exécute pas de serveur Python persistant.

- `netlify/functions/api.mjs` — la function (routes `/health`, `/search`, `/representation`).
- `netlify/public/index.html` — page d'accueil statique.
- [`../netlify.toml`](../netlify.toml) — config (publish + functions, Node 20).

Sources agrégées : LRCLIB (paroles → ChordPro) + The Session (mélodies → ABC,
domaine public). Garde-fou : une mélodie hors source domaine public est refusée (403).

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

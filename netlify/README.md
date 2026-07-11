# Backend Rubato sur Netlify

Le proxy d'agrégation (recherche de morceaux en ligne) est déployé ici en
**Netlify Function** (Node), car Netlify n'exécute pas de serveur Python.
Même contrat d'API que le proxy Python de [`../proxy`](../proxy) (dev local Docker).

- `netlify/functions/api.mjs` — la function (routes `/health`, `/search`, `/representation`).
- `netlify/public/index.html` — page d'accueil statique.
- [`../netlify.toml`](../netlify.toml) — config (publish + functions, Node 20).

## Déployer (recommandé : via Git)

Le repo est déjà sur GitHub. Sur https://app.netlify.com :

1. **Add new site → Import an existing project → GitHub → `rubato`**.
2. Netlify lit `netlify.toml` (aucun réglage à saisir). Deploy.
3. Choisir la **branche de production** (ex. `main` ou `develop`) dans
   *Site settings → Build & deploy → Branches*.
4. URL du site : `https://<nom>.netlify.app`. Redéploiement auto à chaque push.

Vérifier :
```
curl https://<nom>.netlify.app/health
curl "https://<nom>.netlify.app/search?q=cooley"
```

## Déployer (alternative : CLI, nécessite Node local)

```
npm i -g netlify-cli
netlify login
netlify deploy --prod       # depuis la racine du repo
```

## Pointer l'app sur ce backend

```
make apk RUBATO_API=https://<nom>.netlify.app
# ou pour tester le web sur le backend déployé :
make web RUBATO_API=https://<nom>.netlify.app
```

## Limite connue

The Session est derrière Cloudflare : selon l'IP de sortie Netlify, la mélodie
peut être bloquée (403). LRCLIB (paroles) n'est pas concerné. À vérifier après
le 1er déploiement via `/search?q=cooley` (présence de résultats `score`).

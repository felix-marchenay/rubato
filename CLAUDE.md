# Rubato — guide projet

Appli **Flutter** de visualisation de partitions : un **morceau → N représentations**
(grille d'accords, paroles, mélodie…). Nom produit **Rubato** ; nom de package Dart
interne = `mscore` (ne pas renommer, casserait les imports `package:mscore/…` des tests).

## Environnement (tout via Docker)

Rien n'est installé sur l'hôte : Flutter tourne dans le conteneur
(`ghcr.io/cirruslabs/flutter:stable`, contient `curl` + `bash`).

```bash
make web        # serveur web (voir port ci-dessous)
make apk        # APK Android release
make apk-telegram   # build APK + envoi Telegram (config dans .env)
make api-run    # backend Go de recherche → http://localhost:8091
make search creep radiohead   # recherche via le backend Go, résumé lisible
make api-deploy # déployer le backend sur Fly.io (cf. backend/README.md)
make analyze / make test / make api-test   # ⚠️ demander avant de lancer (règle utilisateur)
```

- **Lancement web réel** (le port hôte 8080 est pris par un autre projet) :
  `docker compose run --rm -p 8090:8080 flutter flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080`
  → http://localhost:8090
- Device `web-server` : **pas de hot reload auto**. Après un changement de code
  **ou l'ajout de nouveaux assets**, il faut **redémarrer** le serveur (stop conteneur `mscore-flutter-run` + relancer).
- Hôte : Python 3.14 + Pillow dispo. Pas de navigateur/Chrome MCP →
  **le rendu visuel n'est pas vérifiable ici, c'est l'utilisateur qui teste**.

## Direction artistique « Encre & Papier »

Papier crème + encre profonde + **un seul accent laiton/ocre** (jamais de bleu Material).
Serif **Fraunces** (titres, accords) + sans **Manrope** (interface), via `google_fonts`.
Tout est centralisé dans `lib/src/ui/theme.dart` (`RubatoPalette`, `RubatoType`,
`RubatoTheme.light()/dark()`, extension `context.palette`). Réutiliser ces styles.

## Architecture

- `lib/src/domain/` : modèles purs — `song.dart` (Song, Representation,
  `RepresentationType {chordGrid, lyrics, score, …}`, getters `primaryChordGrid`
  `primaryLyrics` `primaryScore`), `chord_chart.dart`, `lyric_sheet.dart`.
- `lib/src/codec/` : (dé)sérialisation découplée du domaine —
  `json_chord_chart_codec.dart`, `chord_parser.dart` (vocabulaire iReal :
  `-`=min, `^`=maj7, `h`=ø, `o`=°), `chordpro_codec.dart`.
- `lib/src/data/` : `catalog_repository.dart` (charge assets), `library_repository.dart`
  (assets + biblio perso), `lrclib_service.dart` (paroles en ligne, appel direct),
  `remote_catalog_service.dart` (client du backend Go : flux SSE + repli batch),
  `sse.dart` + `sse_transport.dart` (+ `_io`/`_web`/`_stub`) pour le streaming,
  `search_cache.dart` sur `local_db.dart` (+ `_io`/`_web`/`_stub`) pour le cache,
  `key_value_store.dart` (contrat du stockage), `lyrics_store.dart` /
  `user_library_store.dart` (+ `_io`/`_web`/`_stub`, persistance locale).
- `lib/src/ui/` : `library_screen.dart`, `chart_screen.dart` (sélecteur 3 vues
  **Grille · Paroles · Mélodie**), `online_search_screen.dart` (recherche en ligne),
  `widgets/` (`chord_grid_view`, `lyric_sheet_view`, `lyrics_pane`, `score_view`,
  `meta_chip`).
- `backend/` : **backend Go** de recherche en ligne (stdlib pure, zéro dépendance).
  Voir [`backend/README.md`](backend/README.md).

### Pièges connus
- Dans un `SingleChildScrollView` vertical, un `Row` avec
  `CrossAxisAlignment.stretch` doit être enveloppé d'`IntrinsicHeight` (sinon
  hauteur infinie → écran blanc). Cf. `_BarRow`.

## Recherche en ligne : backend Go + flux + cache

Le backend est en **Go** (`backend/`) et a **remplacé** l'ancienne fonction
Netlify en Node (supprimée : plus de `netlify/`, plus de `scripts/backend_cli.mjs`).
Détails complets dans [`backend/README.md`](backend/README.md) ; l'essentiel :

- **Endpoints** : `GET /health`, `GET /search/stream?q=…` (**SSE**, ce que l'app
  utilise), `GET /search?q=…` (même recherche d'un bloc, pour curl/CLI et comme
  repli). **Pas de `/representation`** : le contenu est **embarqué dans les
  résultats** (`{title,artist,source,content}` au format pivot), un seul
  aller-retour.
- **Sources** (ordre de priorité) : corpus **iReal Pro embarqué** (go:embed,
  ~1 700 standards, instantané, vraies mesures), **e-chords**, **Cifra Club**,
  **Ultimate Guitar** pour les grilles ; **LRCLIB** pour les paroles. Une source =
  un fichier dans `backend/search/sources/`. Non portée : The Session (mélodies).
- Les sources de grilles renvoient accords **+ paroles** ; le backend n'extrait
  que l'harmonie (package `chart`) — aucune parole ne sort de ces sources.
- **Flux côté app** : `RemoteCatalogService.searchStream()` rend des `SearchEvent`
  (`SearchSongs` / `SearchSourceDone` / `SearchDone`) et l'écran affiche au
  compte-gouttes. Transport SSE par import conditionnel : `EventSource` sur le
  web, réponse HTTP lue en flux (`Client.send`) sur natif. ⚠️ `EventSource`
  **reconnecte tout seul** : il faut la fermer sur `done`.
- **Cache local** (`search_cache.dart`) : une requête déjà faite est relue en
  local (contenus compris) → instantané, hors-ligne, et le backend n'est pas
  re-sollicité. 7 jours de validité, 30 requêtes gardées, bouton « actualiser »
  pour forcer le réseau. Les requêtes en cache sont proposées sur l'écran vide.
- `RUBATO_API` pointe par défaut sur `http://localhost:8091` (le backend local).
  Pour l'APK, `localhost` = le téléphone, donc viser l'IP LAN
  (`make apk RUBATO_API=http://<ip-lan>:8091`, même WiFi) ou le **backend
  déployé** (`make apk RUBATO_API=https://<app>.fly.dev`, marche partout).
- **Déploiement** : `backend/Dockerfile` + `backend/fly.toml` → **Fly.io**
  (Netlify n'exécute pas de Go, et il faut un conteneur pour avoir `curl`).
  `make api-login` / `api-create` une fois, puis `make api-deploy` ; `api-status`,
  `api-logs`, `api-url` pour vérifier, `api-image-run` pour tester l'image de prod
  en local. Machine en veille automatique (démarrage à froid ~1 s). Détails,
  coûts et limites : [`backend/README.md`](backend/README.md).

## Représentations & contenu

- **Grille** : `assets/charts/<id>.json` (`{key,time,sections:[{label,bars:[{chords:[…]}]}]}`).
- **Paroles** : `assets/lyrics/<id>.pro` (**ChordPro**, accords entre crochets).
  Récupérables via **LRCLIB** (bouton dans la vue) et **conservées en local**
  (fichier `.pro` sur Android, `localStorage` sur web). Permission INTERNET dans le
  manifest principal.
- **Mélodie** : `assets/scores/<id>.abc` (**notation ABC**, rendue par **abcjs**
  embarqué hors-ligne dans `assets/abcjs/`, dans une WebView `webview_flutter`).
  Rendu real book : une portée clef de sol + accords au-dessus. Fiabilité surtout
  sur l'APK Android (WebView).

## Droit d'auteur — RÈGLE IMPORTANTE

**Ne jamais reproduire de paroles ni de mélodies sous droits** (Claude ne peut pas
en être la source). Les grilles d'accords (harmonie) sont OK. Les démos embarquées
(blues `blues-in-c`) sont **originales / domaine public**. L'utilisateur ajoute
lui-même ses paroles/mélodies (fichier `.pro`/`.abc` déposé, saisi, ou récupéré via
LRCLIB) — c'est lui la source.

## Scripts (`scripts/`)

- `seed_catalog.py` : génère les 100 morceaux (jazz corrects ; soul/pop = boucles
  approximatives à affiner). ⚠️ **réécrit `catalog.json` en entier** → écrase les
  imports iReal. Détecte auto les `.pro`/`.abc` déposés. Champs `lyrics=`/`melody=`.
- `import_irealpro.py` : convertit `irealb://…` → JSON Rubato (dé-brouillage type
  pyRealParser), fusionne dans `catalog.json` en conservant paroles/mélodie
  existantes. Reprises `{ }` non dépliées. Usage : `python3 scripts/import_irealpro.py <fichier> [--dry-run] [--tags a,b]`.
- `build_ireal_corpus.py` : construit le corpus iReal Pro pré-parsé
  (`backend/search/sources/data/`), **embarqué dans le binaire Go** (go:embed) et
  servi par la source `irealpro`. Relancer le script suffit à le rafraîchir.
- `send-telegram.sh` : envoie l'APK sur Telegram (`.env` = `TELEGRAM_BOT_TOKEN`,
  `TELEGRAM_CHAT_ID`, git-ignoré).
- `make_branding.py` : génère icône + splash (`assets/branding/`, monogramme « R »
  laiton). Régénérer ensuite `dart run flutter_launcher_icons` +
  `dart run flutter_native_splash:create`.

## Réconciliation à faire (dette connue)

`seed_catalog.py` et `import_irealpro.py` écrivent tous deux `catalog.json` de façon
concurrente. Quand l'utilisateur bascule sur les vraies grilles iReal, arrêter
d'utiliser le seed pour le catalogue (ou fusionner proprement les deux flux).

# Backend Rubato (Go)

Backend de recherche en ligne en **Go, stdlib pure (`net/http`)** — pas de
framework, **aucune dépendance externe** (`go.sum` vide). Le routage par méthode
(`GET /path`) est natif depuis Go 1.22, donc Gin/Echo/… ne sont pas nécessaires.
Rien n'est installé sur l'hôte : tout passe par Docker.

C'est **le seul backend** : il a remplacé l'ancienne fonction Netlify en Node
(`netlify/functions/*.mjs`, supprimée) et c'est lui que l'app Flutter interroge
via `RUBATO_API` (par défaut `http://localhost:8091`).

## Structure

```
backend/
  main.go            point d'entrée, routeur (newRouter), handlers, CORS, mode CLI
  stream_handler.go  l'endpoint SSE /search/stream
  Dockerfile         image de production (déploiement uniquement, pas le dev)
  fly.toml           config de déploiement Fly.io
  chart/             format pivot des grilles (= JSON des assets et du codec Dart)
    chart.go         modèle Chart/Section/Bar + sérialisation
    text.go          détection d'accords, libellés, assemblage (Builder, TaggedSource)
  search/
    query.go         la requête
    result.go        les résultats par nature (grilles / paroles / mélodies)
    searcher.go      l'interface d'une source
    search.go        recherche batch + normalisation des titres
    stream.go        le flux (SearchStream) et l'agrégateur incrémental
    sources/         une source = un fichier
      fetch.go       récupération HTTP commune (via curl, cf. plus bas)
      html.go        utilitaires de scraping (entités, strip tags)
      irealcorpus.go corpus iReal Pro embarqué (go:embed data/ireal-*.json)
      echords.go     e-chords.com
      cifraclub.go   cifraclub.com.br
      ultimateguitar.go  Ultimate Guitar
      lrclib.go      LRCLIB (paroles)
      data/          le corpus iReal pré-parsé, embarqué dans le binaire
```

`newRouter()` est isolé de `main()` pour être testable sans démarrer de serveur.
Le `Dockerfile` ne sert **qu'au déploiement** : en dev, le service `backend` du
`docker-compose.yml` monte la source dans l'image officielle `golang` et fait
`go run` — rien à builder.

## Les sources

| Source           | Nature   | Comment                                                        |
|------------------|----------|----------------------------------------------------------------|
| `irealpro`       | grilles  | **corpus embarqué** (go:embed), ~1 700 standards jazz, hors-ligne, vraies mesures — répond en millisecondes |
| `echords`        | grilles  | API JSON d'e-chords, feuille « accords entre crochets »        |
| `cifraclub`      | grilles  | index Solr public + page `imprimir.html`, accords en `<b>`      |
| `ultimateguitar` | grilles  | JSON embarqué `js-store` de la page, accords `[ch]…[/ch]`       |
| `lrclib`         | paroles  | API JSON ouverte, paroles → ChordPro, un seul appel            |

Ajouter une source = un fichier dans `search/sources/` qui implémente
`search.Searcher` (`Name()` + `Search()`), plus une ligne dans `main.go`. Les
formats de feuille se partagent deux lecteurs dans `chart` : `TaggedSource`
(accords balisés : e-chords, Cifra Club) et `SectionsFromChordLines` (lignes
d'accords pures : Ultimate Guitar).

## Contrat d'API

- `GET /health` → `{"ok":true,"sources":["irealpro","echords",…]}`
- `GET /search/stream?q=…` → **le flux** (SSE), voir plus bas : c'est ce que
  l'app utilise.
- `GET /search?q=…` → la même recherche d'un seul bloc, JSON, **contenu
  embarqué** (pratique en curl / CLI ; sert aussi de repli à l'app) :

```json
{
  "chordGrids": [
    { "title": "Creep", "artist": "Radiohead", "source": "echords",
      "content": "{\"key\":\"G\",\"time\":\"4/4\",\"sections\":[…]}" }
  ],
  "lyrics": [],
  "melodies": []
}
```

Le champ `content` porte directement la représentation au **format pivot** —
grille JSON (package `chart`), ChordPro pour des paroles, ABC pour une mélodie.
Il n'y a donc **pas d'endpoint `/representation`** (contrairement au backend JS) :
un seul aller-retour suffit, l'app ajoute le morceau à sa bibliothèque sans
re-appeler le backend. En contrepartie chaque source plafonne le nombre de
morceaux dont elle récupère le contenu (3 pour les sites scrapés, un appel HTTP
chacun ; 5 pour LRCLIB et 8 pour le corpus, qui n'en coûtent aucun), pour que la
recherche reste rapide.

### `GET /search/stream` — résultats au compte-gouttes (SSE)

Les sources ne répondent pas à la même vitesse : le corpus embarqué en ~15 ms, un
site scrapé en 1 à 5 s. Attendre la plus lente pour tout afficher gâche cette
différence, d'où un flux **Server-Sent Events** : chaque source publie dès
qu'elle a fini.

```
event: result   data: {"type":"chordGrid","title":…,"artist":…,"source":…,"content":…}
event: source   data: {"source":"echords","count":1,"found":2,"ms":5032}
event: done     data: {"chordGrids":4,"lyrics":2,"melodies":0}
```

- `result` — un résultat de plus (`type` = `chordGrid` | `lyrics` | `score`) ;
- `source` — une source vient de finir : combien retenu (`count`), combien trouvé
  avant dédoublonnage (`found`), en combien de temps, et `error` si elle a
  échoué ;
- `done` — fin du flux, le serveur ferme. **Le client doit fermer aussi** :
  côté navigateur, `EventSource` se reconnecte sinon en boucle.

Pourquoi SSE plutôt que du NDJSON : c'est le seul format que le navigateur lit en
flux sans dépendance (`EventSource` est natif), et il se relit tout aussi bien
depuis Dart natif. Un seul format pour les deux plateformes.

Vu en vrai (`curl -N`), une recherche « creep radiohead » :

```
 0.00s  source   irealpro       count=0 found=0 13ms
 0.75s  result   chordGrid  Creep                        ultimateguitar
 1.02s  result   chordGrid  Creep (Acoustic)             cifraclub
 1.98s  result   lyrics     Creep                        lrclib
 5.02s  result   chordGrid  Creep (ver. 2)               echords
 5.02s  done     {"chordGrids":4,"lyrics":2,"melodies":0}
```

Le mode batch et le mode flux partagent le **même** code : `Search()` consomme
`SearchStream()` jusqu'au bout. Pas de risque de dérive entre les deux endpoints.

Un compromis à connaître : en flux, un doublon est gagné par la **première source
à répondre**, pas par la plus prioritaire — impossible d'arbitrer sans attendre
tout le monde. En pratique le corpus embarqué répond avant tous les autres.

Autres règles du contrat :
- `q` de moins de 2 caractères → `400 {"error":"q trop court"}`.
- Une source qui échoue est **loguée et ignorée** (best-effort) ; l'erreur n'est
  remontée (`502`) que si **toutes** les sources échouent.
- Un résultat sans contenu exploitable n'est pas renvoyé (l'app n'en ferait rien).
- Doublons fusionnés sur titre + artiste normalisés ; l'ordre de câblage des
  sources dans `main.go` fait la priorité.
- **CORS ouvert** (`Access-Control-Allow-Origin: *`) + réponse aux préflights
  `OPTIONS` : sans ça, le web Flutter (servi sur le port 8090) ne peut pas lire
  les réponses.

### Droit d'auteur

Les sources de **grilles** renvoient des feuilles complètes (accords **+
paroles**). Le backend n'en extrait que l'**harmonie** : aucune parole ne sort de
ces sources-là. Le format pivot le garantit structurellement (une grille n'a pas
de champ pour des paroles), et les tests le vérifient.

Les **paroles** ne viennent que de LRCLIB, en relais direct de ce que
l'utilisateur demande — comme le fait déjà le bouton « récupérer les paroles » de
la vue Paroles, qui interroge LRCLIB depuis l'app. La source, c'est LRCLIB ;
Claude n'écrit ni paroles ni mélodie (règle projet).

## Les appels sortants passent par `curl` (contournement Cloudflare)

`search/sources/fetch.go` appelle les sites via le binaire **`curl`**, pas via
`net/http`. Cloudflare bloque sur un **challenge de fingerprint TLS (JA3/JA4)** :
le ClientHello de la stdlib Go est reconnu comme bot (HTTP 403 « Just a
moment… », même en HTTP/2 et avec des en-têtes de navigateur), alors que celui de
curl (OpenSSL) passe. D'où l'image **`golang:1.24`** (Debian, embarque curl) et
non `-alpine` dans le `docker-compose.yml`.

## Commandes (depuis la racine du repo)

| Make                          | Effet                                                  |
|-------------------------------|--------------------------------------------------------|
| `make api-run`                | lance le serveur → http://localhost:8091/search        |
| `make search creep radiohead` | recherche unique, résultats affichés **au fil de l'eau** |
| `make api-search q='…'`       | recherche unique, JSON complet + trace des appels API  |
| `make api-test`               | `go test ./...`                                        |
| `make api-tidy`               | `go mod tidy`                                          |
| `make api-image-run`          | builder + lancer l'**image de prod** en local          |
| `make api-deploy`             | déployer sur Fly.io (cf. « Déploiement »)              |
| `make api-token`              | jeton de déploiement pour le secret GitHub `FLY_API_TOKEN` |
| `make api-status` / `api-logs` / `api-url` | état, logs, vérification du déployé       |

### Tester une recherche + voir les appels API

```bash
make search creep radiohead            # résumé : une ligne par résultat
make api-search q='creep radiohead'    # JSON complet (contenus inclus)
```

Les deux tournent en mode CLI (`-q`, sans démarrer le serveur) et **tracent dans
les logs du conteneur chaque requête sortante**. C'est `curlGet` (dans
`fetch.go`) qui log chaque appel :

```
→ API GET https://www.e-chords.com/api/search?only%5B%5D=songs&q=creep+radiohead&songs_take=3
← API GET https://www.e-chords.com/api/search?… → 200 (412ms)
→ API GET https://www.e-chords.com/api/song/123456/chords
← API GET https://www.e-chords.com/api/song/123456/chords → 200 (188ms)
```

Le même traçage s'applique au serveur (`make api-run`). Le serveur écoute sur
`:8080` dans le conteneur, exposé sur `8091` côté hôte (8080 pris, 8090 = web
Flutter).

## Brancher l'app dessus

`RUBATO_API` vaut `http://localhost:8091` par défaut → le web Flutter
(`make web`) marche sans rien faire, à condition que `make api-run` tourne à côté.

Pour l'**APK**, `localhost` désigne le téléphone : le défaut est donc le
**backend déployé**, seul joignable depuis un téléphone qui n'est pas sur le
WiFi de la machine.

```bash
make apk                                       # → https://<app>.fly.dev (défaut)
make apk RUBATO_API=http://192.168.1.20:8091   # backend local, même WiFi
```

`make apk` dérive l'URL du nom d'app lu dans `fly.toml` ; une surcharge en ligne
de commande gagne toujours. Le manifest Android autorise le trafic en clair
(`usesCleartextTraffic`) : inutile pour le défaut en HTTPS, nécessaire pour la
seconde forme (le backend local n'a pas de TLS).

## Déploiement (Fly.io)

Netlify n'exécute pas de Go ; le backend part donc sur **Fly.io**, qui déploie un
conteneur — ce qui tombe bien, il en faut un : le backend a besoin du binaire
`curl` à l'exécution (cf. plus haut).

Deux fichiers, et rien à installer sur l'hôte (flyctl tourne aussi en conteneur) :

- **`Dockerfile`** — image de prod : compilation dans `golang:1.24` puis binaire
  statique posé sur `debian:trixie-slim` + `curl` + certificats racine (~150 Mo).
  `trixie` est épinglé exprès : c'est la base de `golang:1.24`, donc le **même
  curl** que celui qui passe Cloudflare en dev.
- **`fly.toml`** — une machine `shared-cpu-1x` / 256 Mo à Paris (`cdg`), TLS
  forcé, **mise en veille automatique** (`auto_stop_machines`,
  `min_machines_running = 0`) et plafond de 25 requêtes simultanées.

### La première fois

```bash
make api-login     # ouvre une URL à coller dans le navigateur (jeton dans ~/.fly)
make api-create    # crée l'app « rubato-backend » (nom global → cf. plus bas)
make api-deploy    # build distant + déploiement
make api-url       # vérifie : /health puis une vraie recherche
```

Ensuite, un `make api-deploy` suffit. `make api-status` montre l'état des
machines (dont « stopped » quand ça dort), `make api-logs` suit les logs — y
compris les appels sortants tracés par `curlGet`.

`make api-login` ouvre le navigateur depuis un conteneur, ce qui peut être
pénible : un jeton créé sur le site marche aussi, `export FLY_API_TOKEN=…` avant
la commande (le Makefile le fait passer dans le conteneur).

### Déploiement automatique (push sur `develop`)

`.github/workflows/deploy-backend.yml` redéploie le backend à chaque push sur
`develop` **qui touche à `backend/`** — un commit purement Dart ne redéploie
rien. Le job vérifie le formatage, `go vet`, `go test ./...`, déploie, puis
appelle `/health` pour ne pas déclarer un succès sur un backend muet. Un
déploiement à la main reste possible depuis l'onglet Actions
(`workflow_dispatch`).

Il faut un secret **`FLY_API_TOKEN`** dans les réglages du repo GitHub. Le créer
avec un jeton de **déploiement** (portée limitée à cette app), pas un jeton de
compte :

```bash
make api-token     # affiche le jeton à copier dans les secrets GitHub
```

À savoir : ce workflow **déploie**, il ne crée pas l'app — `make api-create` reste
à faire une fois en local. Et un jeton dans les secrets GitHub donne le droit de
déployer sur ton compte facturable : `fly tokens list` / `fly tokens revoke` pour
faire le ménage.

Le nom d'app vit dans un espace de noms **global à tout Fly** — c'est lui qui
donne l'URL `https://<nom>.fly.dev`, donc les noms génériques sont souvent déjà
pris par d'autres comptes (`Name has already been taken` sur `api-create`).
Il se change dans `fly.toml` (ligne `app = …`), d'où le Makefile le relit ; le
défaut Dart de `_apiBase` doit suivre, et `make apk` prévient s'il a divergé.

### Ce qu'il faut savoir avant de déployer

- **Ce n'est pas gratuit-gratuit.** Fly a supprimé son offre gratuite pour les
  nouveaux comptes : carte bancaire à l'inscription, ~5 $ de crédit d'essai,
  facturation à la seconde. Avec la mise en veille, une machine qui ne sert que
  tes recherches coûte des centimes par mois (une machine 256 Mo *toujours*
  allumée ≈ 2 $/mois) — mais ce n'est pas zéro, et il n'y a pas de plafond dur
  côté Fly. Les alternatives sans carte (Render free, Koyeb…) endorment aussi les
  services, avec des démarrages à froid nettement plus longs.
- **Démarrage à froid** : la première recherche après une période d'inactivité
  attend le réveil de la machine (~1 s, le binaire Go démarre instantanément).
  Le cache local de l'app masque ça pour les recherches déjà faites.
- **L'API est publique et anonyme** : n'importe qui connaissant l'URL peut faire
  scraper le backend. Le plafond de concurrence limite les dégâts, mais si tu
  veux vraiment fermer la porte il faudra un jeton partagé (en-tête vérifié côté
  backend + `--dart-define` côté app). Pas fait pour l'instant.
- **IP de datacenter** : Cloudflare est plus dur avec les IP de cloud qu'avec une
  IP résidentielle. `irealpro` (embarqué) et `lrclib` sont insensibles ;
  `echords`, `cifraclub` et `ultimateguitar` peuvent se faire bloquer là où ils
  passent depuis chez toi. À vérifier avec `make api-url` / `make api-logs` après
  le premier déploiement — une source bloquée est loguée et ignorée, la recherche
  continue avec les autres.

### Tester l'image de prod sans déployer

```bash
make api-image-run      # build + run l'image finale → http://localhost:8091
```

Utile parce que le dev tourne en `go run` dans une image complète : c'est le seul
moyen de vérifier que le binaire statique et `curl` cohabitent bien dans l'image
réduite. Le backend lit `PORT` (injecté par Fly et compagnie) et retombe sur
8080.

## Le corpus iReal embarqué

`search/sources/data/ireal-{index,charts}.json` (~1,4 Mo) sont **compilés dans le
binaire** par `go:embed`. Ils sont produits par
`python3 scripts/build_ireal_corpus.py` (threads « méga-playlist » du forum iReal
Pro → parser `irealb://` de `scripts/import_irealpro.py`). Relancer le script
suffit à rafraîchir le corpus.

C'est la seule source qui donne de **vraies mesures** (plusieurs accords dans une
mesure) : les sources scrapées retombent sur la convention « une mesure = un
accord », faute de barres de mesure dans leurs feuilles.

## Sources non portées (dette assumée)

Du backend JS, il reste deux choses non portées :

- **The Session** (mélodies ABC, domaine public) — plus de mélodie dans la
  recherche en ligne ; les `.abc` déposés dans `assets/scores/` marchent toujours.
  Le contrat prévoit déjà la nature `score` : c'est une source à écrire, rien de
  plus.
- **Forum iReal Pro en direct** (grilles) — le corpus embarqué couvre le même
  besoin sans réseau ni anti-bot ; le scraping live du forum n'a pas été repris.

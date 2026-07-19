# Backend Rubato (Go)

Nouveau backend en **Go, stdlib pure (`net/http`)** — pas de framework. Le routage
par méthode (`GET /path`) est natif depuis Go 1.22, donc Gin/Echo/… ne sont pas
nécessaires ici : tout reste explicite et sans dépendance. Rien n'est installé sur
l'hôte : tout passe par Docker. Construit **pas à pas**.

## Structure

```
backend/
  main.go        point d'entrée + routeur (newRouter) + handlers
  main_test.go   tests (httptest, sans réseau)
  go.mod/go.sum  module (aucune dépendance externe → go.sum vide)
```

`newRouter()` est isolé de `main()` pour être testable sans démarrer de serveur.
Pas de Dockerfile : en dev on utilise directement l'image officielle `golang`
via le service `backend` du `docker-compose.yml` (source montée, `go run`).

## Commandes (depuis la racine du repo)

| Make            | Effet                                                       |
|-----------------|-------------------------------------------------------------|
| `make api-run`  | lance le serveur (`go run`) → http://localhost:8091/search  |
| `make api-test` | `go test ./...`                                             |
| `make api-tidy` | `go mod tidy`                                               |

Tout passe par `docker compose run --rm backend …`. Le serveur écoute sur `:8080`
dans le conteneur, exposé sur `8091` côté hôte (8080 pris, 8090 = web Flutter).

## Endpoints

- `GET /search` → `ok` (stub, à remplacer par la vraie recherche).

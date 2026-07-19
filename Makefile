# mscore — raccourcis Docker/Flutter. Rien n'est installé sur l'hôte.
# Toutes les commandes Flutter tournent dans le conteneur.

RUN  := docker compose run --rm flutter
RUNP := docker compose run --rm --service-ports flutter

# Image Node (backend Netlify) — rien n'est installé sur l'hôte.
NODE_IMAGE ?= node:24-slim

# « make search creep radiohead » : les mots après `search` forment la requête.
# Make les prend pour des cibles → on les neutralise, MAIS seulement quand la
# 1re cible est `search` (sinon on écraserait test/web/… par accident).
ifeq (search,$(firstword $(MAKECMDGOALS)))
SEARCH_QUERY := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
ifneq ($(SEARCH_QUERY),)
$(eval $(SEARCH_QUERY):;@:)
endif
endif

# Backend de recherche en ligne (fonction Netlify). Surchargeable :
#   make web  RUBATO_API=https://autre-backend.example
RUBATO_API ?= https://rubato1.netlify.app

# ── Backend Go (service `backend` du docker-compose) ─────────────────────────
# Rien sur l'hôte : Go tourne dans le conteneur compose (image officielle Go).
GOBACK  := docker compose run --rm backend
GOBACKP := docker compose run --rm --service-ports backend

.PHONY: build shell create get analyze test web apk telegram apk-telegram clean doctor backend search \
	api-run api-test api-tidy

## build   : construire l'image Docker de dev
build:
	docker compose build

## doctor  : diagnostic de l'environnement Flutter dans le conteneur
doctor:
	$(RUN) flutter doctor -v

## create  : scaffolder le projet Flutter dans le dossier courant (une fois)
create:
	$(RUN) flutter create --org com.mscore --project-name mscore \
		--platforms android,web --overwrite .

## get     : récupérer les dépendances (flutter pub get)
get:
	$(RUN) flutter pub get

## analyze : analyse statique
analyze:
	$(RUN) flutter analyze

## test    : lancer les tests
test:
	$(RUN) flutter test

## web     : lancer l'app en mode web (http://localhost:8090)
web:
	$(RUNP) flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080 \
		--dart-define=RUBATO_API=$(RUBATO_API)

## apk     : builder l'APK Android (release)
apk:
	$(RUN) flutter build apk --release --dart-define=RUBATO_API=$(RUBATO_API)

## telegram: envoyer l'APK déjà buildé sur Telegram (config dans .env)
telegram:
	$(RUN) bash scripts/send-telegram.sh

## apk-telegram : builder l'APK PUIS l'envoyer sur Telegram
apk-telegram: apk
	$(RUN) bash scripts/send-telegram.sh

## search  : recherche rapide, résultats lisibles — make search creep radiohead
search:
	@docker run --rm --init -e Q="$(SEARCH_QUERY)" \
		-v "$(CURDIR)":/app -w /app $(NODE_IMAGE) node scripts/backend_cli.mjs

## backend : tester le backend Netlify en local (Node via Docker, accès réseau réel)
##   make backend q='so what'                      → /search?q=so what (scrape live)
##   make backend route='/health'
##   make backend route='/representation?type=chordGrid&source=ultimateguitar&ref=<url-encodée>'
backend:
	docker run --rm --init -e Q="$(q)" -e ROUTE="$(route)" \
		-v "$(CURDIR)":/app -w /app $(NODE_IMAGE) node scripts/backend_cli.mjs

## api-run : lancer le backend Go (go run) → http://localhost:8091/search
api-run:
	$(GOBACKP) go run .

## api-test : lancer les tests Go
api-test:
	$(GOBACK) go test ./...

## api-tidy : go mod tidy (met à jour go.mod/go.sum, garde les fichiers à ton UID)
api-tidy:
	$(GOBACK) sh -c 'go mod tidy && chown -R $(shell id -u):$(shell id -g) /app'

## shell   : ouvrir un shell dans le conteneur
shell:
	$(RUN) bash

## clean   : nettoyer les artefacts de build
clean:
	$(RUN) flutter clean

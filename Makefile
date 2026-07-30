# mscore — raccourcis Docker/Flutter. Rien n'est installé sur l'hôte.
# Toutes les commandes Flutter tournent dans le conteneur.

RUN  := docker compose run --rm flutter
RUNP := docker compose run --rm --service-ports flutter

# « make search creep radiohead » : les mots après `search` forment la requête.
# Make les prend pour des cibles → on les neutralise, MAIS seulement quand la
# 1re cible est `search` (sinon on écraserait test/web/… par accident).
ifeq (search,$(firstword $(MAKECMDGOALS)))
SEARCH_QUERY := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
ifneq ($(SEARCH_QUERY),)
$(eval $(SEARCH_QUERY):;@:)
endif
endif

# Backend de recherche en ligne = le backend Go (dossier backend/, cible
# api-run), exposé sur le port hôte 8091. C'est le défaut pour `make web` : en
# dev on veut le backend qu'on est en train de modifier.
RUBATO_API ?= http://localhost:8091

# Pour l'**APK**, le défaut est le backend **déployé sur Fly** : sur un
# téléphone « localhost » désigne le téléphone, et l'IP LAN ne marche que sur le
# même WiFi. Variable spécifique aux cibles → une surcharge en ligne de commande
# gagne toujours, pour tester contre son backend local :
#   make apk RUBATO_API=http://192.168.1.20:8091
apk apk-telegram: RUBATO_API = https://$(FLY_APP).fly.dev

# ── Backend Go (service `backend` du docker-compose) ─────────────────────────
# Rien sur l'hôte : Go tourne dans le conteneur compose (image officielle Go).
GOBACK  := docker compose run --rm backend
GOBACKP := docker compose run --rm --service-ports backend

# ── Déploiement du backend sur Fly.io ────────────────────────────────────────
# flyctl aussi tourne en conteneur (rien sur l'hôte). Le jeton de connexion est
# gardé dans ~/.fly, monté dans le conteneur ; -it car `fly auth login` et
# `fly apps create` sont interactifs.
# Le nom d'app se change dans backend/fly.toml (source unique), on le relit ici.
FLY_APP := $(shell sed -n "s/^app *= *'\(.*\)'.*/\1/p" backend/fly.toml)
# HOME=/ : l'image flyctl est vide (un seul binaire), sans HOME elle chercherait
# sa config ailleurs que dans le /.fly qu'on monte.
FLY := docker run --rm -it -e FLY_API_TOKEN -e HOME=/ \
	-v $(HOME)/.fly:/.fly -v $(CURDIR)/backend:/app -w /app flyio/flyctl:latest

.PHONY: build shell create get analyze test web apk telegram apk-telegram clean doctor search \
	api-run api-search api-test api-tidy api-image api-image-run \
	api-login api-create api-deploy api-token api-status api-logs api-url

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
	@grep -q "https://$(FLY_APP).fly.dev" lib/src/data/remote_catalog_service.dart \
		|| echo "⚠️  le défaut Dart de _apiBase ne correspond pas au nom d'app de backend/fly.toml ($(FLY_APP))"
	$(RUN) flutter build apk --release --dart-define=RUBATO_API=$(RUBATO_API)

## telegram: envoyer l'APK déjà buildé sur Telegram (config dans .env)
telegram:
	$(RUN) bash scripts/send-telegram.sh

## apk-telegram : builder l'APK PUIS l'envoyer sur Telegram
apk-telegram: apk
	$(RUN) bash scripts/send-telegram.sh

## search  : recherche rapide via le backend Go, résultats lisibles
##   make search creep radiohead
search:
	@$(GOBACK) go run . -q "$(SEARCH_QUERY)" -short

## api-run : lancer le backend Go (go run) → http://localhost:8091/search
api-run:
	$(GOBACKP) go run .

## api-search : recherche unique via le backend Go, en traçant TOUS les appels API
##   (recherche + contenu) dans les logs du conteneur. Résultat JSON sur stdout.
##   make api-search q='creep radiohead'
api-search:
	$(GOBACK) go run . -q "$(q)"

## api-test : lancer les tests Go
api-test:
	$(GOBACK) go test ./...

## api-tidy : go mod tidy (met à jour go.mod/go.sum, garde les fichiers à ton UID)
api-tidy:
	$(GOBACK) sh -c 'go mod tidy && chown -R $(shell id -u):$(shell id -g) /app'

## api-image : builder l'image de prod (backend/Dockerfile), celle que Fly déploie
api-image:
	docker build -t rubato-backend:local backend

## api-image-run : lancer l'image de prod en local → http://localhost:8091
##   Vérifie avant déploiement que le binaire compilé + curl marchent dans
##   l'image finale (le dev, lui, tourne en `go run`).
api-image-run: api-image
	docker run --rm -p 8091:8080 rubato-backend:local

## api-login : se connecter à Fly.io (une fois ; affiche une URL à ouvrir)
api-login:
	@mkdir -p $(HOME)/.fly
	$(FLY) auth login

## api-create : créer l'app Fly « $(FLY_APP) » (une fois, avant le 1er déploiement)
##   Le nom est global chez Fly : s'il est pris, change-le dans backend/fly.toml.
api-create:
	@mkdir -p $(HOME)/.fly
	$(FLY) apps create $(FLY_APP)

## api-deploy : déployer le backend sur Fly.io (build distant, rien à installer)
api-deploy:
	@mkdir -p $(HOME)/.fly
	$(FLY) deploy --remote-only

## api-token : créer un jeton de DÉPLOIEMENT (portée = cette app, pas le compte)
##   À coller dans les secrets du repo GitHub sous le nom FLY_API_TOKEN : c'est
##   ce que lit le workflow .github/workflows/deploy-backend.yml.
api-token:
	$(FLY) tokens create deploy --name "github-actions ($(FLY_APP))"

## api-status : état de l'app déployée (machines, version, veille)
api-status:
	$(FLY) status

## api-logs : logs du backend déployé (Ctrl-C pour sortir)
api-logs:
	$(FLY) logs

## api-url : vérifier le backend déployé (santé + une recherche)
api-url:
	@echo "→ https://$(FLY_APP).fly.dev/health"
	@curl -fsS https://$(FLY_APP).fly.dev/health && echo
	@curl -fsS "https://$(FLY_APP).fly.dev/search?q=so+what" \
		| head -c 300 && echo " …"

## shell   : ouvrir un shell dans le conteneur
shell:
	$(RUN) bash

## clean   : nettoyer les artefacts de build
clean:
	$(RUN) flutter clean

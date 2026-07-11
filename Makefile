# mscore — raccourcis Docker/Flutter. Rien n'est installé sur l'hôte.
# Toutes les commandes Flutter tournent dans le conteneur.

RUN  := docker compose run --rm flutter
RUNP := docker compose run --rm --service-ports flutter

# Backend de recherche en ligne (fonction Netlify). Surchargeable :
#   make web  RUBATO_API=https://autre-backend.example
RUBATO_API ?= https://rubato1.netlify.app

.PHONY: build shell create get analyze test web apk telegram apk-telegram clean doctor

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

## shell   : ouvrir un shell dans le conteneur
shell:
	$(RUN) bash

## clean   : nettoyer les artefacts de build
clean:
	$(RUN) flutter clean

# mscore — raccourcis Docker/Flutter. Rien n'est installé sur l'hôte.
# Toutes les commandes Flutter tournent dans le conteneur.

RUN  := docker compose run --rm flutter
RUNP := docker compose run --rm --service-ports flutter

.PHONY: build shell create get analyze test web apk clean doctor

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

## web     : lancer l'app en mode web (http://localhost:8080)
web:
	$(RUNP) flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080

## apk     : builder l'APK Android (release)
apk:
	$(RUN) flutter build apk --release

## shell   : ouvrir un shell dans le conteneur
shell:
	$(RUN) bash

## clean   : nettoyer les artefacts de build
clean:
	$(RUN) flutter clean

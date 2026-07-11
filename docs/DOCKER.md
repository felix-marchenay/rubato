# Environnement de dev conteneurisé — mscore

**Rien n'est installé sur la machine hôte.** Flutter, Dart, le SDK Android et le
JDK vivent uniquement dans l'image Docker. Le code du projet est monté en volume
dans le conteneur.

## Pré-requis hôte

- Docker + `docker compose` (v2+). C'est tout.

## Image

- Base : `ghcr.io/cirruslabs/flutter:stable` (Flutter stable + SDK Android + JDK).
- Un utilisateur interne est mappé sur ton UID/GID (1001) → les fichiers générés
  dans le projet t'appartiennent, pas à `root`.
- Caches `pub` et `gradle` persistés dans des volumes Docker nommés.

## Commandes (via Makefile)

| Commande | Effet |
|----------|-------|
| `make build`   | Construit l'image de dev |
| `make doctor`  | `flutter doctor -v` dans le conteneur |
| `make create`  | Scaffolde le projet Flutter (une seule fois) |
| `make get`     | `flutter pub get` |
| `make analyze` | Analyse statique |
| `make test`    | Tests |
| `make web`     | Lance l'app en web sur http://localhost:8080 |
| `make apk`     | Build APK release |
| `make shell`   | Shell interactif dans le conteneur |
| `make clean`   | `flutter clean` |

## Voir l'app pendant le dev

Le plus simple en conteneur : la **cible web**.

```bash
make web        # puis ouvrir http://localhost:8080 dans le navigateur de l'hôte
```

Le rendu de la grille d'accords est en Flutter pur (pas de dépendance native),
donc le web reflète fidèlement ce qu'on verra sur Android.

## Builder pour Android

```bash
make apk        # génère build/app/outputs/flutter-apk/app-release.apk
```

Copier l'APK sur un appareil Android et l'installer (ou via `adb install`).

### Émulateur Android

`/dev/kvm` est présent sur l'hôte, donc un émulateur en conteneur est
techniquement possible, mais lourd (GUI, exposition X/VNC). Non mis en place
pour l'instant : on privilégie **web pour l'itération UI** et **APK sur appareil
réel** pour valider Android. À ajouter plus tard si besoin.

## Notes

- Première exécution plus lente (téléchargement des artefacts, remplissage des
  caches). Les runs suivants réutilisent les volumes.
- Si un fichier apparaît quand même en `root:root`, vérifier que l'image a bien
  été construite avec les bons `UID`/`GID` (args dans `docker-compose.yml`).

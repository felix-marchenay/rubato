# mscore

Application mobile Android (cross-platform Flutter) de **visualisation de partitions de musique**.

## Vision

Une bibliothèque de morceaux où chaque **morceau** peut être présenté sous
**plusieurs représentations** : grille d'accords, tablature, vraie partition,
PDF/scan… L'utilisateur bascule entre ces représentations selon son besoin.

Le cœur du produit, c'est ce modèle « 1 morceau → N représentations ».

La première représentation développée : une **grille d'accords style iReal Pro**
(accords dans des mesures, **sans paroles**).

## État actuel

**Squelette v0 en place** : l'app compile (web + analyse), les tests passent, un
catalogue de 4 morceaux de démo s'affiche en grille d'accords. Voir [`docs/`](docs/) :

- [`docs/SPECS.md`](docs/SPECS.md) — specs fonctionnelles & techniques
- [`docs/DATA-MODEL.md`](docs/DATA-MODEL.md) — modèle de données
- [`docs/CHORD-GRID.md`](docs/CHORD-GRID.md) — représentation grille d'accords (modèle + codec)
- [`docs/DOCKER.md`](docs/DOCKER.md) — environnement de dev conteneurisé (rien installé sur l'hôte)
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — v0 (MVP) et jalons suivants

## Périmètre v0 (MVP)

Afficher des grilles d'accords (style iReal Pro, sans paroles) issues d'un
catalogue fourni, sur téléphone et tablette Android, 100% hors-ligne.
Volontairement minimal : mesures + accords + tonalité + signature rythmique.
Pas de sections/reprises, transposition, auto-scroll ni édition pour l'instant.

## Stack

- **Flutter** (Dart) — un seul code, rendu custom adapté aux représentations musicales
- Cible : **Android** (phone + tablette), responsive
- Stockage **local** uniquement pour la v0
- **Dev 100% conteneurisé** (Docker) : rien installé sur l'hôte — voir [`docs/DOCKER.md`](docs/DOCKER.md)

## Démarrage rapide (dev)

```bash
make build     # construit l'image Flutter (une fois, plusieurs Go)
make get       # dépendances
make web       # lance l'app sur http://localhost:8080
```

## Architecture du code (`lib/src/`)

```
domain/   modèle métier pur (Song, Representation, ChordChart, Section, Bar, Chord)
codec/    (dé)sérialisation découplée : ChordChartCodec + JsonChordChartCodec + parseur
data/     CatalogRepository (charge le catalogue et les grilles depuis les assets)
ui/       écrans (bibliothèque, lecture) + widgets (rendu de la grille)
```

Le rendu et la logique ne dépendent que du **domaine** ; le format de stockage
est isolé derrière la couche `codec` (on pourra brancher un `IRealProCodec` plus
tard sans rien changer au reste).

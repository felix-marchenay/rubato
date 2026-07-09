# mscore

Application mobile Android (cross-platform Flutter) de **visualisation de partitions de musique**.

## Vision

Une bibliothèque de morceaux où chaque **morceau** peut être présenté sous
**plusieurs représentations** : grille d'accords, tablature, vraie partition,
PDF/scan… L'utilisateur bascule entre ces représentations selon son besoin.

Le cœur du produit, c'est ce modèle « 1 morceau → N représentations ».

## État actuel

Démarrage / cadrage. Voir [`docs/`](docs/) :

- [`docs/SPECS.md`](docs/SPECS.md) — specs fonctionnelles & techniques
- [`docs/DATA-MODEL.md`](docs/DATA-MODEL.md) — modèle de données
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — v0 (MVP) et jalons suivants
- [`docs/CHORDPRO.md`](docs/CHORDPRO.md) — notes sur le format ChordPro

## Périmètre v0 (MVP)

Afficher des grilles d'accords (format ChordPro) issues d'un catalogue fourni,
sur téléphone et tablette Android, 100% hors-ligne. Volontairement minimal :
pas de transposition, d'auto-scroll ni d'édition pour l'instant.

## Stack

- **Flutter** (Dart) — un seul code, rendu custom adapté aux représentations musicales
- Cible : **Android** (phone + tablette), responsive
- Stockage **local** uniquement pour la v0

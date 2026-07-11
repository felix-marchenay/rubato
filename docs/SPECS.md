# Specs — mscore

> Document vivant. Décisions prises pendant le cadrage initial (2026-07-09).

## 1. Vision produit

App de **visualisation** de partitions. Un **morceau** regroupe plusieurs
**représentations** typées entre lesquelles l'utilisateur bascule :

- grille d'accords (style iReal Pro, **sans paroles**)
- tablature
- paroles (avec accords, type ChordPro)
- vraie partition (notation)
- PDF / image scannée

C'est ce modèle « morceau → N représentations » qui différencie l'app. Le MVP
n'implémente que la représentation **grille d'accords**, mais l'architecture le
prévoit dès le départ.

## 2. Public cible

Large, à terme : musicien perso/hobby, musicien de scène/pro, contexte
prof↔élève, ensembles (chœur/orchestre). La v0 ne cible pas un segment précis :
elle pose les bases de lecture.

## 3. Décisions structurantes

| Sujet | Décision |
|-------|----------|
| Modèle | Morceau = N représentations typées (voir DATA-MODEL.md) |
| Stack | Flutter (Dart), cible Android phone + tablette |
| Rendu | Responsive phone/tablette dès le départ |
| Représentation v0 | Grille d'accords style iReal Pro, sans paroles |
| Format grille | Modèle de domaine propre + codec pluggable (JSON en v0). Vocabulaire d'accords aligné iReal Pro. Voir CHORD-GRID.md |
| Interop iReal Pro | Prévue via un codec dédié, mais plus tard (pas en v0) |
| Stockage | 100% local (v0). Cloud/sync : non tranché, plus tard |
| Contenu | Catalogue fourni + (plus tard) saisie de grilles par l'utilisateur |

## 4. Périmètre v0 (MVP) — ce qui est DEDANS

- Écran **Bibliothèque** : liste des morceaux (titre, artiste), recherche simple.
- Écran **Lecture** : affichage d'une grille d'accords (mesures + accords),
  avec tonalité et signature rythmique en tête. Disposition en grille responsive.
- **Catalogue fourni** : quelques morceaux embarqués avec l'app (notre format JSON).
- **Responsive** phone / tablette.
- **Hors-ligne** total.

## 5. Hors périmètre v0 — pour plus tard

- Sections/repères visuels (A/B, Intro/Chorus), reprises `{ }`, fins N1/N2.
- Import/export iReal Pro (via `IRealProCodec`).
- Transposition, capo.
- Auto-scroll / défilement automatique.
- Réglages de lecture (taille police, thème sombre) — au-delà des défauts.
- Édition / saisie de grilles par l'utilisateur, import de fichiers.
- Autres représentations : tablature, partition, PDF.
- Setlists, tags avancés, partage, comptes, sync cloud.
- Tourne-page Bluetooth, métronome, accordeur, playback audio.

## 6. Contraintes techniques

- Android d'abord (Flutter permet iOS plus tard sans refonte).
- Fonctionnement hors-ligne obligatoire.
- Rendu lisible sur petit écran comme sur tablette.

## 7. Questions encore ouvertes

- Nom définitif de l'app (code actuel : `mscore`).
- Stockage local : assets JSON en v0 → base (Isar/Drift) quand l'édition arrive.
- Vocabulaire d'accords exact à couvrir en v0 (jeu minimal vs large).
- Stratégie cloud/sync éventuelle (reportée).

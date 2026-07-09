# Specs — mscore

> Document vivant. Décisions prises pendant le cadrage initial (2026-07-09).

## 1. Vision produit

App de **visualisation** de partitions. Un **morceau** regroupe plusieurs
**représentations** typées entre lesquelles l'utilisateur bascule :

- grille d'accords (ChordPro)
- tablature
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
| Format grille | ChordPro standard |
| Stockage | 100% local (v0). Cloud/sync : non tranché, plus tard |
| Contenu | Catalogue fourni + (plus tard) saisie de grilles par l'utilisateur |

## 4. Périmètre v0 (MVP) — ce qui est DEDANS

- Écran **Bibliothèque** : liste des morceaux (titre, artiste), recherche simple.
- Écran **Lecture** : affichage d'une grille d'accords ChordPro mise en forme
  (accords alignés au-dessus des paroles, sections, titres).
- **Catalogue fourni** : quelques morceaux embarqués avec l'app.
- **Responsive** phone / tablette.
- **Hors-ligne** total.

## 5. Hors périmètre v0 — pour plus tard

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
- Format du catalogue embarqué (fichiers `.cho` bruts vs base pré-parsée).
- Stockage local : simples fichiers vs base (Isar/Drift/sqlite) — voir ROADMAP.
- Stratégie cloud/sync éventuelle (reportée).

# Roadmap — mscore

## v0 — MVP « lecture de grilles d'accords »

Objectif : prouver le concept et poser l'architecture « morceau → représentations ».

1. **Init projet Flutter** (structure, thème de base, cible Android phone+tablette).
2. **Modèle de domaine** `Song` / `Representation` + `ChordChart` / `Section` /
   `Bar` / `Chord` (voir DATA-MODEL.md & CHORD-GRID.md).
3. **Couche codec** : interface `ChordChartCodec` + `JsonChordChartCodec` (v0).
4. **Catalogue fourni** : `catalog.json` + charts JSON en assets, chargement.
5. **Écran Bibliothèque** : liste des morceaux + recherche simple.
6. **Écran Lecture** : rendu de la grille (mesures + accords, tonalité +
   signature rythmique en tête), responsive.
7. Finitions : icône, splash, build APK.

Critère de sortie v0 : ouvrir l'app, choisir un morceau du catalogue, lire sa
grille d'accords (mesures/accords/tonalité/rythme) correctement mise en forme,
hors-ligne, sur phone et tablette.

## v1 — Grille d'accords complète + confort de lecture

- Sections/repères (A/B, Intro/Chorus), reprises `{ }`, fins alternatives N1/N2.
- **Import iReal Pro** (`IRealProCodec`) pour amorcer le catalogue.
- Transposition (+ affichage capo).
- Auto-scroll réglable.
- Réglages : taille de police, thème sombre.

## v2 — Contenu utilisateur

- Saisie / édition de grilles ChordPro dans l'app.
- Import de fichiers `.cho`.
- Passage à une base locale (Isar/Drift) pour les données utilisateur.
- Organisation : tags, favoris, setlists.

## v3+ — Multi-représentations & au-delà

- Représentation **paroles + accords** (type ChordPro).
- Représentation **tablature**.
- Représentation **partition** (MusicXML) et/ou **PDF/image**.
- Éventuellement : sync cloud / comptes, partage, tourne-page Bluetooth,
  métronome, playback audio, iOS.

## Idées à trancher plus tard

- Nom & identité de l'app.
- Cloud/sync (backend) : oui/non, quand.
- Catalogue en ligne / téléchargeable.

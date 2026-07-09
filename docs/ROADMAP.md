# Roadmap — mscore

## v0 — MVP « lecture de grilles d'accords »

Objectif : prouver le concept et poser l'architecture « morceau → représentations ».

1. **Init projet Flutter** (structure, thème de base, cible Android phone+tablette).
2. **Modèle de données** `Song` / `Representation` (voir DATA-MODEL.md).
3. **Catalogue fourni** : quelques `.cho` + `catalog.json` en assets, chargement.
4. **Parseur ChordPro** minimal (accords `[..]`, directives `{..}`, sections).
5. **Écran Bibliothèque** : liste des morceaux + recherche simple.
6. **Écran Lecture** : rendu de la grille (accords alignés au-dessus des paroles).
7. **Responsive** phone / tablette.
8. Finitions : icône, splash, build APK.

Critère de sortie v0 : ouvrir l'app, choisir un morceau du catalogue, lire sa
grille d'accords correctement mise en forme, hors-ligne, sur phone et tablette.

## v1 — Confort de lecture

- Transposition (+ affichage capo).
- Auto-scroll réglable.
- Réglages : taille de police, thème sombre.
- Navigation par sections.

## v2 — Contenu utilisateur

- Saisie / édition de grilles ChordPro dans l'app.
- Import de fichiers `.cho`.
- Passage à une base locale (Isar/Drift) pour les données utilisateur.
- Organisation : tags, favoris, setlists.

## v3+ — Multi-représentations & au-delà

- Représentation **tablature**.
- Représentation **partition** (MusicXML) et/ou **PDF/image**.
- Éventuellement : sync cloud / comptes, partage, tourne-page Bluetooth,
  métronome, playback audio, iOS.

## Idées à trancher plus tard

- Nom & identité de l'app.
- Cloud/sync (backend) : oui/non, quand.
- Catalogue en ligne / téléchargeable.

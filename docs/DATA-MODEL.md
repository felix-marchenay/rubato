# Modèle de données — mscore

Le cœur du produit : **un morceau porte N représentations typées**.

## Entités

### Song (Morceau)
Métadonnées communes, indépendantes de la représentation.

| Champ | Type | Notes |
|-------|------|-------|
| id | String (uuid) | |
| title | String | |
| artist | String? | |
| tags | List\<String\> | genre, ambiance, capo… (v0 : optionnel) |
| representations | List\<Representation\> | 1..N |
| createdAt / updatedAt | DateTime | |

### Representation (Représentation)
Une façon de présenter le morceau. Type discriminant + contenu spécifique.

| Champ | Type | Notes |
|-------|------|-------|
| id | String (uuid) | |
| type | enum `RepresentationType` | voir ci-dessous |
| label | String? | ex: "Version capo 3", "Tab intro" |
| content | selon type | v0 : texte ChordPro |

```dart
enum RepresentationType {
  chordGrid,   // ChordPro — SEUL implémenté en v0
  tablature,   // futur
  score,       // futur (MusicXML/notation)
  pdf,         // futur
  image,       // futur
}
```

## v0 : ce qu'on code réellement

- `Song` avec au moins **une** représentation `chordGrid`.
- `chordGrid.content` = texte **ChordPro** brut ; le parsing/rendu se fait à la lecture.
- Les autres types existent dans l'enum mais ne sont ni stockés ni rendus.

## Persistance (v0)

Catalogue **fourni** et lecture seule → le plus simple :

- Option A (retenue par défaut) : fichiers `.cho` (ChordPro) + un `catalog.json`
  décrivant les morceaux et leurs représentations, embarqués dans les assets.
- Option B : base locale (Isar/Drift) — à introduire quand on ajoutera
  l'édition / l'ajout par l'utilisateur (post-v0).

Décision : **Option A pour la v0**, migration vers une base quand la saisie
utilisateur arrive.

## Évolutivité

Ajouter une représentation = ajouter une valeur d'enum + un widget de rendu
dédié + (si besoin) un parseur. Aucune refonte du modèle `Song`.

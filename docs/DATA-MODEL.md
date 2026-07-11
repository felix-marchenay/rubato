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
  chordGrid,   // grille d'accords style iReal Pro — SEUL implémenté en v0
  tablature,   // futur
  lyrics,      // futur (paroles + accords, type ChordPro)
  score,       // futur (MusicXML/notation)
  pdf,         // futur
  image,       // futur
}
```

Pour `chordGrid`, le `content` est un **`ChordChart`** (modèle de domaine
structuré, voir [CHORD-GRID.md](CHORD-GRID.md)) — PAS une chaîne de format.

## v0 : ce qu'on code réellement

- `Song` avec au moins **une** représentation `chordGrid`.
- Le contenu de `chordGrid` est un `ChordChart` structuré (sections → bars →
  chords). En v0 : mesures + accords + tonalité + signature rythmique.
- La (dé)sérialisation passe par un **codec** (`ChordChartCodec`) ; v0 =
  `JsonChordChartCodec`. Le modèle ne dépend d'aucun format.
- Les autres types existent dans l'enum mais ne sont ni stockés ni rendus.

## Persistance (v0)

Catalogue **fourni** et lecture seule → le plus simple :

- **Retenu** : assets JSON embarqués — un `catalog.json` (liste des morceaux +
  leurs représentations), les charts décodés par `JsonChordChartCodec`.
- Base locale (Isar/Drift) : introduite plus tard, quand l'édition / l'ajout
  par l'utilisateur arrive.

## Évolutivité

- Ajouter une **représentation** = valeur d'enum + widget de rendu dédié
  (+ codec si besoin). Aucune refonte de `Song`.
- Changer le **format de stockage** d'une grille = nouveau `ChordChartCodec`
  (ex. `IRealProCodec`). Aucun impact sur le rendu ni la logique.

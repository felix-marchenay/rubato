# Représentation « Grille d'accords » — mscore

Style **iReal Pro** : des accords rangés dans des **mesures**, **sans paroles**.
(Les paroles seront une *autre* représentation, plus tard.)

## Principe directeur : découplage

La donnée interne est un **modèle de domaine propre**, indépendant de tout
format texte. La (dé)sérialisation passe par une **couche codec** pluggable.
On pourra changer de format de stockage sans toucher au rendu ni à la logique.

```
Fichier/asset ──(ChordChartCodec.decode)──▶ ChordChart (domaine) ──▶ Rendu
Rendu ◀── ChordChart ◀──(ChordChartCodec.encode)── (édition, plus tard)
```

- v0 : `JsonChordChartCodec` — un JSON lisible, à nous.
- plus tard : `IRealProCodec` — import/export du format iReal Pro.
- Le reste de l'app ne dépend QUE du modèle de domaine.

## Modèle de domaine

```dart
class ChordChart {
  final String? title;        // souvent porté par le Song parent
  final MusicKey key;         // tonalité, ex: Bb
  final TimeSignature time;   // ex: 4/4
  final List<Section> sections; // v0 : au moins une section (peut être unique/implicite)
}

class Section {
  final String? label;        // "A", "Intro", "Chorus"… (non rendu en v0)
  final List<Bar> bars;
}

class Bar {
  final List<Chord> chords;   // 1..n accords dans la mesure
  final Barline open;         // futur : reprises
  final Barline close;        // futur
  final int? ending;          // futur : N1/N2
  // futur : repeatPreviousBar, etc.
}

class Chord {
  final PitchClass root;      // 0..11 (permet transposition future)
  final String quality;       // vocabulaire aligné iReal Pro (^7, -7, h7, o7, sus, alt…)
  final PitchClass? bass;     // accord slash, ex: C/E
}
```

Stocker `root` comme classe de hauteur (pas juste "C#") = transposition triviale
plus tard, indépendante du format.

## Vocabulaire des accords (aligné iReal Pro)

On reprend la sémantique documentée d'iReal Pro pour les qualités d'accords :
majeur 7 `^7`, mineur `-`, mineur 7 `-7`, demi-diminué `h7`, diminué `o7`,
`sus`, `alt`, altérations `b5/#5/b9/#9/#11/b13`, etc. `n` = N.C. (no chord).

> Réf. symboles : https://technimo.helpshift.com/hc/en/3-ireal-pro/faq/88-chord-symbols-used-in-ireal-pro/

Note : on adopte le **vocabulaire**, pas forcément la chaîne de sérialisation
iReal Pro (celle-ci est compacte/brouillée à l'export ; elle viendra via
`IRealProCodec` plus tard).

## Portée v0 (affichage)

DEDANS :
- Mesures séparées par des barres, un ou plusieurs accords par mesure.
- **Signature rythmique** (4/4, 3/4…) et **tonalité** affichées en tête.
- Disposition en **grille fixe façon iReal Pro** : mesures en cases régulières,
  N mesures par ligne (ex. 4), lisible phone + tablette.
- **Une seule grille par morceau en v0** (le modèle en autorise N, mais pas de
  sélecteur de version tant qu'on n'en a qu'une).
- **Catalogue de démo : 3–5 morceaux**, choisis pour couvrir les cas de rendu
  (plusieurs accords/mesure, tonalités variées, signatures 4/4 et 3/4).

DEHORS (modèle prévu, rendu plus tard) :
- Sections/repères visuels (A/B, Intro/Chorus).
- Reprises `{ }`, fins alternatives N1/N2, signes de répétition de mesure.
- Transposition, capo.
- Import iReal Pro.

## Réf. iReal Pro

- Protocole : https://www.irealpro.com/ireal-pro-custom-chord-chart-protocol
- Developer docs : https://www.irealpro.com/developer-docs
- Symboles d'accords : https://technimo.helpshift.com/hc/en/3-ireal-pro/faq/88-chord-symbols-used-in-ireal-pro/

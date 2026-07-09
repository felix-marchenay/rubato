# ChordPro — notes de référence

Format texte standard pour grilles d'accords. On l'adopte pour la v0.

## Principes

- Les **accords** sont entre crochets, placés dans la ligne de paroles juste
  avant la syllabe concernée : `[C]Twinkle [G]twinkle [C]little star`.
- Les **directives** sont entre accolades : `{title: ...}`, `{artist: ...}`,
  `{start_of_chorus}` / `{soc}`, `{end_of_chorus}` / `{eoc}`,
  `{start_of_verse}` / `{sov}`, `{comment: ...}` / `{c: ...}`, `{key: ...}`,
  `{capo: ...}`, `{tempo: ...}`.
- Les lignes commençant par `#` sont des commentaires (ignorés).
- Extension de fichier usuelle : `.cho` (aussi `.crd`, `.chordpro`, `.pro`).

## Exemple

```
{title: Amazing Grace}
{artist: John Newton}
{key: G}

{start_of_verse}
A[G]mazing grace how [G7]sweet the [C]sound
That [G]saved a wretch like [D]me
{end_of_verse}

{start_of_chorus}
[G]Praise the [C]Lord
{end_of_chorus}
```

## Rendu attendu (v0)

- Titre/artiste depuis les directives (fallback : nom de fichier).
- Accords affichés **au-dessus** de la syllabe correspondante, alignés.
- Sections (verse/chorus/comment) visuellement distinguées (label, léger fond).
- Police monospace ou alignement soigné pour garder l'alignement accords↔paroles.

## Parseur v0 — portée minimale

À gérer : `[accord]`, `{title}`, `{artist}`, `{key}`, `{capo}`,
`{start_of_*}`/`{end_of_*}` (verse/chorus), `{comment}`, lignes `#`.
À ignorer proprement (sans planter) : toute directive inconnue.

Ne PAS gérer en v0 : tabs `{start_of_tab}`, définitions d'accords
`{define}`, `{chorus}` (rappel), grilles rythmiques, transposition.

## Réf.

Spec : https://www.chordpro.org/

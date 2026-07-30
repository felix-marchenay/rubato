package search

// Searcher est une source de recherche. Une implémentation par source
// (e-chords, Ultimate Guitar…), rangée dans le sous-package search/sources.
//
// Search renvoie un multi-return : une liste par nature de résultat. Chaque
// liste peut être vide (nil) — soit parce que la source ne trouve rien, soit
// parce qu'elle ne fournit pas ce type de contenu.
//
// Contrat : les résultats renvoyés portent **déjà leur contenu** (champ Content
// au format pivot : grille JSON, ChordPro ou ABC). Une source qui n'arrive pas à
// récupérer le contenu d'un morceau l'omet plutôt que de renvoyer une coquille
// vide — l'app n'a rien à aller chercher ensuite.
type Searcher interface {
	// Name identifie la source (champ Source des résultats, logs, /health).
	Name() string
	Search(q Query) (grids []ChordGridResult, lyrics []LyricsResult, melodies []MelodyResult, err error)
}

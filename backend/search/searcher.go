package search

// Searcher est une source de recherche. On prévoit une implémentation par
// source (eChords, LRCLIB…), rangée dans le sous-package search/sources.
//
// Search renvoie un multi-return : une liste par nature de résultat. Chaque
// liste peut être vide (nil) — soit parce que la source ne trouve rien, soit
// parce qu'elle ne fournit pas ce type de contenu.
type Searcher interface {
	Search(q Query) (grids []ChordGridResult, lyrics []LyricsResult, melodies []MelodyResult, err error)
}

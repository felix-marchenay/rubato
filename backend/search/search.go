package search

// maxResultsPerType plafonne le nombre de résultats renvoyés par nature.
const maxResultsPerType = 10

// Engine orchestre plusieurs Searcher. Les implémentations lui sont injectées
// (c'est main qui les câble) : ainsi le package search ne dépend pas de
// search/sources, et il n'y a aucun cycle d'import.
type Engine struct {
	searchers []Searcher
}

// NewEngine crée l'orchestrateur à partir des sources fournies.
func NewEngine(searchers ...Searcher) *Engine {
	return &Engine{searchers: searchers}
}

// Search interroge chaque source, fusionne leurs résultats par nature, puis
// plafonne chaque liste à maxResultsPerType. Pas encore de logique de tri ni de
// dédoublonnage : simple concaténation.
func (e *Engine) Search(q Query) (Results, error) {
	var out Results
	for _, s := range e.searchers {
		grids, lyrics, melodies, err := s.Search(q)
		if err != nil {
			// TODO: décider de la politique d'erreur (ignorer une source qui
			// échoue et continuer, ou remonter l'erreur ?). Pour l'instant on
			// remonte.
			return out, err
		}
		out.ChordGrids = append(out.ChordGrids, grids...)
		out.Lyrics = append(out.Lyrics, lyrics...)
		out.Melodies = append(out.Melodies, melodies...)
	}
	out.ChordGrids = limit(out.ChordGrids, maxResultsPerType)
	out.Lyrics = limit(out.Lyrics, maxResultsPerType)
	out.Melodies = limit(out.Melodies, maxResultsPerType)
	return out, nil
}

// limit tronque une slice aux n premiers éléments.
func limit[T any](s []T, n int) []T {
	if len(s) > n {
		return s[:n]
	}
	return s
}

package search

import (
	"errors"
	"strings"
	"unicode"
)

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

// Sources liste les noms des sources câblées (endpoint /health).
func (e *Engine) Sources() []string {
	names := make([]string, 0, len(e.searchers))
	for _, s := range e.searchers {
		names = append(names, s.Name())
	}
	return names
}

// Search : recherche **batch** (endpoint /search). Elle consomme le flux de
// SearchStream jusqu'au bout, donc elle interroge toutes les sources en
// parallèle, dédoublonne et plafonne exactement comme le mode flux.
//
// Politique d'erreur : best-effort. Une source qui échoue est loguée et ignorée
// — les autres répondent quand même (c'était déjà le comportement du backend JS
// remplacé, indispensable avec des sources scrapées). L'erreur n'est remontée
// que si **toutes** les sources échouent : là, c'est le backend qui a un
// problème, pas une source.
func (e *Engine) Search(q Query) (Results, error) {
	agg := NewAggregator(maxResultsPerType)
	out := Results{
		ChordGrids: []ChordGridResult{},
		Lyrics:     []LyricsResult{},
		Melodies:   []MelodyResult{},
	}

	var errs []error
	for u := range e.SearchStream(q) {
		kept := agg.Accept(u)
		if u.Err != nil {
			errs = append(errs, u.Err)
			continue
		}
		out.ChordGrids = append(out.ChordGrids, kept.Grids...)
		out.Lyrics = append(out.Lyrics, kept.Lyrics...)
		out.Melodies = append(out.Melodies, kept.Melodies...)
	}
	if len(errs) > 0 && len(errs) == len(e.searchers) {
		return out, errors.Join(errs...)
	}
	return out, nil
}

// songKey normalise titre + artiste pour la comparaison : sans accents, sans
// ponctuation, sans casse (« Ain't Misbehavin' » == « aint misbehavin »).
func songKey(title, artist string) string {
	return NormalizeKey(title) + "|" + NormalizeKey(artist)
}

// NormalizeKey réduit un libellé à sa forme comparable : minuscules, sans
// accents, sans ponctuation, espaces normalisés. Exporté parce que les sources
// en ont besoin aussi (recherche dans le corpus iReal embarqué, par exemple) —
// une seule implémentation pour tout le backend.
func NormalizeKey(s string) string {
	var b strings.Builder
	for _, r := range strings.ToLower(s) {
		r = foldAccent(r)
		switch {
		case unicode.Is(unicode.Mn, r): // diacritique combinant → ignoré
		case unicode.IsLetter(r) || unicode.IsDigit(r):
			b.WriteRune(r)
		case unicode.IsSpace(r):
			b.WriteRune(' ')
		}
	}
	return strings.Join(strings.Fields(b.String()), " ")
}

// accentGroups : lettres accentuées repliées sur leur lettre de base. Table
// maison plutôt que golang.org/x/text : le backend tient à **zéro dépendance**
// (go.sum vide), et les titres de morceaux ne sortent guère du latin étendu.
var accentGroups = map[rune]string{
	'a': "àáâãäåāăą",
	'e': "èéêëēĕėęě",
	'i': "ìíîïĩīĭįı",
	'o': "òóôõöøōŏő",
	'u': "ùúûüũūŭůűų",
	'c': "çćĉċč",
	'n': "ñńņň",
	'y': "ýÿŷ",
	's': "śşšß",
	'z': "źżž",
	'd': "đð",
	'l': "ł",
	'g': "ğ",
}

var accentFolds = func() map[rune]rune {
	m := make(map[rune]rune)
	for base, accents := range accentGroups {
		for _, r := range accents {
			m[r] = base
		}
	}
	return m
}()

func foldAccent(r rune) rune {
	if base, ok := accentFolds[r]; ok {
		return base
	}
	return r
}

// dedup garde le premier résultat de chaque clé (donc la source la plus
// prioritaire, l'ordre de NewEngine étant préservé).
func dedup[T any](items []T, key func(T) string) []T {
	seen := make(map[string]bool, len(items))
	out := make([]T, 0, len(items))
	for _, it := range items {
		k := key(it)
		if seen[k] {
			continue
		}
		seen[k] = true
		out = append(out, it)
	}
	return out
}

// limit tronque une slice aux n premiers éléments.
func limit[T any](s []T, n int) []T {
	if len(s) > n {
		return s[:n]
	}
	return s
}

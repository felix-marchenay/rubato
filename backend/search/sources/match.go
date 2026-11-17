package sources

import (
	"strings"

	"rubato/search"
)

// matchesWords dit si chaque mot est le début d'un mot de fields (comparaison
// normalisée : « boheme » trouve « La Bohème », « wonderw » trouve
// « Wonderwall »). Sert aux sources dont la recherche est trop floue.
func matchesWords(words []string, fields ...string) bool {
	have := " " + search.NormalizeKey(strings.Join(fields, " "))
	for _, w := range words {
		if !strings.Contains(have, " "+w) {
			return false
		}
	}
	return true
}

// queryWords découpe une requête en mots normalisés, pour matchesWords.
func queryWords(q string) []string {
	return strings.Fields(search.NormalizeKey(q))
}

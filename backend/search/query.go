package search

// Query représente une requête de recherche. Pour l'instant une simple chaîne
// de texte ; on l'enrichira plus tard si besoin (filtres, pagination…).
type Query struct {
	Text string
}

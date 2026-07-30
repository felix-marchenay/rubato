package sources

import (
	"html"
	"regexp"
)

// Petits utilitaires de scraping partagés (portés du backend JS supprimé).

// decodeEntities décode les entités HTML (&amp;, &#39;, &#x2019;…). La stdlib
// sait le faire ; ce wrapper nomme l'intention côté scrapers. Utile aussi sur
// les titres : sans lui, « A &amp; B » finirait slugifié en « a-amp-b ».
func decodeEntities(s string) string { return html.UnescapeString(s) }

var (
	brRe    = regexp.MustCompile(`(?i)<br\s*/?>`)
	blockRe = regexp.MustCompile(`(?i)</(?:p|div|li|tr)>`)
	tagRe   = regexp.MustCompile(`<[^>]*>`)
)

// stripTags transforme un fragment HTML en texte brut en **gardant les sauts de
// ligne structurants** (<br>, fins de blocs) : ce sont eux qui portent la mise
// en page « accords au-dessus des paroles », dont dépend la détection des
// lignes d'accords.
func stripTags(h string) string {
	h = brRe.ReplaceAllString(h, "\n")
	h = blockRe.ReplaceAllString(h, "\n")
	return decodeEntities(tagRe.ReplaceAllString(h, ""))
}

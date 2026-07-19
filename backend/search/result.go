package search

// Un résultat de recherche peut être de plusieurs natures. Chaque nature a sa
// propre struct : elles partagent aujourd'hui les mêmes champs, mais restent
// distinctes pour pouvoir diverger librement (une grille d'accords n'a pas
// forcément les mêmes métadonnées qu'une mélodie ou des paroles).
//
// Le contenu est embarqué directement dans l'objet (champ Content) — léger pour
// l'instant, on ne renvoie pas juste une référence à aller chercher ensuite.

// ChordGridResult : une grille d'accords trouvée chez une source.
type ChordGridResult struct {
	Title   string `json:"title"`   // titre du morceau
	Artist  string `json:"artist"`  // interprète / auteur
	Source  string `json:"source"`  // quelle source a renvoyé ce résultat (echords…)
	Content string `json:"content"` // la grille elle-même
}

// LyricsResult : des paroles trouvées chez une source.
type LyricsResult struct {
	Title   string `json:"title"`
	Artist  string `json:"artist"`
	Source  string `json:"source"`
	Content string `json:"content"` // les paroles elles-mêmes
}

// MelodyResult : une mélodie / partition trouvée chez une source.
type MelodyResult struct {
	Title   string `json:"title"`
	Artist  string `json:"artist"`
	Source  string `json:"source"`
	Content string `json:"content"` // la mélodie elle-même
}

// Results agrège les trois natures de résultat. C'est la sortie de
// l'orchestrateur et du endpoint /search : une liste par nature, chacune
// pouvant être vide si rien n'a été trouvé.
type Results struct {
	ChordGrids []ChordGridResult `json:"chordGrids"`
	Lyrics     []LyricsResult    `json:"lyrics"`
	Melodies   []MelodyResult    `json:"melodies"`
}

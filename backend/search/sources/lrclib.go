package sources

import (
	"encoding/json"
	"fmt"
	"net/url"
	"strings"

	"rubato/search"
)

// LRCLIB (lrclib.net) — base de paroles communautaire, API JSON ouverte, sans
// clé ni scraping. C'est la source de **paroles** du backend.
//
// Un seul appel suffit : `/api/search?q=…` renvoie déjà `plainLyrics` pour
// chaque résultat, donc pas de second aller-retour pour le contenu.
//
// Droit d'auteur : le backend ne fait que **relayer** ce que l'utilisateur va
// chercher (comme le bouton « récupérer les paroles » de la vue Paroles, qui
// interroge LRCLIB en direct depuis l'app). La source, c'est LRCLIB.

const sourceLrclib = "lrclib"

// lrclibSearchURL : recherche libre (titre, artiste, ou les deux).
const lrclibSearchURL = "https://lrclib.net/api/search"

// lrclibUserAgent : LRCLIB demande un User-Agent identifiant l'application.
const lrclibUserAgent = "Rubato/0.1 (carnet d'accords personnel)"

// lrclibMaxSongs : plafond de résultats retenus.
const lrclibMaxSongs = 5

// LrclibSearcher interroge LRCLIB.
type LrclibSearcher struct{}

var _ search.Searcher = (*LrclibSearcher)(nil)

// Name identifie la source (logs, /health).
func (LrclibSearcher) Name() string { return sourceLrclib }

// Search renvoie des paroles au format **ChordPro** (le format pivot des
// paroles côté app, cf. lib/src/codec/chordpro_codec.dart) : deux directives
// d'en-tête puis le texte. LRCLIB ne fournit ni grille ni mélodie.
func (l LrclibSearcher) Search(q search.Query) (grids []search.ChordGridResult, lyrics []search.LyricsResult, melodies []search.MelodyResult, err error) {
	params := url.Values{}
	params.Set("q", q.Text)

	body, err := curlGet(lrclibSearchURL+"?"+params.Encode(),
		"Accept: application/json",
		"User-Agent: "+lrclibUserAgent)
	if err != nil {
		return nil, nil, nil, fmt.Errorf("lrclib: recherche : %w", err)
	}

	tracks, err := parseLrclibSearch(body)
	if err != nil {
		return nil, nil, nil, err
	}

	for _, t := range tracks {
		if len(lyrics) >= lrclibMaxSongs {
			break
		}
		content := lrclibChordPro(t)
		if content == "" {
			continue
		}
		lyrics = append(lyrics, search.LyricsResult{
			Title:   strings.TrimSpace(t.TrackName),
			Artist:  strings.TrimSpace(t.ArtistName),
			Source:  sourceLrclib,
			Content: content,
		})
	}
	return nil, lyrics, nil, nil
}

// lrclibTrack : champs exploités d'un résultat LRCLIB.
type lrclibTrack struct {
	ID           int    `json:"id"`
	TrackName    string `json:"trackName"`
	ArtistName   string `json:"artistName"`
	Instrumental bool   `json:"instrumental"`
	PlainLyrics  string `json:"plainLyrics"`
}

// parseLrclibSearch décode la réponse (un tableau) et écarte ce qui n'a pas de
// paroles utilisables : morceaux instrumentaux, entrées vides.
func parseLrclibSearch(body []byte) ([]lrclibTrack, error) {
	var all []lrclibTrack
	if err := json.Unmarshal(body, &all); err != nil {
		return nil, fmt.Errorf("lrclib: JSON invalide : %w", err)
	}
	var out []lrclibTrack
	for _, t := range all {
		if t.Instrumental || strings.TrimSpace(t.TrackName) == "" ||
			strings.TrimSpace(t.PlainLyrics) == "" {
			continue
		}
		// LRCLIB est alimenté par des clients variés : certaines entrées ont la
		// requête recopiée dans tous les champs (« radiohead creep » comme titre
		// ET comme artiste). Inexploitable pour identifier un morceau.
		if search.NormalizeKey(t.TrackName) == search.NormalizeKey(t.ArtistName) {
			continue
		}
		out = append(out, t)
	}
	return out, nil
}

// lrclibChordPro habille les paroles en ChordPro : le titre et l'artiste en
// directives, puis le texte tel quel (LRCLIB ne fournit pas d'accords).
func lrclibChordPro(t lrclibTrack) string {
	plain := strings.TrimSpace(t.PlainLyrics)
	if plain == "" {
		return ""
	}
	var b strings.Builder
	fmt.Fprintf(&b, "{title: %s}\n", strings.TrimSpace(t.TrackName))
	if a := strings.TrimSpace(t.ArtistName); a != "" {
		fmt.Fprintf(&b, "{artist: %s}\n", a)
	}
	b.WriteString("\n")
	b.WriteString(plain)
	b.WriteString("\n")
	return b.String()
}

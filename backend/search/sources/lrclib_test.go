package sources

import (
	"strings"
	"testing"
)

// Fixture synthétique : pas de vraies paroles dans le repo, on ne teste que le
// filtrage et la mise au format ChordPro.
const lrclibJSON = `[
  {"id":1,"trackName":"Demo","artistName":"Untel","instrumental":false,"plainLyrics":"ligne une\nligne deux"},
  {"id":2,"trackName":"Instrumental","artistName":"Untel","instrumental":true,"plainLyrics":""},
  {"id":3,"trackName":"Sans paroles","artistName":"Untel","instrumental":false,"plainLyrics":"   "},
  {"id":4,"trackName":"untel demo","artistName":"untel demo","instrumental":false,"plainLyrics":"recopie de la requete"}
]`

// Trois entrées sur quatre sont inexploitables : instrumentale, vide, et celle
// dont le titre est recopié dans l'artiste (LRCLIB est communautaire).
func TestParseLrclibSearch(t *testing.T) {
	tracks, err := parseLrclibSearch([]byte(lrclibJSON))
	if err != nil {
		t.Fatalf("parseLrclibSearch : %v", err)
	}
	if len(tracks) != 1 {
		t.Fatalf("nb tracks = %d, want 1 (%+v)", len(tracks), tracks)
	}
	if tracks[0].TrackName != "Demo" {
		t.Errorf("track = %+v, want Demo", tracks[0])
	}
}

// Le contenu doit être du ChordPro : directives d'en-tête puis le texte.
func TestLrclibChordPro(t *testing.T) {
	got := lrclibChordPro(lrclibTrack{
		TrackName: "Demo", ArtistName: "Untel", PlainLyrics: "ligne une\nligne deux",
	})
	want := "{title: Demo}\n{artist: Untel}\n\nligne une\nligne deux\n"
	if got != want {
		t.Errorf("ChordPro =\n%q\nwant\n%q", got, want)
	}

	// Sans artiste, pas de directive vide.
	got = lrclibChordPro(lrclibTrack{TrackName: "Demo", PlainLyrics: "x"})
	if strings.Contains(got, "{artist:") {
		t.Errorf("ChordPro = %q, want sans directive artist", got)
	}

	// Sans paroles, pas de contenu du tout (le résultat sera écarté).
	if got := lrclibChordPro(lrclibTrack{TrackName: "Demo"}); got != "" {
		t.Errorf("ChordPro = %q, want vide", got)
	}
}

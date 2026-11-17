package sources

import (
	"strings"
	"testing"
)

const songsterrSearchJSON = `[
  {"songId":1,"title":"Demo","artist":"Untel","hasChords":true},
  {"songId":2,"title":"Demo (Fingerstyle)","artist":"Untel","hasChords":false},
  {"songId":3,"title":"demo","artist":"UNTEL","hasChords":true},
  {"songId":4,"title":"Autre","artist":"Untel","hasChords":true}
]`

func TestParseSongsterrSearch(t *testing.T) {
	songs, err := parseSongsterrSearch([]byte(songsterrSearchJSON), "untel")
	if err != nil {
		t.Fatalf("parseSongsterrSearch : %v", err)
	}
	if len(songs) != 2 || songs[0].ID != 1 || songs[1].ID != 4 {
		t.Fatalf("songs = %+v, want les IDs 1 et 4 (sans accords et doublon écartés)", songs)
	}
	// Les autres titres de l'artiste ne collent pas à la requête.
	songs, _ = parseSongsterrSearch([]byte(songsterrSearchJSON), "demo untel")
	if len(songs) != 1 || songs[0].ID != 1 {
		t.Errorf("songs = %+v, want le seul ID 1", songs)
	}
}

func TestSongsterrSlug(t *testing.T) {
	if got := songsterrSlug(songsterrSong{Artist: "Guns N' Roses", Title: "Don't Cry (Alt.)"}); got != "guns-n-roses-don-t-cry-alt" {
		t.Errorf("slug = %q", got)
	}
}

func songsterrChordJSON(base, first, suffix string) string {
	return `{"type":"chord","chord":{"baseNote":{"name":"` + base + `"},"firstNote":{"name":"` + first +
		`"},"chordType":{"suffix":"` + suffix + `"}}}`
}

// Paroles bidon, comme toutes les fixtures du repo.
var songsterrPage = `<html><head><script id="state" type="application/json">{"chordpro":{"current":[` +
	`{"type":"tuning","text":"Standard (EADGBE)"},` +
	`{"type":"section","text":"Intro"},` +
	`{"type":"line","line":[` + songsterrChordJSON("G", "G", "") + `,{"type":"noise","text":"  "},` + songsterrChordJSON("D", "F#", "") + `]},` +
	`{"type":"line","line":[]},` +
	`{"type":"section","text":"Verse"},` +
	`{"type":"line","line":[{"type":"text","text":"blabla "},` + songsterrChordJSON("A", "A", "m7") + `,{"type":"text","text":"bla"}]},` +
	`{"type":"line","line":[{"type":"text","text":"blabla sans accord"}]},` +
	`{"type":"line","line":[` + songsterrChordJSON("C", "C", "add9") + `]}` +
	`]}}</script></head></html>`

func TestSongsterrChart(t *testing.T) {
	c, ok := songsterrChart([]byte(songsterrPage))
	if !ok {
		t.Fatal("songsterrChart = ok false, want true")
	}
	if len(c.Sections) != 2 {
		t.Fatalf("nb sections = %d, want 2 (%+v)", len(c.Sections), c.Sections)
	}
	intro, verse := c.Sections[0], c.Sections[1]
	if intro.Label != "Intro" || len(intro.Bars) != 2 || intro.Bars[1].Chords[0] != "D/F#" {
		t.Errorf("intro = %+v, want Intro : G | D/F#", intro)
	}
	// Une ligne de paroles sans accord ne coupe pas la section.
	if verse.Label != "Verse" || len(verse.Bars) != 2 || verse.Bars[0].Chords[0] != "Am7" || verse.Bars[1].Chords[0] != "Cadd9" {
		t.Errorf("verse = %+v, want Verse : Am7 | Cadd9", verse)
	}

	js, err := c.JSON()
	if err != nil {
		t.Fatalf("JSON : %v", err)
	}
	if strings.Contains(js, "blabla") {
		t.Errorf("la grille contient des paroles : %s", js)
	}
}

func TestSongsterrChartWithoutState(t *testing.T) {
	if _, ok := songsterrChart([]byte("<html>rien</html>")); ok {
		t.Error("songsterrChart = ok true, want false")
	}
	empty := `<script id="state" type="application/json">{"chordpro":{"current":null}}</script>`
	if _, ok := songsterrChart([]byte(empty)); ok {
		t.Error("songsterrChart sans feuille = ok true, want false")
	}
}

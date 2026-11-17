package sources

import (
	"reflect"
	"testing"

	"rubato/chart"
)

func TestParseTheSessionSearch(t *testing.T) {
	body := `{"tunes":[
	  {"id":1,"name":"The Creep","type":"hornpipe"},
	  {"id":2,"name":"Demo Reel","alias":"","type":"reel"},
	  {"id":3,"name":"Autre","alias":"Demo Reel","type":"jig"}
	]}`
	tunes, err := parseTheSessionSearch([]byte(body), "demo reel")
	if err != nil {
		t.Fatalf("parseTheSessionSearch : %v", err)
	}
	if len(tunes) != 2 || tunes[0].ID != 2 || tunes[1].ID != 3 {
		t.Errorf("tunes = %+v, want 2 et 3 (nom ou alias)", tunes)
	}
	tunes, _ = parseTheSessionSearch([]byte(body), "creep radiohead")
	if len(tunes) != 0 {
		t.Errorf("tunes = %+v, want aucun (recherche floue du site)", tunes)
	}
}

func TestTheSessionKey(t *testing.T) {
	for in, want := range map[string]string{
		"Edorian": "Em", "Gmajor": "G", "Bbmixolydian": "Bb", "F#minor": "F#m", "": "",
	} {
		if got := theSessionKey(in); got != want {
			t.Errorf("theSessionKey(%q) = %q, want %q", in, got, want)
		}
	}
}

func chordsOf(s chart.Section) [][]string {
	var out [][]string
	for _, b := range s.Bars {
		out = append(out, b.Chords)
	}
	return out
}

// Air synthétique au format The Session (« ! » = saut de ligne) : levée,
// reprise avec 1re/2de fin, accord en milieu de mesure, annotation, mesure
// sans accord qui reprend le précédent.
func TestABCChart(t *testing.T) {
	abc := `D|:"Em"E2E "D"DDD|EEE "slide"FFF|1 "Em"GGG GGG:|2 "C"AAA "D"BBB||! ` +
		`|:"G"ccc ccc|ddd "Am7"eee|"D/F#"fff fff:|`
	c, ok := abcChart(abc, "Em", "6/8")
	if !ok {
		t.Fatal("abcChart = ok false, want true")
	}
	if c.Key != "Em" || c.Time != "6/8" {
		t.Errorf("key/time = %q %q", c.Key, c.Time)
	}
	if len(c.Sections) != 2 || c.Sections[0].Label != "A" || c.Sections[1].Label != "B" {
		t.Fatalf("sections = %+v, want A et B", c.Sections)
	}
	wantA := [][]string{{"Em", "D"}, {"D"}, {"Em"}, {"C", "D"}}
	if got := chordsOf(c.Sections[0]); !reflect.DeepEqual(got, wantA) {
		t.Errorf("A = %q, want %q", got, wantA)
	}
	wantB := [][]string{{"G"}, {"G", "Am7"}, {"D/F#"}}
	if got := chordsOf(c.Sections[1]); !reflect.DeepEqual(got, wantB) {
		t.Errorf("B = %q, want %q", got, wantB)
	}
}

// Une version sans accords (ou dont une partie n'en a pas) ne doit pas
// produire une grille faite d'un accord répété.
func TestABCChartWithoutChords(t *testing.T) {
	if _, ok := abcChart(`|:EEE FFF|GGG AAA:|`, "", ""); ok {
		t.Error("abcChart sans accords = ok true, want false")
	}
	c, ok := abcChart(`|:"G"GGG|"D"AAA:||:BBB|ccc:|`, "", "")
	if !ok || len(c.Sections) != 1 {
		t.Errorf("sections = %+v, want la seule partie harmonisée", c.Sections)
	}
}

package chart

import "testing"

func TestIsChord(t *testing.T) {
	chords := []string{"C", "Am", "F#m7", "Bb", "C/E", "Dm7", "G7sus4", "Cmaj7", "N.C.", "%"}
	for _, c := range chords {
		if !IsChord(c) {
			t.Errorf("IsChord(%q) = false, want true", c)
		}
	}
	// Des mots de paroles ne doivent jamais passer pour des accords — « Ah » et
	// « Am » se ressemblent beaucoup, d'où la qualité strictement composée de
	// caractères d'accord (pas de « h », qui est pourtant le ø d'iReal : ce
	// vocabulaire-là n'existe pas chez les sources scrapées).
	words := []string{"", "When", "let", "trouble", "Mother", "wisdom", "be", "and", "a", "Ah", "Do", "Cause"}
	for _, w := range words {
		if IsChord(w) {
			t.Errorf("IsChord(%q) = true, want false", w)
		}
	}
}

func TestLabel(t *testing.T) {
	cases := map[string]string{
		"[Verse 1]": "Verse 1",
		"[Intro]":   "Intro",
		"Refrain:":  "Refrain",
		"Chorus":    "Chorus",
		"A":         "A", // les grilles jazz nomment leurs sections d'une lettre
		"B:":        "B",
	}
	for line, want := range cases {
		got, ok := Label(line)
		if !ok || got != want {
			t.Errorf("Label(%q) = (%q, %v), want (%q, true)", line, got, ok, want)
		}
	}
	if _, ok := Label("When I find myself in times of trouble"); ok {
		t.Error("une ligne de paroles ne doit pas être prise pour un en-tête")
	}
	// Un accord que IsChord ne sait pas lire ne doit pas devenir un libellé
	// (« F#7/13b » commence par une lettre de note : piège classique).
	for _, line := range []string{"F#7/13b", "Gm7(11)", "Bb13sus"} {
		if l, ok := Label(line); ok {
			t.Errorf("Label(%q) = %q, want aucun libellé", line, l)
		}
	}
}

// Format « accords au-dessus des paroles » (Ultimate Guitar après nettoyage) :
// on garde l'harmonie, on jette les paroles, et un couplet reste UN bloc — les
// lignes de paroles ne coupent pas la section, seules les lignes vides le font.
func TestSectionsFromChordLines(t *testing.T) {
	text := "[Intro]\nC G Am F\n\n[Verse 1]\n  C        G\nune ligne de paroles\n  Am       F\nune autre ligne\n"

	sections := SectionsFromChordLines(text)
	if len(sections) != 2 {
		t.Fatalf("nb sections = %d, want 2 (%+v)", len(sections), sections)
	}
	if sections[0].Label != "Intro" || len(sections[0].Bars) != 4 {
		t.Errorf("section 0 = %+v, want Intro avec 4 mesures", sections[0])
	}
	if sections[1].Label != "Verse 1" || len(sections[1].Bars) != 4 {
		t.Errorf("section 1 = %+v, want « Verse 1 » avec 4 mesures", sections[1])
	}
	if got := sections[0].Bars[0].Chords; len(got) != 1 || got[0] != "C" {
		t.Errorf("mesure 0 = %v, want [C]", got)
	}
}

func TestNewDropsEmptySections(t *testing.T) {
	sections := []Section{
		{Label: "vide"},
		{Label: "A", Bars: []Bar{{Chords: []string{"C"}}}},
	}
	c, ok := New(sections, "C", "")
	if !ok {
		t.Fatal("New = ok false, want true")
	}
	if len(c.Sections) != 1 || c.Sections[0].Label != "A" {
		t.Errorf("sections = %+v, want la seule section non vide", c.Sections)
	}
	if c.Time != DefaultTime || c.Key != "C" {
		t.Errorf("key/time = %q/%q, want C/%s", c.Key, c.Time, DefaultTime)
	}

	if _, ok := New([]Section{{Label: "vide"}}, "", ""); ok {
		t.Error("New sur des sections vides doit renvoyer ok=false")
	}
}

// Le JSON produit doit être exactement le format pivot attendu par le codec Dart.
func TestChartJSON(t *testing.T) {
	c, _ := New([]Section{{Label: "A", Bars: []Bar{{Chords: []string{"C"}}}}}, "Dm", "3/4")
	got, err := c.JSON()
	if err != nil {
		t.Fatalf("JSON : %v", err)
	}
	want := `{"key":"Dm","time":"3/4","sections":[{"label":"A","bars":[{"chords":["C"]}]}]}`
	if got != want {
		t.Errorf("JSON =\n%s\nwant\n%s", got, want)
	}
}

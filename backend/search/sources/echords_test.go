package sources

import (
	"os"
	"strings"
	"testing"
)

// TestParseEchordsSearch vérifie l'extraction des chansons à partir d'une vraie
// réponse d'e-chords (requête « jean jacques goldman »), figée dans
// testdata/echords_search.json. On contrôle aussi l'ID et le slug d'instrument,
// indispensables au fetch du contenu.
func TestParseEchordsSearch(t *testing.T) {
	body, err := os.ReadFile("testdata/echords_search.json")
	if err != nil {
		t.Fatalf("lecture fixture : %v", err)
	}

	songs, err := parseEchordsSearch(body)
	if err != nil {
		t.Fatalf("parseEchordsSearch : %v", err)
	}

	// La fixture contient 5 chansons (doublons compris : on ne dédoublonne pas).
	if len(songs) != 5 {
		t.Fatalf("nb songs = %d, want 5", len(songs))
	}

	first := songs[0]
	if first.Title != "Je Te Donne" {
		t.Errorf("Title = %q, want %q", first.Title, "Je Te Donne")
	}
	if first.Artist != "Jean Jacques Goldman" {
		t.Errorf("Artist = %q, want %q", first.Artist, "Jean Jacques Goldman")
	}
	if first.ID != 239532 {
		t.Errorf("ID = %d, want %d", first.ID, 239532)
	}
	// Le slug de contenu doit privilégier « chords » (guitare).
	if got := first.contentSlug(); got != "chords" {
		t.Errorf("contentSlug() = %q, want %q", got, "chords")
	}
}

// TestContentSlug couvre le choix de l'instrument pour l'URL du contenu.
func TestContentSlug(t *testing.T) {
	// « chords » est prioritaire même s'il n'est pas en tête.
	withChords := echordsSong{Instruments: []echordsInstrument{
		{Slug: "ukulele"}, {Slug: "chords"},
	}}
	if got := withChords.contentSlug(); got != "chords" {
		t.Errorf("contentSlug() = %q, want %q", got, "chords")
	}

	// Sans « chords », on retombe sur le premier instrument disponible.
	noChords := echordsSong{Instruments: []echordsInstrument{
		{Slug: "ukulele"}, {Slug: "keyboards"},
	}}
	if got := noChords.contentSlug(); got != "ukulele" {
		t.Errorf("contentSlug() = %q, want %q", got, "ukulele")
	}

	// Aucun instrument → slug vide.
	if got := (echordsSong{}).contentSlug(); got != "" {
		t.Errorf("contentSlug() = %q, want vide", got)
	}
}

// TestParseEchordsContent vérifie l'extraction de la feuille (chord.MUSICA) et
// de la tonalité. Fixture synthétique volontairement (pas de vraies paroles →
// pas de souci de droits d'auteur) : on ne teste que le parsing.
func TestParseEchordsContent(t *testing.T) {
	body := []byte(`{"id":1,"title":"Demo","default_key":"C",` +
		`"chord":{"MUSICA":"[C] la la [G] la","ACORDES_PADROES":"C,G"}}`)

	sheet, key, err := parseEchordsContent(body)
	if err != nil {
		t.Fatalf("parseEchordsContent : %v", err)
	}
	if sheet != "[C] la la [G] la" {
		t.Errorf("sheet = %q, want %q", sheet, "[C] la la [G] la")
	}
	if key != "C" {
		t.Errorf("key = %q, want %q", key, "C")
	}
}

// TestDedupEchordsSongs : la recherche d'e-chords renvoie régulièrement deux
// fois le même morceau — inutile de payer deux fetchs de contenu.
func TestDedupEchordsSongs(t *testing.T) {
	got := dedupEchordsSongs([]echordsSong{{ID: 1}, {ID: 2}, {ID: 1}})
	if len(got) != 2 || got[0].ID != 1 || got[1].ID != 2 {
		t.Errorf("dedupEchordsSongs = %+v, want [1 2]", got)
	}
}

// TestEchordsChart : conversion d'une feuille e-chords vers le format pivot.
// Les libellés viennent des balises (<i>…</i>, pseudo-balises maison) et
// **seuls les accords sont retenus** : la ligne de paroles synthétique de la
// fixture ne doit apparaître nulle part dans la grille.
func TestEchordsChart(t *testing.T) {
	sheet := "<i>Intro</i> [C] [G] [Am] [F]\r\n\r\n<V1>\r\n" +
		"   [C]              [G]\r\nblabla bla blabla\r\n   [Am]      [F]\r\nencore du blabla\r\n</V1>"

	c, ok := echordsChart(sheet, "C")
	if !ok {
		t.Fatal("echordsChart = ok false, want true")
	}
	if c.Key != "C" || c.Time != "4/4" {
		t.Errorf("key/time = %q/%q, want C/4/4", c.Key, c.Time)
	}
	if len(c.Sections) != 2 {
		t.Fatalf("nb sections = %d, want 2 (%+v)", len(c.Sections), c.Sections)
	}
	if c.Sections[0].Label != "Intro" || len(c.Sections[0].Bars) != 4 {
		t.Errorf("section 0 = %+v, want Intro avec 4 mesures", c.Sections[0])
	}
	if c.Sections[1].Label != "V1" || len(c.Sections[1].Bars) != 4 {
		t.Errorf("section 1 = %+v, want V1 avec 4 mesures", c.Sections[1])
	}

	js, err := c.JSON()
	if err != nil {
		t.Fatalf("JSON : %v", err)
	}
	if strings.Contains(js, "blabla") {
		t.Errorf("la grille contient des paroles : %s", js)
	}
}

// Une feuille sans aucun accord ne doit pas produire de grille (l'app n'en
// ferait rien) : ok=false, et la source ignore le morceau.
func TestEchordsChartWithoutChords(t *testing.T) {
	if _, ok := echordsChart("juste du texte\nsans accords\n", ""); ok {
		t.Error("echordsChart = ok true, want false")
	}
}

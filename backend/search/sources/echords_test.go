package sources

import (
	"os"
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

// TestParseEchordsContent vérifie l'extraction de la feuille (chord.MUSICA).
// Fixture synthétique volontairement (pas de vraies paroles → pas de souci de
// droits d'auteur) : on ne teste que le parsing.
func TestParseEchordsContent(t *testing.T) {
	body := []byte(`{"id":1,"title":"Demo","chord":{"MUSICA":"[C] la la [G] la","ACORDES_PADROES":"C,G"}}`)

	content, err := parseEchordsContent(body)
	if err != nil {
		t.Fatalf("parseEchordsContent : %v", err)
	}
	if content != "[C] la la [G] la" {
		t.Errorf("content = %q, want %q", content, "[C] la la [G] la")
	}
}

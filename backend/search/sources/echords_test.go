package sources

import (
	"os"
	"testing"
)

// TestParseEchordsSearch vérifie le mapping à partir d'une vraie réponse d'e-chords
// (requête « jean jacques goldman »), figée dans testdata/echords_search.json.
func TestParseEchordsSearch(t *testing.T) {
	body, err := os.ReadFile("testdata/echords_search.json")
	if err != nil {
		t.Fatalf("lecture fixture : %v", err)
	}

	grids, lyrics, melodies, err := parseEchordsSearch(body)
	if err != nil {
		t.Fatalf("parseEchordsSearch : %v", err)
	}

	// La fixture contient 5 chansons (doublons compris : on ne dédoublonne pas).
	if len(grids) != 5 {
		t.Fatalf("nb grilles = %d, want 5", len(grids))
	}
	// L'endpoint search ne fournit ni paroles ni mélodies.
	if len(lyrics) != 0 || len(melodies) != 0 {
		t.Fatalf("lyrics=%d melodies=%d, want 0/0", len(lyrics), len(melodies))
	}

	// Premier résultat : contrôle des champs mappés.
	first := grids[0]
	if first.Title != "Je Te Donne" {
		t.Errorf("Title = %q, want %q", first.Title, "Je Te Donne")
	}
	if first.Artist != "Jean Jacques Goldman" {
		t.Errorf("Artist = %q, want %q", first.Artist, "Jean Jacques Goldman")
	}
	if first.Source != sourceEchords {
		t.Errorf("Source = %q, want %q", first.Source, sourceEchords)
	}
	// Le contenu n'est pas fourni par l'endpoint search.
	if first.Content != "" {
		t.Errorf("Content = %q, want vide", first.Content)
	}

	// Toutes les grilles doivent porter la source echords et un titre non vide.
	for i, g := range grids {
		if g.Source != sourceEchords {
			t.Errorf("grids[%d].Source = %q, want %q", i, g.Source, sourceEchords)
		}
		if g.Title == "" {
			t.Errorf("grids[%d].Title vide", i)
		}
	}
}

package sources

import (
	"encoding/json"
	"testing"

	"rubato/chart"
	"rubato/search"
)

// Le corpus est embarqué dans le binaire : ce test travaille sur les vraies
// données, sans réseau. Il vérifie du même coup que les fichiers embarqués sont
// bien là et bien formés (une erreur ici = une erreur de build).
func TestIRealCorpusSearch(t *testing.T) {
	grids, lyrics, melodies, err := IRealCorpusSearcher{}.Search(search.Query{Text: "so what"})
	if err != nil {
		t.Fatalf("Search : %v", err)
	}
	if len(lyrics) != 0 || len(melodies) != 0 {
		t.Errorf("le corpus ne fournit que des grilles (got %d paroles, %d mélodies)",
			len(lyrics), len(melodies))
	}
	if len(grids) == 0 {
		t.Fatal("aucune grille pour « so what »")
	}

	g := grids[0]
	if g.Source != sourceIRealCorpus {
		t.Errorf("source = %q, want %q", g.Source, sourceIRealCorpus)
	}
	// Le contenu doit être une grille au format pivot, directement décodable.
	var c chart.Chart
	if err := json.Unmarshal([]byte(g.Content), &c); err != nil {
		t.Fatalf("contenu non décodable : %v (%q)", err, g.Content)
	}
	if len(c.Sections) == 0 || c.Bars() == 0 {
		t.Errorf("grille vide : %+v", c)
	}
}

// Tous les mots de la requête doivent être présents, dans n'importe quel ordre —
// « so what miles » trouve « So What » de « Davis Miles ».
func TestIRealCorpusMatchesWordsInAnyOrder(t *testing.T) {
	grids, _, _, err := IRealCorpusSearcher{}.Search(search.Query{Text: "so what miles"})
	if err != nil {
		t.Fatalf("Search : %v", err)
	}
	if len(grids) == 0 {
		t.Fatal("aucune grille pour « so what miles »")
	}
	if grids[0].Title != "So What" {
		t.Errorf("premier résultat = %q, want « So What »", grids[0].Title)
	}
}

func TestIRealCorpusEmptyQuery(t *testing.T) {
	grids, _, _, err := IRealCorpusSearcher{}.Search(search.Query{Text: "  "})
	if err != nil || len(grids) != 0 {
		t.Errorf("Search(vide) = %d grilles, %v ; want 0, nil", len(grids), err)
	}
}

func TestContainsAll(t *testing.T) {
	if !containsAll("so what davis miles", []string{"so", "miles"}) {
		t.Error("containsAll = false, want true")
	}
	if containsAll("so what davis miles", []string{"so", "coltrane"}) {
		t.Error("containsAll = true, want false")
	}
}

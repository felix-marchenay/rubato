package search

import (
	"errors"
	"testing"
	"time"
)

// slowStub : une source qui met un certain temps à répondre, pour vérifier que
// le flux délivre les rapides sans attendre les lentes.
type slowStub struct {
	name  string
	delay time.Duration
	grids []ChordGridResult
	err   error
}

func (s slowStub) Name() string { return s.name }
func (s slowStub) Search(Query) ([]ChordGridResult, []LyricsResult, []MelodyResult, error) {
	time.Sleep(s.delay)
	return s.grids, nil, nil, s.err
}

// Le flux délivre un Update par source, la plus rapide en premier, puis se ferme.
func TestSearchStreamDeliversFastestFirst(t *testing.T) {
	e := NewEngine(
		slowStub{name: "lente", delay: 80 * time.Millisecond,
			grids: []ChordGridResult{grid("Lente", "X", "lente")}},
		slowStub{name: "rapide", grids: []ChordGridResult{grid("Rapide", "X", "rapide")}},
	)

	var order []string
	for u := range e.SearchStream(Query{Text: "x"}) {
		order = append(order, u.Source)
	}
	if len(order) != 2 {
		t.Fatalf("updates = %v, want 2", order)
	}
	if order[0] != "rapide" {
		t.Errorf("ordre = %v, want la source rapide en premier", order)
	}
}

// L'agrégateur garde tout, y compris un morceau déjà rapporté par une autre
// source, et au-delà de 10 résultats.
func TestAggregatorKeepsEverything(t *testing.T) {
	agg := NewAggregator()
	agg.Accept(Update{Source: "a", Grids: []ChordGridResult{grid("Creep", "Radiohead", "a")}})

	var many []ChordGridResult
	for range 12 {
		many = append(many, grid("Creep", "Radiohead", "b"))
	}
	if kept := agg.Accept(Update{Source: "b", Grids: many}); len(kept.Grids) != 12 {
		t.Errorf("retenues = %d, want 12", len(kept.Grids))
	}
	if g, _, _ := agg.Totals(); g != 13 {
		t.Errorf("total grilles = %d, want 13", g)
	}
}

// Une source en échec ne rapporte rien mais n'interrompt pas le flux.
func TestAggregatorIgnoresFailedUpdate(t *testing.T) {
	agg := NewAggregator()
	kept := agg.Accept(Update{Source: "ko", Err: errors.New("réseau")})
	if kept.Count() != 0 || kept.Err == nil {
		t.Errorf("kept = %+v, want 0 résultat et l'erreur conservée", kept)
	}
}

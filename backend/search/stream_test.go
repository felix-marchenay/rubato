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

// L'agrégateur dédoublonne au fil de l'eau : le même morceau arrivé deux fois
// n'est retenu qu'une fois, et seule la première occurrence est renvoyée.
func TestAggregatorDedupsAcrossUpdates(t *testing.T) {
	agg := NewAggregator(10)

	first := agg.Accept(Update{Source: "a", Grids: []ChordGridResult{
		grid("Ain't Misbehavin'", "Fats Waller", "a"),
	}})
	if len(first.Grids) != 1 {
		t.Fatalf("premier update : %d grille(s), want 1", len(first.Grids))
	}

	second := agg.Accept(Update{Source: "b", Grids: []ChordGridResult{
		grid("aint misbehavin", "FATS WALLER", "b"), // même morceau, écrit autrement
		grid("Autre", "Untel", "b"),
	}})
	if len(second.Grids) != 1 || second.Grids[0].Title != "Autre" {
		t.Fatalf("second update = %+v, want seulement « Autre »", second.Grids)
	}

	if g, _, _ := agg.Totals(); g != 2 {
		t.Errorf("total grilles = %d, want 2", g)
	}
}

// Le plafond par nature s'applique aussi en flux.
func TestAggregatorCaps(t *testing.T) {
	agg := NewAggregator(2)
	kept := agg.Accept(Update{Source: "a", Grids: []ChordGridResult{
		grid("Un", "X", "a"), grid("Deux", "X", "a"), grid("Trois", "X", "a"),
	}})
	if len(kept.Grids) != 2 {
		t.Errorf("retenues = %d, want 2 (plafond)", len(kept.Grids))
	}
}

// Une source en échec ne rapporte rien mais n'interrompt pas le flux.
func TestAggregatorIgnoresFailedUpdate(t *testing.T) {
	agg := NewAggregator(10)
	kept := agg.Accept(Update{Source: "ko", Err: errors.New("réseau")})
	if kept.Count() != 0 || kept.Err == nil {
		t.Errorf("kept = %+v, want 0 résultat et l'erreur conservée", kept)
	}
}

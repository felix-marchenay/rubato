package search

import (
	"errors"
	"testing"
)

type stub struct {
	name   string
	grids  []ChordGridResult
	lyrics []LyricsResult
	err    error
}

func (s stub) Name() string { return s.name }
func (s stub) Search(Query) ([]ChordGridResult, []LyricsResult, []MelodyResult, error) {
	return s.grids, s.lyrics, nil, s.err
}

func grid(title, artist, source string) ChordGridResult {
	return ChordGridResult{Title: title, Artist: artist, Source: source, Content: "{}"}
}

// Une source qui échoue ne doit pas emporter la recherche : les autres répondent.
func TestSearchIsBestEffort(t *testing.T) {
	e := NewEngine(
		stub{name: "ko", err: errors.New("réseau")},
		stub{name: "ok", grids: []ChordGridResult{grid("So What", "Miles Davis", "ok")}},
	)

	res, err := e.Search(Query{Text: "so what"})
	if err != nil {
		t.Fatalf("Search : %v", err)
	}
	if len(res.ChordGrids) != 1 || res.ChordGrids[0].Source != "ok" {
		t.Fatalf("grilles = %+v, want celle de la source « ok »", res.ChordGrids)
	}
}

// En revanche, si TOUTES les sources échouent, c'est une erreur (→ 502).
func TestSearchFailsWhenEverySourceFails(t *testing.T) {
	e := NewEngine(
		stub{name: "a", err: errors.New("boum")},
		stub{name: "b", err: errors.New("badaboum")},
	)
	if _, err := e.Search(Query{Text: "x"}); err == nil {
		t.Fatal("Search = nil, want une erreur")
	}
}

// Le même morceau chez deux sources ne doit apparaître qu'une fois, et c'est la
// source la plus prioritaire (ordre de NewEngine) qui gagne.
func TestSearchDedupsBySongPriorityToFirstSource(t *testing.T) {
	e := NewEngine(
		stub{name: "premiere", grids: []ChordGridResult{grid("Ain't Misbehavin'", "Fats Waller", "premiere")}},
		stub{name: "seconde", grids: []ChordGridResult{
			grid("aint misbehavin", "FATS WALLER", "seconde"), // même morceau, écrit autrement
			grid("Épistrophy", "Thelonious Monk", "seconde"),
		}},
	)

	res, err := e.Search(Query{Text: "x"})
	if err != nil {
		t.Fatalf("Search : %v", err)
	}
	if len(res.ChordGrids) != 2 {
		t.Fatalf("nb grilles = %d, want 2 (%+v)", len(res.ChordGrids), res.ChordGrids)
	}
	if res.ChordGrids[0].Source != "premiere" {
		t.Errorf("source retenue = %q, want « premiere »", res.ChordGrids[0].Source)
	}
}

func TestNormalizeKey(t *testing.T) {
	cases := [][2]string{
		{"Ain't Misbehavin'", "aint misbehavin"},
		{"  Épistrophy  ", "epistrophy"},
		{"Blue in Green (take 2)", "blue in green take 2"},
	}
	for _, c := range cases {
		if got := NormalizeKey(c[0]); got != c[1] {
			t.Errorf("NormalizeKey(%q) = %q, want %q", c[0], got, c[1])
		}
	}
}

func TestSourcesLists(t *testing.T) {
	e := NewEngine(stub{name: "echords"}, stub{name: "ultimateguitar"})
	got := e.Sources()
	if len(got) != 2 || got[0] != "echords" || got[1] != "ultimateguitar" {
		t.Errorf("Sources() = %v", got)
	}
}

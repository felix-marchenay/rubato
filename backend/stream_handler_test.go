package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"rubato/search"
)

// lyricsSource : une source de paroles, pour vérifier que le flux transporte les
// trois natures de résultat avec le bon `type`.
type lyricsSource struct{ name string }

func (l lyricsSource) Name() string { return l.name }
func (l lyricsSource) Search(search.Query) ([]search.ChordGridResult, []search.LyricsResult, []search.MelodyResult, error) {
	return nil, []search.LyricsResult{
		{Title: "Demo", Artist: "Untel", Source: l.name, Content: "{title: Demo}\n\nla la"},
	}, nil, nil
}

// Le flux SSE doit livrer : un `result` par nouveauté, un `source` par source, et
// un `done` final — dans un format que le client sait relire.
func TestSearchStreamSSE(t *testing.T) {
	engine := search.NewEngine(
		fakeSource{name: "grilles", grids: []search.ChordGridResult{
			{Title: "So What", Artist: "Miles Davis", Source: "grilles", Content: `{"sections":[]}`},
		}},
		lyricsSource{name: "paroles"},
	)

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/search/stream?q=so+what", nil)
	newRouter(engine).ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", w.Code, http.StatusOK)
	}
	if ct := w.Header().Get("Content-Type"); !strings.HasPrefix(ct, "text/event-stream") {
		t.Fatalf("Content-Type = %q, want text/event-stream", ct)
	}

	events := parseSSE(t, w.Body.String())

	var results, sources int
	var done map[string]any
	types := map[string]bool{}
	for _, ev := range events {
		switch ev.name {
		case "result":
			results++
			types[ev.data["type"].(string)] = true
			if ev.data["content"] == "" {
				t.Errorf("result sans contenu : %+v", ev.data)
			}
		case "source":
			sources++
		case "done":
			done = ev.data
		}
	}

	if results != 2 {
		t.Errorf("nb result = %d, want 2", results)
	}
	if !types["chordGrid"] || !types["lyrics"] {
		t.Errorf("types reçus = %v, want chordGrid + lyrics", types)
	}
	if sources != 2 {
		t.Errorf("nb source = %d, want 2 (une par source)", sources)
	}
	if done == nil {
		t.Fatal("pas d'événement done")
	}
	if done["chordGrids"] != 1.0 || done["lyrics"] != 1.0 {
		t.Errorf("done = %v, want 1 grille + 1 paroles", done)
	}
	// `done` doit être le dernier : c'est lui qui dit au client de fermer.
	if events[len(events)-1].name != "done" {
		t.Errorf("dernier événement = %q, want done", events[len(events)-1].name)
	}
}

func TestSearchStreamRejectsShortQuery(t *testing.T) {
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/search/stream?q=a", nil)
	newRouter(search.NewEngine()).ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want %d", w.Code, http.StatusBadRequest)
	}
}

// --- Lecture des trames SSE (côté test) ------------------------------------

type sseFrame struct {
	name string
	data map[string]any
}

// parseSSE relit le flux : des blocs « event: X \n data: {...} », séparés par une
// ligne vide.
func parseSSE(t *testing.T, body string) []sseFrame {
	t.Helper()
	var out []sseFrame
	for _, block := range strings.Split(strings.TrimSpace(body), "\n\n") {
		var f sseFrame
		for _, line := range strings.Split(block, "\n") {
			switch {
			case strings.HasPrefix(line, "event: "):
				f.name = strings.TrimPrefix(line, "event: ")
			case strings.HasPrefix(line, "data: "):
				if err := json.Unmarshal([]byte(strings.TrimPrefix(line, "data: ")), &f.data); err != nil {
					t.Fatalf("data non-JSON dans %q : %v", block, err)
				}
			}
		}
		if f.name != "" {
			out = append(out, f)
		}
	}
	if len(out) == 0 {
		t.Fatalf("aucune trame SSE dans %q", body)
	}
	return out
}

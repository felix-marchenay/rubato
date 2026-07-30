package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"rubato/search"
)

// fakeSource : source de test, sans réseau.
type fakeSource struct {
	name  string
	grids []search.ChordGridResult
}

func (f fakeSource) Name() string { return f.name }
func (f fakeSource) Search(search.Query) ([]search.ChordGridResult, []search.LyricsResult, []search.MelodyResult, error) {
	return f.grids, nil, nil, nil
}

func testRouter(searchers ...search.Searcher) http.Handler {
	return newRouter(search.NewEngine(searchers...))
}

func TestSearchReturnsJSON(t *testing.T) {
	src := fakeSource{name: "fake", grids: []search.ChordGridResult{
		{Title: "So What", Artist: "Miles Davis", Source: "fake", Content: `{"sections":[]}`},
	}}

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/search?q=so+what", nil)
	testRouter(src).ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", w.Code, http.StatusOK)
	}

	var results search.Results
	if err := json.Unmarshal(w.Body.Bytes(), &results); err != nil {
		t.Fatalf("réponse non-JSON : %v (body = %q)", err, w.Body.String())
	}
	if len(results.ChordGrids) != 1 || results.ChordGrids[0].Content == "" {
		t.Fatalf("grilles = %+v, want 1 grille avec contenu", results.ChordGrids)
	}
	// Le web Flutter est servi sur un autre port : sans CORS, il ne peut pas lire
	// la réponse.
	if got := w.Header().Get("Access-Control-Allow-Origin"); got != "*" {
		t.Errorf("Access-Control-Allow-Origin = %q, want %q", got, "*")
	}
}

// Une requête trop courte ne doit pas déclencher de scraping.
func TestSearchRejectsShortQuery(t *testing.T) {
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/search?q=+a+", nil)
	testRouter().ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want %d", w.Code, http.StatusBadRequest)
	}
}

// Le routage par méthode (Go 1.22+) doit refuser POST sur /search.
func TestSearchRejectsWrongMethod(t *testing.T) {
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/search", nil)
	testRouter().ServeHTTP(w, req)

	if w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status = %d, want %d", w.Code, http.StatusMethodNotAllowed)
	}
}

func TestHealthListsSources(t *testing.T) {
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	testRouter(fakeSource{name: "echords"}, fakeSource{name: "ultimateguitar"}).ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", w.Code, http.StatusOK)
	}
	var body struct {
		OK      bool     `json:"ok"`
		Sources []string `json:"sources"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatalf("réponse non-JSON : %v", err)
	}
	if !body.OK || len(body.Sources) != 2 || body.Sources[0] != "echords" {
		t.Fatalf("body = %+v, want ok + 2 sources", body)
	}
}

// Préflight CORS : le navigateur envoie OPTIONS avant un GET cross-origin.
func TestPreflight(t *testing.T) {
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodOptions, "/search", nil)
	testRouter().ServeHTTP(w, req)

	if w.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want %d", w.Code, http.StatusNoContent)
	}
}

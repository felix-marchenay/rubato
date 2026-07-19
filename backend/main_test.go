package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"rubato/search"
)

// testRouter construit un routeur avec un engine sans aucune source : la
// recherche renvoie donc des listes vides (mais bien un JSON valide).
func testRouter() http.Handler {
	return newRouter(search.NewEngine())
}

func TestSearchReturnsJSON(t *testing.T) {
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/search?q=so+what", nil)
	testRouter().ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", w.Code, http.StatusOK)
	}

	var results search.Results
	if err := json.Unmarshal(w.Body.Bytes(), &results); err != nil {
		t.Fatalf("réponse non-JSON : %v (body = %q)", err, w.Body.String())
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

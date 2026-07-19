// Backend Rubato en Go — stdlib pure (net/http), sans framework. Pour l'instant
// un seul endpoint /search. On construit l'architecture pas à pas.
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"time"

	"rubato/search"
	"rubato/search/sources"
)

// listenAddr : ":8080" = 0.0.0.0:8080, joignable depuis l'extérieur du conteneur.
const listenAddr = ":8080"

func main() {
	// On câble ici les sources de recherche. Une seule pour l'instant.
	engine := search.NewEngine(sources.EchordsSearcher{})

	srv := &http.Server{
		Addr:              listenAddr,
		Handler:           newRouter(engine),
		ReadHeaderTimeout: 5 * time.Second, // garde-fou anti slow-loris
	}
	log.Printf("Rubato backend à l'écoute sur %s", listenAddr)
	if err := srv.ListenAndServe(); err != nil {
		log.Fatalf("serveur arrêté : %v", err)
	}
}

// newRouter configure le routeur. Isolé de main() pour être testable sans
// démarrer de serveur. Routage par méthode « GET /path » = Go 1.22+.
func newRouter(engine *search.Engine) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /search", handleSearch(engine))
	return logging(mux)
}

// handleSearch interroge l'engine avec le paramètre ?q= et renvoie les
// résultats en JSON.
func handleSearch(engine *search.Engine) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		q := search.Query{Text: r.URL.Query().Get("q")}

		results, err := engine.Search(q)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		if err := json.NewEncoder(w).Encode(results); err != nil {
			log.Printf("encodage JSON : %v", err)
		}
	}
}

// logging : middleware minimal (méthode, chemin, statut, durée) — remplace
// gin.Logger(). À enrichir plus tard (recovery, request-id…) si besoin.
func logging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		log.Printf("%s %s → %d (%s)", r.Method, r.URL.Path, rec.status, time.Since(start))
	})
}

// statusRecorder capture le code de statut pour le log.
type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

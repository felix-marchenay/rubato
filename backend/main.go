// Backend Rubato en Go — stdlib pure (net/http), sans framework. Il remplace
// l'ancien backend JS (fonction Netlify) : c'est lui que l'app Flutter
// interroge, via RUBATO_API (par défaut http://localhost:8091).
//
// Endpoints : GET /health, GET /search?q=… (batch),
// GET /search/stream?q=… (SSE, résultats au compte-gouttes — cf. stream_handler.go)
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"rubato/search"
	"rubato/search/sources"
)

// defaultPort : le conteneur écoute sur 8080 (exposé sur 8091 côté hôte par le
// docker-compose ; 8080 est pris et 8090 sert au web Flutter).
const defaultPort = "8080"

// listenAddr renvoie l'adresse d'écoute : ":8080" = 0.0.0.0:8080, joignable
// depuis l'extérieur du conteneur. PORT est honoré parce que les hébergeurs
// (Fly.io, Render, Cloud Run…) l'injectent pour dire où écouter.
func listenAddr() string {
	if p := strings.TrimSpace(os.Getenv("PORT")); p != "" {
		return ":" + p
	}
	return ":" + defaultPort
}

// minQueryLen : en dessous, on refuse la recherche (une lettre ferait scraper
// toutes les sources pour rien).
const minQueryLen = 2

func main() {
	// Mode CLI : `-q "…"` lance une seule recherche puis quitte (sans serveur).
	// Pratique pour tester en voyant tous les appels API dans les logs.
	q := flag.String("q", "", "lance une recherche unique puis affiche le résultat et quitte")
	short := flag.Bool("short", false, "avec -q : résumé lisible au lieu du JSON complet")
	flag.Parse()

	// On câble ici les sources de recherche. L'ordre est l'ordre de priorité en
	// cas de doublon : le corpus iReal embarqué d'abord (instantané, vraies
	// mesures), puis les sources scrapées de grilles, puis les paroles. Les
	// appels API sortants sont logués par curlGet, en mode serveur comme en CLI.
	engine := search.NewEngine(
		sources.IRealCorpusSearcher{},
		sources.EchordsSearcher{},
		sources.CifraClubSearcher{},
		sources.UltimateGuitarSearcher{},
		sources.LrclibSearcher{},
	)

	if *q != "" {
		runSearchCLI(engine, *q, *short)
		return
	}

	addr := listenAddr()
	srv := &http.Server{
		Addr:              addr,
		Handler:           newRouter(engine),
		ReadHeaderTimeout: 5 * time.Second, // garde-fou anti slow-loris
	}
	log.Printf("Rubato backend à l'écoute sur %s (sources : %s)",
		addr, strings.Join(engine.Sources(), ", "))
	if err := srv.ListenAndServe(); err != nil {
		log.Fatalf("serveur arrêté : %v", err)
	}
}

// runSearchCLI exécute une recherche unique et laisse curlGet tracer les appels
// API dans les logs. C'est la commande de test : `make api-search q='…'` (JSON
// complet) et `make search creep radiohead` (résumé au fil de l'eau, -short).
func runSearchCLI(engine *search.Engine, q string, short bool) {
	log.Printf("recherche CLI : %q", q)

	if short {
		renderStream(engine, q)
		return
	}

	results, err := engine.Search(search.Query{Text: q})
	if err != nil {
		log.Fatalf("recherche : %v", err)
	}

	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	if err := enc.Encode(results); err != nil {
		log.Fatalf("encodage JSON : %v", err)
	}
	log.Printf("recherche CLI terminée : %d grille(s), %d paroles, %d mélodie(s)",
		len(results.ChordGrids), len(results.Lyrics), len(results.Melodies))
}

// renderStream consomme le **flux** de recherche et écrit chaque résultat dès
// qu'il arrive : c'est la façon de voir le compte-gouttes sans navigateur (mêmes
// événements que /search/stream, autre habillage).
func renderStream(engine *search.Engine, q string) {
	fmt.Printf("\n« %s »\n\n", q)

	line := func(kind, title, artist, source, content string) {
		label := title
		if artist != "" {
			label += " — " + artist
		}
		fmt.Printf("  %-8s %-44s %-14s %6d o\n", kind, truncate(label, 44), source, len(content))
	}

	agg := search.NewAggregator(0)
	for u := range engine.SearchStream(search.Query{Text: q}) {
		kept := agg.Accept(u)
		for _, g := range kept.Grids {
			line("grille", g.Title, g.Artist, g.Source, g.Content)
		}
		for _, l := range kept.Lyrics {
			line("paroles", l.Title, l.Artist, l.Source, l.Content)
		}
		for _, m := range kept.Melodies {
			line("mélodie", m.Title, m.Artist, m.Source, m.Content)
		}
		status := fmt.Sprintf("%d retenu(s) sur %d", kept.Count(), u.Count())
		if u.Err != nil {
			status = "échec : " + u.Err.Error()
		}
		fmt.Printf("  ── %-14s %s en %s\n", u.Source, status, u.Elapsed.Round(time.Millisecond))
	}

	grids, lyrics, melodies := agg.Totals()
	fmt.Printf("\n  total : %d grille(s), %d paroles, %d mélodie(s)\n\n", grids, lyrics, melodies)
}

func truncate(s string, n int) string {
	rs := []rune(s)
	if len(rs) <= n {
		return s
	}
	return string(rs[:n-1]) + "…"
}

// newRouter configure le routeur. Isolé de main() pour être testable sans
// démarrer de serveur. Routage par méthode « GET /path » = Go 1.22+.
func newRouter(engine *search.Engine) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", handleHealth(engine))
	mux.HandleFunc("GET /search", handleSearch(engine))
	mux.HandleFunc("GET /search/stream", handleSearchStream(engine))
	return logging(cors(mux))
}

// handleHealth : sonde de vie + sources câblées (utile pour vérifier d'un curl
// que le backend visé par l'app est bien celui qu'on croit).
func handleHealth(engine *search.Engine) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{
			"ok":      true,
			"sources": engine.Sources(),
		})
	}
}

// queryParam lit et valide le paramètre ?q=. Si la requête est trop courte, il
// répond lui-même 400 et renvoie ok=false (le handler n'a plus qu'à sortir).
func queryParam(w http.ResponseWriter, r *http.Request) (string, bool) {
	q := strings.TrimSpace(r.URL.Query().Get("q"))
	if len([]rune(q)) < minQueryLen {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "q trop court"})
		return "", false
	}
	return q, true
}

// handleSearch interroge l'engine avec le paramètre ?q= et renvoie les résultats
// en JSON (contenus inclus), d'un seul bloc. Pour l'affichage au compte-gouttes,
// voir /search/stream.
func handleSearch(engine *search.Engine) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		q, ok := queryParam(w, r)
		if !ok {
			return
		}

		results, err := engine.Search(search.Query{Text: q})
		if err != nil {
			// Toutes les sources ont échoué : c'est un problème en amont, pas une
			// requête invalide → 502 comme faisait le backend JS.
			log.Printf("recherche %q : %v", q, err)
			writeJSON(w, http.StatusBadGateway, map[string]any{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, results)
	}
}

// writeJSON écrit une réponse JSON UTF-8 avec le statut demandé.
func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(body); err != nil {
		log.Printf("encodage JSON : %v", err)
	}
}

// cors autorise les appels depuis le web Flutter (servi sur un autre port :
// localhost:8090 en dev), et répond aux préflights. Même politique que la
// fonction Netlify remplacée : API publique en lecture seule.
func cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("Access-Control-Allow-Origin", "*")
		h.Set("Access-Control-Allow-Methods", "GET, OPTIONS")
		h.Set("Access-Control-Allow-Headers", "*")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// logging : middleware minimal (méthode, chemin, statut, durée).
func logging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		log.Printf("%s %s → %d (%s)", r.Method, r.URL.RequestURI(), rec.status, time.Since(start))
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

// Flush : indispensable. Sans ce passe-plat, l'enveloppe masquerait le
// http.Flusher du ResponseWriter et le flux SSE ne partirait qu'à la fin —
// c'est-à-dire plus de flux du tout.
func (r *statusRecorder) Flush() {
	if f, ok := r.ResponseWriter.(http.Flusher); ok {
		f.Flush()
	}
}

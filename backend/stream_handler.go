package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"

	"rubato/search"
)

// Endpoint de recherche **en flux** : `GET /search/stream?q=…`, en
// Server-Sent Events (SSE). Le client affiche les résultats au fur et à mesure
// au lieu d'attendre la source la plus lente.
//
// Pourquoi SSE et pas du NDJSON : c'est le seul format que le navigateur sait
// lire en flux **sans dépendance** (EventSource est natif), et il se lit tout
// aussi bien depuis Dart natif (on parse les trames à la main). Un seul format
// pour les deux plateformes.
//
// Trois types d'événements :
//
//	event: result   data: {"type":"chordGrid","title":…,"artist":…,"source":…,"content":…}
//	event: source   data: {"source":"echords","count":2,"ms":412,"error":null}
//	event: done     data: {"chordGrids":3,"lyrics":2,"melodies":0}
//
// `result` arrive au compte-gouttes ; `source` clôt une source (compteur, durée,
// erreur éventuelle) ; `done` termine le flux. La connexion est ensuite fermée :
// le client ne doit pas se reconnecter (côté web, EventSource reconnecte
// automatiquement → il faut appeler close() sur `done`).

// sseEvent : une trame SSE prête à écrire.
type sseEvent struct {
	name string
	data any
}

// handleSearchStream diffuse les résultats en SSE au fil des réponses des
// sources.
func handleSearchStream(engine *search.Engine) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		q, ok := queryParam(w, r)
		if !ok {
			return
		}

		flusher, canFlush := w.(http.Flusher)
		if !canFlush {
			// Sans flush, le flux n'aurait aucun intérêt (tout arriverait d'un
			// bloc à la fin) : autant le dire clairement.
			writeJSON(w, http.StatusInternalServerError,
				map[string]any{"error": "flux non supporté par le serveur"})
			return
		}

		h := w.Header()
		h.Set("Content-Type", "text/event-stream; charset=utf-8")
		h.Set("Cache-Control", "no-cache")
		h.Set("Connection", "keep-alive")
		h.Set("X-Accel-Buffering", "no") // au cas où un proxy s'intercale
		w.WriteHeader(http.StatusOK)
		flusher.Flush()

		send := func(ev sseEvent) bool {
			payload, err := json.Marshal(ev.data)
			if err != nil {
				log.Printf("SSE : encodage de %s : %v", ev.name, err)
				return true // on continue : un événement perdu n'arrête pas le flux
			}
			if _, err := fmt.Fprintf(w, "event: %s\ndata: %s\n\n", ev.name, payload); err != nil {
				return false // client parti
			}
			flusher.Flush()
			return true
		}

		agg := search.NewAggregator(0)
		updates := engine.SearchStream(search.Query{Text: q})

		for {
			select {
			case <-r.Context().Done():
				// Client déconnecté (recherche annulée, page fermée) : on arrête
				// d'écrire. Les sources en vol finiront dans le vide, sans fuite
				// (le canal est tamponné et fermé par SearchStream).
				log.Printf("SSE : client parti, flux interrompu (q=%q)", q)
				return

			case u, open := <-updates:
				if !open {
					grids, lyrics, melodies := agg.Totals()
					send(sseEvent{"done", map[string]any{
						"chordGrids": grids, "lyrics": lyrics, "melodies": melodies,
					}})
					return
				}

				kept := agg.Accept(u)
				for _, ev := range resultEvents(kept) {
					if !send(ev) {
						return
					}
				}
				if !send(sourceEvent(u, kept)) {
					return
				}
			}
		}
	}
}

// resultEvents transforme les nouveautés d'un Update en événements `result`.
// Le champ `type` reprend le vocabulaire de l'app (`RepresentationType`).
func resultEvents(kept search.Update) []sseEvent {
	var out []sseEvent
	for _, g := range kept.Grids {
		out = append(out, sseEvent{"result", map[string]any{
			"type": "chordGrid", "title": g.Title, "artist": g.Artist,
			"source": g.Source, "content": g.Content,
		}})
	}
	for _, l := range kept.Lyrics {
		out = append(out, sseEvent{"result", map[string]any{
			"type": "lyrics", "title": l.Title, "artist": l.Artist,
			"source": l.Source, "content": l.Content,
		}})
	}
	for _, m := range kept.Melodies {
		out = append(out, sseEvent{"result", map[string]any{
			"type": "score", "title": m.Title, "artist": m.Artist,
			"source": m.Source, "content": m.Content,
		}})
	}
	return out
}

// sourceEvent clôt une source : combien de résultats retenus, en combien de
// temps, et l'erreur si elle a échoué. C'est ce qui permet à l'app d'afficher
// « e-chords ✓ 2 · cifraclub … » pendant la recherche.
func sourceEvent(u, kept search.Update) sseEvent {
	data := map[string]any{
		"source": u.Source,
		"count":  kept.Count(),
		"found":  u.Count(), // avant dédoublonnage
		"ms":     u.Elapsed.Milliseconds(),
	}
	if u.Err != nil {
		data["error"] = u.Err.Error()
	}
	return sseEvent{"source", data}
}

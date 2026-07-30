package search

import (
	"fmt"
	"log"
	"sync"
	"time"
)

// Recherche en flux : chaque source est interrogée dans sa propre goroutine et
// publie son Update **dès qu'elle a fini**, sans attendre les autres. C'est ce
// qui permet à l'app d'afficher les résultats au compte-gouttes (le corpus iReal
// embarqué répond en microsecondes, un site scrapé en quelques secondes).
//
// Search() (recherche batch, endpoint /search) est construite sur ce même flux :
// un seul chemin de code, donc pas de dérive entre les deux endpoints.

// Update : ce qu'une source a produit. Soit des résultats, soit une erreur.
type Update struct {
	Source   string // nom de la source
	Grids    []ChordGridResult
	Lyrics   []LyricsResult
	Melodies []MelodyResult
	Err      error         // non nil = source en échec (les autres continuent)
	Elapsed  time.Duration // temps de réponse de la source
}

// Count : nombre de résultats portés par l'update.
func (u Update) Count() int { return len(u.Grids) + len(u.Lyrics) + len(u.Melodies) }

// SearchStream interroge toutes les sources en parallèle et renvoie un canal qui
// délivre un Update par source, dans l'ordre d'arrivée. Le canal est fermé quand
// toutes les sources ont répondu.
//
// Les Updates ne sont **pas** dédoublonnés : c'est le rôle d'Aggregator, que les
// deux appelants (batch et SSE) utilisent.
func (e *Engine) SearchStream(q Query) <-chan Update {
	out := make(chan Update, len(e.searchers))

	var wg sync.WaitGroup
	for _, s := range e.searchers {
		wg.Add(1)
		go func(s Searcher) {
			defer wg.Done()
			start := time.Now()
			g, l, m, err := s.Search(q)
			if err != nil {
				err = fmt.Errorf("%s : %w", s.Name(), err)
			}
			out <- Update{
				Source:   s.Name(),
				Grids:    g,
				Lyrics:   l,
				Melodies: m,
				Err:      err,
				Elapsed:  time.Since(start),
			}
		}(s)
	}
	go func() {
		wg.Wait()
		close(out)
	}()
	return out
}

// Aggregator accumule les Updates : il dédoublonne au fil de l'eau (même
// morceau vu chez deux sources) et plafonne chaque nature de résultat.
//
// Compromis assumé du mode flux : c'est la **première source à répondre** qui
// gagne un doublon, pas la plus prioritaire — l'ordre de câblage ne peut plus
// arbitrer si on veut afficher sans attendre. En mode batch, le résultat est
// identique dans les faits (le corpus embarqué répond avant tout le monde).
type Aggregator struct {
	seenGrids  map[string]bool
	seenLyrics map[string]bool
	seenMelody map[string]bool
	grids      int
	lyrics     int
	melodies   int
	maxPerType int
}

// NewAggregator crée un agrégateur plafonné à maxPerType résultats par nature
// (0 → le plafond par défaut de l'orchestrateur).
func NewAggregator(maxPerType int) *Aggregator {
	if maxPerType <= 0 {
		maxPerType = maxResultsPerType
	}
	return &Aggregator{
		seenGrids:  map[string]bool{},
		seenLyrics: map[string]bool{},
		seenMelody: map[string]bool{},
		maxPerType: maxPerType,
	}
}

// Accept filtre un Update et renvoie **uniquement les nouveautés** retenues :
// ni doublon, ni résultat au-delà du plafond. Un Update en échec est loggué et
// ne rapporte rien.
func (a *Aggregator) Accept(u Update) Update {
	if u.Err != nil {
		log.Printf("source en échec (ignorée) : %v", u.Err)
		return Update{Source: u.Source, Err: u.Err, Elapsed: u.Elapsed}
	}
	log.Printf("source %s : %d grille(s), %d paroles, %d mélodie(s) en %s",
		u.Source, len(u.Grids), len(u.Lyrics), len(u.Melodies), u.Elapsed.Round(time.Millisecond))

	kept := Update{Source: u.Source, Elapsed: u.Elapsed}
	for _, r := range u.Grids {
		if a.grids >= a.maxPerType {
			break
		}
		if k := songKey(r.Title, r.Artist); !a.seenGrids[k] {
			a.seenGrids[k] = true
			a.grids++
			kept.Grids = append(kept.Grids, r)
		}
	}
	for _, r := range u.Lyrics {
		if a.lyrics >= a.maxPerType {
			break
		}
		if k := songKey(r.Title, r.Artist); !a.seenLyrics[k] {
			a.seenLyrics[k] = true
			a.lyrics++
			kept.Lyrics = append(kept.Lyrics, r)
		}
	}
	for _, r := range u.Melodies {
		if a.melodies >= a.maxPerType {
			break
		}
		if k := songKey(r.Title, r.Artist); !a.seenMelody[k] {
			a.seenMelody[k] = true
			a.melodies++
			kept.Melodies = append(kept.Melodies, r)
		}
	}
	return kept
}

// Totals : ce qui a été retenu en tout, par nature.
func (a *Aggregator) Totals() (grids, lyrics, melodies int) {
	return a.grids, a.lyrics, a.melodies
}

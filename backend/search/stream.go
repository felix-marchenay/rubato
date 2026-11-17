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

// Aggregator journalise et compte ce que rapportent les sources. Rien n'est
// dédoublonné ni plafonné : un morceau trouvé par deux sources donne deux
// versions, et chaque source borne déjà son propre nombre de résultats.
type Aggregator struct {
	grids, lyrics, melodies int
}

func NewAggregator() *Aggregator { return &Aggregator{} }

// Accept renvoie l'Update tel quel, ou vidé de ses résultats s'il est en échec.
func (a *Aggregator) Accept(u Update) Update {
	if u.Err != nil {
		log.Printf("source en échec (ignorée) : %v", u.Err)
		return Update{Source: u.Source, Err: u.Err, Elapsed: u.Elapsed}
	}
	log.Printf("source %s : %d grille(s), %d paroles, %d mélodie(s) en %s",
		u.Source, len(u.Grids), len(u.Lyrics), len(u.Melodies), u.Elapsed.Round(time.Millisecond))
	a.grids += len(u.Grids)
	a.lyrics += len(u.Lyrics)
	a.melodies += len(u.Melodies)
	return u
}

// Totals : ce qui a été rapporté en tout, par nature.
func (a *Aggregator) Totals() (grids, lyrics, melodies int) {
	return a.grids, a.lyrics, a.melodies
}

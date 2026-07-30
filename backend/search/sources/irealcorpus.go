package sources

import (
	"embed"
	"encoding/json"
	"fmt"
	"log"
	"strings"
	"sync"

	"rubato/search"
)

// Corpus iReal Pro **embarqué dans le binaire** (go:embed) : ~1 700 standards
// jazz pré-parsés depuis les méga-playlists du forum iReal Pro par
// `scripts/build_ireal_corpus.py`.
//
// C'est la source de grilles la plus fiable et la seule instantanée :
//   - pas d'appel réseau, donc jamais en échec ni bloquée par un anti-bot ;
//   - de **vraies mesures** (plusieurs accords par mesure quand c'est le cas),
//     là où les sources scrapées retombent sur « une mesure = un accord » ;
//   - déjà au format pivot → le contenu est renvoyé tel quel, sans conversion.
//
// D'où sa position en tête dans main.go : en cas de doublon, c'est elle qui
// gagne. Pour rafraîchir le corpus : `python3 scripts/build_ireal_corpus.py`.

const sourceIRealCorpus = "irealpro"

// irealMaxSongs : plafond de résultats renvoyés (la recherche est locale, donc
// on pourrait en renvoyer plus ; le plafond garde des réponses lisibles).
const irealMaxSongs = 8

//go:embed data/ireal-index.json data/ireal-charts.json
var irealFS embed.FS

// IRealCorpusSearcher cherche dans le corpus embarqué.
type IRealCorpusSearcher struct{}

var _ search.Searcher = (*IRealCorpusSearcher)(nil)

// Name identifie la source (logs, /health).
func (IRealCorpusSearcher) Name() string { return sourceIRealCorpus }

// irealEntry : une entrée de l'index (`data/ireal-index.json`).
type irealEntry struct {
	ID     string   `json:"id"`
	Title  string   `json:"title"`
	Artist string   `json:"artist"`
	Tags   []string `json:"tags"`
}

// irealCorpus : l'index + les grilles, chargés une seule fois. Les grilles
// restent du JSON brut (json.RawMessage) : elles sont déjà au format pivot, donc
// les décoder puis les ré-encoder ne servirait qu'à risquer d'y perdre quelque
// chose.
type irealCorpus struct {
	index  []irealEntry
	charts map[string]json.RawMessage
	// normalized[i] = titre + artiste normalisés de index[i] (comparaison).
	normalized []string
}

var (
	irealOnce   sync.Once
	irealLoaded *irealCorpus
	irealErr    error
)

// loadIRealCorpus décode les fichiers embarqués au premier appel. Une erreur ici
// est une erreur de build (fichier absent ou corrompu), pas un incident réseau.
func loadIRealCorpus() (*irealCorpus, error) {
	irealOnce.Do(func() {
		c := &irealCorpus{}

		raw, err := irealFS.ReadFile("data/ireal-index.json")
		if err != nil {
			irealErr = fmt.Errorf("irealpro: index embarqué illisible : %w", err)
			return
		}
		if err := json.Unmarshal(raw, &c.index); err != nil {
			irealErr = fmt.Errorf("irealpro: index embarqué invalide : %w", err)
			return
		}

		raw, err = irealFS.ReadFile("data/ireal-charts.json")
		if err != nil {
			irealErr = fmt.Errorf("irealpro: grilles embarquées illisibles : %w", err)
			return
		}
		if err := json.Unmarshal(raw, &c.charts); err != nil {
			irealErr = fmt.Errorf("irealpro: grilles embarquées invalides : %w", err)
			return
		}

		c.normalized = make([]string, len(c.index))
		for i, e := range c.index {
			c.normalized[i] = search.NormalizeKey(e.Title + " " + e.Artist)
		}
		log.Printf("irealpro: corpus embarqué chargé (%d morceaux, %d grilles)",
			len(c.index), len(c.charts))
		irealLoaded = c
	})
	return irealLoaded, irealErr
}

// Search cherche les entrées dont titre + artiste contiennent **tous les mots**
// de la requête (dans n'importe quel ordre : « so what miles » trouve « So What »
// de « Davis Miles »). Les morceaux dont le **titre** porte tous les mots passent
// devant ceux qui ne correspondent que par l'artiste (« monk » → « Monk's Mood »
// avant les autres Thelonious Monk).
func (IRealCorpusSearcher) Search(q search.Query) (grids []search.ChordGridResult, lyrics []search.LyricsResult, melodies []search.MelodyResult, err error) {
	corpus, err := loadIRealCorpus()
	if err != nil {
		return nil, nil, nil, err
	}
	words := strings.Fields(search.NormalizeKey(q.Text))
	if len(words) == 0 {
		return nil, nil, nil, nil
	}

	var byTitle, byArtist []search.ChordGridResult
	for i, e := range corpus.index {
		if !containsAll(corpus.normalized[i], words) {
			continue
		}
		raw, ok := corpus.charts[e.ID]
		if !ok || len(raw) == 0 {
			continue // entrée d'index sans grille : ignorée
		}
		r := search.ChordGridResult{
			Title:   e.Title,
			Artist:  e.Artist,
			Source:  sourceIRealCorpus,
			Content: string(raw),
		}
		if containsAll(search.NormalizeKey(e.Title), words) {
			byTitle = append(byTitle, r)
		} else {
			byArtist = append(byArtist, r)
		}
		if len(byTitle)+len(byArtist) >= irealMaxSongs*2 {
			break // assez de candidats pour remplir le quota
		}
	}

	grids = append(byTitle, byArtist...)
	if len(grids) > irealMaxSongs {
		grids = grids[:irealMaxSongs]
	}
	return grids, nil, nil, nil
}

// containsAll dit si haystack (déjà normalisé) contient tous les mots donnés.
func containsAll(haystack string, words []string) bool {
	for _, w := range words {
		if !strings.Contains(haystack, w) {
			return false
		}
	}
	return true
}

// Package sources regroupe les implémentations de search.Searcher, une par
// source de contenu. Chaque fichier = une source.
package sources

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"

	"rubato/search"
)

// sourceEchords : valeur du champ Source des résultats venant d'e-chords.
const sourceEchords = "echords"

// echordsSearchURL : endpoint de recherche d'e-chords (renvoie du JSON).
const echordsSearchURL = "https://www.e-chords.com/api/search"

// EchordsSearcher interroge l'API de recherche d'e-chords.
type EchordsSearcher struct {
	// HTTPClient est injectable (tests, timeouts). Nil → client par défaut.
	HTTPClient *http.Client
}

// Vérification à la compilation qu'EchordsSearcher satisfait bien l'interface.
var _ search.Searcher = (*EchordsSearcher)(nil)

// Search interroge e-chords puis mappe la réponse. L'appel HTTP est séparé du
// parsing (parseEchordsSearch) pour que ce dernier soit testable sans réseau.
func (e EchordsSearcher) Search(q search.Query) (grids []search.ChordGridResult, lyrics []search.LyricsResult, melodies []search.MelodyResult, err error) {
	params := url.Values{}
	params.Set("q", q.Text)
	params.Add("only[]", "songs")
	params.Set("songs_take", "10")

	req, err := http.NewRequest(http.MethodGet, echordsSearchURL+"?"+params.Encode(), nil)
	if err != nil {
		return nil, nil, nil, fmt.Errorf("echords: requête : %w", err)
	}
	// e-chords sert le JSON à un client type navigateur (XHR).
	req.Header.Set("Accept", "application/json, text/plain, */*")
	req.Header.Set("User-Agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36")
	req.Header.Set("X-Requested-With", "XMLHttpRequest")
	req.Header.Set("Referer", "https://www.e-chords.com/")

	client := e.HTTPClient
	if client == nil {
		client = &http.Client{Timeout: 15 * time.Second}
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, nil, nil, fmt.Errorf("echords: appel : %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, nil, nil, fmt.Errorf("echords: statut inattendu %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, nil, nil, fmt.Errorf("echords: lecture : %w", err)
	}

	return parseEchordsSearch(body)
}

// echordsSearchResponse : sous-ensemble exploité de la réponse de /api/search.
// e-chords renvoie un objet par nature (songs, artists, videos…), chacun de la
// forme { hits: [...], total: N }. On ne lit que les chansons (= grilles).
type echordsSearchResponse struct {
	Songs struct {
		Hits []echordsSong `json:"hits"`
	} `json:"songs"`
}

// echordsSong : champs utiles d'un hit « song » (noms d'origine en portugais).
type echordsSong struct {
	Title      string `json:"TITULO"`
	Artist     string `json:"ARTISTA"`
	ArtistSlug string `json:"COD_ARTISTA"` // pour construire l'URL de la page
	TitleSlug  string `json:"COD_TITULO"`  // idem
}

// parseEchordsSearch mappe la réponse JSON d'e-chords vers nos résultats.
// Chaque chanson devient une grille d'accords. Le contenu (Content) reste vide :
// l'endpoint search ne renvoie que des métadonnées, pas la grille elle-même.
func parseEchordsSearch(body []byte) (grids []search.ChordGridResult, lyrics []search.LyricsResult, melodies []search.MelodyResult, err error) {
	var resp echordsSearchResponse
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, nil, nil, fmt.Errorf("echords: JSON invalide : %w", err)
	}

	for _, s := range resp.Songs.Hits {
		grids = append(grids, search.ChordGridResult{
			Title:  s.Title,
			Artist: s.Artist,
			Source: sourceEchords,
			// TODO: Content nécessite un 2e fetch de la page
			// https://www.e-chords.com/chords/<ArtistSlug>/<TitleSlug>.
		})
	}
	return grids, nil, nil, nil
}

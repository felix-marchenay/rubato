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

// echordsSearchURL : endpoint de recherche d'e-chords (renvoie du JSON, que des
// métadonnées : titre, artiste, ID… mais pas la grille elle-même).
const echordsSearchURL = "https://www.e-chords.com/api/search"

// echordsSongURL : gabarit de l'endpoint contenu. %d = ID_MUSICA (numérique,
// fourni uniquement par la recherche), %s = slug d'instrument (chords, ukulele…).
// Renvoie le JSON complet du morceau, dont chord.MUSICA (la feuille : accords
// entre crochets + paroles).
const echordsSongURL = "https://www.e-chords.com/api/song/%d/%s"

// echordsMaxContentFetch : nombre max de morceaux dont on récupère le contenu.
// Chaque contenu = un appel HTTP supplémentaire → on plafonne pour rester léger.
const echordsMaxContentFetch = 3

// EchordsSearcher interroge l'API d'e-chords.
type EchordsSearcher struct {
	// HTTPClient est injectable (tests, timeouts). Nil → client par défaut.
	HTTPClient *http.Client
}

// Vérification à la compilation qu'EchordsSearcher satisfait bien l'interface.
var _ search.Searcher = (*EchordsSearcher)(nil)

// Search interroge e-chords en deux temps : d'abord la recherche (métadonnées),
// puis, pour les premiers résultats, un fetch du contenu de chaque morceau. Le
// parsing (parseEchordsSearch/parseEchordsContent) est séparé des appels HTTP
// pour rester testable sans réseau.
func (e EchordsSearcher) Search(q search.Query) (grids []search.ChordGridResult, lyrics []search.LyricsResult, melodies []search.MelodyResult, err error) {
	params := url.Values{}
	params.Set("q", q.Text)
	params.Add("only[]", "songs")
	params.Set("songs_take", fmt.Sprintf("%d", echordsMaxContentFetch))

	req, err := e.newRequest(echordsSearchURL + "?" + params.Encode())
	if err != nil {
		return nil, nil, nil, fmt.Errorf("echords: requête : %w", err)
	}
	body, err := e.do(req)
	if err != nil {
		return nil, nil, nil, fmt.Errorf("echords: recherche : %w", err)
	}

	songs, err := parseEchordsSearch(body)
	if err != nil {
		return nil, nil, nil, err
	}

	// On ne récupère le contenu que des premiers résultats (un appel chacun).
	if len(songs) > echordsMaxContentFetch {
		songs = songs[:echordsMaxContentFetch]
	}

	for _, s := range songs {
		g := search.ChordGridResult{
			Title:  s.Title,
			Artist: s.Artist,
			Source: sourceEchords,
		}
		// Best-effort : si le fetch du contenu échoue, on garde quand même la
		// grille (métadonnées) plutôt que de faire échouer toute la recherche.
		if content, cerr := e.fetchContent(s); cerr == nil {
			g.Content = content
		}
		grids = append(grids, g)
	}
	return grids, nil, nil, nil
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
	ID          int                 `json:"ID_MUSICA"`   // requis pour l'URL du contenu
	Title       string              `json:"TITULO"`
	Artist      string              `json:"ARTISTA"`
	ArtistSlug  string              `json:"COD_ARTISTA"` // page web (pas l'API)
	TitleSlug   string              `json:"COD_TITULO"`  // page web (pas l'API)
	Instruments []echordsInstrument `json:"INSTRUMENTOS"`
}

// echordsInstrument : une version instrumentale disponible pour un morceau. Son
// SLUG (chords, ukulele, keyboards, cavaco) complète l'URL du contenu.
type echordsInstrument struct {
	Slug string `json:"SLUG"`
}

// contentSlug choisit l'instrument à récupérer : « chords » (guitare) en
// priorité, sinon le premier proposé. Vide si le morceau n'a aucun instrument.
func (s echordsSong) contentSlug() string {
	for _, ins := range s.Instruments {
		if ins.Slug == "chords" {
			return "chords"
		}
	}
	if len(s.Instruments) > 0 {
		return s.Instruments[0].Slug
	}
	return ""
}

// parseEchordsSearch extrait la liste des chansons de la réponse de /api/search.
// Il ne mappe pas encore vers ChordGridResult : l'ID et le slug d'instrument
// sont nécessaires à l'étape suivante (fetch du contenu).
func parseEchordsSearch(body []byte) ([]echordsSong, error) {
	var resp echordsSearchResponse
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, fmt.Errorf("echords: JSON invalide : %w", err)
	}
	return resp.Songs.Hits, nil
}

// echordsSongContent : sous-ensemble exploité de /api/song/{id}/{slug}. Le champ
// chord.MUSICA porte la feuille complète (accords entre crochets + paroles).
type echordsSongContent struct {
	Chord struct {
		Musica string `json:"MUSICA"`
	} `json:"chord"`
}

// fetchContent récupère la feuille d'un morceau via /api/song/{id}/{slug}.
func (e EchordsSearcher) fetchContent(s echordsSong) (string, error) {
	slug := s.contentSlug()
	if s.ID == 0 || slug == "" {
		return "", fmt.Errorf("echords: identifiants de contenu manquants")
	}
	req, err := e.newRequest(fmt.Sprintf(echordsSongURL, s.ID, slug))
	if err != nil {
		return "", err
	}
	body, err := e.do(req)
	if err != nil {
		return "", fmt.Errorf("echords: contenu %d/%s : %w", s.ID, slug, err)
	}
	return parseEchordsContent(body)
}

// parseEchordsContent extrait la feuille (chord.MUSICA) d'une réponse contenu.
func parseEchordsContent(body []byte) (string, error) {
	var c echordsSongContent
	if err := json.Unmarshal(body, &c); err != nil {
		return "", fmt.Errorf("echords: JSON contenu invalide : %w", err)
	}
	return c.Chord.Musica, nil
}

// newRequest construit une requête GET avec les en-têtes attendus par e-chords
// (sinon 403). Un User-Agent navigateur suffit ; on ajoute le reste par prudence
// (l'endpoint search est plus strict et les réclame).
func (e EchordsSearcher) newRequest(u string) (*http.Request, error) {
	req, err := http.NewRequest(http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/json, text/plain, */*")
	req.Header.Set("User-Agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36")
	req.Header.Set("X-Requested-With", "XMLHttpRequest")
	req.Header.Set("Referer", "https://www.e-chords.com/")
	return req, nil
}

// do exécute la requête (client injecté ou client par défaut) et renvoie le
// corps si le statut est 200.
func (e EchordsSearcher) do(req *http.Request) ([]byte, error) {
	client := e.HTTPClient
	if client == nil {
		client = &http.Client{Timeout: 15 * time.Second}
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("echords: appel : %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("echords: statut inattendu %d", resp.StatusCode)
	}
	return io.ReadAll(resp.Body)
}

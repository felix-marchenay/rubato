package sources

import (
	"encoding/json"
	"fmt"
	"log"
	"net/url"
	"regexp"
	"strings"

	"rubato/chart"
	"rubato/search"
)

// Ultimate Guitar — très large couverture pop/rock/soul. Portage du scraper JS
// (netlify/functions/scrapers.mjs, supprimé).
//
// Les pages UG embarquent tout leur état dans
// `<div class="js-store" data-content="…">` : du JSON échappé en HTML. On y lit
// les résultats de recherche, puis le contenu du tab (`tab_view.wiki_tab`), où
// les accords sont balisés `[ch]…[/ch]`. Comme pour e-chords, seule l'harmonie
// est conservée — jamais les paroles.

const sourceUltimateGuitar = "ultimateguitar"

// ugSearchURL : recherche par titre (le type « chords » est filtré ensuite).
const ugSearchURL = "https://www.ultimate-guitar.com/search.php"

// ugMaxTabs : nombre max de tabs dont on récupère le contenu (un appel chacun).
const ugMaxTabs = 3

// UltimateGuitarSearcher interroge Ultimate Guitar.
type UltimateGuitarSearcher struct{}

var _ search.Searcher = (*UltimateGuitarSearcher)(nil)

// Name identifie la source (logs, /health).
func (UltimateGuitarSearcher) Name() string { return sourceUltimateGuitar }

// Search cherche les tabs de type « Chords », puis convertit le contenu des
// premiers en grilles au format pivot. UG ne fournit ni paroles ni mélodie ici.
func (u UltimateGuitarSearcher) Search(q search.Query) (grids []search.ChordGridResult, lyrics []search.LyricsResult, melodies []search.MelodyResult, err error) {
	params := url.Values{}
	params.Set("search_type", "title")
	params.Set("value", q.Text)

	html, err := curlGet(ugSearchURL + "?" + params.Encode())
	if err != nil {
		return nil, nil, nil, fmt.Errorf("ultimateguitar: recherche : %w", err)
	}

	tabs, err := parseUGSearch(html)
	if err != nil {
		return nil, nil, nil, err
	}
	if len(tabs) > ugMaxTabs {
		tabs = tabs[:ugMaxTabs]
	}

	for _, t := range tabs {
		// Best-effort, comme e-chords : un tab illisible est ignoré plutôt que de
		// faire échouer la recherche ou de renvoyer un résultat sans grille.
		content, cerr := u.fetchChart(t)
		if cerr != nil {
			log.Printf("ultimateguitar: %q ignoré : %v", t.SongName, cerr)
			continue
		}
		grids = append(grids, search.ChordGridResult{
			Title:   decodeEntities(t.SongName),
			Artist:  decodeEntities(t.ArtistName),
			Source:  sourceUltimateGuitar,
			Content: content,
		})
	}
	return grids, nil, nil, nil
}

// ugStoreRe : le JSON d'état de la page, échappé dans un attribut HTML.
var ugStoreRe = regexp.MustCompile(`class="js-store"[^>]*\sdata-content="([^"]*)"`)

// ugStore : forme (partielle) du magasin d'état d'une page UG. Les deux pages
// qui nous intéressent — recherche et tab — partagent le même emplacement.
type ugStore struct {
	Store struct {
		Page struct {
			Data struct {
				// Page de recherche.
				Results []ugTab `json:"results"`
				// Page d'un tab.
				Tab struct {
					TonalityName string `json:"tonality_name"`
				} `json:"tab"`
				TabView struct {
					WikiTab struct {
						Content string `json:"content"`
					} `json:"wiki_tab"`
				} `json:"tab_view"`
			} `json:"data"`
		} `json:"page"`
	} `json:"store"`
}

// ugTab : un résultat de recherche UG.
type ugTab struct {
	Type       string `json:"type"` // « Chords », « Tabs », « Pro »… ou null
	SongName   string `json:"song_name"`
	ArtistName string `json:"artist_name"`
	TabURL     string `json:"tab_url"`
	Votes      int    `json:"votes"`
}

// parseUGStore extrait et décode le magasin d'état d'une page UG.
func parseUGStore(page []byte) (*ugStore, error) {
	m := ugStoreRe.FindSubmatch(page)
	if m == nil {
		return nil, fmt.Errorf("ultimateguitar: js-store introuvable (page inattendue)")
	}
	var s ugStore
	if err := json.Unmarshal([]byte(decodeEntities(string(m[1]))), &s); err != nil {
		return nil, fmt.Errorf("ultimateguitar: js-store illisible : %w", err)
	}
	return &s, nil
}

// parseUGSearch retient les tabs d'accords (type « Chords »), dédoublonnés par
// URL et par morceau. On garde l'ordre de pertinence d'UG.
func parseUGSearch(page []byte) ([]ugTab, error) {
	s, err := parseUGStore(page)
	if err != nil {
		return nil, err
	}
	var out []ugTab
	seen := make(map[string]bool)
	for _, t := range s.Store.Page.Data.Results {
		if !strings.EqualFold(t.Type, "chords") || t.TabURL == "" {
			continue
		}
		// Une même chanson a souvent plusieurs versions : la première (la mieux
		// classée par UG) suffit.
		key := strings.ToLower(t.SongName + "|" + t.ArtistName)
		if seen[key] || seen[t.TabURL] {
			continue
		}
		seen[key], seen[t.TabURL] = true, true
		out = append(out, t)
	}
	return out, nil
}

// ugHostRe : les tabs sont servis sur des sous-domaines (tabs.ultimate-guitar…).
// Garde-fou : on ne suit que des URLs du domaine.
var ugHostRe = regexp.MustCompile(`(?i)^https?://(?:[a-z0-9-]+\.)*ultimate-guitar\.com/`)

// fetchChart récupère la page d'un tab et la convertit en grille JSON.
func (u UltimateGuitarSearcher) fetchChart(t ugTab) (string, error) {
	if !ugHostRe.MatchString(t.TabURL) {
		return "", fmt.Errorf("URL hors domaine : %s", t.TabURL)
	}
	page, err := curlGet(t.TabURL)
	if err != nil {
		return "", fmt.Errorf("tab %s : %w", t.TabURL, err)
	}
	c, ok := ugChart(page)
	if !ok {
		return "", fmt.Errorf("aucune mesure exploitable dans le tab")
	}
	return c.JSON()
}

var (
	ugTabTagRe   = regexp.MustCompile(`\[/?tab\]`)
	ugChordTagRe = regexp.MustCompile(`\[ch\]([^\[]+)\[/ch\]`)
)

// ugChart convertit la page d'un tab en grille au format pivot : on retire les
// balises `[tab]`, on déshabille les accords `[ch]C[/ch]` → `C`, et les en-têtes
// `[Verse 1]` restent pour servir de libellés (voir chart.SectionsFromChordLines).
func ugChart(page []byte) (chart.Chart, bool) {
	s, err := parseUGStore(page)
	if err != nil {
		return chart.Chart{}, false
	}
	content := s.Store.Page.Data.TabView.WikiTab.Content
	if strings.TrimSpace(content) == "" {
		return chart.Chart{}, false
	}
	text := ugChordTagRe.ReplaceAllString(ugTabTagRe.ReplaceAllString(content, ""), "$1")
	key := strings.TrimSpace(s.Store.Page.Data.Tab.TonalityName)
	return chart.New(chart.SectionsFromChordLines(text), key, chart.DefaultTime)
}

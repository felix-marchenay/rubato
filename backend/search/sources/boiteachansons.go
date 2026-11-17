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

// La Boîte à chansons (boiteachansons.net) — le répertoire **francophone**
// (chanson française, québécoise…), mal couvert par les autres sources.
//
//  1. recherche → POST `/recherche/xhrGetResultats` (JSON, l'autocomplétion du
//     site) ;
//  2. contenu   → `/partitions/<artiste>/<morceau>` : une `<div class="pL…">`
//     par ligne, accords dans `<span class="a" data-a="Dm">`.
//
// Seule l'harmonie sort du backend, jamais les paroles.

const sourceBoiteAChansons = "boiteachansons"

const (
	boiteSearchURL = "https://www.boiteachansons.net/recherche/xhrGetResultats"
	boiteSongURL   = "https://www.boiteachansons.net/partitions/%s/%s"
	boiteReferer   = "Referer: https://www.boiteachansons.net/"
)

const boiteMaxSongs = 3

// boiteMaxQueries borne les relances de recherche (cf. boiteQueries).
const boiteMaxQueries = 4

// BoiteAChansonsSearcher interroge La Boîte à chansons.
type BoiteAChansonsSearcher struct{}

var _ search.Searcher = (*BoiteAChansonsSearcher)(nil)

func (BoiteAChansonsSearcher) Name() string { return sourceBoiteAChansons }

func (b BoiteAChansonsSearcher) Search(q search.Query) (grids []search.ChordGridResult, lyrics []search.LyricsResult, melodies []search.MelodyResult, err error) {
	songs, err := b.searchSongs(q.Text)
	if err != nil {
		return nil, nil, nil, err
	}
	if len(songs) > boiteMaxSongs {
		songs = songs[:boiteMaxSongs]
	}

	for _, s := range songs {
		content, cerr := b.fetchChart(s)
		if cerr != nil {
			log.Printf("boiteachansons: %q ignoré : %v", s.Title, cerr)
			continue
		}
		grids = append(grids, search.ChordGridResult{
			Title:   s.displayTitle(),
			Artist:  s.displayArtist(),
			Source:  sourceBoiteAChansons,
			Content: content,
		})
	}
	return grids, nil, nil, nil
}

// searchSongs essaie les requêtes de boiteQueries jusqu'à la première qui
// trouve des morceaux contenant aussi les mots qu'elle a retirés.
func (BoiteAChansonsSearcher) searchSongs(q string) ([]boiteSong, error) {
	for _, sub := range boiteQueries(q) {
		body, err := curlPost(boiteSearchURL, url.Values{"recherche": {sub.text}},
			"X-Requested-With: XMLHttpRequest",
			"Accept: application/json",
			boiteReferer)
		if err != nil {
			return nil, fmt.Errorf("boiteachansons: recherche : %w", err)
		}
		songs, err := parseBoiteSearch(body)
		if err != nil {
			return nil, err
		}
		var kept []boiteSong
		for _, s := range songs {
			if matchesWords(queryWords(sub.dropped), s.displayTitle(), s.displayArtist()) {
				kept = append(kept, s)
			}
		}
		if len(kept) > 0 {
			return kept, nil
		}
	}
	return nil, nil
}

type boiteQuery struct {
	text    string
	dropped string // mots retirés, que les morceaux trouvés doivent contenir
}

// boiteQueries : la recherche du site cherche la requête telle quelle dans le
// titre OU l'artiste, donc « la boheme aznavour » ne trouve rien. On relance en
// retirant des mots en fin puis en début (« la boheme » + « aznavour »…). Le
// site ignore les requêtes de moins de 3 caractères.
func boiteQueries(q string) []boiteQuery {
	words := strings.Fields(q)
	out := []boiteQuery{{text: strings.Join(words, " ")}}
	seen := map[string]bool{out[0].text: true}
	add := func(kept, dropped []string) {
		s := strings.Join(kept, " ")
		if len([]rune(s)) < 3 || seen[s] || len(out) >= boiteMaxQueries {
			return
		}
		seen[s] = true
		out = append(out, boiteQuery{text: s, dropped: strings.Join(dropped, " ")})
	}
	for drop := 1; drop < len(words); drop++ {
		add(words[:len(words)-drop], words[len(words)-drop:])
		add(words[drop:], words[:drop])
	}
	return out
}

// boiteSong : un résultat de recherche. `auteur` et `fichierAuteur` listent les
// artistes séparés par « | » quand il y en a plusieurs.
type boiteSong struct {
	Type       string `json:"typeResult"` // « p » = morceau, « a » = artiste
	Title      string `json:"titre"`
	Version    string `json:"version"`
	Artist     string `json:"auteur"`
	ArtistFile string `json:"fichierAuteur"`
	SongFile   string `json:"fichierChanson"`
}

func (s boiteSong) displayTitle() string {
	t := strings.TrimSpace(decodeEntities(s.Title))
	if v := strings.TrimSpace(decodeEntities(s.Version)); v != "" {
		t += " (" + v + ")"
	}
	return t
}

func (s boiteSong) displayArtist() string {
	return strings.Join(strings.Split(decodeEntities(s.Artist), "|"), ", ")
}

func parseBoiteSearch(body []byte) ([]boiteSong, error) {
	var all []boiteSong
	if err := json.Unmarshal(body, &all); err != nil {
		return nil, fmt.Errorf("boiteachansons: JSON invalide : %w", err)
	}
	var out []boiteSong
	for _, s := range all {
		if s.Type != "p" || strings.TrimSpace(s.Title) == "" || s.ArtistFile == "" || s.SongFile == "" {
			continue
		}
		out = append(out, s)
	}
	return out, nil
}

func (BoiteAChansonsSearcher) fetchChart(s boiteSong) (string, error) {
	artist := strings.ReplaceAll(s.ArtistFile, "|", "-")
	u := fmt.Sprintf(boiteSongURL, url.PathEscape(artist), url.PathEscape(s.SongFile))
	page, err := curlGet(u, boiteReferer)
	if err != nil {
		return "", fmt.Errorf("partition %s : %w", u, err)
	}
	c, ok := boiteChart(page)
	if !ok {
		return "", fmt.Errorf("aucune mesure exploitable dans la partition")
	}
	return c.JSON()
}

var (
	// Classes vues : pL (accords + paroles), pLI (instrumental), pLS (paroles
	// seules), pLVV (ligne vide). Les tablatures (div tabT/tabR/tabC) ne
	// correspondent pas et sont donc ignorées.
	boiteLineRe  = regexp.MustCompile(`(?s)<div class="pL[A-Z]*"[^>]*>(.*?)</div>`)
	boiteChordRe = regexp.MustCompile(`data-a="([^"]*)"`)
	boiteKeyRe   = regexp.MustCompile(`id="tonalite"[^>]*\bvalue="([A-G][#b]?)"`)
)

type boiteSheet struct{}

var _ chart.TaggedSource = boiteSheet{}

// Chords fait confiance à l'attribut data-a : ce sont des accords par
// construction, y compris des notations que chart.IsChord refuserait (« Dm7/4 »).
func (boiteSheet) Chords(line string) []string {
	var out []string
	for _, m := range boiteChordRe.FindAllStringSubmatch(line, -1) {
		tok := strings.TrimSpace(decodeEntities(m[1]))
		if tok != "" && (chart.IsChord(tok) || strings.IndexByte("ABCDEFG", tok[0]) >= 0) {
			out = append(out, tok)
		}
	}
	return out
}

func (boiteSheet) Label(line string) string {
	if l, ok := chart.Label(stripTags(line)); ok {
		return l
	}
	return ""
}

func (boiteSheet) Blank(line string) bool {
	return strings.TrimSpace(stripTags(line)) == ""
}

func boiteChart(page []byte) (chart.Chart, bool) {
	html := string(page)
	start := strings.Index(html, `id="divPartition"`)
	if start < 0 {
		return chart.Chart{}, false
	}
	html = html[start:]
	if end := strings.Index(html, `id="divDroitePagePartition"`); end >= 0 {
		html = html[:end]
	}

	var lines []string
	for _, m := range boiteLineRe.FindAllStringSubmatch(html, -1) {
		lines = append(lines, strings.ReplaceAll(m[1], "\n", " "))
	}
	sections := chart.SectionsFromTaggedLines(strings.Join(lines, "\n"), boiteSheet{})

	key := ""
	if m := boiteKeyRe.FindSubmatch(page); m != nil {
		key = boiteKey(string(m[1]), sections)
	}
	return chart.New(sections, key, chart.DefaultTime)
}

// boiteKey : le site ne donne que la tonique (« A » pour la mineur). On la dit
// mineure quand le morceau finit sur l'accord mineur de cette tonique.
func boiteKey(tonic string, sections []chart.Section) string {
	last := ""
	for _, s := range sections {
		for _, b := range s.Bars {
			if len(b.Chords) > 0 {
				last = b.Chords[len(b.Chords)-1]
			}
		}
	}
	if strings.HasPrefix(last, tonic+"m") && !strings.HasPrefix(last, tonic+"maj") {
		return tonic + "m"
	}
	return tonic
}

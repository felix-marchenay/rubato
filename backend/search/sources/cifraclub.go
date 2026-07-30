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

// Cifra Club (cifraclub.com.br) — énorme catalogue (pop/rock international +
// répertoire brésilien), et surtout une **vraie API de recherche JSON** (Solr),
// donc pas de HTML à parser pour trouver les morceaux.
//
// Deux appels :
//  1. recherche → `https://solr.sscdn.co/cifraclub/m/?q=…` (JSON)
//  2. contenu   → `https://www.cifraclub.com.br/<artiste>/<morceau>/imprimir.html`
//     (version « imprimer » : une seule balise <pre>, accords en <b>)
//
// Comme partout ici, seule l'harmonie est conservée : les paroles de la feuille
// ne sortent pas du backend.

const sourceCifraClub = "cifraclub"

// cifraClubSearchURL : l'index Solr public utilisé par le site lui-même.
const cifraClubSearchURL = "https://solr.sscdn.co/cifraclub/m/"

// cifraClubChartURL : gabarit de la version imprimable d'une cifra.
// %s/%s = slug artiste (`dns`) / slug morceau (`url`).
const cifraClubChartURL = "https://www.cifraclub.com.br/%s/%s/imprimir.html"

// cifraClubMaxSongs : plafond de contenus récupérés (un appel HTTP chacun).
const cifraClubMaxSongs = 3

// CifraClubSearcher interroge Cifra Club.
type CifraClubSearcher struct{}

var _ search.Searcher = (*CifraClubSearcher)(nil)

// Name identifie la source (logs, /health).
func (CifraClubSearcher) Name() string { return sourceCifraClub }

// Search cherche dans l'index Solr, puis convertit les premières cifras en
// grilles au format pivot. Cifra Club ne fournit ici que des grilles.
func (c CifraClubSearcher) Search(q search.Query) (grids []search.ChordGridResult, lyrics []search.LyricsResult, melodies []search.MelodyResult, err error) {
	params := url.Values{}
	params.Set("q", q.Text)

	body, err := curlGet(cifraClubSearchURL+"?"+params.Encode(),
		"Accept: application/json, text/plain, */*",
		"Referer: https://www.cifraclub.com.br/")
	if err != nil {
		return nil, nil, nil, fmt.Errorf("cifraclub: recherche : %w", err)
	}

	songs, err := parseCifraClubSearch(body)
	if err != nil {
		return nil, nil, nil, err
	}
	if len(songs) > cifraClubMaxSongs {
		songs = songs[:cifraClubMaxSongs]
	}

	for _, s := range songs {
		content, cerr := c.fetchChart(s)
		if cerr != nil {
			log.Printf("cifraclub: %q ignoré : %v", s.Title, cerr)
			continue
		}
		grids = append(grids, search.ChordGridResult{
			Title:   decodeEntities(s.Title),
			Artist:  decodeEntities(s.Artist),
			Source:  sourceCifraClub,
			Content: content,
		})
	}
	return grids, nil, nil, nil
}

// cifraClubResponse : réponse Solr. Seuls les documents nous intéressent.
type cifraClubResponse struct {
	Response struct {
		Docs []cifraClubSong `json:"docs"`
	} `json:"response"`
}

// cifraClubSong : un document Solr. Noms de champs courts (l'index est celui du
// site) : `txt` = titre, `art` = artiste, `dns` = slug artiste, `url` = slug
// morceau, `t` = type de document (« 2 » = un morceau).
type cifraClubSong struct {
	Type      string `json:"t"`
	Title     string `json:"txt"`
	Artist    string `json:"art"`
	ArtistDNS string `json:"dns"`
	SongURL   string `json:"url"`
}

// parseCifraClubSearch retient les documents « morceau » exploitables, c'est-à-
// dire ceux dont on peut construire l'URL de la cifra.
func parseCifraClubSearch(body []byte) ([]cifraClubSong, error) {
	var resp cifraClubResponse
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, fmt.Errorf("cifraclub: JSON invalide : %w", err)
	}
	var out []cifraClubSong
	for _, d := range resp.Response.Docs {
		if d.Title == "" || d.ArtistDNS == "" || d.SongURL == "" {
			continue
		}
		out = append(out, d)
	}
	return out, nil
}

var (
	// cifraClubPreRe : le corps de la cifra (une seule balise <pre> sur la page
	// imprimable).
	cifraClubPreRe = regexp.MustCompile(`(?is)<pre[^>]*>(.*?)</pre>`)
	// cifraClubKeyRe : la tonalité, affichée « tom: G » en en-tête.
	cifraClubKeyRe = regexp.MustCompile(`(?i)tom:\s*<[^>]*>?\s*([A-G][#b]?m?)\b`)
	// Blocs de tablature à jeter : ce sont des positions de doigts, pas des
	// accords. Structure imbriquée
	// `<span class="tablatura">…<span class="cnt">…</span></span>` → on retire
	// l'intérieur d'abord, l'extérieur ensuite (RE2 ne sait pas récurser).
	cifraClubTabInnerRe = regexp.MustCompile(`(?is)<span class="cnt">.*?</span>`)
	cifraClubTabOuterRe = regexp.MustCompile(`(?is)<span class="tablatura">.*?</span>`)
	// cifraClubChordRe : un accord, en gras dans la cifra.
	cifraClubChordRe = regexp.MustCompile(`(?is)<b>\s*([^<>]{1,12}?)\s*</b>`)
	// cifraClubLabelRe : les libellés de section sont entre crochets en début de
	// ligne (« [Intro] », « [Primeira Parte] »).
	cifraClubLabelRe = regexp.MustCompile(`^\s*\[([^\]]{1,30})\]`)
)

// cifraClubSheet lit une cifra : du texte « accords en gras au-dessus des
// paroles », avec des blocs de tablature à ignorer.
//
//	[Intro] <b>G</b>  <b>B</b>  <b>C</b>
//	<b>G</b>            <b>B</b>
//	une ligne de paroles
type cifraClubSheet struct{}

var _ chart.TaggedSource = cifraClubSheet{}

// Chords relève les accords en gras de la ligne.
func (cifraClubSheet) Chords(line string) []string {
	var out []string
	for _, m := range cifraClubChordRe.FindAllStringSubmatch(line, -1) {
		if tok := decodeEntities(strings.TrimSpace(m[1])); chart.IsChord(tok) {
			out = append(out, tok)
		}
	}
	return out
}

// Label lit le libellé entre crochets en début de ligne.
func (cifraClubSheet) Label(line string) string {
	if m := cifraClubLabelRe.FindStringSubmatch(stripTags(line)); m != nil {
		return strings.TrimSpace(m[1])
	}
	return ""
}

// Blank : seules les lignes réellement vides coupent la section.
func (cifraClubSheet) Blank(line string) bool {
	return strings.TrimSpace(stripTags(line)) == ""
}

// fetchChart récupère la version imprimable d'une cifra et la convertit.
func (c CifraClubSearcher) fetchChart(s cifraClubSong) (string, error) {
	u := fmt.Sprintf(cifraClubChartURL, url.PathEscape(s.ArtistDNS), url.PathEscape(s.SongURL))
	page, err := curlGet(u, "Referer: https://www.cifraclub.com.br/")
	if err != nil {
		return "", fmt.Errorf("cifra %s : %w", u, err)
	}
	chrt, ok := cifraClubChart(page)
	if !ok {
		return "", fmt.Errorf("aucune mesure exploitable dans la cifra")
	}
	return chrt.JSON()
}

// cifraClubChart convertit la page imprimable d'une cifra en grille pivot.
func cifraClubChart(page []byte) (chart.Chart, bool) {
	m := cifraClubPreRe.FindSubmatch(page)
	if m == nil {
		return chart.Chart{}, false
	}
	sheet := string(m[1])
	// Les tablatures contiennent des lettres de cordes (E|A|D|G|B|E) qui
	// passeraient pour des accords : on les retire avant toute analyse.
	sheet = cifraClubTabInnerRe.ReplaceAllString(sheet, "")
	sheet = cifraClubTabOuterRe.ReplaceAllString(sheet, "")

	key := ""
	if k := cifraClubKeyRe.FindSubmatch(page); k != nil {
		key = string(k[1])
	}
	sections := chart.SectionsFromTaggedLines(sheet, cifraClubSheet{})
	return chart.New(sections, key, chart.DefaultTime)
}

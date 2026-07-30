// Package sources regroupe les implémentations de search.Searcher, une par
// source de contenu. Chaque fichier = une source.
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

// sourceEchords : valeur du champ Source des résultats venant d'e-chords.
const sourceEchords = "echords"

// echordsSearchURL : endpoint de recherche d'e-chords (renvoie du JSON, que des
// métadonnées : titre, artiste, ID… mais pas la grille elle-même).
const echordsSearchURL = "https://www.e-chords.com/api/search"

// echordsSongURL : gabarit de l'endpoint contenu. %d = ID_MUSICA (numérique,
// fourni uniquement par la recherche), %s = slug d'instrument (chords, ukulele…).
// Renvoie le JSON complet du morceau, dont chord.MUSICA (la feuille : accords
// entre crochets + paroles) et default_key (la tonalité).
const echordsSongURL = "https://www.e-chords.com/api/song/%d/%s"

// echordsMaxSongs : nombre max de morceaux traités. Chaque morceau = un appel
// HTTP de plus (on récupère la grille tout de suite, pas à la demande) → on
// plafonne pour que la recherche reste rapide.
const echordsMaxSongs = 3

// EchordsSearcher interroge l'API d'e-chords et convertit ses feuilles au
// format pivot des grilles (voir package chart). Les appels réseau passent par
// curlGet (cf. fetch.go pour le pourquoi).
type EchordsSearcher struct{}

// Vérification à la compilation qu'EchordsSearcher satisfait bien l'interface.
var _ search.Searcher = (*EchordsSearcher)(nil)

// Name identifie la source (logs, /health).
func (EchordsSearcher) Name() string { return sourceEchords }

// Search interroge e-chords en deux temps : d'abord la recherche (métadonnées),
// puis, pour les premiers résultats, le contenu de chaque morceau converti en
// grille. Le parsing (parseEchordsSearch/parseEchordsContent/echordsChart) est
// séparé des appels réseau pour rester testable sans réseau.
//
// e-chords ne fournit que des grilles : les paroles de ses feuilles ne sortent
// jamais du backend (règle projet — droit d'auteur), seule l'harmonie est
// conservée.
func (e EchordsSearcher) Search(q search.Query) (grids []search.ChordGridResult, lyrics []search.LyricsResult, melodies []search.MelodyResult, err error) {
	params := url.Values{}
	params.Set("q", q.Text)
	params.Add("only[]", "songs")
	params.Set("songs_take", fmt.Sprintf("%d", echordsMaxSongs))

	body, err := curlGet(echordsSearchURL+"?"+params.Encode(),
		"Accept: application/json, text/plain, */*",
		"Referer: https://www.e-chords.com/")
	if err != nil {
		return nil, nil, nil, fmt.Errorf("echords: recherche : %w", err)
	}

	songs, err := parseEchordsSearch(body)
	if err != nil {
		return nil, nil, nil, err
	}
	songs = dedupEchordsSongs(songs)
	if len(songs) > echordsMaxSongs {
		songs = songs[:echordsMaxSongs]
	}

	for _, s := range songs {
		// Best-effort : un morceau dont le contenu échoue (ou dont la feuille ne
		// donne aucune mesure exploitable) est ignoré — on ne renvoie pas de
		// résultat sans grille, l'app n'en ferait rien.
		content, cerr := e.fetchChart(s)
		if cerr != nil {
			log.Printf("echords: %q ignoré : %v", s.Title, cerr)
			continue
		}
		grids = append(grids, search.ChordGridResult{
			Title:   decodeEntities(s.Title),
			Artist:  decodeEntities(s.Artist),
			Source:  sourceEchords,
			Content: content,
		})
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
	ID          int                 `json:"ID_MUSICA"` // requis pour l'URL du contenu
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

// dedupEchordsSongs supprime les doublons d'ID : la recherche d'e-chords renvoie
// régulièrement deux fois le même morceau, ce qui coûterait deux fetchs pour
// rien.
func dedupEchordsSongs(songs []echordsSong) []echordsSong {
	seen := make(map[int]bool, len(songs))
	out := make([]echordsSong, 0, len(songs))
	for _, s := range songs {
		if seen[s.ID] {
			continue
		}
		seen[s.ID] = true
		out = append(out, s)
	}
	return out
}

// echordsSongContent : sous-ensemble exploité de /api/song/{id}/{slug}. Le champ
// chord.MUSICA porte la feuille complète (accords entre crochets + paroles) ;
// default_key donne la tonalité affichée par e-chords.
type echordsSongContent struct {
	DefaultKey string `json:"default_key"`
	Chord      struct {
		Musica string `json:"MUSICA"`
	} `json:"chord"`
}

// fetchChart récupère la feuille d'un morceau via /api/song/{id}/{slug} et la
// convertit en grille JSON (format pivot).
func (e EchordsSearcher) fetchChart(s echordsSong) (string, error) {
	slug := s.contentSlug()
	if s.ID == 0 || slug == "" {
		return "", fmt.Errorf("identifiants de contenu manquants")
	}
	body, err := curlGet(fmt.Sprintf(echordsSongURL, s.ID, slug),
		"Accept: application/json, text/plain, */*",
		"Referer: https://www.e-chords.com/")
	if err != nil {
		return "", fmt.Errorf("contenu %d/%s : %w", s.ID, slug, err)
	}
	sheet, key, err := parseEchordsContent(body)
	if err != nil {
		return "", err
	}
	c, ok := echordsChart(sheet, key)
	if !ok {
		return "", fmt.Errorf("aucune mesure exploitable dans la feuille")
	}
	return c.JSON()
}

// parseEchordsContent extrait la feuille (chord.MUSICA) et la tonalité d'une
// réponse contenu.
func parseEchordsContent(body []byte) (sheet, key string, err error) {
	var c echordsSongContent
	if err := json.Unmarshal(body, &c); err != nil {
		return "", "", fmt.Errorf("echords: JSON contenu invalide : %w", err)
	}
	return c.Chord.Musica, strings.TrimSpace(c.DefaultKey), nil
}

var (
	// echordsBracketRe : un accord entre crochets dans la feuille e-chords.
	echordsBracketRe = regexp.MustCompile(`\[([^\[\]\n]{1,12})\]`)
	// echordsItalicRe : e-chords balise ses libellés de section en italique
	// (« <i>Intro</i> », « (<i>Instrumental</i> 2x) »).
	echordsItalicRe = regexp.MustCompile(`(?is)<i>(.*?)</i>`)
	// echordsPseudoTagRe : et parfois avec des pseudo-balises maison (<V1>,
	// <PONTE>, <R>…), ouvrantes ou fermantes.
	echordsPseudoTagRe = regexp.MustCompile(`<\s*(/?)\s*([A-Za-z][^<>\s]{0,19})\s*>`)
)

// echordsHTMLTags : balises de mise en forme, qui ne sont pas des libellés.
var echordsHTMLTags = map[string]bool{
	"i": true, "b": true, "u": true, "em": true, "strong": true,
	"span": true, "br": true, "p": true, "div": true, "small": true,
}

// echordsSheet lit une feuille e-chords, c'est-à-dire du texte « accords entre
// crochets AU-DESSUS des paroles » :
//
//	<i>Intro</i> [C] [G] [Am] [F]
//	   [C]                    [G]
//	Une ligne de paroles quelconque
//
// Implémente chart.TaggedSource : **seuls les accords sont retenus**, les
// paroles ne quittent jamais le backend (règle projet — droit d'auteur).
type echordsSheet struct{}

var _ chart.TaggedSource = echordsSheet{}

// Chords relève les accords entre crochets d'une ligne, dans l'ordre.
func (echordsSheet) Chords(line string) []string {
	var out []string
	for _, m := range echordsBracketRe.FindAllStringSubmatch(line, -1) {
		if tok := strings.TrimSpace(m[1]); chart.IsChord(tok) {
			out = append(out, tok)
		}
	}
	return out
}

// Label extrait un libellé de section : d'abord le texte en italique, sinon une
// pseudo-balise ouvrante maison.
func (echordsSheet) Label(line string) string {
	if m := echordsItalicRe.FindStringSubmatch(line); m != nil {
		// « <i>Intro:</i> » → « Intro » (la ponctuation de fin n'apporte rien au
		// libellé affiché dans la grille).
		if label := strings.Trim(stripTags(m[1]), " \t:-–—*."); label != "" {
			return label
		}
	}
	for _, m := range echordsPseudoTagRe.FindAllStringSubmatch(line, -1) {
		closing, name := m[1] == "/", m[2]
		if closing || echordsHTMLTags[strings.ToLower(name)] {
			continue
		}
		return name
	}
	return ""
}

// Blank : seules les lignes réellement vides coupent une section (une ligne de
// paroles est simplement ignorée — cf. chart.Builder.Break).
func (echordsSheet) Blank(line string) bool {
	return strings.TrimSpace(stripTags(line)) == ""
}

// echordsChart convertit une feuille e-chords en grille au format pivot.
func echordsChart(sheet, key string) (chart.Chart, bool) {
	sections := chart.SectionsFromTaggedLines(sheet, echordsSheet{})
	return chart.New(sections, key, chart.DefaultTime)
}

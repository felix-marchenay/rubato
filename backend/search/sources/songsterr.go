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

// Songsterr — gros catalogue pop/rock international, aux accords **structurés**
// (fondamentale, type, basse) : rien à deviner dans du texte.
//
//  1. recherche → `/api/songs?pattern=…` (JSON, drapeau `hasChords`)
//  2. contenu   → page « chords », état embarqué dans
//     `<script id="state" type="application/json">`, feuille sous
//     `chordpro.current`.
//
// Seule l'harmonie sort du backend, jamais les paroles.

const sourceSongsterr = "songsterr"

const songsterrSearchURL = "https://www.songsterr.com/api/songs"

// Seul l'ID compte : un slug faux est redirigé vers le canonique.
const songsterrChordsURL = "https://www.songsterr.com/a/wsa/%s-chords-s%d"

const songsterrMaxSongs = 3

// La recherche mêle des tabs sans accords (fingerstyle, reprises…) qu'on écarte.
const songsterrSearchSize = 15

// SongsterrSearcher interroge Songsterr.
type SongsterrSearcher struct{}

var _ search.Searcher = (*SongsterrSearcher)(nil)

func (SongsterrSearcher) Name() string { return sourceSongsterr }

func (s SongsterrSearcher) Search(q search.Query) (grids []search.ChordGridResult, lyrics []search.LyricsResult, melodies []search.MelodyResult, err error) {
	params := url.Values{}
	params.Set("pattern", q.Text)
	params.Set("size", fmt.Sprintf("%d", songsterrSearchSize))

	body, err := curlGet(songsterrSearchURL+"?"+params.Encode(), "Accept: application/json")
	if err != nil {
		return nil, nil, nil, fmt.Errorf("songsterr: recherche : %w", err)
	}

	songs, err := parseSongsterrSearch(body, q.Text)
	if err != nil {
		return nil, nil, nil, err
	}
	if len(songs) > songsterrMaxSongs {
		songs = songs[:songsterrMaxSongs]
	}

	for _, song := range songs {
		content, cerr := s.fetchChart(song)
		if cerr != nil {
			log.Printf("songsterr: %q ignoré : %v", song.Title, cerr)
			continue
		}
		grids = append(grids, search.ChordGridResult{
			Title:   song.Title,
			Artist:  song.Artist,
			Source:  sourceSongsterr,
			Content: content,
		})
	}
	return grids, nil, nil, nil
}

type songsterrSong struct {
	ID        int    `json:"songId"`
	Title     string `json:"title"`
	Artist    string `json:"artist"`
	HasChords bool   `json:"hasChords"`
}

// parseSongsterrSearch garde les morceaux qui ont des accords et contiennent
// tous les mots de la requête (sinon « la boheme aznavour » ramène les autres
// titres d'Aznavour), une version par morceau (la première : Songsterr classe
// par pertinence).
func parseSongsterrSearch(body []byte, q string) ([]songsterrSong, error) {
	var all []songsterrSong
	if err := json.Unmarshal(body, &all); err != nil {
		return nil, fmt.Errorf("songsterr: JSON invalide : %w", err)
	}
	words := queryWords(q)
	var out []songsterrSong
	seen := make(map[string]bool)
	for _, s := range all {
		if !s.HasChords || s.ID == 0 || s.Title == "" || !matchesWords(words, s.Title, s.Artist) {
			continue
		}
		key := search.NormalizeKey(s.Title) + "|" + search.NormalizeKey(s.Artist)
		if seen[key] {
			continue
		}
		seen[key] = true
		out = append(out, s)
	}
	return out, nil
}

var slugJunkRe = regexp.MustCompile(`[^a-z0-9]+`)

func songsterrSlug(s songsterrSong) string {
	slug := strings.Trim(slugJunkRe.ReplaceAllString(strings.ToLower(s.Artist+" "+s.Title), "-"), "-")
	if slug == "" {
		return "song"
	}
	return slug
}

func (SongsterrSearcher) fetchChart(s songsterrSong) (string, error) {
	u := fmt.Sprintf(songsterrChordsURL, songsterrSlug(s), s.ID)
	page, err := curlGet(u)
	if err != nil {
		return "", fmt.Errorf("page %s : %w", u, err)
	}
	c, ok := songsterrChart(page)
	if !ok {
		return "", fmt.Errorf("aucune mesure exploitable dans la feuille")
	}
	return c.JSON()
}

var songsterrStateRe = regexp.MustCompile(`(?s)<script id="state" type="application/json">(.*?)</script>`)

type songsterrState struct {
	Chordpro struct {
		Current []songsterrItem `json:"current"`
	} `json:"chordpro"`
}

// songsterrItem : `line`, `section` (Text = libellé), `tuning`, `capo`…
type songsterrItem struct {
	Type string          `json:"type"`
	Text string          `json:"text"`
	Line []songsterrPart `json:"line"`
}

// songsterrPart : `chord`, `text` (paroles) ou `noise` (espaces, barres de rythme).
type songsterrPart struct {
	Type  string          `json:"type"`
	Text  string          `json:"text"`
	Chord *songsterrChord `json:"chord"`
}

// songsterrChord : `firstNote` est la basse ; différente de la fondamentale,
// c'est un renversement (C/G).
type songsterrChord struct {
	BaseNote  songsterrNote `json:"baseNote"`
	FirstNote songsterrNote `json:"firstNote"`
	ChordType struct {
		Suffix string `json:"suffix"`
	} `json:"chordType"`
}

type songsterrNote struct {
	Name string `json:"name"`
}

func (c songsterrChord) Symbol() string {
	if c.BaseNote.Name == "" {
		return ""
	}
	sym := c.BaseNote.Name + c.ChordType.Suffix
	if c.FirstNote.Name != "" && c.FirstNote.Name != c.BaseNote.Name {
		sym += "/" + c.FirstNote.Name
	}
	return sym
}

// songsterrChart : accords structurés, donc pas de filtre chart.IsChord (qui
// rejetterait des notations valides comme « C6/9 »).
func songsterrChart(page []byte) (chart.Chart, bool) {
	m := songsterrStateRe.FindSubmatch(page)
	if m == nil {
		return chart.Chart{}, false
	}
	var st songsterrState
	if err := json.Unmarshal(m[1], &st); err != nil {
		return chart.Chart{}, false
	}

	b := chart.NewBuilder()
	for _, it := range st.Chordpro.Current {
		switch it.Type {
		case "section":
			b.SetLabel(strings.TrimSpace(it.Text))
		case "line":
			var chords []string
			blank := true
			for _, p := range it.Line {
				switch {
				case p.Type == "chord" && p.Chord != nil:
					if sym := p.Chord.Symbol(); sym != "" {
						chords = append(chords, sym)
					}
				case p.Type == "text" && strings.TrimSpace(p.Text) != "":
					blank = false
				}
			}
			if len(chords) > 0 {
				b.AddChords(chords)
			} else if blank {
				b.Break()
			}
		}
	}
	return chart.New(b.Sections(), "", chart.DefaultTime)
}

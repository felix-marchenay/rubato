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

// The Session (thesession.org) — airs traditionnels irlandais / folk, API JSON
// ouverte et sans anti-bot. Les airs sont en ABC, et certaines versions
// (« settings ») portent des accords ("Em") : avec les barres de mesure de
// l'ABC, ce sont de **vraies mesures**, comme le corpus iReal.
//
//  1. recherche → `/tunes/search?q=…&format=json`
//  2. contenu   → `/tunes/<id>?format=json` (toutes les versions de l'air)
//
// Seule l'harmonie est extraite, pas la mélodie.

const sourceTheSession = "thesession"

const (
	theSessionSearchURL = "https://thesession.org/tunes/search"
	theSessionTuneURL   = "https://thesession.org/tunes/%d?format=json"
)

const theSessionMaxTunes = 3

// TheSessionSearcher interroge The Session.
type TheSessionSearcher struct{}

var _ search.Searcher = (*TheSessionSearcher)(nil)

func (TheSessionSearcher) Name() string { return sourceTheSession }

func (t TheSessionSearcher) Search(q search.Query) (grids []search.ChordGridResult, lyrics []search.LyricsResult, melodies []search.MelodyResult, err error) {
	params := url.Values{}
	params.Set("q", q.Text)
	params.Set("format", "json")
	params.Set("perpage", "10")

	body, err := curlGet(theSessionSearchURL+"?"+params.Encode(), "Accept: application/json")
	if err != nil {
		return nil, nil, nil, fmt.Errorf("thesession: recherche : %w", err)
	}
	tunes, err := parseTheSessionSearch(body, q.Text)
	if err != nil {
		return nil, nil, nil, err
	}
	if len(tunes) > theSessionMaxTunes {
		tunes = tunes[:theSessionMaxTunes]
	}

	for _, tune := range tunes {
		content, cerr := t.fetchChart(tune)
		if cerr != nil {
			log.Printf("thesession: %q ignoré : %v", tune.Name, cerr)
			continue
		}
		grids = append(grids, search.ChordGridResult{
			Title:   decodeEntities(tune.Name),
			Artist:  tune.Type,
			Source:  sourceTheSession,
			Content: content,
		})
	}
	return grids, nil, nil, nil
}

type theSessionTune struct {
	ID    int    `json:"id"`
	Name  string `json:"name"`
	Alias string `json:"alias"`
	Type  string `json:"type"` // reel, jig, hornpipe…
}

// parseTheSessionSearch ne garde que les airs dont le nom contient tous les
// mots de la requête : la recherche du site est floue (« creep radiohead »
// renvoie le hornpipe « The Creep »).
func parseTheSessionSearch(body []byte, q string) ([]theSessionTune, error) {
	var resp struct {
		Tunes []theSessionTune `json:"tunes"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, fmt.Errorf("thesession: JSON invalide : %w", err)
	}
	words := queryWords(q)
	var out []theSessionTune
	for _, t := range resp.Tunes {
		if t.ID != 0 && matchesWords(words, t.Name, t.Alias, t.Type) {
			out = append(out, t)
		}
	}
	return out, nil
}

type theSessionSetting struct {
	Key string `json:"key"` // « Edorian », « Gmajor »…
	ABC string `json:"abc"`
}

func (TheSessionSearcher) fetchChart(t theSessionTune) (string, error) {
	body, err := curlGet(fmt.Sprintf(theSessionTuneURL, t.ID), "Accept: application/json")
	if err != nil {
		return "", fmt.Errorf("air %d : %w", t.ID, err)
	}
	var tune struct {
		Settings []theSessionSetting `json:"settings"`
	}
	if err := json.Unmarshal(body, &tune); err != nil {
		return "", fmt.Errorf("thesession: JSON air invalide : %w", err)
	}
	// Beaucoup de versions n'ont pas d'accords : on prend la première qui en a.
	for _, s := range tune.Settings {
		if c, ok := abcChart(s.ABC, theSessionKey(s.Key), theSessionMeters[t.Type]); ok {
			return c.JSON()
		}
	}
	return "", fmt.Errorf("aucune version avec accords")
}

var theSessionMeters = map[string]string{
	"reel": "4/4", "hornpipe": "4/4", "barndance": "4/4", "strathspey": "4/4",
	"jig": "6/8", "slip jig": "9/8", "slide": "12/8", "polka": "2/4",
	"waltz": "3/4", "mazurka": "3/4", "three-two": "3/2",
}

var theSessionKeyRe = regexp.MustCompile(`^([A-G][#b]?)(.*)$`)

// theSessionKey : « Edorian » → « Em », « Gmajor » → « G » (le format pivot ne
// connaît que majeur / mineur).
func theSessionKey(k string) string {
	m := theSessionKeyRe.FindStringSubmatch(strings.TrimSpace(k))
	if m == nil {
		return ""
	}
	switch strings.ToLower(m[2]) {
	case "minor", "dorian", "aeolian", "phrygian", "locrian":
		return m[1] + "m"
	}
	return m[1]
}

var (
	abcDecorationRe  = regexp.MustCompile(`![^!\s|]+!`)
	abcCommentRe     = regexp.MustCompile(`%[^\n]*`)
	abcInlineFieldRe = regexp.MustCompile(`\[[A-Za-z]:[^\]]*\]`)
	// Une fin de reprise suivie d'une 2de fin (« :|2 ») ne clôt pas la partie.
	abcRepeatVoltaRe = regexp.MustCompile(`:+\|+\s*\[?\d+(?:[,-]\d+)*`)
	abcVoltaRe       = regexp.MustCompile(`(\|+)\s*\[?\d+(?:[,-]\d+)*`)
	abcVoltaBrRe     = regexp.MustCompile(`\[\d+(?:[,-]\d+)*`)
	abcTokenRe       = regexp.MustCompile(`"[^"]*"|:*\|[|\]:]*|:{2,}|[A-Ga-g]`)
)

// abcChart lit les accords d'un corps ABC mesure par mesure. Une mesure sans
// accord reprend le précédent (convention du corpus iReal) ; une partie sans
// aucun accord écrit est écartée (version partiellement harmonisée). Les
// reprises ne sont pas dépliées : 1re et 2de fins se suivent.
func abcChart(abc, key, meter string) (chart.Chart, bool) {
	abc = abcDecorationRe.ReplaceAllString(abc, "")
	abc = strings.ReplaceAll(abc, "!", "\n") // saut de ligne façon The Session
	abc = abcCommentRe.ReplaceAllString(abc, "")
	abc = abcInlineFieldRe.ReplaceAllString(abc, "")
	abc = abcRepeatVoltaRe.ReplaceAllString(abc, "|")
	abc = abcVoltaRe.ReplaceAllString(abc, "$1")
	abc = abcVoltaBrRe.ReplaceAllString(abc, "")

	var (
		sections []chart.Section
		cur      []chart.Bar
		bar      []string
		prev     string
		notes    bool // une note lue dans la mesure en cours
		written  int  // accords écrits dans la partie en cours
	)
	flushBar := func() {
		if len(bar) == 0 && prev != "" && notes {
			bar = []string{prev}
		}
		if len(bar) > 0 {
			cur = append(cur, chart.Bar{Chords: bar})
		}
		bar, notes = nil, false
	}
	endPart := func() {
		if len(cur) > 0 && written > 0 {
			sections = append(sections, chart.Section{Label: string(rune('A' + len(sections)%26)), Bars: cur})
		}
		cur, written = nil, 0
	}

	for _, tok := range abcTokenRe.FindAllString(abc, -1) {
		switch tok[0] {
		case '"':
			sym := strings.TrimSpace(tok[1 : len(tok)-1])
			if !chart.IsChord(sym) {
				continue // annotation (« slide », « ^texte »…)
			}
			if len(bar) == 0 && notes && prev != "" {
				bar = append(bar, prev)
			}
			prev = chart.NormalizeChord(sym)
			bar = append(bar, prev)
			written++
		case '|', ':':
			flushBar()
			if strings.ContainsAny(tok, ":]") || strings.Contains(tok, "||") {
				endPart()
			}
		default:
			notes = true
		}
	}
	flushBar()
	endPart()
	return chart.New(sections, key, meter)
}

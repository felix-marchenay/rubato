// Package chart porte le **format pivot** des grilles d'accords de Rubato : le
// même JSON que les assets `assets/charts/<id>.json` et que le codec Dart
// `JsonChordChartCodec`.
//
//	{ "key": "Dm", "time": "4/4",
//	  "sections": [ { "label": "A", "bars": [ { "chords": ["D-7"] } ] } ] }
//
// Toutes les sources (e-chords, Ultimate Guitar…) convertissent leur format
// maison vers celui-ci : l'app n'a donc qu'un seul décodeur à connaître, quelle
// que soit l'origine du morceau.
//
// Droit d'auteur : ce format ne transporte que l'**harmonie** (des accords).
// Aucune parole ne doit y arriver — c'est la garantie structurelle qui remplace
// les feuilles brutes (accords + paroles) renvoyées par les sources.
package chart

import "encoding/json"

// DefaultTime : métrique utilisée quand la source ne la donne pas. Les sources
// scrapées ne fournissent pas de vraies barres de mesure (voir Builder), donc
// c'est presque toujours cette valeur.
const DefaultTime = "4/4"

// Bar : une mesure, c'est-à-dire une liste d'accords (souvent un seul).
type Bar struct {
	Chords []string `json:"chords"`
}

// Section : un bloc de mesures, avec un libellé optionnel (Intro, Verse 1…).
type Section struct {
	Label string `json:"label,omitempty"`
	Bars  []Bar  `json:"bars"`
}

// Chart : la grille complète. Key et Time vides sont omis du JSON (le codec
// Dart les accepte absents/null).
type Chart struct {
	Key      string    `json:"key,omitempty"`
	Time     string    `json:"time,omitempty"`
	Sections []Section `json:"sections"`
}

// New assemble une grille en écartant les sections sans mesure. ok=false quand
// il ne reste rien d'exploitable : l'appelant doit alors abandonner le résultat
// (mieux vaut pas de grille qu'une grille vide).
func New(sections []Section, key, time string) (Chart, bool) {
	clean := make([]Section, 0, len(sections))
	for _, s := range sections {
		if len(s.Bars) > 0 {
			clean = append(clean, s)
		}
	}
	if len(clean) == 0 {
		return Chart{}, false
	}
	if time == "" {
		time = DefaultTime
	}
	return Chart{Key: key, Time: time, Sections: clean}, true
}

// JSON sérialise la grille au format pivot. C'est ce que les sources mettent
// dans le champ Content d'un résultat de recherche.
func (c Chart) JSON() (string, error) {
	b, err := json.Marshal(c)
	if err != nil {
		return "", err
	}
	return string(b), nil
}

// Bars compte les mesures de toutes les sections (diagnostic, logs).
func (c Chart) Bars() int {
	n := 0
	for _, s := range c.Sections {
		n += len(s.Bars)
	}
	return n
}

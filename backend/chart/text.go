package chart

import (
	"regexp"
	"strings"
)

// Repérage des accords dans du texte. Portage des heuristiques du backend JS
// (netlify/functions/scrapers.mjs, supprimé) — mêmes règles, mêmes limites.

// chordRe : racine A–G + altération, puis une qualité faite uniquement de
// caractères d'accord. Volontairement permissif sur la qualité, strict sur la
// forme d'ensemble : c'est ce qui évite d'attraper des mots de paroles (« Am I
// free » → « Am » oui, « free » non).
var chordRe = regexp.MustCompile(
	`^[A-G][#b]?(?:maj|min|aug|dim|sus|add|alt|omit|no|m|M|Δ|ø|°|\+|-|\d|[#b]|\(|\)|/[A-G][#b]?)*$`)

// maxChordLen : au-delà, ce n'est plus un accord mais du texte.
const maxChordLen = 12

// IsChord dit si un token isolé ressemble à un accord.
func IsChord(tok string) bool {
	switch tok {
	case "":
		return false
	case "N.C.", "NC", "%":
		return true
	}
	if len(tok) > maxChordLen {
		return false
	}
	return chordRe.MatchString(tok)
}

// NormalizeChord uniformise les notations équivalentes à l'entrée du format
// pivot (le reste est laissé tel quel : c'est le parser Dart qui interprète).
func NormalizeChord(c string) string {
	if c == "NC" {
		return "N.C."
	}
	return c
}

var (
	bracketLabelRe = regexp.MustCompile(`^\[([^\]]{1,30})\]$`)
	sectionWordRe  = regexp.MustCompile(`(?i)^(intro|verse|couplet|chorus|refrain|bridge|pont|pre-?chorus|` +
		`outro|solo|interlude|coda|ending|part\s|section\s)\b`)
	// Les grilles jazz nomment souvent leurs sections d'une seule lettre (A, B,
	// C…). On exige que la **ligne entière** soit cette lettre : sinon un accord
	// mal reconnu (« F#7/13b ») passerait pour un libellé de section.
	singleLetterLabelRe = regexp.MustCompile(`^([A-Ha-h])\s*[:.)\-]?$`)
	labelTrailRe        = regexp.MustCompile(`[:*\-\d.]+$`)
)

// Label reconnaît une ligne d'en-tête de section — « [Verse 1] », « Refrain: »,
// « A » — et renvoie son libellé. ok=false si la ligne n'en est pas une.
func Label(line string) (string, bool) {
	t := strings.TrimSpace(line)
	if m := bracketLabelRe.FindStringSubmatch(t); m != nil {
		l := strings.TrimSpace(m[1])
		return l, l != ""
	}
	if len([]rune(t)) <= 24 && sectionWordRe.MatchString(t) {
		l := strings.TrimSpace(labelTrailRe.ReplaceAllString(t, ""))
		return l, l != ""
	}
	if m := singleLetterLabelRe.FindStringSubmatch(t); m != nil {
		return strings.ToUpper(m[1]), true
	}
	return "", false
}

// Builder assemble des sections au fil d'un texte lu ligne par ligne. Chaque
// source repère les accords à sa façon, mais toutes produisent la même
// structure : des blocs de mesures, séparés par des ruptures, avec un libellé
// éventuel repris de l'en-tête qui précède.
//
// Choix produit (inchangé depuis le backend JS) : **une mesure = un accord**.
// On ne tente pas de reconstruire les vraies barres à partir d'une feuille
// « accords au-dessus des paroles » ; les sources qui donnent de vraies mesures
// (iReal) auront leur propre chemin.
type Builder struct {
	sections []Section
	pending  string // libellé en attente pour la prochaine section ouverte
	gap      bool   // rupture vue → la prochaine mesure ouvre une section
}

// NewBuilder crée un assembleur vide (la première mesure ouvrira une section).
func NewBuilder() *Builder { return &Builder{gap: true} }

// SetLabel retient un libellé pour la prochaine section, et marque une rupture :
// un en-tête ferme toujours la section en cours.
func (b *Builder) SetLabel(label string) {
	b.pending = label
	b.gap = true
}

// Break marque une rupture de section (ligne vide, fin de bloc).
//
// Attention : une ligne de **paroles** n'est PAS une rupture. C'est la seule
// différence assumée avec le backend JS, qui coupait à chaque ligne non-accord
// et débitait donc un couplet en une dizaine de sections de deux mesures. Ici
// un couplet reste un bloc, coupé par les lignes vides et les en-têtes.
func (b *Builder) Break() { b.gap = true }

// AddChords ajoute une mesure par accord à la section courante (en ouvrant une
// section si une rupture vient d'avoir lieu).
func (b *Builder) AddChords(chords []string) {
	if len(chords) == 0 {
		return
	}
	if b.gap || len(b.sections) == 0 {
		b.sections = append(b.sections, Section{Label: b.pending})
		b.pending = ""
		b.gap = false
	}
	s := &b.sections[len(b.sections)-1]
	for _, c := range chords {
		s.Bars = append(s.Bars, Bar{Chords: []string{NormalizeChord(c)}})
	}
}

// Sections renvoie les sections accumulées (à passer à New).
func (b *Builder) Sections() []Section { return b.sections }

// SectionsFromChordLines convertit un texte « accords au-dessus des paroles »
// (ou des blocs d'accords purs) en sections : une ligne dont **tous** les
// tokens sont des accords est une ligne d'accords ; les autres lignes ne
// donnent qu'un libellé éventuel. Format d'entrée d'Ultimate Guitar après
// nettoyage de ses balises.
//
// Les paroles ne sont jamais reprises : seule l'harmonie sort d'ici.
func SectionsFromChordLines(text string) []Section {
	b := NewBuilder()
	for _, raw := range SplitLines(text) {
		line := strings.TrimSpace(raw)
		if line == "" {
			b.Break()
			continue
		}
		if tokens := strings.Fields(line); allChords(tokens) {
			b.AddChords(tokens)
			continue
		}
		if label, ok := Label(line); ok {
			b.SetLabel(label)
		}
	}
	return b.Sections()
}

// TaggedSource décrit une source dont les accords sont **balisés** dans le
// texte — entre crochets chez e-chords (`[C]`), en gras chez Cifra Club
// (`<b>C</b>`) — au lieu d'être alignés sur des lignes d'accords pures comme
// chez Ultimate Guitar (voir SectionsFromChordLines).
//
// Trois questions par ligne, c'est tout ce qui distingue ces sources : d'où les
// accords viennent, où est le libellé de section, ce qui compte comme rupture.
type TaggedSource interface {
	// Chords relève les accords de la ligne, dans l'ordre de lecture.
	Chords(line string) []string
	// Label renvoie le libellé de section porté par la ligne, ou "" si aucun.
	Label(line string) string
	// Blank dit si la ligne vaut rupture de section (ligne vide, séparateur).
	Blank(line string) bool
}

// SectionsFromTaggedLines assemble les sections d'une source à accords balisés.
// Les paroles ne sont jamais reprises : seuls les accords que Chords relève
// entrent dans la grille.
func SectionsFromTaggedLines(text string, src TaggedSource) []Section {
	b := NewBuilder()
	for _, line := range SplitLines(text) {
		if label := src.Label(line); label != "" {
			b.SetLabel(label)
		}
		if chords := src.Chords(line); len(chords) > 0 {
			b.AddChords(chords)
			continue
		}
		if src.Blank(line) {
			b.Break()
		}
	}
	return b.Sections()
}

// SplitLines découpe un texte en lignes (CRLF ou LF) en neutralisant les
// espaces exotiques que les pages web glissent entre les accords (insécables,
// largeur nulle) — sinon `strings.Fields` ne sépare pas les tokens.
func SplitLines(text string) []string {
	text = strings.ReplaceAll(text, "\r\n", "\n")
	text = strings.ReplaceAll(text, "\r", "\n")
	text = strings.Map(spaceLike, text)
	return strings.Split(text, "\n")
}

func spaceLike(r rune) rune {
	switch r {
	case '\u00a0', '\u2007', '\u202f', '\t': // espaces insécables, tabulation
		return ' '
	case '\u200b', '\ufeff': // largeur nulle, BOM → supprimés
		return -1
	}
	return r
}

func allChords(tokens []string) bool {
	if len(tokens) == 0 {
		return false
	}
	for _, t := range tokens {
		if !IsChord(t) {
			return false
		}
	}
	return true
}

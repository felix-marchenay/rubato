package sources

import (
	"strings"
	"testing"
)

const cifraClubSearchJSON = `{"response":{"numFound":2,"docs":[
  {"t":"2","art":"Radiohead","dns":"radiohead","txt":"Creep","url":"creep"},
  {"t":"2","art":"Sans slug","dns":"","txt":"Inutilisable","url":""}
]}}`

// La page imprimable, réduite à sa structure : un <pre>, des accords en <b>, un
// bloc de tablature imbriqué, et une ligne de paroles bidon (pas de vraies
// paroles dans les fixtures).
const cifraClubPage = `<html><body><div>tom:  <span>G</span></div><pre>[Intro] <b>G</b>  <b>B</b>  <b>C</b>

<span class="tablatura">[Tab - Intro]
   <b>G</b>
<span class="cnt">E|-----3----|
B|-----0----|</span></span>

[Primeira Parte]
<b>Am</b>            <b>F</b>
blabla bla blabla
</pre></body></html>`

func TestParseCifraClubSearch(t *testing.T) {
	songs, err := parseCifraClubSearch([]byte(cifraClubSearchJSON))
	if err != nil {
		t.Fatalf("parseCifraClubSearch : %v", err)
	}
	// Le document sans slug est inutilisable : on ne peut pas construire son URL.
	if len(songs) != 1 {
		t.Fatalf("nb songs = %d, want 1 (%+v)", len(songs), songs)
	}
	if songs[0].Title != "Creep" || songs[0].ArtistDNS != "radiohead" || songs[0].SongURL != "creep" {
		t.Errorf("song = %+v", songs[0])
	}
}

// Le point délicat : les blocs de tablature contiennent des lettres de cordes
// (E, B, G…) et des accords en <b> qui ne sont pas dans la grille. Ils doivent
// disparaître avant l'analyse.
func TestCifraClubChartIgnoresTablature(t *testing.T) {
	c, ok := cifraClubChart([]byte(cifraClubPage))
	if !ok {
		t.Fatal("cifraClubChart = ok false, want true")
	}
	if c.Key != "G" {
		t.Errorf("key = %q, want G (lu dans « tom: »)", c.Key)
	}
	if len(c.Sections) != 2 {
		t.Fatalf("nb sections = %d, want 2 (%+v)", len(c.Sections), c.Sections)
	}
	if c.Sections[0].Label != "Intro" || len(c.Sections[0].Bars) != 3 {
		t.Errorf("section 0 = %+v, want Intro avec 3 mesures", c.Sections[0])
	}
	if c.Sections[1].Label != "Primeira Parte" || len(c.Sections[1].Bars) != 2 {
		t.Errorf("section 1 = %+v, want « Primeira Parte » avec 2 mesures", c.Sections[1])
	}

	js, err := c.JSON()
	if err != nil {
		t.Fatalf("JSON : %v", err)
	}
	if strings.Contains(js, "blabla") {
		t.Errorf("la grille contient des paroles : %s", js)
	}
	// Le <b>G</b> qui étiquette la tablature ne doit pas avoir créé de mesure :
	// 3 (intro) + 2 (couplet) et rien d'autre.
	if got := c.Bars(); got != 5 {
		t.Errorf("nb mesures = %d, want 5", got)
	}
}

func TestCifraClubChartWithoutPre(t *testing.T) {
	if _, ok := cifraClubChart([]byte("<html>rien</html>")); ok {
		t.Error("cifraClubChart = ok true, want false")
	}
}

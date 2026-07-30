package sources

import (
	"strings"
	"testing"
)

// Fixtures synthétiques : une page UG réelle pèse ~1 Mo et contiendrait de
// vraies paroles. On reproduit seulement la structure exploitée (le js-store et
// ses balises `[ch]…[/ch]`), avec des paroles bidon.
const ugSearchPage = `<html><body>` +
	`<div class="js-store" data-content="{&quot;store&quot;:{&quot;page&quot;:{&quot;data&quot;:{&quot;results&quot;:[` +
	`{&quot;type&quot;:null,&quot;song_name&quot;:&quot;Demo&quot;,&quot;artist_name&quot;:&quot;Untel&quot;,&quot;tab_url&quot;:&quot;https://www.ultimate-guitar.com/pro/?tab_id=1&quot;},` +
	`{&quot;type&quot;:&quot;Chords&quot;,&quot;song_name&quot;:&quot;Demo&quot;,&quot;artist_name&quot;:&quot;Untel&quot;,&quot;tab_url&quot;:&quot;https://tabs.ultimate-guitar.com/tab/untel/demo-chords-1&quot;,&quot;votes&quot;:12},` +
	`{&quot;type&quot;:&quot;Chords&quot;,&quot;song_name&quot;:&quot;Demo&quot;,&quot;artist_name&quot;:&quot;Untel&quot;,&quot;tab_url&quot;:&quot;https://tabs.ultimate-guitar.com/tab/untel/demo-chords-2&quot;,&quot;votes&quot;:3},` +
	`{&quot;type&quot;:&quot;Chords&quot;,&quot;song_name&quot;:&quot;Autre&quot;,&quot;artist_name&quot;:&quot;Untel&quot;,&quot;tab_url&quot;:&quot;https://tabs.ultimate-guitar.com/tab/untel/autre-chords-3&quot;}` +
	`]}}}}"></div></body></html>`

const ugTabPage = `<html><body>` +
	`<div class="js-store" data-content="{&quot;store&quot;:{&quot;page&quot;:{&quot;data&quot;:{` +
	`&quot;tab&quot;:{&quot;tonality_name&quot;:&quot;C&quot;},` +
	`&quot;tab_view&quot;:{&quot;wiki_tab&quot;:{&quot;content&quot;:&quot;[Intro]\n[ch]C[/ch] [ch]G[/ch]\n\n[Verse 1]\n[tab][ch]Am[/ch]    [ch]F[/ch]\nblabla bla blabla[/tab]&quot;}}` +
	`}}}}"></div></body></html>`

// parseUGSearch ne garde que les tabs d'accords, et une seule version par
// morceau (la mieux classée par UG, donc la première rencontrée).
func TestParseUGSearch(t *testing.T) {
	tabs, err := parseUGSearch([]byte(ugSearchPage))
	if err != nil {
		t.Fatalf("parseUGSearch : %v", err)
	}
	if len(tabs) != 2 {
		t.Fatalf("nb tabs = %d, want 2 (%+v)", len(tabs), tabs)
	}
	if tabs[0].SongName != "Demo" || !strings.HasSuffix(tabs[0].TabURL, "demo-chords-1") {
		t.Errorf("tab 0 = %+v, want la première version de Demo", tabs[0])
	}
	if tabs[1].SongName != "Autre" {
		t.Errorf("tab 1 = %+v, want Autre", tabs[1])
	}
}

func TestParseUGSearchWithoutStore(t *testing.T) {
	if _, err := parseUGSearch([]byte("<html>page inattendue</html>")); err == nil {
		t.Fatal("parseUGSearch = nil, want une erreur")
	}
}

// ugChart : accords `[ch]…[/ch]` → grille au format pivot, en-têtes `[Verse 1]`
// → libellés, et aucune parole dans la sortie.
func TestUGChart(t *testing.T) {
	c, ok := ugChart([]byte(ugTabPage))
	if !ok {
		t.Fatal("ugChart = ok false, want true")
	}
	if c.Key != "C" {
		t.Errorf("key = %q, want C", c.Key)
	}
	if len(c.Sections) != 2 {
		t.Fatalf("nb sections = %d, want 2 (%+v)", len(c.Sections), c.Sections)
	}
	if c.Sections[0].Label != "Intro" || len(c.Sections[0].Bars) != 2 {
		t.Errorf("section 0 = %+v, want Intro avec 2 mesures", c.Sections[0])
	}
	if c.Sections[1].Label != "Verse 1" || len(c.Sections[1].Bars) != 2 {
		t.Errorf("section 1 = %+v, want « Verse 1 » avec 2 mesures", c.Sections[1])
	}

	js, err := c.JSON()
	if err != nil {
		t.Fatalf("JSON : %v", err)
	}
	if strings.Contains(js, "blabla") {
		t.Errorf("la grille contient des paroles : %s", js)
	}
}

// Garde-fou : on ne suit pas une URL hors du domaine UG (le champ vient d'une
// page scrapée, donc d'une source non fiable).
func TestUGRejectsForeignHost(t *testing.T) {
	if _, err := (UltimateGuitarSearcher{}).fetchChart(ugTab{TabURL: "https://exemple.test/tab"}); err == nil {
		t.Fatal("fetchChart = nil, want une erreur")
	}
}

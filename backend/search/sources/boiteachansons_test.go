package sources

import (
	"reflect"
	"strings"
	"testing"
)

const boiteSearchJSON = `[
  {"titre":"Untel","typeResult":"a","auteur":"","nb":"3","version":"","fichierAuteur":"untel","fichierChanson":null},
  {"titre":" Demo","typeResult":"p","auteur":"Autre","nb":"1","version":"","fichierAuteur":"autre","fichierChanson":"demo"},
  {"titre":"Demo","typeResult":"p","auteur":"Untel|Truc","nb":"3|1","version":"version live","fichierAuteur":"untel|truc","fichierChanson":"demo"}
]`

func TestParseBoiteSearch(t *testing.T) {
	songs, err := parseBoiteSearch([]byte(boiteSearchJSON))
	if err != nil {
		t.Fatalf("parseBoiteSearch : %v", err)
	}
	if len(songs) != 2 {
		t.Fatalf("nb songs = %d, want 2 (l'artiste est écarté) : %+v", len(songs), songs)
	}
	if got := songs[1].displayTitle(); got != "Demo (version live)" {
		t.Errorf("titre = %q", got)
	}
	if got := songs[1].displayArtist(); got != "Untel, Truc" {
		t.Errorf("artiste = %q", got)
	}
}

// Le titre et l'artiste ne se cherchent pas ensemble sur le site : on relance
// en retirant des mots, que les morceaux trouvés devront contenir.
func TestBoiteQueries(t *testing.T) {
	got := boiteQueries("la boheme aznavour")
	want := []boiteQuery{
		{text: "la boheme aznavour"},
		{text: "la boheme", dropped: "aznavour"},
		{text: "boheme aznavour", dropped: "la"},
		{text: "aznavour", dropped: "la boheme"},
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("boiteQueries = %+v, want %+v", got, want)
	}
	if got := boiteQueries("ab"); len(got) != 1 {
		t.Errorf("boiteQueries(ab) = %+v, want la seule requête d'origine", got)
	}
}

// Structure réelle d'une partition, paroles bidon : une div par ligne, lignes
// vides pLVV, ligne instrumentale pLI, paroles seules pLS, tablature ignorée.
const boitePage = `<html><body>
<input type="hidden" id="tonalite" name="tonalite" value="A">
<div style="display:none;" id="divPartitionPerso" class="divPartition"></div>
<div id="divPartition" class="divPartition"><div class="tabT"><div class="tabR"><div class="tabC"><span>e</span></div></div></div>` +
	`<div class="pLI"><span class="ALI"><span class="a" data-a="Dm" data-aff="Dm"></span></span> <span class="ALI"><span class="a" data-a="E7" data-aff="E7"></span></span></div>` +
	`<div class="pLVV"></div>` +
	`<div class="pL"><span class="sI"><span class="a" data-a="Dm" data-aff="Dm"></span></span>blabla <span class="sI"><span class="a" data-a="Bm7(b5)" data-aff="Bm7(b5)"></span></span>bla</div>` +
	`<div class="pLS">blabla sans accord</div>` +
	`<div class="pL">bla <span class="sI"><span class="a" data-a="Dm7/4" data-aff="Dm7/4"></span></span>bla <span class="sI"><span class="a" data-a="Am" data-aff="Am"></span></span></div>` +
	`</div></div><div id="divDroitePagePartition"><span class="a" data-a="C"></span></div></body></html>`

func TestBoiteChart(t *testing.T) {
	c, ok := boiteChart([]byte(boitePage))
	if !ok {
		t.Fatal("boiteChart = ok false, want true")
	}
	if c.Key != "Am" {
		t.Errorf("key = %q, want Am (tonique A, finit sur Am)", c.Key)
	}
	if len(c.Sections) != 2 {
		t.Fatalf("nb sections = %d, want 2 (%+v)", len(c.Sections), c.Sections)
	}
	if n := len(c.Sections[0].Bars); n != 2 {
		t.Errorf("intro = %d mesures, want 2", n)
	}
	var got []string
	for _, b := range c.Sections[1].Bars {
		got = append(got, b.Chords...)
	}
	if want := []string{"Dm", "Bm7(b5)", "Dm7/4", "Am"}; !reflect.DeepEqual(got, want) {
		t.Errorf("couplet = %q, want %q", got, want)
	}

	js, _ := c.JSON()
	if strings.Contains(js, "blabla") {
		t.Errorf("la grille contient des paroles : %s", js)
	}
}

func TestBoiteChartWithoutPartition(t *testing.T) {
	if _, ok := boiteChart([]byte("<html>rien</html>")); ok {
		t.Error("boiteChart = ok true, want false")
	}
}

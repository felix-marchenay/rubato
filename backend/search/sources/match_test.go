package sources

import "testing"

func TestMatchesWords(t *testing.T) {
	for _, c := range []struct {
		q    string
		want bool
	}{
		{"boheme aznav", true}, // accents ignorés, début de mot suffisant
		{"LA BOHÈME", true},
		{"la boheme brel", false},
		{"heme", false}, // milieu de mot
		{"", true},
	} {
		if got := matchesWords(queryWords(c.q), "La Bohème", "Charles Aznavour"); got != c.want {
			t.Errorf("matchesWords(%q) = %v, want %v", c.q, got, c.want)
		}
	}
}

#!/usr/bin/env python3
"""Génère le catalogue de Rubato : un fichier de grille par morceau
(assets/charts/<id>.json) + l'index assets/catalog.json.

Contenu : grilles d'accords UNIQUEMENT (aucune parole, aucune mélodie) — de
l'information harmonique, façon real book. Les standards de jazz visent des
changements corrects ; la soul et la pop utilisent les progressions courantes
(boucles) et sont à affiner à l'oreille.

Notation (alignée iReal Pro), voir lib/src/codec/chord_parser.dart :
  -   mineur (C-7 = Cm7)       ^   maj7 (C^7 = Cmaj7)
  h   demi-diminué (Dh7)       o   diminué (Co7)
  /   basse slash (C/E)        7b9, sus, add9, #11, b5… conservés tels quels

Format des sections : "accord accord | accord | …" (| sépare les mesures,
l'espace sépare plusieurs accords dans une même mesure).

Usage :  python3 scripts/seed_catalog.py
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CHARTS_DIR = os.path.join(ROOT, "assets", "charts")
LYRICS_DIR = os.path.join(ROOT, "assets", "lyrics")
CATALOG = os.path.join(ROOT, "assets", "catalog.json")


def S(id, title, artist, tags, key, time, sections, lyrics=None):
    # `lyrics` : texte ChordPro optionnel (paroles + accords entre crochets).
    # Droits d'auteur : ne mettre ici QUE des paroles libres de droits ou
    # écrites par soi-même. Le catalogue fourni n'embarque pas de paroles
    # protégées.
    return dict(id=id, title=title, artist=artist, tags=tags,
                key=key, time=time, sections=sections, lyrics=lyrics)


SONGS = [
    # ─────────────── STANDARDS DE JAZZ ───────────────
    S("autumn-leaves", "Autumn Leaves", "Joseph Kosma", ["jazz", "standard"], "Gm", "4/4", [
        ("A", "C-7 | F7 | Bb^7 | Eb^7 | Ah7 | D7b9 | G-6 | G-6"),
        ("B", "Ah7 | D7b9 | G-6 | G-6 | C-7 | F7 | Bb^7 | Eb^7"),
    ]),
    S("blue-bossa", "Blue Bossa", "Kenny Dorham", ["jazz", "bossa"], "Cm", "4/4", [
        ("A", "C-7 | C-7 | F-7 | F-7 | Dh7 | G7b9 | C-7 | C-7 | "
              "Eb-7 | Ab7 | Db^7 | Db^7 | Dh7 | G7b9 | C-7 | Dh7 G7b9"),
    ]),
    S("blues-in-c", "Twelve-Bar Blues in C", "Traditional", ["blues"], "C", "4/4", [
        ("Blues", "C7 | F7 | C7 | C7 | F7 | F7 | C7 | C7 | G7 | F7 | C7 | G7"),
    ], lyrics="""{title: Twelve-Bar Blues in C}
{key: C}
{time: 4/4}

{comment: Couplet 1}
[C7]Woke up this mornin', my [F7]coffee had gone [C7]cold
[F7]Woke up this mornin', my [C7]coffee had gone cold
[G7]Nothin' left to warm me but the [F7]tales the night had [C7]told [G7]

{comment: Couplet 2}
[C7]Train down at the station, I can [F7]hear that whistle [C7]cry
[F7]Train down at the station, I can [C7]hear that whistle cry
[G7]Carry me on over where the [F7]river meets the [C7]sky [G7]
"""),
    S("someday-my-prince", "Someday My Prince Will Come", "Frank Churchill", ["jazz", "waltz"], "Bb", "3/4", [
        ("A", "Bb^7 | G-7 | C-7 | F7 | Bb^7 | G-7 | C-7 F7 | Bb^7"),
    ]),
    S("all-of-me", "All of Me", "Gerald Marks", ["jazz", "standard"], "C", "4/4", [
        ("A", "C^7 | C^7 | E7 | E7 | A7 | A7 | D-7 | D-7"),
        ("B", "E7 | E7 | A-7 | A-7 | D7 | D7 | D-7 | G7"),
    ]),
    S("fly-me-to-the-moon", "Fly Me to the Moon", "Bart Howard", ["jazz", "standard"], "C", "4/4", [
        ("A", "A-7 | D-7 | G7 | C^7 | F^7 | Bh7 | E7 | A-7 A7"),
        ("B", "D-7 | G7 | C^7 | E7 | A-7 | D-7 | G7 | C^7 Bh7 E7"),
    ]),
    S("take-the-a-train", "Take the \"A\" Train", "Billy Strayhorn", ["jazz", "standard"], "C", "4/4", [
        ("A", "C^7 | C^7 | D7#11 | D7#11 | D-7 | G7 | C^7 | C^7"),
    ]),
    S("summertime", "Summertime", "George Gershwin", ["jazz", "standard"], "Am", "4/4", [
        ("A", "A-6 | A-6 | E7 | E7 | A-6 | A-6 | D-6 | E7 | A-6 | C7 | F^7 | E7 | A-6 | A-6"),
    ]),
    S("so-what", "So What", "Miles Davis", ["jazz", "modal"], "Dm", "4/4", [
        ("A", "D-7 | D-7 | D-7 | D-7 | D-7 | D-7 | D-7 | D-7"),
        ("B", "Eb-7 | Eb-7 | Eb-7 | Eb-7 | D-7 | D-7 | D-7 | D-7"),
    ]),
    S("all-the-things-you-are", "All the Things You Are", "Jerome Kern", ["jazz", "standard"], "Ab", "4/4", [
        ("A", "F-7 | Bb-7 | Eb7 | Ab^7 | Db^7 | D-7 G7 | C^7 | C^7"),
        ("B", "C-7 | F-7 | Bb7 | Eb^7 | Ab^7 | Ah7 D7 | G^7 | G^7"),
    ]),
    S("misty", "Misty", "Erroll Garner", ["jazz", "ballad"], "Eb", "4/4", [
        ("A", "Eb^7 | Bb-7 Eb7 | Ab^7 | Ab-7 Db7 | Eb^7 C-7 | F-7 Bb7 | Eb6 C-7 | F-7 Bb7"),
    ]),
    S("satin-doll", "Satin Doll", "Duke Ellington", ["jazz", "standard"], "C", "4/4", [
        ("A", "D-7 G7 | D-7 G7 | E-7 A7 | E-7 A7 | A-7 D7 | A-7 D7 | Ab-7 Db7 | C^7"),
    ]),
    S("girl-from-ipanema", "The Girl from Ipanema", "Antonio Carlos Jobim", ["jazz", "bossa"], "F", "4/4", [
        ("A", "F^7 | F^7 | G7 | G7 | G-7 | Gb7 | F^7 | Gb7"),
        ("B", "Gb^7 | Gb^7 | B7 | B7 | F#-7 | F#-7 | D7 | D7 | "
              "G-7 | G-7 | Eb7 | Eb7 | A-7 | D7 | G-7 | C7"),
    ]),
    S("wave", "Wave", "Antonio Carlos Jobim", ["jazz", "bossa"], "D", "4/4", [
        ("A", "D^7 | Bb7 | A-7 | D7 | G^7 | G-6 | F#-7 | B7 | E-7 | A7 | D6 | A7"),
    ]),
    S("black-orpheus", "Manhã de Carnaval", "Luiz Bonfá", ["jazz", "bossa"], "Am", "4/4", [
        ("A", "A-7 | Bh7 E7 | A-7 | Bh7 E7 | A-7 | D-7 | E7 | A-7 A7"),
        ("B", "D-7 | G7 | C^7 | F^7 | Bh7 | E7 | A-7 | E7"),
    ]),
    S("cantaloupe-island", "Cantaloupe Island", "Herbie Hancock", ["jazz", "modal"], "Fm", "4/4", [
        ("A", "F-7 | F-7 | F-7 | F-7 | Db7 | Db7 | Db7 | Db7 | "
              "D-7 | D-7 | D-7 | D-7 | F-7 | F-7 | F-7 | F-7"),
    ]),
    S("watermelon-man", "Watermelon Man", "Herbie Hancock", ["jazz", "funk"], "F", "4/4", [
        ("A", "F7 | F7 | F7 | F7 | Bb7 | Bb7 | F7 | F7 | C7 | Bb7 | F7 | C7"),
    ]),
    S("song-for-my-father", "Song for My Father", "Horace Silver", ["jazz", "latin"], "Fm", "4/4", [
        ("A", "F-7 | Eb7 | Db7 | C7 | F-7 | Eb7 | Db7 | C7"),
    ]),
    S("st-thomas", "St. Thomas", "Sonny Rollins", ["jazz", "calypso"], "C", "4/4", [
        ("A", "C^7 | C^7 | D-7 G7 | C^7 | C^7 | E7 | A-7 | D-7 G7 | C^7 | C^7"),
    ]),
    S("blue-monk", "Blue Monk", "Thelonious Monk", ["jazz", "blues"], "Bb", "4/4", [
        ("Blues", "Bb7 | Eb7 | Bb7 | Bb7 | Eb7 | Eb7 | Bb7 | G7 | C-7 | F7 | Bb7 G7 | C-7 F7"),
    ]),
    S("round-midnight", "'Round Midnight", "Thelonious Monk", ["jazz", "ballad"], "Ebm", "4/4", [
        ("A", "Eb-7 | Bh7 Eb7b9 | Ab-7 | Db7 | Gb^7 | Bh7 E7 | Eb-7 Ab7 | Db^7"),
    ]),
    S("body-and-soul", "Body and Soul", "Johnny Green", ["jazz", "ballad"], "Db", "4/4", [
        ("A", "Eb-7 | Bb7 | Eb-7 Ab7 | Db^7 Gb7 | F-7 Bb7 | Eb-7 Ab7 | Db^7 | Db^7"),
    ]),
    S("my-funny-valentine", "My Funny Valentine", "Richard Rodgers", ["jazz", "ballad"], "Cm", "4/4", [
        ("A", "C-7 | C-^7 | C-7 | C-6 | Ab^7 | F-7 | Dh7 | G7b9"),
    ]),
    S("bye-bye-blackbird", "Bye Bye Blackbird", "Ray Henderson", ["jazz", "standard"], "F", "4/4", [
        ("A", "F^7 | G-7 C7 | F^7 | A-7 D7 | G-7 | C7 | F^7 | F^7"),
    ]),
    S("another-you", "There Will Never Be Another You", "Harry Warren", ["jazz", "standard"], "Eb", "4/4", [
        ("A", "Eb^7 | Dh7 G7 | C-7 | Bb-7 Eb7 | Ab^7 | Db7 | Eb^7 C-7 | F-7 Bb7"),
    ]),
    S("recorda-me", "Recorda Me", "Joe Henderson", ["jazz", "latin"], "Am", "4/4", [
        ("A", "A-^7 | A-^7 | C-7 F7 | Bb^7 | Bb-7 Eb7 | Ab^7 | Ab-7 Db7 | Gb^7"),
    ]),
    S("maiden-voyage", "Maiden Voyage", "Herbie Hancock", ["jazz", "modal"], "D", "4/4", [
        ("A", "A7sus | A7sus | A7sus | A7sus | C7sus | C7sus | C7sus | C7sus"),
    ]),
    S("dont-get-around", "Don't Get Around Much Anymore", "Duke Ellington", ["jazz", "standard"], "C", "4/4", [
        ("A", "A-7 D7 | C^7 | A-7 D7 | C^7 | D-7 G7 | E-7 A7 | D-7 | G7"),
    ]),
    S("sentimental-mood", "In a Sentimental Mood", "Duke Ellington", ["jazz", "ballad"], "Dm", "4/4", [
        ("A", "D-^7 | D-7 | G-^7 | G-7 | D-7 | Bb7 A7 | D-7 Gb7 | G-7 C7"),
    ]),
    S("nardis", "Nardis", "Miles Davis", ["jazz", "modal"], "Em", "4/4", [
        ("A", "E-7 | F^7 | C^7 | Bb7#11 | A-7 | D7 | E-7 | E-7"),
    ]),

    # ─────────────── STEVIE WONDER ───────────────
    S("superstition", "Superstition", "Stevie Wonder", ["soul", "funk"], "Ebm", "4/4", [
        ("A", "Eb-7 | Eb-7 | Eb-7 | Eb-7"),
        ("B", "Ab7 | Ab7 | Bb7 | Bb7"),
    ]),
    S("i-wish", "I Wish", "Stevie Wonder", ["soul", "funk"], "Ebm", "4/4", [
        ("A", "Eb-7 | Ab7 | Eb-7 | Ab7"),
    ]),
    S("higher-ground", "Higher Ground", "Stevie Wonder", ["soul", "funk"], "Ebm", "4/4", [
        ("A", "Eb-7 | Eb-7 | Eb-7 | Eb-7"),
    ]),
    S("sir-duke", "Sir Duke", "Stevie Wonder", ["soul", "funk"], "B", "4/4", [
        ("A", "B^7 | B^7 | G#-7 | G#-7 | E7 | F#7 | B | B"),
    ]),
    S("you-are-the-sunshine", "You Are the Sunshine of My Life", "Stevie Wonder", ["soul"], "B", "4/4", [
        ("A", "B^7 | E^7 | B^7 | E^7"),
    ]),
    S("isnt-she-lovely", "Isn't She Lovely", "Stevie Wonder", ["soul"], "E", "4/4", [
        ("A", "E^7 | A9 | E^7 | A9"),
    ]),
    S("master-blaster", "Master Blaster (Jammin')", "Stevie Wonder", ["soul", "reggae"], "C#m", "4/4", [
        ("A", "C#-7 | F#-7 | C#-7 | G#7"),
    ]),
    S("dont-you-worry", "Don't You Worry 'bout a Thing", "Stevie Wonder", ["soul", "latin"], "Cm", "4/4", [
        ("A", "C-9 | F9 | Bb^7 | Eb^7 | Ab^7 | D7 | G7 | C-9"),
    ]),
    S("living-for-the-city", "Living for the City", "Stevie Wonder", ["soul", "funk"], "F", "4/4", [
        ("A", "F | Bb | F | Bb"),
    ]),
    S("as-stevie", "As", "Stevie Wonder", ["soul"], "F", "4/4", [
        ("A", "F^7 | A-7 | Bb^7 | C7"),
    ]),

    # ─────────────── SOUL / MOTOWN / R&B ───────────────
    S("aint-no-sunshine", "Ain't No Sunshine", "Bill Withers", ["soul"], "Am", "4/4", [
        ("A", "A-7 | E-7 G7 | A-7 | A-7"),
    ]),
    S("lean-on-me", "Lean on Me", "Bill Withers", ["soul"], "C", "4/4", [
        ("A", "C | F | C | G | C | F | C G | C"),
    ]),
    S("stand-by-me", "Stand by Me", "Ben E. King", ["soul"], "A", "4/4", [
        ("A", "A | A | F#-7 | F#-7 | D | E | A | A"),
    ]),
    S("my-girl", "My Girl", "The Temptations", ["soul", "motown"], "C", "4/4", [
        ("A", "C | F | C | F | C | F | G | G"),
    ]),
    S("grapevine", "I Heard It Through the Grapevine", "Marvin Gaye", ["soul", "motown"], "Ebm", "4/4", [
        ("A", "Eb-7 | Eb-7 | Bb-7 | Bb-7 | Ab-7 | Ab-7 | Eb-7 | Eb-7"),
    ]),
    S("whats-going-on", "What's Going On", "Marvin Gaye", ["soul"], "E", "4/4", [
        ("A", "E^7 | C#-7 | F#-7 | B7 | E^7 | C#-7 | F#-7 | B7"),
    ]),
    S("lets-stay-together", "Let's Stay Together", "Al Green", ["soul"], "Ab", "4/4", [
        ("A", "Ab^7 | Gb^7 | Ab^7 | Gb^7"),
    ]),
    S("respect", "Respect", "Otis Redding", ["soul"], "C", "4/4", [
        ("A", "C7 | F | G | C"),
    ]),
    S("dock-of-the-bay", "(Sittin' On) The Dock of the Bay", "Otis Redding", ["soul"], "G", "4/4", [
        ("A", "G | B | C | A | G | B | C | A"),
    ]),
    S("midnight-hour", "In the Midnight Hour", "Wilson Pickett", ["soul"], "E", "4/4", [
        ("A", "E | E | A | B | E | A | E | E"),
    ]),
    S("georgia", "Georgia on My Mind", "Hoagy Carmichael", ["soul", "jazz"], "F", "4/4", [
        ("A", "F^7 | A7 | D-7 | F7 | Bb^7 | Bb-7 | F/A Ab7 | G-7 C7"),
    ]),
    S("wonderful-world", "What a Wonderful World", "Bob Thiele", ["jazz", "standard"], "F", "4/4", [
        ("A", "F^7 | A-7 | Bb^7 | A-7 | G-7 | F^7 | E7 | A7"),
    ]),
    S("valerie", "Valerie", "The Zutons", ["soul", "pop"], "Eb", "4/4", [
        ("A", "Eb | Bb | C-7 | Bb | Ab | Eb Bb | Ab | Bb"),
    ]),
    S("rehab", "Rehab", "Amy Winehouse", ["soul"], "C", "4/4", [
        ("A", "C | Eb F | C | Eb F"),
    ]),
    S("aint-no-mountain", "Ain't No Mountain High Enough", "Marvin Gaye & Tammi Terrell", ["soul", "motown"], "C", "4/4", [
        ("A", "C | F | C | F | C | F | G | G"),
    ]),
    S("i-want-you-back", "I Want You Back", "The Jackson 5", ["soul", "motown", "pop"], "Ab", "4/4", [
        ("A", "Ab^7 | Db^7 | Eb7 | Ab^7"),
    ]),
    S("natural-woman", "(You Make Me Feel Like) A Natural Woman", "Aretha Franklin", ["soul"], "A", "4/4", [
        ("A", "A | C#-7 | D | E | A | C#-7 | D | E"),
    ]),
    S("killing-me-softly", "Killing Me Softly with His Song", "Roberta Flack", ["soul"], "Am", "4/4", [
        ("A", "A-7 | D7 | G^7 | C^7 | F^7 | Bh7 E7 | A-7 | A-7"),
    ]),
    S("lovely-day", "Lovely Day", "Bill Withers", ["soul"], "E", "4/4", [
        ("A", "E^7 | E^7 | A^7 | A^7"),
    ]),
    S("september", "September", "Earth, Wind & Fire", ["soul", "funk"], "A", "4/4", [
        ("A", "A | B | D E | A | B | D E"),
    ]),

    # ─────────────── POP DES ANNÉES 2000 ───────────────
    S("mr-brightside", "Mr. Brightside", "The Killers", ["pop", "rock", "2000s"], "Db", "4/4", [
        ("A", "Db | Db | Gb | Ab | Db | Db | Gb | Ab"),
    ]),
    S("hey-there-delilah", "Hey There Delilah", "Plain White T's", ["pop", "2000s"], "D", "4/4", [
        ("A", "D | F#-7 | D | F#-7 | D | F#-7 | G | A"),
    ]),
    S("boulevard", "Boulevard of Broken Dreams", "Green Day", ["rock", "2000s"], "Fm", "4/4", [
        ("A", "F-7 | Ab | Eb | Bb | F-7 | Ab | Eb | Bb"),
    ]),
    S("clocks", "Clocks", "Coldplay", ["pop", "rock", "2000s"], "Eb", "4/4", [
        ("A", "Eb | Bb-7 | F-7 | Eb | Bb-7 | F-7"),
    ]),
    S("chasing-cars", "Chasing Cars", "Snow Patrol", ["pop", "rock", "2000s"], "A", "4/4", [
        ("A", "A | E | D | A | E | D"),
    ]),
    S("use-somebody", "Use Somebody", "Kings of Leon", ["rock", "2000s"], "C", "4/4", [
        ("A", "C | C | E-7 | F | C | C | E-7 | F"),
    ]),
    S("viva-la-vida", "Viva la Vida", "Coldplay", ["pop", "2000s"], "Ab", "4/4", [
        ("A", "Db | Eb | Ab^7 | F-7 | Db | Eb | Ab^7 | F-7"),
    ]),
    S("crazy", "Crazy", "Gnarls Barkley", ["soul", "pop", "2000s"], "Cm", "4/4", [
        ("A", "C-7 | C-7 | Eb | Eb | Ab | Ab | G7 | G7"),
    ]),
    S("hey-ya", "Hey Ya!", "OutKast", ["pop", "2000s"], "G", "4/4", [
        ("A", "G | C | D | E7"),
    ]),
    S("i-gotta-feeling", "I Gotta Feeling", "The Black Eyed Peas", ["pop", "2000s"], "G", "4/4", [
        ("A", "G | G | E-7 | E-7 | C | C | C | C"),
    ]),
    S("halo", "Halo", "Beyoncé", ["pop", "2000s"], "A", "4/4", [
        ("A", "A | E | F#-7 | D"),
    ]),
    S("poker-face", "Poker Face", "Lady Gaga", ["pop", "2000s"], "G#m", "4/4", [
        ("A", "G#-7 | E | B | F#"),
    ]),
    S("umbrella", "Umbrella", "Rihanna", ["pop", "2000s"], "Bb", "4/4", [
        ("A", "G-7 | Eb | Bb | F"),
    ]),
    S("since-u-been-gone", "Since U Been Gone", "Kelly Clarkson", ["pop", "2000s"], "C#m", "4/4", [
        ("A", "C#-7 | A | E | B"),
    ]),
    S("complicated", "Complicated", "Avril Lavigne", ["pop", "2000s"], "F", "4/4", [
        ("A", "F | C | Bb | Bb"),
    ]),
    S("the-scientist", "The Scientist", "Coldplay", ["pop", "2000s"], "F", "4/4", [
        ("A", "D-7 | Bb | F | F | D-7 | Bb | F | F"),
    ]),
    S("bad-day", "Bad Day", "Daniel Powter", ["pop", "2000s"], "A", "4/4", [
        ("A", "A | E | D | A | E | D"),
    ]),
    S("dont-know-why", "Don't Know Why", "Norah Jones", ["jazz", "pop", "2000s"], "Bb", "4/4", [
        ("A", "Bb^7 | D7 | Eb^7 | D7 | G-7 | C7 | F7 | F7"),
    ]),
    S("apologize", "Apologize", "OneRepublic", ["pop", "2000s"], "Cm", "4/4", [
        ("A", "C-7 | Ab^7 | Eb | Bb"),
    ]),
    S("how-to-save-a-life", "How to Save a Life", "The Fray", ["pop", "2000s"], "Bb", "4/4", [
        ("A", "Bb | F | Eb | Eb | Bb | F | Eb | Eb"),
    ]),

    # ─────────────── POP RÉCENTE (2010s–2020s) ───────────────
    S("rolling-in-the-deep", "Rolling in the Deep", "Adele", ["pop"], "Cm", "4/4", [
        ("A", "C-7 | Bb | Ab | Ab | C-7 | Bb | Ab | Bb"),
    ]),
    S("someone-like-you", "Someone Like You", "Adele", ["pop"], "A", "4/4", [
        ("A", "A | E/G# | F#-7 | D | A | E/G# | F#-7 | D"),
    ]),
    S("happy", "Happy", "Pharrell Williams", ["pop", "soul"], "F", "4/4", [
        ("A", "F7 | F7 | Bb7 | Bb7"),
    ]),
    S("uptown-funk", "Uptown Funk", "Mark Ronson ft. Bruno Mars", ["pop", "funk"], "Dm", "4/4", [
        ("A", "D-7 | D-7 | D-7 | G7"),
    ]),
    S("get-lucky", "Get Lucky", "Daft Punk", ["pop", "funk"], "Bm", "4/4", [
        ("A", "B-7 | D^7 | F#-7 | E7"),
    ]),
    S("shape-of-you", "Shape of You", "Ed Sheeran", ["pop"], "C#m", "4/4", [
        ("A", "C#-7 | F#-7 | A | B"),
    ]),
    S("thinking-out-loud", "Thinking Out Loud", "Ed Sheeran", ["pop", "soul"], "D", "4/4", [
        ("A", "D | D/F# | G | A | D | D/F# | G | A"),
    ]),
    S("stay-with-me", "Stay with Me", "Sam Smith", ["pop", "soul"], "C", "4/4", [
        ("A", "A-7 | F | C | C"),
    ]),
    S("all-of-me-legend", "All of Me", "John Legend", ["pop", "soul"], "Ab", "4/4", [
        ("A", "F-7 | Db^7 | Ab | Eb | F-7 | Db^7 | Ab | Eb"),
    ]),
    S("blinding-lights", "Blinding Lights", "The Weeknd", ["pop"], "Fm", "4/4", [
        ("A", "F-7 | C-7 | Db^7 | Eb"),
    ]),
    S("levitating", "Levitating", "Dua Lipa", ["pop"], "Bm", "4/4", [
        ("A", "B-7 | F#-7 | E-7 | A"),
    ]),
    S("dont-start-now", "Don't Start Now", "Dua Lipa", ["pop", "funk"], "Bm", "4/4", [
        ("A", "B-7 | E-7 | B-7 | F#7"),
    ]),
    S("watermelon-sugar", "Watermelon Sugar", "Harry Styles", ["pop"], "G", "4/4", [
        ("A", "G | C | D | C"),
    ]),
    S("as-it-was", "As It Was", "Harry Styles", ["pop"], "F#m", "4/4", [
        ("A", "F#-7 | D | A | E"),
    ]),
    S("bad-guy", "Bad Guy", "Billie Eilish", ["pop"], "Gm", "4/4", [
        ("A", "G-7 | G-7 | G-7 | G-7"),
    ]),
    S("drivers-license", "drivers license", "Olivia Rodrigo", ["pop"], "Ab", "4/4", [
        ("A", "Ab | Eb | F-7 | Db"),
    ]),
    S("good-4-u", "good 4 u", "Olivia Rodrigo", ["pop", "rock"], "A", "4/4", [
        ("A", "A | A | D | E | A | A | D | E"),
    ]),
    S("flowers", "Flowers", "Miley Cyrus", ["pop"], "Am", "4/4", [
        ("A", "A-7 | D-7 | G7 | C^7"),
    ]),
    S("anti-hero", "Anti-Hero", "Taylor Swift", ["pop"], "E", "4/4", [
        ("A", "E | C#-7 | A | B"),
    ]),
    S("cruel-summer", "Cruel Summer", "Taylor Swift", ["pop"], "A", "4/4", [
        ("A", "A | E | F#-7 | D"),
    ]),
]


def bars_from(spec):
    """'C-7 F7 | Bb^7' -> [{'chords':['C-7','F7']}, {'chords':['Bb^7']}]"""
    bars = []
    for cell in spec.split("|"):
        chords = cell.split()
        if chords:
            bars.append({"chords": chords})
    return bars


def main():
    os.makedirs(CHARTS_DIR, exist_ok=True)
    os.makedirs(LYRICS_DIR, exist_ok=True)
    ids = set()
    catalog_songs = []
    lyrics_count = 0

    for song in SONGS:
        sid = song["id"]
        if sid in ids:
            raise SystemExit(f"id en double : {sid}")
        ids.add(sid)

        chart = {
            "key": song["key"],
            "time": song["time"],
            "sections": [
                {"label": label, "bars": bars_from(spec)}
                for (label, spec) in song["sections"]
            ],
        }
        chart_asset = f"assets/charts/{sid}.json"
        with open(os.path.join(ROOT, chart_asset), "w", encoding="utf-8") as f:
            json.dump(chart, f, ensure_ascii=False, indent=2)
            f.write("\n")

        representations = [
            {"id": f"{sid}-grid", "type": "chordGrid", "asset": chart_asset}
        ]

        # Paroles (ChordPro). Deux sources possibles, traitées pareil :
        #   1. champ `lyrics=` en dur dans ce fichier (démo blues) ;
        #   2. un fichier déposé à la main dans assets/lyrics/<id>.pro
        #      (récupéré d'une source dont tu as le droit d'usage).
        # Dès qu'un .pro existe pour le morceau, la représentation est ajoutée.
        lyrics_asset = f"assets/lyrics/{sid}.pro"
        lyrics_path = os.path.join(ROOT, lyrics_asset)
        if song.get("lyrics"):
            with open(lyrics_path, "w", encoding="utf-8") as f:
                f.write(song["lyrics"])
        if os.path.exists(lyrics_path):
            representations.append(
                {"id": f"{sid}-lyrics", "type": "lyrics", "asset": lyrics_asset}
            )
            lyrics_count += 1

        entry = {
            "id": sid,
            "title": song["title"],
            "tags": song["tags"],
            "representations": representations,
        }
        if song["artist"]:
            entry["artist"] = song["artist"]
        catalog_songs.append(entry)

    with open(CATALOG, "w", encoding="utf-8") as f:
        json.dump({"version": 1, "songs": catalog_songs}, f,
                  ensure_ascii=False, indent=2)
        f.write("\n")

    print(f"{len(catalog_songs)} morceaux générés "
          f"(dont {lyrics_count} avec paroles) → assets/ + catalog.json")


if __name__ == "__main__":
    main()

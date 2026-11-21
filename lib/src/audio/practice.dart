import '../domain/chord_chart.dart';
import 'chord_detector.dart';
import 'chord_matcher.dart';

/// Position d'un accord dans la grille.
typedef ChordRef = ({int section, int bar, int chord});

/// Couleur d'un accord, ce que l'oreille (et le détecteur) distingue
/// sûrement : les extensions (9, 11, 13, altérations) n'en changent pas.
enum ChordFamily { major, minor, diminished, augmented, suspended }

/// Famille d'une qualité, au vocabulaire iReal (`-7`, `h7`, `^7#11`…) comme
/// usuel (`m7`, `maj7`, `dim`…).
ChordFamily familyOf(String quality) {
  final q = quality.trim();
  final minorish = q.startsWith('-') || (q.startsWith('m') && !q.startsWith('maj'));
  if (q.startsWith('h') ||
      q.startsWith('o') ||
      q.startsWith('dim') ||
      (minorish && q.contains('b5'))) {
    return ChordFamily.diminished;
  }
  if (minorish) return ChordFamily.minor;
  if (q.startsWith('+') || q.startsWith('aug') || q.contains('#5')) {
    return ChordFamily.augmented;
  }
  if (q.contains('sus') || q == '2') return ChordFamily.suspended;
  return ChordFamily.major;
}

/// Ce qu'on accepte d'entendre pour un accord de la grille.
class ChordExpectation {
  final int root;
  final Set<ChordFamily> families;

  const ChordExpectation(this.root, this.families);

  /// Null pour un accord sans fondamentale lisible (N.C., symbole inconnu).
  static ChordExpectation? of(Chord chord) {
    final root = chord.root;
    if (chord.isNoChord || root == null) return null;
    final q = chord.quality.trim();
    final family = familyOf(q);
    return ChordExpectation(root.value, {
      family,
      // Accord de puissance (C5) : ni majeur ni mineur, et le 3e harmonique
      // de la quinte (un Ré pour C5) le fait souvent sonner « sus2 ».
      if (q == '5')
        ...[ChordFamily.major, ChordFamily.minor, ChordFamily.suspended],
      // Un accord augmenté s'entend souvent comme majeur (la quinte bouge).
      if (family == ChordFamily.augmented) ChordFamily.major,
      // C11 se joue souvent sans tierce.
      if (q.startsWith('11')) ChordFamily.suspended,
    });
  }

  bool accepts(ChordCandidate c) =>
      c.root == root && families.contains(familyOf(c.quality));

  /// Deux étapes que l'oreille ne distingue pas (C puis C7, C puis C/E).
  bool sameAs(ChordExpectation other) =>
      root == other.root &&
      families.length == other.families.length &&
      families.containsAll(other.families);
}

/// Un accord à jouer. Les accords identiques qui se suivent (C | C | C)
/// forment une seule étape : on s'entraîne aux enchaînements, pas au tempo.
class PracticeStep {
  final Chord chord;
  final ChordExpectation expectation;
  final List<ChordRef> refs;

  const PracticeStep(this.chord, this.expectation, this.refs);
}

/// Étapes d'entraînement d'une grille, dans l'ordre de lecture. Les N.C. et
/// symboles illisibles sont sautés.
List<PracticeStep> practiceSteps(ChordChart chart) {
  final steps = <PracticeStep>[];
  for (var s = 0; s < chart.sections.length; s++) {
    final bars = chart.sections[s].bars;
    for (var b = 0; b < bars.length; b++) {
      final chords = bars[b].chords;
      for (var c = 0; c < chords.length; c++) {
        final chord = chords[c];
        final ref = (section: s, bar: b, chord: c);
        if (steps.isNotEmpty && steps.last.chord.raw == chord.raw) {
          steps.last.refs.add(ref);
          continue;
        }
        final expectation = ChordExpectation.of(chord);
        if (expectation == null) continue;
        steps.add(PracticeStep(chord, expectation, [ref]));
      }
    }
  }
  return steps;
}

/// Suit la progression dans la grille : l'accord attendu est validé quand on
/// l'entend nettement plusieurs trames d'affilée, puis on passe au suivant.
class PracticeSession {
  PracticeSession(
    this.steps, {
    this.confirmFrames = 5,
    this.tolerance = 0.05,
    this.minScore = 0.55,
    this.attackDb = 6,
  });

  final List<PracticeStep> steps;

  /// Trames d'affilée (~45 ms chacune) où l'accord doit être entendu.
  final int confirmFrames;

  /// On sait quel accord est attendu : il suffit qu'il soit presque aussi
  /// probable que le meilleur candidat (C6 et Am7 ont les mêmes notes).
  final double tolerance;
  final double minScore;

  /// Remontée de niveau (dB) qui signale une nouvelle attaque.
  final double attackDb;

  int _index = 0;
  int _streak = 0;
  bool _hearing = false;
  bool _needsAttack = false;
  double _quietestDb = 0;

  int get index => _index;
  bool get finished => _index >= steps.length;
  PracticeStep? get current => finished ? null : steps[_index];
  PracticeStep? get next => _index + 1 < steps.length ? steps[_index + 1] : null;

  /// L'accord attendu est entendu sur la dernière trame.
  bool get hearing => _hearing;

  /// Avancement de la validation de l'accord courant (0..1).
  double get confirmation => _streak / confirmFrames;

  /// Traite une trame d'analyse ; vrai si elle valide l'accord courant.
  bool onFrame(ListeningFrame frame) {
    final step = current;
    if (step == null) return false;
    if (_needsAttack) {
      if (frame.levelDb < _quietestDb) _quietestDb = frame.levelDb;
      if (frame.hasSignal && frame.levelDb >= _quietestDb + attackDb) {
        _needsAttack = false;
      }
    }
    _hearing = !_needsAttack &&
        frame.hasSignal &&
        _matches(frame.candidates, step.expectation);
    _streak = _hearing ? _streak + 1 : 0;
    if (_streak < confirmFrames) return false;
    _goTo(_index + 1, after: step, levelDb: frame.levelDb);
    return true;
  }

  bool _matches(List<ChordCandidate> ranked, ChordExpectation e) {
    if (ranked.isEmpty || ranked.first.score < minScore) return false;
    for (final c in ranked) {
      if (c.score < ranked.first.score - tolerance) return false;
      if (e.accepts(c)) return c.score >= minScore;
    }
    return false;
  }

  /// Aller à l'étape [i] (retour arrière, saut, clic sur la grille).
  void jumpTo(int i) => _goTo(i.clamp(0, steps.length));

  void restart() => jumpTo(0);

  void _goTo(int i, {PracticeStep? after, double levelDb = 0}) {
    _index = i;
    _streak = 0;
    _hearing = false;
    // Si l'accord suivant sonne pareil, l'accord qui résonne encore ne doit
    // pas le valider : on attend un nouveau coup de médiator.
    final cur = current;
    _needsAttack =
        after != null && cur != null && after.expectation.sameAs(cur.expectation);
    _quietestDb = levelDb;
  }

  /// Index de l'étape qui contient cet accord de la grille.
  int? stepOf(ChordRef ref) {
    for (var i = 0; i < steps.length; i++) {
      if (steps[i].refs.contains(ref)) return i;
    }
    return null;
  }
}

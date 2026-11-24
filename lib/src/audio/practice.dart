import '../domain/chord_chart.dart';
import 'chord_detector.dart';
import 'chord_matcher.dart';

/// Position d'un accord dans la grille.
typedef ChordRef = ({int section, int bar, int chord});

/// Notes d'un accord, en demi-tons au-dessus de la fondamentale.
typedef ChordTones = ({Set<int> required, Set<int> forbidden});

/// Lit une qualité d'accord, au vocabulaire iReal (`-7`, `h7`, `^7#11`,
/// `7b9sus`…) comme usuel (`m7`, `maj7`, `dim`…), et dit quelles notes il faut
/// entendre (`required`) et lesquelles en feraient un autre accord
/// (`forbidden`) : l'autre tierce, une septième ou une sixte non notées.
///
/// Les extensions notées (9, 11, 13, altérations) sont permises sans être
/// exigées, comme la quinte juste, souvent omise. La quinte n'est jamais
/// interdite : le 3e harmonique de la fondamentale la fait toujours sonner.
ChordTones chordTones(String quality) {
  var q = quality.trim().replaceAll(RegExp(r'[(),\s]'), '');
  if (q.startsWith('maj')) {
    q = '^${q.substring(3)}';
  } else if (q.startsWith('min')) {
    q = '-${q.substring(3)}';
  } else if (q.startsWith('m') && !q.startsWith('maj')) {
    q = '-${q.substring(1)}';
  } else if (q.startsWith('dim')) {
    q = 'o${q.substring(3)}';
  } else if (q.startsWith('aug')) {
    q = '+${q.substring(3)}';
  }
  q = q.replaceAll('Δ', '^').replaceAll('ø', 'h').replaceAll('°', 'o');

  int? third = 4; // null : accord de puissance, sans tierce
  var thirdOptional = false;
  var fifth = 7;
  int? seventh; // 9 (7e diminuée), 10, 11
  var sixth = false;
  final extensions = <int>{};

  if (q.startsWith('-')) {
    third = 3;
    q = q.substring(1);
  } else if (q.startsWith('h')) {
    third = 3;
    fifth = 6;
    seventh = 10;
    q = q.substring(1).replaceFirst(RegExp(r'^7'), '');
  } else if (q.startsWith('o')) {
    third = 3;
    fifth = 6;
    q = q.substring(1);
    if (q.startsWith('7')) {
      seventh = 9;
      q = q.substring(1);
    }
  } else if (q.startsWith('+')) {
    fifth = 8;
    q = q.substring(1);
  }
  if (q.startsWith('^')) {
    seventh = 11;
    q = q.substring(1);
  }
  final number = RegExp(r'^(69|13|11|9|7|6|5|2)').firstMatch(q)?.group(1);
  if (number != null) {
    q = q.substring(number.length);
    switch (number) {
      case '7':
        seventh ??= 10;
      case '9':
        seventh ??= 10;
        extensions.add(2);
      case '11':
        seventh ??= 10;
        extensions.addAll([2, 5]);
        // C11 se joue le plus souvent sans tierce majeure.
        if (third == 4) thirdOptional = true;
      case '13':
        seventh ??= 10;
        extensions.addAll([2, 9]);
      case '6':
        sixth = true;
      case '69':
        sixth = true;
        extensions.add(2);
      case '5':
        third = null;
      case '2':
        third = 2;
    }
  }
  if (q.contains('sus2')) {
    third = 2;
  } else if (q.contains('sus')) {
    third = 5;
  }
  if (q.contains('add9') || q.contains('add2')) extensions.add(2);
  if (q.contains('b5')) fifth = 6;
  if (q.contains('#5')) fifth = 8;
  if (q.contains('b9')) extensions.add(1);
  if (q.contains('#9')) extensions.add(3);
  if (q.contains('#11')) extensions.add(6);
  if (q.contains('b13') || q.contains('b6')) extensions.add(8);
  if (q.contains('alt')) extensions.addAll([1, 3, 6, 8]);

  final required = <int>{
    0,
    if (third != null && !thirdOptional) third,
    if (third == null) 7,
    ?seventh,
    if (sixth) 9,
    if (fifth != 7) fifth,
  };
  final forbidden = <int>{
    if (third == 4) 3,
    if (third == 3) 4,
    if (third == null || third == 2 || third == 5) ...[3, 4],
    if (thirdOptional) 3,
    if (seventh == null && !sixth) ...[9, 10, 11],
    if (seventh == 10) 11,
    if (seventh == 11) 10,
    if ((seventh == 9 || sixth) && seventh != 10) ...[10, 11],
    if (seventh == 10 && !sixth) 9,
    if (seventh == 11 && !sixth) 9,
  }..removeAll({...required, ...extensions});
  return (required: required, forbidden: forbidden);
}

/// Ce qu'il faut entendre pour valider un accord de la grille, à la note
/// près : ses notes exigées présentes, aucune note qui en ferait un autre
/// accord (cf. [chordTones]). La basse d'un accord slash n'est pas exigée.
class ChordExpectation {
  final int root;

  /// Classes de hauteur absolues (bit i = classe i).
  final int required;
  final int forbidden;

  const ChordExpectation(this.root, this.required, this.forbidden);

  /// Null pour un accord sans fondamentale lisible (N.C., symbole inconnu).
  static ChordExpectation? of(Chord chord) {
    final root = chord.root;
    if (chord.isNoChord || root == null) return null;
    final tones = chordTones(chord.quality);
    int mask(Set<int> intervals) => intervals.fold(
        0, (m, i) => m | 1 << (root.value + i) % 12);
    return ChordExpectation(
      root.value,
      mask(tones.required),
      mask(tones.forbidden),
    );
  }

  /// Une note interdite ne compte que si elle sonne nettement (chroma) : un
  /// résidu d'harmonique ou une corde voisine effleurée ne disqualifie pas.
  static const forbiddenLevel = 0.25;

  bool heardIn(ListeningFrame frame) {
    if ((frame.pitchClasses & required) != required) return false;
    for (var pc = 0; pc < 12; pc++) {
      if (forbidden & (1 << pc) != 0 && frame.chroma[pc] >= forbiddenLevel) {
        return false;
      }
    }
    return true;
  }

  /// Deux étapes identiques à l'oreille (C puis C/E).
  bool sameAs(ChordExpectation other) =>
      root == other.root &&
      required == other.required &&
      forbidden == other.forbidden;
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
    this.minScore = 0.55,
    this.attackDb = 6,
  });

  final List<PracticeStep> steps;

  /// Trames d'affilée (~30 ms chacune) où l'accord doit être entendu.
  final int confirmFrames;
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
        _isChord(frame.candidates) &&
        step.expectation.heardIn(frame);
    _streak = _hearing ? _streak + 1 : 0;
    if (_streak < confirmFrames) return false;
    _goTo(_index + 1, after: step, levelDb: frame.levelDb);
    return true;
  }

  /// Assez de notes, et un contenu tonal (pas du bruit).
  bool _isChord(List<ChordCandidate> ranked) =>
      ranked.isNotEmpty && ranked.first.score >= minScore;

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

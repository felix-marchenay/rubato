import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Direction artistique « Encre & Papier » de Rubato : un carnet d'accords
/// gravé. Papier chaud, encre profonde, un unique accent laiton/ocre. Serif de
/// caractère (Fraunces) pour l'éditorial, sans net (Manrope) pour l'interface.
class RubatoPalette {
  const RubatoPalette({
    required this.paper,
    required this.surface,
    required this.ink,
    required this.inkMuted,
    required this.brass,
    required this.onBrass,
    required this.line,
    required this.brassTint,
    required this.onBrassTint,
  });

  /// Fond « papier ».
  final Color paper;

  /// Surface légèrement contrastée (cases, champs).
  final Color surface;

  /// Encre principale (texte).
  final Color ink;

  /// Encre atténuée (secondaire).
  final Color inkMuted;

  /// Accent laiton/ocre.
  final Color brass;

  /// Texte posé sur l'accent laiton.
  final Color onBrass;

  /// Filets et bordures fines.
  final Color line;

  /// Fond teinté laiton (pastilles, chips).
  final Color brassTint;

  /// Texte sur fond teinté laiton.
  final Color onBrassTint;

  static const light = RubatoPalette(
    paper: Color(0xFFF4EEE2),
    surface: Color(0xFFFCFAF3),
    ink: Color(0xFF201D18),
    inkMuted: Color(0xFF77705F),
    brass: Color(0xFFAE7C36),
    onBrass: Color(0xFFFCFAF3),
    line: Color(0xFFDCD3C1),
    brassTint: Color(0xFFEDE3CF),
    onBrassTint: Color(0xFF6E4E1E),
  );

  static const dark = RubatoPalette(
    paper: Color(0xFF14110C),
    surface: Color(0xFF1D1913),
    ink: Color(0xFFECE5D5),
    inkMuted: Color(0xFF9E937E),
    brass: Color(0xFFC9A25B),
    onBrass: Color(0xFF14110C),
    line: Color(0xFF332D22),
    brassTint: Color(0xFF2A2416),
    onBrassTint: Color(0xFFD8B675),
  );
}

/// Accès à la palette active depuis n'importe quel widget : `context.palette`.
extension RubatoPaletteX on BuildContext {
  RubatoPalette get palette =>
      Theme.of(this).brightness == Brightness.dark
          ? RubatoPalette.dark
          : RubatoPalette.light;
}

/// Fabrique des styles serif « gravés » (Fraunces).
class RubatoType {
  static TextStyle serif({
    double size = 20,
    FontWeight weight = FontWeight.w600,
    Color? color,
    double? letterSpacing,
    FontStyle? style,
    double? height,
  }) =>
      GoogleFonts.fraunces(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        fontStyle: style,
        height: height,
      );

  /// Petite capitale espacée pour légendes/étiquettes (Manrope).
  static TextStyle caption(Color color) => GoogleFonts.manrope(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
        color: color,
      );
}

class RubatoTheme {
  static ThemeData light() => _build(Brightness.light, RubatoPalette.light);
  static ThemeData dark() => _build(Brightness.dark, RubatoPalette.dark);

  static ThemeData _build(Brightness brightness, RubatoPalette p) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: p.brass,
      onPrimary: p.onBrass,
      secondary: p.brass,
      onSecondary: p.onBrass,
      secondaryContainer: p.brassTint,
      onSecondaryContainer: p.onBrassTint,
      error: const Color(0xFFB3261E),
      onError: Colors.white,
      surface: p.surface,
      onSurface: p.ink,
      surfaceContainerHighest: p.paper,
      outline: p.line,
      outlineVariant: p.line,
    );

    final baseText = ThemeData(brightness: brightness).textTheme;
    final text = GoogleFonts.manropeTextTheme(baseText)
        .apply(bodyColor: p.ink, displayColor: p.ink);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.paper,
      canvasColor: p.paper,
      textTheme: text,
      dividerColor: p.line,
      dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: p.inkMuted),
      appBarTheme: AppBarTheme(
        backgroundColor: p.paper,
        surfaceTintColor: Colors.transparent,
        foregroundColor: p.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.brass),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        hintStyle: TextStyle(color: p.inkMuted),
        prefixIconColor: p.inkMuted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.brass, width: 1.5),
        ),
      ),
    );
  }
}

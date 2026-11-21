import 'package:flutter/material.dart';

import '../theme.dart';

/// Sélecteur à segments façon pilule (DA « Encre & Papier ») : l'option active
/// est posée sur le laiton.
class PillToggle<T> extends StatelessWidget {
  final T value;

  /// Options dans l'ordre d'affichage, avec leur libellé.
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  const PillToggle({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: p.line),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in options.entries) _segment(context, e.key, e.value),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, T option, String label) {
    final p = context.palette;
    final active = option == value;
    return GestureDetector(
      onTap: active ? null : () => onChanged(option),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? p.brass : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: active ? p.onBrass : p.inkMuted,
          ),
        ),
      ),
    );
  }
}

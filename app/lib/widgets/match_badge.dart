import 'package:flutter/material.dart';

import '../theme.dart';

/// Percentual de match do currículo + cover letter com a vaga.
/// Verde a partir de 75%, âmbar de 50 a 74%, cinza abaixo; "…" enquanto não foi calculado.
class MatchBadge extends StatelessWidget {
  const MatchBadge(this.percent, {super.key, this.large = false});
  final int? percent;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final p = percent;
    final (fg, bg) = switch (p) {
      null => (AppColors.quiet, const Color(0xFFF0F1EC)),
      >= 75 => (const Color(0xFF14532D), const Color(0xFFDCFCE7)),
      >= 50 => (const Color(0xFF854D0E), const Color(0xFFFEF3C7)),
      _ => (AppColors.quiet, const Color(0xFFF0F1EC)),
    };
    return Semantics(
      label: p == null ? 'Match ainda sendo calculado' : 'Match de $p por cento com seu currículo',
      child: ExcludeSemantics(
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: large ? 14 : 10, vertical: large ? 8 : 6),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(p == null ? '…' : '$p%',
                style: TextStyle(fontSize: large ? 26 : 18, fontWeight: FontWeight.w800, color: fg, height: 1.1)),
            Text('match', style: TextStyle(fontSize: large ? 12 : 10, fontWeight: FontWeight.w600, color: fg)),
          ]),
        ),
      ),
    );
  }
}

/// "hoje", "ontem", "há 5 dias", "há 3 semanas"…
String relativeDate(DateTime? d) {
  if (d == null) return 'data não informada';
  final days = DateTime.now().difference(d.toLocal()).inDays;
  if (days <= 0) return 'hoje';
  if (days == 1) return 'ontem';
  if (days < 14) return 'há $days dias';
  if (days < 60) return 'há ${days ~/ 7} semanas';
  return 'há ${days ~/ 30} meses';
}

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../theme.dart';

class EligibilityBadge extends StatelessWidget {
  const EligibilityBadge(this.eligibility, {super.key, this.sponsorRegistered = false});
  final Eligibility eligibility;
  final bool sponsorRegistered;

  Widget _pill(String text, Color fg, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
      );

  @override
  Widget build(BuildContext context) {
    final pills = <Widget>[
      switch (eligibility) {
        Eligibility.remoteBr => _pill('Remoto do Brasil', const Color(0xFF1E3A8A), AppColors.remoteTint),
        Eligibility.visaSponsor => _pill('Patrocina visto', AppColors.visa, AppColors.visaTint),
        Eligibility.uncertain => _pill('Vale perguntar ao recrutador', AppColors.quiet, const Color(0xFFF0F1EC)),
        Eligibility.notEligible => _pill('Não elegível', AppColors.quiet, const Color(0xFFF0F1EC)),
      },
      if (sponsorRegistered) _pill('Empresa em registro oficial', AppColors.quiet, const Color(0xFFF0F1EC)),
    ];
    return Wrap(spacing: 6, runSpacing: 6, children: pills);
  }
}

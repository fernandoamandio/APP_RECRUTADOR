import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme.dart';

/// Nome do produto. Segue o padrão da família Coders4You (C4Y Interview, C4Y Jobs).
const productName = 'C4Y Jobs';

/// Ícone "4_" da Coders4You.
class BrandIcon extends StatelessWidget {
  const BrandIcon({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Image.asset('assets/brand/c4y_icon.png', width: size, height: size, filterQuality: FilterQuality.medium),
      );
}

/// "C4Y Jobs" com o 4 em laranja, na fonte da marca (JetBrains Mono).
class BrandName extends StatelessWidget {
  const BrandName({super.key, this.fontSize = 18, this.color = AppColors.ink});
  final double fontSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.jetBrainsMono(fontSize: fontSize, fontWeight: FontWeight.w800, color: color);
    return Semantics(
      label: productName,
      child: ExcludeSemantics(
        child: Text.rich(TextSpan(style: style, children: const [
          TextSpan(text: 'C'),
          TextSpan(text: '4', style: TextStyle(color: AppColors.brandOrange)),
          TextSpan(text: 'Y Jobs'),
        ])),
      ),
    );
  }
}

/// "by coders4you_" no estilo do logo.
class BrandSignature extends StatelessWidget {
  const BrandSignature({super.key, this.fontSize = 11, this.color = AppColors.quiet});
  final double fontSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.jetBrainsMono(fontSize: fontSize, fontWeight: FontWeight.w700, color: color);
    return Semantics(
      label: 'by Coders4You',
      child: ExcludeSemantics(
        child: Text.rich(TextSpan(style: style, children: const [
          TextSpan(text: 'by coders'),
          TextSpan(text: '4', style: TextStyle(color: AppColors.brandOrange)),
          TextSpan(text: 'you'),
          TextSpan(text: '_', style: TextStyle(color: AppColors.brandOrange)),
        ])),
      ),
    );
  }
}

/// Ícone + nome + assinatura, lado a lado. Usado no login e no topo do feed.
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key, this.iconSize = 40, this.nameSize = 18});
  final double iconSize;
  final double nameSize;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        BrandIcon(size: iconSize),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          BrandName(fontSize: nameSize),
          BrandSignature(fontSize: nameSize * 0.58),
        ]),
      ]);
}

/// Rodapé institucional da Coders4You.
class BrandFooter extends StatelessWidget {
  const BrandFooter({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(children: [
          const BrandIcon(size: 28),
          const SizedBox(height: 6),
          const BrandSignature(fontSize: 12),
          const SizedBox(height: 2),
          Text('suporte · software · consultoria',
              style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.quiet)),
        ]),
      );
}

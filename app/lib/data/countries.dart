// Nomes em português e bandeiras dos países que aparecem nas vagas.

const _names = {
  'AR': 'Argentina', 'AT': 'Áustria', 'AU': 'Austrália', 'BE': 'Bélgica', 'BO': 'Bolívia', 'BR': 'Brasil',
  'CA': 'Canadá', 'CH': 'Suíça', 'CL': 'Chile', 'CO': 'Colômbia', 'CR': 'Costa Rica', 'DE': 'Alemanha',
  'DK': 'Dinamarca', 'EC': 'Equador', 'ES': 'Espanha', 'FI': 'Finlândia', 'FR': 'França', 'GB': 'Reino Unido',
  'IE': 'Irlanda', 'IN': 'Índia', 'IT': 'Itália', 'MX': 'México', 'NL': 'Holanda', 'NO': 'Noruega',
  'NZ': 'Nova Zelândia', 'PE': 'Peru', 'PL': 'Polônia', 'PT': 'Portugal', 'PY': 'Paraguai', 'SE': 'Suécia',
  'SG': 'Singapura', 'US': 'Estados Unidos', 'UY': 'Uruguai', 'VE': 'Venezuela', 'ZA': 'África do Sul',
};

String countryName(String code) => _names[code.toUpperCase()] ?? code.toUpperCase();

/// Bandeira a partir do código ISO de 2 letras (pares de "regional indicator symbols" do Unicode).
String countryFlag(String code) {
  final c = code.toUpperCase();
  if (c.length != 2 || !RegExp(r'^[A-Z]{2}$').hasMatch(c)) return '🏳️';
  return String.fromCharCodes(c.codeUnits.map((u) => 0x1F1E6 + u - 0x41));
}

/// Chave para ordenar nomes em ordem alfabética ignorando acentos ("Áustria" junto do "A").
String sortKey(String s) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
  const to = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString().toLowerCase();
}

import 'package:intl/intl.dart';

import '../data/models.dart';

String money(double value, String currency) {
  final f = NumberFormat.compactSimpleCurrency(locale: 'pt_BR', name: currency);
  return f.format(value);
}

String moneyRange(SalarySuggestion s) {
  return '${money(s.min, s.currency)}–${money(s.max, s.currency)}/ano';
}

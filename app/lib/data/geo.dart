import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

/// País de onde o celular está acessando, pelo IP (código ISO, ex.: "BR").
///
/// Consulta o serviço público country.is, que devolve só o país do IP da requisição.
/// Sem internet ou se o serviço falhar, usa o país das configurações de idioma do aparelho.
Future<String?> detectCountry() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final req = await client.getUrl(Uri.parse('https://api.country.is/'));
    final res = await req.close().timeout(const Duration(seconds: 5));
    if (res.statusCode == 200) {
      final body = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
      final country = body['country'] as String?;
      if (country != null && country.length == 2) return country.toUpperCase();
    }
  } catch (_) {
    // segue para o país do aparelho
  } finally {
    client.close(force: true);
  }
  return PlatformDispatcher.instance.locale.countryCode?.toUpperCase();
}

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Provedores de IA que o usuário pode escolher. A chave é dele e fica no Vault do Supabase.
enum AiProvider {
  anthropic('anthropic', 'Claude (Anthropic)', 'console.anthropic.com → API Keys', 'sk-ant-'),
  openai('openai', 'ChatGPT (OpenAI)', 'platform.openai.com → API keys', 'sk-');

  const AiProvider(this.id, this.label, this.whereToGetKey, this.keyPrefix);
  final String id;
  final String label;
  final String whereToGetKey;
  final String keyPrefix;

  static AiProvider? fromId(String? id) => switch (id) {
        'anthropic' => AiProvider.anthropic,
        'openai' => AiProvider.openai,
        _ => null,
      };
}

class AiModel {
  const AiModel(this.id, this.name);
  final String id;
  final String name;
}

class AiKeyException implements Exception {
  AiKeyException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Valida a chave direto no provedor e devolve os modelos que ela pode usar.
Future<List<AiModel>> listModels(AiProvider provider, String apiKey) async {
  final http.Response resp;
  try {
    resp = switch (provider) {
      AiProvider.anthropic => await http.get(Uri.parse('https://api.anthropic.com/v1/models?limit=100'),
          headers: {'x-api-key': apiKey, 'anthropic-version': '2023-06-01'}),
      AiProvider.openai => await http.get(Uri.parse('https://api.openai.com/v1/models'),
          headers: {'Authorization': 'Bearer $apiKey'}),
    }.timeout(const Duration(seconds: 20));
  } catch (_) {
    throw AiKeyException('Não consegui falar com ${provider.label}. Confira a internet e tente de novo.');
  }
  if (resp.statusCode == 401 || resp.statusCode == 403) {
    throw AiKeyException('Chave recusada por ${provider.label}. Confira se copiou a chave inteira.');
  }
  if (resp.statusCode >= 400) {
    throw AiKeyException('${provider.label} respondeu com erro ${resp.statusCode}. Tente de novo em instantes.');
  }
  final data = (jsonDecode(resp.body) as Map<String, dynamic>)['data'] as List? ?? const [];
  final models = <AiModel>[
    for (final m in data)
      if (_usable(provider, m['id'] as String))
        AiModel(m['id'] as String, (m['display_name'] as String?) ?? m['id'] as String),
  ];
  if (provider == AiProvider.openai) models.sort((a, b) => b.id.compareTo(a.id));
  if (models.isEmpty) throw AiKeyException('A chave funciona, mas não encontrei modelos de texto disponíveis nela.');
  return models;
}

/// A OpenAI lista também modelos de áudio, imagem e embeddings: ficam só os de conversa
/// que leem PDF e usam ferramentas.
bool _usable(AiProvider provider, String id) {
  if (provider == AiProvider.anthropic) return id.startsWith('claude');
  final chat = RegExp(r'^(gpt-[4-9]|gpt-\d{2}|o[1-9]|chatgpt-)').hasMatch(id);
  const skip = ['audio', 'realtime', 'tts', 'transcribe', 'image', 'search', 'embedding', 'instruct', 'codex',
      'moderation', 'preview-20', 'mini-tts'];
  return chat && !skip.any(id.contains);
}

/// Sugestão de modelo: bom equilíbrio entre custo e qualidade para triagem e match em volume.
AiModel? suggestedModel(AiProvider provider, List<AiModel> models) {
  final prefs = provider == AiProvider.anthropic ? ['haiku', 'sonnet'] : ['mini', 'gpt-'];
  for (final p in prefs) {
    for (final m in models) {
      if (m.id.contains(p)) return m;
    }
  }
  return models.isEmpty ? null : models.first;
}

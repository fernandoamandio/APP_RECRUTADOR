import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'countries.dart';
import 'geo.dart';
import 'models.dart';
import 'search_status.dart';

final supabaseProvider = Provider<SupabaseClient>((_) => Supabase.instance.client);
final repositoryProvider = Provider((ref) => Repository(ref.watch(supabaseProvider)));

/// Filtro do feed: null = todas.
final feedFilterProvider = StateProvider<Eligibility?>((_) => null);

/// País do IP do celular, detectado uma vez por sessão do app.
final countryProvider = FutureProvider<String?>((_) => detectCountry());

/// Feed agrupado por país: o país do IP primeiro e os demais em ordem alfabética.
/// Vagas "Remoto do Brasil" sem país entram no grupo do país do IP; as demais sem país
/// ficam de fora. Cada grupo traz só as de maior match.
final feedProvider = FutureProvider.autoDispose<List<CountryGroup>>((ref) async {
  final jobs = await ref.watch(repositoryProvider).feed(ref.watch(feedFilterProvider));
  final country = await ref.watch(countryProvider.future);
  return groupFeed(jobs, country);
});

const topPerCountry = 5;

class CountryGroup {
  CountryGroup({required this.code, required this.jobs, required this.isLocal});

  /// Código ISO do país; nulo = vagas remotas sem país definido.
  final String? code;
  final List<JobMatch> jobs; // todas, da maior para a menor aderência
  final bool isLocal; // é o país de onde o celular está acessando

  String get name => code == null ? 'Remoto internacional' : countryName(code!);
  String get flag => code == null ? '🌎' : countryFlag(code!);
  List<JobMatch> get top => jobs.take(topPerCountry).toList();
  int get hidden => jobs.length - top.length;
}

List<CountryGroup> groupFeed(List<JobMatch> jobs, String? ipCountry) {
  final byCode = <String?, List<JobMatch>>{};
  for (final j in jobs) {
    // Sem país definido: só entra (no grupo do seu país) se for remota aceitando o Brasil.
    // As demais sem país (localização desconhecida) ficam fora para não poluir o grupo do Brasil.
    if (j.country == null && j.eligibility != Eligibility.remoteBr) continue;
    final code = j.country?.toUpperCase() ?? ipCountry;
    byCode.putIfAbsent(code, () => []).add(j);
  }
  // Dentro do país: maior match primeiro (sem match calculado vai para o fim), empate pela mais recente
  int byMatch(JobMatch a, JobMatch b) {
    final m = (b.matchPct ?? -1).compareTo(a.matchPct ?? -1);
    return m != 0 ? m : b.dateRank.compareTo(a.dateRank);
  }

  final groups = [
    for (final e in byCode.entries)
      CountryGroup(code: e.key, jobs: e.value..sort(byMatch), isLocal: e.key != null && e.key == ipCountry),
  ];
  int rank(CountryGroup g) => g.isLocal ? 0 : (g.code == null ? 1 : 2);
  return groups
    ..sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : sortKey(a.name).compareTo(sortKey(b.name));
    });
}

final jobProvider = FutureProvider.autoDispose.family<JobMatch, String>((ref, id) {
  return ref.watch(repositoryProvider).job(id);
});

final applicationsProvider = FutureProvider.autoDispose<List<(JobMatch, DateTime?)>>((ref) {
  return ref.watch(repositoryProvider).applications();
});

final aiSettingsProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) {
  return ref.watch(repositoryProvider).aiSettings();
});

final careerProfileProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) {
  return ref.watch(repositoryProvider).careerProfile();
});

class Repository {
  Repository(this.sb);
  final SupabaseClient sb;

  String get uid => sb.auth.currentUser!.id;

  // !inner nos dois níveis para que o filtro por categoria remova a linha inteira do feed
  static const _matchSelect = '*, jobs!inner(*, job_eligibility!inner(*), job_sources(*))';

  Future<List<JobMatch>> feed(Eligibility? filter) async {
    var q = sb.from('job_matches').select(_matchSelect).eq('user_id', uid).inFilter('status', ['new', 'seen', 'saved']);
    if (filter != null) {
      final value = switch (filter) {
        Eligibility.localBr => 'local_br',
        Eligibility.remoteBr => 'remote_br',
        Eligibility.visaSponsor => 'visa_sponsor',
        Eligibility.uncertain => 'uncertain',
        Eligibility.notEligible => 'not_eligible',
      };
      q = q.eq('jobs.job_eligibility.category', value);
    }
    // As 200 de maior nota entram; a ordem de exibição (país e data) é feita em sortFeed
    final rows = await q.order('score', ascending: false).limit(200);
    return rows.map(JobMatch.fromRow).toList();
  }

  /// Provedor, modelo, final da chave e e-mail de contato (a chave em si nunca volta para o app).
  Future<Map<String, dynamic>?> aiSettings() => sb
      .from('user_ai_settings')
      .select('provider, model, key_hint, contact_email, updated_at')
      .eq('user_id', uid)
      .maybeSingle();

  /// Grava as escolhas; `apiKey` nulo mantém a chave já salva. A chave vai para o Vault.
  Future<void> saveAiSettings({required String provider, required String model, String? apiKey,
      String? contactEmail}) {
    return sb.rpc('save_ai_settings', params: {
      'p_provider': provider,
      'p_model': model,
      'p_api_key': apiKey,
      'p_contact_email': contactEmail,
    });
  }

  /// Pede uma busca de vagas (o banco recusa se a última foi há menos de 12 horas).
  Future<SearchStatus> requestSearch() async {
    final res = await sb.rpc('request_job_search');
    return SearchStatus.fromJson(Map<String, dynamic>.from(res as Map));
  }

  /// Situação da busca deste usuário: em andamento, última busca e quando a próxima é liberada.
  Future<SearchStatus> searchStatus() async {
    final res = await sb.rpc('job_search_status');
    return SearchStatus.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<JobMatch> job(String jobId) async {
    final row = await sb.from('job_matches').select(_matchSelect).eq('user_id', uid).eq('job_id', jobId).single();
    if (row['status'] == 'new') {
      await sb.from('job_matches').update({'status': 'seen'}).eq('user_id', uid).eq('job_id', jobId);
    }
    return JobMatch.fromRow(row);
  }

  /// Salvar, descartar ou aplicar: muda o status e registra o evento para o aprendizado.
  /// Desfaz a marcação de candidatura: a vaga volta para o feed.
  Future<void> unapply(String jobId) =>
      sb.from('job_matches').update({'status': 'seen'}).eq('user_id', uid).eq('job_id', jobId);

  /// Vagas marcadas como "Já me candidatei", da candidatura mais recente para a mais antiga.
  Future<List<(JobMatch, DateTime?)>> applications() async {
    final rows = await sb.from('job_matches').select(_matchSelect).eq('user_id', uid).eq('status', 'applied');
    final events = await sb
        .from('feedback_events')
        .select('job_id, created_at')
        .eq('user_id', uid)
        .eq('kind', 'applied')
        .order('created_at', ascending: false);
    final appliedAt = <String, DateTime>{};
    for (final e in events) {
      appliedAt.putIfAbsent(e['job_id'] as String, () => DateTime.parse(e['created_at'] as String));
    }
    final list = [for (final r in rows) JobMatch.fromRow(r)];
    final out = [for (final j in list) (j, appliedAt[j.jobId])];
    out.sort((a, b) => (b.$2?.millisecondsSinceEpoch ?? 0).compareTo(a.$2?.millisecondsSinceEpoch ?? 0));
    return out;
  }

  Future<void> react(String jobId, String kind, {String? reason}) async {
    final status = switch (kind) { 'saved' => 'saved', 'dismissed' => 'dismissed', 'applied' => 'applied', _ => null };
    if (status != null) {
      await sb.from('job_matches').update({'status': status}).eq('user_id', uid).eq('job_id', jobId);
    }
    await sb.from('feedback_events').insert({'user_id': uid, 'job_id': jobId, 'kind': kind, 'reason': reason});
  }

  Future<void> editSalary(String jobId, double value, String currency) {
    return sb.from('feedback_events').insert(
        {'user_id': uid, 'job_id': jobId, 'kind': 'salary_edit', 'value': value, 'currency': currency});
  }

  Future<void> saveConsent() {
    final now = DateTime.now().toUtc().toIso8601String();
    return sb.from('profiles').update({'consent_ai_at': now, 'consent_learning_at': now}).eq('user_id', uid);
  }

  /// Envia o PDF para o bucket privado e registra o documento. Retorna o id.
  /// `origin`: 'upload' (arquivo próprio) ou 'linkedin_pdf' (PDF exportado do perfil do LinkedIn).
  /// A análise é feita pelo worker em até 15 minutos.
  Future<String> uploadDocument(String kind, Uint8List bytes, {String origin = 'upload'}) async {
    final path = '$uid/$kind-${DateTime.now().millisecondsSinceEpoch}.pdf';
    await sb.storage.from('documents').uploadBinary(path, bytes,
        fileOptions: const FileOptions(contentType: 'application/pdf'));
    final row = await sb
        .from('documents')
        .insert({'user_id': uid, 'kind': kind, 'storage_path': path, 'origin': origin})
        .select('id')
        .single();
    return row['id'] as String;
  }

  /// Dados do perfil usados na tela de documentos (consentimento e link do LinkedIn).
  Future<Map<String, dynamic>?> profileInfo() =>
      sb.from('profiles').select('consent_ai_at, linkedin_url').eq('user_id', uid).maybeSingle();

  Future<void> saveLinkedinUrl(String url) =>
      sb.from('profiles').update({'linkedin_url': url}).eq('user_id', uid);

  /// Documento mais recente de cada tipo, com o status da análise.
  Future<List<Map<String, dynamic>>> latestDocuments() async {
    final rows = await sb
        .from('documents')
        .select('kind, origin, created_at, analyzed_at')
        .eq('user_id', uid)
        .order('created_at', ascending: false);
    final seen = <String>{};
    return [for (final r in rows) if (seen.add(r['kind'] as String)) r];
  }

  Future<Map<String, dynamic>?> careerProfile() =>
      sb.from('career_profile').select().eq('user_id', uid).maybeSingle();

  Future<void> confirmCareerProfile(Map<String, dynamic> changes) => sb
      .from('career_profile')
      .update({...changes, 'confirmed_at': DateTime.now().toUtc().toIso8601String()}).eq('user_id', uid);

  Future<void> saveHousehold({required String maritalStatus, required List<int> childrenAges,
      required String spouseWillWork, required bool hasPets}) {
    return sb.from('household').upsert({
      'user_id': uid,
      'marital_status': maritalStatus,
      'children_ages': childrenAges,
      'spouse_will_work': spouseWillWork,
      'has_pets': hasPets,
    });
  }
}

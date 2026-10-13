import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'geo.dart';
import 'models.dart';

final supabaseProvider = Provider<SupabaseClient>((_) => Supabase.instance.client);
final repositoryProvider = Provider((ref) => Repository(ref.watch(supabaseProvider)));

/// Filtro do feed: null = todas.
final feedFilterProvider = StateProvider<Eligibility?>((_) => null);

/// País do IP do celular, detectado uma vez por sessão do app.
final countryProvider = FutureProvider<String?>((_) => detectCountry());

/// Feed ordenado: vagas do país onde o celular está primeiro, depois as mais recentes.
final feedProvider = FutureProvider.autoDispose<List<JobMatch>>((ref) async {
  final jobs = await ref.watch(repositoryProvider).feed(ref.watch(feedFilterProvider));
  final country = await ref.watch(countryProvider.future);
  return sortFeed(jobs, country);
});

List<JobMatch> sortFeed(List<JobMatch> jobs, String? country) {
  int local(JobMatch j) => country != null && j.country?.toUpperCase() == country ? 0 : 1;
  return [...jobs]..sort((a, b) {
      final byCountry = local(a).compareTo(local(b));
      return byCountry != 0 ? byCountry : b.dateRank.compareTo(a.dateRank);
    });
}

final jobProvider = FutureProvider.autoDispose.family<JobMatch, String>((ref, id) {
  return ref.watch(repositoryProvider).job(id);
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

  Future<JobMatch> job(String jobId) async {
    final row = await sb.from('job_matches').select(_matchSelect).eq('user_id', uid).eq('job_id', jobId).single();
    if (row['status'] == 'new') {
      await sb.from('job_matches').update({'status': 'seen'}).eq('user_id', uid).eq('job_id', jobId);
    }
    return JobMatch.fromRow(row);
  }

  /// Salvar, descartar ou aplicar: muda o status e registra o evento para o aprendizado.
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
  Future<String> uploadDocument(String kind, Uint8List bytes) async {
    final path = '$uid/$kind-${DateTime.now().millisecondsSinceEpoch}.pdf';
    await sb.storage.from('documents').uploadBinary(path, bytes,
        fileOptions: const FileOptions(contentType: 'application/pdf'));
    final row = await sb.from('documents').insert({'user_id': uid, 'kind': kind, 'storage_path': path}).select('id').single();
    return row['id'] as String;
  }

  Future<void> analyzeCv(String cvId, String? coverId) async {
    final res = await sb.functions.invoke('analyze-cv', body: {'cv_document_id': cvId, 'cover_letter_document_id': coverId});
    if (res.status != 200) throw Exception('Falha na análise do currículo (${res.status})');
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

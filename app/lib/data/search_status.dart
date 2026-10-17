import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notifications.dart';
import 'repository.dart';

/// Situação da busca de vagas do usuário (botão "Buscar vagas", 1 vez a cada 12 horas).
class SearchStatus {
  const SearchStatus({
    required this.status,
    required this.searching,
    required this.hasAiKey,
    this.requestedAt,
    this.finishedAt,
    this.lastDoneAt,
    this.nextAllowedAt,
    this.error,
  });

  final String status; // never | pending | running | done | failed
  final bool searching;
  final bool hasAiKey;
  final DateTime? requestedAt;
  final DateTime? finishedAt;
  final DateTime? lastDoneAt;
  final DateTime? nextAllowedAt;
  final String? error; // no_ai_key | too_soon

  /// Pode tocar em "Buscar vagas" agora?
  bool get canSearch =>
      hasAiKey && !searching && (nextAllowedAt == null || DateTime.now().isAfter(nextAllowedAt!));

  static DateTime? _date(dynamic v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

  static SearchStatus fromJson(Map<String, dynamic> j) => SearchStatus(
        status: (j['status'] as String?) ?? 'never',
        searching: (j['searching'] as bool?) ?? false,
        hasAiKey: (j['has_ai_key'] as bool?) ?? false,
        requestedAt: _date(j['requested_at']),
        finishedAt: _date(j['finished_at']),
        lastDoneAt: _date(j['last_done_at']),
        nextAllowedAt: _date(j['next_allowed_at']),
        error: j['error'] as String?,
      );
}

/// Carrega a situação ao abrir o feed e acompanha a busca até terminar.
class SearchStatusNotifier extends StateNotifier<SearchStatus?> {
  SearchStatusNotifier(this.ref) : super(null) {
    refresh();
  }

  final Ref ref;
  Timer? _poll;

  Future<void> refresh() async {
    try {
      final s = await ref.read(repositoryProvider).searchStatus();
      if (!mounted) return;
      _apply(s);
    } catch (_) {
      // sem a migração no banco ou sem rede: o feed continua funcionando
    }
  }

  /// Toque no botão. Devolve a situação, com `error` se o banco recusou.
  Future<SearchStatus> request() async {
    final s = await ref.read(repositoryProvider).requestSearch();
    if (mounted) _apply(s);
    if (s.searching) scheduleCheckAfterSearch().catchError((_) {});
    return s;
  }

  void _apply(SearchStatus s) {
    final finished = state?.searching == true && !s.searching;
    state = s;
    if (finished) ref.invalidate(feedProvider); // vagas novas: recarrega o feed
    _poll?.cancel();
    if (s.searching) _poll = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}

final searchStatusProvider =
    StateNotifierProvider<SearchStatusNotifier, SearchStatus?>((ref) => SearchStatusNotifier(ref));

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notifications.dart';
import 'repository.dart';

/// Situação da busca de vagas pedida ao abrir o app.
class SearchStatus {
  const SearchStatus({required this.status, this.requestedAt, this.finishedAt});

  final String status; // pending | running | done | failed | unknown
  final DateTime? requestedAt;
  final DateTime? finishedAt;

  bool get searching => status == 'pending' || status == 'running';

  static SearchStatus fromJson(Map<String, dynamic> j) => SearchStatus(
        status: (j['status'] as String?) ?? 'unknown',
        requestedAt: DateTime.tryParse((j['requested_at'] ?? '') as String),
        finishedAt: DateTime.tryParse((j['finished_at'] ?? '') as String),
      );
}

/// Pede uma busca ao abrir (ou voltar para) o app e acompanha até terminar.
/// O banco ignora o pedido se já houve busca nas últimas 3 horas.
class SearchStatusNotifier extends StateNotifier<SearchStatus?> {
  SearchStatusNotifier(this.ref) : super(null);

  final Ref ref;
  Timer? _poll;
  bool _requesting = false;

  Future<void> requestOnOpen() async {
    if (_requesting) return;
    _requesting = true;
    try {
      final s = await ref.read(repositoryProvider).requestSearch();
      if (!mounted) return;
      state = s;
      _schedulePoll();
      if (s.searching) scheduleCheckAfterSearch().catchError((_) {});
    } catch (_) {
      // sem a migração no banco ou sem rede: o feed continua funcionando
    } finally {
      _requesting = false;
    }
  }

  void _schedulePoll() {
    _poll?.cancel();
    if (state?.searching != true) return;
    _poll = Timer.periodic(const Duration(seconds: 30), (_) async {
      try {
        final s = await ref.read(repositoryProvider).latestSearch();
        if (!mounted || s == null) return;
        final finished = state?.searching == true && !s.searching;
        state = s;
        if (finished) {
          _poll?.cancel();
          ref.invalidate(feedProvider); // vagas novas: recarrega o feed
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}

final searchStatusProvider =
    StateNotifierProvider<SearchStatusNotifier, SearchStatus?>((ref) => SearchStatusNotifier(ref));

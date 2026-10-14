import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/countries.dart';
import '../../data/repository.dart';
import '../../theme.dart';
import '../../widgets/app_nav.dart';
import '../../widgets/match_badge.dart';

/// Vagas marcadas como "Já me candidatei". Elas não aparecem mais no feed nem nas notificações.
class ApplicationsScreen extends ConsumerWidget {
  const ApplicationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final async = ref.watch(applicationsProvider);
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(applicationsProvider.future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            children: [
              Text('Candidaturas', style: t.headlineMedium),
              const Padding(
                padding: EdgeInsets.only(top: 4, bottom: 16),
                child: Text('Vagas em que você marcou "Já me candidatei". Elas saem do feed e das notificações.',
                    style: TextStyle(fontSize: 13, color: AppColors.quiet)),
              ),
              ...async.when(
                loading: () => [const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))],
                error: (e, _) => [Text('Não foi possível carregar: $e')],
                data: (items) => items.isEmpty
                    ? [const Text('Nenhuma candidatura registrada ainda. No detalhe de uma vaga, toque em "Já me candidatei".')]
                    : [
                        for (final (job, at) in items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Card(
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => context.push('/job/${job.jobId}'),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Expanded(
                                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Text(job.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                        Text('${job.country != null ? '${countryFlag(job.country!)} ' : ''}${job.company} · ${job.location}',
                                            style: const TextStyle(color: AppColors.quiet)),
                                        const SizedBox(height: 4),
                                        Text(at == null ? 'Candidatura registrada' : 'Candidatura em ${DateFormat('dd/MM/yyyy').format(at.toLocal())}',
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF15803D))),
                                      ]),
                                    ),
                                    const SizedBox(width: 12),
                                    MatchBadge(job.matchPct),
                                  ]),
                                ),
                              ),
                            ),
                          ),
                      ],
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const AppNav(index: 1),
    );
  }
}

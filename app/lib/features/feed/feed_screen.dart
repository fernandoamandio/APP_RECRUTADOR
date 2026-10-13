import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import '../../theme.dart';
import '../../widgets/eligibility_badge.dart';
import '../../widgets/money.dart';

class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final filter = ref.watch(feedFilterProvider);
    final feed = ref.watch(feedProvider);

    Widget chip(String label, Eligibility? value) => ChoiceChip(
          label: Text(label),
          selected: filter == value,
          onSelected: (_) => ref.read(feedFilterProvider.notifier).state = value,
        );

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(feedProvider.future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            children: [
              Text(
                feed.maybeWhen(data: (l) => '${l.length} vagas para você', orElse: () => 'Vagas para você'),
                style: t.headlineMedium,
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [
                chip('Todas', null),
                chip('Remoto do Brasil', Eligibility.remoteBr),
                chip('Visto', Eligibility.visaSponsor),
                chip('Vale perguntar', Eligibility.uncertain),
              ]),
              const SizedBox(height: 16),
              ...feed.when(
                loading: () => [const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))],
                error: (e, _) => [Text('Não foi possível carregar o feed: $e')],
                data: (jobs) => jobs.isEmpty
                    ? [const Text('Nenhuma vaga ainda. A busca roda a cada 6 horas; volte mais tarde.')]
                    : [for (final j in jobs) Padding(padding: const EdgeInsets.only(bottom: 12), child: _JobCard(j))],
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (i) => i == 1 ? context.go('/profile') : null,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.work_outline), label: 'Vagas'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Perfil'),
        ],
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard(this.job);
  final JobMatch job;

  @override
  Widget build(BuildContext context) {
    final s = job.salary;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/job/${job.jobId}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(job.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  Text('${job.company} · ${job.location}', style: const TextStyle(color: AppColors.quiet)),
                ]),
              ),
              Text('${job.score}', style: Theme.of(context).textTheme.headlineSmall),
            ]),
            const SizedBox(height: 10),
            EligibilityBadge(job.eligibility, sponsorRegistered: job.sponsorRegistered),
            const Divider(height: 20),
            Row(children: [
              Expanded(
                child: Text(s == null ? 'Sem dados para sugerir salário' : 'Sugestão: ${moneyRange(s)}',
                    style: const TextStyle(fontSize: 13)),
              ),
              if (job.sources.isNotEmpty)
                Text('via ${job.sources.first.label}', style: const TextStyle(fontSize: 13, color: AppColors.quiet)),
            ]),
          ]),
        ),
      ),
    );
  }
}

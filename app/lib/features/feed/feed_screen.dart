import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_service.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../theme.dart';
import '../../notifications.dart';
import '../../widgets/app_nav.dart';
import '../../widgets/eligibility_badge.dart';
import '../../widgets/match_badge.dart';
import '../../widgets/money.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  @override
  void initState() {
    super.initState();
    // Android 13+: pede permissão para avisar de vagas novas (o sistema só pergunta uma vez)
    WidgetsBinding.instance.addPostFrameCallback((_) => requestNotificationPermission().catchError((_) {}));
  }

  @override
  Widget build(BuildContext context) {
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
              Text('Melhores vagas por país', style: t.headlineMedium),
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('As $topPerCountry de maior match em cada país, com o seu país primeiro',
                    style: TextStyle(fontSize: 13, color: AppColors.quiet)),
              ),
              ListenableBuilder(
                listenable: passwordGate,
                builder: (_, __) {
                  final days = passwordGate.daysLeft;
                  if (days == null || days > 7) return const SizedBox.shrink();
                  return Card(
                    margin: const EdgeInsets.only(top: 12),
                    color: AppColors.visaTint,
                    child: ListTile(
                      leading: const Icon(Icons.lock_clock, color: AppColors.visa),
                      title: Text(days <= 1 ? 'Sua senha expira amanhã' : 'Sua senha expira em $days dias'),
                      subtitle: const Text('Troque agora para não ser obrigado a trocar no próximo acesso.'),
                      onTap: () => context.push('/change-password'),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 4, children: [
                chip('Todas', null),
                chip('No Brasil', Eligibility.localBr),
                chip('Remoto do Brasil', Eligibility.remoteBr),
                chip('Visto', Eligibility.visaSponsor),
                chip('Vale perguntar', Eligibility.uncertain),
              ]),
              const SizedBox(height: 8),
              ...feed.when(
                loading: () => [const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))],
                error: (e, _) => [Text('Não foi possível carregar o feed: $e')],
                data: (groups) => groups.isEmpty
                    ? [const Text('Nenhuma vaga ainda. A busca roda a cada 6 horas; volte mais tarde.')]
                    : [for (final g in groups) _CountrySection(g)],
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const AppNav(index: 0),
    );
  }
}

class _CountrySection extends StatelessWidget {
  const _CountrySection(this.group);
  final CountryGroup group;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(0, 20, 0, 10),
        child: Semantics(
          header: true,
          child: Row(children: [
            ExcludeSemantics(child: Text(group.flag, style: const TextStyle(fontSize: 24))),
            const SizedBox(width: 10),
            Expanded(
              child: Text(group.name, style: Theme.of(context).textTheme.headlineSmall),
            ),
            if (group.isLocal)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(8)),
                child: const Text('Seu país', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
          ]),
        ),
      ),
      for (final j in group.top) Padding(padding: const EdgeInsets.only(bottom: 12), child: _JobCard(j)),
      if (group.hidden > 0)
        Text('+ ${group.hidden} ${group.hidden == 1 ? 'vaga' : 'vagas'} com match menor em ${group.name}',
            style: const TextStyle(fontSize: 12, color: AppColors.quiet)),
    ]);
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
                  const SizedBox(height: 2),
                  Text(relativeDate(job.publishedAt), style: const TextStyle(fontSize: 12, color: AppColors.quiet)),
                ]),
              ),
              const SizedBox(width: 12),
              MatchBadge(job.matchPct),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_service.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../data/search_status.dart';
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
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Android 13+: pede permissão para avisar de vagas novas (o sistema só pergunta uma vez)
      requestNotificationPermission().catchError((_) {});
      // A busca de vagas roda quando o app abre (no máximo uma a cada 3 horas)
      ref.read(searchStatusProvider.notifier).requestOnOpen();
    });
    // Voltar para o app depois de um tempo também conta como abrir
    _lifecycle = AppLifecycleListener(onResume: () => ref.read(searchStatusProvider.notifier).requestOnOpen());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
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
              const _SearchBanner(),
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
                    ? [const Text('Nenhuma vaga ainda. A busca começa quando você abre o app e leva uns 10 minutos.')]
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

/// Aviso de busca em andamento, ou de quando foi a última busca.
class _SearchBanner extends ConsumerWidget {
  const _SearchBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(searchStatusProvider);
    if (s == null) return const SizedBox.shrink();
    if (s.searching) {
      return const Card(
        margin: EdgeInsets.only(top: 12),
        color: AppColors.remoteTint,
        child: ListTile(
          leading: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
          title: Text('Procurando vagas novas'),
          subtitle: Text('Leva uns 10 minutos. Pode fechar o app: você recebe uma notificação.'),
        ),
      );
    }
    final last = s.finishedAt ?? s.requestedAt;
    if (last == null) return const SizedBox.shrink();
    final text = s.status == 'failed'
        ? 'A última busca falhou; a próxima abertura do app tenta de novo.'
        : 'Última busca ${_ago(last)}. Uma nova roda ao abrir o app, a cada 3 horas no máximo.';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(text, style: const TextStyle(fontSize: 12, color: AppColors.quiet)),
    );
  }

  static String _ago(DateTime d) {
    final m = DateTime.now().difference(d.toLocal()).inMinutes;
    if (m < 1) return 'agora há pouco';
    if (m < 60) return 'há $m min';
    final h = m ~/ 60;
    return h < 24 ? 'há $h h' : 'há ${h ~/ 24} ${h ~/ 24 == 1 ? 'dia' : 'dias'}';
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

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
import '../../widgets/brand.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Android 13+: pede permissão para avisar de vagas novas (o sistema só pergunta uma vez)
      requestNotificationPermission().catchError((_) {});
      ref.read(searchStatusProvider.notifier).refresh();
    });
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
              Row(children: [
                const Expanded(child: Align(alignment: Alignment.centerLeft, child: BrandHeader(iconSize: 36, nameSize: 17))),
                IconButton(
                  tooltip: 'Sair da conta',
                  icon: const Icon(Icons.logout),
                  onPressed: () => confirmSignOut(context),
                ),
              ]),
              const SizedBox(height: 18),
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
              const _SearchPanel(),
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
                    ? [const Text('Nenhuma vaga ainda. Toque em Buscar vagas; a busca leva uns 15 minutos.')]
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

/// Botão "Buscar vagas" (1 vez a cada 12 horas) e a situação da busca.
class _SearchPanel extends ConsumerStatefulWidget {
  const _SearchPanel();

  @override
  ConsumerState<_SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends ConsumerState<_SearchPanel> {
  bool _sending = false;

  static String _when(DateTime d) {
    final now = DateTime.now();
    final hm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
    final tomorrow = now.add(const Duration(days: 1));
    if (sameDay) return 'hoje às $hm';
    if (d.year == tomorrow.year && d.month == tomorrow.month && d.day == tomorrow.day) return 'amanhã às $hm';
    final yesterday = now.subtract(const Duration(days: 1));
    if (d.year == yesterday.year && d.month == yesterday.month && d.day == yesterday.day) return 'ontem às $hm';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} às $hm';
  }

  Future<void> _search() async {
    setState(() => _sending = true);
    try {
      final s = await ref.read(searchStatusProvider.notifier).request();
      if (!mounted) return;
      final msg = switch (s.error) {
        'no_ai_key' => 'Cadastre a sua chave de IA antes de buscar.',
        'too_soon' => 'Você já buscou nas últimas 12 horas. Próxima busca ${_when(s.nextAllowedAt!)}.',
        _ => s.searching ? 'Busca iniciada. Você recebe uma notificação quando terminar.' : null,
      };
      if (msg != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível pedir a busca: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(searchStatusProvider);
    if (s == null) return const SizedBox(height: 12);

    if (!s.hasAiKey) {
      return Card(
        margin: const EdgeInsets.only(top: 12),
        color: AppColors.visaTint,
        child: ListTile(
          leading: const Icon(Icons.key, color: AppColors.visa),
          title: const Text('Cadastre a sua IA para buscar vagas'),
          subtitle: const Text('Escolha Claude ou ChatGPT, o modelo e cole a sua chave de API.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/ai-settings'),
        ),
      );
    }

    if (s.searching) {
      return const Card(
        margin: EdgeInsets.only(top: 12),
        color: AppColors.remoteTint,
        child: ListTile(
          leading: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
          title: Text('Procurando vagas novas'),
          subtitle: Text('Leva uns 15 minutos. Pode fechar o app: você recebe uma notificação.'),
        ),
      );
    }

    final String info;
    if (s.status == 'failed') {
      info = 'A última busca falhou e não conta no limite. Pode tentar de novo.';
    } else if (s.nextAllowedAt != null && !s.canSearch) {
      info = 'Última busca ${_when(s.lastDoneAt ?? s.requestedAt ?? DateTime.now())}. '
          'Próxima liberada ${_when(s.nextAllowedAt!)}.';
    } else if (s.lastDoneAt != null) {
      info = 'Última busca ${_when(s.lastDoneAt!)}. Você pode buscar 1 vez a cada 12 horas.';
    } else {
      info = 'Você pode buscar 1 vez a cada 12 horas.';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilledButton.icon(
          onPressed: s.canSearch && !_sending ? _search : null,
          icon: _sending
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5))
              : const Icon(Icons.travel_explore),
          label: const Text('Buscar vagas'),
        ),
        const SizedBox(height: 6),
        Text(info, style: const TextStyle(fontSize: 12, color: AppColors.quiet), textAlign: TextAlign.center),
      ]),
    );
  }
}

/// Pede confirmação e encerra a sessão; o roteador leva para a tela de login.
Future<void> confirmSignOut(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Sair da conta?'),
      content: const Text('Você vai precisar do e-mail e da senha para entrar de novo.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sair')),
      ],
    ),
  );
  if (ok == true) await authService.auth.signOut();
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

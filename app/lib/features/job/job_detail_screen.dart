import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import '../../theme.dart';
import '../../widgets/eligibility_badge.dart';
import '../../widgets/money.dart';

class JobDetailScreen extends ConsumerWidget {
  const JobDetailScreen({super.key, required this.jobId});
  final String jobId;

  static const _dismissReasons = {
    'salary_low': 'Salário baixo',
    'country': 'Não quero esse país',
    'stack': 'Stack não combina',
    'timezone': 'Fuso horário',
    'company': 'Não quero essa empresa',
    'misclassified': 'Classificação errada',
  };

  Future<void> _dismiss(BuildContext context, WidgetRef ref) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('Por que descartar?', style: TextStyle(fontWeight: FontWeight.w700))),
          for (final e in _dismissReasons.entries) ListTile(title: Text(e.value), onTap: () => Navigator.pop(c, e.key)),
        ]),
      ),
    );
    if (reason == null) return;
    final repo = ref.read(repositoryProvider);
    if (reason == 'misclassified') {
      await repo.react(jobId, 'misclassified');
    }
    await repo.react(jobId, 'dismissed', reason: reason);
    ref.invalidate(feedProvider);
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _editSalary(BuildContext context, WidgetRef ref, SalarySuggestion s) async {
    final ctrl = TextEditingController(text: s.target.toStringAsFixed(0));
    final value = await showDialog<double>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sua pretensão para esta vaga'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(suffixText: '${s.currency}/ano'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, double.tryParse(ctrl.text)), child: const Text('Salvar')),
        ],
      ),
    );
    if (value != null) {
      await ref.read(repositoryProvider).editSalary(jobId, value, s.currency);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Anotado. As próximas sugestões vão considerar esse valor.')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final async = ref.watch(jobProvider(jobId));
    return Scaffold(
      appBar: AppBar(),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: $e')),
        data: (job) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(job.title, style: t.headlineMedium),
            const SizedBox(height: 4),
            Text('${job.company} · ${job.location}', style: const TextStyle(color: AppColors.quiet)),
            const SizedBox(height: 12),
            Row(children: [
              EligibilityBadge(job.eligibility, sponsorRegistered: job.sponsorRegistered),
              const Spacer(),
              Text('Aderência ${job.score}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
            if (job.evidence != null && job.evidence!.isNotEmpty) ...[
              const SizedBox(height: 12),
              _EvidenceCard(job),
            ],
            if (job.reasons.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final r in job.reasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    const Icon(Icons.check, size: 18, color: AppColors.remote),
                    const SizedBox(width: 8),
                    Expanded(child: Text(r)),
                  ]),
                ),
            ],
            const SizedBox(height: 12),
            if (job.salary != null)
              _SalaryCard(job.salary!, onEdit: () => _editSalary(context, ref, job.salary!))
            else
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Ainda não temos dados confiáveis para sugerir salário neste país.'),
                ),
              ),
            const SizedBox(height: 16),
            Text(job.description, style: t.bodyMedium),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => _dismiss(context, ref), child: const Text('Descartar'))),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    await ref.read(repositoryProvider).react(jobId, 'saved');
                    ref.invalidate(feedProvider);
                  },
                  child: const Text('Salvar'),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            // Atribuição obrigatória: link direto para a vaga na fonte original
            for (final src in job.sources)
              FilledButton(
                onPressed: () async {
                  await ref.read(repositoryProvider).react(jobId, 'applied');
                  await launchUrl(Uri.parse(src.url), mode: LaunchMode.externalApplication);
                },
                child: Text('Ver vaga no ${src.label}'),
              ),
          ],
        ),
      ),
    );
  }
}

class _EvidenceCard extends StatelessWidget {
  const _EvidenceCard(this.job);
  final JobMatch job;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6F0),
        border: Border.all(color: const Color(0xFFF3D3BE)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Por que achamos isso', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.visa)),
        const SizedBox(height: 6),
        Text('“${job.evidence}”', style: const TextStyle(fontStyle: FontStyle.italic)),
        if (job.sponsorRegistered) ...[
          const SizedBox(height: 6),
          const Text('A empresa consta em registro oficial de patrocinadores. Isso indica que pode patrocinar, não garante.',
              style: TextStyle(fontSize: 12, color: AppColors.quiet)),
        ],
      ]),
    );
  }
}

class _SalaryCard extends StatelessWidget {
  const _SalaryCard(this.s, {required this.onEdit});
  final SalarySuggestion s;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final cost = s.inputs['monthly_cost'] as num?;
    final market = s.inputs['market'] as Map<String, dynamic>?;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.modality == 'remote' ? 'Pretensão sugerida · remoto' : 'Pretensão sugerida · realocação',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('${money(s.target, s.currency)} /ano', style: Theme.of(context).textTheme.headlineMedium),
          Text('Faixa: ${moneyRange(s)}', style: const TextStyle(color: AppColors.quiet)),
          if (s.warnings.contains('market_below_family_cost'))
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Atenção: o mercado local paga menos do que o custo de vida da sua família neste destino.',
                  style: TextStyle(color: AppColors.visa)),
            ),
          const Divider(height: 24),
          if (cost != null) _row('Custo de vida da família', '${money(cost.toDouble(), s.currency)}/mês'),
          if (market != null) _row('Mercado local (mediana)', money((market['p50'] as num).toDouble(), s.currency)),
          TextButton(onPressed: onEdit, child: const Text('Ajustar minha pretensão')),
        ]),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(color: AppColors.quiet))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );
}

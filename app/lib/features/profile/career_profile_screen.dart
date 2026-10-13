import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repository.dart';
import '../../theme.dart';

/// Perfil gerado pelo Claude a partir do currículo. O usuário revisa e confirma antes da busca.
class CareerProfileScreen extends ConsumerStatefulWidget {
  const CareerProfileScreen({super.key});

  @override
  ConsumerState<CareerProfileScreen> createState() => _CareerProfileScreenState();
}

class _CareerProfileScreenState extends ConsumerState<CareerProfileScreen> {
  List<String>? _titles;

  Future<void> _addTitle() async {
    final ctrl = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Novo cargo-alvo'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Adicionar')),
        ],
      ),
    );
    if (value != null && value.isNotEmpty) setState(() => _titles!.add(value));
  }

  Future<void> _confirm() async {
    await ref.read(repositoryProvider).confirmCareerProfile({'target_titles': _titles});
    if (mounted) context.go('/feed');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final async = ref.watch(careerProfileProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Seu perfil')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro ao carregar o perfil: $e')),
        data: (p) {
          if (p == null) {
            return Center(
              child: TextButton(
                onPressed: () => context.go('/onboarding/documents'),
                child: const Text('Envie seu currículo para gerar o perfil'),
              ),
            );
          }
          _titles ??= List<String>.from(p['target_titles'] ?? const []);
          final stack = List<Map<String, dynamic>>.from(p['stack'] ?? const []);
          const levelLabel = {'main': 'Principal', 'secondary': 'Secundária', 'basic': 'Básico'};
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Chip(
                label: Text('Gerado do seu currículo · revise'),
                backgroundColor: AppColors.remoteTint,
                side: BorderSide.none,
              ),
              const SizedBox(height: 8),
              Text('Seu perfil profissional', style: t.headlineMedium),
              const SizedBox(height: 16),
              _Section(title: 'Cargos-alvo', children: [
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final title in _titles!)
                    InputChip(label: Text(title), onDeleted: () => setState(() => _titles!.remove(title))),
                  ActionChip(label: const Text('+ Adicionar'), onPressed: _addTitle),
                ]),
                const Divider(height: 24),
                Row(children: [
                  const Expanded(child: Text('Senioridade')),
                  Text('${p['seniority'] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ]),
              const SizedBox(height: 12),
              _Section(title: 'Stack', children: [
                for (final s in stack)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Expanded(child: Text('${s['name']}', style: const TextStyle(fontWeight: FontWeight.w600))),
                      Text(levelLabel[s['level']] ?? '${s['level']}'),
                    ]),
                  ),
              ]),
              const SizedBox(height: 12),
              _Section(title: 'Para o mercado internacional', children: [
                for (final s in List<String>.from(p['strengths'] ?? const []))
                  ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.check, color: AppColors.remote), title: Text(s)),
                for (final g in List<String>.from(p['gaps'] ?? const []))
                  ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.info_outline, color: AppColors.visa), title: Text(g)),
              ]),
              const SizedBox(height: 24),
              FilledButton(onPressed: _titles!.isEmpty ? null : _confirm, child: const Text('Confirmar e buscar vagas')),
            ],
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title.toUpperCase(),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.quiet, letterSpacing: 0.7)),
          const SizedBox(height: 10),
          ...children,
        ]),
      ),
    );
  }
}

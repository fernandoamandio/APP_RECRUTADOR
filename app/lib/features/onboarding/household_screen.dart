import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repository.dart';

/// Etapa 2: situação pessoal. Tudo opcional; sem isso o cálculo usa "pessoa sozinha".
class HouseholdScreen extends ConsumerStatefulWidget {
  const HouseholdScreen({super.key});

  @override
  ConsumerState<HouseholdScreen> createState() => _HouseholdScreenState();
}

class _HouseholdScreenState extends ConsumerState<HouseholdScreen> {
  String _marital = 'single';
  String _spouseWork = 'unknown';
  bool _pets = false;
  final List<int> _childrenAges = [];

  Future<void> _save() async {
    await ref.read(repositoryProvider).saveHousehold(
          maritalStatus: _marital,
          childrenAges: _childrenAges,
          spouseWillWork: _spouseWork,
          hasPets: _pets,
        );
    if (mounted) context.go('/profile');
  }

  Widget _choices(String title, Map<String, String> options, String value, ValueChanged<String> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in options.entries)
            ChoiceChip(label: Text(e.value), selected: value == e.key, onSelected: (_) => onChanged(e.key)),
        ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Etapa 2 de 5'),
        actions: [TextButton(onPressed: () => context.go('/profile'), child: const Text('Pular'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Quem vai com você?', style: t.headlineMedium),
          const SizedBox(height: 8),
          Text('Usamos isso só para calcular o custo de vida no destino e sugerir um salário que cubra sua família. '
              'Tudo é opcional.', style: t.bodyLarge),
          const SizedBox(height: 24),
          _choices('Estado civil', const {'single': 'Solteiro(a)', 'married': 'Casado(a) / união estável', 'other': 'Outro'},
              _marital, (v) => setState(() => _marital = v)),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Row(children: [
                  const Expanded(child: Text('Filhos', style: TextStyle(fontWeight: FontWeight.w700))),
                  IconButton.outlined(
                    tooltip: 'Diminuir',
                    onPressed: _childrenAges.isEmpty ? null : () => setState(() => _childrenAges.removeLast()),
                    icon: const Icon(Icons.remove),
                  ),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('${_childrenAges.length}')),
                  IconButton.outlined(
                    tooltip: 'Aumentar',
                    onPressed: () => setState(() => _childrenAges.add(0)),
                    icon: const Icon(Icons.add),
                  ),
                ]),
                for (var i = 0; i < _childrenAges.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextFormField(
                      initialValue: '${_childrenAges[i]}',
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: 'Idade do ${i + 1}º filho', border: const OutlineInputBorder()),
                      onChanged: (v) => _childrenAges[i] = int.tryParse(v) ?? 0,
                    ),
                  ),
              ]),
            ),
          ),
          if (_marital == 'married') ...[
            const SizedBox(height: 20),
            _choices('Seu cônjuge pretende trabalhar no destino?',
                const {'yes': 'Sim', 'no': 'Não', 'unknown': 'Ainda não sei'}, _spouseWork,
                (v) => setState(() => _spouseWork = v)),
          ],
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Leva pets na mudança'),
            value: _pets,
            onChanged: (v) => setState(() => _pets = v),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('Continuar')),
        ],
      ),
    );
  }
}

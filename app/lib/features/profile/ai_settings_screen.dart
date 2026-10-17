import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/password_widgets.dart';
import '../../data/ai_providers.dart';
import '../../data/repository.dart';
import '../../data/search_status.dart';
import '../../theme.dart';

/// Provedor de IA (Claude ou ChatGPT), modelo, chave de API e e-mail de contato do usuário.
/// A chave é validada direto no provedor, que também informa os modelos disponíveis nela.
class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  final _key = TextEditingController();
  final _email = TextEditingController();
  AiProvider _provider = AiProvider.anthropic;
  List<AiModel> _models = const [];
  String? _model;
  String? _savedHint; // final da chave já salva
  String? _savedProvider;
  bool _loaded = false;
  bool _busy = false;
  bool _obscure = true;
  String? _keyError;

  @override
  void dispose() {
    _key.dispose();
    _email.dispose();
    super.dispose();
  }

  void _load(Map<String, dynamic>? s) {
    if (_loaded) return;
    _loaded = true;
    _email.text = (s?['contact_email'] as String?) ?? Supabase.instance.client.auth.currentUser?.email ?? '';
    if (s == null) return;
    _provider = AiProvider.fromId(s['provider'] as String?) ?? AiProvider.anthropic;
    _savedProvider = _provider.id;
    _savedHint = s['key_hint'] as String?;
    _model = s['model'] as String?;
    if (_model != null) _models = [AiModel(_model!, _model!)];
  }

  /// A chave salva só vale para o provedor em que foi cadastrada.
  bool get _usingSavedKey => _key.text.trim().isEmpty && _savedHint != null && _savedProvider == _provider.id;

  Future<void> _validate() async {
    final key = _key.text.trim();
    if (key.isEmpty) {
      setState(() => _keyError = 'Cole a chave para validar e ver os modelos');
      return;
    }
    setState(() {
      _busy = true;
      _keyError = null;
    });
    try {
      final models = await listModels(_provider, key);
      if (!mounted) return;
      setState(() {
        _models = models;
        if (!models.any((m) => m.id == _model)) _model = suggestedModel(_provider, models)?.id;
      });
    } on AiKeyException catch (e) {
      if (mounted) setState(() => _keyError = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final newKey = _key.text.trim();
    if (newKey.isNotEmpty && !_models.any((m) => m.id == _model)) {
      await _validate(); // garante que a chave nova funciona antes de gravar
      if (_keyError != null || !mounted) return;
    }
    if (_model == null || (newKey.isEmpty && !_usingSavedKey)) {
      showError(context, 'Informe a chave e escolha um modelo.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).saveAiSettings(
            provider: _provider.id,
            model: _model!,
            apiKey: newKey.isEmpty ? null : newKey,
            contactEmail: _email.text.trim(),
          );
      ref.invalidate(aiSettingsProvider);
      ref.read(searchStatusProvider.notifier).refresh();
      if (!mounted) return;
      showError(context, 'IA salva: ${_provider.label} · $_model');
      context.pop();
    } catch (e) {
      if (mounted) showError(context, 'Não foi possível salvar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(aiSettingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Inteligência artificial')),
      body: settings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Padding(padding: const EdgeInsets.all(20), child: Text('Não foi possível carregar: $e')),
        data: (s) {
          _load(s);
          return ListView(padding: const EdgeInsets.all(20), children: [
            const Text(
              'A leitura do currículo, a triagem e o match das vagas usam a sua conta de IA. '
              'O custo fica na sua conta do provedor; a chave é guardada criptografada e não aparece de novo no app.',
              style: TextStyle(color: AppColors.quiet),
            ),
            const SizedBox(height: 20),
            Text('Provedor', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<AiProvider>(
              segments: [
                for (final p in AiProvider.values) ButtonSegment(value: p, label: Text(p.label.split(' ').first)),
              ],
              selected: {_provider},
              onSelectionChanged: _busy
                  ? null
                  : (v) => setState(() {
                        _provider = v.first;
                        _keyError = null;
                        _models = _provider.id == _savedProvider && _model != null && _savedHint != null
                            ? [AiModel(_model!, _model!)]
                            : const [];
                        if (_models.isEmpty) _model = null;
                      }),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _key,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) => setState(() => _keyError = null),
              decoration: InputDecoration(
                labelText: 'Chave de API',
                hintText: _usingSavedKey || (_savedHint != null && _savedProvider == _provider.id)
                    ? 'Salva: ••••$_savedHint (deixe vazio para manter)'
                    : '${_provider.keyPrefix}…',
                helperText: 'Onde gerar: ${_provider.whereToGetKey}',
                errorText: _keyError,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Mostrar chave' : 'Ocultar chave',
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy ? null : _validate,
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Validar chave e listar modelos'),
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _models.any((m) => m.id == _model) ? _model : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Modelo',
                helperText: 'Modelos menores (Haiku, mini) são mais baratos e dão conta da triagem.',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final m in _models)
                  DropdownMenuItem(value: m.id, child: Text(m.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: _busy ? null : (v) => setState(() => _model = v),
              hint: const Text('Valide a chave para ver os modelos'),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'E-mail de contato',
                helperText: 'Enviado aos sites de vagas como contato, por boa prática no uso das APIs públicas.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Text('Salvar'),
            ),
          ]);
        },
      ),
    );
  }
}

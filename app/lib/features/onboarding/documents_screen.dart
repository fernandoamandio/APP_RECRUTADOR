import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repository.dart';

/// Etapa 1: currículo (obrigatório), cover letter (opcional) e consentimento LGPD.
class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  PlatformFile? _cv;
  PlatformFile? _cover;
  bool _consent = false;
  bool _busy = false;

  Future<PlatformFile?> _pick() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
    return r?.files.single;
  }

  Future<void> _submit() async {
    final repo = ref.read(repositoryProvider);
    setState(() => _busy = true);
    try {
      await repo.saveConsent();
      final cvId = await repo.uploadDocument('cv', _cv!.bytes!);
      final coverId = _cover == null ? null : await repo.uploadDocument('cover_letter', _cover!.bytes!);
      await repo.analyzeCv(cvId, coverId);
      if (mounted) context.go('/onboarding/household');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Etapa 1 de 5')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Seus documentos', style: t.headlineMedium),
          const SizedBox(height: 8),
          Text('O Claude lê o currículo para montar seu perfil. Você revisa tudo antes da busca.', style: t.bodyLarge),
          const SizedBox(height: 24),
          _FileTile(label: 'Currículo (PDF)', file: _cv, onTap: () async {
            final f = await _pick();
            if (f != null) setState(() => _cv = f);
          }),
          const SizedBox(height: 12),
          _FileTile(label: 'Cover letter (opcional)', file: _cover, onTap: () async {
            final f = await _pick();
            if (f != null) setState(() => _cover = f);
          }),
          const SizedBox(height: 24),
          CheckboxListTile(
            value: _consent,
            onChanged: (v) => setState(() => _consent = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text('Autorizo a análise dos meus documentos por IA e o uso das minhas respostas '
                'para personalizar vagas e salários.'),
            subtitle: const Text('Você pode exportar ou apagar seus dados a qualquer momento.'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _cv != null && _consent && !_busy ? _submit : null,
            child: _busy ? const Text('Analisando seu currículo…') : const Text('Continuar'),
          ),
        ],
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({required this.label, required this.file, required this.onTap});
  final String label;
  final PlatformFile? file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        minVerticalPadding: 16,
        leading: Icon(file == null ? Icons.upload_file : Icons.check_circle_outline),
        title: Text(label),
        subtitle: Text(file?.name ?? 'Toque para escolher'),
        onTap: onTap,
      ),
    );
  }
}

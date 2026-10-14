import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/repository.dart';
import '../../theme.dart';

final _profileInfoProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) => ref.watch(repositoryProvider).profileInfo());
final _documentsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) => ref.watch(repositoryProvider).latestDocuments());

/// Currículo em PDF, PDF do perfil do LinkedIn e cover letter.
/// Usada no onboarding e pela tela de perfil ("Atualizar currículo ou LinkedIn").
class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key, this.onboarding = false});
  final bool onboarding;

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  final _linkedin = TextEditingController();
  bool _consent = false;
  bool _busy = false;
  bool _loadedProfile = false;

  static final _linkedinRe = RegExp(r'^(https?://)?([a-z]{2,3}\.)?linkedin\.com/in/[^/\s?#]+/?', caseSensitive: false);

  @override
  void dispose() {
    _linkedin.dispose();
    super.dispose();
  }

  String? get _linkedinUrl {
    final v = _linkedin.text.trim();
    if (!_linkedinRe.hasMatch(v)) return null;
    return v.startsWith('http') ? v : 'https://$v';
  }

  Future<void> _upload({required String kind, String origin = 'upload'}) async {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['pdf']);
    if (file == null) return;
    final repo = ref.read(repositoryProvider);
    setState(() => _busy = true);
    try {
      await repo.saveConsent();
      await repo.uploadDocument(kind, await file.readAsBytes(), origin: origin);
      ref.invalidate(_documentsProvider);
      ref.invalidate(_profileInfoProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Recebido! A análise leva até 15 minutos; depois o perfil e o match são atualizados.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível enviar: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openLinkedin() async {
    final url = _linkedinUrl;
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cole o link do seu perfil, no formato linkedin.com/in/seu-nome')));
      return;
    }
    await ref.read(repositoryProvider).saveLinkedinUrl(url);
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final info = ref.watch(_profileInfoProvider).valueOrNull;
    if (info != null && !_loadedProfile) {
      _loadedProfile = true;
      _consent = info['consent_ai_at'] != null;
      _linkedin.text = (info['linkedin_url'] as String?) ?? '';
    }
    final docs = ref.watch(_documentsProvider).valueOrNull ?? const [];
    final canUpload = _consent && !_busy;

    return Scaffold(
      appBar: AppBar(title: Text(widget.onboarding ? 'Etapa 1 de 5' : 'Currículo e LinkedIn')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Seu currículo', style: t.headlineMedium),
          const SizedBox(height: 8),
          Text('Envie o currículo em PDF ou o PDF do seu perfil do LinkedIn. O Claude lê o documento, '
              'monta seu perfil e compara cada vaga com ele.', style: t.bodyLarge),
          const SizedBox(height: 16),
          CheckboxListTile(
            value: _consent,
            onChanged: (v) => setState(() => _consent = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text('Autorizo a análise dos meus documentos por IA e o uso das minhas respostas '
                'para personalizar vagas e salários.'),
            subtitle: const Text('Você pode apagar seus dados a qualquer momento.'),
          ),
          const SizedBox(height: 8),

          // 1. Currículo em PDF
          _OptionCard(
            icon: Icons.description_outlined,
            title: 'Opção 1 · Currículo em PDF',
            children: [
              const Text('O arquivo do seu currículo, como você envia para as empresas.'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: canUpload ? () => _upload(kind: 'cv') : null,
                icon: const Icon(Icons.upload_file),
                label: const Text('Escolher PDF do currículo'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2. Perfil do LinkedIn
          _OptionCard(
            icon: Icons.badge_outlined,
            title: 'Opção 2 · Perfil do LinkedIn',
            children: [
              const Text('O LinkedIn não permite que apps leiam o perfil pelo link, mas ele mesmo gera um PDF '
                  'do seu perfil em um toque:'),
              const SizedBox(height: 8),
              const _Step(n: 1, text: 'Cole o link do seu perfil e toque em "Abrir meu perfil".'),
              const _Step(n: 2, text: 'No seu perfil, toque em "Mais" (ou "Recursos") e depois em "Salvar em PDF".'),
              const _Step(n: 3, text: 'Volte aqui e envie o PDF baixado.'),
              const SizedBox(height: 12),
              TextField(
                controller: _linkedin,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Link do perfil',
                  hintText: 'linkedin.com/in/seu-nome',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openLinkedin,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Abrir meu perfil'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: canUpload ? () => _upload(kind: 'cv', origin: 'linkedin_pdf') : null,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Enviar PDF'),
                  ),
                ),
              ]),
            ],
          ),
          const SizedBox(height: 12),

          // Cover letter (opcional)
          _OptionCard(
            icon: Icons.mail_outline,
            title: 'Cover letter (opcional)',
            children: [
              const Text('Entra no cálculo do match junto com o currículo.'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: canUpload ? () => _upload(kind: 'cover_letter') : null,
                icon: const Icon(Icons.upload_file),
                label: const Text('Escolher PDF da cover letter'),
              ),
            ],
          ),

          if (!_consent)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('Marque a autorização acima para enviar documentos.',
                  style: TextStyle(color: AppColors.visa)),
            ),
          if (_busy) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
          if (docs.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Enviados', style: t.titleMedium),
            for (final d in docs) _DocStatus(d),
          ],
          if (widget.onboarding) ...[
            const SizedBox(height: 24),
            FilledButton(
              onPressed: docs.any((d) => d['kind'] == 'cv') ? () => context.go('/onboarding/household') : null,
              child: const Text('Continuar'),
            ),
          ],
        ],
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({required this.icon, required this.title, required this.children});
  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(icon, color: AppColors.remote),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
          ]),
          const SizedBox(height: 10),
          ...children,
        ]),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text});
  final int n;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(radius: 11, backgroundColor: AppColors.remoteTint,
            child: Text('$n', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.remote))),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ]),
    );
  }
}

class _DocStatus extends StatelessWidget {
  const _DocStatus(this.doc);
  final Map<String, dynamic> doc;

  @override
  Widget build(BuildContext context) {
    final kind = doc['kind'] == 'cv'
        ? (doc['origin'] == 'linkedin_pdf' ? 'Currículo (PDF do LinkedIn)' : 'Currículo')
        : 'Cover letter';
    final sent = DateTime.tryParse(doc['created_at'] as String? ?? '')?.toLocal();
    final analyzed = doc['analyzed_at'] != null;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(analyzed ? Icons.check_circle_outline : Icons.hourglass_top,
          color: analyzed ? const Color(0xFF15803D) : AppColors.quiet),
      title: Text(kind),
      subtitle: Text([
        if (sent != null) 'Enviado em ${DateFormat('dd/MM HH:mm').format(sent)}',
        analyzed ? 'analisado' : 'aguardando análise (até 15 min)',
      ].join(' · ')),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Login por link mágico no e-mail (sem senha para guardar).
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  bool _sent = false;
  bool _busy = false;

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.auth.signInWithOtp(
        email: _email.text.trim(),
        emailRedirectTo: 'io.recrutador://login-callback',
      );
      setState(() => _sent = true);
    } on AuthException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Text('Vagas do mundo,\nfiltradas para quem está no Brasil.', style: t.headlineMedium),
              const SizedBox(height: 12),
              Text('Remoto do Brasil ou com patrocínio de visto, com sugestão salarial para cada vaga.',
                  style: t.bodyLarge),
              const Spacer(),
              if (_sent)
                Text('Enviamos um link de acesso para ${_email.text}. Abra no celular para entrar.', style: t.bodyLarge)
              else ...[
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Seu e-mail', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _busy ? null : _send, child: const Text('Receber link de acesso')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

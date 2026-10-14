import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/auth_service.dart';
import '../../auth/password_policy.dart';
import '../../auth/password_widgets.dart';
import '../../theme.dart';

/// Login com e-mail e senha. Após 5 senhas erradas a conta é bloqueada
/// (desbloqueio por "Esqueci minha senha").
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  static const _lockedMessage =
      'Conta bloqueada após $maxLoginAttempts tentativas de senha incorretas. Use "Esqueci minha senha" para desbloquear.';

  Future<void> _signIn() async {
    final email = _email.text.trim().toLowerCase();
    if (!isValidEmail(email) || _password.text.isEmpty) {
      setState(() => _error = 'Informe o e-mail e a senha.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (await authService.isLocked(email)) {
        setState(() => _error = _lockedMessage);
        return;
      }
      await authService.auth.signInWithPassword(email: email, password: _password.text);
      await authService.registerSuccessfulLogin();
      // O roteador leva ao feed (ou à troca obrigatória de senha, se ela tiver mais de 90 dias)
    } on AuthException catch (e) {
      final code = e.code ?? '';
      final msg = e.message.toLowerCase();
      if (code == 'email_not_confirmed' || msg.contains('not confirmed')) {
        if (mounted) context.push('/signup', extra: {'email': email, 'password': _password.text, 'verifyOnly': true});
      } else if (code == 'invalid_credentials' || msg.contains('invalid login')) {
        final left = await authService.registerFailedLogin(email);
        setState(() => _error = left == 0
            ? _lockedMessage
            : 'E-mail ou senha incorretos. ${left == 1 ? 'Resta 1 tentativa' : 'Restam $left tentativas'} antes do bloqueio.');
      } else {
        setState(() => _error = authErrorMessage(e));
      }
    } catch (e) {
      setState(() => _error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 32),
            Text('Vagas do mundo,\nfiltradas para quem está no Brasil.', style: t.headlineMedium),
            const SizedBox(height: 12),
            Text('Remoto do Brasil ou com patrocínio de visto, com sugestão salarial para cada vaga.',
                style: t.bodyLarge),
            const SizedBox(height: 40),
            AutofillGroup(
              child: Column(children: [
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'E-mail', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => _signIn(),
                  decoration: InputDecoration(
                    labelText: 'Senha',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Mostrar senha' : 'Esconder senha',
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
              ]),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => context.push('/forgot-password', extra: _email.text.trim()),
                child: const Text('Esqueci minha senha'),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: const TextStyle(color: AppColors.visa)),
              ),
            FilledButton(onPressed: _busy ? null : _signIn, child: Text(_busy ? 'Entrando…' : 'Entrar')),
            const SizedBox(height: 16),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54), shape: const StadiumBorder()),
              onPressed: () => context.push('/signup'),
              child: const Text('Criar conta'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Usado por outras telas para mostrar erro de forma padronizada.
void showAuthError(BuildContext context, Object e) => showError(context, authErrorMessage(e));

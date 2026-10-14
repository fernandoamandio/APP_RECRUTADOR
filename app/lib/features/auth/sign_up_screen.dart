import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/auth_service.dart';
import '../../auth/password_policy.dart';
import '../../auth/password_widgets.dart';

/// Cadastro: e-mail + senha (política) → código enviado para o e-mail → conta confirmada.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key, this.initialEmail, this.initialPassword, this.verifyOnly = false});
  final String? initialEmail;
  final String? initialPassword; // senha digitada no login, para registrar no histórico após confirmar
  final bool verifyOnly; // conta já criada, só falta confirmar o e-mail

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  late final _email = TextEditingController(text: widget.initialEmail ?? '');
  late final _password = TextEditingController(text: widget.initialPassword ?? '');
  final _confirmation = TextEditingController();
  final _code = TextEditingController();
  late bool _codeStep = widget.verifyOnly;
  bool _busy = false;

  String get _emailValue => _email.text.trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    if (widget.verifyOnly && widget.initialEmail != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _resend(silent: true));
    }
  }

  @override
  void dispose() {
    for (final c in [_email, _password, _confirmation, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showError(context, authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() => _run(() async {
        if (!isValidEmail(_emailValue)) throw const AuthException('Informe um e-mail válido.');
        final problem = passwordProblem(_password.text, _confirmation.text);
        if (problem != null) throw AuthException(problem);
        final res = await authService.auth.signUp(email: _emailValue, password: _password.text);
        if (res.session != null) {
          // Projeto sem confirmação de e-mail: já entra direto
          await _finish();
          return;
        }
        setState(() => _codeStep = true);
      });

  Future<void> _verify() => _run(() async {
        final code = _code.text.trim();
        if (code.length < 6) throw const AuthException('Digite o código que chegou no seu e-mail.');
        try {
          await authService.auth.verifyOTP(type: OtpType.email, email: _emailValue, token: code);
        } on AuthException {
          await authService.auth.verifyOTP(type: OtpType.signup, email: _emailValue, token: code);
        }
        await _finish();
      });

  Future<void> _finish() async {
    if (_password.text.isNotEmpty) await authService.recordPasswordChange(_password.text);
    await passwordGate.refresh();
    if (mounted) context.go('/onboarding/documents');
  }

  Future<void> _resend({bool silent = false}) => _run(() async {
        await authService.auth.resend(type: OtpType.signup, email: _emailValue);
        if (!silent && mounted) showError(context, 'Enviamos um novo código para $_emailValue.');
      });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(_codeStep ? 'Confirme seu e-mail' : 'Criar conta')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: _codeStep
            ? [
                Text('Digite o código', style: t.headlineMedium),
                const SizedBox(height: 12),
                EmailCodeField(controller: _code, email: _emailValue),
                const SizedBox(height: 20),
                FilledButton(onPressed: _busy ? null : _verify, child: const Text('Confirmar e-mail')),
                TextButton(onPressed: _busy ? null : _resend, child: const Text('Reenviar código')),
              ]
            : [
                Text('Crie sua conta', style: t.headlineMedium),
                const SizedBox(height: 8),
                const Text('Vamos enviar um código para o seu e-mail para confirmar que ele é seu.'),
                const SizedBox(height: 20),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'E-mail', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                NewPasswordFields(password: _password, confirmation: _confirmation, label: 'Senha'),
                const SizedBox(height: 20),
                FilledButton(onPressed: _busy ? null : _create, child: const Text('Criar conta e enviar código')),
              ],
      ),
    );
  }
}

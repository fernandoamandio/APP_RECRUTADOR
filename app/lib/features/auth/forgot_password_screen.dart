import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/auth_service.dart';
import '../../auth/password_policy.dart';
import '../../auth/password_widgets.dart';

/// Esqueci minha senha: e-mail + nova senha + confirmação → OK → código no e-mail → senha trocada.
/// Também desbloqueia a conta bloqueada por tentativas erradas.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail});
  final String? initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final _email = TextEditingController(text: widget.initialEmail ?? '');
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _code = TextEditingController();
  bool _codeStep = false;
  bool _verified = false; // código já validado: pode só escolher outra senha
  bool _busy = false;

  String get _emailValue => _email.text.trim().toLowerCase();

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

  Future<void> _submitForm() => _run(() async {
        if (!isValidEmail(_emailValue)) throw const AuthException('Informe um e-mail válido.');
        final problem = passwordProblem(_password.text, _confirmation.text);
        if (problem != null) throw AuthException(problem);
        if (_verified) {
          await _applyNewPassword();
          return;
        }
        await authService.auth.resetPasswordForEmail(_emailValue);
        setState(() => _codeStep = true);
      });

  Future<void> _verifyCode() => _run(() async {
        final code = _code.text.trim();
        if (code.length < 6) throw const AuthException('Digite o código que chegou no seu e-mail.');
        await authService.auth.verifyOTP(type: OtpType.recovery, email: _emailValue, token: code);
        _verified = true;
        await _applyNewPassword();
      });

  Future<void> _applyNewPassword() async {
    if (await authService.passwordWasUsed(_password.text)) {
      setState(() => _codeStep = false); // volta ao formulário, já validado, para escolher outra senha
      throw const AuthException(
          'Esta senha já foi usada. Escolha uma diferente das suas últimas $passwordHistorySize senhas.');
    }
    await authService.auth.updateUser(UserAttributes(password: _password.text));
    await authService.recordPasswordChange(_password.text); // também desbloqueia a conta
    passwordGate.markChanged();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Senha alterada com sucesso.')));
    context.go('/feed');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Esqueci minha senha')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: _codeStep
            ? [
                Text('Digite o código', style: t.headlineMedium),
                const SizedBox(height: 12),
                EmailCodeField(controller: _code, email: _emailValue),
                const SizedBox(height: 20),
                FilledButton(onPressed: _busy ? null : _verifyCode, child: const Text('Validar e trocar a senha')),
                TextButton(
                  onPressed: _busy ? null : () => setState(() => _codeStep = false),
                  child: const Text('Voltar e reenviar'),
                ),
              ]
            : [
                Text(_verified ? 'Escolha outra senha' : 'Redefinir senha', style: t.headlineMedium),
                const SizedBox(height: 8),
                Text(_verified
                    ? 'Seu e-mail já foi validado. Escolha uma senha que você não usou recentemente.'
                    : 'Informe seu e-mail e a nova senha. Depois enviaremos um código para confirmar que é você.'),
                const SizedBox(height: 20),
                TextField(
                  controller: _email,
                  enabled: !_verified,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'E-mail', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                NewPasswordFields(password: _password, confirmation: _confirmation),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submitForm,
                  child: Text(_verified ? 'Salvar nova senha' : 'OK, enviar código'),
                ),
              ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/auth_service.dart';
import '../../auth/password_policy.dart';
import '../../auth/password_widgets.dart';
import '../../theme.dart';

/// Alterar senha (logado): nova senha + confirmação → código no e-mail → troca confirmada.
/// Também é a tela obrigatória quando a senha passa de 90 dias.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _code = TextEditingController();
  bool _codeStep = false;
  bool _busy = false;

  String get _email => authService.auth.currentUser?.email ?? '';

  @override
  void dispose() {
    for (final c in [_password, _confirmation, _code]) {
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

  Future<void> _sendCode() => _run(() async {
        final problem = passwordProblem(_password.text, _confirmation.text);
        if (problem != null) throw AuthException(problem);
        if (await authService.passwordWasUsed(_password.text)) {
          throw const AuthException(
              'Esta senha já foi usada. Escolha uma diferente das suas últimas $passwordHistorySize senhas.');
        }
        await authService.auth.reauthenticate(); // envia o código para o e-mail da conta
        setState(() => _codeStep = true);
      });

  Future<void> _confirm() => _run(() async {
        final code = _code.text.trim();
        if (code.length < 6) throw const AuthException('Digite o código que chegou no seu e-mail.');
        await authService.auth.updateUser(UserAttributes(password: _password.text, nonce: code));
        await authService.recordPasswordChange(_password.text);
        passwordGate.markChanged();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Senha alterada com sucesso.')));
        context.go('/feed');
      });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final forced = passwordGate.expired;
    return PopScope(
      canPop: !forced,
      child: Scaffold(
        appBar: AppBar(title: const Text('Alterar senha'), automaticallyImplyLeading: !forced),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (forced)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.visaTint, borderRadius: BorderRadius.circular(12)),
                child: const Text(
                  'Sua senha passou de $passwordMaxAgeDays dias e precisa ser trocada para continuar usando o app.',
                  style: TextStyle(color: AppColors.visa, fontWeight: FontWeight.w600),
                ),
              ),
            if (_codeStep) ...[
              Text('Confirme a troca', style: t.headlineMedium),
              const SizedBox(height: 12),
              EmailCodeField(controller: _code, email: _email),
              const SizedBox(height: 20),
              FilledButton(onPressed: _busy ? null : _confirm, child: const Text('Confirmar troca de senha')),
              TextButton(onPressed: _busy ? null : _sendCode, child: const Text('Reenviar código')),
            ] else ...[
              Text('Nova senha', style: t.headlineMedium),
              const SizedBox(height: 8),
              const Text('Para sua segurança, enviaremos um código para o seu e-mail para confirmar a alteração.'),
              const SizedBox(height: 20),
              NewPasswordFields(password: _password, confirmation: _confirmation),
              const SizedBox(height: 20),
              FilledButton(onPressed: _busy ? null : _sendCode, child: const Text('Enviar código de confirmação')),
            ],
          ],
        ),
      ),
    );
  }
}

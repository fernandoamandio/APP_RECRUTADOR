import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'password_policy.dart';

/// Regras da política de senhas que dependem do banco (histórico, validade, bloqueio).
class AuthService {
  AuthService(this.sb);
  final SupabaseClient sb;

  GoTrueClient get auth => sb.auth;

  Future<bool> isLocked(String email) async =>
      (await sb.rpc('login_status', params: {'p_email': email.trim().toLowerCase()})) == 'locked';

  /// Registra uma tentativa errada; devolve quantas restam (0 = bloqueada).
  Future<int> registerFailedLogin(String email) async =>
      (await sb.rpc('login_failed', params: {'p_email': email.trim().toLowerCase()})) as int;

  Future<void> registerSuccessfulLogin() => sb.rpc('login_succeeded');

  /// A senha é igual à atual ou a uma das últimas 12?
  Future<bool> passwordWasUsed(String password) async =>
      (await sb.rpc('password_was_used', params: {'p_password': password})) == true;

  /// Depois de trocar a senha: guarda no histórico, renova os 90 dias e desbloqueia a conta.
  Future<void> recordPasswordChange(String password) =>
      sb.rpc('record_password_change', params: {'p_password': password});
}

final authService = AuthService(Supabase.instance.client);

/// Estado da senha do usuário logado, usado pelo roteador (troca obrigatória após 90 dias).
class PasswordGate extends ChangeNotifier {
  PasswordGate(this.sb) {
    sb.auth.onAuthStateChange.listen((_) => refresh());
    refresh();
  }

  final SupabaseClient sb;
  bool expired = false;
  int? daysLeft;

  Future<void> refresh() async {
    final user = sb.auth.currentUser;
    if (user == null) {
      expired = false;
      daysLeft = null;
      notifyListeners();
      return;
    }
    try {
      final row = await sb.from('profiles').select('password_changed_at').eq('user_id', user.id).maybeSingle();
      final changed = DateTime.tryParse(row?['password_changed_at'] as String? ?? '');
      if (changed != null) {
        final age = DateTime.now().toUtc().difference(changed.toUtc()).inDays;
        daysLeft = passwordMaxAgeDays - age;
        expired = daysLeft! <= 0;
      }
    } catch (_) {
      // sem rede: não bloqueia o uso do app
    }
    notifyListeners();
  }

  void markChanged() {
    expired = false;
    daysLeft = passwordMaxAgeDays;
    notifyListeners();
  }
}

final passwordGate = PasswordGate(Supabase.instance.client);

/// Traduz os erros mais comuns do Supabase Auth.
String authErrorMessage(Object e) {
  if (e is AuthException) {
    final code = e.code ?? '';
    final msg = e.message.toLowerCase();
    if (code == 'weak_password' || msg.contains('weak') || msg.contains('should contain')) {
      return 'A senha não atende à política: use 8+ caracteres com número, maiúscula, minúscula e caractere especial.';
    }
    if (code == 'same_password' || msg.contains('different from the old')) {
      return 'A nova senha deve ser diferente da atual.';
    }
    if (code == 'otp_expired' || msg.contains('expired') || (msg.contains('invalid') && msg.contains('token'))) {
      return 'Código inválido ou expirado. Confira o código ou peça um novo.';
    }
    if (code == 'reauthentication_not_valid' || msg.contains('nonce')) {
      return 'Código de confirmação inválido ou expirado. Peça um novo.';
    }
    if (code == 'over_email_send_rate_limit' || msg.contains('rate limit')) {
      return 'Muitos e-mails enviados em pouco tempo. Aguarde alguns minutos e tente de novo.';
    }
    if (code == 'email_not_confirmed' || msg.contains('not confirmed')) {
      return 'E-mail ainda não confirmado.';
    }
    if (code == 'user_already_exists' || msg.contains('already registered')) {
      return 'Já existe uma conta com este e-mail. Use "Esqueci minha senha" se não lembrar a senha.';
    }
    return e.message;
  }
  if (e is PostgrestException) return e.message;
  return 'Algo deu errado: $e';
}

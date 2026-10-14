/// Política de senhas: mínimo de 8 caracteres com número, letra maiúscula, letra minúscula
/// e caractere especial. As mesmas regras ficam configuradas no Supabase Auth, que recusa
/// senhas fracas mesmo se alguém contornar o app.
class PasswordRule {
  const PasswordRule(this.label, this.test);
  final String label;
  final bool Function(String) test;
}

const passwordMinLength = 8;
const passwordMaxAgeDays = 90;
const passwordHistorySize = 12;
const maxLoginAttempts = 5;

// Mesmo conjunto de símbolos que o Supabase aceita como "caractere especial"
final _special = RegExp(r'''[!@#$%^&*()_+\-=\[\]{};':"\\|<>?,./`~]''');

final passwordRules = <PasswordRule>[
  PasswordRule('No mínimo $passwordMinLength caracteres', (p) => p.length >= passwordMinLength),
  PasswordRule('Pelo menos um número', (p) => RegExp(r'[0-9]').hasMatch(p)),
  PasswordRule('Pelo menos uma letra maiúscula', (p) => RegExp(r'[A-Z]').hasMatch(p)),
  PasswordRule('Pelo menos uma letra minúscula', (p) => RegExp(r'[a-z]').hasMatch(p)),
  PasswordRule('Pelo menos um caractere especial (ex.: ! @ # \$ % & *)', (p) => _special.hasMatch(p)),
];

bool passwordMeetsPolicy(String p) => passwordRules.every((r) => r.test(p));

/// Mensagem de erro para o formulário, ou null se a senha e a confirmação estiverem ok.
String? passwordProblem(String password, String confirmation) {
  if (!passwordMeetsPolicy(password)) return 'A senha não atende a todos os requisitos.';
  if (password != confirmation) return 'A confirmação não é igual à nova senha.';
  return null;
}

final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
bool isValidEmail(String email) => _emailRe.hasMatch(email.trim());

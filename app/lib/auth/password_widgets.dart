import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'password_policy.dart';

/// Nova senha + confirmação, com a lista de requisitos marcando em tempo real.
class NewPasswordFields extends StatefulWidget {
  const NewPasswordFields({super.key, required this.password, required this.confirmation, this.label = 'Nova senha'});
  final TextEditingController password;
  final TextEditingController confirmation;
  final String label;

  @override
  State<NewPasswordFields> createState() => _NewPasswordFieldsState();
}

class _NewPasswordFieldsState extends State<NewPasswordFields> {
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    widget.password.addListener(_rebuild);
    widget.confirmation.addListener(_rebuild);
  }

  @override
  void dispose() {
    widget.password.removeListener(_rebuild);
    widget.confirmation.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final p = widget.password.text;
    final c = widget.confirmation.text;
    final eye = IconButton(
      tooltip: _obscure ? 'Mostrar senha' : 'Esconder senha',
      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
      onPressed: () => setState(() => _obscure = !_obscure),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        controller: widget.password,
        obscureText: _obscure,
        autofillHints: const [AutofillHints.newPassword],
        decoration: InputDecoration(labelText: widget.label, border: const OutlineInputBorder(), suffixIcon: eye),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: widget.confirmation,
        obscureText: _obscure,
        autofillHints: const [AutofillHints.newPassword],
        decoration: InputDecoration(
          labelText: 'Confirmar ${widget.label.toLowerCase()}',
          border: const OutlineInputBorder(),
          errorText: c.isNotEmpty && c != p ? 'As senhas não são iguais' : null,
        ),
      ),
      const SizedBox(height: 12),
      for (final r in passwordRules) _RuleLine(ok: r.test(p), label: r.label),
      const _RuleLine(ok: null, label: 'Diferente das suas últimas $passwordHistorySize senhas'),
    ]);
  }
}

class _RuleLine extends StatelessWidget {
  const _RuleLine({required this.ok, required this.label});
  final bool? ok; // null = verificado no servidor
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = ok == true ? const Color(0xFF15803D) : AppColors.quiet;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: [
        Icon(ok == true ? Icons.check_circle : (ok == null ? Icons.info_outline : Icons.radio_button_unchecked),
            size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: color))),
      ]),
    );
  }
}

/// Campo do código enviado por e-mail.
class EmailCodeField extends StatelessWidget {
  const EmailCodeField({super.key, required this.controller, required this.email});
  final TextEditingController controller;
  final String email;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Enviamos um código para $email. Ele expira em 1 hora. Confira também a caixa de spam.'),
      const SizedBox(height: 16),
      TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        autofillHints: const [AutofillHints.oneTimeCode],
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
        style: const TextStyle(fontSize: 24, letterSpacing: 6, fontWeight: FontWeight.w700),
        textAlign: TextAlign.center,
        decoration: const InputDecoration(labelText: 'Código', border: OutlineInputBorder()),
      ),
    ]);
  }
}

void showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

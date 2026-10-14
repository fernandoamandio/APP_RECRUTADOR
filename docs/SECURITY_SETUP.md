# Configuração de segurança no Supabase

Passos feitos uma vez, no painel do Supabase, para a política de senhas e os códigos por e-mail funcionarem.

## 1. Banco

Rode `supabase/migrations/20261014010000_password_policy.sql` no SQL Editor.

## 2. Authentication → Sign In / Providers → Email

| Configuração | Valor |
| --- | --- |
| Allow new users to sign up | Ligado (necessário para o cadastro pelo app) |
| Confirm email | Ligado |
| Secure password change | Ligado (troca de senha exige o código enviado por e-mail) |
| Minimum password length | 8 |
| Password requirements | Lowercase, uppercase letters, digits and symbols |

## 3. Authentication → Emails (templates)

Cole o conteúdo de cada arquivo de `supabase/email_templates/` no modelo correspondente. Eles usam
`{{ .Token }}`, o código de 6 dígitos, no lugar do link:

| Modelo no painel | Arquivo | Assunto sugerido |
| --- | --- | --- |
| Confirm sign up | `confirm_signup.html` | Seu código de confirmação |
| Reset password | `reset_password.html` | Código para redefinir sua senha |
| Reauthentication | `reauthentication.html` | Código para confirmar a troca de senha |

## 4. Authentication → Hooks → Custom Access Token

Ative e escolha a função `public.custom_access_token_hook`. É ela que impede o login de uma conta
bloqueada após 5 senhas erradas, mesmo que alguém tente entrar sem usar o app.

## 5. Envio de e-mails (para usuários reais)

O serviço de e-mail padrão do Supabase serve só para testes: envia apenas para os membros da
organização do projeto e com limite baixo por hora. Para o app ser usado por outras pessoas,
configure um SMTP próprio em Authentication → Emails → SMTP Settings (ex.: Resend, Brevo, Amazon SES).

## Como cada regra é aplicada

| Regra | Onde |
| --- | --- |
| 8+ caracteres, número, maiúscula, minúscula, especial | App (lista em tempo real) e Supabase Auth (recusa senha fraca) |
| Não reutilizar as últimas 12 senhas | `password_history` (hash bcrypt) + `password_was_used()` |
| Troca obrigatória a cada 90 dias | `profiles.password_changed_at`; o app avisa 7 dias antes e obriga a troca no acesso seguinte |
| Bloqueio após 5 tentativas | `auth_lockouts` + hook de access token; desbloqueio por "Esqueci minha senha" |
| Código por e-mail no cadastro, na troca e na recuperação | Supabase Auth (`verifyOTP`, `reauthenticate`, `resetPasswordForEmail`) |

Limitações conhecidas:
- O histórico de senhas é verificado pelo app antes da troca. Uma troca feita direto pela API, sem o app,
  não consulta o histórico: o Supabase não entrega a senha nova ao banco no momento da troca, e só com ela
  dá para comparar com os hashes guardados.
- As tentativas erradas são contadas pelo app. O bloqueio, porém, vale no servidor: conta bloqueada não recebe token.
- Qualquer pessoa que saiba um e-mail pode provocar 5 erros e bloquear a conta (vale para toda política de bloqueio);
  o dono desbloqueia com "Esqueci minha senha".

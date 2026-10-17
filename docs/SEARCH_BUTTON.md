# Botão "Buscar vagas" e IA de cada usuário

## IA por usuário

Em **Perfil → Inteligência artificial**, cada usuário escolhe:

- o provedor: **Claude (Anthropic)** ou **ChatGPT (OpenAI)**;
- o modelo (o app valida a chave no provedor e lista os modelos disponíveis nela);
- a própria **chave de API** e um **e-mail de contato** (vai no User-Agent das APIs de vagas).

A chave é gravada pela função `save_ai_settings()` no **Vault** do Supabase, criptografada. O app
nunca a lê de volta (mostra só os 4 últimos caracteres); só o worker, com a service role, lê pela
função `ai_credentials()`. Leitura do currículo, triagem e match usam essa IA e o custo fica na
conta do usuário. Sem chave cadastrada, o botão de busca fica bloqueado e os documentos esperam.

## Botão "Buscar vagas"

- Cada usuário pode buscar **1 vez a cada 12 horas** (`request_job_search()`); a regra está no banco.
- Uma busca que falha não conta no limite.
- O worker só processa quem pediu: coleta as vagas, faz a triagem das novas com a IA do primeiro
  usuário da rodada (o resultado é compartilhado) e calcula o match com a IA de cada um.
- Rodar à mão pela aba Actions sem pedido pendente não faz nada.
- Ao terminar, o feed recarrega e, com o app fechado, chega uma notificação uns 15 minutos depois.

## Quem dispara o worker

**Sem configurar nada:** o workflow *Analisar currículos*, que roda a cada 15 minutos, encontra o
pedido e dispara o *Worker de vagas*. A busca começa em até ~15–20 minutos.

**Na hora (opcional):** o próprio banco chama o GitHub assim que o pedido é gravado. Precisa de um
token do GitHub guardado no Vault do Supabase:

1. GitHub → foto do perfil → **Settings → Developer settings → Personal access tokens →
   Fine-grained tokens → Generate new token**.
   - *Repository access*: **Only select repositories** → `APP_RECRUTADOR`
   - *Permissions → Repository permissions → Actions*: **Read and write**
   - Copie o token (começa com `github_pat_`).
2. Supabase → **SQL Editor**, rode (colando o seu token no lugar):
   ```sql
   select vault.create_secret('github_pat_COLE_AQUI', 'github_dispatch_token');
   ```
   Para trocar depois: `select vault.update_secret((select id from vault.secrets where name = 'github_dispatch_token'), 'novo_token');`

Se o token vencer ou for inválido, nada quebra: o workflow de 15 em 15 minutos assume.

## Ajustes

- Intervalo entre buscas: parâmetro `min_interval_minutes` de `request_job_search` e `job_search_status` (padrão 720).

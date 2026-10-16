# Busca de vagas ao abrir o app

O worker não tem mais horário fixo. Ao abrir o app (ou voltar para ele), o app chama a função
`request_job_search()` no banco:

- Se houve busca nas últimas **3 horas**, nada acontece; o feed mostra quando foi a última.
- Senão, grava um pedido em `search_requests` e o feed mostra "Procurando vagas novas".
- O worker marca o pedido como concluído no fim; o feed recarrega sozinho e, com o app fechado,
  chega uma notificação uns 15 minutos depois.

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

- Intervalo mínimo entre buscas: parâmetro `min_interval_minutes` de `request_job_search` (padrão 180).
- Rodar na mão continua possível: **Actions → Worker de vagas → Run workflow**.

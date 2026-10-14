# APP_RECRUTADOR — App de Vagas Globais

App mobile que lê o currículo e a cover letter do profissional, entende o perfil com a API do Claude e entrega vagas nacionais e internacionais que permitem **trabalhar remoto do Brasil** ou que **patrocinam visto**. Para cada vaga, sugere uma pretensão salarial calibrada pelo custo de vida do destino e pela situação familiar do usuário.

> Status: esqueleto do MVP (Fase 1). A especificação completa está no documento "Especificação — App de Vagas Globais".

## Estrutura

```
app/        App Flutter (Android e iOS)
supabase/   Migrations do Postgres (com RLS) e Edge Functions
worker/     Worker Python agendado: coleta, triagem, pontuação e salário
docs/       Arquitetura e decisões
.github/    CI e agendamento do worker
```

## Como rodar

### 1. Supabase

```bash
npm i -g supabase
supabase login
supabase link --project-ref <seu-project-ref>
supabase db push                       # aplica supabase/migrations
```

A análise do currículo (PDF próprio ou PDF exportado do perfil do LinkedIn) roda no worker,
pelo workflow **Analisar currículos**, a cada 15 minutos. A Edge Function `analyze-cv` é opcional.

### 2. Worker (Python 3.11+)

```bash
cd worker
python -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"
cp .env.example .env                   # preencha as chaves
pytest                                 # testes unitários
python -m recrutador.main              # uma rodada de coleta + triagem
```

### 3. App Flutter

```bash
cd app
flutter create . --platforms=android,ios --project-name recrutador   # gera as pastas de plataforma
flutter pub get
flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=...
```

## Fontes de vagas e termos de uso

| Fonte | Uso no MVP | Obrigação |
| --- | --- | --- |
| Adzuna | Sim | Chave gratuita (app_id/app_key) |
| Jooble | Sim | Chave gratuita |
| RemoteOK | Sim | Link de volta para a vaga (sem `nofollow`) e citar a fonte |
| We Work Remotely (RSS) | Sim | Atribuição e link para a vaga |
| Working Nomads | Sim | Feed público sem chave; atribuição e link para a vaga |
| Arbeitnow | Sim | API pública sem chave (Europa; filtro de patrocínio de visto) |
| Get on Board | Sim | API pública sem chave para leitura (tech na América Latina) |
| InfoJobs | Opcional | Exige aplicação registrada (client_id/client_secret); só vagas 100% remotas |
| Remotive | **Não** | Termos proíbem uso para captar cadastros |
| LinkedIn / Indeed | **Não** | Sem API pública de busca |

Toda vaga exibida no app mostra a fonte e o link original.

## Segurança

- Chaves de API ficam só no backend (Supabase secrets e variáveis do worker), nunca no app.
- Todas as tabelas com `user_id` têm Row Level Security.
- Currículos ficam em bucket privado do Supabase Storage.

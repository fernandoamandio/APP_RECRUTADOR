# Arquitetura

```
App Flutter ──(login, dados, upload)──> Supabase (Auth · Postgres com RLS · Storage · Edge Functions)
                                             ▲                         │
                                             │ grava vagas e notas     └─ analyze-cv ──> API do Claude
Fontes de vagas ──> Worker Python (no botão)┘                                          ▲
Registros de visto, custo de vida ──┘        └──────── triagem em volume ───────────────┘
```

## Decisões

| Decisão | Motivo |
| --- | --- |
| O app só fala com o Supabase | Chaves de API ficam no servidor; o celular nunca espera chamadas lentas |
| Triagem de elegibilidade uma vez por vaga, compartilhada | Corta o custo de IA: N usuários não multiplicam as chamadas |
| PDF enviado direto ao Claude (bloco `document`) | Dispensa extração de texto no servidor e lê layouts de currículo melhor |
| Pontuação de aderência por heurística no MVP | Barata, explicável e testável; IA entra na fase 2 se a heurística não bastar |
| Aprendizado = pesos recalculados do histórico de feedback | Reproduzível e visível ao usuário; nenhum treino de modelo |
| Sugestão salarial some quando faltam dados | Melhor não sugerir do que sugerir errado |

## Pipeline do worker (`worker/recrutador/main.py`)

1. **Coleta** com os termos de busca de todos os perfis confirmados.
2. **Deduplicação** por empresa + título normalizado + país.
3. **Pré-filtro** por regras (cidadania exigida, "no sponsorship" em vaga presencial).
4. **Triagem** com o Claude (Haiku), só para vagas novas; teto por rodada.
5. **Pontuação** por usuário, com os pesos aprendidos.
6. **Salário** sugerido conforme a modalidade (`worker/recrutador/salary.py`).

## Pendências do MVP

- Telas de onboarding 3 a 5 (mobilidade, idiomas, regime e pretensão).
- Job de importação dos registros de patrocinadores (Reino Unido e Holanda) para `sponsor_registry`.
- Carga inicial de `cost_of_living` e `tax_rates` das cidades-alvo.
- Tabela de câmbio para converter o piso brasileiro na moeda da vaga (sugestão remota).
- Push de vagas novas (Firebase Cloud Messaging).
- Tela "O que o app aprendeu sobre você" e exportação/exclusão de dados (LGPD).

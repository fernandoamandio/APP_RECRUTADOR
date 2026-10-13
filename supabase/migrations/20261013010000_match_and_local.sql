-- Match do currículo + cover letter com cada vaga, e categoria "vaga no Brasil"

-- 1. Resultado do match calculado pelo Claude (por usuário e vaga)
alter table public.job_matches
  add column if not exists match_pct       smallint check (match_pct between 0 and 100),
  add column if not exists match_strengths text[] not null default '{}',
  add column if not exists match_gaps      text[] not null default '{}',
  add column if not exists matched_at      timestamptz;

-- 2. Nova categoria de elegibilidade: vaga localizada no Brasil (presencial, híbrida ou remota no país)
alter table public.job_eligibility drop constraint if exists job_eligibility_category_check;
alter table public.job_eligibility add constraint job_eligibility_category_check
  check (category in ('local_br', 'remote_br', 'visa_sponsor', 'uncertain', 'not_eligible'));

-- 3. Ordenação do feed por data
create index if not exists jobs_published_at_idx on public.jobs (published_at desc nulls last);

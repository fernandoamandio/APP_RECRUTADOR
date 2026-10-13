-- Esquema inicial do App de Vagas Globais
-- Tabelas de usuário: RLS "dono lê e escreve as próprias linhas".
-- Tabelas compartilhadas (vagas, referências): leitura para autenticados, escrita só pelo worker (service role).

create extension if not exists "pgcrypto";

-- ---------- Perfil e onboarding ----------

create table public.profiles (
  user_id        uuid primary key references auth.users(id) on delete cascade,
  full_name      text,
  current_city   text,
  modality       text check (modality in ('remote_br', 'relocation', 'both')) default 'both',
  work_regime    text check (work_regime in ('clt', 'contractor', 'both')) default 'both',
  has_cnpj       boolean default false,
  max_tz_offset  smallint,                -- diferença máxima de fuso em horas
  plan           text not null default 'free' check (plan in ('free', 'premium')),
  consent_ai_at       timestamptz,        -- LGPD: consentimento por finalidade
  consent_learning_at timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create table public.household (
  user_id               uuid primary key references auth.users(id) on delete cascade,
  marital_status        text check (marital_status in ('single', 'married', 'other')),
  children_ages         smallint[] default '{}',
  spouse_will_work      text check (spouse_will_work in ('yes', 'no', 'unknown')),
  has_pets              boolean default false,
  updated_at            timestamptz not null default now()
);

create table public.languages (
  user_id  uuid references auth.users(id) on delete cascade,
  language text not null,
  level    text not null check (level in ('basic', 'intermediate', 'advanced', 'fluent', 'native')),
  primary key (user_id, language)
);

create table public.citizenships (
  user_id uuid references auth.users(id) on delete cascade,
  country char(2) not null,               -- ISO 3166-1 alpha-2
  primary key (user_id, country)
);

create table public.target_countries (
  user_id  uuid references auth.users(id) on delete cascade,
  country  char(2) not null,
  excluded boolean not null default false,
  primary key (user_id, country)
);

create table public.documents (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  kind           text not null check (kind in ('cv', 'cover_letter')),
  storage_path   text not null,
  extracted_text text,
  version        int not null default 1,
  created_at     timestamptz not null default now()
);

create table public.career_profile (
  user_id       uuid primary key references auth.users(id) on delete cascade,
  target_titles text[] not null default '{}',
  seniority     text,
  years_total   numeric(4,1),
  stack         jsonb not null default '[]',   -- [{name, level: main|secondary|basic, years}]
  domains       text[] default '{}',
  keywords      jsonb not null default '{}',   -- {adzuna: [...], jooble: [...], remoteok_tags: [...]}
  strengths     text[] default '{}',
  gaps          text[] default '{}',
  source_doc_id uuid references public.documents(id) on delete set null,
  confirmed_at  timestamptz,                   -- usuário revisou o perfil
  updated_at    timestamptz not null default now()
);

create table public.salary_prefs (
  user_id    uuid references auth.users(id) on delete cascade,
  country    char(2) not null,                 -- 'BR' para o piso local
  modality   text not null check (modality in ('remote', 'relocation')),
  min_annual numeric(12,2) not null,
  currency   char(3) not null,
  origin     text not null default 'user' check (origin in ('user', 'learned')),
  updated_at timestamptz not null default now(),
  primary key (user_id, country, modality)
);

-- ---------- Vagas (compartilhadas) ----------

create table public.jobs (
  id            uuid primary key default gen_random_uuid(),
  dedup_hash    text not null unique,
  title         text not null,
  company       text not null,
  country       char(2),
  city          text,
  is_remote     boolean,
  salary_min    numeric(12,2),
  salary_max    numeric(12,2),
  salary_period text check (salary_period in ('year', 'month', 'hour')),
  currency      char(3),
  description   text,
  published_at  timestamptz,
  first_seen_at timestamptz not null default now(),
  last_seen_at  timestamptz not null default now()
);

-- Uma vaga pode vir de várias fontes; cada uma exige atribuição
create table public.job_sources (
  job_id      uuid references public.jobs(id) on delete cascade,
  source      text not null,                   -- adzuna | jooble | remoteok | weworkremotely
  external_id text not null,
  url         text not null,
  primary key (source, external_id)
);

create table public.job_eligibility (
  job_id             uuid primary key references public.jobs(id) on delete cascade,
  category           text not null check (category in ('remote_br', 'visa_sponsor', 'uncertain', 'not_eligible')),
  evidence           text,                     -- trecho da vaga que justifica
  confidence         numeric(3,2) check (confidence between 0 and 1),
  sponsor_registered boolean not null default false,
  model              text,
  classified_at      timestamptz not null default now()
);

create table public.job_matches (
  user_id          uuid references auth.users(id) on delete cascade,
  job_id           uuid references public.jobs(id) on delete cascade,
  score            smallint not null check (score between 0 and 100),
  reasons          text[] default '{}',
  salary_suggested jsonb,                      -- {modality, min, target, max, currency, period, inputs{...}}
  status           text not null default 'new' check (status in ('new', 'seen', 'saved', 'dismissed', 'applied')),
  created_at       timestamptz not null default now(),
  primary key (user_id, job_id)
);

-- ---------- Aprendizado ----------

create table public.feedback_events (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  job_id     uuid references public.jobs(id) on delete set null,
  kind       text not null check (kind in ('saved', 'dismissed', 'applied', 'interview', 'offer', 'rejected', 'salary_edit', 'misclassified')),
  reason     text,                             -- ex.: salary_low, country, stack, timezone, company
  value      numeric(12,2),
  currency   char(3),
  created_at timestamptz not null default now()
);

create table public.learned_prefs (
  user_id    uuid references auth.users(id) on delete cascade,
  key        text not null,                    -- ex.: country:DE, company:acme, remote_discount
  value      jsonb not null,
  weight     numeric(5,2) not null default 1,
  updated_at timestamptz not null default now(),
  primary key (user_id, key)
);

-- ---------- Referências (compartilhadas) ----------

create table public.sponsor_registry (
  country           char(2) not null,          -- GB, NL
  company_normalized text not null,
  route             text,
  updated_at        timestamptz not null default now(),
  primary key (country, company_normalized)
);

create table public.cost_of_living (
  country  char(2) not null,
  city     text not null default '',           -- '' = média do país
  item     text not null,                      -- rent_1br, rent_3br, school_per_child, health_per_person, food_per_person, transport_per_person
  monthly  numeric(12,2) not null,
  currency char(3) not null,
  source   text not null,
  ref_date date not null,
  primary key (country, city, item)
);

create table public.tax_rates (
  country        char(2) not null,
  annual_from    numeric(12,2) not null,
  effective_rate numeric(4,3) not null check (effective_rate between 0 and 1),
  currency       char(3) not null,
  source         text,
  primary key (country, annual_from)
);

create index on public.job_matches (user_id, status, score desc);
create index on public.feedback_events (user_id, created_at desc);
create index on public.jobs (last_seen_at desc);

-- ---------- RLS ----------

do $$
declare t text;
begin
  foreach t in array array['profiles','household','languages','citizenships','target_countries',
                           'documents','career_profile','salary_prefs','job_matches',
                           'feedback_events','learned_prefs']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy "%1$s_owner_all" on public.%1$I for all to authenticated
                    using (user_id = auth.uid()) with check (user_id = auth.uid())', t);
  end loop;

  foreach t in array array['jobs','job_sources','job_eligibility','sponsor_registry','cost_of_living','tax_rates']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy "%1$s_read" on public.%1$I for select to authenticated using (true)', t);
  end loop;
end $$;

-- O usuário só pode mudar o status da própria vaga, não a nota nem o salário calculado
revoke insert, update, delete on public.job_matches from authenticated;
grant update (status) on public.job_matches to authenticated;

-- Plano não é editável pelo app
revoke update on public.profiles from authenticated;
grant update (full_name, current_city, modality, work_regime, has_cnpj, max_tz_offset,
              consent_ai_at, consent_learning_at, updated_at) on public.profiles to authenticated;

-- Cria o perfil vazio ao registrar
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (user_id) values (new.id);
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- Storage: currículos em bucket privado ----------

insert into storage.buckets (id, name, public) values ('documents', 'documents', false)
  on conflict (id) do nothing;

create policy "documents_owner_rw" on storage.objects for all to authenticated
  using (bucket_id = 'documents' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'documents' and (storage.foldername(name))[1] = auth.uid()::text);

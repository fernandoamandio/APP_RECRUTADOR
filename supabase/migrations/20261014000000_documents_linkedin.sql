-- Análise de currículo pelo worker e link do perfil do LinkedIn

-- Quando o worker leu o documento (nulo = aguardando análise)
alter table public.documents add column if not exists analyzed_at timestamptz;
-- De onde veio o PDF: arquivo próprio ou exportação do perfil do LinkedIn
alter table public.documents add column if not exists origin text not null default 'upload'
  check (origin in ('upload', 'linkedin_pdf'));

-- Link do perfil do LinkedIn (guardado para referência; o LinkedIn não permite leitura automática)
alter table public.profiles add column if not exists linkedin_url text;
grant update (linkedin_url) on public.profiles to authenticated;

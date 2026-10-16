-- Busca de vagas sob demanda: o app pede uma rodada do worker ao ser aberto.
--
-- Fluxo:
-- 1. Ao abrir, o app chama request_job_search().
-- 2. Se a última busca foi há menos de 3 horas, nada acontece (evita gastar Apify e Claude
--    a cada abertura). Senão, grava um pedido em search_requests.
-- 3. Com um token do GitHub guardado no Vault (opcional), o próprio banco dispara o worker
--    na hora via pg_net. Sem o token, o workflow "Analisar currículos", que roda a cada
--    15 minutos, encontra o pedido e dispara o worker.
-- 4. O worker marca o pedido como em andamento e, no fim, como concluído.

create extension if not exists pg_net with schema extensions;

create table if not exists public.search_requests (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users on delete cascade,
  requested_at timestamptz not null default now(),
  dispatched_at timestamptz,
  started_at timestamptz,
  finished_at timestamptz,
  status text not null default 'pending' check (status in ('pending', 'running', 'done', 'failed'))
);
create index if not exists search_requests_status_idx on public.search_requests (status, requested_at);

alter table public.search_requests enable row level security;
drop policy if exists "own search requests" on public.search_requests;
create policy "own search requests" on public.search_requests for select using (user_id = auth.uid());

create or replace function public.request_job_search(min_interval_minutes int default 180)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  uid uuid := auth.uid();
  prev public.search_requests;
  req public.search_requests;
  gh_token text;
begin
  if uid is null then
    raise exception 'não autenticado';
  end if;

  -- Pedido em aberto ou busca recente (qualquer usuário: o worker busca para todos)
  select * into prev from public.search_requests
   where (status = 'pending' and requested_at > now() - interval '2 hours')
      or (status = 'running' and started_at > now() - interval '45 minutes')  -- mais que isso: travou
      or (status = 'done' and requested_at > now() - make_interval(mins => greatest(min_interval_minutes, 30)))
   order by requested_at desc limit 1;
  if found then
    return jsonb_build_object('created', false, 'id', prev.id, 'status', prev.status,
                              'requested_at', prev.requested_at, 'finished_at', prev.finished_at);
  end if;

  insert into public.search_requests (user_id) values (uid) returning * into req;

  -- Disparo imediato, só se o token do GitHub estiver no Vault (ver docs/SEARCH_ON_OPEN.md)
  begin
    select decrypted_secret into gh_token from vault.decrypted_secrets where name = 'github_dispatch_token' limit 1;
    if gh_token is not null then
      perform net.http_post(
        url := 'https://api.github.com/repos/fernandoamandio/APP_RECRUTADOR/actions/workflows/worker.yml/dispatches',
        body := jsonb_build_object('ref', 'main'),
        headers := jsonb_build_object(
          'Authorization', 'Bearer ' || gh_token,
          'Accept', 'application/vnd.github+json',
          'X-GitHub-Api-Version', '2022-11-28',
          'User-Agent', 'app-recrutador',
          'Content-Type', 'application/json'
        )
      );
      update public.search_requests set dispatched_at = now() where id = req.id;
    end if;
  exception when others then
    null; -- sem Vault/pg_net ou token inválido: o workflow de 15 em 15 minutos dispara
  end;

  return jsonb_build_object('created', true, 'id', req.id, 'status', req.status,
                            'requested_at', req.requested_at, 'finished_at', null);
end $$;

revoke all on function public.request_job_search(int) from public, anon;
grant execute on function public.request_job_search(int) to authenticated;

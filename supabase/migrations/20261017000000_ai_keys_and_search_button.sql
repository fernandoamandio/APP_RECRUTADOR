-- 1. Provedor de IA por usuário: cada um cadastra no app o provedor (Claude ou ChatGPT), o modelo,
--    a própria chave e o e-mail de contato. A chave fica criptografada no Vault; o app nunca a lê de
--    volta (só os 4 últimos caracteres, para mostrar qual está salva).
-- 2. Botão "Buscar vagas": cada usuário pode pedir uma busca a cada 12 horas.

create table if not exists public.user_ai_settings (
  user_id uuid primary key references auth.users on delete cascade,
  provider text not null check (provider in ('anthropic', 'openai')),
  model text not null,
  key_secret_id uuid,
  key_hint text,
  contact_email text,
  updated_at timestamptz not null default now()
);

alter table public.user_ai_settings enable row level security;
drop policy if exists "own ai settings" on public.user_ai_settings;
create policy "own ai settings" on public.user_ai_settings for select using (user_id = auth.uid());
-- Gravação só pela função abaixo (que guarda a chave no Vault)

create or replace function public.save_ai_settings(p_provider text, p_model text, p_api_key text default null,
                                                   p_contact_email text default null)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  uid uuid := auth.uid();
  secret_name text;
  secret_id uuid;
  hint text;
begin
  if uid is null then raise exception 'não autenticado'; end if;
  if p_provider not in ('anthropic', 'openai') then raise exception 'provedor inválido'; end if;
  if coalesce(trim(p_model), '') = '' then raise exception 'escolha um modelo'; end if;

  select key_secret_id, key_hint into secret_id, hint from public.user_ai_settings where user_id = uid;

  if coalesce(trim(p_api_key), '') <> '' then
    secret_name := 'ai_key_' || uid;
    if secret_id is null then
      select id into secret_id from vault.secrets where name = secret_name;
    end if;
    if secret_id is null then
      secret_id := vault.create_secret(trim(p_api_key), secret_name, 'Chave de IA do usuário (APP_RECRUTADOR)');
    else
      perform vault.update_secret(secret_id, trim(p_api_key));
    end if;
    hint := right(trim(p_api_key), 4);
  elsif secret_id is null then
    raise exception 'informe a chave de API';
  end if;

  insert into public.user_ai_settings (user_id, provider, model, key_secret_id, key_hint, contact_email, updated_at)
  values (uid, p_provider, trim(p_model), secret_id, hint, nullif(trim(p_contact_email), ''), now())
  on conflict (user_id) do update set provider = excluded.provider, model = excluded.model,
    key_secret_id = excluded.key_secret_id, key_hint = excluded.key_hint,
    contact_email = excluded.contact_email, updated_at = now();

  return jsonb_build_object('provider', p_provider, 'model', trim(p_model), 'key_hint', hint);
end $$;

revoke all on function public.save_ai_settings(text, text, text, text) from public, anon;
grant execute on function public.save_ai_settings(text, text, text, text) to authenticated;

-- Só o worker (service role) lê a chave decifrada
create or replace function public.ai_credentials(p_user uuid)
returns table (provider text, model text, api_key text, contact_email text)
language sql stable security definer set search_path = public as $$
  select s.provider, s.model, d.decrypted_secret, s.contact_email
    from public.user_ai_settings s
    left join vault.decrypted_secrets d on d.id = s.key_secret_id
   where s.user_id = p_user;
$$;

revoke all on function public.ai_credentials(uuid) from public, anon, authenticated;
grant execute on function public.ai_credentials(uuid) to service_role;

-- ---------- Botão "Buscar vagas" ----------

-- Situação da busca do usuário: pedido em aberto, última busca e quando a próxima é liberada
create or replace function public.job_search_status(min_interval_minutes int default 720)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  open_req public.search_requests;
  last_done public.search_requests;
  last_any public.search_requests;
begin
  if uid is null then raise exception 'não autenticado'; end if;

  select * into open_req from public.search_requests
   where user_id = uid
     and ((status = 'pending' and requested_at > now() - interval '2 hours')
       or (status = 'running' and started_at > now() - interval '45 minutes'))
   order by requested_at desc limit 1;
  select * into last_done from public.search_requests
   where user_id = uid and status = 'done' order by requested_at desc limit 1;
  select * into last_any from public.search_requests
   where user_id = uid order by requested_at desc limit 1;

  return jsonb_build_object(
    'searching', open_req.id is not null,
    -- pedido antigo que nunca terminou (worker caiu) aparece como falha
    'status', coalesce(open_req.status,
                       case when last_any.status in ('pending', 'running') then 'failed' else last_any.status end,
                       'never'),
    'requested_at', coalesce(open_req.requested_at, last_any.requested_at),
    'finished_at', case when open_req.id is null then last_any.finished_at end,
    'last_done_at', last_done.finished_at,
    -- busca que falhou não conta: o usuário pode tentar de novo
    'next_allowed_at', last_done.requested_at + make_interval(mins => min_interval_minutes),
    'has_ai_key', exists (select 1 from public.user_ai_settings where user_id = uid and key_secret_id is not null)
  );
end $$;

revoke all on function public.job_search_status(int) from public, anon;
grant execute on function public.job_search_status(int) to authenticated;

-- Substitui a versão que rodava ao abrir o app (3 horas, global) pela do botão (12 horas, por usuário)
drop function if exists public.request_job_search(int);

create or replace function public.request_job_search(min_interval_minutes int default 720)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  uid uuid := auth.uid();
  st jsonb;
  gh_token text;
begin
  if uid is null then raise exception 'não autenticado'; end if;
  st := public.job_search_status(min_interval_minutes);

  if not (st->>'has_ai_key')::boolean then
    return st || jsonb_build_object('created', false, 'error', 'no_ai_key');
  end if;
  if (st->>'searching')::boolean then
    return st || jsonb_build_object('created', false);
  end if;
  if (st->>'next_allowed_at') is not null and (st->>'next_allowed_at')::timestamptz > now() then
    return st || jsonb_build_object('created', false, 'error', 'too_soon');
  end if;

  insert into public.search_requests (user_id) values (uid);

  -- Disparo imediato, só se o token do GitHub estiver no Vault (ver docs/SEARCH_BUTTON.md)
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
      update public.search_requests set dispatched_at = now()
       where user_id = uid and status = 'pending' and dispatched_at is null;
    end if;
  exception when others then
    null; -- sem token ou token inválido: o workflow de 15 em 15 minutos dispara
  end;

  return public.job_search_status(min_interval_minutes) || jsonb_build_object('created', true);
end $$;

revoke all on function public.request_job_search(int) from public, anon;
grant execute on function public.request_job_search(int) to authenticated;

-- Política de senhas
--   * complexidade (8+ caracteres, número, maiúscula, minúscula, especial): configuração de senha do Supabase Auth
--   * não reutilizar as últimas 12 senhas: password_history + password_was_used()
--   * troca obrigatória a cada 90 dias: profiles.password_changed_at
--   * bloqueio após 5 tentativas erradas: auth_lockouts + custom_access_token_hook (aplicado pelo servidor de login)

create extension if not exists pgcrypto with schema extensions;

-- ---------- Validade da senha ----------
alter table public.profiles add column if not exists password_changed_at timestamptz not null default now();

-- ---------- Histórico (hash bcrypt; nenhuma senha em texto) ----------
create table if not exists public.password_history (
  id            bigint generated always as identity primary key,
  user_id       uuid not null references auth.users(id) on delete cascade,
  password_hash text not null,
  created_at    timestamptz not null default now()
);
create index if not exists password_history_user_idx on public.password_history (user_id, created_at desc);
alter table public.password_history enable row level security;   -- sem políticas: ninguém lê pela API
revoke all on public.password_history from anon, authenticated;

-- ---------- Bloqueio por tentativas ----------
create table if not exists public.auth_lockouts (
  email           text primary key,        -- e-mail em minúsculas
  failed_attempts int not null default 0,
  locked_at       timestamptz,
  updated_at      timestamptz not null default now()
);
alter table public.auth_lockouts enable row level security;
revoke all on public.auth_lockouts from anon, authenticated;
grant select on public.auth_lockouts to supabase_auth_admin;
drop policy if exists "auth_admin_read_lockouts" on public.auth_lockouts;
create policy "auth_admin_read_lockouts" on public.auth_lockouts for select to supabase_auth_admin using (true);

-- 'locked' ou 'ok' (não revela se o e-mail existe)
create or replace function public.login_status(p_email text) returns text
language sql stable security definer set search_path = public as $$
  select case when exists (select 1 from auth_lockouts where email = lower(trim(p_email)) and locked_at is not null)
              then 'locked' else 'ok' end;
$$;

-- Registra uma tentativa errada e devolve quantas restam (0 = conta bloqueada)
create or replace function public.login_failed(p_email text) returns integer
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into auth_lockouts as l (email, failed_attempts, updated_at)
  values (lower(trim(p_email)), 1, now())
  on conflict (email) do update
    set failed_attempts = case when l.locked_at is null then l.failed_attempts + 1 else l.failed_attempts end,
        updated_at = now()
  returning failed_attempts into n;
  if n >= 5 then
    update auth_lockouts set locked_at = coalesce(locked_at, now()) where email = lower(trim(p_email));
    return 0;
  end if;
  return 5 - n;
end $$;

-- Login certo zera o contador
create or replace function public.login_succeeded() returns void
language sql security definer set search_path = public as $$
  delete from auth_lockouts
  where email = (select lower(email) from auth.users where id = auth.uid()) and locked_at is null;
$$;

-- A nova senha é igual a alguma das últimas 12 (ou à atual)?
create or replace function public.password_was_used(p_password text) returns boolean
language plpgsql stable security definer set search_path = public, extensions as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not authenticated'; end if;
  return exists (
           select 1 from (select password_hash from password_history
                          where user_id = uid order by created_at desc, id desc limit 12) h
           where h.password_hash = extensions.crypt(p_password, h.password_hash))
      or exists (
           select 1 from auth.users u
           where u.id = uid and coalesce(u.encrypted_password, '') <> ''
             and u.encrypted_password = extensions.crypt(p_password, u.encrypted_password));
end $$;

-- Chamada logo depois da troca: guarda o hash, mantém só 12, renova os 90 dias e desbloqueia a conta
create or replace function public.record_password_change(p_password text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid := auth.uid(); v_email text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  -- Só vale para a senha que está de fato na conta
  if not exists (select 1 from auth.users u where u.id = uid
                 and u.encrypted_password = extensions.crypt(p_password, u.encrypted_password)) then
    raise exception 'a senha informada não é a senha atual da conta';
  end if;
  -- Mesma senha já registrada por último: não renova o prazo (troca é obrigatória)
  if exists (select 1 from (select password_hash from password_history where user_id = uid
                            order by created_at desc, id desc limit 1) h
             where h.password_hash = extensions.crypt(p_password, h.password_hash)) then
    return;
  end if;
  insert into password_history (user_id, password_hash)
  values (uid, extensions.crypt(p_password, extensions.gen_salt('bf')));
  delete from password_history
  where user_id = uid and id not in (select id from password_history where user_id = uid
                                     order by created_at desc, id desc limit 12);
  update profiles set password_changed_at = now() where user_id = uid;
  select lower(email) into v_email from auth.users where id = uid;
  delete from auth_lockouts where email = v_email;
end $$;

revoke execute on function public.login_status(text), public.login_failed(text), public.login_succeeded(),
                           public.password_was_used(text), public.record_password_change(text) from public;
grant execute on function public.login_status(text), public.login_failed(text) to anon, authenticated;
grant execute on function public.login_succeeded(), public.password_was_used(text),
                          public.record_password_change(text) to authenticated;

-- ---------- Hook do servidor de login: conta bloqueada não recebe token ----------
-- Ativar em Authentication → Hooks → Custom Access Token → public.custom_access_token_hook
create or replace function public.custom_access_token_hook(event jsonb) returns jsonb
language plpgsql stable as $$
declare is_locked boolean;
begin
  -- Recuperação de senha e códigos por e-mail provam a identidade: permitidos para desbloquear a conta
  if coalesce(event->>'authentication_method', '') in ('recovery', 'otp', 'email/signup', 'invite', 'magiclink') then
    return event;
  end if;
  select exists (
    select 1 from public.auth_lockouts l
    join auth.users u on lower(u.email) = l.email
    where u.id = (event->>'user_id')::uuid and l.locked_at is not null
  ) into is_locked;
  if is_locked then
    return jsonb_build_object('error', jsonb_build_object(
      'http_code', 403,
      'message', 'Conta bloqueada após 5 tentativas de senha incorretas. Use "Esqueci minha senha" para desbloquear.'));
  end if;
  return event;
end $$;

grant usage on schema public to supabase_auth_admin;
grant execute on function public.custom_access_token_hook(jsonb) to supabase_auth_admin;
revoke execute on function public.custom_access_token_hook(jsonb) from authenticated, anon, public;

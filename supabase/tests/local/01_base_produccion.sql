-- Estructura de produccion ANTES de 0011 (leida del catalogo de Postgres el 19/11/2026).
-- Solo para pruebas locales: permite ensayar migraciones sobre una copia fiel.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;
create table private.app_secrets (name text primary key, value text);
insert into private.app_secrets values ('webhook_notify', 'secreto-de-prueba');

create sequence public.ticket_number_seq;

create table public.account_items (
  id uuid not null default gen_random_uuid(), table_number integer, product_name text not null, qty integer not null default 1,
  size text, extras jsonb not null default '[]'::jsonb, quita jsonb not null default '[]'::jsonb, note text,
  unit_usd numeric not null default 0, created_at timestamp with time zone default now(), takeaway_id uuid, ticket_id uuid);
create table public.app_config (
  id integer not null default 1, rate numeric not null default 36.5, updated_at timestamp with time zone default now(),
  business_name text not null default 'Puesto de Comida'::text, motiv_shown boolean not null default false);
create table public.app_users (
  id uuid not null default gen_random_uuid(), name text not null default ''::text, pin text not null, role text not null default 'mesero'::text,
  active boolean not null default true, created_at timestamp with time zone default now(), pin_hash text, email text);
create table public.cancellations (
  id uuid not null default gen_random_uuid(), ticket_number integer, table_number integer, takeaway_name text, reason text,
  merchandise_used boolean not null default false, value_usd numeric not null default 0, by_user text, at timestamp with time zone default now());
create table public.cash_closes (
  id uuid not null default gen_random_uuid(), closed_at timestamp with time zone not null default now(), from_at timestamp with time zone,
  total_usd numeric not null default 0, accounts_count integer not null default 0, by_method jsonb not null default '{}'::jsonb,
  units jsonb not null default '{}'::jsonb, gastos_usd numeric not null default 0);
create table public.categories (
  id uuid not null default gen_random_uuid(), key text not null, label text not null, emoji text not null default '🍽️'::text,
  "position" integer not null default 100, protected boolean not null default false);
create table public.device_tokens (
  token text not null, user_email text not null, role text not null, updated_at timestamp with time zone not null default now());
create table public.dining_tables (
  number integer not null, capacity integer not null default 2, status text not null default 'disponible'::text, waiter text, opened_at timestamp with time zone);
create table public.employees (
  id uuid not null default gen_random_uuid(), name text not null default ''::text, cedula text, birthdate text, phone text, address text,
  "position" text, schedule text, salary numeric not null default 0, deductions numeric not null default 0, notes text,
  active boolean not null default true, created_at timestamp with time zone default now());
create table public.gastos (
  id uuid not null default gen_random_uuid(), concept text not null, category text not null default 'otros'::text, amount_usd numeric not null default 0,
  payment_method text, note text, by_user text, at timestamp with time zone not null default now());
create table public.ingredients (
  id uuid not null default gen_random_uuid(), name text not null, unit text not null default 'unidad'::text, stock numeric not null default 0,
  min_stock numeric not null default 0, updated_at timestamp with time zone default now(), cost numeric not null default 0,
  cost_currency text not null default 'usd'::text, kind text not null default 'comida'::text, emoji text not null default '📦'::text);
create table public.products (
  id uuid not null default gen_random_uuid(), name text not null, emoji text default '🍽️'::text, category text not null default 'otros'::text,
  price numeric not null default 0, currency text not null default 'usd'::text, available boolean not null default true,
  sizes jsonb not null default '[]'::jsonb, extras jsonb not null default '[]'::jsonb, quita jsonb not null default '[]'::jsonb,
  updated_at timestamp with time zone default now(), stock numeric not null default 0, min_stock numeric not null default 0,
  track_stock boolean not null default false, recipe jsonb not null default '[]'::jsonb, combo_items jsonb not null default '[]'::jsonb);
create table public.sales (
  id uuid not null default gen_random_uuid(), table_number integer, total_usd numeric not null default 0, lines jsonb not null default '[]'::jsonb,
  payments jsonb not null default '[]'::jsonb, at timestamp with time zone default now(), customer text);
create table public.takeaways (
  id uuid not null default gen_random_uuid(), name text not null default ''::text, status text not null default 'abierta'::text,
  created_at timestamp with time zone default now());
create table public.tickets (
  id uuid not null default gen_random_uuid(), number integer not null default nextval('ticket_number_seq'::regclass), table_number integer,
  waiter text, status text not null default 'nueva'::text, adicion boolean not null default false, note text, lines jsonb not null default '[]'::jsonb,
  reprinted boolean not null default false, sent_at timestamp with time zone default now(), takeaway_id uuid, takeaway_name text);

alter table public.account_items add constraint account_items_pkey PRIMARY KEY (id);
alter table public.app_config add constraint app_config_pkey PRIMARY KEY (id);
alter table public.app_users add constraint app_users_pkey PRIMARY KEY (id);
alter table public.cancellations add constraint cancellations_pkey PRIMARY KEY (id);
alter table public.cash_closes add constraint cash_closes_pkey PRIMARY KEY (id);
alter table public.categories add constraint categories_key_key UNIQUE (key);
alter table public.categories add constraint categories_pkey PRIMARY KEY (id);
alter table public.device_tokens add constraint device_tokens_pkey PRIMARY KEY (token);
alter table public.dining_tables add constraint dining_tables_pkey PRIMARY KEY (number);
alter table public.employees add constraint employees_pkey PRIMARY KEY (id);
alter table public.gastos add constraint gastos_pkey PRIMARY KEY (id);
alter table public.ingredients add constraint ingredients_pkey PRIMARY KEY (id);
alter table public.products add constraint products_pkey PRIMARY KEY (id);
alter table public.sales add constraint sales_pkey PRIMARY KEY (id);
alter table public.takeaways add constraint takeaways_pkey PRIMARY KEY (id);
alter table public.tickets add constraint tickets_pkey PRIMARY KEY (id);
do $$ declare t text; begin
  foreach t in array array['account_items','app_config','app_users','cancellations','cash_closes','categories','device_tokens','dining_tables','employees','gastos','ingredients','products','sales','takeaways','tickets'] loop
    execute format('alter table public.%I enable row level security', t);
  end loop; end $$;

-- ---------- funciones ----------
CREATE OR REPLACE FUNCTION private.staff_role() RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $function$
  select a.role from public.app_users a
  where a.active and lower(a.email) = lower(coalesce(auth.jwt() ->> 'email', '')) limit 1;
$function$;
CREATE OR REPLACE FUNCTION private.is_admin() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $function$
  select coalesce(private.staff_role() = 'admin', false);
$function$;
CREATE OR REPLACE FUNCTION private.notify_new_ticket() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
begin
  if new.status = 'nueva' then
    perform net.http_post(
      url := 'https://tmjejukvdcfifajnmlca.supabase.co/functions/v1/notify-comanda',
      headers := jsonb_build_object('Content-Type', 'application/json',
        'x-webhook-secret', (select value from private.app_secrets where name = 'webhook_notify')),
      body := jsonb_build_object('number', new.number, 'table', new.table_number, 'takeaway', new.takeaway_name, 'adicion', new.adicion));
  end if;
  return new;
exception when others then
  return new;
end;
$function$;
CREATE OR REPLACE FUNCTION private.pin_debil(p text) RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path TO '' AS $function$
  select p ~ '^(\d)\1{5}$' or p ~ '^(\d\d)\1\1$' or p ~ '^(\d\d\d)\1$' or p ~ '^(\d)(\d)(\d)\3\2\1$' or p ~ '^(\d)\1(\d)\2(\d)\3$'
    or p in ('012345','123456','234567','345678','456789','567890','678901','789012','890123','901234',
             '987654','876543','765432','654321','543210','432109','321098','210987','109876','098765');
$function$;
CREATE OR REPLACE FUNCTION private.tickets_guard() RETURNS trigger LANGUAGE plpgsql SET search_path TO '' AS $function$
begin
  if private.staff_role() = 'cocina' then
    if (to_jsonb(new) - 'status' - 'reprinted') is distinct from (to_jsonb(old) - 'status' - 'reprinted') then
      raise exception 'Cocina solo puede cambiar el estado de la comanda' using errcode = '42501';
    end if;
    if new.status is distinct from old.status then
      if old.status in ('anulada', 'entregada') then raise exception 'Esta comanda ya esta cerrada' using errcode = '42501'; end if;
      if new.status not in ('preparando', 'lista', 'entregada') then raise exception 'Estado no permitido para cocina' using errcode = '42501'; end if;
    end if;
  end if;
  return new;
end;
$function$;
CREATE OR REPLACE FUNCTION public.admin_esquema()
 RETURNS TABLE(tabla text, tipo text, columna text, tipo_dato text, nulo boolean, por_defecto text, es_pk boolean, posicion integer, filas_aprox bigint)
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $function$
begin
  if not private.is_admin() then raise exception 'No autorizado' using errcode = '42501'; end if;
  return query
  select c.relname::text, case c.relkind when 'v' then 'vista' else 'tabla' end, a.attname::text, pg_catalog.format_type(a.atttypid, a.atttypmod),
         not a.attnotnull, pg_catalog.pg_get_expr(d.adbin, d.adrelid),
         exists (select 1 from pg_catalog.pg_index i where i.indrelid = c.oid and i.indisprimary and a.attnum = any(i.indkey::int2[])),
         a.attnum::int, greatest(c.reltuples, 0)::bigint
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
    join pg_catalog.pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
    left join pg_catalog.pg_attrdef d on d.adrelid = c.oid and d.adnum = a.attnum
   where c.relkind in ('r', 'v') order by c.relname, a.attnum;
end;
$function$;
CREATE OR REPLACE FUNCTION public.cambiar_pin(p_actual text, p_nuevo text) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'extensions', 'public' AS $function$
declare uid uuid := auth.uid(); hash text;
begin
  if uid is null then return 'sin_sesion'; end if;
  select encrypted_password into hash from auth.users where id = uid;
  if hash is null then return 'sin_usuario'; end if;
  if hash <> crypt(p_actual || '-comandas', hash) then return 'pin_actual_incorrecto'; end if;
  if p_nuevo !~ '^[0-9]{6}$' then return 'pin_nuevo_invalido'; end if;
  if private.pin_debil(p_nuevo) then return 'pin_nuevo_facil'; end if;
  update auth.users set encrypted_password = crypt(p_nuevo || '-comandas', gen_salt('bf')), updated_at = now() where id = uid;
  return 'ok';
end;
$function$;
CREATE OR REPLACE FUNCTION public.deduct_ingredient(i_id uuid, i_qty numeric) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
begin
  if coalesce(private.staff_role(), '') not in ('admin', 'mesero') then raise exception 'No autorizado' using errcode = '42501'; end if;
  if i_qty is null or i_qty < 0 then raise exception 'Cantidad invalida' using errcode = '22023'; end if;
  update ingredients set stock = stock - i_qty where id = i_id;
end;
$function$;
CREATE OR REPLACE FUNCTION public.deduct_stock(p_id uuid, p_qty numeric) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
begin
  if coalesce(private.staff_role(), '') not in ('admin', 'mesero') then raise exception 'No autorizado' using errcode = '42501'; end if;
  if p_qty is null or p_qty < 0 then raise exception 'Cantidad invalida' using errcode = '22023'; end if;
  update products set stock = stock - p_qty,
      available = case when track_stock and (stock - p_qty) <= 0 then false else available end
  where id = p_id and track_stock = true;
end;
$function$;
CREATE OR REPLACE FUNCTION public.my_profile() RETURNS TABLE(id uuid, name text, role text) LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
  select a.id, a.name, a.role from public.app_users a
  where a.active and lower(a.email) = lower(coalesce(auth.jwt() ->> 'email', '')) limit 1;
$function$;
CREATE OR REPLACE FUNCTION public.register_device(p_token text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
declare r text := private.staff_role();
begin
  if r not in ('admin', 'cocina') then raise exception 'No autorizado' using errcode = '42501'; end if;
  if p_token is null or length(p_token) < 20 then raise exception 'Token invalido' using errcode = '22023'; end if;
  insert into public.device_tokens (token, user_email, role, updated_at)
  values (p_token, lower(coalesce(auth.jwt() ->> 'email', '')), r, now())
  on conflict (token) do update set user_email = excluded.user_email, role = excluded.role, updated_at = now();
end;
$function$;
CREATE OR REPLACE FUNCTION public.save_user(p_id uuid, p_name text, p_pin text, p_role text, p_active boolean) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions' AS $function$
declare v_email text;
begin
  if not private.is_admin() then raise exception 'No autorizado' using errcode = '42501'; end if;
  if p_role not in ('admin', 'cocina', 'mesero') then raise exception 'Rol invalido' using errcode = '22023'; end if;
  if (p_id is null or coalesce(p_pin, '') <> '') and coalesce(p_pin, '') !~ '^[0-9]{6}$' then raise exception 'El PIN debe ser de 6 numeros' using errcode = '22023'; end if;
  if coalesce(p_pin, '') <> '' and private.pin_debil(p_pin) then raise exception 'PIN demasiado facil de adivinar' using errcode = '22023'; end if;
  if p_id is null then
    insert into app_users(name, pin, pin_hash, role, active) values (p_name, '', crypt(p_pin, gen_salt('bf')), p_role, p_active);
  else
    update app_users set name = p_name, role = p_role, active = p_active,
      pin_hash = case when coalesce(p_pin,'') <> '' then crypt(p_pin, gen_salt('bf')) else pin_hash end
    where id = p_id returning email into v_email;
    if coalesce(p_pin, '') <> '' and coalesce(v_email, '') <> '' then
      update auth.users set encrypted_password = crypt(p_pin || '-comandas', gen_salt('bf')), updated_at = now() where lower(email) = lower(v_email);
    end if;
  end if;
end;
$function$;
CREATE OR REPLACE FUNCTION public.unregister_device(p_token text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
begin
  if coalesce(private.staff_role(), '') = '' then raise exception 'No autorizado' using errcode = '42501'; end if;
  delete from public.device_tokens where token = p_token;
end;
$function$;

create or replace view public.public_staff as SELECT id, name, email, role FROM app_users WHERE (active AND (COALESCE(email, ''::text) <> ''::text));
CREATE TRIGGER tickets_guard BEFORE UPDATE ON public.tickets FOR EACH ROW EXECUTE FUNCTION private.tickets_guard();
CREATE TRIGGER tickets_notify AFTER INSERT ON public.tickets FOR EACH ROW EXECUTE FUNCTION private.notify_new_ticket();

-- ---------- reglas de acceso (RLS) ----------
create policy account_items_delete on public.account_items as PERMISSIVE for DELETE to authenticated using ((( SELECT private.staff_role()) = ANY (ARRAY['admin','mesero'])));
create policy account_items_insert on public.account_items as PERMISSIVE for INSERT to authenticated with check ((( SELECT private.staff_role()) = ANY (ARRAY['admin','mesero'])));
create policy account_items_select on public.account_items as PERMISSIVE for SELECT to authenticated using ((( SELECT private.staff_role()) = ANY (ARRAY['admin','mesero'])));
create policy account_items_update on public.account_items as PERMISSIVE for UPDATE to authenticated using ((( SELECT private.staff_role()) = ANY (ARRAY['admin','mesero']))) with check ((( SELECT private.staff_role()) = ANY (ARRAY['admin','mesero'])));
create policy app_config_select on public.app_config as PERMISSIVE for SELECT to authenticated using ((( SELECT private.staff_role()) = ANY (ARRAY['admin','mesero','cocina'])));
create policy app_config_write on public.app_config as PERMISSIVE for ALL to authenticated using (( SELECT private.is_admin())) with check (( SELECT private.is_admin()));
create policy app_users_delete on public.app_users as PERMISSIVE for DELETE to authenticated using (( SELECT private.is_admin()));
create policy app_users_insert on public.app_users as PERMISSIVE for INSERT to authenticated with check (( SELECT private.is_admin()));
create policy app_users_select on public.app_users as PERMISSIVE for SELECT to authenticated using ((( SELECT private.is_admin()) OR (lower(email) = lower(COALESCE((auth.jwt() ->> 'email'), '')))));
create policy app_users_update on public.app_users as PERMISSIVE for UPDATE to authenticated using (( SELECT private.is_admin())) with check (( SELECT private.is_admin()));
create policy cancellations_admin on public.cancellations as PERMISSIVE for ALL to authenticated using (( SELECT private.is_admin())) with check (( SELECT private.is_admin()));
create policy cash_closes_admin on public.cash_closes as PERMISSIVE for ALL to authenticated using (( SELECT private.is_admin())) with check (( SELECT private.is_admin()));
create policy categories_select on public.categories as PERMISSIVE for SELECT to authenticated using ((( SELECT private.staff_role()) = ANY (ARRAY['admin','mesero'])));
create policy categories_write on public.categories as PERMISSIVE for ALL to authenticated using (( SELECT private.is_admin())) with check (( SELECT private.is_admin()));
create policy dining_tables_delete on public.dining_tables as PERMISSIVE for DELETE to authenticated using (( SELECT private.is_admin()));
create policy dining_tables_insert on public.dining_tables as PERMISSIVE for INSERT to authenticated with check (( SELECT private.is_admin()));
create policy dining_tables_select on public.dining_tables as PERMISSIVE for SELECT to authenticated using ((( SELECT private.staff_role()) = ANY (ARRAY['admin','mesero'])));
create policy dining_tables_update on public.dining_tables as PERMISSIVE for UPDATE to authenticated using ((( SELECT private.staff_role()) = ANY (ARRAY['admin','mesero']))) with check ((( SELECT private.staff_role()) = ANY (ARRAY['admin','mesero'])));
create policy employees_admin on public.employees as PERMISSIVE for ALL to authenticated using (( SELECT private.is_admin())) with check (( SELECT private.is_admin()));
create policy gastos_admin on public.gastos as PERMISSIVE for ALL to authenticated using (( SELECT private.is_admin())) with check (( SELECT private.is_admin()));
create policy ingredients_select on public.ingredients as PERMISSIVE for SELECT to authenticated using ((( SELECT private.staff_role()) = ANY (ARRAY['admin','mesero'])));
create policy ingredients_write on public.ingredients as PERMISSIVE for ALL to authenticated using (( SELECT private.is_admin())) with check (( SELECT private.is_admin()));
create policy products_select on public.products as PERMISSIVE for SELECT to authenticated using ((( SELECT private.staff_role()) = ANY (ARRAY['admin','mesero'])));
create policy products_write on public.products as PERMISSIVE for ALL to authenticated using (( SELECT private.is_admin())) with check (( SELECT private.is_admin()));
create policy sales_delete on public.sales as PERMISSIVE for DELETE to authenticated using (( SELECT private.is_admin()));
create policy sales_insert on public.sales as PERMISSIVE for INSERT to authenticated with check ((( SELECT private.staff_role()) = ANY (ARRAY['admin','mesero'])));
create policy sales_select on public.sales as PERMISSIVE for SELECT to authenticated using (( SELECT private.is_admin()));
create policy sales_update on public.sales as PERMISSIVE for UPDATE to authenticated using (( SELECT private.is_admin())) with check (( SELECT private.is_admin()));
create policy takeaways_delete on public.takeaways as PERMISSIVE for DELETE to authenticated using ((( SELECT private.staff_role()) = ANY (ARRAY['admin','mesero'])));
create policy takeaways_insert on public.takeaways as PERMISSIVE for INSERT to authenticated with check ((( SELECT private.staff_role()) = ANY (ARRAY['admin','mesero'])));
create policy takeaways_select on public.takeaways as PERMISSIVE for SELECT to authenticated using ((( SELECT private.staff_role()) = ANY (ARRAY['admin','mesero'])));
create policy takeaways_update on public.takeaways as PERMISSIVE for UPDATE to authenticated using ((( SELECT private.staff_role()) = ANY (ARRAY['admin','mesero']))) with check ((( SELECT private.staff_role()) = ANY (ARRAY['admin','mesero'])));
create policy tickets_delete on public.tickets as PERMISSIVE for DELETE to authenticated using (( SELECT private.is_admin()));
create policy tickets_insert on public.tickets as PERMISSIVE for INSERT to authenticated with check ((( SELECT private.staff_role()) = ANY (ARRAY['admin','mesero'])));
create policy tickets_select on public.tickets as PERMISSIVE for SELECT to authenticated using ((( SELECT private.staff_role()) = ANY (ARRAY['admin','mesero','cocina'])));
create policy tickets_update on public.tickets as PERMISSIVE for UPDATE to authenticated using ((( SELECT private.staff_role()) = ANY (ARRAY['admin','mesero','cocina']))) with check ((( SELECT private.staff_role()) = ANY (ARRAY['admin','mesero','cocina'])));

-- ---------- permisos ----------
grant select, insert, update, delete on all tables in schema public to authenticated;
revoke all on public.device_tokens from authenticated;
revoke all on public.app_users from anon;
grant usage, select on sequence public.ticket_number_seq to authenticated;
grant select on public.public_staff to anon, authenticated;
revoke execute on all functions in schema public from public, anon;
revoke execute on all functions in schema private from public, anon;
grant execute on function private.is_admin(), private.staff_role(), private.pin_debil(text) to authenticated;
grant execute on function public.admin_esquema(), public.cambiar_pin(text, text), public.deduct_ingredient(uuid, numeric), public.deduct_stock(uuid, numeric),
  public.my_profile(), public.register_device(text), public.save_user(uuid, text, text, text, boolean), public.unregister_device(text) to authenticated, service_role;
alter publication supabase_realtime add table public.app_config, public.products, public.dining_tables, public.account_items, public.tickets, public.sales,
  public.ingredients, public.takeaways, public.cancellations, public.employees, public.app_users, public.cash_closes, public.categories, public.gastos;

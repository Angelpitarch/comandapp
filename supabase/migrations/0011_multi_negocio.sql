-- 0011: ComandApp para varios negocios en una sola base de datos.
--
-- Idea: cada fila pertenece a un negocio (columna negocio_id). Quien entra solo ve y cambia
-- las filas de SU negocio, gracias a una regla "restrictiva" por tabla que se suma a las reglas
-- por rol que ya existian. El negocio de cada persona sale de su usuario (app_users.negocio_id).
--
-- Compatible con la app actual: negocio_id se llena solo al insertar (valor por defecto), la tasa
-- sigue en app_config con id = 1 (una fila por negocio), las mesas siguen identificandose por su
-- numero dentro del negocio y los numeros de comanda siguen consecutivos, ahora por negocio.
--
-- El negocio que ya existia pasa a ser el primero, sin perder nada.

begin;

-- ---------------------------------------------------------------- negocios
create table if not exists public.negocios (
  id         uuid primary key default gen_random_uuid(),
  nombre     text not null,
  codigo     text not null unique check (codigo ~ '^[a-z0-9][a-z0-9-]{1,40}$'), -- para entrar a la app (ej: puesto-de-comida)
  rif        text,
  telefono   text,
  direccion  text,
  logo_url   text,
  plan       text not null default 'fundador',
  estado     text not null default 'activo' check (estado in ('activo', 'suspendido')),
  vence_el   date,                     -- null = sin vencimiento
  creado_el  timestamptz not null default now()
);
comment on table public.negocios is 'Negocios clientes de ComandApp. Cada persona ve solo el suyo.';

-- Dueno(s) de la plataforma: pueden crear y administrar negocios (lo usara el panel de plataforma).
create table if not exists private.plataforma_admins (email text primary key);

-- Contadores por negocio (numero de comanda, y mas adelante facturas, etc.)
create table if not exists private.contadores (
  negocio_id uuid not null references public.negocios(id) on delete cascade,
  nombre     text not null,
  valor      bigint not null default 0,
  primary key (negocio_id, nombre)
);

-- ---------------------------------------------------------------- el negocio que ya existe
insert into public.negocios (nombre, codigo)
select coalesce((select business_name from public.app_config order by id limit 1), 'Mi negocio'), 'puesto-de-comida'
where not exists (select 1 from public.negocios);

-- ---------------------------------------------------------------- negocio_id en todas las tablas
do $$
declare
  t text;
  primero uuid := (select id from public.negocios order by creado_el limit 1);
begin
  foreach t in array array['account_items','app_config','app_users','cancellations','cash_closes','categories','device_tokens',
                           'dining_tables','employees','gastos','ingredients','products','sales','takeaways','tickets'] loop
    execute format('alter table public.%I add column if not exists negocio_id uuid', t);
    execute format('update public.%I set negocio_id = %L where negocio_id is null', t, primero);
    execute format('alter table public.%I alter column negocio_id set not null', t);
    execute format('alter table public.%I drop constraint if exists %I', t, t || '_negocio_fk');
    execute format('alter table public.%I add constraint %I foreign key (negocio_id) references public.negocios(id)', t, t || '_negocio_fk');
    execute format('create index if not exists %I on public.%I (negocio_id)', t || '_negocio_idx', t);
  end loop;
end $$;

-- El negocio actual: el del usuario que hace la peticion, solo si esta activo y al dia.
create or replace function private.negocio_actual()
returns uuid
language sql stable security definer set search_path = ''
as $$
  select a.negocio_id
    from public.app_users a
    join public.negocios n on n.id = a.negocio_id
   where a.active
     and lower(a.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
     and n.estado = 'activo'
     and (n.vence_el is null or n.vence_el >= (now() at time zone 'America/Caracas')::date)
   limit 1;
$$;

-- El rol ahora tambien exige que el negocio este activo.
create or replace function private.staff_role()
returns text
language sql stable security definer set search_path = ''
as $$
  select a.role
    from public.app_users a
    join public.negocios n on n.id = a.negocio_id
   where a.active
     and lower(a.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
     and n.estado = 'activo'
     and (n.vence_el is null or n.vence_el >= (now() at time zone 'America/Caracas')::date)
   limit 1;
$$;

create or replace function private.siguiente_numero(p_negocio uuid, p_nombre text)
returns bigint
language sql volatile security definer set search_path = ''
as $$
  insert into private.contadores as c (negocio_id, nombre, valor) values (p_negocio, p_nombre, 1)
  on conflict (negocio_id, nombre) do update set valor = c.valor + 1
  returning c.valor;
$$;

revoke all on function private.negocio_actual(), private.siguiente_numero(uuid, text) from public, anon;
grant execute on function private.negocio_actual() to authenticated;

-- Valor por defecto (el negocio de quien inserta) y regla restrictiva en cada tabla.
do $$
declare t text;
begin
  foreach t in array array['account_items','app_config','app_users','cancellations','cash_closes','categories','device_tokens',
                           'dining_tables','employees','gastos','ingredients','products','sales','takeaways','tickets'] loop
    execute format('alter table public.%I alter column negocio_id set default private.negocio_actual()', t);
    -- regla restrictiva: se suma (AND) a las reglas por rol que ya existen
    execute format('drop policy if exists %I on public.%I', t || '_negocio', t);
    execute format('create policy %I on public.%I as restrictive for all to authenticated
                      using (negocio_id = (select private.negocio_actual()))
                      with check (negocio_id = (select private.negocio_actual()))', t || '_negocio', t);
  end loop;
end $$;

-- ---------------------------------------------------------------- claves unicas por negocio
-- app_config: una fila por negocio; id sigue valiendo 1 para que la app actual no cambie.
alter table public.app_config drop constraint if exists app_config_pkey;
alter table public.app_config add constraint app_config_pkey primary key (negocio_id);

-- mesas: el numero se repite entre negocios
alter table public.dining_tables drop constraint if exists dining_tables_pkey;
alter table public.dining_tables add constraint dining_tables_pkey primary key (negocio_id, number);

-- categorias: la clave se repite entre negocios
alter table public.categories drop constraint if exists categories_key_key;
alter table public.categories add constraint categories_negocio_key_key unique (negocio_id, key);

-- un correo identifica a una sola persona en toda la plataforma
create unique index if not exists app_users_email_unico on public.app_users (lower(email)) where email is not null and email <> '';

-- ---------------------------------------------------------------- numero de comanda por negocio
insert into private.contadores (negocio_id, nombre, valor)
select n.id, 'comanda', greatest(coalesce((select max(number) from public.tickets t where t.negocio_id = n.id), 0),
                                 (select last_value from public.ticket_number_seq))
  from public.negocios n
on conflict (negocio_id, nombre) do nothing;

alter table public.tickets alter column number drop default;

create or replace function private.tickets_numero()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.negocio_id is null then
    raise exception 'No se pudo saber a que negocio pertenece esta comanda' using errcode = '42501';
  end if;
  if new.number is null then
    new.number := private.siguiente_numero(new.negocio_id, 'comanda');
  end if;
  return new;
end;
$$;
drop trigger if exists tickets_numero on public.tickets;
create trigger tickets_numero before insert on public.tickets for each row execute function private.tickets_numero();

-- ---------------------------------------------------------------- negocios: quien ve y cambia que
alter table public.negocios enable row level security;
drop policy if exists negocios_select on public.negocios;
create policy negocios_select on public.negocios for select to authenticated using (id = (select private.negocio_actual()));
drop policy if exists negocios_update on public.negocios;
create policy negocios_update on public.negocios for update to authenticated
  using (id = (select private.negocio_actual()) and (select private.is_admin()))
  with check (id = (select private.negocio_actual()) and (select private.is_admin()));
revoke all on public.negocios from anon, authenticated;
grant select on public.negocios to authenticated;
-- el admin del negocio puede editar sus datos, pero no el plan, el estado ni el vencimiento
grant update (nombre, rif, telefono, direccion, logo_url) on public.negocios to authenticated;

-- Si el admin cambia el nombre en la app (app_config), se refleja en negocios.
create or replace function private.sincronizar_nombre()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.business_name is distinct from old.business_name and coalesce(new.business_name, '') <> '' then
    update public.negocios set nombre = new.business_name where id = new.negocio_id;
  end if;
  return new;
end;
$$;
drop trigger if exists app_config_nombre on public.app_config;
create trigger app_config_nombre after update on public.app_config for each row execute function private.sincronizar_nombre();

-- ---------------------------------------------------------------- funciones con control de negocio
create or replace function public.deduct_ingredient(i_id uuid, i_qty numeric)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if coalesce(private.staff_role(), '') not in ('admin', 'mesero') then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if i_qty is null or i_qty < 0 then
    raise exception 'Cantidad invalida' using errcode = '22023';
  end if;
  update ingredients set stock = stock - i_qty, updated_at = now()
   where id = i_id and negocio_id = private.negocio_actual();
end;
$$;

create or replace function public.deduct_stock(p_id uuid, p_qty numeric)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if coalesce(private.staff_role(), '') not in ('admin', 'mesero') then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_qty is null or p_qty < 0 then
    raise exception 'Cantidad invalida' using errcode = '22023';
  end if;
  update products
     set stock = stock - p_qty,
         available = case when track_stock and (stock - p_qty) <= 0 then false else available end
   where id = p_id and track_stock = true and negocio_id = private.negocio_actual();
end;
$$;

create or replace function public.save_user(p_id uuid, p_name text, p_pin text, p_role text, p_active boolean)
returns void
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_email text;
  v_neg uuid := private.negocio_actual();
begin
  if not private.is_admin() or v_neg is null then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_role not in ('admin', 'cocina', 'mesero') then
    raise exception 'Rol invalido' using errcode = '22023';
  end if;
  if (p_id is null or coalesce(p_pin, '') <> '') and coalesce(p_pin, '') !~ '^[0-9]{6}$' then
    raise exception 'El PIN debe ser de 6 numeros' using errcode = '22023';
  end if;
  if coalesce(p_pin, '') <> '' and private.pin_debil(p_pin) then
    raise exception 'PIN demasiado facil de adivinar' using errcode = '22023';
  end if;
  if p_id is null then
    insert into app_users(name, pin, pin_hash, role, active, negocio_id)
      values (p_name, '', crypt(p_pin, gen_salt('bf')), p_role, p_active, v_neg);
  else
    update app_users set name = p_name, role = p_role, active = p_active,
      pin_hash = case when coalesce(p_pin,'') <> '' then crypt(p_pin, gen_salt('bf')) else pin_hash end
     where id = p_id and negocio_id = v_neg
    returning email into v_email;
    if not found then
      raise exception 'Usuario no encontrado' using errcode = 'P0002';
    end if;
    if coalesce(p_pin, '') <> '' and coalesce(v_email, '') <> '' then
      update auth.users
         set encrypted_password = crypt(p_pin || '-comandas', gen_salt('bf')), updated_at = now()
       where lower(email) = lower(v_email);
    end if;
  end if;
end;
$$;

create or replace function public.register_device(p_token text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r text := private.staff_role();
  v_neg uuid := private.negocio_actual();
begin
  if r not in ('admin', 'cocina') or v_neg is null then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_token is null or length(p_token) < 20 then
    raise exception 'Token invalido' using errcode = '22023';
  end if;
  insert into public.device_tokens (token, user_email, role, updated_at, negocio_id)
  values (p_token, lower(coalesce(auth.jwt() ->> 'email', '')), r, now(), v_neg)
  on conflict (token) do update
    set user_email = excluded.user_email, role = excluded.role, updated_at = now(), negocio_id = excluded.negocio_id;
end;
$$;

create or replace function public.unregister_device(p_token text)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if coalesce(private.staff_role(), '') = '' then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  delete from public.device_tokens where token = p_token and negocio_id = private.negocio_actual();
end;
$$;

-- my_profile ahora tambien dice a que negocio pertenece la persona y si esta activo.
drop function if exists public.my_profile();
create function public.my_profile()
returns table(id uuid, name text, role text, negocio_id uuid, negocio_nombre text, negocio_codigo text, negocio_activo boolean)
language sql stable security definer set search_path = public
as $$
  select a.id, a.name, a.role, n.id, n.nombre, n.codigo,
         (n.estado = 'activo' and (n.vence_el is null or n.vence_el >= (now() at time zone 'America/Caracas')::date))
    from public.app_users a
    join public.negocios n on n.id = a.negocio_id
   where a.active
     and lower(a.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
   limit 1;
$$;
revoke all on function public.my_profile() from public, anon;
grant execute on function public.my_profile() to authenticated, service_role;

-- Pantalla de entrada por negocio: lista el personal SOLO del negocio cuyo codigo se escribe.
-- (Reemplazara a la vista public_staff, que hoy lista a todos; se cerrara cuando la app nueva este instalada.)
create or replace function public.personal_del_negocio(p_codigo text)
returns table(id uuid, name text, email text, role text, negocio_nombre text)
language sql stable security definer set search_path = public
as $$
  select a.id, a.name, a.email, a.role, n.nombre
    from public.app_users a
    join public.negocios n on n.id = a.negocio_id
   where n.codigo = lower(trim(p_codigo))
     and n.estado = 'activo'
     and a.active and coalesce(a.email, '') <> ''
   order by a.name;
$$;
revoke all on function public.personal_del_negocio(text) from public;
grant execute on function public.personal_del_negocio(text) to anon, authenticated;

-- Aviso de comanda nueva: ahora lleva el negocio, para avisar solo a sus telefonos.
create or replace function private.notify_new_ticket()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.status = 'nueva' then
    perform net.http_post(
      url := 'https://tmjejukvdcfifajnmlca.supabase.co/functions/v1/notify-comanda',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-webhook-secret', (select value from private.app_secrets where name = 'webhook_notify')),
      body := jsonb_build_object('number', new.number, 'table', new.table_number, 'takeaway', new.takeaway_name,
                                 'adicion', new.adicion, 'negocio_id', new.negocio_id)
    );
  end if;
  return new;
exception when others then
  return new;  -- un fallo del aviso nunca debe impedir guardar la comanda
end;
$$;

-- ---------------------------------------------------------------- alta de un negocio nuevo
-- Crea el negocio con su configuracion, categorias base, mesas y su administrador (sin acceso todavia:
-- el acceso con correo y PIN lo crea la funcion en la nube). Solo para el dueno de la plataforma.
create or replace function private.crear_negocio(p_nombre text, p_codigo text, p_admin_nombre text, p_admin_correo text, p_mesas int default 6)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare v_id uuid;
begin
  insert into public.negocios (nombre, codigo) values (p_nombre, lower(trim(p_codigo))) returning id into v_id;
  insert into public.app_config (id, negocio_id, business_name, rate)
    values (1, v_id, p_nombre, coalesce((select rate from public.app_config order by updated_at desc nulls last limit 1), 36.5));
  insert into public.categories (negocio_id, key, label, emoji, position, protected) values
    (v_id, 'comidas', 'Comidas', '🍔', 10, true),
    (v_id, 'bebidas', 'Bebidas', '🥤', 20, true),
    (v_id, 'combos', 'Combos', '🍱', 30, true),
    (v_id, 'otros', 'Otros', '🍽️', 40, true);
  insert into public.dining_tables (negocio_id, number, capacity)
    select v_id, g, 4 from generate_series(1, greatest(coalesce(p_mesas, 0), 0)) g;
  insert into public.app_users (negocio_id, name, pin, role, active, email)
    values (v_id, p_admin_nombre, '', 'admin', true, lower(trim(p_admin_correo)));
  insert into private.contadores (negocio_id, nombre, valor) values (v_id, 'comanda', 0);
  return v_id;
end;
$$;
revoke all on function private.crear_negocio(text, text, text, text, int) from public, anon, authenticated;

commit;

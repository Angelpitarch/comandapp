-- 0019: tasa del dia automatica con la tasa oficial del BCV. Seguro de repetir.
--
-- La funcion tasa-bcv lee www.bcv.org.ve cada hora y guarda la tasa con su "fecha valor".
-- La tasa vigente de un dia es la ultima publicada con fecha valor igual o anterior a ese dia
-- (el BCV publica en la tarde la tasa del dia habil siguiente: se aplica al llegar ese dia).
-- Cada negocio elige: automatica (por defecto) o manual. Si el administrador escribe una tasa a mano,
-- ese negocio pasa a manual hasta que vuelva a activar la automatica.

-- Historial de tasas oficiales (es informacion publica, igual para todos los negocios).
create table if not exists public.tasas_bcv (
  fecha_valor date primary key,
  usd numeric not null check (usd > 0),
  eur numeric check (eur is null or eur > 0),
  obtenida timestamptz not null default now()
);
alter table public.tasas_bcv enable row level security;
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'tasas_bcv' and policyname = 'tasas_bcv_select') then
    create policy tasas_bcv_select on public.tasas_bcv for select to authenticated using (true);
  end if;
end $$;
revoke all on public.tasas_bcv from anon, authenticated;
grant select on public.tasas_bcv to authenticated;

-- Como se maneja la tasa en cada negocio.
alter table public.app_config add column if not exists tasa_auto boolean not null default true;
alter table public.app_config add column if not exists tasa_fecha date;          -- fecha valor de la tasa en uso (si viene del BCV)
alter table public.app_config add column if not exists tasa_origen text not null default 'manual'
  check (tasa_origen in ('bcv', 'manual'));

-- Hoy en Venezuela.
create or replace function private.hoy_venezuela()
returns date language sql stable set search_path = ''
as $$ select (now() at time zone 'America/Caracas')::date; $$;

-- Si el administrador cambia la tasa a mano, ese negocio queda en "manual".
-- (Cuando la cambia el sistema con la del BCV, se marca la sesion y no se toca.)
create or replace function private.tasa_cambio_manual()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if new.rate is distinct from old.rate and coalesce(current_setting('comandapp.tasa_bcv', true), '') <> '1' then
    new.tasa_auto := false;
    new.tasa_origen := 'manual';
    new.tasa_fecha := null;
  end if;
  return new;
end;
$$;
drop trigger if exists app_config_tasa_manual on public.app_config;
create trigger app_config_tasa_manual before update of rate on public.app_config
  for each row execute function private.tasa_cambio_manual();

-- Pone la tasa vigente del BCV en los negocios con tasa automatica (o solo en uno). Devuelve cuantos cambiaron.
create or replace function private.aplicar_tasa_bcv(p_negocio uuid default null)
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  t record;
  n int;
begin
  select b.fecha_valor, b.usd into t from public.tasas_bcv b
   where b.fecha_valor <= private.hoy_venezuela() order by b.fecha_valor desc limit 1;
  if not found then
    return 0;
  end if;
  perform set_config('comandapp.tasa_bcv', '1', true);
  update public.app_config c
     set rate = t.usd, tasa_fecha = t.fecha_valor, tasa_origen = 'bcv', updated_at = now()
   where c.tasa_auto and (p_negocio is null or c.negocio_id = p_negocio)
     and (c.rate is distinct from t.usd or c.tasa_fecha is distinct from t.fecha_valor or c.tasa_origen <> 'bcv');
  get diagnostics n = row_count;
  perform set_config('comandapp.tasa_bcv', '', true);
  return n;
end;
$$;
revoke all on function private.aplicar_tasa_bcv(uuid) from public;

-- Lo llama la funcion tasa-bcv (servidor). Revisa que la tasa tenga sentido, la guarda y la aplica.
create or replace function public.guardar_tasa_bcv(p_fecha date, p_usd numeric, p_eur numeric default null)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_ant numeric;
  v_n int;
begin
  if p_fecha is null or p_usd is null or p_usd <= 0 then
    raise exception 'Tasa invalida' using errcode = '22023';
  end if;
  if p_fecha > private.hoy_venezuela() + 10 or p_fecha < private.hoy_venezuela() - 30 then
    raise exception 'Fecha valor fuera de rango: %', p_fecha using errcode = '22023';
  end if;
  -- proteccion contra una lectura mala de la pagina: no se aceptan saltos de mas de 40% contra la ultima tasa
  select b.usd into v_ant from public.tasas_bcv b where b.fecha_valor < p_fecha order by b.fecha_valor desc limit 1;
  if v_ant is not null and (p_usd > v_ant * 1.4 or p_usd < v_ant * 0.6) then
    raise exception 'La tasa leida (%) es muy distinta a la anterior (%): no se aplica', p_usd, v_ant using errcode = '22023';
  end if;
  insert into public.tasas_bcv (fecha_valor, usd, eur) values (p_fecha, p_usd, p_eur)
  on conflict (fecha_valor) do update set usd = excluded.usd, eur = excluded.eur, obtenida = now();
  v_n := private.aplicar_tasa_bcv(null);
  return jsonb_build_object('fecha_valor', p_fecha, 'usd', p_usd, 'eur', p_eur, 'negocios_actualizados', v_n);
end;
$$;
revoke all on function public.guardar_tasa_bcv(date, numeric, numeric) from public, anon, authenticated;
grant execute on function public.guardar_tasa_bcv(date, numeric, numeric) to service_role;

-- Para el administrador: activar o apagar la tasa automatica de su negocio.
-- Al activarla se pone de una vez la tasa vigente del BCV.
create or replace function public.usar_tasa_bcv(p_activar boolean)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_neg uuid := private.negocio_actual();
  c record;
begin
  if not coalesce(private.is_admin(), false) or v_neg is null then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  update public.app_config set tasa_auto = coalesce(p_activar, true) where negocio_id = v_neg;
  if coalesce(p_activar, true) then
    perform private.aplicar_tasa_bcv(v_neg);
  end if;
  select a.rate, a.tasa_auto, a.tasa_fecha, a.tasa_origen into c from public.app_config a where a.negocio_id = v_neg;
  return jsonb_build_object('rate', c.rate, 'tasa_auto', c.tasa_auto, 'tasa_fecha', c.tasa_fecha, 'tasa_origen', c.tasa_origen);
end;
$$;
revoke all on function public.usar_tasa_bcv(boolean) from public, anon;
grant execute on function public.usar_tasa_bcv(boolean) to authenticated;

-- 0014: rendimiento y una sola llamada para descontar inventario. Seguro de repetir.
-- (Sin instrucciones que borren nada: solo crea o ajusta.)

-- 1) app_users: auth.jwt() se evalua una vez por consulta, no una vez por fila.
alter policy app_users_select on public.app_users
  using ((select private.is_admin()) or lower(email) = lower(coalesce((select auth.jwt()) ->> 'email', '')));

-- 2) Descontar insumos de un negocio (uso interno: lo llaman descontar_insumos y enviar_comanda).
--    p_items = [{"id": "<ingrediente>", "qty": 1.5}, ...]; dos lineas del mismo insumo se suman.
create or replace function private.descontar_insumos_de(p_neg uuid, p_items jsonb)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    return;
  end if;
  if jsonb_array_length(p_items) > 500 then
    raise exception 'Lista de insumos invalida' using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_array_elements(p_items) e
              where (e ->> 'id') is null or (e ->> 'qty') is null or (e ->> 'qty')::numeric < 0) then
    raise exception 'Cantidad invalida' using errcode = '22023';
  end if;
  update public.ingredients i
     set stock = i.stock - x.qty, updated_at = now()
    from (select (e ->> 'id')::uuid as id, sum((e ->> 'qty')::numeric) as qty
            from jsonb_array_elements(p_items) e group by 1) x
   where i.id = x.id and i.negocio_id = p_neg;
end;
$$;
revoke all on function private.descontar_insumos_de(uuid, jsonb) from public;

-- 3) Descontar todos los insumos de una comanda en UNA llamada (antes era una llamada por ingrediente).
create or replace function public.descontar_insumos(p_items jsonb)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_neg uuid := private.negocio_actual();
begin
  if coalesce(private.staff_role(), '') not in ('admin', 'mesero') or v_neg is null then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' then
    raise exception 'Lista de insumos invalida' using errcode = '22023';
  end if;
  perform private.descontar_insumos_de(v_neg, p_items);
end;
$$;
revoke all on function public.descontar_insumos(jsonb) from public, anon;
grant execute on function public.descontar_insumos(jsonb) to authenticated;

-- 4) Para las funciones del servidor: encontrar el acceso de un correo sin recorrer todos los usuarios.
--    Solo la puede usar el servidor (service_role), nunca la app ni el panel.
create or replace function public.auth_id_de_correo(p_correo text)
returns uuid
language sql stable security definer set search_path = ''
as $$
  select id from auth.users where lower(email) = lower(p_correo) limit 1;
$$;
revoke all on function public.auth_id_de_correo(text) from public, anon, authenticated;
grant execute on function public.auth_id_de_correo(text) to service_role;

-- 5) Los correos se guardan siempre en minusculas (asi se pueden buscar con una comparacion exacta).
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'app_users_email_minusculas') then
    alter table public.app_users add constraint app_users_email_minusculas check (email is null or email = lower(email));
  end if;
end $$;

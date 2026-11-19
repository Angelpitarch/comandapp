-- 0014: rendimiento y una sola llamada para descontar inventario. Seguro de repetir.

-- 1) app_users: auth.jwt() se evalua una vez por consulta, no una vez por fila.
drop policy if exists app_users_select on public.app_users;
create policy app_users_select on public.app_users for select to authenticated
  using ((select private.is_admin()) or lower(email) = lower(coalesce((select auth.jwt()) ->> 'email', '')));

-- 2) Una sola politica permisiva por accion. Antes "_write" (para todo) se sumaba a "_select"
--    en cada lectura; ahora escribir queda en tres politicas separadas, solo para el administrador.
do $$
declare t text;
begin
  foreach t in array array['app_config', 'categories', 'ingredients', 'products'] loop
    execute format('drop policy if exists %I on public.%I', t || '_write', t);
    execute format('drop policy if exists %I on public.%I', t || '_insert', t);
    execute format('drop policy if exists %I on public.%I', t || '_update', t);
    execute format('drop policy if exists %I on public.%I', t || '_delete', t);
    execute format('create policy %I on public.%I for insert to authenticated with check ((select private.is_admin()))', t || '_insert', t);
    execute format('create policy %I on public.%I for update to authenticated using ((select private.is_admin())) with check ((select private.is_admin()))', t || '_update', t);
    execute format('create policy %I on public.%I for delete to authenticated using ((select private.is_admin()))', t || '_delete', t);
  end loop;
end $$;

-- 3) Descontar todos los insumos de una comanda en UNA llamada (antes era una llamada por ingrediente,
--    lo que hacia esperar al mesero varios segundos con mala senal).
--    p_items = [{"id": "<ingrediente>", "qty": 1.5}, ...]
create or replace function public.descontar_insumos(p_items jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_neg uuid := private.negocio_actual();
begin
  if coalesce(private.staff_role(), '') not in ('admin', 'mesero') or v_neg is null then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) > 500 then
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
   where i.id = x.id and i.negocio_id = v_neg;
end;
$$;
revoke all on function public.descontar_insumos(jsonb) from public, anon;
grant execute on function public.descontar_insumos(jsonb) to authenticated;

-- 4) Para la funcion admin-usuarios: encontrar el acceso de un correo sin recorrer todos los usuarios.
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
update public.app_users set email = lower(email) where email <> lower(email);
alter table public.app_users drop constraint if exists app_users_email_minusculas;
alter table public.app_users add constraint app_users_email_minusculas check (email is null or email = lower(email));

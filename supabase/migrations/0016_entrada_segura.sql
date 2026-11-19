-- 0016: entrada protegida contra quien intente adivinar un PIN, y sin mostrar correos. Seguro de repetir.
-- (Sin instrucciones que borren nada.)
--
-- Antes: la pantalla de entrada recibia el correo de cada persona y el telefono probaba el PIN directo
-- contra Supabase, sin limite propio. Ahora:
--   * personal_para_entrar(codigo) da nombre y rol, SIN correo.
--   * entrar_con_pin(usuario, pin) comprueba el PIN en el servidor y solo si es correcto devuelve el correo
--     con el que el telefono abre la sesion. Tras 5 fallos seguidos desde el mismo equipo ese usuario queda
--     bloqueado 5 minutos (10 fallos: 30 minutos; 15 o mas: 2 horas). Con 30 fallos en una hora desde
--     cualquier lugar, el usuario queda bloqueado 30 minutos.
--   * entrar_con_correo(correo, pin) hace lo mismo para el panel web.

create table if not exists private.intentos_entrada (
  clave text primary key,                 -- 'u:<usuario>|<ip>' o 'u:<usuario>'
  fallos int not null default 0,
  bloqueado_hasta timestamptz,
  actualizado timestamptz not null default now()
);

-- IP del equipo que llama (la pasa el servidor de Supabase); '?' si no se sabe.
create or replace function private.ip_cliente()
returns text
language sql stable set search_path = ''
as $$
  select coalesce(
    nullif(current_setting('request.headers', true)::json ->> 'cf-connecting-ip', ''),
    nullif(trim(split_part(current_setting('request.headers', true)::json ->> 'x-forwarded-for', ',', 1)), ''),
    nullif(current_setting('request.headers', true)::json ->> 'x-real-ip', ''),
    '?');
$$;

-- Comprueba un PIN de una persona con bloqueo por intentos. Devuelve:
--   {"ok": true, "correo": "..."}                          PIN correcto
--   {"ok": false, "motivo": "pin", "restantes": 3}          PIN incorrecto
--   {"ok": false, "motivo": "bloqueado", "espera_min": 5}   demasiados intentos
create or replace function private.comprobar_pin(p_usuario uuid, p_pin text)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_correo text;
  v_hash text;
  v_local text := 'u:' || coalesce(p_usuario::text, '?') || '|' || private.ip_cliente();
  v_global text := 'u:' || coalesce(p_usuario::text, '?');
  v_hasta timestamptz;
  v_fallos int;
begin
  -- bloqueado?
  select max(i.bloqueado_hasta) into v_hasta from private.intentos_entrada i
   where i.clave in (v_local, v_global) and i.bloqueado_hasta > now();
  if v_hasta is not null then
    return jsonb_build_object('ok', false, 'motivo', 'bloqueado', 'espera_min', greatest(1, ceil(extract(epoch from v_hasta - now()) / 60)::int));
  end if;

  select a.email, u.encrypted_password into v_correo, v_hash
    from public.app_users a
    join auth.users u on lower(u.email) = a.email
   where a.id = p_usuario and a.active and coalesce(a.email, '') <> '';

  if v_hash is not null and coalesce(p_pin, '') ~ '^[0-9]{4,6}$'
     and v_hash = extensions.crypt(p_pin || '-comandas', v_hash) then
    update private.intentos_entrada i set fallos = 0, bloqueado_hasta = null, actualizado = now()
     where i.clave in (v_local, v_global);
    return jsonb_build_object('ok', true, 'correo', v_correo);
  end if;

  -- fallo: se cuenta en este equipo y en total (los contadores viejos de mas de 1 hora vuelven a cero)
  insert into private.intentos_entrada as i (clave, fallos, actualizado) values (v_local, 1, now())
  on conflict (clave) do update
    set fallos = case when i.actualizado < now() - interval '1 hour' and coalesce(i.bloqueado_hasta, now()) <= now() then 1 else i.fallos + 1 end,
        actualizado = now()
  returning fallos into v_fallos;
  if v_fallos >= 5 and v_fallos % 5 = 0 then
    update private.intentos_entrada i
       set bloqueado_hasta = now() + case when v_fallos >= 15 then interval '2 hours' when v_fallos >= 10 then interval '30 minutes' else interval '5 minutes' end
     where i.clave = v_local;
  end if;
  insert into private.intentos_entrada as i (clave, fallos, actualizado) values (v_global, 1, now())
  on conflict (clave) do update
    set fallos = case when i.actualizado < now() - interval '1 hour' and coalesce(i.bloqueado_hasta, now()) <= now() then 1 else i.fallos + 1 end,
        actualizado = now(),
        bloqueado_hasta = case when i.fallos + 1 >= 30 then now() + interval '30 minutes' else i.bloqueado_hasta end;

  select max(i.bloqueado_hasta) into v_hasta from private.intentos_entrada i
   where i.clave in (v_local, v_global) and i.bloqueado_hasta > now();
  if v_hasta is not null then
    return jsonb_build_object('ok', false, 'motivo', 'bloqueado', 'espera_min', greatest(1, ceil(extract(epoch from v_hasta - now()) / 60)::int));
  end if;
  return jsonb_build_object('ok', false, 'motivo', 'pin', 'restantes', 5 - (v_fallos % 5));
end;
$$;
revoke all on function private.comprobar_pin(uuid, text) from public;

-- Para la app: persona elegida en la lista + PIN.
create or replace function public.entrar_con_pin(p_usuario uuid, p_pin text)
returns jsonb
language sql security definer set search_path = ''
as $$
  select private.comprobar_pin(p_usuario, p_pin);
$$;
revoke all on function public.entrar_con_pin(uuid, text) from public;
grant execute on function public.entrar_con_pin(uuid, text) to anon, authenticated;

-- Para el panel web: correo + PIN.
create or replace function public.entrar_con_correo(p_correo text, p_pin text)
returns jsonb
language sql security definer set search_path = ''
as $$
  select private.comprobar_pin(
    (select a.id from public.app_users a where a.email = lower(trim(coalesce(p_correo, ''))) limit 1), p_pin);
$$;
revoke all on function public.entrar_con_correo(text, text) from public;
grant execute on function public.entrar_con_correo(text, text) to anon, authenticated;

-- Lista para la pantalla de entrada: nombre y rol, sin correo.
create or replace function public.personal_para_entrar(p_codigo text)
returns table(id uuid, name text, role text, negocio_nombre text)
language sql stable security definer set search_path = ''
as $$
  select a.id, a.name, a.role, n.nombre
    from public.app_users a
    join public.negocios n on n.id = a.negocio_id
   where private.codigo_compacto(n.codigo) = private.codigo_compacto(p_codigo)
     and private.codigo_compacto(p_codigo) <> ''
     and n.estado = 'activo'
     and a.active and coalesce(a.email, '') <> ''
   order by a.name;
$$;
revoke all on function public.personal_para_entrar(text) from public;
grant execute on function public.personal_para_entrar(text) to anon, authenticated;

-- La lista vieja (con correos) deja de estar disponible para la app y el panel.
revoke execute on function public.personal_del_negocio(text) from anon, authenticated;

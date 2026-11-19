-- Prueba de la entrada segura (0016). Todo ocurre dentro de un bloque que al final lanza
-- "PRUEBA_TERMINADA", asi que NO deja cambios. Si algo falla, el mensaje empieza con "FALLO".
do $t$
declare
  mesero_a text := (select email from public.app_users where role = 'mesero' and active order by created_at limit 1);
  admin_a text := (select email from public.app_users where role = 'admin' and active order by created_at limit 1);
  id_mesero uuid; codigo text; r jsonb; n int; total int := 0; i int;
begin
  id_mesero := (select id from public.app_users where email = mesero_a);
  codigo := (select n.codigo from public.negocios n join public.app_users a on a.negocio_id = n.id where a.email = mesero_a);
  update auth.users set encrypted_password = extensions.crypt('482915-comandas', extensions.gen_salt('bf')) where lower(email) in (mesero_a, admin_a);
  delete from private.intentos_entrada;

  -- ================= sin sesion, desde el equipo 1.1.1.1 =================
  perform set_config('request.headers', '{"x-forwarded-for": "1.1.1.1, 10.0.0.1"}', true);
  perform set_config('request.jwt.claims', '{"role": "anon"}', true);
  execute 'set local role anon';

  select count(*) into n from public.personal_para_entrar(upper(codigo));
  if n < 2 then raise exception 'FALLO 1: la lista de entrada trae % personas', n; end if; total := total + 1;
  begin
    perform * from public.personal_del_negocio(codigo);
    raise exception 'FALLO 2: la lista vieja con correos sigue abierta';
  exception when insufficient_privilege then null; end; total := total + 1;

  r := public.entrar_con_pin(id_mesero, '482915');
  if not (r ->> 'ok')::boolean or r ->> 'correo' <> mesero_a then raise exception 'FALLO 3: PIN correcto rechazado: %', r; end if; total := total + 1;

  r := public.entrar_con_pin(id_mesero, '111222');
  if (r ->> 'ok')::boolean or r ->> 'correo' is not null or (r ->> 'restantes')::int <> 4 then raise exception 'FALLO 4: PIN malo: %', r; end if; total := total + 1;
  for i in 1..3 loop r := public.entrar_con_pin(id_mesero, '111222'); end loop;
  if (r ->> 'restantes')::int <> 1 then raise exception 'FALLO 5: tras 4 fallos quedan % intentos', r ->> 'restantes'; end if; total := total + 1;
  r := public.entrar_con_pin(id_mesero, '111222');
  if r ->> 'motivo' <> 'bloqueado' then raise exception 'FALLO 6: al 5o fallo no se bloqueo: %', r; end if; total := total + 1;
  r := public.entrar_con_pin(id_mesero, '482915');
  if (r ->> 'ok')::boolean or r ->> 'motivo' <> 'bloqueado' or r ? 'correo' then raise exception 'FALLO 7: bloqueado pero entro: %', r; end if; total := total + 1;

  -- desde OTRO equipo (el telefono del negocio) la persona puede seguir entrando
  perform set_config('request.headers', '{"x-forwarded-for": "2.2.2.2"}', true);
  r := public.entrar_con_pin(id_mesero, '482915');
  if not (r ->> 'ok')::boolean then raise exception 'FALLO 8: el bloqueo de un equipo afecto a otro: %', r; end if; total := total + 1;

  -- usuario inexistente o PIN con letras: siempre "pin", nunca correo
  r := public.entrar_con_pin(gen_random_uuid(), '482915');
  if (r ->> 'ok')::boolean or r ? 'correo' then raise exception 'FALLO 9: usuario inexistente: %', r; end if; total := total + 1;
  r := public.entrar_con_pin(id_mesero, 'abc');
  if (r ->> 'ok')::boolean then raise exception 'FALLO 10: PIN invalido aceptado'; end if; total := total + 1;

  -- panel: correo + PIN (con mayusculas y espacios)
  r := public.entrar_con_correo('  ' || upper(admin_a) || ' ', '482915');
  if not (r ->> 'ok')::boolean then raise exception 'FALLO 11: el panel no deja entrar al administrador: %', r; end if; total := total + 1;
  r := public.entrar_con_correo('nadie@ejemplo.test', '482915');
  if (r ->> 'ok')::boolean then raise exception 'FALLO 12: entro un correo que no existe'; end if; total := total + 1;
  execute 'reset role';

  -- tope global: 30 fallos en una hora (desde varios equipos) bloquea a la persona en todas partes
  execute 'set local role anon';
  for i in 1..30 loop
    perform set_config('request.headers', json_build_object('x-forwarded-for', '9.9.9.' || i)::text, true);
    r := public.entrar_con_pin(id_mesero, '999888');
  end loop;
  perform set_config('request.headers', '{"x-forwarded-for": "3.3.3.3"}', true);
  r := public.entrar_con_pin(id_mesero, '482915');
  if r ->> 'motivo' <> 'bloqueado' then raise exception 'FALLO 13: 30 fallos desde varios equipos no bloquearon: %', r; end if; total := total + 1;
  execute 'reset role';

  raise exception 'PRUEBA_TERMINADA: OK, % verificaciones', total;
end $t$;

-- Prueba de la tasa automatica del BCV (0019). No deja cambios (termina con "PRUEBA_TERMINADA").
do $t$
declare
  admin_a text := (select email from public.app_users where role = 'admin' and active order by created_at limit 1);
  mesero_a text := (select email from public.app_users where role = 'mesero' and active order by created_at limit 1);
  a uuid; hoy date := (now() at time zone 'America/Caracas')::date; r jsonb; v numeric; txt text; b boolean; total int := 0;
begin
  a := (select negocio_id from public.app_users where email = admin_a);
  delete from public.tasas_bcv;
  update public.app_config set tasa_auto = true where negocio_id = a;

  -- el servidor guarda la tasa de hoy: el negocio automatico la toma
  r := public.guardar_tasa_bcv(hoy, 900.5, 1000);
  select rate, tasa_origen, tasa_fecha into v, txt from public.app_config where negocio_id = a;
  if v <> 900.5 or txt <> 'bcv' then raise exception 'FALLO 1: la tasa quedo % (%)', v, txt; end if; total := total + 1;

  -- tasa publicada para manana: todavia no se aplica
  r := public.guardar_tasa_bcv(hoy + 1, 910);
  select rate into v from public.app_config where negocio_id = a;
  if v <> 900.5 then raise exception 'FALLO 2: se aplico antes de su fecha valor (%)', v; end if; total := total + 1;

  -- lectura mala (salto enorme): rechazada
  begin
    perform public.guardar_tasa_bcv(hoy + 2, 5000);
    raise exception 'FALLO 3: se acepto una tasa absurda';
  exception when invalid_parameter_value then null; end; total := total + 1;

  -- el administrador escribe una tasa a mano: pasa a manual y el BCV ya no la cambia
  perform set_config('request.jwt.claims', json_build_object('email', admin_a, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  update public.app_config set rate = 950 where negocio_id = a;
  if not found then raise exception 'FALLO 4a: el administrador no pudo cambiar la tasa'; end if;
  execute 'reset role';
  select tasa_auto, tasa_origen into b, txt from public.app_config where negocio_id = a;
  if b or txt <> 'manual' then raise exception 'FALLO 4: tras escribirla a mano quedo auto=% origen=%', b, txt; end if; total := total + 1;
  r := public.guardar_tasa_bcv(hoy, 901);
  select rate into v from public.app_config where negocio_id = a;
  if v <> 950 then raise exception 'FALLO 5: el BCV piso la tasa manual (%)', v; end if; total := total + 1;

  -- vuelve a activar la automatica: toma la vigente de una vez
  perform set_config('request.jwt.claims', json_build_object('email', admin_a, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  r := public.usar_tasa_bcv(true);
  if (r ->> 'rate')::numeric <> 901 or not (r ->> 'tasa_auto')::boolean then raise exception 'FALLO 6: al activar quedo %', r; end if; total := total + 1;
  begin
    perform public.guardar_tasa_bcv(hoy, 1);
    raise exception 'FALLO 7: un administrador pudo escribir la tasa oficial';
  exception when insufficient_privilege then null; end; total := total + 1;
  execute 'reset role';

  -- un mesero no puede cambiar el modo
  perform set_config('request.jwt.claims', json_build_object('email', mesero_a, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    perform public.usar_tasa_bcv(false);
    raise exception 'FALLO 8: un mesero cambio el modo de la tasa';
  exception when insufficient_privilege then null; end; total := total + 1;
  -- el historial de tasas se puede leer con sesion
  if (select count(*) from public.tasas_bcv) < 2 then raise exception 'FALLO 9: el historial no se ve'; end if; total := total + 1;
  execute 'reset role';

  raise exception 'PRUEBA_TERMINADA: OK, % verificaciones', total;
end $t$;

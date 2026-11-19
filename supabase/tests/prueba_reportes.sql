-- Prueba de reporte_periodo (0017). No deja cambios (termina con "PRUEBA_TERMINADA").
do $t$
declare
  admin_a text := (select email from public.app_users where role = 'admin' and active order by created_at limit 1);
  mesero_a text := (select email from public.app_users where role = 'mesero' and active order by created_at limit 1);
  a uuid; r jsonb; total int := 0; desde timestamptz := '2031-03-01 00:00-04'; hasta timestamptz := '2031-04-01 00:00-04';
begin
  a := (select negocio_id from public.app_users where email = admin_a);
  -- 1500 ventas en marzo 2031 (mas de las 1000 que guarda la app) + una fuera del periodo + otra de otro negocio
  insert into public.sales (negocio_id, at, total_usd, lines, payments)
  select a, desde + (i || ' minutes')::interval * 20, 2,
         jsonb_build_array(jsonb_build_object('name', 'Arepa', 'qty', 1, 'lineUsd', 2)),
         jsonb_build_array(jsonb_build_object('method', case when i % 2 = 0 then 'Efectivo USD' else 'Pago movil' end, 'amountUsd', 2))
    from generate_series(1, 1500) i;
  insert into public.sales (negocio_id, at, total_usd, lines, payments) values (a, hasta + interval '1 minute', 999, '[]', '[]');
  insert into public.gastos (negocio_id, concept, amount_usd, at) values (a, 'Harina', 30, '2031-03-02 10:00-04');

  perform set_config('request.jwt.claims', json_build_object('email', admin_a, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  r := public.reporte_periodo(desde, hasta);
  if (r ->> 'cuentas')::int <> 1500 then raise exception 'FALLO 1: cuentas = %', r ->> 'cuentas'; end if; total := total + 1;
  if (r ->> 'ventas')::numeric <> 3000 then raise exception 'FALLO 2: ventas = %', r ->> 'ventas'; end if; total := total + 1;
  if (r ->> 'gastos')::numeric <> 30 then raise exception 'FALLO 3: gastos = %', r ->> 'gastos'; end if; total := total + 1;
  if (r -> 'por_metodo' ->> 'Efectivo USD')::numeric <> 1500 then raise exception 'FALLO 4: por metodo = %', r -> 'por_metodo'; end if; total := total + 1;
  if (r -> 'unidades' ->> 'Arepa')::numeric <> 1500 then raise exception 'FALLO 5: unidades = %', r -> 'unidades'; end if; total := total + 1;
  if (r -> 'por_dia' -> 0 ->> 'dia') <> '2031-03-21' then raise exception 'FALLO 6: el dia mas reciente es %', r -> 'por_dia' -> 0 ->> 'dia'; end if; total := total + 1;
  begin
    perform public.reporte_periodo(hasta, desde);
    raise exception 'FALLO 7: periodo al reves aceptado';
  exception when invalid_parameter_value then null; end; total := total + 1;
  execute 'reset role';

  perform set_config('request.jwt.claims', json_build_object('email', mesero_a, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    perform public.reporte_periodo(desde, hasta);
    raise exception 'FALLO 8: un mesero vio el reporte';
  exception when insufficient_privilege then null; end; total := total + 1;
  execute 'reset role';

  raise exception 'PRUEBA_TERMINADA: OK, % verificaciones', total;
end $t$;

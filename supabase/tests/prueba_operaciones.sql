-- Prueba de enviar_comanda y cobrar (0015). Todo ocurre dentro de un bloque que al final lanza
-- "PRUEBA_TERMINADA", asi que NO deja cambios. Si algo falla, el mensaje empieza con "FALLO".
do $t$
declare
  mesero_a text := (select email from public.app_users where role = 'mesero' and active order by created_at limit 1);
  cocina_a text := (select email from public.app_users where role = 'cocina' and active order by created_at limit 1);
  a uuid; ing uuid; c1 uuid := gen_random_uuid(); c2 uuid := gen_random_uuid(); v1 uuid := gen_random_uuid();
  n1 int; n2 int; n int; v numeric; txt text; total int := 0; llevar uuid; nombre_mesero text;
begin
  a := (select negocio_id from public.app_users where email = mesero_a);
  nombre_mesero := (select name from public.app_users where email = mesero_a);
  insert into public.ingredients (negocio_id, name, stock) values (a, 'Harina prueba op', 100) returning id into ing;
  delete from public.account_items where negocio_id = a and table_number = 1;
  delete from public.tickets where negocio_id = a and table_number = 1;
  update public.dining_tables set status = 'disponible', waiter = null, opened_at = null where negocio_id = a and number = 1;

  -- ================= como MESERO =================
  perform set_config('request.jwt.claims', json_build_object('email', mesero_a, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';

  n1 := public.enviar_comanda(jsonb_build_object(
    'id', c1, 'mesa', 1, 'mesero', 'Nombre falso',
    'lineas', jsonb_build_array(jsonb_build_object('name', 'Arepa', 'qty', 2)),
    'cuenta', jsonb_build_array(jsonb_build_object('product_name', 'Arepa', 'qty', 2, 'unit_usd', 3.5),
                                jsonb_build_object('product_name', 'Jugo', 'qty', 1, 'unit_usd', 2)),
    'insumos', jsonb_build_array(jsonb_build_object('id', ing, 'qty', 4))));
  select count(*) into n from public.account_items where ticket_id = c1;
  if n <> 2 then raise exception 'FALLO 1: la cuenta tiene % lineas', n; end if; total := total + 1;
  select status into txt from public.dining_tables where number = 1;
  if txt <> 'ocupada' then raise exception 'FALLO 2: la mesa quedo %', txt; end if; total := total + 1;
  select waiter into txt from public.tickets where id = c1;
  if txt is distinct from nombre_mesero then raise exception 'FALLO 3: la comanda dice mesero "%"', txt; end if; total := total + 1;

  -- reintento con el mismo id: mismo numero, nada duplicado
  n2 := public.enviar_comanda(jsonb_build_object('id', c1, 'mesa', 1,
    'lineas', jsonb_build_array(jsonb_build_object('name', 'Arepa', 'qty', 2)),
    'cuenta', jsonb_build_array(jsonb_build_object('product_name', 'Arepa', 'qty', 2, 'unit_usd', 3.5)),
    'insumos', jsonb_build_array(jsonb_build_object('id', ing, 'qty', 4))));
  select count(*) into n from public.account_items where table_number = 1;
  if n2 <> n1 or n <> 2 then raise exception 'FALLO 4: el reintento duplico (numero % / %, lineas %)', n1, n2, n; end if; total := total + 1;

  -- adicion: mismo numero, marcada como adicion
  n2 := public.enviar_comanda(jsonb_build_object('id', c2, 'mesa', 1, 'numero', n1,
    'lineas', jsonb_build_array(jsonb_build_object('name', 'Malta', 'qty', 1)),
    'cuenta', jsonb_build_array(jsonb_build_object('product_name', 'Malta', 'qty', 1, 'unit_usd', 1.5))));
  if n2 <> n1 or not (select adicion from public.tickets where id = c2) then raise exception 'FALLO 5: la adicion no reuso el numero'; end if; total := total + 1;

  -- datos malos: no se guarda NADA (ni la comanda)
  begin
    perform public.enviar_comanda(jsonb_build_object('id', gen_random_uuid(), 'mesa', 1,
      'lineas', jsonb_build_array(jsonb_build_object('name', 'X', 'qty', 1)),
      'cuenta', jsonb_build_array(jsonb_build_object('product_name', 'X', 'qty', 0, 'unit_usd', 1))));
    raise exception 'FALLO 6: se acepto cantidad 0';
  exception when invalid_parameter_value then null; end; total := total + 1;
  begin
    perform public.enviar_comanda(jsonb_build_object('id', gen_random_uuid(), 'mesa', 999,
      'lineas', jsonb_build_array(jsonb_build_object('name', 'X', 'qty', 1)),
      'cuenta', jsonb_build_array(jsonb_build_object('product_name', 'X', 'qty', 1, 'unit_usd', 1))));
    raise exception 'FALLO 7: se acepto una mesa que no existe';
  exception when invalid_parameter_value then null; end; total := total + 1;
  select count(*) into n from public.tickets where table_number = 1;
  if n <> 2 then raise exception 'FALLO 8: quedaron % comandas de la mesa 1 (se esperaban 2)', n; end if; total := total + 1;

  -- cobrar: el total lo pone el servidor (2x3.5 + 2 + 1.5 = 10.5) y la mesa queda pagada
  perform public.cobrar(jsonb_build_object('id', v1, 'mesa', 1,
    'pagos', jsonb_build_array(jsonb_build_object('method', 'Efectivo USD', 'amountUsd', 10.5))));
  execute 'reset role';
  select total_usd into v from public.sales where id = v1;
  if v <> 10.5 then raise exception 'FALLO 9: la venta quedo en %', v; end if; total := total + 1;
  select status into txt from public.dining_tables where negocio_id = a and number = 1;
  if txt <> 'pago_espera' then raise exception 'FALLO 10: la mesa cobrada quedo %', txt; end if; total := total + 1;
  select stock into v from public.ingredients where id = ing;
  if v <> 96 then raise exception 'FALLO 11: el inventario quedo en % (se esperaba 96)', v; end if; total := total + 1;

  perform set_config('request.jwt.claims', json_build_object('email', mesero_a, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  -- reintento del cobro: no duplica; otro cobro de la misma mesa: rechazado
  perform public.cobrar(jsonb_build_object('id', v1, 'mesa', 1,
    'pagos', jsonb_build_array(jsonb_build_object('method', 'Efectivo USD', 'amountUsd', 10.5))));
  begin
    perform public.cobrar(jsonb_build_object('id', gen_random_uuid(), 'mesa', 1,
      'pagos', jsonb_build_array(jsonb_build_object('method', 'Efectivo USD', 'amountUsd', 10.5))));
    raise exception 'FALLO 12: se cobro dos veces la misma mesa';
  exception when invalid_parameter_value then null; end; total := total + 1;

  -- para llevar: se cobra una sola vez y queda pagado
  insert into public.takeaways (name) values ('Cliente prueba') returning id into llevar;
  perform public.enviar_comanda(jsonb_build_object('id', gen_random_uuid(), 'llevar_id', llevar, 'llevar_nombre', 'Cliente prueba',
    'lineas', jsonb_build_array(jsonb_build_object('name', 'Arepa', 'qty', 1)),
    'cuenta', jsonb_build_array(jsonb_build_object('product_name', 'Arepa', 'qty', 1, 'unit_usd', 4))));
  perform public.cobrar(jsonb_build_object('id', gen_random_uuid(), 'llevar_id', llevar,
    'pagos', jsonb_build_array(jsonb_build_object('method', 'Pago movil', 'amountUsd', 4))));
  begin
    perform public.cobrar(jsonb_build_object('id', gen_random_uuid(), 'llevar_id', llevar,
      'pagos', jsonb_build_array(jsonb_build_object('method', 'Pago movil', 'amountUsd', 4))));
    raise exception 'FALLO 13: se cobro dos veces el pedido para llevar';
  exception when invalid_parameter_value then null; end; total := total + 1;
  select status into txt from public.takeaways where id = llevar;
  if txt <> 'pagada' then raise exception 'FALLO 14: el pedido para llevar quedo %', txt; end if; total := total + 1;

  -- venta directa sin productos: rechazada
  begin
    perform public.cobrar(jsonb_build_object('id', gen_random_uuid(),
      'pagos', jsonb_build_array(jsonb_build_object('method', 'Efectivo USD', 'amountUsd', 1))));
    raise exception 'FALLO 15: venta directa sin productos';
  exception when invalid_parameter_value then null; end; total := total + 1;
  execute 'reset role';

  -- ================= como COCINA: no puede enviar ni cobrar =================
  perform set_config('request.jwt.claims', json_build_object('email', cocina_a, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    perform public.enviar_comanda(jsonb_build_object('id', gen_random_uuid(), 'mesa', 2,
      'lineas', jsonb_build_array(jsonb_build_object('name', 'X', 'qty', 1))));
    raise exception 'FALLO 16: cocina envio una comanda';
  exception when insufficient_privilege then null; end; total := total + 1;
  begin
    perform public.cobrar(jsonb_build_object('id', gen_random_uuid(), 'mesa', 2,
      'pagos', jsonb_build_array(jsonb_build_object('method', 'Efectivo USD', 'amountUsd', 1))));
    raise exception 'FALLO 17: cocina cobro';
  exception when insufficient_privilege then null; end; total := total + 1;
  execute 'reset role';

  -- ================= sin sesion: nada =================
  execute 'set local role anon';
  begin
    perform public.cobrar('{}'::jsonb);
    raise exception 'FALLO 18: sin sesion se pudo llamar a cobrar';
  exception when insufficient_privilege then null; end; total := total + 1;
  execute 'reset role';

  raise exception 'PRUEBA_TERMINADA: OK, % verificaciones (comanda %)', total, n1;
end $t$;

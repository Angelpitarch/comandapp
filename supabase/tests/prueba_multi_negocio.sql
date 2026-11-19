-- Prueba de aislamiento entre negocios (0011). Se puede correr en la copia local o en Supabase:
-- todo ocurre dentro de un bloque que al final lanza "PRUEBA_TERMINADA", asi que NO deja cambios.
-- Si algo falla, el mensaje empieza con "FALLO".
do $t$
declare
  a uuid; b uuid; n int; n2 int; v numeric; txt text; num_a int; num_b int; total int := 0;
  admin_a text := (select email from public.app_users where role = 'admin' and active order by created_at limit 1);
  mesero_a text := (select email from public.app_users where role = 'mesero' and active order by created_at limit 1);
  cocina_a text := (select email from public.app_users where role = 'cocina' and active order by created_at limit 1);
  antes jsonb;
  id_mesero_b uuid; id_harina_b uuid;
  despues jsonb;
begin
  a := (select negocio_id from public.app_users where email = admin_a);
  -- conteos del negocio A antes de la prueba
  select jsonb_build_object('products', (select count(*) from public.products where negocio_id = a),
                            'sales', (select count(*) from public.sales where negocio_id = a),
                            'ingredients', (select count(*) from public.ingredients where negocio_id = a),
                            'gastos', (select count(*) from public.gastos where negocio_id = a)) into antes;

  -- ---------- negocio B de prueba ----------
  b := private.crear_negocio('Arepera Prueba', 'arepera-prueba-zz', 'Admin B', 'admin-b@prueba.test', 3);
  insert into public.app_users (negocio_id, name, pin, role, email) values (b, 'Mesero B', '', 'mesero', 'mesero-b@prueba.test');
  insert into public.products (negocio_id, name, price, category) values (b, 'Arepa reina', 3, 'comidas');
  insert into public.ingredients (negocio_id, name, stock) values (b, 'Harina B', 10);
  insert into public.sales (negocio_id, total_usd) values (b, 99);
  id_mesero_b := (select id from public.app_users where email = 'mesero-b@prueba.test');
  id_harina_b := (select id from public.ingredients where name = 'Harina B' and negocio_id = b limit 1);

  -- ================= como ADMIN del negocio A =================
  perform set_config('request.jwt.claims', json_build_object('email', admin_a, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';

  select count(*) into n from public.products where name = 'Arepa reina';
  if n <> 0 then raise exception 'FALLO 1: A ve productos de B'; end if; total := total + 1;
  select count(*) into n from public.sales where total_usd = 99;
  if n <> 0 then raise exception 'FALLO 2: A ve ventas de B'; end if; total := total + 1;
  select count(*) into n from public.negocios;
  if n <> 1 then raise exception 'FALLO 3: A ve % negocios', n; end if; total := total + 1;
  select count(*) into n from public.app_config;
  if n <> 1 then raise exception 'FALLO 4: A ve % filas de configuracion', n; end if; total := total + 1;

  -- la app actual actualiza la tasa con id = 1: solo debe cambiar la de A
  update public.app_config set rate = 801 where id = 1;
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'FALLO 5: actualizar tasa cambio % filas', n; end if; total := total + 1;

  -- insertar sin negocio_id: queda en A
  insert into public.products (name, price, category) values ('Producto nuevo A', 5, 'perros');
  select count(*) into n from public.products where name = 'Producto nuevo A';
  if n <> 1 then raise exception 'FALLO 6: no se ve el producto recien creado'; end if; total := total + 1;

  -- intentar meter datos en B: debe rechazarse
  begin
    insert into public.products (negocio_id, name, price) values (b, 'Intruso', 1);
    raise exception 'FALLO 7: A pudo insertar en B';
  exception when insufficient_privilege then null; end; total := total + 1;

  -- intentar cambiar productos de B: no afecta nada
  update public.products set price = 0 where name = 'Arepa reina';
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FALLO 8: A cambio productos de B'; end if; total := total + 1;

  -- funciones: no deben tocar B
  perform public.deduct_ingredient(id_harina_b, 5);
  begin
    perform public.save_user(id_mesero_b, 'Hackeado', '', 'admin', true);
    raise exception 'FALLO 9: A edito un usuario de B';
  exception when no_data_found then null; end; total := total + 1;

  -- datos del negocio: puede cambiar el nombre, no el plan
  update public.negocios set telefono = '0414-0000000';
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'FALLO 10: el admin no pudo editar su negocio'; end if; total := total + 1;
  begin
    update public.negocios set plan = 'pro';
    raise exception 'FALLO 11: el admin cambio su plan';
  exception when insufficient_privilege then null; end; total := total + 1;

  -- categoria con una clave que B tambien tiene: permitido
  insert into public.categories (key, label) values ('comidas', 'Comidas A');
  total := total + 1;

  -- el perfil dice su negocio
  select negocio_codigo into txt from public.my_profile();
  if txt is distinct from (select codigo from public.negocios where id = a) then raise exception 'FALLO 12: my_profile sin negocio'; end if; total := total + 1;
  execute 'reset role';

  -- ================= como MESERO del negocio A =================
  perform set_config('request.jwt.claims', json_build_object('email', mesero_a, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  insert into public.tickets (table_number, waiter, status, lines) values (1, 'Mesero', 'nueva', '[]') returning number into num_a;
  update public.dining_tables set status = 'ocupada' where number = 1;
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'FALLO 13: la mesa 1 de A cambio % filas', n; end if; total := total + 1;
  update public.negocios set nombre = 'X';
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FALLO 14: un mesero edito el negocio'; end if; total := total + 1;
  select count(*) into n from public.sales;
  if n <> 0 then raise exception 'FALLO 15: el mesero ve ventas'; end if; total := total + 1;
  execute 'reset role';

  -- ================= como MESERO del negocio B =================
  perform set_config('request.jwt.claims', json_build_object('email', 'mesero-b@prueba.test', 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  insert into public.tickets (table_number, waiter, status, lines) values (1, 'Mesero B', 'nueva', '[]') returning number into num_b;
  if num_b <> 1 then raise exception 'FALLO 16: la primera comanda de B es la %', num_b; end if; total := total + 1;
  select count(*) into n from public.tickets;
  if n <> 1 then raise exception 'FALLO 17: B ve % comandas', n; end if; total := total + 1;
  select count(*) into n from public.dining_tables where status = 'ocupada';
  if n <> 0 then raise exception 'FALLO 18: B ve mesas ocupadas de A'; end if; total := total + 1;
  select count(*) into n from public.products;
  if n <> 1 then raise exception 'FALLO 19: B ve % productos', n; end if; total := total + 1;
  execute 'reset role';

  -- ================= como COCINA del negocio A =================
  perform set_config('request.jwt.claims', json_build_object('email', cocina_a, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.tickets where number = num_b and table_number = 1 and waiter = 'Mesero B';
  if n <> 0 then raise exception 'FALLO 20: cocina A ve comandas de B'; end if; total := total + 1;
  perform public.register_device('token-de-prueba-cocina-a-0000000000000001');
  begin
    update public.tickets set lines = '[{"x":1}]' where number = num_a;
    raise exception 'FALLO 21: cocina cambio el contenido de una comanda';
  exception when insufficient_privilege then null; end; total := total + 1;
  execute 'reset role';

  -- ================= verificaciones como dueno de la base =================
  if num_a <= 1 then raise exception 'FALLO 22: la numeracion de A se reinicio (%)', num_a; end if; total := total + 1;
  select rate into v from public.app_config where negocio_id = b;
  if v = 801 then raise exception 'FALLO 23: la tasa de A cambio la de B'; end if; total := total + 1;
  select stock into v from public.ingredients where name = 'Harina B' and negocio_id = b;
  if v <> 10 then raise exception 'FALLO 24: A desconto inventario de B'; end if; total := total + 1;
  select status into txt from public.dining_tables where negocio_id = b and number = 1;
  if txt <> 'disponible' then raise exception 'FALLO 25: la mesa 1 de B cambio'; end if; total := total + 1;
  select negocio_id::text into txt from public.device_tokens where token = 'token-de-prueba-cocina-a-0000000000000001';
  if txt is distinct from a::text then raise exception 'FALLO 26: el telefono no quedo en su negocio'; end if; total := total + 1;
  select count(*) into n from public.personal_del_negocio('arepera-prueba-zz');
  select count(*) into n2 from public.personal_del_negocio(' ARepera-PRUEBA-zz ');
  if n <> 2 or n2 <> 2 then raise exception 'FALLO 27: personal de B = % / %', n, n2; end if; total := total + 1;
  if exists (select 1 from public.personal_del_negocio('arepera-prueba-zz') where email = admin_a) then raise exception 'FALLO 28: el personal de B incluye gente de A'; end if; total := total + 1;
  if (select nombre from public.negocios where id = a) is null then raise exception 'FALLO 29'; end if; total := total + 1;

  -- negocio suspendido: no ve nada y su perfil lo dice
  update public.negocios set estado = 'suspendido' where id = b;
  perform set_config('request.jwt.claims', json_build_object('email', 'mesero-b@prueba.test', 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.products;
  if n <> 0 then raise exception 'FALLO 30: un negocio suspendido ve datos'; end if; total := total + 1;
  if (select negocio_activo from public.my_profile()) then raise exception 'FALLO 31: el perfil no dice suspendido'; end if; total := total + 1;
  execute 'reset role';
  -- negocio vencido: igual
  update public.negocios set estado = 'activo', vence_el = current_date - 2 where id = b;
  perform set_config('request.jwt.claims', json_build_object('email', 'mesero-b@prueba.test', 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.products;
  if n <> 0 then raise exception 'FALLO 32: un negocio vencido ve datos'; end if; total := total + 1;
  execute 'reset role';

  -- los datos de A siguen intactos (mas lo creado en la prueba)
  select jsonb_build_object('products', (select count(*) from public.products where negocio_id = a) - 1,
                            'sales', (select count(*) from public.sales where negocio_id = a),
                            'ingredients', (select count(*) from public.ingredients where negocio_id = a),
                            'gastos', (select count(*) from public.gastos where negocio_id = a)) into despues;
  if antes <> despues then raise exception 'FALLO 33: cambiaron los datos de A: % -> %', antes, despues; end if; total := total + 1;

  raise exception 'PRUEBA_TERMINADA: OK, % verificaciones (comanda A=%, primera de B=%)', total, num_a, num_b;
end $t$;

-- Datos INVENTADOS con la misma forma que produccion (ningun correo ni PIN real) (un solo negocio, como antes de 0011).
insert into public.app_config (id, rate, business_name, motiv_shown) values (1, 746.63, 'Puesto de Comida', true);
insert into auth.users (id, email, encrypted_password) values
  ('11111111-1111-1111-1111-111111111111', 'admin@ejemplo.test', extensions.crypt('000000-prueba', extensions.gen_salt('bf'))),
  ('22222222-2222-2222-2222-222222222222', 'mesero@ejemplo.test', extensions.crypt('000000-prueba', extensions.gen_salt('bf'))),
  ('33333333-3333-3333-3333-333333333333', 'cocina@ejemplo.test', extensions.crypt('000000-prueba', extensions.gen_salt('bf')));
insert into public.app_users (id, name, pin, role, email) values
  ('fe1458f2-a6b2-434c-b981-5fc73a6ced43', 'Administrador', '', 'admin', 'admin@ejemplo.test'),
  ('962598ee-a1e0-48a2-8a1f-1daceba41df1', 'Mesero', '', 'mesero', 'mesero@ejemplo.test'),
  ('faa4b428-3f5c-463e-b165-f13d9d083b9c', 'Cocinero', '', 'cocina', 'cocina@ejemplo.test');
insert into public.categories (key, label, emoji, position, protected) values
  ('hamburguesas', 'Hamburguesas', '🍔', 10, true), ('perros', 'Perros calientes', '🌭', 20, true), ('otros', 'Salchipapas', '🍟', 60, true);
insert into public.ingredients (id, name, unit, stock, min_stock, cost) values
  ('3cfbc335-34b3-46ea-9fc9-84e123c5e2bc', 'Pan de perro', 'unidad', 32, 10, 0.1),
  ('f6328009-4694-456b-88bf-7698bf500e20', 'Salchicha Plumrose', 'unidad', 80, 36, 0.04);
insert into public.products (id, name, emoji, category, price, recipe) values
  ('b828db84-66bc-4e8b-92e3-db1a7a8bc859', 'Perro Normal', '🌭', 'perros', 4,
   '[{"qty":1,"ingredient_id":"3cfbc335-34b3-46ea-9fc9-84e123c5e2bc"},{"qty":1,"ingredient_id":"f6328009-4694-456b-88bf-7698bf500e20"}]');
insert into public.dining_tables (number, capacity, status, waiter) values (1, 2, 'disponible', null), (2, 4, 'ocupada', 'Mesero'), (3, 2, 'disponible', null);
select setval('public.ticket_number_seq', 16);
insert into public.tickets (number, table_number, waiter, status, lines) values (16, 2, 'Mesero', 'entregada', '[{"qty":1,"name":"Perro Normal"}]');
insert into public.account_items (table_number, product_name, qty, unit_usd) values (2, 'Perro Normal', 1, 4);
insert into public.sales (table_number, total_usd, lines, payments) values (9, 8, '[{"qty":2,"name":"Perro Normal","lineUsd":8}]', '[{"method":"Pago movil","amountUsd":8}]');
insert into public.gastos (concept, category, amount_usd, by_user) values ('Pan de Perro', 'ingredientes', 13, 'Administrador');
insert into public.cancellations (ticket_number, table_number, merchandise_used, value_usd, by_user) values (5, 5, true, 39, 'Administrador');
insert into public.device_tokens (token, user_email, role) values ('token-de-prueba-del-telefono-de-cocina-0001', 'cocina@ejemplo.test', 'cocina');

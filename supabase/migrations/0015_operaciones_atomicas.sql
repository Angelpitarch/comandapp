-- 0015: enviar una comanda y cobrar, cada una en UNA sola operacion en el servidor. Seguro de repetir.
-- Antes la app hacia varios pasos sueltos: si la senal se cortaba a mitad, una comanda podia llegar a
-- cocina sin quedar en la cuenta, o una mesa cobrada podia quedar como "ocupada" y cobrarse otra vez.
-- Ahora todo pasa junto o no pasa nada, y reintentar con el mismo id no duplica.
-- Requiere 0014 (private.descontar_insumos_de).

-- Nombre de quien tiene la sesion (para que la comanda y la venta digan quien fue, sin confiar en la app).
create or replace function private.mi_nombre()
returns text
language sql stable security definer set search_path = ''
as $$
  select a.name from public.app_users a
   where a.email = lower(coalesce(auth.jwt() ->> 'email', '')) and a.negocio_id = private.negocio_actual()
   limit 1;
$$;

-- p = {
--   "id": "<uuid creado en el telefono>",       (obligatorio: reintentar con el mismo id no duplica)
--   "numero": 18 | null,                         (numero de la comanda anterior si es adicion)
--   "mesa": 3 | null, "llevar_id": "<uuid>" | null, "llevar_nombre": "Maria" | null, "nota": "..." | null,
--   "lineas": [ {name, qty, size, extras, quita, note} ],                       (lo que ve cocina)
--   "cuenta": [ {product_name, qty, size, extras, quita, note, unit_usd} ],     (lo que se cobra)
--   "insumos": [ {id, qty} ]                                                    (inventario a descontar)
-- }
-- Devuelve el numero de la comanda.
create or replace function public.enviar_comanda(p jsonb)
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  v_neg uuid := private.negocio_actual();
  v_id uuid;
  v_mesa int;
  v_llevar uuid;
  v_num int;
  v_mesero text;
  v_res int;
begin
  if coalesce(private.staff_role(), '') not in ('admin', 'mesero') or v_neg is null then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  v_id := (p ->> 'id')::uuid;
  v_mesa := (p ->> 'mesa')::int;
  v_llevar := (p ->> 'llevar_id')::uuid;
  v_num := (p ->> 'numero')::int;
  if v_id is null then
    raise exception 'Falta el id de la comanda' using errcode = '22023';
  end if;
  if jsonb_typeof(p -> 'lineas') is distinct from 'array' or jsonb_array_length(p -> 'lineas') = 0 then
    raise exception 'La comanda no tiene productos' using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_array_elements(coalesce(p -> 'cuenta', '[]'::jsonb)) c
              where coalesce((c ->> 'qty')::int, 0) <= 0 or coalesce((c ->> 'unit_usd')::numeric, 0) < 0
                 or coalesce(c ->> 'product_name', '') = '') then
    raise exception 'Hay un producto con cantidad o precio invalido' using errcode = '22023';
  end if;

  -- reintento: si ya se guardo, se devuelve el mismo numero
  select t.number into v_res from public.tickets t where t.id = v_id and t.negocio_id = v_neg;
  if found then
    return v_res;
  end if;

  if v_mesa is not null and not exists (select 1 from public.dining_tables d where d.negocio_id = v_neg and d.number = v_mesa) then
    raise exception 'La mesa % no existe', v_mesa using errcode = '22023';
  end if;
  if v_llevar is not null and not exists (select 1 from public.takeaways w where w.negocio_id = v_neg and w.id = v_llevar) then
    raise exception 'El pedido para llevar no existe' using errcode = '22023';
  end if;

  v_mesero := coalesce(private.mi_nombre(), nullif(p ->> 'mesero', ''), '');

  insert into public.tickets (id, negocio_id, number, table_number, takeaway_id, takeaway_name, waiter, status, adicion, note, lines)
  values (v_id, v_neg, v_num, v_mesa, v_llevar, nullif(p ->> 'llevar_nombre', ''), v_mesero, 'nueva', v_num is not null,
          nullif(p ->> 'nota', ''), p -> 'lineas')
  returning number into v_res;

  if v_mesa is not null or v_llevar is not null then
    insert into public.account_items (negocio_id, table_number, takeaway_id, ticket_id, product_name, qty, size, extras, quita, note, unit_usd)
    select v_neg, v_mesa, v_llevar, v_id, c ->> 'product_name', (c ->> 'qty')::int, nullif(c ->> 'size', ''),
           coalesce(c -> 'extras', '[]'::jsonb), coalesce(c -> 'quita', '[]'::jsonb), nullif(c ->> 'note', ''),
           coalesce((c ->> 'unit_usd')::numeric, 0)
      from jsonb_array_elements(coalesce(p -> 'cuenta', '[]'::jsonb)) c;
  end if;

  if v_mesa is not null then
    update public.dining_tables d
       set status = 'ocupada', waiter = v_mesero,
           opened_at = case when d.status = 'disponible' or d.opened_at is null then now() else d.opened_at end
     where d.negocio_id = v_neg and d.number = v_mesa;
  end if;

  perform private.descontar_insumos_de(v_neg, p -> 'insumos');
  return v_res;
end;
$$;
revoke all on function public.enviar_comanda(jsonb) from public, anon;
grant execute on function public.enviar_comanda(jsonb) to authenticated;

-- p = {
--   "id": "<uuid creado en el telefono>",       (obligatorio: reintentar con el mismo id no duplica)
--   "mesa": 3 | null, "llevar_id": "<uuid>" | null,
--   "pagos": [ {method, amountUsd, reference} ],
--   "lineas": [...], "total": 12.5               (solo en venta directa, sin mesa ni para llevar)
-- }
-- El total de una mesa o un pedido para llevar lo calcula el servidor con lo que hay en la cuenta.
-- La mesa queda "pagada - en espera" y el pedido para llevar "pagado" en la misma operacion.
create or replace function public.cobrar(p jsonb)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_neg uuid := private.negocio_actual();
  v_id uuid;
  v_mesa int;
  v_llevar uuid;
  v_lineas jsonb;
  v_total numeric;
  v_cliente text;
  v_estado text;
begin
  if coalesce(private.staff_role(), '') not in ('admin', 'mesero') or v_neg is null then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  v_id := (p ->> 'id')::uuid;
  v_mesa := (p ->> 'mesa')::int;
  v_llevar := (p ->> 'llevar_id')::uuid;
  if v_id is null then
    raise exception 'Falta el id del cobro' using errcode = '22023';
  end if;
  if jsonb_typeof(p -> 'pagos') is distinct from 'array' or jsonb_array_length(p -> 'pagos') = 0 then
    raise exception 'Faltan los pagos' using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_array_elements(p -> 'pagos') x
              where coalesce(x ->> 'method', '') = '' or coalesce((x ->> 'amountUsd')::numeric, -1) < 0) then
    raise exception 'Hay un pago invalido' using errcode = '22023';
  end if;

  -- reintento: si ya se guardo, no se cobra otra vez
  if exists (select 1 from public.sales s where s.id = v_id and s.negocio_id = v_neg) then
    return v_id;
  end if;

  if v_mesa is not null then
    select d.status into v_estado from public.dining_tables d where d.negocio_id = v_neg and d.number = v_mesa for update;
    if not found then
      raise exception 'La mesa % no existe', v_mesa using errcode = '22023';
    end if;
    if v_estado in ('pago_espera', 'pago_servido') then
      raise exception 'La mesa % ya fue cobrada', v_mesa using errcode = '22023';
    end if;
    select coalesce(jsonb_agg(jsonb_build_object('name', a.product_name, 'qty', a.qty, 'lineUsd', a.qty * a.unit_usd) order by a.created_at), '[]'::jsonb),
           coalesce(sum(a.qty * a.unit_usd), 0)
      into v_lineas, v_total
      from public.account_items a where a.negocio_id = v_neg and a.table_number = v_mesa;
    if jsonb_array_length(v_lineas) = 0 then
      raise exception 'La cuenta de la mesa % esta vacia', v_mesa using errcode = '22023';
    end if;
    update public.dining_tables d set status = 'pago_espera' where d.negocio_id = v_neg and d.number = v_mesa;
  elsif v_llevar is not null then
    select w.name, w.status into v_cliente, v_estado from public.takeaways w where w.negocio_id = v_neg and w.id = v_llevar for update;
    if not found then
      raise exception 'El pedido para llevar no existe' using errcode = '22023';
    end if;
    if v_estado = 'pagada' then
      raise exception 'Este pedido para llevar ya fue cobrado' using errcode = '22023';
    end if;
    select coalesce(jsonb_agg(jsonb_build_object('name', a.product_name, 'qty', a.qty, 'lineUsd', a.qty * a.unit_usd) order by a.created_at), '[]'::jsonb),
           coalesce(sum(a.qty * a.unit_usd), 0)
      into v_lineas, v_total
      from public.account_items a where a.negocio_id = v_neg and a.takeaway_id = v_llevar;
    if jsonb_array_length(v_lineas) = 0 then
      raise exception 'La cuenta de este pedido esta vacia' using errcode = '22023';
    end if;
    update public.takeaways w set status = 'pagada' where w.negocio_id = v_neg and w.id = v_llevar;
  else
    v_lineas := p -> 'lineas';
    v_total := (p ->> 'total')::numeric;
    if jsonb_typeof(v_lineas) is distinct from 'array' or jsonb_array_length(v_lineas) = 0 or v_total is null or v_total < 0 then
      raise exception 'Venta directa sin productos o sin total' using errcode = '22023';
    end if;
  end if;

  insert into public.sales (id, negocio_id, table_number, customer, total_usd, lines, payments)
  values (v_id, v_neg, v_mesa, v_cliente, v_total, v_lineas, p -> 'pagos');
  return v_id;
end;
$$;
revoke all on function public.cobrar(jsonb) from public, anon;
grant execute on function public.cobrar(jsonb) to authenticated;

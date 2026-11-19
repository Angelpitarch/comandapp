-- 0017: reportes calculados en el servidor. Seguro de repetir.
-- La app del telefono guarda solo las ventas mas recientes; los reportes por semana o por mes
-- ahora se calculan en la base con TODAS las ventas del periodo y llegan ya resumidos (pocos datos).

-- Devuelve:
-- { "ventas": 123.4, "cuentas": 40, "gastos": 20,
--   "por_metodo": {"Efectivo USD": 80, ...}, "unidades": {"Arepa reina": 25, ...},
--   "por_dia": [ {"dia": "2026-11-19", "ventas": 50, "gastos": 5}, ... ] }   (dias en hora de Venezuela)
create or replace function public.reporte_periodo(p_desde timestamptz, p_hasta timestamptz)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_neg uuid := private.negocio_actual();
  r jsonb;
begin
  if not coalesce(private.is_admin(), false) or v_neg is null then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_desde is null or p_hasta is null or p_hasta <= p_desde or p_hasta - p_desde > interval '400 days' then
    raise exception 'Periodo invalido' using errcode = '22023';
  end if;

  with v as (
    select s.at, s.total_usd, s.lines, s.payments from public.sales s
     where s.negocio_id = v_neg and s.at >= p_desde and s.at < p_hasta
  ), g as (
    select x.at, x.amount_usd from public.gastos x
     where x.negocio_id = v_neg and x.at >= p_desde and x.at < p_hasta
  )
  select jsonb_build_object(
    'ventas', coalesce((select sum(v.total_usd) from v), 0),
    'cuentas', (select count(*) from v),
    'gastos', coalesce((select sum(g.amount_usd) from g), 0),
    'por_metodo', coalesce((
        select jsonb_object_agg(m.metodo, m.total) from (
          select coalesce(nullif(p ->> 'method', ''), 'Otro') as metodo, sum(coalesce((p ->> 'amountUsd')::numeric, 0)) as total
            from v, jsonb_array_elements(coalesce(v.payments, '[]'::jsonb)) p group by 1) m), '{}'::jsonb),
    'unidades', coalesce((
        select jsonb_object_agg(u.nombre, u.cantidad) from (
          select coalesce(nullif(l ->> 'name', ''), '(sin nombre)') as nombre, sum(coalesce((l ->> 'qty')::numeric, 0)) as cantidad
            from v, jsonb_array_elements(coalesce(v.lines, '[]'::jsonb)) l group by 1) u), '{}'::jsonb),
    'por_dia', coalesce((
        select jsonb_agg(jsonb_build_object('dia', d.dia, 'ventas', d.ventas, 'gastos', d.gastos) order by d.dia desc) from (
          select z.dia, sum(z.ventas) as ventas, sum(z.gastos) as gastos from (
            select (v.at at time zone 'America/Caracas')::date as dia, v.total_usd as ventas, 0::numeric as gastos from v
            union all
            select (g.at at time zone 'America/Caracas')::date, 0::numeric, g.amount_usd from g) z
          group by z.dia) d), '[]'::jsonb)
  ) into r;
  return r;
end;
$$;
revoke all on function public.reporte_periodo(timestamptz, timestamptz) from public, anon;
grant execute on function public.reporte_periodo(timestamptz, timestamptz) to authenticated;

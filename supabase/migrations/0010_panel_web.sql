-- 0010: apoyo para el panel web de administracion.
-- admin_esquema(): lista tablas y columnas del esquema public (para la seccion "Base de datos").
-- Solo responde a administradores activos; para cualquier otro da error.

create or replace function public.admin_esquema()
returns table(tabla text, tipo text, columna text, tipo_dato text, nulo boolean,
              por_defecto text, es_pk boolean, posicion int, filas_aprox bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  return query
  select c.relname::text,
         case c.relkind when 'v' then 'vista' else 'tabla' end,
         a.attname::text,
         pg_catalog.format_type(a.atttypid, a.atttypmod),
         not a.attnotnull,
         pg_catalog.pg_get_expr(d.adbin, d.adrelid),
         exists (select 1 from pg_catalog.pg_index i
                  where i.indrelid = c.oid and i.indisprimary and a.attnum = any(i.indkey::int2[])),
         a.attnum::int,
         greatest(c.reltuples, 0)::bigint
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
    join pg_catalog.pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
    left join pg_catalog.pg_attrdef d on d.adrelid = c.oid and d.adnum = a.attnum
   where c.relkind in ('r', 'v')
   order by c.relname, a.attnum;
end;
$$;

revoke all on function public.admin_esquema() from public, anon;
grant execute on function public.admin_esquema() to authenticated;

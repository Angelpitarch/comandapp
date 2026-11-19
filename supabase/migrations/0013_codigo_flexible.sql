-- 0013: el codigo del negocio se reconoce aunque se escriba distinto.
-- "Puesto de Comida", "puesto de comida", "PUESTO-DE-COMIDA" y "puestodecomida" llevan al mismo negocio:
-- se ignoran mayusculas, tildes, espacios, guiones y otros signos. Seguro de repetir.

-- Forma compacta de un codigo: minusculas, sin tildes y solo letras y numeros.
create or replace function private.codigo_compacto(p text)
returns text
language sql immutable
set search_path = ''
as $$
  select regexp_replace(
           translate(lower(coalesce(p, '')), 'áàäâéèëêíìïîóòöôúùüûñç', 'aaaaeeeeiiiioooouuuunc'),
           '[^a-z0-9]', '', 'g');
$$;

-- Dos negocios no pueden tener codigos que solo se diferencien en los guiones.
create unique index if not exists negocios_codigo_compacto on public.negocios (private.codigo_compacto(codigo));

create or replace function public.personal_del_negocio(p_codigo text)
returns table(id uuid, name text, email text, role text, negocio_nombre text)
language sql stable security definer set search_path = public
as $$
  select a.id, a.name, a.email, a.role, n.nombre
    from public.app_users a
    join public.negocios n on n.id = a.negocio_id
   where private.codigo_compacto(n.codigo) = private.codigo_compacto(p_codigo)
     and private.codigo_compacto(p_codigo) <> ''
     and n.estado = 'activo'
     and a.active and coalesce(a.email, '') <> ''
   order by a.name;
$$;
revoke all on function public.personal_del_negocio(text) from public;
grant execute on function public.personal_del_negocio(text) to anon, authenticated;

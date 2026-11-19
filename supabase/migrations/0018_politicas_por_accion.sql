-- 0018: una sola politica permisiva por accion en app_config, categories, ingredients y products. Seguro de repetir.
-- Antes "_write" (para todo) se sumaba a "_select" en cada lectura; ahora escribir queda en tres politicas
-- separadas, solo para el administrador. Mismos permisos que antes, consultas mas rapidas.
do $$
declare t text;
begin
  foreach t in array array['app_config', 'categories', 'ingredients', 'products'] loop
    execute format('drop policy if exists %I on public.%I', t || '_write', t);
    execute format('drop policy if exists %I on public.%I', t || '_insert', t);
    execute format('drop policy if exists %I on public.%I', t || '_update', t);
    execute format('drop policy if exists %I on public.%I', t || '_delete', t);
    execute format('create policy %I on public.%I for insert to authenticated with check ((select private.is_admin()))', t || '_insert', t);
    execute format('create policy %I on public.%I for update to authenticated using ((select private.is_admin())) with check ((select private.is_admin()))', t || '_update', t);
    execute format('create policy %I on public.%I for delete to authenticated using ((select private.is_admin()))', t || '_delete', t);
  end loop;
end $$;

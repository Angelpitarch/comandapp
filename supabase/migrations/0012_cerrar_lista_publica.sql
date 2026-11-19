-- 0012: cierra la lista publica de personal.
-- La app ComandApp 1.0 entra con el codigo del negocio y usa personal_del_negocio(codigo),
-- que solo muestra el personal de ESE negocio. La vista public_staff listaba a todo el personal
-- de la plataforma sin sesion, asi que se elimina. Seguro de repetir.
drop view if exists public.public_staff;

-- Los negocios nuevos no deben ver el mensaje de bienvenida del negocio fundador.
alter table public.app_config alter column motiv_shown set default true;

<p align="center"><img src="assets/marca/logo-horizontal.png" alt="ComandApp" width="420"></p>

# ComandApp

Comandas, caja e inventario para restaurantes y negocios de comida: mesas, pedidos, cocina, cobro en
USD y Bs, inventario con recetas, caja, empleados, gastos y reportes. Varios negocios comparten la misma
plataforma, cada uno con sus datos aislados. Los datos viven en **Supabase** y se comparten en tiempo
real entre los telefonos, la tableta de cocina y el panel web.

## Entrar a la app

1. **Codigo del negocio** (solo la primera vez en cada telefono; queda guardado). Ejemplo: `mi-restaurante`.
2. **Quien eres**: aparece solo el personal activo de ese negocio.
3. **PIN de 6 numeros** con el teclado en pantalla.

El telefono queda **vinculado** a ese negocio: el personal no puede cambiarlo desde la entrada. Solo un
administrador, ya dentro de la app, puede usar "Desvincular este dispositivo del negocio" (Administrador, al final
de los ajustes). Si el negocio vinculado se suspende o deja de existir, la entrada lo avisa y ofrece vincular otro.

## Marca

- Logo, icono y piezas en `assets/marca/` (simbolo, texto, logo horizontal, icono y favicon).
- Colores: ambar `#FCAC0C`, negro `#111111`, verde `#549C1C`, rojo `#D43424` (sobre fondo claro, el
  ambar de texto es `#A05F00` para que se lea bien).
- Fuente: **Outfit** (licencia SIL Open Font License, `assets/fuentes/OFL.txt`).

## Roles

| Rol | Qué ve y qué puede hacer |
|---|---|
| **Mesero** | Solo atiende mesas y pedidos para llevar: toma pedidos, los envía a cocina, cobra y libera la mesa. No ve ventas, caja, gastos ni empleados. |
| **Cocina** | Solo ve las comandas y cambia su estado (nueva → preparando → lista). No puede anular ni modificar el contenido de una comanda (lo impide un disparador en la base de datos). |
| **Administrador** | Todo: usuarios y roles, menú, inventario, categorías, tasa, caja, anulaciones, empleados, gastos (se descuentan en Rentabilidad, cierre de caja y reportes), reportes por semana y mes e historial. También puede abrir las pantallas de Mesero y de Cocina. |

Esto se aplica **en la base de datos** (reglas RLS en `supabase/migrations/0002_seguridad_por_rol.sql`),
no solo en la pantalla: aunque alguien modifique la app, el servidor rechaza lo que su rol no permite.

## Poner en marcha la base de datos (una sola vez)

1. En Supabase abre **SQL Editor** y ejecuta, en orden, los archivos de `supabase/migrations/`:
   `0001_schema.sql`, `0002_seguridad_por_rol.sql`, `0003_datos_iniciales.sql`, `0004_cocina_solo_estado.sql`, `0005_cierre_con_gastos.sql`, `0006_avisos_push.sql`, `0007_disparador_avisos.sql`, `0008_pin_6_digitos.sql`, `0009_pines_obvios.sql`, `0010_panel_web.sql`, `0011_multi_negocio.sql`, `0012_cerrar_lista_publica.sql` y `0013_codigo_flexible.sql`.
   Son seguros de repetir: no borran datos.
2. Crea el primer administrador:
   - En **Authentication → Users → Add user** crea un usuario con su correo y la contraseña
     `<PIN de 6 números>-comandas` (tu PIN real de 6 números seguido de `-comandas`). Marca "Auto confirm".
   - En **SQL Editor** ejecuta (con tus datos):
     ```sql
     insert into public.app_users (name, pin, role, active, email)
     values ('Tu nombre', '', 'admin', true, 'tu-correo@ejemplo.com');
     ```
   El correo debe ser **exactamente el mismo** en Authentication y en `app_users`.
3. Entra al panel web (o a la app) con ese administrador y crea los demás usuarios desde **Usuarios**.
   Meseros y cocina **no necesitan correo**: se crean con nombre, rol y PIN, y el sistema les arma por dentro un
   acceso interno que nadie ve (termina en `.local`, un dominio que no existe en internet). El administrador sí usa
   un correo real, porque con él entra al panel web. Crear, dar acceso, cambiar el correo y eliminar usuarios pasa
   por la función `admin-usuarios`, tanto desde el panel como desde la app.
4. Ejecuta `supabase/tests/prueba_roles.sql` para comprobar los permisos de cada rol
   (no guarda nada; el resultado aparece dentro de un mensaje que empieza con `PRUEBA_TERMINADA`).

## Recomendaciones de seguridad (hazlas en el panel de Supabase)

- **Authentication → Sign In / Providers**: desactiva "Allow new users to sign up".
  Así nadie puede crearse una cuenta por su cuenta.
- **Authentication → Rate limits**: deja activos los límites de inicio de sesión.
- **Authentication → Password security**: activa "Leaked password protection" si tu plan lo permite.
- La pantalla de acceso lista el personal (nombre y correo) sin sesión. El PIN es de 6 números
  (un millón de combinaciones), pero quien conozca un correo aún puede intentar adivinarlo. La app y
  la base de datos (`0009_pines_obvios.sql`) rechazan PIN obvios: un solo número repetido (`000000`),
  escaleras (`123456`, `654321`), repeticiones (`121212`, `123123`), capicúas (`123321`) y parejas
  (`112233`). Aun así evita fechas de nacimiento, cámbialos si sospechas algo y mantén los límites
  de inicio de sesión activos. La regla solo aplica a PIN nuevos: los que ya existen siguen entrando.
- **PIN de 4 números (usuarios antiguos):** pueden entrar con el botón "Entrar con PIN de 4 números"
  y la app les exige crear uno de 6 antes de continuar. Si el administrador cambia el PIN de alguien
  desde **Usuarios**, también cambia su clave real de acceso. Antes de hacerlo, comprueba que el
  celular de esa persona ya tenga la versión con teclado de 6 números.
- Nunca subas al repositorio llaves `service_role`, contraseñas ni archivos `.env`.
  La llave `sb_publishable_...` que está en `lib/main.dart` sí es pública por diseño.

## Avisos con la app cerrada (Firebase)

Cocina y administrador reciben un aviso en el celular cuando entra una comanda nueva, aunque la app
este cerrada. Piezas: la app (registra el celular al iniciar sesion), la tabla `device_tokens`
(`0006_avisos_push.sql`), la funcion `supabase/functions/notify-comanda` y un disparador en la base de
datos que la llama. Secretos en Supabase (nunca en el repositorio): `WEBHOOK_SECRET` y
`FCM_SERVICE_ACCOUNT` (JSON de la cuenta de servicio de Firebase). Los datos de `kFirebaseOptions`
en `lib/main.dart` son publicos por diseno.

**Aviso emergente (ventana que aparece sobre lo que estes haciendo):** Android solo lo muestra si la
notificacion llega por un canal de importancia alta. La app lo crea al abrirse
(`android_extra/MainActivity.kt.tpl`, que el workflow copia al proyecto Android) y la funcion
`notify-comanda` envia cada aviso por el canal `comandas_nuevas` con sonido y vibracion. Como toca
codigo nativo, publicarlo exige un `release` nuevo (version mayor) e instalar el APK; no se puede
enviar como `patch`. Si el celular tiene las notificaciones de ComandApp silenciadas o el canal
"Comandas nuevas" en baja prioridad (Ajustes → Apps → ComandApp → Notificaciones), no aparecera la ventana.

## Varios negocios (0011)

ComandApp atiende a varios negocios en una sola base de datos. Cada fila tiene `negocio_id` y cada persona
solo ve y cambia los datos de su negocio (regla restrictiva por tabla, ademas de las reglas por rol).

- `public.negocios`: nombre, codigo para entrar, plan, estado (`activo` / `suspendido`) y `vence_el`.
  Un negocio suspendido o vencido no ve ningun dato. El admin del negocio puede editar nombre, RIF,
  telefono, direccion y logo, pero no el plan, el estado ni el vencimiento.
- La app actual sigue funcionando igual: `negocio_id` se llena solo, la tasa sigue en `app_config` con
  `id = 1` (una fila por negocio), las mesas se identifican por numero dentro del negocio y el numero de
  comanda es consecutivo por negocio (`private.contadores`).
- `private.crear_negocio(nombre, codigo, admin_nombre, admin_correo, mesas)` da de alta un negocio con su
  configuracion, categorias base, mesas y administrador (el acceso con correo y PIN lo crea `admin-usuarios`).
- `personal_del_negocio(codigo)`: lista el personal de UN negocio para la pantalla de entrada. La vista
  `public_staff`, que listaba a todo el personal sin sesion, se elimino en `0012_cerrar_lista_publica.sql`.
- Respaldo previo a 0011 dentro de la base: esquema `respaldo_20261119` (sin acceso desde la API).
- `0014_rendimiento.sql`: políticas más rápidas, `descontar_insumos(lista)` para descontar el inventario de una
  comanda en una sola llamada, `auth_id_de_correo` (solo para el servidor) y correos siempre en minúsculas.

### Probar migraciones en local

`supabase/tests/local/` tiene una copia fiel de la estructura de produccion (anterior a 0011) y una imitacion
minima de Supabase. Con un Postgres local:

```bash
supabase/tests/local/preparar.sh supabase/migrations/0011_multi_negocio.sql
psql -h /var/lib/postgresql/comandapp-test -p 54329 -U postgres -d comandapp_prueba -f supabase/tests/prueba_multi_negocio.sql
psql -h /var/lib/postgresql/comandapp-test -p 54329 -U postgres -d comandapp_prueba -f supabase/tests/prueba_roles.sql
```

Ambas pruebas terminan con `PRUEBA_TERMINADA` (a proposito, para no dejar cambios). `prueba_multi_negocio.sql`
tambien se puede correr en el SQL Editor de Supabase: crea un negocio de prueba, verifica 35 puntos de
aislamiento y lo deshace todo.

## Pagina web (panel de administracion)

Direccion: **https://angelpitarch.github.io/comandapp/**

- **Panel de administracion** (raiz de la pagina, carpeta `admin/`): solo para administradores. Se entra con
  correo y PIN. Tiene Resumen, Ventas, Reportes, Caja (con cierre de caja), Productos (receta, costo y margen),
  Categorias, Inventario, Gastos, Anulaciones, Usuarios, Trabajadores, Configuracion y **Base de datos**
  (explorar, filtrar, editar, insertar y borrar filas de las tablas de Postgres, respetando las reglas RLS).
  Es HTML y JavaScript sin librerias ni compilacion; habla directo con Supabase.
- **Donde trabaja cada quien:** meseros y cocina usan la app ComandApp en Android (telefono o tableta); la app ya no
  se publica para navegador. El dueno usa este panel en la computadora (o en el navegador del telefono) y tambien puede
  entrar a la app del telefono como administrador. Para la cocina se recomienda una tableta en la pared, o una cajita
  Android TV conectada a un monitor con un raton. En `/app/` queda un aviso que lleva al panel.
- Se publica sola con el workflow **Pagina web** cada vez que cambia `admin/` en `main`
  (o a mano desde Actions → Pagina web → Run workflow). Los celulares necesitan su `patch` o `release`.
- Activacion (una sola vez): Settings → Pages → Source: **GitHub Actions**.
- Piezas en Supabase que usa el panel: `supabase/migrations/0010_panel_web.sql` (funcion `admin_esquema`, solo
  admin) y la funcion en la nube `supabase/functions/admin-usuarios` (crear usuarios con su acceso real,
  dar acceso a usuarios viejos y eliminarlos). Esa funcion comprueba que quien llama es un administrador activo.
- En la web no hay avisos push. La sesion se guarda en el navegador: en una computadora compartida, cierra sesion al terminar.

## Compilar el APK

Desde GitHub → **Actions → Build APK → Run workflow**:
- `release`: primera vez o cambios grandes (genera el APK para instalar).
- `patch`: actualización por el aire (Shorebird), para cambios solo de código Dart.

**Si un `patch` falla con "native changes" (cambios nativos):** Shorebird se niega a publicar porque las
piezas nativas (Gradle) de la compilacion de hoy no son identicas a las del release instalado. Si desde
ese release solo cambio codigo Dart (`lib/`) y no se agregaron ni actualizaron plugins (compruebalo con
`git diff <commit-del-release> HEAD --stat`), vuelve a lanzar el `patch` marcando
**permitir_cambios_nativos**. Si cambiaste `pubspec.yaml`, haz un `release` nuevo con version mayor.

**Actualizaciones por el aire (patch) sin romperse:** un `patch` solo funciona si las librerías son
exactamente las mismas que las del `release` instalado. Por eso `pubspec.lock` está en el repositorio
y el flujo lo guarda solo después de cada `release`. Regla práctica: si cambias `pubspec.yaml`
(agregar o actualizar librerías) haz un `release` nuevo con un `version:` más alto; si solo cambias
código Dart, haz `patch`.

Secretos necesarios en GitHub (Settings → Secrets): `SHOREBIRD_TOKEN` y, para el respaldo diario,
`SUPABASE_DB_URL` y `BACKUP_PASSPHRASE`.

## Respaldo diario (cifrado)

El workflow **Backup DB** guarda cada noche una copia de la base de datos (tablas, funciones y accesos)
como archivo de Actions durante 30 días. Como el repositorio es público, la copia se **cifra** con
`BACKUP_PASSPHRASE`; sin esa clave el workflow se detiene en vez de subir los datos en claro.

- `SUPABASE_DB_URL`: la cadena **Session pooler** (Supabase → Connect). La conexión directa
  `db.<proyecto>.supabase.co` solo tiene IPv6 y GitHub no puede usarla.
- `BACKUP_PASSPHRASE`: una clave larga inventada, guardada fuera de GitHub.
- Abrir una copia: `gpg -d respaldo.tar.gz.gpg | tar -xz` y luego `pg_restore` sobre `comandapp.dump`.
- GitHub apaga los workflows programados si el repositorio pasa 60 días sin cambios: si se apaga,
  se vuelve a encender en Actions → Backup DB → Enable workflow.
- Con el plan Pro de Supabase hay además copias diarias automáticas del lado de Supabase.

## Estructura

```
lib/main.dart                         Arranque, llaves publicas de Supabase y Firebase, y la lista de partes
lib/src/store.dart                    Estado de la app conectado a Supabase (comandas, cobros, inventario)
lib/src/modelos.dart                  Modelos de datos
lib/src/tema.dart                     Tema visual, barra con la marca y pantalla raiz
lib/src/entrada.dart                  Entrada (codigo, personal, PIN) y cambiar PIN
lib/src/mesas.dart, pedido.dart, cobro.dart, cocina.dart           Operacion del salon y la cocina
lib/src/admin.dart, productos.dart, inventario.dart, personal.dart,
        gastos.dart, historial.dart, reportes.dart, formato.dart  Administracion
supabase/migrations/                  Esquema, seguridad por rol, datos iniciales candado de cocina y gastos en el cierre
supabase/tests/prueba_roles.sql       Prueba de permisos por rol
.github/workflows/build-apk.yml       Compilación del APK y parches Shorebird
.github/workflows/revisar.yml         Revisa el codigo (flutter analyze) y deja una vista previa web en la rama vista-previa
.github/workflows/web.yml             Publica el panel en GitHub Pages
admin/                                Panel web de administracion (HTML + JavaScript, sin compilar)
assets/marca, assets/fuentes          Logo, icono y fuente de ComandApp
.github/workflows/backup.yml          Respaldo diario de la base de datos
```

// Gestion de usuarios con acceso real (correo + PIN) desde el panel web.
// Solo la puede usar un administrador activo con su sesion abierta.
// Acciones (POST JSON):
//   { "accion": "crear",    "nombre", "correo", "pin", "rol", "activo" }
//   { "accion": "acceso",   "id", "correo", "pin" }     -> da acceso a un usuario que no lo tiene
//   { "accion": "eliminar", "id" }                       -> borra el usuario y su acceso
// La clave de acceso es "<PIN>-comandas", igual que en la app.
// Todo ocurre dentro del negocio del administrador que llama (ComandApp es para varios negocios).
import { createClient } from 'npm:@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

const ROLES = ['admin', 'mesero', 'cocina'];
const CORREO = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// Misma regla que private.pin_debil en la base de datos.
function pinDebil(p: string): boolean {
  if (/^(\d)\1{5}$/.test(p) || /^(\d\d)\1\1$/.test(p) || /^(\d\d\d)\1$/.test(p)) return true;
  if (/^(\d)(\d)(\d)\3\2\1$/.test(p) || /^(\d)\1(\d)\2(\d)\3$/.test(p)) return true;
  const esc = '0123456789012345678901234567890';
  return esc.includes(p) || esc.split('').reverse().join('').includes(p);
}
function revisarPin(pin: unknown): string | null {
  if (typeof pin !== 'string' || !/^[0-9]{6}$/.test(pin)) return 'El PIN debe ser de 6 numeros';
  if (pinDebil(pin)) return 'Ese PIN es muy facil de adivinar (como 123456 o 111111). Elige otro.';
  return null;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'Metodo no permitido' }, 405);

  const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // 1) Quien llama debe ser un administrador activo
  const jwt = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
  if (!jwt) return json({ error: 'Inicia sesion de nuevo' }, 401);
  const { data: quien, error: errQuien } = await admin.auth.getUser(jwt);
  const miCorreo = quien?.user?.email?.toLowerCase();
  if (errQuien || !miCorreo) return json({ error: 'Tu sesion expiro. Inicia sesion de nuevo.' }, 401);
  const { data: admins, error: errAdmins } = await admin.from('app_users')
    .select('id,email,negocio_id,negocios(estado,vence_el)').eq('role', 'admin').eq('active', true);
  if (errAdmins) return json({ error: 'No se pudo comprobar tu rol' }, 500);
  const yo = (admins ?? []).find((a) => (a.email ?? '').toLowerCase() === miCorreo);
  if (!yo) return json({ error: 'Solo un administrador puede gestionar usuarios' }, 403);
  // 2) Su negocio debe estar activo y al dia; todo lo que haga queda dentro de ese negocio
  const neg = Array.isArray(yo.negocios) ? yo.negocios[0] : yo.negocios;
  const hoy = new Date(Date.now() - 4 * 3600 * 1000).toISOString().slice(0, 10); // fecha en Venezuela
  if (!neg || neg.estado !== 'activo' || (neg.vence_el && neg.vence_el < hoy)) {
    return json({ error: 'Tu negocio no esta activo. Contacta a ComandApp.' }, 403);
  }
  const miNegocio: string = yo.negocio_id;

  const b = await req.json().catch(() => ({}));
  const accion = b.accion;

  async function correoLibre(correo: string, excepto?: string): Promise<boolean> {
    const { data } = await admin.from('app_users').select('id,email');
    return !(data ?? []).some((u) => (u.email ?? '').toLowerCase() === correo && u.id !== excepto);
  }
  async function idDeAcceso(correo: string): Promise<string | null> {
    for (let page = 1; page <= 20; page++) {
      const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 200 });
      if (error) return null;
      const u = data.users.find((x) => (x.email ?? '').toLowerCase() === correo);
      if (u) return u.id;
      if (data.users.length < 200) return null;
    }
    return null;
  }
  async function crearAcceso(correo: string, pin: string): Promise<{ id?: string; error?: string }> {
    const { data, error } = await admin.auth.admin.createUser({ email: correo, password: `${pin}-comandas`, email_confirm: true });
    if (error) {
      const yaExiste = /already|registered|exists/i.test(error.message);
      return { error: yaExiste ? 'Ese correo ya tiene un acceso creado en Supabase' : 'No se pudo crear el acceso: ' + error.message };
    }
    return { id: data.user.id };
  }

  if (accion === 'crear') {
    const nombre = String(b.nombre ?? '').trim();
    const correo = String(b.correo ?? '').trim().toLowerCase();
    const rol = String(b.rol ?? '');
    const activo = b.activo !== false;
    if (!nombre) return json({ error: 'Escribe el nombre' }, 400);
    if (!CORREO.test(correo)) return json({ error: 'Escribe un correo valido' }, 400);
    if (!ROLES.includes(rol)) return json({ error: 'Rol invalido' }, 400);
    const malPin = revisarPin(b.pin);
    if (malPin) return json({ error: malPin }, 400);
    if (!(await correoLibre(correo))) return json({ error: 'Ya hay un usuario con ese correo' }, 400);
    const acceso = await crearAcceso(correo, b.pin);
    if (acceso.error) return json({ error: acceso.error }, 400);
    const { data: fila, error } = await admin.from('app_users')
      .insert({ name: nombre, pin: '', role: rol, active: activo, email: correo, negocio_id: miNegocio }).select('id').single();
    if (error) {
      await admin.auth.admin.deleteUser(acceso.id!);
      return json({ error: 'No se pudo guardar el usuario: ' + error.message }, 500);
    }
    return json({ ok: true, id: fila.id });
  }

  if (accion === 'acceso') {
    const correo = String(b.correo ?? '').trim().toLowerCase();
    if (!CORREO.test(correo)) return json({ error: 'Escribe un correo valido' }, 400);
    const malPin = revisarPin(b.pin);
    if (malPin) return json({ error: malPin }, 400);
    const { data: u } = await admin.from('app_users').select('id,email').eq('id', b.id).eq('negocio_id', miNegocio).maybeSingle();
    if (!u) return json({ error: 'Usuario no encontrado' }, 404);
    if (u.email) return json({ error: 'Este usuario ya tiene correo de acceso' }, 400);
    if (!(await correoLibre(correo, u.id))) return json({ error: 'Ya hay un usuario con ese correo' }, 400);
    const acceso = await crearAcceso(correo, b.pin);
    if (acceso.error) return json({ error: acceso.error }, 400);
    const { error } = await admin.from('app_users').update({ email: correo }).eq('id', u.id);
    if (error) {
      await admin.auth.admin.deleteUser(acceso.id!);
      return json({ error: 'No se pudo guardar el correo: ' + error.message }, 500);
    }
    return json({ ok: true, id: u.id });
  }

  if (accion === 'eliminar') {
    if (b.id === yo.id) return json({ error: 'No puedes eliminar tu propio usuario' }, 400);
    const { data: u } = await admin.from('app_users').select('id,email').eq('id', b.id).eq('negocio_id', miNegocio).maybeSingle();
    if (!u) return json({ error: 'Usuario no encontrado' }, 404);
    const { error } = await admin.from('app_users').delete().eq('id', u.id).eq('negocio_id', miNegocio);
    if (error) return json({ error: 'No se pudo eliminar: ' + error.message }, 500);
    if (u.email) {
      const authId = await idDeAcceso(u.email.toLowerCase());
      if (authId) await admin.auth.admin.deleteUser(authId);
    }
    return json({ ok: true });
  }

  return json({ error: 'Accion desconocida' }, 400);
});

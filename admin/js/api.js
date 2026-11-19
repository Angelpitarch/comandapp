// Cliente minimo de Supabase (Auth + REST + funciones) usando fetch.
// No depende de librerias externas.
import { SUPABASE_URL as URL_BASE, SUPABASE_KEY as KEY } from './config.js';
import { storage } from './util.js';

const LS = 'comandas_admin_sesion';
let session = (() => { try { return JSON.parse(storage.get(LS) || 'null'); } catch { return null; } })();
const listeners = new Set();
export const onSessionLost = (fn) => listeners.add(fn);

function save(s) { session = s; storage.set(LS, s ? JSON.stringify(s) : null); }

export class ApiError extends Error {
  constructor(message, status = 0, body = null) { super(message); this.status = status; this.body = body; }
}

function mensaje(body, status) {
  const m = body && (body.message || body.error_description || body.msg || body.error);
  if (status === 0) return 'Sin conexión. Revisa tu internet e intenta de nuevo.';
  if (m === 'Invalid login credentials') return 'Correo o PIN incorrecto';
  if (body?.code === '42501' || /permission denied|row-level security|No autorizado/i.test(m || '')) return 'No tienes permiso para esta acción';
  if (body?.code === '23505') return 'Ya existe un registro con ese valor (duplicado)';
  if (body?.code === '23503') return 'No se puede: otros registros dependen de este';
  if (body?.code === '22P02') return 'Hay un valor con formato inválido';
  if (body?.code === '23502') return 'Falta un valor obligatorio';
  return m || `Error ${status}`;
}

async function fetchJson(url, opts) {
  let r;
  try { r = await fetch(url, opts); } catch { throw new ApiError(mensaje(null, 0), 0); }
  const text = await r.text();
  let body = null;
  if (text) { try { body = JSON.parse(text); } catch { body = { message: text }; } }
  if (!r.ok) throw new ApiError(mensaje(body, r.status), r.status, body);
  return { body, headers: r.headers, status: r.status };
}

// ---------- Auth ----------
function fromToken(j, email) {
  return {
    access_token: j.access_token,
    refresh_token: j.refresh_token,
    expires_at: Math.floor(Date.now() / 1000) + (j.expires_in || 3600),
    email: j.user?.email || email || session?.email || '',
  };
}
/** Comprueba correo + PIN en el servidor antes de abrir sesion (bloqueo tras varios intentos fallidos).
 *  Devuelve null si se puede entrar, o el mensaje para mostrar. Si la base aun no tiene la funcion, deja seguir. */
export async function comprobarEntrada(correo, pin) {
  let r;
  try {
    r = await fetchJson(`${URL_BASE}/rest/v1/rpc/entrar_con_correo`, {
      method: 'POST',
      headers: { apikey: KEY, Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_correo: correo, p_pin: pin }),
    });
  } catch (e) {
    if (e.status === 404 || e.body?.code === 'PGRST202') return null; // base de datos anterior a 0016
    throw e;
  }
  const m = r.body || {};
  if (m.ok) return null;
  if (m.motivo === 'bloqueado') return `Demasiados intentos. Por seguridad espera ${m.espera_min} min y vuelve a intentar.`;
  return m.restantes <= 2 ? `Correo o PIN incorrecto. Te quedan ${m.restantes} intentos.` : 'Correo o PIN incorrecto';
}

export async function signIn(email, password) {
  const { body } = await fetchJson(`${URL_BASE}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { apikey: KEY, 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }),
  });
  save(fromToken(body, email));
  return session;
}
let refreshing = null;
async function refresh() {
  if (!session?.refresh_token) { lost(); throw new ApiError('Tu sesión terminó. Inicia sesión de nuevo.', 401); }
  refreshing ??= fetchJson(`${URL_BASE}/auth/v1/token?grant_type=refresh_token`, {
    method: 'POST', headers: { apikey: KEY, 'Content-Type': 'application/json' }, body: JSON.stringify({ refresh_token: session.refresh_token }),
  }).then(({ body }) => save(fromToken(body)))
    .catch((e) => { if (e.status === 400 || e.status === 401) lost(); throw new ApiError('Tu sesión terminó. Inicia sesión de nuevo.', 401); })
    .finally(() => { refreshing = null; });
  return refreshing;
}
function lost() { save(null); listeners.forEach((fn) => fn()); }
async function accessToken() {
  if (!session) throw new ApiError('Inicia sesión', 401);
  if (session.expires_at - 60 < Date.now() / 1000) await refresh();
  return session.access_token;
}
export const hasSession = () => !!session;
export const sessionEmail = () => session?.email || '';
export async function signOut() {
  const t = session?.access_token;
  save(null);
  if (t) fetch(`${URL_BASE}/auth/v1/logout`, { method: 'POST', headers: { apikey: KEY, Authorization: `Bearer ${t}` } }).catch(() => {});
}

// ---------- REST (PostgREST) ----------
async function rest(path, { method = 'GET', body, headers = {}, retry = true } = {}) {
  const t = await accessToken();
  try {
    return await fetchJson(`${URL_BASE}/rest/v1/${path}`, {
      method,
      headers: { apikey: KEY, Authorization: `Bearer ${t}`, 'Content-Type': 'application/json', ...headers },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  } catch (e) {
    if (e.status === 401 && retry) { await refresh(); return rest(path, { method, body, headers, retry: false }); }
    throw e;
  }
}

/** Filtro PostgREST: eq('id', x) -> "id=eq.x" */
export const f = {
  eq: (c, v) => `${encodeURIComponent(c)}=eq.${encodeURIComponent(v)}`,
  gte: (c, v) => `${encodeURIComponent(c)}=gte.${encodeURIComponent(v)}`,
  gt: (c, v) => `${encodeURIComponent(c)}=gt.${encodeURIComponent(v)}`,
  lt: (c, v) => `${encodeURIComponent(c)}=lt.${encodeURIComponent(v)}`,
};

export const db = {
  /** Una pagina (hasta 1000 filas). */
  async select(table, query = 'select=*') {
    return (await rest(`${table}?${query}`)).body || [];
  },
  /** Todas las filas, pidiendo de 1000 en 1000. */
  async all(table, query = 'select=*') {
    const out = [];
    const size = 1000;
    for (let from = 0; ; from += size) {
      const { body } = await rest(`${table}?${query}`, { headers: { 'Range-Unit': 'items', Range: `${from}-${from + size - 1}` } });
      out.push(...(body || []));
      if (!body || body.length < size) break;
    }
    return out;
  },
  /** Pagina con total exacto (para el editor de tablas). */
  async page(table, query, from, to) {
    const { body, headers } = await rest(`${table}?${query}`, {
      headers: { 'Range-Unit': 'items', Range: `${from}-${to}`, Prefer: 'count=exact' },
    });
    const cr = headers.get('Content-Range') || '';
    const total = Number(cr.split('/')[1]);
    return { rows: body || [], total: Number.isFinite(total) ? total : null };
  },
  async insert(table, row) {
    return (await rest(table, { method: 'POST', body: row, headers: { Prefer: 'return=representation' } })).body;
  },
  async update(table, filter, patch) {
    const rows = (await rest(`${table}?${filter}`, { method: 'PATCH', body: patch, headers: { Prefer: 'return=representation' } })).body || [];
    if (!rows.length) throw new ApiError('No se guardó ningún cambio (el registro no existe o no tienes permiso)', 404);
    return rows;
  },
  async remove(table, filter) {
    const rows = (await rest(`${table}?${filter}`, { method: 'DELETE', headers: { Prefer: 'return=representation' } })).body || [];
    if (!rows.length) throw new ApiError('No se eliminó nada (el registro no existe o no tienes permiso)', 404);
    return rows;
  },
  /** Igual que update/remove pero sin exigir filas afectadas (operaciones masivas). */
  async patchMany(table, filter, patch) {
    return (await rest(`${table}?${filter}`, { method: 'PATCH', body: patch, headers: { Prefer: 'return=minimal' } })).body;
  },
  async removeMany(table, filter) {
    return (await rest(`${table}?${filter}`, { method: 'DELETE', headers: { Prefer: 'return=minimal' } })).body;
  },
  async rpc(fn, args = {}) {
    return (await rest(`rpc/${fn}`, { method: 'POST', body: args })).body;
  },
};

/** Funciones en la nube (Edge Functions). */
export async function fn(name, payload, retry = true) {
  const t = await accessToken();
  try {
    const { body } = await fetchJson(`${URL_BASE}/functions/v1/${name}`, {
      method: 'POST', headers: { apikey: KEY, Authorization: `Bearer ${t}`, 'Content-Type': 'application/json' }, body: JSON.stringify(payload),
    });
    return body;
  } catch (e) {
    if (e.status === 401 && retry) { await refresh(); return fn(name, payload, false); }
    throw e;
  }
}

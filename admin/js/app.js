// Panel de administracion: inicio de sesion, estructura, navegacion y actualizacion automatica.
import { signIn, comprobarEntrada, signOut, hasSession, sessionEmail, onSessionLost, db } from './api.js';
import { REFRESH_MS } from './config.js';
import { S, loadAll, loadLive, emit, onChange, lowIngredients, rate } from './store.js';
import { html, raw, setHTML, toast, storage, num, haceRato, openDrawer, revisarPin, parseNum, $ } from './util.js';
import { icon } from './icons.js';

import resumen from './views/resumen.js';
import ventas from './views/ventas.js';
import reportes from './views/reportes.js';
import caja from './views/caja.js';
import productos from './views/productos.js';
import categorias from './views/categorias.js';
import inventario from './views/inventario.js';
import gastos from './views/gastos.js';
import anulaciones from './views/anulaciones.js';
import usuarios from './views/usuarios.js';
import trabajadores from './views/trabajadores.js';
import basedatos from './views/basedatos.js';
import configuracion from './views/configuracion.js';

const GROUPS = [
  ['Negocio', [resumen, ventas, reportes, caja]],
  ['Menú e inventario', [productos, categorias, inventario]],
  ['Control', [gastos, anulaciones]],
  ['Personas', [usuarios, trabajadores]],
  ['Sistema', [basedatos, configuracion]],
];
const VIEWS = GROUPS.flatMap(([, v]) => v);
const app = document.getElementById('app');
let current = null;
let cleanup = null;
let timer = null;
let pendingRender = false;

// ===================== Inicio de sesion =====================
function renderLogin(msg = '') {
  stopTimer();
  const email = storage.get('comandas_admin_correo', '');
  setHTML(app, html`<div class="login">
    <section class="login-side">
      <div>
        <div class="brand-big"><img src="marca/logo-horizontal.png" alt="ComandApp" onerror="this.replaceWith(Object.assign(document.createElement('b'),{textContent:'ComandApp'}))"></div>
        <h1>Todo el negocio en una sola pantalla</h1>
        <p class="lede">Ventas, caja, menú, inventario, gastos y personal, con los mismos datos que usan los teléfonos en tiempo real.</p>
        <ul>
          <li>${icon('chart')}Reportes por día, semana y mes</li>
          <li>${icon('boxes')}Inventario con recetas y alertas de stock</li>
          <li>${icon('database')}Acceso directo a las tablas de la base de datos</li>
        </ul>
      </div>
      <p class="muted small">Solo para administradores. Mesero y cocina usan la app en el teléfono.</p>
    </section>
    <main class="login-main">
      <div class="login-brand" aria-hidden="true"><img src="marca/simbolo.png" alt=""><b>Comand<span>App</span></b></div>
      <form class="login-card" id="login-form" novalidate>
        <p class="eyebrow">Panel de administración</p>
        <h2>Bienvenido de nuevo</h2>
        <p class="sub">Entra con tu correo y tu PIN de 6 números.</p>
        <div class="form-error ${msg ? '' : 'hidden'}" role="alert">${msg}</div>
        <div class="field"><label for="l-email">Correo</label>
          <input class="input" id="l-email" name="email" type="email" autocomplete="username" required value="${email}"></div>
        <div class="field"><label for="l-pin">PIN</label>
          <input class="input pin-input" id="l-pin" name="pin" type="password" inputmode="numeric" autocomplete="current-password" maxlength="6" required></div>
        <button class="btn btn-primary btn-block" type="submit" style="height:44px;margin-top:6px">Entrar</button>
        <div class="login-alt">${icon('user', 16)}<span>¿Eres mesero o cocina? Entra desde la app ComandApp en tu teléfono o tableta.</span></div>
      </form>
      <p class="login-foot">© ${new Date().getFullYear()} ComandApp · Comandas, caja e inventario</p>
    </main>
  </div>`);
  const form = $('#login-form');
  (email ? $('#l-pin') : $('#l-email')).focus();
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const err = form.querySelector('.form-error');
    const btn = form.querySelector('button');
    const correo = form.email.value.trim().toLowerCase();
    const pin = form.pin.value.trim();
    const fail = (m) => { err.textContent = m; err.classList.remove('hidden'); btn.disabled = false; btn.textContent = 'Entrar'; };
    if (!correo) return fail('Escribe tu correo');
    if (!/^[0-9]{4,6}$/.test(pin)) return fail('El PIN son solo números');
    btn.disabled = true; btn.textContent = 'Entrando…';
    try {
      const bloqueo = await comprobarEntrada(correo, pin);
      if (bloqueo) return fail(bloqueo);
      await signIn(correo, `${pin}-comandas`);
      storage.set('comandas_admin_correo', correo);
      const ok = await afterLogin(fail);
      if (ok && pin.length < 6) await forzarCambioPin(pin);
    } catch (ex) { fail(ex.message); }
  });
}

async function afterLogin(fail = (m) => renderLogin(m)) {
  let perfil;
  try { perfil = (await db.rpc('my_profile'))?.[0]; } catch (e) { await signOut(); fail(e.message); return false; }
  if (!perfil) { await signOut(); fail('Tu usuario no está activo o no tiene acceso. Pide ayuda a otro administrador.'); return false; }
  if (perfil.negocio_activo === false) { await signOut(); fail('Tu negocio no está activo en este momento. Escríbenos para reactivarlo.'); return false; }
  if (perfil.role !== 'admin') { await signOut(); fail('Este panel es solo para administradores. Usa la app en el teléfono.'); return false; }
  S.me = { ...perfil, email: sessionEmail() };
  setHTML(app, html`<div class="boot"><div class="spinner" aria-hidden="true"></div><span>Cargando datos del negocio…</span></div>`);
  try { await loadAll(); } catch (e) { toast('No se pudieron cargar todos los datos: ' + e.message, 'bad'); }
  renderShell();
  route();
  startTimer();
  return true;
}

function forzarCambioPin(actual) {
  return new Promise((resolve) => {
    openDrawer({
      title: 'Crea tu PIN de 6 números',
      submitLabel: 'Guardar PIN',
      body: html`<p class="text-2">Tu PIN actual es de ${actual.length} números. Para seguir usando el sistema crea uno nuevo de 6 números. Será tu PIN en la app y en este panel.</p>
        <div class="field"><label for="np1">PIN nuevo</label><input class="input pin-input" id="np1" name="nuevo" type="password" inputmode="numeric" maxlength="6" autocomplete="new-password"></div>
        <div class="field"><label for="np2">Repite el PIN nuevo</label><input class="input pin-input" id="np2" name="repite" type="password" inputmode="numeric" maxlength="6" autocomplete="new-password"></div>`,
      async onSubmit(d) { await cambiarPin(actual, d.nuevo, d.repite); toast('PIN actualizado'); resolve(); },
    });
  });
}
async function cambiarPin(actual, nuevo, repite) {
  const malo = revisarPin(nuevo);
  if (malo) throw new Error(malo);
  if (nuevo !== repite) throw new Error('Los PIN nuevos no coinciden');
  if (nuevo === actual) throw new Error('El PIN nuevo debe ser distinto al actual');
  const r = await db.rpc('cambiar_pin', { p_actual: actual, p_nuevo: nuevo });
  const msg = { pin_actual_incorrecto: 'El PIN actual no es correcto', pin_nuevo_invalido: 'El PIN nuevo debe ser de 6 números', pin_nuevo_facil: 'Ese PIN es muy fácil de adivinar. Elige otro.', sin_sesion: 'Tu sesión terminó. Inicia sesión de nuevo.' }[r];
  if (r !== 'ok') throw new Error(msg || 'No se pudo cambiar el PIN');
}

// ===================== Estructura =====================
function navHTML() {
  const bajos = lowIngredients().length;
  return html`${GROUPS.map(([g, views]) => html`<div class="nav-group"><div class="nav-title">${g}</div><nav class="nav">
    ${views.map((v) => html`<a href="#/${v.path}" data-path="${v.path}">${icon(v.icon)}<span>${v.title}</span>${v.path === 'inventario' && bajos ? html`<span class="count" title="Ingredientes por agotarse">${bajos}</span>` : ''}</a>`)}
  </nav></div>`)}`;
}

function renderShell() {
  setHTML(app, html`<div class="shell" id="shell">
    <aside class="sidebar" aria-label="Menú principal">
      <div class="brand"><img src="marca/simbolo.png" alt="" onerror="this.style.display='none'"><div><div class="b-name">${S.config.business_name || S.me.negocio_nombre || 'Mi negocio'}</div><div class="b-sub">Panel · ComandApp</div></div></div>
      <div id="nav">${navHTML()}</div>
      <div class="sidebar-foot nav">
        <div class="me"><span class="avatar">${(S.me.name || '?').trim().charAt(0).toUpperCase()}</span><div><b>${S.me.name}</b><span>Administrador</span></div></div>
      </div>
    </aside>
    <div class="main">
      <header class="topbar">
        <button class="icon-btn menu-btn" id="menu-btn" aria-label="Abrir menú">${icon('menu')}</button>
        <div class="title"><h1 id="v-title"></h1><p id="v-sub"></p></div>
        <div class="spacer"></div>
        <button class="rate-chip" id="rate-btn" title="Cambiar la tasa del día"><span>Tasa</span><b id="rate-val"></b><span>Bs por $</span></button>
        <span class="sync" id="sync"></span>
        <button class="icon-btn" id="refresh-btn" title="Actualizar datos" aria-label="Actualizar datos">${icon('refresh')}</button>
        <button class="icon-btn" id="theme-btn" title="Cambiar tema" aria-label="Cambiar tema claro u oscuro"></button>
        <div class="rel">
          <button class="icon-btn bordered" id="user-btn" aria-haspopup="menu" aria-expanded="false" title="${S.me.name}">${icon('user')}</button>
          <div class="menu-pop hidden" id="user-menu" role="menu">
            <div class="who"><b>${S.me.name}</b><span>${S.me.email}</span></div>
            <button role="menuitem" data-act="pin">${icon('key', 16)}Cambiar mi PIN</button>
            <button role="menuitem" data-act="salir">${icon('logout', 16)}Cerrar sesión</button>
          </div>
        </div>
      </header>
      <main class="content" id="view" tabindex="-1"></main>
    </div>
  </div>`);
  paintTop();
  $('#menu-btn').onclick = () => $('#shell').classList.toggle('nav-open');
  $('#shell').addEventListener('click', (e) => {
    if (e.target.id === 'shell') $('#shell').classList.remove('nav-open');
    if (e.target.closest('.nav a')) $('#shell').classList.remove('nav-open');
  });
  $('#refresh-btn').onclick = () => refreshNow(true);
  $('#rate-btn').onclick = editarTasa;
  $('#theme-btn').onclick = toggleTheme;
  const menu = $('#user-menu');
  $('#user-btn').onclick = (e) => { e.stopPropagation(); menu.classList.toggle('hidden'); $('#user-btn').setAttribute('aria-expanded', String(!menu.classList.contains('hidden'))); };
  document.addEventListener('click', (e) => { if (!e.target.closest('#user-menu')) menu.classList.add('hidden'); });
  menu.addEventListener('click', async (e) => {
    const act = e.target.closest('[data-act]')?.dataset.act;
    menu.classList.add('hidden');
    if (act === 'salir') { await signOut(); S.me = null; renderLogin(); }
    if (act === 'pin') {
      openDrawer({
        title: 'Cambiar mi PIN', submitLabel: 'Guardar PIN',
        body: html`<p class="text-2">Es el mismo PIN que usas en la app del teléfono.</p>
          <div class="field"><label for="cp0">PIN actual</label><input class="input pin-input" id="cp0" name="actual" type="password" inputmode="numeric" maxlength="6" autocomplete="current-password"></div>
          <div class="field"><label for="cp1">PIN nuevo</label><input class="input pin-input" id="cp1" name="nuevo" type="password" inputmode="numeric" maxlength="6" autocomplete="new-password"></div>
          <div class="field"><label for="cp2">Repite el PIN nuevo</label><input class="input pin-input" id="cp2" name="repite" type="password" inputmode="numeric" maxlength="6" autocomplete="new-password"></div>`,
        async onSubmit(d) { await cambiarPin(d.actual, d.nuevo, d.repite); toast('PIN actualizado. Úsalo la próxima vez que entres.'); },
      });
    }
  });
}

function paintTop() {
  const rv = $('#rate-val'); if (rv) rv.textContent = num(rate());
  const sy = $('#sync'); if (sy) sy.textContent = S.loadedAt ? 'Actualizado ' + haceRato(S.loadedAt) : '';
  const nav = $('#nav'); if (nav) { setHTML(nav, navHTML()); markNav(); }
  const tb = $('#theme-btn'); if (tb) setHTML(tb, icon(isDark() ? 'sun' : 'moon'));
}
function markNav() {
  document.querySelectorAll('.nav a[data-path]').forEach((a) => {
    if (a.dataset.path === current?.path) a.setAttribute('aria-current', 'page'); else a.removeAttribute('aria-current');
  });
}

// ===================== Navegacion =====================
async function route() {
  if (!S.me) return;
  const path = (location.hash.replace(/^#\/?/, '').split('?')[0]) || 'resumen';
  const v = VIEWS.find((x) => x.path === path) || resumen;
  const changed = v !== current;
  current = v;
  markNav();
  $('#v-title').textContent = v.title;
  document.title = `${v.title} · ComandApp`;
  const view = $('#view');
  if (changed) {
    cleanup?.(); cleanup = null;
    if (v.load) {
      setHTML(view, html`<div class="boot" style="min-height:40vh"><div class="spinner"></div></div>`);
      try { await v.load(); } catch (e) { toast(e.message, 'bad'); }
      if (current !== v) return;
    }
  }
  paint();
  if (changed) { view.focus({ preventScroll: true }); window.scrollTo(0, 0); }
}

function paint() {
  if (!current) return;
  const view = $('#view');
  if (!view) return;
  $('#v-sub').textContent = current.subtitle?.() || '';
  cleanup?.();
  setHTML(view, current.render());
  // Los eventos que registra la vista se cancelan solos en el siguiente dibujo.
  const ac = new AbortController();
  const extra = current.mount?.(view, { rerender: paint, refresh: refreshNow, signal: ac.signal }) || null;
  cleanup = () => { ac.abort(); extra?.(); };
  pendingRender = false;
}

/** Re-pinta la vista sin quitarle el foco a quien esta escribiendo. */
function softRepaint() {
  paintTop();
  const a = document.activeElement;
  if (a && $('#view')?.contains(a) && /INPUT|TEXTAREA|SELECT/.test(a.tagName)) { pendingRender = true; return; }
  if (document.querySelector('#overlays .drawer')) { pendingRender = true; return; }
  paint();
}
document.addEventListener('focusout', () => setTimeout(() => {
  if (pendingRender && !document.querySelector('#overlays .drawer')) {
    const a = document.activeElement;
    if (!(a && $('#view')?.contains(a) && /INPUT|TEXTAREA|SELECT/.test(a.tagName))) paint();
  }
}, 50));
new MutationObserver(() => { if (pendingRender && !document.querySelector('#overlays .drawer')) softRepaint(); })
  .observe(document.getElementById('overlays'), { childList: true });

async function refreshNow(full = false) {
  const btn = $('#refresh-btn');
  btn?.setAttribute('disabled', '');
  try {
    if (full) { await loadAll(); await current?.load?.(true); } else { await loadLive(); await current?.reload?.(); }
    emit();
    if (full) toast('Datos actualizados');
  } catch (e) {
    if (full) toast(e.message, 'bad');
  } finally { btn?.removeAttribute('disabled'); }
}
function startTimer() {
  stopTimer();
  timer = setInterval(() => { if (document.visibilityState === 'visible' && S.me) refreshNow(false); }, REFRESH_MS);
}
function stopTimer() { if (timer) clearInterval(timer); timer = null; }
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible' && S.me && S.loadedAt && Date.now() - S.loadedAt > 10000) refreshNow(false);
});
onChange(softRepaint);
setInterval(() => { const sy = $('#sync'); if (sy && S.loadedAt) sy.textContent = 'Actualizado ' + haceRato(S.loadedAt); }, 20000);

// ===================== Tasa del dia =====================
function editarTasa() {
  openDrawer({
    title: 'Tasa de cambio del día',
    submitLabel: 'Guardar tasa',
    body: html`<p class="text-2">Se usa en la app y en este panel para mostrar precios y montos en bolívares.</p>
      <div class="field"><label for="t-rate">Bolívares por 1 dólar</label>
        <div class="input-group"><input class="input" id="t-rate" name="rate" inputmode="decimal" value="${num(rate())}"><span class="addon">Bs</span></div>
        <span class="hint">Tasa actual: ${num(rate())} Bs. Última actualización ${S.config.updated_at ? haceRato(S.config.updated_at) : '—'}.</span></div>`,
    async onSubmit(d) {
      const v = parseNum(d.rate);
      if (!(v > 0)) throw new Error('Escribe una tasa mayor a cero');
      const rows = await db.update('app_config', 'id=eq.1', { rate: v, updated_at: new Date().toISOString() });
      S.config = rows[0];
      emit();
      toast('Tasa actualizada');
    },
  });
}

// ===================== Tema =====================
function isDark() {
  const t = document.documentElement.dataset.theme;
  return t ? t === 'dark' : matchMedia('(prefers-color-scheme: dark)').matches;
}
function toggleTheme() {
  const next = isDark() ? 'light' : 'dark';
  document.documentElement.dataset.theme = next;
  storage.set('comandas_tema', next);
  paintTop();
  paint(); // los graficos toman los colores del tema
}
export function setTheme(t) {
  if (t === 'system') { delete document.documentElement.dataset.theme; storage.set('comandas_tema', null); }
  else { document.documentElement.dataset.theme = t; storage.set('comandas_tema', t); }
  paintTop(); paint();
}

// ===================== Arranque =====================
onSessionLost(() => { S.me = null; current = null; renderLogin('Tu sesión terminó. Inicia sesión de nuevo.'); });
window.addEventListener('hashchange', route);
(async () => {
  if (hasSession()) {
    const ok = await afterLogin((m) => renderLogin(m));
    if (!ok && !S.me) return;
  } else {
    renderLogin();
  }
})();
export { raw };

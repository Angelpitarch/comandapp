// Usuarios del sistema: roles, PIN y acceso. Meseros y cocina entran solo con PIN; el administrador usa correo para el panel.
import { html, fecha, openDrawer, confirmDialog, toast, revisarPin } from '../util.js';
import { icon } from '../icons.js';
import { db, fn } from '../api.js';
import { S, load as L, emit, ROLES } from '../store.js';
import { empty, listen } from './common.js';

const roleBadge = (r) => html`<span class="badge ${r === 'admin' ? 'warn' : 'neutral'}">${icon(r === 'admin' ? 'key' : 'user', 13)}${ROLES[r] || r}</span>`;
// Acceso interno (sin correo real): lo crea el sistema para meseros y cocina y nadie lo ve.
const interno = (email) => /\.local$/i.test(email || '');
const MAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
function acceso(u) {
  if (!u.email) return html`<span class="badge warn">${icon('alert', 13)}Sin acceso</span>`;
  if (interno(u.email)) return html`<span class="badge good">${icon('lock', 13)}Entra con PIN</span>${u.role === 'admin' ? html` <span class="muted small">sin correo para el panel</span>` : ''}`;
  return html`<span class="mono">${u.email}</span>`;
}

function render() {
  const us = S.users;
  return html`
  <div class="toolbar"><p class="text-2 grow">Cada persona entra a la app tocando su nombre y poniendo su PIN de 6 números. Meseros y cocina no necesitan correo; el administrador sí, para entrar a este panel. Mesero atiende mesas y cobra, Cocina solo ve las comandas, Administrador puede todo.</p>
    <button class="btn btn-primary" data-act="nuevo">${icon('plus', 16)}Nuevo usuario</button></div>
  <section class="card card-flush">
    ${us.length ? html`<div class="table-wrap"><table class="table">
      <thead><tr><th>Nombre</th><th>Acceso</th><th>Rol</th><th>Estado</th><th>Creado</th><th class="r"></th></tr></thead>
      <tbody>${us.map((u) => html`<tr class="clickable" data-id="${u.id}" tabindex="0">
        <td><div class="t-main">${u.name || '(sin nombre)'}${u.id === S.me?.id ? html` <span class="muted small">(tú)</span>` : ''}</div></td>
        <td>${acceso(u)}</td>
        <td>${roleBadge(u.role)}</td>
        <td>${u.active ? html`<span class="badge good">${icon('checkCircle', 13)}Activo</span>` : html`<span class="badge neutral">${icon('xCircle', 13)}Inactivo</span>`}</td>
        <td class="muted nowrap">${u.created_at ? fecha(u.created_at) : '—'}</td>
        <td class="r"><button class="btn btn-sm" data-edit="${u.id}">${icon('edit', 14)}Editar</button></td></tr>`)}</tbody>
    </table></div>` : empty('Sin usuarios')}
  </section>
  <p class="muted small" style="margin-top:10px">Los PIN no se pueden ver: solo cambiar. No se aceptan PIN fáciles de adivinar (123456, 111111, 121212…).</p>`;
}

const rolSelect = (sel, disabled = false) => html`<select class="input" name="role" id="u-role" ${disabled ? 'disabled' : ''}>${Object.entries(ROLES).map(([k, v]) => html`<option value="${k}" ${k === sel ? 'selected' : ''}>${v}</option>`)}</select>`;
const campoCorreo = (valor = '', ayuda = 'Con este correo y su PIN entra al panel web. Meseros y cocina no lo necesitan.') =>
  html`<div class="field full" data-correo><label for="u-mail">Correo para el panel web</label><input class="input" id="u-mail" name="email" type="email" autocomplete="off" value="${valor}"><span class="hint">${ayuda}</span></div>`;
// muestra el campo de correo solo cuando el rol elegido es Administrador
function correoSegunRol(frm, siempre = false) {
  const sync = () => { const c = frm.querySelector('[data-correo]'); if (c) c.classList.toggle('hidden', !siempre && frm.role?.value !== 'admin'); };
  frm.addEventListener('change', (e) => { if (e.target.name === 'role') sync(); });
  sync();
}

function nuevo() {
  openDrawer({
    title: 'Nuevo usuario', submitLabel: 'Crear usuario',
    body: html`<div class="form-grid">
      <div class="field full"><label for="u-name">Nombre</label><input class="input" id="u-name" name="name" required><span class="hint">Así aparecerá en la pantalla de entrada de la app.</span></div>
      <div class="field"><label for="u-pin">PIN (6 números)</label><input class="input pin-input" id="u-pin" name="pin" inputmode="numeric" maxlength="6" autocomplete="new-password"></div>
      <div class="field"><label for="u-role">Rol</label>${rolSelect('mesero')}</div>
      ${campoCorreo()}
      <div class="field full"><label class="switch"><input type="checkbox" name="active" checked><span class="track"></span>Activo (puede entrar)</label></div>
    </div>`,
    onMount(frm) { correoSegunRol(frm); },
    async onSubmit(d) {
      if (!d.name) throw new Error('Escribe el nombre');
      const malo = revisarPin(d.pin); if (malo) throw new Error(malo);
      const correo = d.role === 'admin' ? (d.email || '').trim() : '';
      if (d.role === 'admin' && !MAIL.test(correo)) throw new Error('El administrador necesita un correo válido para entrar al panel');
      const r = await fn('admin-usuarios', { accion: 'crear', nombre: d.name, correo, pin: d.pin, rol: d.role, activo: !!d.active });
      if (r?.error) throw new Error(r.error);
      await L.users(); emit();
      toast(`${d.name} ya puede entrar a la app con su PIN`);
    },
  });
}

function editar(u) {
  const yo = u.id === S.me?.id;
  const real = u.email && !interno(u.email);
  openDrawer({
    title: `Editar ${u.name}`, submitLabel: 'Guardar cambios',
    extraFoot: yo ? '' : html`<button type="button" class="btn btn-danger left" data-borrar>${icon('trash', 16)}Eliminar usuario</button>`,
    body: html`<div class="form-grid">
      <div class="field full"><label for="u-name">Nombre</label><input class="input" id="u-name" name="name" value="${u.name}" required></div>
      <div class="field"><label for="u-role">Rol</label>${rolSelect(u.role, yo)}${yo ? html`<span class="hint">No puedes quitarte tu propio rol de administrador.</span>` : ''}</div>
      <div class="field"><label for="u-pin">PIN nuevo</label><input class="input pin-input" id="u-pin" name="pin" inputmode="numeric" maxlength="6" autocomplete="new-password" placeholder="${u.email ? 'Vacío = no cambiar' : 'Obligatorio para darle acceso'}"><span class="hint">Cambia también la clave con la que entra a la app.</span></div>
      ${u.email ? campoCorreo(real ? u.email : '', real ? 'Con este correo y su PIN entra al panel web.' + (yo ? ' Si lo cambias tendrás que volver a iniciar sesión.' : '') : 'Para que este administrador entre al panel web, escribe su correo.') : ''}
      <div class="field full"><label class="switch"><input type="checkbox" name="active" ${u.active ? 'checked' : ''} ${yo ? 'disabled' : ''}><span class="track"></span>Activo (puede entrar)</label></div>
    </div>
    ${u.email ? '' : html`<div class="note warn stack" style="gap:10px"><div><b>Este usuario no tiene acceso todavía.</b> Escribe un PIN nuevo para que pueda entrar a la app.</div>
        ${campoCorreo('', 'Solo si va a ser administrador: correo para entrar al panel web.')}</div>`}`,
    onMount(frm, close) {
      correoSegunRol(frm, real);
      frm.addEventListener('click', async (e) => {
        if (!e.target.closest('[data-borrar]')) return;
        const ok = await confirmDialog({ title: `Eliminar a ${u.name}`, body: 'Se borra el usuario y su acceso. Ya no podrá entrar a la app. Las ventas que registró se conservan.', confirm: 'Eliminar', danger: true });
        if (!ok) return;
        try {
          const r = await fn('admin-usuarios', { accion: 'eliminar', id: u.id });
          if (r?.error) throw new Error(r.error);
          await L.users(); emit(); close(); toast('Usuario eliminado');
        } catch (ex) { toast(ex.message, 'bad'); }
      });
    },
    async onSubmit(d) {
      if (!d.name) throw new Error('Escribe el nombre');
      const role = yo ? 'admin' : d.role;
      const active = yo ? true : !!d.active;
      const correo = (d.email || '').trim().toLowerCase();
      if (d.pin) { const malo = revisarPin(d.pin); if (malo) throw new Error(malo); }
      if (correo && !MAIL.test(correo)) throw new Error('Escribe un correo válido');
      if (!u.email) {
        if (!d.pin) throw new Error('Para darle acceso escribe un PIN nuevo');
        if (role === 'admin' && !correo) throw new Error('El administrador necesita un correo para entrar al panel');
        await db.rpc('save_user', { p_id: u.id, p_name: d.name, p_pin: '', p_role: role, p_active: active });
        const r = await fn('admin-usuarios', { accion: 'acceso', id: u.id, correo: role === 'admin' ? correo : '', pin: d.pin });
        if (r?.error) throw new Error(r.error);
      } else {
        await db.rpc('save_user', { p_id: u.id, p_name: d.name, p_pin: d.pin || '', p_role: role, p_active: active });
        if (correo && correo !== (u.email || '').toLowerCase()) {
          const r = await fn('admin-usuarios', { accion: 'correo', id: u.id, correo });
          if (r?.error) throw new Error(r.error);
          if (yo) { toast('Correo cambiado. Vuelve a iniciar sesión con el correo nuevo.'); setTimeout(() => location.reload(), 1500); }
        }
      }
      await L.users(); emit();
      toast(d.pin ? 'Cambios guardados. El PIN nuevo ya funciona.' : 'Cambios guardados');
    },
  });
}

function mount(root, ctx) {
  listen(root, ctx, {
    click(e) {
      if (e.target.closest('[data-act="nuevo"]')) return nuevo();
      const id = e.target.closest('[data-edit]')?.dataset.edit || e.target.closest('tr[data-id]')?.dataset.id;
      if (id) editar(S.users.find((u) => u.id === id));
    },
  });
}

export default { path: 'usuarios', title: 'Usuarios', icon: 'users', subtitle: () => 'Quién entra a la app y con qué rol', render, mount };

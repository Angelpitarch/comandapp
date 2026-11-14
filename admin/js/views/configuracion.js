// Configuracion: nombre del negocio, tasa, apariencia y enlaces utiles.
import { html, num, parseNum, toast, haceRato, storage } from '../util.js';
import { icon } from '../icons.js';
import { db } from '../api.js';
import { S, emit } from '../store.js';
import { APP_URL } from '../config.js';
import { listen, seg } from './common.js';
import { setTheme } from '../app.js';

const temaActual = () => storage.get('comandas_tema', 'system') || 'system';

function render() {
  return html`
  <div class="grid-2e">
    <section class="card"><div class="card-head"><div><h2>Negocio</h2><p>Se usa en la app y en los comprobantes</p></div></div>
      <form class="card-body stack" data-form="negocio" novalidate>
        <div class="field"><label for="c-name">Nombre del negocio</label><input class="input" id="c-name" name="business_name" value="${S.config.business_name || ''}"></div>
        <div class="field"><label for="c-rate">Tasa de cambio (Bs por 1 dólar)</label><div class="input-group"><input class="input" id="c-rate" name="rate" inputmode="decimal" value="${num(S.config.rate)}"><span class="addon">Bs</span></div>
          <span class="hint">Última actualización ${S.config.updated_at ? haceRato(S.config.updated_at) : '—'}. Cambia en todos los teléfonos al instante.</span></div>
        <div><button class="btn btn-primary" type="submit">Guardar</button></div>
      </form></section>

    <section class="card"><div class="card-head"><div><h2>Apariencia</h2><p>Solo en este navegador</p></div></div>
      <div class="card-body stack">
        <div class="field"><span class="label">Tema</span>${seg('tema', [['system', 'Igual que el sistema'], ['light', 'Claro'], ['dark', 'Oscuro']], temaActual())}</div>
      </div></section>

    <section class="card"><div class="card-head"><div><h2>Pantallas de mesero y cocina</h2><p>La app completa en el navegador</p></div></div>
      <div class="card-body stack">
        <p class="text-2">Abre la misma app de los teléfonos en esta computadora, por ejemplo para usar la pantalla de cocina en un monitor.</p>
        <div><a class="btn" href="${APP_URL}" target="_blank" rel="noopener">${icon('external', 16)}Abrir la app</a></div>
      </div></section>

    <section class="card"><div class="card-head"><div><h2>Sesión</h2><p>${S.me?.email || ''}</p></div></div>
      <div class="card-body stack">
        <dl class="kv"><div><dt>Usuario</dt><dd>${S.me?.name || ''}</dd></div><div><dt>Rol</dt><dd>Administrador</dd></div></dl>
        <p class="muted small">La sesión se guarda en este navegador. Si usas una computadora compartida, ciérrala al terminar desde el menú de usuario arriba a la derecha.</p>
      </div></section>
  </div>`;
}

function mount(root, ctx) {
  listen(root, ctx, {
    click(e) {
      const b = e.target.closest('[data-seg="tema"] button');
      if (b) setTheme(b.dataset.v);
    },
    async submit(e) {
      if (e.target.dataset.form !== 'negocio') return;
      e.preventDefault();
      const name = e.target.business_name.value.trim();
      const rate = parseNum(e.target.rate.value);
      if (!name) return toast('Escribe el nombre del negocio', 'bad');
      if (!(rate > 0)) return toast('Escribe una tasa mayor a cero', 'bad');
      try {
        const patch = { business_name: name };
        if (Math.abs(rate - Number(S.config.rate)) > 1e-9) { patch.rate = rate; patch.updated_at = new Date().toISOString(); }
        const [row] = await db.update('app_config', 'id=eq.1', patch);
        S.config = row; emit(); toast('Configuración guardada');
      } catch (ex) { toast(ex.message, 'bad'); }
    },
  });
}

export default { path: 'configuracion', title: 'Configuración', icon: 'settings', subtitle: () => 'Datos del negocio y preferencias', render, mount };

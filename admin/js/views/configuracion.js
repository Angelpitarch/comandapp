// Configuracion: nombre del negocio, tasa, apariencia y enlaces utiles.
import { html, num, toast, haceRato, storage } from '../util.js';
import { icon } from '../icons.js';
import { db } from '../api.js';
import { S, emit, rate, tasaEsBcv, proximaTasa, fechaValor } from '../store.js';
import { listen, seg } from './common.js';
import { setTheme, editarTasa } from '../app.js';

const temaActual = () => storage.get('comandas_tema', 'system') || 'system';

function tarjetaTasa() {
  const bcv = tasaEsBcv();
  const prox = proximaTasa();
  const estado = bcv
    ? html`<span class="badge good">${icon('check', 14)}Oficial del BCV</span>`
    : S.config.tasa_auto ? html`<span class="badge neutral">Esperando la del BCV</span>` : html`<span class="badge neutral">Escrita a mano</span>`;
  return html`<section class="card"><div class="card-head"><div><h2>Tasa del día</h2><p>Bolívares por 1 dólar. Cambia en todos los teléfonos al instante.</p></div><button class="btn btn-sm" type="button" data-act="tasa">Cambiar</button></div>
    <div class="card-body stack">
      <dl class="kv">
        <div><dt>Tasa en uso</dt><dd>${num(rate())} Bs</dd></div>
        <div><dt>Origen</dt><dd>${estado}</dd></div>
        ${bcv ? html`<div><dt>Fecha valor</dt><dd>${fechaValor(S.config.tasa_fecha)}</dd></div>` : ''}
        <div><dt>Actualizada</dt><dd>${S.config.updated_at ? haceRato(S.config.updated_at) : '—'}</dd></div>
        ${prox ? html`<div><dt>Próxima (${fechaValor(prox.fecha_valor)})</dt><dd>${num(prox.usd)} Bs</dd></div>` : ''}
      </dl>
      <p class="muted small">${S.config.tasa_auto
        ? 'Se toma sola de bcv.org.ve: se revisa cada hora y la nueva tasa se aplica a las 12:01 a.m. del día que indica el BCV. Si escribes una tasa a mano, deja de actualizarse sola.'
        : 'No se actualiza sola. Toca «Cambiar» para escribir otra o para volver a usar la tasa oficial del BCV.'}</p>
    </div></section>`;
}

function render() {
  return html`
  <div class="grid-2e">
    <section class="card"><div class="card-head"><div><h2>Negocio</h2><p>Se usa en la app y en los comprobantes</p></div></div>
      <form class="card-body stack" data-form="negocio" novalidate>
        ${S.me?.negocio_codigo ? html`<div class="field"><span class="label">Código para entrar a la app</span>
          <div class="input-group"><input class="input mono" value="${S.me.negocio_codigo}" readonly aria-label="Código del negocio"><button class="btn" type="button" data-act="copiar-codigo">${icon('copy', 16)}Copiar</button></div>
          <span class="hint">Dáselo a tu personal: lo escriben una sola vez en cada teléfono, antes de elegir su nombre y poner su PIN. Se acepta con mayúsculas o espacios.</span></div>` : ''}
        <div class="field"><label for="c-name">Nombre del negocio</label><input class="input" id="c-name" name="business_name" value="${S.config.business_name || ''}"></div>
        <div><button class="btn btn-primary" type="submit">Guardar</button></div>
      </form></section>

    ${tarjetaTasa()}

    <section class="card"><div class="card-head"><div><h2>Apariencia</h2><p>Solo en este navegador</p></div></div>
      <div class="card-body stack">
        <div class="field"><span class="label">Tema</span>${seg('tema', [['system', 'Igual que el sistema'], ['light', 'Claro'], ['dark', 'Oscuro']], temaActual())}</div>
      </div></section>

    <section class="card"><div class="card-head"><div><h2>App para el personal</h2><p>Mesero, cocina y administrador en el teléfono</p></div></div>
      <div class="card-body stack">
        <p class="text-2">Meseros y cocina trabajan con la app ComandApp instalada en un teléfono o una tableta Android. Para la cocina, lo más práctico es una tableta en la pared, o una cajita Android TV conectada a un monitor con un ratón.</p>
        <p class="text-2">El dueño también puede entrar a la app como administrador para ver el negocio desde cualquier lugar. Este panel funciona igual en el navegador del teléfono.</p>
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
      if (e.target.closest('[data-act="copiar-codigo"]')) {
        navigator.clipboard?.writeText(S.me.negocio_codigo).then(() => toast('Código copiado'), () => toast('No se pudo copiar', 'bad'));
        return;
      }
      if (e.target.closest('[data-act="tasa"]')) { editarTasa(); return; }
      const b = e.target.closest('[data-seg="tema"] button');
      if (b) setTheme(b.dataset.v);
    },
    async submit(e) {
      if (e.target.dataset.form !== 'negocio') return;
      e.preventDefault();
      const name = e.target.business_name.value.trim();
      if (!name) return toast('Escribe el nombre del negocio', 'bad');
      try {
        const [row] = await db.update('app_config', 'id=eq.1', { business_name: name });
        S.config = row; emit(); toast('Configuración guardada');
      } catch (ex) { toast(ex.message, 'bad'); }
    },
  });
}

export default { path: 'configuracion', title: 'Configuración', icon: 'settings', subtitle: () => 'Datos del negocio y preferencias', render, mount };

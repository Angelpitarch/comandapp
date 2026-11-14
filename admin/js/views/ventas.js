// Ventas: cuentas cobradas en un periodo, con detalle y exportacion.
import { html, usd, bs, qty, fecha, hora, fechaHora, openDrawer, downloadCSV, debounce, num } from '../util.js';
import { icon } from '../icons.js';
import { S, summarize, salesCost, salesBetween, toBs } from '../store.js';
import { tile, empty, seg, PRESETS, presetRange, rangeInputs, origen } from './common.js';

const st = { preset: 'turno', desde: '', hasta: '', q: '', rows: [] };

async function load() {
  const r = presetRange(st.preset, st.desde, st.hasta);
  st.range = r;
  st.rows = st.preset === 'turno' ? S.turnoSales : await salesBetween(r.from, r.to);
}

function filtered() {
  const q = st.q.toLowerCase();
  if (!q) return st.rows;
  return st.rows.filter((s) =>
    origen(s).toLowerCase().includes(q)
    || (s.lines || []).some((l) => (l.name || '').toLowerCase().includes(q))
    || (s.payments || []).some((p) => (p.method || '').toLowerCase().includes(q) || (p.reference || '').toLowerCase().includes(q)));
}

function render() {
  const rows = filtered();
  const r = summarize(rows);
  const costo = salesCost(rows);
  return html`
  <div class="toolbar">
    ${seg('preset', PRESETS, st.preset)}
    ${rangeInputs(st)}
    <div class="grow"></div>
    <label class="search">${icon('search', 16)}<span class="sr-only">Buscar</span><input class="input sm" type="search" data-k="q" placeholder="Buscar producto, mesa o pago" value="${st.q}"></label>
    <button class="btn btn-sm" data-act="csv">${icon('download', 16)}Exportar</button>
  </div>
  <p class="muted small" style="margin:-6px 0 12px">${st.range?.label}</p>
  <div class="tiles">
    ${tile('Total vendido', usd(r.total), bs(toBs(r.total)))}
    ${tile('Cuentas cobradas', num(r.count, 0))}
    ${tile('Ticket promedio', usd(r.count ? r.total / r.count : 0))}
    ${tile('Ganancia estimada', usd(r.total - costo), `Costo estimado ${usd(costo)}`)}
  </div>
  <section class="card card-flush">
    ${rows.length ? html`<div class="table-wrap"><table class="table">
      <thead><tr><th>Fecha</th><th>Origen</th><th>Productos</th><th>Pago</th><th class="r">Total</th><th class="r">En Bs</th></tr></thead>
      <tbody>${rows.map((s) => html`<tr class="clickable" data-id="${s.id}" tabindex="0">
        <td class="nowrap"><div class="t-main">${fecha(s.at)}</div><div class="t-sub">${hora(s.at)}</div></td>
        <td class="nowrap">${origen(s)}</td>
        <td><div class="t-main">${resumenLineas(s)}</div></td>
        <td>${(s.payments || []).map((p) => html`<span class="tag" style="margin:1px 4px 1px 0">${p.method}</span>`)}</td>
        <td class="r t-main">${usd(s.total_usd)}</td>
        <td class="r muted">${bs(toBs(s.total_usd))}</td>
      </tr>`)}</tbody>
      <tfoot><tr><td colspan="4">${rows.length} ${rows.length === 1 ? 'cuenta' : 'cuentas'}</td><td class="r">${usd(r.total)}</td><td class="r">${bs(toBs(r.total))}</td></tr></tfoot>
    </table></div>` : empty('No hay ventas en este periodo', st.q ? 'Prueba con otra búsqueda.' : 'Elige otro periodo arriba.')}
  </section>
  <p class="muted small" style="margin-top:10px">Los montos en Bs usan la tasa de hoy. El costo usa los precios de compra actuales de los ingredientes.</p>`;
}

function resumenLineas(s) {
  const l = s.lines || [];
  const txt = l.slice(0, 3).map((x) => `${qty(x.qty)} ${x.name}`).join(', ');
  return l.length > 3 ? `${txt} y ${l.length - 3} más` : txt;
}

function detalle(s) {
  openDrawer({
    title: `${origen(s)}, ${fechaHora(s.at)}`,
    noSubmit: true,
    body: html`
      <div class="table-wrap card"><table class="table">
        <thead><tr><th>Producto</th><th class="r">Cant.</th><th class="r">Importe</th></tr></thead>
        <tbody>${(s.lines || []).map((l) => html`<tr><td>${l.name}</td><td class="r">${qty(l.qty)}</td><td class="r">${usd(l.lineUsd)}</td></tr>`)}</tbody>
        <tfoot><tr><td colspan="2">Total</td><td class="r">${usd(s.total_usd)}</td></tr></tfoot>
      </table></div>
      <div><div class="section-title" style="margin-bottom:8px">Pagos</div>
      <dl class="kv">${(s.payments || []).map((p) => html`<div><dt>${p.method}${p.reference ? html`<div class="muted small">Ref. ${p.reference}</div>` : ''}</dt><dd>${usd(p.amountUsd)}<div class="muted small">${bs(toBs(p.amountUsd))}</div></dd></div>`)}</dl></div>
      <p class="muted small">Registrada el ${fecha(s.at)} a las ${hora(s.at)}. Equivalente en bolívares con la tasa de hoy (${num(S.config.rate)} Bs).</p>`,
  });
}

function mount(root, ctx) {
  root.addEventListener('click', async (e) => {
    const b = e.target.closest('[data-seg="preset"] button');
    if (b) { st.preset = b.dataset.v; await load(); ctx.rerender(); return; }
    if (e.target.closest('[data-act="csv"]')) {
      const rows = filtered();
      downloadCSV(`ventas_${st.preset}.csv`, [
        ['Fecha', 'Hora', 'Origen', 'Productos', 'Pagos', 'Total USD', 'Total Bs (tasa de hoy)'],
        ...rows.map((s) => [fecha(s.at), hora(s.at), origen(s), (s.lines || []).map((l) => `${l.qty} x ${l.name}`).join(' | '),
          (s.payments || []).map((p) => `${p.method} ${Number(p.amountUsd).toFixed(2)}${p.reference ? ' ref ' + p.reference : ''}`).join(' | '),
          Number(s.total_usd).toFixed(2), toBs(s.total_usd).toFixed(2)]),
      ]);
      return;
    }
    const tr = e.target.closest('tr[data-id]');
    if (tr) { const s = st.rows.find((x) => x.id === tr.dataset.id); if (s) detalle(s); }
  }, { signal: ctx.signal });
  root.addEventListener('keydown', (e) => { if (e.key === 'Enter' && e.target.matches('tr[data-id]')) e.target.click(); }, { signal: ctx.signal });
  root.addEventListener('change', async (e) => {
    const k = e.target.dataset.k;
    if (k === 'desde' || k === 'hasta') { st[k] = e.target.value; await load(); ctx.rerender(); }
  }, { signal: ctx.signal });
  const onQ = debounce(() => { ctx.rerender(); const i = root.querySelector('[data-k="q"]'); if (i) { i.focus(); i.setSelectionRange(i.value.length, i.value.length); } }, 250);
  root.addEventListener('input', (e) => { if (e.target.dataset.k === 'q') { st.q = e.target.value; onQ(); } }, { signal: ctx.signal });
}

export default {
  path: 'ventas', title: 'Ventas', icon: 'receipt',
  subtitle: () => 'Cuentas cobradas',
  load, reload: async () => { if (st.preset === 'turno' || st.preset === 'hoy') await load(); },
  render, mount,
};

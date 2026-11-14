// Anulaciones de comandas y perdidas por mercancia usada.
import { html, usd, bs, num, fecha, hora, downloadCSV } from '../util.js';
import { icon } from '../icons.js';
import { S, toBs, sum } from '../store.js';
import { tile, empty, seg, presetRange, rangeInputs, inRange, listen } from './common.js';

const PRE = [['turno', 'Turno actual'], ['hoy', 'Hoy'], ['30', '30 días'], ['mes', 'Este mes'], ['todo', 'Todo'], ['rango', 'Fechas…']];
const st = { preset: '30', desde: '', hasta: '' };
const donde = (c) => (c.table_number ? `Mesa ${c.table_number}` : c.takeaway_name ? `Para llevar: ${c.takeaway_name}` : 'Para llevar');

function lista() { st.range = presetRange(st.preset, st.desde, st.hasta); return S.cancellations.filter((c) => inRange(c.at, st.range)); }

function render() {
  const rows = lista();
  const perdidas = rows.filter((c) => c.merchandise_used);
  const perdida = sum(perdidas, (c) => c.value_usd);
  return html`
  <div class="toolbar">${seg('preset', PRE, st.preset)}${rangeInputs(st)}<div class="grow"></div>
    <button class="btn btn-sm" data-act="csv">${icon('download', 16)}Exportar</button></div>
  <p class="muted small" style="margin:-6px 0 12px">${st.range.label}</p>
  <div class="tiles">
    ${tile('Pérdida por mercancía usada', usd(perdida), bs(toBs(perdida)), { cls: perdida > 0 ? 'neg' : '' })}
    ${tile('Comandas anuladas', num(rows.length, 0))}
    ${tile('Con mercancía usada', num(perdidas.length, 0), 'Se preparó algo que no se cobró')}
  </div>
  <section class="card card-flush">
    ${rows.length ? html`<div class="table-wrap"><table class="table">
      <thead><tr><th>Fecha</th><th>Comanda</th><th>Dónde</th><th>Motivo</th><th>Anuló</th><th>Mercancía</th><th class="r">Pérdida</th></tr></thead>
      <tbody>${rows.map((c) => html`<tr>
        <td class="nowrap"><div class="t-main">${fecha(c.at)}</div><div class="t-sub">${hora(c.at)}</div></td>
        <td class="mono">#${String(c.ticket_number || 0).padStart(6, '0')}</td>
        <td class="nowrap">${donde(c)}</td>
        <td>${c.reason || html`<span class="muted">Sin motivo</span>`}</td>
        <td class="muted">${c.by_user || '—'}</td>
        <td>${c.merchandise_used ? html`<span class="badge bad">${icon('alert', 14)}Usada</span>` : html`<span class="badge neutral">Sin usar</span>`}</td>
        <td class="r ${c.merchandise_used ? 'neg' : 'muted'}">${c.merchandise_used ? usd(c.value_usd) : '—'}</td></tr>`)}</tbody>
    </table></div>` : empty('Sin anulaciones en este periodo')}
  </section>`;
}

function mount(root, ctx) {
  listen(root, ctx, {
    click(e) {
      const b = e.target.closest('[data-seg="preset"] button');
      if (b) { st.preset = b.dataset.v; ctx.rerender(); return; }
      if (e.target.closest('[data-act="csv"]')) {
        downloadCSV('anulaciones.csv', [['Fecha', 'Hora', 'Comanda', 'Dónde', 'Motivo', 'Anuló', 'Mercancía usada', 'Pérdida USD'],
          ...lista().map((c) => [fecha(c.at), hora(c.at), c.ticket_number, donde(c), c.reason || '', c.by_user || '', c.merchandise_used ? 'Sí' : 'No', c.merchandise_used ? Number(c.value_usd).toFixed(2) : '0'])]);
      }
    },
    change(e) { const k = e.target.dataset.k; if (k === 'desde' || k === 'hasta') { st[k] = e.target.value; ctx.rerender(); } },
  });
}

export default { path: 'anulaciones', title: 'Anulaciones', icon: 'ban', subtitle: () => 'Comandas anuladas y pérdidas', render, mount };

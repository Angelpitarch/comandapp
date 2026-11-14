// Reportes por semana o mes: ventas, costo, gastos y ganancia, por dia, metodo y producto.
import { html, usd, bs, qty, num, addDays, dayKey, DIAS, MESES, compact, downloadCSV, fecha } from '../util.js';
import { icon } from '../icons.js';
import { columns, legend, hbars } from '../charts.js';
import { S, summarize, salesCost, salesBetween, sum, toBs } from '../store.js';
import { seg, empty, calendarPeriod, listen } from './common.js';

const st = { modo: 'semana', offset: 0, ventas: [] };
const SERIES = [{ name: 'Ventas', cls: 'bar-1' }, { name: 'Gastos', cls: 'bar-2' }];

async function load() {
  st.p = calendarPeriod(st.modo, st.offset);
  st.ventas = await salesBetween(st.p.from, st.p.to);
}

function datos() {
  const { from, to, days } = st.p;
  const gastos = S.gastos.filter((g) => new Date(g.at) >= from && new Date(g.at) < to);
  const r = summarize(st.ventas);
  const costo = salesCost(st.ventas);
  const totalGastos = sum(gastos, (g) => g.amount_usd);
  const dias = Array.from({ length: days }, (_, i) => addDays(from, i));
  const v = new Map(), g = new Map(), c = new Map();
  for (const s of st.ventas) { const k = dayKey(s.at); v.set(k, (v.get(k) || 0) + Number(s.total_usd || 0)); c.set(k, (c.get(k) || 0) + 1); }
  for (const x of gastos) { const k = dayKey(x.at); g.set(k, (g.get(k) || 0) + Number(x.amount_usd || 0)); }
  return {
    r, costo, totalGastos, gastos,
    ganancia: r.total - costo, neta: r.total - costo - totalGastos,
    dias,
    labels: dias.map((d) => (st.modo === 'semana' ? `${DIAS[d.getDay()]} ${d.getDate()}` : String(d.getDate()))),
    titles: dias.map((d) => `${DIAS[d.getDay()]} ${d.getDate()} de ${MESES[d.getMonth()]}`),
    ventasDia: dias.map((d) => v.get(dayKey(d)) || 0),
    gastosDia: dias.map((d) => g.get(dayKey(d)) || 0),
    cuentasDia: dias.map((d) => c.get(dayKey(d)) || 0),
  };
}

function render() {
  const d = datos();
  const top = [...d.r.units.entries()].sort((a, b) => b[1] - a[1]).slice(0, 10).map(([label, value]) => ({ label, value, sub: usd(d.r.revenue.get(label) || 0) }));
  const metodos = [...d.r.byMethod.entries()].sort((a, b) => b[1] - a[1]).map(([label, value]) => ({ label, value, sub: bs(toBs(value)) }));
  const conMov = d.dias.map((x, i) => i).filter((i) => d.ventasDia[i] || d.gastosDia[i]).reverse();
  return html`
  <div class="toolbar">
    ${seg('modo', [['semana', 'Semana'], ['mes', 'Mes']], st.modo)}
    <div class="row">
      <button class="icon-btn bordered" data-act="prev" aria-label="Periodo anterior">${icon('left')}</button>
      <b style="min-width:190px;text-align:center">${st.p.label}</b>
      <button class="icon-btn bordered" data-act="next" aria-label="Periodo siguiente" ${st.offset >= 0 ? 'disabled' : ''}>${icon('right')}</button>
    </div>
    <div class="grow"></div>
    <button class="btn btn-sm" data-act="csv">${icon('download', 16)}Exportar por día</button>
    <button class="btn btn-sm" data-act="print">${icon('print', 16)}Imprimir</button>
  </div>

  <div class="grid-2" style="margin-bottom:16px">
    <section class="card">
      <div class="card-head"><div><h2>Ventas y gastos por día</h2><p>${st.p.label}, en dólares</p></div>${legend(SERIES)}</div>
      <div class="card-body"><div class="chart" id="chart-rep"></div></div>
    </section>
    <section class="card">
      <div class="card-head"><div><h2>Resultado del periodo</h2><p>${num(d.r.count, 0)} ${d.r.count === 1 ? 'cuenta cobrada' : 'cuentas cobradas'}</p></div></div>
      <div class="card-body"><dl class="kv">
        <div><dt>Ventas</dt><dd>${usd(d.r.total)}</dd></div>
        <div><dt>Costo estimado de lo vendido</dt><dd>− ${usd(d.costo)}</dd></div>
        <div class="total"><dt class="k">Ganancia bruta</dt><dd class="v">${usd(d.ganancia)}</dd></div>
        <div><dt>Gastos</dt><dd>− ${usd(d.totalGastos)}</dd></div>
        <div class="total"><dt class="k">Ganancia neta</dt><dd class="v ${d.neta < 0 ? 'neg' : 'pos'}">${usd(d.neta)}</dd></div>
        <div><dt>Ganancia neta en Bs</dt><dd class="muted">${bs(toBs(d.neta))}</dd></div>
        <div><dt>Margen neto</dt><dd>${d.r.total > 0 ? num((d.neta / d.r.total) * 100, 1) + '%' : '—'}</dd></div>
      </dl>
      <p class="muted small" style="margin-top:10px">El costo usa los precios de compra actuales de los ingredientes, no los de esa fecha. Los montos en Bs usan la tasa de hoy.</p></div>
    </section>
  </div>

  <div class="grid-2e" style="margin-bottom:16px">
    <section class="card"><div class="card-head"><div><h2>Productos más vendidos</h2><p>Unidades; al lado, lo cobrado</p></div></div>
      <div class="card-body">${hbars(top, qty)}</div></section>
    <section class="card"><div class="card-head"><div><h2>Por método de pago</h2><p>Monto cobrado en dólares</p></div></div>
      <div class="card-body">${hbars(metodos, usd)}</div></section>
  </div>

  <section class="card card-flush">
    <div class="card-head" style="padding-bottom:12px"><div><h2>Detalle por día</h2><p>Solo días con movimiento</p></div></div>
    ${conMov.length ? html`<div class="table-wrap"><table class="table">
      <thead><tr><th>Día</th><th class="r">Cuentas</th><th class="r">Ventas</th><th class="r">Gastos</th><th class="r">Ventas menos gastos</th></tr></thead>
      <tbody>${conMov.map((i) => { const n = d.ventasDia[i] - d.gastosDia[i]; return html`<tr>
        <td>${d.titles[i]}</td><td class="r">${d.cuentasDia[i]}</td><td class="r">${usd(d.ventasDia[i])}</td><td class="r">${usd(d.gastosDia[i])}</td>
        <td class="r ${n < 0 ? 'neg' : ''}">${usd(n)}</td></tr>`; })}</tbody>
      <tfoot><tr><td>Total</td><td class="r">${d.r.count}</td><td class="r">${usd(d.r.total)}</td><td class="r">${usd(d.totalGastos)}</td><td class="r">${usd(d.r.total - d.totalGastos)}</td></tr></tfoot>
    </table></div>` : empty('Sin movimientos en este periodo', 'Usa las flechas para ver periodos anteriores.')}
  </section>`;
}

function mount(root, ctx) {
  const d = datos();
  columns(root.querySelector('#chart-rep'), {
    labels: d.labels, titles: d.titles,
    series: [{ ...SERIES[0], values: d.ventasDia }, { ...SERIES[1], values: d.gastosDia }],
    fmt: usd, tick: (v) => '$' + compact(v), height: 260,
  });
  listen(root, ctx, {
    async click(e) {
      const b = e.target.closest('[data-seg="modo"] button');
      if (b) { st.modo = b.dataset.v; st.offset = 0; await load(); ctx.rerender(); return; }
      const act = e.target.closest('[data-act]')?.dataset.act;
      if (act === 'prev') { st.offset--; await load(); ctx.rerender(); }
      if (act === 'next' && st.offset < 0) { st.offset++; await load(); ctx.rerender(); }
      if (act === 'print') window.print();
      if (act === 'csv') {
        const x = datos();
        downloadCSV(`reporte_${st.modo}_${dayKey(st.p.from)}.csv`, [
          ['Día', 'Cuentas', 'Ventas USD', 'Gastos USD', 'Ventas menos gastos USD'],
          ...x.dias.map((dd, i) => [fecha(dd), x.cuentasDia[i], x.ventasDia[i].toFixed(2), x.gastosDia[i].toFixed(2), (x.ventasDia[i] - x.gastosDia[i]).toFixed(2)]),
        ]);
      }
    },
  });
}

export default {
  path: 'reportes', title: 'Reportes', icon: 'chart',
  subtitle: () => 'Resultados por semana o por mes',
  load, reload: async () => { if (st.offset === 0) await load(); }, render, mount,
};

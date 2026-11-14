// Resumen: el turno actual de un vistazo.
import { html, usd, bs, num, qty, fecha, hora, addDays, startOfDay, dayKey, DIAS, MESES, compact } from '../util.js';
import { icon } from '../icons.js';
import { columns, legend, hbars } from '../charts.js';
import {
  S, summarize, salesCost, gastosSince, lastCloseAt, sum, toBs, openAccountsUsd, lowIngredients, lowProducts, salesBetween,
} from '../store.js';
import { tile, empty, stockBadge } from './common.js';

let last14 = [];
const range14 = () => { const hoy = startOfDay(new Date()); return [addDays(hoy, -13), addDays(hoy, 1)]; };

async function load() { const [a, b] = range14(); last14 = await salesBetween(a, b); }

function render() {
  const lc = lastCloseAt();
  const r = summarize(S.turnoSales);
  const costo = salesCost(S.turnoSales);
  const gastos = sum(gastosSince(lc), (g) => g.amount_usd);
  const neta = r.total - costo - gastos;
  // misma regla que la app: una mesa esta ocupada si tiene cuenta abierta o esta cobrada sin liberar
  const ocupadas = S.tables.filter((t) => ['pago_espera', 'pago_servido', 'pagada'].includes(t.status) || S.accountItems.some((a) => a.table_number === t.number)).length;
  const enCocina = S.openTickets.filter((t) => t.status === 'nueva' || t.status === 'preparando').length;
  const listas = S.openTickets.filter((t) => t.status === 'lista').length;
  const llevar = S.takeaways.filter((t) => t.status !== 'pagada').length;
  const top = [...r.units.entries()].sort((a, b) => b[1] - a[1]).slice(0, 8)
    .map(([label, value]) => ({ label, value, sub: usd(r.revenue.get(label) || 0) }));
  const metodos = [...r.byMethod.entries()].sort((a, b) => b[1] - a[1]);
  const bajos = lowIngredients().sort((a, b) => a.stock - b.stock);
  const prodBajos = lowProducts(5);

  return html`
  <div class="tiles">
    ${tile('Ventas del turno', usd(r.total), `${bs(toBs(r.total))}, ${r.count} ${r.count === 1 ? 'cuenta cobrada' : 'cuentas cobradas'}`, { hero: true })}
    ${tile('Ticket promedio', usd(r.count ? r.total / r.count : 0), 'Por cuenta cobrada')}
    ${tile('Gastos del turno', usd(gastos), bs(toBs(gastos)))}
    ${tile('Ganancia neta estimada', usd(neta), `Ventas menos costo (${usd(costo)}) y gastos`, { cls: neta < 0 ? 'neg' : '' })}
  </div>

  <section class="card" style="margin-bottom:16px" aria-label="Operación en este momento">
    <div class="ops">
      <div><div class="o-value">${ocupadas} <span class="muted small">de ${S.tables.length}</span></div><div class="o-label">Mesas ocupadas</div></div>
      <div><div class="o-value">${enCocina}</div><div class="o-label">Comandas en cocina${listas ? html`, <b>${listas}</b> listas para servir` : ''}</div></div>
      <div><div class="o-value">${llevar}</div><div class="o-label">Pedidos para llevar abiertos</div></div>
      <div><div class="o-value">${usd(openAccountsUsd())}</div><div class="o-label">Por cobrar en cuentas abiertas</div></div>
    </div>
  </section>

  <div class="grid-2" style="margin-bottom:16px">
    <section class="card">
      <div class="card-head"><div><h2>Ventas y gastos por día</h2><p>Últimos 14 días, en dólares</p></div>${legend(SERIES)}</div>
      <div class="card-body">
        <div class="chart" id="chart14"></div>
        <details class="as-table"><summary>Ver como tabla</summary>${tabla14()}</details>
      </div>
    </section>
    <section class="card">
      <div class="card-head"><div><h2>Más vendidos del turno</h2><p>Unidades vendidas; al lado, lo cobrado</p></div></div>
      <div class="card-body">${top.length ? hbars(top, (v) => qty(v)) : empty('Sin ventas en este turno', 'Cuando se cobre la primera cuenta aparecerá aquí.')}</div>
    </section>
  </div>

  <div class="grid-2e">
    <section class="card">
      <div class="card-head"><div><h2>Inventario por revisar</h2><p>Ingredientes en su mínimo y productos que alcanzan para 5 o menos</p></div><a class="btn btn-sm" href="#/inventario">Ver inventario</a></div>
      <div class="card-body">
        ${!bajos.length && !prodBajos.length ? empty('Todo en orden', 'Ningún ingrediente está en su stock mínimo.') : html`<div class="alerts">
          ${bajos.map((i) => html`<div><span>${i.emoji}</span><span class="a-name">${i.name}</span><span class="muted small num">${qty(i.stock)} ${i.unit}</span>${stockBadge(i.stock, i.min_stock)}</div>`)}
          ${prodBajos.map(({ p, m }) => html`<div><span>${p.emoji}</span><span class="a-name">${p.name}</span><span class="muted small">${m === 0 ? 'no alcanza' : `alcanza para ${m}`}</span><span class="badge ${m === 0 ? 'bad' : 'warn'}">${icon(m === 0 ? 'xCircle' : 'alert', 14)}Producto</span></div>`)}
        </div>`}
      </div>
    </section>
    <section class="card">
      <div class="card-head"><div><h2>Cobrado por método de pago</h2><p>${lc ? `Desde el cierre del ${fecha(lc)} a las ${hora(lc)}` : 'Desde el inicio'}</p></div><a class="btn btn-sm" href="#/caja">Ir a caja</a></div>
      <div class="card-body">
        ${metodos.length ? html`<dl class="kv">${metodos.map(([m, v]) => html`<div><dt>${m}</dt><dd>${usd(v)} <span class="muted">${bs(toBs(v))}</span></dd></div>`)}
          <div class="total"><dt class="k">Total</dt><dd class="v">${usd(r.total)}</dd></div></dl>` : empty('Sin cobros en este turno')}
      </div>
    </section>
  </div>`;
}

const SERIES = [{ name: 'Ventas', cls: 'bar-1' }, { name: 'Gastos', cls: 'bar-2' }];
function data14() {
  const [a] = range14();
  const days = Array.from({ length: 14 }, (_, i) => addDays(a, i));
  const v = new Map(), g = new Map();
  for (const s of last14) v.set(dayKey(s.at), (v.get(dayKey(s.at)) || 0) + Number(s.total_usd || 0));
  for (const x of S.gastos) g.set(dayKey(x.at), (g.get(dayKey(x.at)) || 0) + Number(x.amount_usd || 0));
  return {
    days,
    labels: days.map((d) => `${DIAS[d.getDay()]} ${d.getDate()}`),
    titles: days.map((d) => `${DIAS[d.getDay()]} ${d.getDate()} de ${MESES[d.getMonth()]}`),
    ventas: days.map((d) => v.get(dayKey(d)) || 0),
    gastos: days.map((d) => g.get(dayKey(d)) || 0),
  };
}
function tabla14() {
  const d = data14();
  return html`<div class="table-wrap"><table class="table"><thead><tr><th>Día</th><th class="r">Ventas</th><th class="r">Gastos</th></tr></thead><tbody>
    ${d.days.map((x, i) => html`<tr><td>${d.titles[i]}</td><td class="r">${usd(d.ventas[i])}</td><td class="r">${usd(d.gastos[i])}</td></tr>`).reverse()}
  </tbody></table></div>`;
}

function mount(root) {
  const el = root.querySelector('#chart14');
  const d = data14();
  columns(el, {
    labels: d.labels, titles: d.titles,
    series: [{ ...SERIES[0], values: d.ventas }, { ...SERIES[1], values: d.gastos }],
    fmt: usd, tick: (v) => '$' + compact(v),
  });
}

export default {
  path: 'resumen', title: 'Resumen', icon: 'home',
  subtitle: () => { const lc = lastCloseAt(); return lc ? `Turno abierto desde el cierre del ${fecha(lc)} a las ${hora(lc)}` : 'Aún no hay cierres de caja: se muestra todo lo vendido'; },
  load, reload: load, render, mount,
};
export { num };

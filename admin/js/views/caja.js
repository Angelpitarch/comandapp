// Caja: turno actual, cierre de caja y historial de cierres.
import { html, usd, bs, qty, num, fecha, hora, toast, confirmDialog, openDrawer, downloadCSV } from '../util.js';
import { icon } from '../icons.js';
import { S, summarize, gastosSince, lastCloseAt, sum, toBs, pendingToClose, cerrarCaja, loadAll, emit } from '../store.js';
import { tile, empty, listen } from './common.js';

function render() {
  const lc = lastCloseAt();
  const r = summarize(S.turnoSales);
  const gastos = sum(gastosSince(lc), (g) => g.amount_usd);
  const pend = pendingToClose();
  const bloqueado = pend.mesas.length > 0 || pend.llevar.length > 0;
  const metodos = [...r.byMethod.entries()].sort((a, b) => b[1] - a[1]);
  return html`
  <div class="tiles">
    ${tile('Vendido en el turno', usd(r.total), bs(toBs(r.total)), { hero: true })}
    ${tile('Cuentas cobradas', num(r.count, 0))}
    ${tile('Gastos del turno', usd(gastos), bs(toBs(gastos)))}
    ${tile('Ventas menos gastos', usd(r.total - gastos), bs(toBs(r.total - gastos)), { cls: r.total - gastos < 0 ? 'neg' : '' })}
  </div>

  <div class="grid-2e" style="margin-bottom:16px">
    <section class="card">
      <div class="card-head"><div><h2>Cierre de caja</h2><p>${lc ? `Turno abierto desde el ${fecha(lc)} a las ${hora(lc)}` : 'Todavía no se ha hecho ningún cierre'}</p></div></div>
      <div class="card-body stack">
        ${bloqueado ? html`<div class="note warn"><b>Todavía no se puede cerrar.</b> Falta cobrar o anular:
            <ul style="margin:6px 0 0;padding-left:18px">
              ${pend.mesas.map((t) => html`<li>Mesa ${t.number}${t.waiter ? `, atendida por ${t.waiter}` : ''}</li>`)}
              ${pend.llevar.map((t) => html`<li>Para llevar: ${t.name || 'sin nombre'}</li>`)}
            </ul></div>`
          : html`<p class="text-2">Guarda el resumen del turno en el historial y deja mesas, pedidos y comandas listos para el próximo turno. Las ventas, los gastos y el historial no se borran.</p>`}
        <div><button class="btn ${bloqueado ? '' : 'btn-primary'}" data-act="cerrar" ${bloqueado ? 'disabled' : ''}>${icon('register', 16)}Cerrar caja</button></div>
      </div>
    </section>
    <section class="card">
      <div class="card-head"><div><h2>Cobrado por método</h2><p>En este turno</p></div></div>
      <div class="card-body">${metodos.length ? html`<dl class="kv">
        ${metodos.map(([m, v]) => html`<div><dt>${m}</dt><dd>${usd(v)} <span class="muted">${bs(toBs(v))}</span></dd></div>`)}
        <div class="total"><dt class="k">Total</dt><dd class="v">${usd(r.total)}</dd></div></dl>` : empty('Sin cobros en este turno')}</div>
    </section>
  </div>

  <section class="card card-flush">
    <div class="card-head" style="padding-bottom:12px"><div><h2>Historial de cierres</h2><p>${S.closes.length} ${S.closes.length === 1 ? 'cierre' : 'cierres'} registrados</p></div>
      ${S.closes.length ? html`<button class="btn btn-sm" data-act="csv">${icon('download', 16)}Exportar</button>` : ''}</div>
    ${S.closes.length ? html`<div class="table-wrap"><table class="table">
      <thead><tr><th>Cerrado</th><th>Desde</th><th class="r">Cuentas</th><th class="r">Vendido</th><th class="r">Gastos</th><th class="r">Ventas menos gastos</th></tr></thead>
      <tbody>${S.closes.map((c) => html`<tr class="clickable" data-id="${c.id}" tabindex="0">
        <td class="nowrap"><div class="t-main">${fecha(c.closed_at)}</div><div class="t-sub">${hora(c.closed_at)}</div></td>
        <td class="nowrap muted">${c.from_at ? `${fecha(c.from_at)} ${hora(c.from_at)}` : 'Inicio'}</td>
        <td class="r">${c.accounts_count}</td><td class="r t-main">${usd(c.total_usd)}</td><td class="r">${usd(c.gastos_usd || 0)}</td>
        <td class="r">${usd(Number(c.total_usd) - Number(c.gastos_usd || 0))}</td></tr>`)}</tbody>
    </table></div>` : empty('Aún no hay cierres de caja', 'El primero aparecerá aquí cuando cierres la caja.')}
  </section>`;
}

function detalle(c) {
  const metodos = Object.entries(c.by_method || {}).sort((a, b) => b[1] - a[1]);
  const unidades = Object.entries(c.units || {}).sort((a, b) => b[1] - a[1]);
  openDrawer({
    title: `Cierre del ${fecha(c.closed_at)} a las ${hora(c.closed_at)}`,
    noSubmit: true,
    body: html`
      <dl class="kv">
        <div><dt>Periodo</dt><dd>${c.from_at ? `${fecha(c.from_at)} ${hora(c.from_at)}` : 'Desde el inicio'} al ${fecha(c.closed_at)} ${hora(c.closed_at)}</dd></div>
        <div><dt>Cuentas cobradas</dt><dd>${c.accounts_count}</dd></div>
        <div><dt>Vendido</dt><dd>${usd(c.total_usd)}</dd></div>
        <div><dt>Gastos</dt><dd>${usd(c.gastos_usd || 0)}</dd></div>
        <div class="total"><dt class="k">Ventas menos gastos</dt><dd class="v">${usd(Number(c.total_usd) - Number(c.gastos_usd || 0))}</dd></div>
      </dl>
      <div><div class="section-title" style="margin-bottom:8px">Por método de pago</div>
        ${metodos.length ? html`<dl class="kv">${metodos.map(([m, v]) => html`<div><dt>${m}</dt><dd>${usd(v)}</dd></div>`)}</dl>` : html`<p class="muted">Sin cobros</p>`}</div>
      <div><div class="section-title" style="margin-bottom:8px">Unidades vendidas</div>
        ${unidades.length ? html`<dl class="kv">${unidades.map(([m, v]) => html`<div><dt>${m}</dt><dd>${qty(v)}</dd></div>`)}</dl>` : html`<p class="muted">Sin ventas</p>`}</div>`,
  });
}

function mount(root, ctx) {
  listen(root, ctx, {
    async click(e) {
      const act = e.target.closest('[data-act]')?.dataset.act;
      if (act === 'cerrar') {
        const r = summarize(S.turnoSales);
        const gastos = sum(gastosSince(lastCloseAt()), (g) => g.amount_usd);
        const ok = await confirmDialog({
          title: 'Cerrar la caja',
          body: html`<dl class="kv">
              <div><dt>Vendido</dt><dd>${usd(r.total)}</dd></div>
              <div><dt>Cuentas cobradas</dt><dd>${r.count}</dd></div>
              <div><dt>Gastos</dt><dd>${usd(gastos)}</dd></div>
              <div class="total"><dt class="k">Ventas menos gastos</dt><dd class="v">${usd(r.total - gastos)}</dd></div></dl>
            <p>Se reinician mesas, pedidos para llevar y comandas en todos los teléfonos. Las ventas y el historial se conservan.</p>`,
          confirm: 'Cerrar caja',
        });
        if (!ok) return;
        try {
          await loadAll(); // datos frescos antes de comprobar
          const p = pendingToClose();
          if (p.mesas.length || p.llevar.length) { toast('Alguien abrió una cuenta mientras tanto. Revisa la lista de pendientes.', 'bad'); emit(); return; }
          await cerrarCaja();
          await loadAll();
          emit();
          toast('Caja cerrada. Mesas, pedidos y comandas reiniciados.');
        } catch (ex) { toast('No se pudo cerrar la caja: ' + ex.message, 'bad'); }
        return;
      }
      if (act === 'csv') {
        downloadCSV('cierres_de_caja.csv', [
          ['Cerrado', 'Desde', 'Cuentas', 'Vendido USD', 'Gastos USD', 'Ventas menos gastos USD'],
          ...S.closes.map((c) => [`${fecha(c.closed_at)} ${hora(c.closed_at)}`, c.from_at ? `${fecha(c.from_at)} ${hora(c.from_at)}` : '', c.accounts_count,
            Number(c.total_usd).toFixed(2), Number(c.gastos_usd || 0).toFixed(2), (Number(c.total_usd) - Number(c.gastos_usd || 0)).toFixed(2)]),
        ]);
        return;
      }
      const tr = e.target.closest('tr[data-id]');
      if (tr) { const c = S.closes.find((x) => x.id === tr.dataset.id); if (c) detalle(c); }
    },
  });
}

export default { path: 'caja', title: 'Caja', icon: 'register', subtitle: () => 'Turno actual e historial de cierres', render, mount };

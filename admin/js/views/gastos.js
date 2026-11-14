// Gastos del negocio: registro, filtros por periodo y resumen por categoria.
import { html, usd, bs, num, parseNum, fecha, hora, inputDateTime, openDrawer, confirmDialog, toast, debounce, downloadCSV } from '../util.js';
import { icon } from '../icons.js';
import { db, f } from '../api.js';
import { S, load as L, toBs, emit, GASTO_CATS, METODOS, sum, rate } from '../store.js';
import { tile, empty, seg, presetRange, rangeInputs, inRange, listen, keepFocus } from './common.js';
import { hbars } from '../charts.js';

const PRE = [['turno', 'Turno actual'], ['hoy', 'Hoy'], ['30', '30 días'], ['mes', 'Este mes'], ['todo', 'Todo'], ['rango', 'Fechas…']];
const st = { preset: 'turno', desde: '', hasta: '', q: '', cat: '' };

function lista() {
  const r = presetRange(st.preset, st.desde, st.hasta);
  st.range = r;
  const q = st.q.toLowerCase();
  return S.gastos.filter((g) => inRange(g.at, r) && (!st.cat || g.category === st.cat)
    && (!q || `${g.concept} ${g.note || ''} ${g.payment_method || ''} ${g.by_user || ''}`.toLowerCase().includes(q)));
}

function render() {
  const rows = lista();
  const total = sum(rows, (g) => g.amount_usd);
  const porCat = new Map();
  for (const g of rows) porCat.set(g.category, (porCat.get(g.category) || 0) + Number(g.amount_usd || 0));
  const cats = [...porCat.entries()].sort((a, b) => b[1] - a[1]).map(([k, v]) => ({ label: GASTO_CATS[k] || k, value: v }));
  return html`
  <div class="toolbar">
    ${seg('preset', PRE, st.preset)}
    ${rangeInputs(st)}
    <div class="grow"></div>
    <button class="btn btn-sm" data-act="csv">${icon('download', 16)}Exportar</button>
    <button class="btn btn-primary" data-act="nuevo">${icon('plus', 16)}Nuevo gasto</button>
  </div>
  <p class="muted small" style="margin:-6px 0 12px">${st.range.label}</p>
  <div class="grid-2" style="margin-bottom:16px">
    <div class="tiles two" style="margin:0;align-content:start">
      ${tile('Total de gastos', usd(total), bs(toBs(total)), { hero: true })}
      ${tile('Registros', num(rows.length, 0))}
      ${tile('Gasto promedio', usd(rows.length ? total / rows.length : 0))}
    </div>
    <section class="card"><div class="card-head"><div><h2>Por categoría</h2><p>En dólares</p></div></div>
      <div class="card-body">${hbars(cats, usd)}</div></section>
  </div>
  <div class="toolbar">
    <label class="search">${icon('search', 16)}<span class="sr-only">Buscar gasto</span><input class="input sm" type="search" data-k="q" placeholder="Buscar concepto, nota o pago" value="${st.q}"></label>
    <select class="input sm" data-k="cat" style="width:auto" aria-label="Categoría"><option value="">Todas las categorías</option>
      ${Object.entries(GASTO_CATS).map(([k, v]) => html`<option value="${k}" ${st.cat === k ? 'selected' : ''}>${v}</option>`)}</select>
  </div>
  <section class="card card-flush">
    ${rows.length ? html`<div class="table-wrap"><table class="table">
      <thead><tr><th>Fecha</th><th>Concepto</th><th>Categoría</th><th>Pagado con</th><th>Registró</th><th class="r">Monto</th><th class="r">En Bs</th></tr></thead>
      <tbody>${rows.map((g) => html`<tr class="clickable" data-id="${g.id}" tabindex="0">
        <td class="nowrap"><div class="t-main">${fecha(g.at)}</div><div class="t-sub">${hora(g.at)}</div></td>
        <td><div class="t-main">${g.concept || '(sin concepto)'}</div>${g.note ? html`<div class="t-sub">${g.note}</div>` : ''}</td>
        <td><span class="tag">${GASTO_CATS[g.category] || g.category}</span></td>
        <td>${g.payment_method || html`<span class="muted">—</span>`}</td>
        <td class="muted">${g.by_user || '—'}</td>
        <td class="r t-main">${usd(g.amount_usd)}</td><td class="r muted">${bs(toBs(g.amount_usd))}</td></tr>`)}</tbody>
      <tfoot><tr><td colspan="5">${rows.length} ${rows.length === 1 ? 'gasto' : 'gastos'}</td><td class="r">${usd(total)}</td><td class="r">${bs(toBs(total))}</td></tr></tfoot>
    </table></div>` : empty('No hay gastos en este periodo', 'Registra uno con "Nuevo gasto".')}
  </section>`;
}

function form(g) {
  const nuevo = !g;
  g = g || { concept: '', category: 'otros', amount_usd: '', payment_method: '', note: '', at: new Date().toISOString() };
  openDrawer({
    title: nuevo ? 'Nuevo gasto' : 'Editar gasto',
    submitLabel: nuevo ? 'Registrar gasto' : 'Guardar cambios',
    extraFoot: nuevo ? '' : html`<button type="button" class="btn btn-danger left" data-borrar>${icon('trash', 16)}Eliminar</button>`,
    body: html`<div class="form-grid">
      <div class="field full"><label for="g-c">Concepto</label><input class="input" id="g-c" name="concept" value="${g.concept}" placeholder="Ej: pan, gas, bolsas" required></div>
      <div class="field"><label for="g-cat">Categoría</label><select class="input" id="g-cat" name="category">${Object.entries(GASTO_CATS).map(([k, v]) => html`<option value="${k}" ${k === g.category ? 'selected' : ''}>${v}</option>`)}</select></div>
      <div class="field"><label for="g-at">Fecha y hora</label><input class="input" id="g-at" name="at" type="datetime-local" value="${inputDateTime(g.at)}"></div>
      <div class="field"><label for="g-m">Monto</label><div class="input-group"><input class="input" id="g-m" name="monto" inputmode="decimal" value="${g.amount_usd === '' ? '' : num(g.amount_usd)}" required>
        <select class="input" name="moneda" style="width:84px;border-radius:0 8px 8px 0;border-left:0" aria-label="Moneda"><option value="usd">USD</option><option value="ves">Bs</option></select></div>
        <span class="hint" id="g-eq"></span></div>
      <div class="field"><span class="label">Pagado con</span><div class="chips" id="g-met">
        ${METODOS.map((m) => html`<button type="button" class="chip" data-m="${m}" aria-pressed="${String(g.payment_method === m)}">${m}</button>`)}</div>
        <input type="hidden" name="payment_method" value="${g.payment_method || ''}"></div>
      <div class="field full"><label for="g-n">Nota (opcional)</label><textarea class="input" id="g-n" name="note" rows="3">${g.note || ''}</textarea></div>
    </div>`,
    onMount(frm, close) {
      const eq = () => {
        const v = parseNum(frm.monto.value) || 0;
        frm.querySelector('#g-eq').textContent = frm.moneda.value === 'ves'
          ? `Equivale a ${usd(rate() > 0 ? v / rate() : 0)} (tasa ${num(rate())} Bs)` : `Equivale a ${bs(toBs(v))}`;
      };
      frm.addEventListener('input', eq); frm.addEventListener('change', eq); eq();
      frm.addEventListener('click', async (e) => {
        const c = e.target.closest('[data-m]');
        if (c) {
          const on = c.getAttribute('aria-pressed') !== 'true';
          frm.querySelectorAll('#g-met .chip').forEach((x) => x.setAttribute('aria-pressed', 'false'));
          c.setAttribute('aria-pressed', String(on));
          frm.payment_method.value = on ? c.dataset.m : '';
          return;
        }
        if (e.target.closest('[data-borrar]')) {
          const ok = await confirmDialog({ title: 'Eliminar gasto', body: `"${g.concept}" por ${usd(g.amount_usd)}. Dejará de contar en caja y reportes.`, confirm: 'Eliminar', danger: true });
          if (!ok) return;
          try { await db.remove('gastos', f.eq('id', g.id)); await L.gastos(); emit(); close(); toast('Gasto eliminado'); } catch (ex) { toast(ex.message, 'bad'); }
        }
      });
    },
    async onSubmit(d) {
      if (!d.concept) throw new Error('Escribe el concepto');
      const v = parseNum(d.monto);
      const usdAmount = d.moneda === 'ves' ? (rate() > 0 ? v / rate() : 0) : v;
      if (!(usdAmount > 0)) throw new Error('Escribe un monto mayor a cero');
      const at = d.at ? new Date(d.at) : new Date();
      if (Number.isNaN(at.getTime())) throw new Error('Revisa la fecha');
      const row = { concept: d.concept, category: d.category, amount_usd: Math.round(usdAmount * 100) / 100, payment_method: d.payment_method || '', note: d.note || '', at: at.toISOString() };
      if (nuevo) await db.insert('gastos', { ...row, by_user: S.me?.name || '' }); else await db.update('gastos', f.eq('id', g.id), row);
      await L.gastos(); emit();
      toast(nuevo ? 'Gasto registrado' : 'Gasto actualizado');
    },
  });
}

function mount(root, ctx) {
  const onQ = debounce(() => { ctx.rerender(); keepFocus(document.getElementById('view'), '[data-k="q"]'); }, 200);
  listen(root, ctx, {
    click(e) {
      const b = e.target.closest('[data-seg="preset"] button');
      if (b) { st.preset = b.dataset.v; ctx.rerender(); return; }
      const act = e.target.closest('[data-act]')?.dataset.act;
      if (act === 'nuevo') return form(null);
      if (act === 'csv') {
        return downloadCSV('gastos.csv', [['Fecha', 'Hora', 'Concepto', 'Categoría', 'Pagado con', 'Registró', 'Monto USD', 'Nota'],
          ...lista().map((g) => [fecha(g.at), hora(g.at), g.concept, GASTO_CATS[g.category] || g.category, g.payment_method || '', g.by_user || '', Number(g.amount_usd).toFixed(2), g.note || ''])]);
      }
      const tr = e.target.closest('tr[data-id]');
      if (tr) form(S.gastos.find((x) => x.id === tr.dataset.id));
    },
    change(e) {
      const k = e.target.dataset.k;
      if (k === 'desde' || k === 'hasta' || k === 'cat') { st[k] = e.target.value; ctx.rerender(); }
    },
    input(e) { if (e.target.dataset.k === 'q') { st.q = e.target.value; onQ(); } },
  });
}

export default { path: 'gastos', title: 'Gastos', icon: 'wallet', subtitle: () => 'Compras y pagos del negocio', render, mount };

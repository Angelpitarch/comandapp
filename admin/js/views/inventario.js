// Inventario de ingredientes: stock, minimos, costos, valor y compras.
import { html, usd, bs, qty, num, parseNum, openDrawer, confirmDialog, toast, debounce, downloadCSV } from '../util.js';
import { icon } from '../icons.js';
import { db, f } from '../api.js';
import { S, load as L, toUsd, toBs, emit, UNIDADES, sum } from '../store.js';
import { tile, empty, stockBadge, listen, keepFocus, seg } from './common.js';

const st = { q: '', kind: '', estado: '' };
const estadoDe = (i) => (Number(i.stock) <= 0 ? 'agotado' : Number(i.stock) <= Number(i.min_stock) ? 'bajo' : 'ok');

function lista() {
  const q = st.q.toLowerCase();
  const orden = { agotado: 0, bajo: 1, ok: 2 };
  return S.ingredients
    .filter((i) => (!st.kind || i.kind === st.kind) && (!st.estado || (st.estado === 'alerta' ? estadoDe(i) !== 'ok' : true)) && (!q || i.name.toLowerCase().includes(q)))
    .sort((a, b) => orden[estadoDe(a)] - orden[estadoDe(b)] || a.name.localeCompare(b.name, 'es'));
}
const usos = (id) => S.products.filter((p) => (p.recipe || []).some((r) => r.ingredient_id === id));

function render() {
  const rows = lista();
  const valor = sum(S.ingredients, (i) => Math.max(0, Number(i.stock)) * toUsd(i.cost, i.cost_currency));
  const bajos = S.ingredients.filter((i) => estadoDe(i) === 'bajo').length;
  const agot = S.ingredients.filter((i) => estadoDe(i) === 'agotado').length;
  return html`
  <div class="tiles">
    ${tile('Valor del inventario', usd(valor), `${bs(toBs(valor))} a precio de compra`)}
    ${tile('Ingredientes', num(S.ingredients.length, 0))}
    ${tile('Por agotarse', num(bajos, 0), 'En su stock mínimo o menos', { cls: bajos ? 'neg' : '' })}
    ${tile('Agotados', num(agot, 0), '', { cls: agot ? 'neg' : '' })}
  </div>
  <div class="toolbar">
    <label class="search">${icon('search', 16)}<span class="sr-only">Buscar ingrediente</span><input class="input sm" type="search" data-k="q" placeholder="Buscar ingrediente" value="${st.q}"></label>
    ${seg('kind', [['', 'Todos'], ['comida', 'Comida'], ['bebida', 'Bebidas']], st.kind)}
    ${seg('estado', [['', 'Cualquier stock'], ['alerta', 'Solo alertas']], st.estado)}
    <div class="grow"></div>
    <button class="btn btn-sm" data-act="csv">${icon('download', 16)}Exportar</button>
    <button class="btn btn-primary" data-act="nuevo">${icon('plus', 16)}Nuevo ingrediente</button>
  </div>
  <section class="card card-flush">
    ${rows.length ? html`<div class="table-wrap"><table class="table">
      <thead><tr><th></th><th>Ingrediente</th><th>Tipo</th><th class="r">Stock</th><th class="r">Mínimo</th><th class="r">Costo por unidad</th><th class="r">Valor en stock</th><th>Estado</th></tr></thead>
      <tbody>${rows.map((i) => { const cu = toUsd(i.cost, i.cost_currency); const n = usos(i.id).length; return html`<tr class="clickable" data-id="${i.id}" tabindex="0">
        <td class="em">${i.emoji}</td>
        <td><div class="t-main">${i.name}</div><div class="t-sub">${n ? `En ${n} ${n === 1 ? 'receta' : 'recetas'}` : 'No está en ninguna receta'}</div></td>
        <td><span class="tag">${i.kind === 'bebida' ? 'Bebida' : 'Comida'}</span></td>
        <td class="r t-main">${qty(i.stock)} <span class="muted">${i.unit}</span></td>
        <td class="r">${qty(i.min_stock)} <span class="muted">${i.unit}</span></td>
        <td class="r">${Number(i.cost) > 0 ? html`${usd(cu)}${i.cost_currency === 'ves' ? html`<div class="t-sub">${bs(i.cost)}</div>` : ''}` : html`<span class="muted">—</span>`}</td>
        <td class="r">${Number(i.cost) > 0 ? usd(Math.max(0, i.stock) * cu) : html`<span class="muted">—</span>`}</td>
        <td>${stockBadge(i.stock, i.min_stock)}</td></tr>`; })}</tbody>
    </table></div>` : empty('No hay ingredientes que coincidan', S.ingredients.length ? 'Cambia los filtros.' : 'Crea el primero con "Nuevo ingrediente".')}
  </section>`;
}

function form(i) {
  const nuevo = !i;
  i = i || { name: '', emoji: '📦', kind: 'comida', unit: 'kg', stock: 0, min_stock: 0, cost: 0, cost_currency: 'usd' };
  const enRecetas = nuevo ? [] : usos(i.id);
  openDrawer({
    title: nuevo ? 'Nuevo ingrediente' : `Editar ${i.name}`,
    submitLabel: nuevo ? 'Crear ingrediente' : 'Guardar cambios',
    extraFoot: nuevo ? '' : html`<button type="button" class="btn btn-danger left" data-borrar>${icon('trash', 16)}Eliminar</button>`,
    body: html`<div class="form-grid">
      <div class="field"><label for="i-emoji">Icono</label><input class="input" id="i-emoji" name="emoji" value="${i.emoji}" maxlength="8"></div>
      <div class="field"><label for="i-name">Nombre</label><input class="input" id="i-name" name="name" value="${i.name}" placeholder="Ej: Carne, Queso, Refresco" required></div>
      <div class="field"><label for="i-kind">Tipo</label><select class="input" id="i-kind" name="kind"><option value="comida" ${i.kind !== 'bebida' ? 'selected' : ''}>Ingrediente de comida</option><option value="bebida" ${i.kind === 'bebida' ? 'selected' : ''}>Bebida</option></select></div>
      <div class="field"><label for="i-unit">Unidad de medida</label><select class="input" id="i-unit" name="unit">${[...new Set([...UNIDADES, i.unit])].map((u) => html`<option ${u === i.unit ? 'selected' : ''}>${u}</option>`)}</select></div>
      <div class="field"><label for="i-stock">Stock actual</label><input class="input" id="i-stock" name="stock" inputmode="decimal" value="${qty(i.stock)}"></div>
      <div class="field"><label for="i-min">Stock mínimo (alerta)</label><input class="input" id="i-min" name="min_stock" inputmode="decimal" value="${qty(i.min_stock)}"></div>
      ${nuevo ? '' : html`<div class="field full"><label for="i-add">Registrar compra (opcional)</label><input class="input" id="i-add" name="compra" inputmode="decimal" placeholder="Cantidad que llegó, se suma al stock actual"><span class="hint" id="i-add-hint"></span></div>`}
      <div class="field"><label for="i-cost">Costo por unidad (compra)</label><input class="input" id="i-cost" name="cost" inputmode="decimal" value="${Number(i.cost) > 0 ? qty(i.cost) : ''}" placeholder="0"></div>
      <div class="field"><label for="i-cur">Moneda del costo</label><select class="input" id="i-cur" name="cost_currency"><option value="usd" ${i.cost_currency !== 'ves' ? 'selected' : ''}>USD</option><option value="ves" ${i.cost_currency === 'ves' ? 'selected' : ''}>Bs</option></select></div>
    </div>
    ${enRecetas.length ? html`<p class="muted small">Se usa en: ${enRecetas.map((p) => p.name).join(', ')}.</p>` : ''}`,
    onMount(frm, close) {
      const hint = frm.querySelector('#i-add-hint');
      frm.addEventListener('input', () => {
        if (!hint) return;
        const c = parseNum(frm.compra.value), s = parseNum(frm.stock.value);
        hint.textContent = c > 0 && s >= 0 ? `El stock quedará en ${qty(s + c)} ${frm.unit.value}` : '';
      });
      frm.addEventListener('click', async (e) => {
        if (!e.target.closest('[data-borrar]')) return;
        const ok = await confirmDialog({
          title: `Eliminar ${i.name}`,
          body: enRecetas.length ? `Está en la receta de ${enRecetas.map((p) => p.name).join(', ')}. Esos productos dejarán de descontarlo y de sumar su costo.` : 'No está en ninguna receta.',
          confirm: 'Eliminar', danger: true,
        });
        if (!ok) return;
        try { await db.remove('ingredients', f.eq('id', i.id)); await L.ingredients(); emit(); close(); toast('Ingrediente eliminado'); } catch (ex) { toast(ex.message, 'bad'); }
      });
    },
    async onSubmit(d) {
      if (!d.name) throw new Error('Escribe el nombre');
      const stock = d.stock === '' ? 0 : parseNum(d.stock);
      const min = d.min_stock === '' ? 0 : parseNum(d.min_stock);
      const cost = d.cost === '' ? 0 : parseNum(d.cost);
      const compra = d.compra ? parseNum(d.compra) : 0;
      if (!Number.isFinite(stock)) throw new Error('Revisa el stock actual');
      if (!(min >= 0)) throw new Error('Revisa el stock mínimo');
      if (!(cost >= 0)) throw new Error('Revisa el costo');
      if (!Number.isFinite(compra) || compra < 0) throw new Error('Revisa la cantidad de la compra');
      const row = { name: d.name, emoji: d.emoji || '📦', kind: d.kind === 'bebida' ? 'bebida' : 'comida', unit: d.unit, stock: stock + compra, min_stock: min, cost, cost_currency: d.cost_currency === 'ves' ? 'ves' : 'usd', updated_at: new Date().toISOString() };
      if (nuevo) await db.insert('ingredients', row); else await db.update('ingredients', f.eq('id', i.id), row);
      await L.ingredients(); emit();
      toast(nuevo ? 'Ingrediente creado' : compra ? `Compra registrada: stock en ${qty(row.stock)} ${row.unit}` : 'Cambios guardados');
    },
  });
}

function mount(root, ctx) {
  const onQ = debounce(() => { ctx.rerender(); keepFocus(document.getElementById('view'), '[data-k="q"]'); }, 200);
  listen(root, ctx, {
    click(e) {
      const sb = e.target.closest('[data-seg] button');
      if (sb) { st[sb.parentElement.dataset.seg] = sb.dataset.v; ctx.rerender(); return; }
      const act = e.target.closest('[data-act]')?.dataset.act;
      if (act === 'nuevo') return form(null);
      if (act === 'csv') {
        return downloadCSV('inventario.csv', [['Ingrediente', 'Tipo', 'Stock', 'Mínimo', 'Unidad', 'Costo', 'Moneda', 'Costo USD', 'Valor en stock USD', 'Estado'],
          ...lista().map((i) => [i.name, i.kind, i.stock, i.min_stock, i.unit, i.cost, i.cost_currency === 'ves' ? 'Bs' : 'USD', toUsd(i.cost, i.cost_currency).toFixed(4), (Math.max(0, i.stock) * toUsd(i.cost, i.cost_currency)).toFixed(2), { agotado: 'Agotado', bajo: 'Por agotarse', ok: 'Suficiente' }[estadoDe(i)]])]);
      }
      const tr = e.target.closest('tr[data-id]');
      if (tr) form(S.ingredients.find((x) => x.id === tr.dataset.id));
    },
    input(e) { if (e.target.dataset.k === 'q') { st.q = e.target.value; onQ(); } },
  });
}

export default { path: 'inventario', title: 'Inventario', icon: 'boxes', subtitle: () => 'Ingredientes y bebidas en existencia', render, mount };

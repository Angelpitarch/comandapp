// Productos del menu: precios, costo por receta, margen, disponibilidad y edicion completa.
import { html, raw, usd, bs, num, qty, parseNum, openDrawer, confirmDialog, toast, debounce, downloadCSV } from '../util.js';
import { icon } from '../icons.js';
import { db, f } from '../api.js';
import { S, load as L, productCost, priceUsd, maxMakeable, hasCostData, catLabel, toBs, toUsd, ingredientById, productById, TAMANOS, emit } from '../store.js';
import { empty, makeableBadge, listen, keepFocus } from './common.js';

const st = { q: '', cat: '', estado: '' };

function lista() {
  const pos = new Map(S.categories.map((c) => [c.key, c.position]));
  const q = st.q.toLowerCase();
  return S.products
    .filter((p) => (!st.cat || p.category === st.cat) && (!st.estado || (st.estado === 'si') === !!p.available) && (!q || p.name.toLowerCase().includes(q)))
    .sort((a, b) => (pos.get(a.category) ?? 999) - (pos.get(b.category) ?? 999) || a.name.localeCompare(b.name, 'es'));
}

function render() {
  const rows = lista();
  return html`
  <div class="toolbar">
    <label class="search">${icon('search', 16)}<span class="sr-only">Buscar producto</span><input class="input sm" type="search" data-k="q" placeholder="Buscar producto" value="${st.q}"></label>
    <select class="input sm" data-k="cat" style="width:auto" aria-label="Categoría">
      <option value="">Todas las categorías</option>
      ${S.categories.map((c) => html`<option value="${c.key}" ${st.cat === c.key ? 'selected' : ''}>${c.emoji} ${c.label}</option>`)}
    </select>
    <select class="input sm" data-k="estado" style="width:auto" aria-label="Disponibilidad">
      <option value="">Disponibles y no disponibles</option>
      <option value="si" ${st.estado === 'si' ? 'selected' : ''}>Solo disponibles</option>
      <option value="no" ${st.estado === 'no' ? 'selected' : ''}>Solo no disponibles</option>
    </select>
    <div class="grow"></div>
    <button class="btn btn-sm" data-act="csv">${icon('download', 16)}Exportar</button>
    <button class="btn btn-primary" data-act="nuevo">${icon('plus', 16)}Nuevo producto</button>
  </div>
  <section class="card card-flush">
    ${rows.length ? html`<div class="table-wrap"><table class="table">
      <thead><tr><th></th><th>Producto</th><th>Categoría</th><th class="r">Precio</th><th class="r">Costo</th><th class="r">Ganancia</th><th class="r">Margen</th><th class="r">Alcanza para</th><th class="c">Disponible</th></tr></thead>
      <tbody>${rows.map((p) => {
        const precio = priceUsd(p), costo = productCost(p), gan = precio - costo, tiene = hasCostData(p);
        return html`<tr class="clickable" data-id="${p.id}" tabindex="0">
          <td class="em">${p.emoji}</td>
          <td><div class="t-main">${p.name}</div>${(p.extras || []).length || (p.sizes || []).length ? html`<div class="t-sub">${[(p.sizes || []).length ? 'Con tamaños' : '', (p.extras || []).length ? `${p.extras.length} ${p.extras.length === 1 ? 'extra' : 'extras'}` : ''].filter(Boolean).join(', ')}</div>` : ''}</td>
          <td><span class="tag">${catLabel(p.category)}</span></td>
          <td class="r"><div class="t-main">${usd(precio)}</div><div class="t-sub">${p.currency === 'ves' ? 'precio en Bs' : bs(toBs(precio))}</div></td>
          <td class="r">${tiene ? usd(costo) : html`<span class="muted">—</span>`}</td>
          <td class="r ${tiene && gan < 0 ? 'neg' : ''}">${tiene ? usd(gan) : html`<span class="muted">—</span>`}</td>
          <td class="r">${tiene && precio > 0 ? num((gan / precio) * 100, 0) + '%' : html`<span class="muted">—</span>`}</td>
          <td class="r">${makeableBadge(maxMakeable(p))}</td>
          <td class="c"><label class="switch" title="${p.available ? 'Disponible' : 'No disponible'}"><input type="checkbox" data-toggle="${p.id}" ${p.available ? 'checked' : ''} aria-label="Disponible: ${p.name}"><span class="track"></span></label></td>
        </tr>`; })}</tbody>
    </table></div>` : empty('No hay productos que coincidan', S.products.length ? 'Cambia los filtros.' : 'Crea el primero con "Nuevo producto".')}
  </section>
  <p class="muted small" style="margin-top:10px">Costo calculado con la receta y el precio de compra de cada ingrediente. "Alcanza para" usa el stock actual del inventario.</p>`;
}

// ---------- Formulario ----------
const ingOptions = (sel) => html`<option value="">Elige un ingrediente</option>${S.ingredients.map((i) => html`<option value="${i.id}" ${i.id === sel ? 'selected' : ''}>${i.emoji} ${i.name} (${i.unit})</option>`)}`;
const prodOptions = (sel, exceptId) => html`<option value="">Elige un producto</option>${S.products.filter((p) => p.category !== 'combos' && p.id !== exceptId).map((p) => html`<option value="${p.id}" ${p.id === sel ? 'selected' : ''}>${p.emoji} ${p.name}</option>`)}`;
const delBtn = raw(`<button type="button" class="icon-btn" data-del aria-label="Quitar">${String(icon('trash', 16))}</button>`);
const rowExtra = (e = { name: '', price: 0 }) => html`<div class="r" data-row="extra"><input class="input sm" data-f="name" placeholder="Ej: queso extra" value="${e.name}" aria-label="Nombre del extra"><input class="input sm" data-f="price" inputmode="decimal" placeholder="Precio" value="${e.price ? num(e.price) : ''}" aria-label="Precio del extra">${delBtn}</div>`;
const rowRec = (r = { ingredient_id: '', qty: 1 }) => html`<div class="r" data-row="rec"><select class="input sm" data-f="id" aria-label="Ingrediente">${ingOptions(r.ingredient_id)}</select><input class="input sm" data-f="qty" inputmode="decimal" value="${qty(r.qty)}" aria-label="Cantidad">${delBtn}</div>`;
const rowCombo = (c = { product_id: '', qty: 1 }, exceptId) => html`<div class="r" data-row="combo"><select class="input sm" data-f="id" aria-label="Producto">${prodOptions(c.product_id, exceptId)}</select><input class="input sm" data-f="qty" inputmode="decimal" value="${qty(c.qty)}" aria-label="Cantidad">${delBtn}</div>`;

function form(p) {
  const nuevo = !p;
  p = p || { name: '', emoji: '🍽️', category: S.categories[0]?.key || 'otros', price: '', currency: 'usd', available: true, sizes: [], extras: [], quita: [], recipe: [], combo_items: [] };
  const esCombo = p.category === 'combos';
  openDrawer({
    title: nuevo ? 'Nuevo producto' : `Editar ${p.name}`,
    submitLabel: nuevo ? 'Crear producto' : 'Guardar cambios',
    wide: true,
    extraFoot: nuevo ? '' : html`<button type="button" class="btn btn-danger left" data-borrar>${icon('trash', 16)}Eliminar</button>`,
    body: html`
      <div class="form-grid">
        <div class="field full"><label for="p-name">Nombre</label><input class="input" id="p-name" name="name" value="${p.name}" required></div>
        <div class="field"><label for="p-cat">Categoría</label><select class="input" id="p-cat" name="category">
          ${S.categories.map((c) => html`<option value="${c.key}" ${c.key === p.category ? 'selected' : ''}>${c.emoji} ${c.label}</option>`)}
          ${S.categories.some((c) => c.key === p.category) ? '' : html`<option value="${p.category}" selected>${p.category}</option>`}</select></div>
        <div class="field"><label for="p-emoji">Icono</label><input class="input" id="p-emoji" name="emoji" value="${p.emoji}" maxlength="8"><span class="hint">Un emoji, como 🌭 o 🥤</span></div>
        <div class="field"><label for="p-price">Precio</label>
          <div class="input-group"><input class="input" id="p-price" name="price" inputmode="decimal" value="${p.price === '' ? '' : num(p.price)}" required>
          <select class="input" name="currency" style="width:84px;border-radius:0 8px 8px 0;border-left:0" aria-label="Moneda"><option value="usd" ${p.currency !== 'ves' ? 'selected' : ''}>USD</option><option value="ves" ${p.currency === 'ves' ? 'selected' : ''}>Bs</option></select></div>
          <span class="hint" id="p-equiv"></span></div>
        <div class="field"><span class="label">Opciones</span>
          <label class="switch"><input type="checkbox" name="available" ${p.available ? 'checked' : ''}><span class="track"></span>Disponible para vender</label>
          <label class="switch"><input type="checkbox" name="sizes" ${(p.sizes || []).length ? 'checked' : ''}><span class="track"></span>Tamaños (pequeña −$0,50, grande +$0,80)</label></div>
        <div class="field full"><label for="p-quita">Ingredientes que el cliente puede quitar</label><input class="input" id="p-quita" name="quita" value="${(p.quita || []).join(', ')}" placeholder="Cebolla, Tomate, Salsas"><span class="hint">Separados por coma. Aparecen como opciones al tomar el pedido.</span></div>
      </div>

      <div class="field"><div class="row" style="justify-content:space-between"><span class="section-title" style="margin:0">Extras con costo</span><button type="button" class="btn btn-sm" data-add="extra">${icon('plus', 14)}Agregar extra</button></div>
        <div class="rows-editor" id="rows-extra">${(p.extras || []).map((e) => rowExtra(e))}</div>
        <span class="hint">El mesero los suma al pedido; su precio se cobra en dólares.</span></div>

      <div class="field ${esCombo ? 'hidden' : ''}" id="sec-rec"><div class="row" style="justify-content:space-between"><span class="section-title" style="margin:0">Receta</span><button type="button" class="btn btn-sm" data-add="rec">${icon('plus', 14)}Agregar ingrediente</button></div>
        <div class="rows-editor" id="rows-rec">${(p.recipe || []).map((r) => rowRec(r))}</div>
        <span class="hint">Qué ingredientes consume y cuánto. Se descuentan del inventario al vender.${S.ingredients.length ? '' : ' Primero agrega ingredientes en Inventario.'}</span></div>

      <div class="field ${esCombo ? '' : 'hidden'}" id="sec-combo"><div class="row" style="justify-content:space-between"><span class="section-title" style="margin:0">Componentes del combo</span><button type="button" class="btn btn-sm" data-add="combo">${icon('plus', 14)}Agregar producto</button></div>
        <div class="rows-editor" id="rows-combo">${(p.combo_items || []).map((c) => rowCombo(c, p.id))}</div>
        <span class="hint">Productos ya creados y su cantidad. El precio del combo es el que pones arriba.</span></div>

      <div class="note" id="p-cost"></div>`,
    onMount(frm, close) {
      const calc = () => {
        const price = parseNum(frm.price.value) || 0;
        const cur = frm.currency.value;
        const precio = toUsd(price, cur);
        frm.querySelector('#p-equiv').textContent = cur === 'ves' ? `Equivale a ${usd(precio)}` : `Equivale a ${bs(toBs(precio))}`;
        const tmp = { recipe: leer(frm).recipe, combo_items: leer(frm).combo_items };
        const costo = productCost(tmp);
        const tiene = tmp.recipe.length || tmp.combo_items.length;
        frm.querySelector('#p-cost').innerHTML = String(tiene
          ? html`Costo estimado <b>${usd(costo)}</b>, ganancia por unidad <b class="${precio - costo < 0 ? 'neg' : ''}">${usd(precio - costo)}</b>${precio > 0 ? html`, margen <b>${num(((precio - costo) / precio) * 100, 0)}%</b>` : ''}.`
          : html`Agrega la receta para calcular el costo y la ganancia de este producto.`);
      };
      const toggleSec = () => {
        const combo = frm.category.value === 'combos';
        frm.querySelector('#sec-rec').classList.toggle('hidden', combo);
        frm.querySelector('#sec-combo').classList.toggle('hidden', !combo);
        calc();
      };
      frm.addEventListener('click', async (e) => {
        const add = e.target.closest('[data-add]')?.dataset.add;
        if (add) {
          const box = frm.querySelector(`#rows-${add}`);
          box.insertAdjacentHTML('beforeend', String(add === 'extra' ? rowExtra() : add === 'rec' ? rowRec() : rowCombo(undefined, p.id)));
          box.lastElementChild.querySelector('input,select')?.focus();
          calc(); return;
        }
        if (e.target.closest('[data-del]')) { e.target.closest('[data-row]').remove(); calc(); return; }
        if (e.target.closest('[data-borrar]')) {
          const ok = await confirmDialog({ title: `Eliminar ${p.name}`, body: 'Se quita del menú en todos los teléfonos. Las ventas ya registradas no cambian.', confirm: 'Eliminar', danger: true });
          if (!ok) return;
          try { await db.remove('products', f.eq('id', p.id)); await L.products(); emit(); close(); toast('Producto eliminado'); } catch (ex) { toast(ex.message, 'bad'); }
        }
      });
      frm.addEventListener('input', debounce(calc, 120));
      frm.addEventListener('change', (e) => { if (e.target.name === 'category') toggleSec(); else calc(); });
      calc();
    },
    async onSubmit(d, frm) {
      const name = d.name;
      const price = parseNum(d.price);
      if (!name) throw new Error('Escribe el nombre del producto');
      if (!(price >= 0)) throw new Error('Escribe un precio válido');
      const x = leer(frm);
      if (x.bad) throw new Error(x.bad);
      const combo = d.category === 'combos';
      const row = {
        name, emoji: d.emoji || '🍽️', category: d.category || 'otros', price, currency: d.currency === 'ves' ? 'ves' : 'usd',
        available: !!d.available,
        sizes: d.sizes ? TAMANOS : [],
        extras: x.extras,
        quita: (d.quita || '').split(',').map((s) => s.trim()).filter(Boolean),
        recipe: combo ? [] : x.recipe,
        combo_items: combo ? x.combo_items : [],
        // igual que la app: el control de stock por producto ya no se usa (va por ingredientes)
        stock: 0, min_stock: 0, track_stock: false,
        updated_at: new Date().toISOString(),
      };
      if (nuevo) await db.insert('products', row); else await db.update('products', f.eq('id', p.id), row);
      await L.products(); emit();
      toast(nuevo ? 'Producto creado' : 'Cambios guardados');
    },
  });
}

function leer(frm) {
  const out = { extras: [], recipe: [], combo_items: [], bad: '' };
  frm.querySelectorAll('[data-row="extra"]').forEach((r, i) => {
    const n = r.querySelector('[data-f="name"]').value.trim();
    const pr = parseNum(r.querySelector('[data-f="price"]').value);
    if (!n) return;
    if (r.querySelector('[data-f="price"]').value.trim() && !(pr >= 0)) out.bad = `Revisa el precio del extra "${n}"`;
    out.extras.push({ id: `e${out.extras.length + 1}`, name: n, price: pr >= 0 ? pr : 0 });
  });
  frm.querySelectorAll('[data-row="rec"]').forEach((r) => {
    const id = r.querySelector('[data-f="id"]').value;
    const q = parseNum(r.querySelector('[data-f="qty"]').value);
    if (!id) return;
    if (!(q > 0)) out.bad = `Revisa la cantidad de ${ingredientById(id)?.name || 'un ingrediente'} en la receta`;
    out.recipe.push({ ingredient_id: id, qty: q > 0 ? q : 0 });
  });
  frm.querySelectorAll('[data-row="combo"]').forEach((r) => {
    const id = r.querySelector('[data-f="id"]').value;
    const q = parseNum(r.querySelector('[data-f="qty"]').value);
    if (!id) return;
    if (!(q > 0)) out.bad = `Revisa la cantidad de ${productById(id)?.name || 'un producto'} en el combo`;
    out.combo_items.push({ product_id: id, qty: q > 0 ? q : 0 });
  });
  return out;
}

function mount(root, ctx) {
  const onQ = debounce(() => { ctx.rerender(); keepFocus(document.getElementById('view'), '[data-k="q"]'); }, 200);
  listen(root, ctx, {
    async click(e) {
      const act = e.target.closest('[data-act]')?.dataset.act;
      if (act === 'nuevo') return form(null);
      if (act === 'csv') {
        return downloadCSV('productos.csv', [['Producto', 'Categoría', 'Precio', 'Moneda', 'Precio USD', 'Costo USD', 'Ganancia USD', 'Disponible'],
          ...lista().map((p) => [p.name, catLabel(p.category), p.price, p.currency === 'ves' ? 'Bs' : 'USD', priceUsd(p).toFixed(2), productCost(p).toFixed(2), (priceUsd(p) - productCost(p)).toFixed(2), p.available ? 'Sí' : 'No'])]);
      }
      if (e.target.closest('.switch')) return; // lo maneja "change"
      const tr = e.target.closest('tr[data-id]');
      if (tr) form(S.products.find((x) => x.id === tr.dataset.id));
    },
    async change(e) {
      const id = e.target.dataset.toggle;
      if (id) {
        const p = S.products.find((x) => x.id === id);
        try {
          const [row] = await db.update('products', f.eq('id', id), { available: e.target.checked });
          Object.assign(p, row);
          toast(row.available ? `${p.name} disponible` : `${p.name} ya no aparece para vender`);
          ctx.rerender();
        } catch (ex) { e.target.checked = !e.target.checked; toast(ex.message, 'bad'); }
        return;
      }
      const k = e.target.dataset.k;
      if (k === 'cat' || k === 'estado') { st[k] = e.target.value; ctx.rerender(); }
    },
    input(e) { if (e.target.dataset.k === 'q') { st.q = e.target.value; onQ(); } },
  });
}

export default { path: 'productos', title: 'Productos', icon: 'burger', subtitle: () => `${S.products.length} productos en el menú`, render, mount };

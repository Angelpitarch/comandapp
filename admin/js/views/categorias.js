// Categorias del menu: crear, renombrar, ordenar y borrar.
import { html, openDrawer, confirmDialog, toast } from '../util.js';
import { icon } from '../icons.js';
import { db, f } from '../api.js';
import { S, load as L, emit, slug } from '../store.js';
import { empty, listen } from './common.js';

function render() {
  const cats = S.categories;
  return html`
  <div class="toolbar"><p class="text-2 grow">El orden de esta lista es el orden en que el mesero ve las categorías al tomar un pedido.</p>
    <button class="btn btn-primary" data-act="nueva">${icon('plus', 16)}Nueva categoría</button></div>
  <section class="card card-flush">
    ${cats.length ? html`<div class="table-wrap"><table class="table">
      <thead><tr><th>Orden</th><th></th><th>Nombre</th><th>Clave interna</th><th class="r">Productos</th><th class="r">Acciones</th></tr></thead>
      <tbody>${cats.map((c, i) => html`<tr>
        <td class="nowrap"><button class="icon-btn" data-up="${c.id}" ${i === 0 ? 'disabled' : ''} aria-label="Subir ${c.label}">${icon('left', 16, 'rot90')}</button><button class="icon-btn" data-down="${c.id}" ${i === cats.length - 1 ? 'disabled' : ''} aria-label="Bajar ${c.label}">${icon('right', 16, 'rot90')}</button></td>
        <td class="em">${c.emoji}</td>
        <td class="t-main">${c.label}${c.protected ? html` <span class="badge neutral" title="Categoría del sistema: no se puede borrar">${icon('lock', 12)}Fija</span>` : ''}</td>
        <td class="mono muted">${c.key}</td>
        <td class="r">${S.products.filter((p) => p.category === c.key).length}</td>
        <td class="r nowrap"><button class="btn btn-sm" data-edit="${c.id}">${icon('edit', 14)}Editar</button>
          ${c.protected ? '' : html`<button class="btn btn-sm btn-danger" data-del="${c.id}">${icon('trash', 14)}Borrar</button>`}</td>
      </tr>`)}</tbody></table></div>` : empty('Sin categorías', 'Crea la primera con "Nueva categoría".')}
  </section>`;
}

function form(c) {
  openDrawer({
    title: c ? `Editar ${c.label}` : 'Nueva categoría',
    submitLabel: c ? 'Guardar cambios' : 'Crear categoría',
    body: html`<div class="form-grid">
      <div class="field"><label for="c-emoji">Icono</label><input class="input" id="c-emoji" name="emoji" value="${c?.emoji || '🍽️'}" maxlength="8"></div>
      <div class="field"><label for="c-label">Nombre</label><input class="input" id="c-label" name="label" value="${c?.label || ''}" required></div></div>
      ${c ? html`<p class="muted small">La clave interna (<span class="mono">${c.key}</span>) no cambia, así los productos siguen en esta categoría.</p>` : ''}`,
    async onSubmit(d) {
      if (!d.label) throw new Error('Escribe el nombre');
      const emoji = d.emoji || '🍽️';
      if (c) await db.update('categories', f.eq('id', c.id), { label: d.label, emoji });
      else {
        let key = slug(d.label);
        const keys = new Set(S.categories.map((x) => x.key));
        for (let n = 2; keys.has(key); n++) key = `${slug(d.label)}_${n}`;
        const pos = S.categories.length ? Math.max(...S.categories.map((x) => x.position)) + 10 : 10;
        await db.insert('categories', { key, label: d.label, emoji, position: pos, protected: false });
      }
      await L.categories(); emit();
      toast(c ? 'Categoría actualizada' : 'Categoría creada');
    },
  });
}

async function mover(id, dir) {
  const cats = S.categories;
  const i = cats.findIndex((c) => c.id === id);
  const j = i + dir;
  if (i < 0 || j < 0 || j >= cats.length) return;
  const a = cats[i], b = cats[j];
  let pa = b.position, pb = a.position;
  if (pa === pb) { pa = a.position + dir * 5; } // posiciones repetidas: se separan
  await db.update('categories', f.eq('id', a.id), { position: pa });
  await db.update('categories', f.eq('id', b.id), { position: pb });
  await L.categories(); emit();
}

function mount(root, ctx) {
  listen(root, ctx, {
    async click(e) {
      const t = e.target.closest('button');
      if (!t) return;
      try {
        if (t.dataset.act === 'nueva') return form(null);
        if (t.dataset.edit) return form(S.categories.find((c) => c.id === t.dataset.edit));
        if (t.dataset.up) return await mover(t.dataset.up, -1);
        if (t.dataset.down) return await mover(t.dataset.down, 1);
        if (t.dataset.del) {
          const c = S.categories.find((x) => x.id === t.dataset.del);
          const n = S.products.filter((p) => p.category === c.key).length;
          const ok = await confirmDialog({ title: `Borrar ${c.label}`, body: n ? `Sus ${n} productos pasarán a "Otros". No se borra ningún producto.` : 'No tiene productos.', confirm: 'Borrar', danger: true });
          if (!ok) return;
          if (n) await db.patchMany('products', f.eq('category', c.key), { category: 'otros' });
          await db.remove('categories', f.eq('id', c.id));
          await Promise.all([L.categories(), L.products()]); emit();
          toast('Categoría borrada');
        }
      } catch (ex) { toast(ex.message, 'bad'); }
    },
  });
}

export default { path: 'categorias', title: 'Categorías', icon: 'tag', subtitle: () => 'Cómo se agrupa el menú', render, mount };

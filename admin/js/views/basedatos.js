// Base de datos: explorador y editor de las tablas de Postgres (Supabase), solo para administradores.
// Respeta las reglas RLS: lo que la base de datos no permite, aqui tampoco se puede.
import { html, esc, num, fechaHora, openDrawer, confirmDialog, toast, downloadCSV, parseNum } from '../util.js';
import { icon } from '../icons.js';
import { db } from '../api.js';
import { emit, loadAll } from '../store.js';
import { empty, listen } from './common.js';

const DESC = {
  account_items: 'Productos de las cuentas abiertas (mesas y para llevar)',
  app_config: 'Configuración general: tasa de cambio y nombre del negocio',
  app_users: 'Usuarios y roles. Se editan en la sección Usuarios',
  cancellations: 'Comandas anuladas y pérdidas',
  cash_closes: 'Cierres de caja',
  categories: 'Categorías del menú',
  device_tokens: 'Teléfonos que reciben avisos. Solo los usa el servidor',
  dining_tables: 'Mesas del local',
  employees: 'Trabajadores',
  gastos: 'Gastos del negocio',
  ingredients: 'Ingredientes del inventario',
  products: 'Productos del menú',
  sales: 'Ventas cobradas',
  takeaways: 'Pedidos para llevar abiertos',
  tickets: 'Comandas enviadas a cocina',
};
// Tablas que aqui solo se leen (tienen su propia pantalla o son internas)
const SOLO_LECTURA = { app_users: 'Los usuarios se editan en la sección Usuarios, para que su acceso y su PIN queden bien.', device_tokens: 'La administra el servidor de avisos.' };
const OCULTAS = { app_users: ['pin', 'pin_hash'] };
const PAGE = 50;

const st = { schema: null, counts: {}, table: null, page: 0, order: null, filter: null, rows: [], total: null, error: '', showCols: false };

async function loadSchema() {
  const rows = await db.rpc('admin_esquema');
  const map = new Map();
  for (const r of rows) {
    if (!map.has(r.tabla)) map.set(r.tabla, { name: r.tabla, kind: r.tipo, cols: [] });
    if (!(OCULTAS[r.tabla] || []).includes(r.columna)) map.get(r.tabla).cols.push(r);
  }
  st.schema = [...map.values()].sort((a, b) => (a.kind === b.kind ? a.name.localeCompare(b.name) : a.kind === 'tabla' ? -1 : 1));
  // totales de filas (en paralelo, 1 fila por tabla)
  await Promise.all(st.schema.map(async (t) => {
    try { st.counts[t.name] = (await db.page(t.name, 'select=' + encodeURIComponent(t.cols[0]?.columna || '*'), 0, 0)).total; } catch { st.counts[t.name] = null; }
  }));
}
const tdef = () => st.schema?.find((t) => t.name === st.table);
const pkCols = (t) => t.cols.filter((c) => c.es_pk);
const editable = (t) => t.kind === 'tabla' && !SOLO_LECTURA[t.name] && pkCols(t).length > 0;
const isJson = (c) => /json/.test(c.tipo_dato);
const isNum = (c) => /^(integer|bigint|smallint|numeric|real|double precision)/.test(c.tipo_dato);
const isBool = (c) => c.tipo_dato === 'boolean';
const isTime = (c) => /^timestamp|^date/.test(c.tipo_dato);
const isText = (c) => /^(text|character)/.test(c.tipo_dato);

function defaultOrder(t) {
  for (const n of ['at', 'sent_at', 'closed_at', 'created_at']) if (t.cols.some((c) => c.columna === n)) return { col: n, dir: 'desc' };
  const pk = pkCols(t)[0];
  return { col: (pk || t.cols[0]).columna, dir: 'asc' };
}

function query(t) {
  const sel = t.cols.map((c) => encodeURIComponent(c.columna)).join(',');
  let q = `select=${sel}`;
  if (st.order) q += `&order=${encodeURIComponent(st.order.col)}.${st.order.dir}.nullslast`;
  const fl = st.filter;
  if (fl?.col) {
    const c = encodeURIComponent(fl.col);
    const v = encodeURIComponent(fl.value ?? '');
    q += {
      contiene: `&${c}=ilike.*${v}*`, igual: `&${c}=eq.${v}`, mayor: `&${c}=gt.${v}`, menor: `&${c}=lt.${v}`,
      desde: `&${c}=gte.${v}`, antes: `&${c}=lt.${v}`, nulo: `&${c}=is.null`, nonulo: `&${c}=not.is.null`,
    }[fl.op] || '';
  }
  return q;
}

async function loadRows() {
  const t = tdef();
  if (!t) return;
  st.error = '';
  try {
    const r = await db.page(t.name, query(t), st.page * PAGE, st.page * PAGE + PAGE - 1);
    st.rows = r.rows; st.total = r.total;
  } catch (e) { st.rows = []; st.total = 0; st.error = e.message; }
}

async function load() {
  if (!st.schema) await loadSchema();
  if (!st.table) st.table = st.schema.find((t) => t.name === 'products')?.name || st.schema[0]?.name;
  if (!st.order && tdef()) st.order = defaultOrder(tdef());
  await loadRows();
}

function cell(c, v) {
  if (v === null || v === undefined) return html`<span class="nul">null</span>`;
  if (isJson(c)) { const s = JSON.stringify(v); return html`<span title="${s.length > 300 ? s.slice(0, 300) + '…' : s}">${s.length > 80 ? s.slice(0, 80) + '…' : s}</span>`; }
  if (isBool(c)) return v ? 'true' : 'false';
  if (isTime(c) && typeof v === 'string' && v.length > 10) return html`<span title="${v}">${fechaHora(v)}</span>`;
  if (isNum(c)) return html`<span class="num">${String(v)}</span>`;
  const s = String(v);
  return html`<span title="${s.length > 40 ? s : ''}">${s}</span>`;
}

function render() {
  if (!st.schema) return empty('No se pudo leer la estructura de la base de datos');
  const t = tdef();
  const tablas = st.schema.filter((x) => x.kind === 'tabla');
  const vistas = st.schema.filter((x) => x.kind === 'vista');
  const btn = (x) => html`<button data-table="${x.name}" aria-current="${String(x.name === st.table)}"><span class="nm">${x.name}</span><span class="ct">${st.counts[x.name] ?? ''}</span></button>`;
  const fl = st.filter || {};
  const fc = t?.cols.find((c) => c.columna === fl.col);
  const ops = !fc ? [] : [
    ...(isText(fc) ? [['contiene', 'contiene'], ['igual', 'es igual a']] : []),
    ...(isNum(fc) ? [['igual', '='], ['mayor', '>'], ['menor', '<']] : []),
    ...(isBool(fc) ? [['igual', 'es']] : []),
    ...(isTime(fc) ? [['desde', 'desde'], ['antes', 'antes de']] : []),
    ...(!isText(fc) && !isNum(fc) && !isBool(fc) && !isTime(fc) && !isJson(fc) ? [['igual', 'es igual a']] : []),
    ...(fc.nulo ? [['nulo', 'está vacío (null)'], ['nonulo', 'no está vacío']] : []),
  ];
  const from = st.page * PAGE;
  const pages = st.total ? Math.ceil(st.total / PAGE) : 1;
  return html`
  <div class="note warn" style="margin-bottom:14px">${icon('alert', 16)} Los cambios aquí van directo a la base de datos y se ven al instante en todos los teléfonos. Para el trabajo diario usa las otras secciones; esta es para revisar o corregir datos puntuales.</div>
  <div class="db">
    <aside class="card db-list" aria-label="Tablas">
      <div class="sep">Tablas</div>${tablas.map(btn)}
      ${vistas.length ? html`<div class="sep">Vistas</div>${vistas.map(btn)}` : ''}
    </aside>
    <section class="card card-flush" style="min-width:0">
      ${!t ? empty('Elige una tabla') : html`
      <div class="card-head" style="padding-bottom:12px;flex-wrap:wrap">
        <div><h2 class="mono" style="font-size:15px">public.${t.name}</h2><p>${DESC[t.name] || ''}${st.total !== null ? ` · ${num(st.total, 0)} ${st.total === 1 ? 'fila' : 'filas'}` : ''}</p></div>
        <div class="row" style="flex-wrap:wrap">
          <button class="btn btn-sm" data-act="cols" aria-pressed="${String(st.showCols)}">${icon('table', 15)}${st.showCols ? 'Ocultar estructura' : 'Ver estructura'}</button>
          <button class="btn btn-sm" data-act="csv">${icon('download', 15)}Exportar</button>
          ${editable(t) ? html`<button class="btn btn-sm btn-primary" data-act="nueva">${icon('plus', 15)}Nueva fila</button>` : html`<span class="badge neutral" title="${SOLO_LECTURA[t.name] || 'Sin clave primaria'}">${icon('lock', 12)}Solo lectura</span>`}
        </div>
      </div>
      ${st.showCols ? html`<div class="table-wrap" style="border-top:1px solid var(--border)"><table class="table grid-table">
        <thead><tr><th>Columna</th><th>Tipo</th><th>Vacío permitido</th><th>Valor por defecto</th></tr></thead>
        <tbody>${t.cols.map((c) => html`<tr><td>${c.es_pk ? html`<span class="pk" title="Clave primaria">${icon('key', 12)} </span>` : ''}${c.columna}</td><td>${c.tipo_dato}</td><td>${c.nulo ? 'sí' : 'no'}</td><td class="muted">${c.por_defecto || ''}</td></tr>`)}</tbody></table></div>` : ''}
      <form class="toolbar" data-form="filtro" style="padding:10px 14px;margin:0;border-top:1px solid var(--border)">
        <span class="muted small">Filtrar</span>
        <select class="input sm" name="col" style="width:auto" aria-label="Columna"><option value="">columna…</option>${t.cols.filter((c) => !isJson(c)).map((c) => html`<option value="${c.columna}" ${c.columna === fl.col ? 'selected' : ''}>${c.columna}</option>`)}</select>
        ${fc ? html`<select class="input sm" name="op" style="width:auto" aria-label="Condición">${ops.map(([k, v]) => html`<option value="${k}" ${k === fl.op ? 'selected' : ''}>${v}</option>`)}</select>
          ${isBool(fc) ? html`<select class="input sm" name="value" style="width:auto"><option ${fl.value === 'true' ? 'selected' : ''}>true</option><option ${fl.value === 'false' ? 'selected' : ''}>false</option></select>`
            : html`<input class="input sm" name="value" style="width:200px" ${isTime(fc) ? 'type="date"' : ''} value="${fl.shown ?? fl.value ?? ''}" aria-label="Valor">`}
          <button class="btn btn-sm" type="submit">Aplicar</button>` : ''}
        ${st.filter?.op ? html`<button class="btn btn-sm btn-ghost" type="button" data-act="limpiar">Quitar filtro</button>` : ''}
      </form>
      ${st.error ? html`<div class="form-error" style="margin:0 14px 14px">${st.error}</div>` : ''}
      ${st.rows.length ? html`<div class="table-wrap" style="max-height:62vh;border-top:1px solid var(--border)"><table class="table grid-table">
        <thead><tr>${t.cols.map((c) => html`<th><button data-sort="${c.columna}" title="Ordenar por ${c.columna}"><span class="cn">${c.es_pk ? html`<span class="pk">${icon('key', 11)}</span> ` : ''}${c.columna}${st.order?.col === c.columna ? (st.order.dir === 'asc' ? ' ↑' : ' ↓') : ''}</span><span class="ty">${c.tipo_dato}</span></button></th>`)}</tr></thead>
        <tbody>${st.rows.map((r, i) => html`<tr class="clickable" data-i="${i}" tabindex="0">${t.cols.map((c) => html`<td>${cell(c, r[c.columna])}</td>`)}</tr>`)}</tbody>
      </table></div>
      <div class="pager"><span>${st.total ? `Filas ${num(from + 1, 0)} a ${num(Math.min(from + PAGE, st.total), 0)} de ${num(st.total, 0)}` : `${st.rows.length} filas`}</span>
        <div class="row"><button class="btn btn-sm" data-act="prev" ${st.page === 0 ? 'disabled' : ''}>${icon('left', 14)}Anterior</button>
          <span>Página ${st.page + 1} de ${pages}</span>
          <button class="btn btn-sm" data-act="next" ${st.page + 1 >= pages ? 'disabled' : ''}>Siguiente${icon('right', 14)}</button></div></div>`
      : st.error ? '' : empty('Sin filas', st.filter?.op ? 'Ningún registro cumple el filtro.' : 'Esta tabla está vacía.')}`}
    </section>
  </div>`;
}

// ---------- Edicion de una fila ----------
function valorInput(c, v) {
  if (v === null || v === undefined) return '';
  if (isJson(c)) return JSON.stringify(v, null, 2);
  return String(v);
}
function campo(c, v, nueva) {
  const id = `f-${c.columna}`;
  const bloqueado = c.es_pk && !nueva;
  const hint = [c.tipo_dato, c.nulo ? 'puede quedar vacío' : 'obligatorio', nueva && c.por_defecto ? `por defecto: ${c.por_defecto}` : ''].filter(Boolean).join(', ');
  let input;
  if (isBool(c)) {
    input = html`<select class="input mono" id="${id}" name="${c.columna}" ${bloqueado ? 'disabled' : ''}>
      ${nueva || c.nulo ? html`<option value="" ${v === null || v === undefined ? 'selected' : ''}>${nueva && c.por_defecto ? '(valor por defecto)' : '(vacío)'}</option>` : ''}
      <option value="true" ${v === true ? 'selected' : ''}>true</option><option value="false" ${v === false ? 'selected' : ''}>false</option></select>`;
  } else if (isJson(c)) {
    input = html`<textarea class="input mono" id="${id}" name="${c.columna}" rows="${Math.min(14, Math.max(3, valorInput(c, v).split('\n').length))}" spellcheck="false" ${bloqueado ? 'readonly' : ''}>${valorInput(c, v)}</textarea>`;
  } else {
    input = html`<input class="input mono" id="${id}" name="${c.columna}" value="${valorInput(c, v)}" ${isNum(c) ? 'inputmode="decimal"' : ''} ${bloqueado ? 'readonly' : ''} spellcheck="false" autocomplete="off">`;
  }
  return html`<div class="field"><label for="${id}" class="mono">${c.es_pk ? html`<span class="pk">${icon('key', 12)}</span> ` : ''}${c.columna}</label>${input}<span class="hint">${hint}</span></div>`;
}
function convertir(c, s, nueva) {
  if (s === '' || s === undefined) {
    if (nueva && c.por_defecto) return undefined; // que la base ponga su valor por defecto
    if (c.nulo) return null;
    if (isText(c)) return '';
    throw new Error(`La columna ${c.columna} es obligatoria`);
  }
  if (isBool(c)) return s === 'true';
  if (isNum(c)) { const n = parseNum(s); if (!Number.isFinite(n)) throw new Error(`${c.columna}: escribe un número`); if (/^(integer|bigint|smallint)/.test(c.tipo_dato) && !Number.isInteger(n)) throw new Error(`${c.columna}: debe ser un número entero`); return n; }
  if (isJson(c)) { try { return JSON.parse(s); } catch { throw new Error(`${c.columna}: el JSON no es válido`); } }
  return s;
}
const pkFilter = (t, row) => pkCols(t).map((c) => `${encodeURIComponent(c.columna)}=eq.${encodeURIComponent(row[c.columna])}`).join('&');

function editarFila(t, row, ctx) {
  const nueva = !row;
  const puede = editable(t);
  openDrawer({
    title: nueva ? `Nueva fila en ${t.name}` : `${t.name}${pkCols(t).length ? ` · ${pkCols(t).map((c) => row[c.columna]).join(', ')}` : ''}`,
    wide: true,
    noSubmit: !puede,
    submitLabel: nueva ? 'Insertar fila' : 'Guardar cambios',
    extraFoot: puede && !nueva ? html`<button type="button" class="btn btn-danger left" data-borrar>${icon('trash', 16)}Eliminar fila</button>` : '',
    body: html`${puede ? '' : html`<div class="note">${icon('lock', 14)} ${SOLO_LECTURA[t.name] || 'Esta tabla no tiene clave primaria: solo se puede leer.'}</div>`}
      <div class="form-grid">${t.cols.map((c) => html`<div class="${isJson(c) ? 'full' : ''}">${campo(c, row ? row[c.columna] : undefined, nueva)}</div>`)}</div>`,
    onMount(frm, close) {
      if (!puede) frm.querySelectorAll('input,select,textarea').forEach((x) => { x.disabled = true; });
      frm.addEventListener('click', async (e) => {
        if (!e.target.closest('[data-borrar]')) return;
        const ok = await confirmDialog({ title: 'Eliminar esta fila', body: html`Se borra de <span class="mono">${t.name}</span> para siempre. No se puede deshacer.`, confirm: 'Eliminar fila', danger: true });
        if (!ok) return;
        try { await db.remove(t.name, pkFilter(t, row)); toast('Fila eliminada'); close(); await despues(ctx); } catch (ex) { toast(ex.message, 'bad'); }
      });
    },
    async onSubmit(_d, frm) {
      const out = {};
      for (const c of t.cols) {
        if (c.es_pk && !nueva) continue;
        const el = frm.elements[c.columna];
        if (!el) continue;
        const v = convertir(c, el.value, nueva);
        if (v === undefined) continue;
        if (!nueva && JSON.stringify(v) === JSON.stringify(row[c.columna] ?? null)) continue; // sin cambios
        out[c.columna] = v;
      }
      if (!nueva && !Object.keys(out).length) { toast('No hay cambios que guardar'); return; }
      if (nueva) await db.insert(t.name, out); else await db.update(t.name, pkFilter(t, row), out);
      toast(nueva ? 'Fila insertada' : 'Fila actualizada');
      await despues(ctx);
    },
  });
}
async function despues(ctx) {
  await loadRows();
  try { st.counts[st.table] = (await db.page(st.table, 'select=' + encodeURIComponent(tdef().cols[0].columna), 0, 0)).total; } catch { /* sin conteo */ }
  ctx.rerender();
  loadAll().then(emit).catch(() => {}); // el resto del panel ve el cambio
}

function mount(root, ctx) {
  listen(root, ctx, {
    async click(e) {
      const tb = e.target.closest('[data-table]');
      if (tb) {
        st.table = tb.dataset.table; st.page = 0; st.filter = null; st.order = defaultOrder(tdef()); st.showCols = false;
        await loadRows(); ctx.rerender(); return;
      }
      const sb = e.target.closest('[data-sort]');
      if (sb) {
        const col = sb.dataset.sort;
        st.order = st.order?.col === col ? { col, dir: st.order.dir === 'asc' ? 'desc' : 'asc' } : { col, dir: 'asc' };
        st.page = 0; await loadRows(); ctx.rerender(); return;
      }
      const act = e.target.closest('[data-act]')?.dataset.act;
      const t = tdef();
      if (act === 'cols') { st.showCols = !st.showCols; ctx.rerender(); return; }
      if (act === 'prev' && st.page > 0) { st.page--; await loadRows(); ctx.rerender(); return; }
      if (act === 'next') { st.page++; await loadRows(); ctx.rerender(); return; }
      if (act === 'limpiar') { st.filter = null; st.page = 0; await loadRows(); ctx.rerender(); return; }
      if (act === 'nueva') return editarFila(t, null, ctx);
      if (act === 'csv') {
        try {
          const rows = await db.all(t.name, query(t));
          downloadCSV(`${t.name}.csv`, [t.cols.map((c) => c.columna), ...rows.map((r) => t.cols.map((c) => r[c.columna]))]);
          toast(`${rows.length} filas exportadas`);
        } catch (ex) { toast(ex.message, 'bad'); }
        return;
      }
      const tr = e.target.closest('tr[data-i]');
      if (tr) editarFila(t, st.rows[Number(tr.dataset.i)], ctx);
    },
    keydown(e) { if (e.key === 'Enter' && e.target.matches('tr[data-i]')) e.target.click(); },
    change(e) {
      const frm = e.target.closest('[data-form="filtro"]');
      if (frm && e.target.name === 'col') { st.filter = e.target.value ? { col: e.target.value, op: '', value: '' } : null; ctx.rerender(); }
    },
    async submit(e) {
      const frm = e.target.closest('[data-form="filtro"]');
      if (!frm) return;
      e.preventDefault();
      const col = frm.col.value, op = frm.op?.value, value = frm.value?.value ?? '';
      if (!col || !op) return;
      if (!['nulo', 'nonulo'].includes(op) && value === '') { toast('Escribe un valor para filtrar', 'bad'); return; }
      st.filter = { col, op, value: (op === 'desde' || op === 'antes') && value ? new Date(value + 'T00:00').toISOString() : value };
      st.filter.shown = value;
      st.page = 0; await loadRows(); ctx.rerender();
    },
  });
}

export default {
  path: 'basedatos', title: 'Base de datos', icon: 'database',
  subtitle: () => 'Tablas de Postgres en Supabase',
  load: async (full) => { if (full) { st.schema = null; } await load(); },
  reload: async () => {}, // no se recarga sola para no mover lo que estas revisando
  render, mount,
};
export { esc };

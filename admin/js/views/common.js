// Piezas compartidas por las pantallas.
import { html, usd, bs, fecha, hora, addDays, startOfDay, mondayOf, inputDate, MESES } from '../util.js';
import { icon } from '../icons.js';
import { toBs, lastCloseAt } from '../store.js';

export function tile(label, value, sub = '', { hero = false, cls = '' } = {}) {
  return html`<div class="tile ${hero ? 'hero' : ''}"><div class="t-label">${label}</div><div class="t-value ${cls}">${value}</div>${sub ? html`<div class="t-sub">${sub}</div>` : ''}</div>`;
}
export const money = (v) => html`<span class="nowrap">${usd(v)}</span>`;
export const dual = (v) => html`${usd(v)} <span class="muted">${bs(toBs(v))}</span>`;
export function empty(title, text = '') { return html`<div class="empty"><strong>${title}</strong>${text}</div>`; }

export function stockBadge(stock, min) {
  if (Number(stock) <= 0) return html`<span class="badge bad">${icon('xCircle', 14)}Agotado</span>`;
  if (Number(stock) <= Number(min)) return html`<span class="badge warn">${icon('alert', 14)}Por agotarse</span>`;
  return html`<span class="badge good">${icon('checkCircle', 14)}Suficiente</span>`;
}
export function makeableBadge(m) {
  if (m < 0) return html`<span class="muted small">Sin receta</span>`;
  if (m === 0) return html`<span class="badge bad">${icon('xCircle', 14)}No alcanza</span>`;
  if (m <= 5) return html`<span class="badge warn">${icon('alert', 14)}${m}</span>`;
  return html`<span class="num">${m >= 1000 ? '999+' : m}</span>`;
}

export function seg(name, options, value) {
  return html`<div class="seg" role="group" data-seg="${name}">${options.map(([v, label]) => html`<button type="button" data-v="${v}" aria-pressed="${String(v === value)}">${label}</button>`)}</div>`;
}

// ---------- Periodos para filtrar (ventas, gastos, anulaciones) ----------
export const PRESETS = [
  ['turno', 'Turno actual'], ['hoy', 'Hoy'], ['7', '7 días'], ['30', '30 días'], ['mes', 'Este mes'], ['rango', 'Fechas…'],
];
/** Devuelve { from: Date|null, to: Date|null, label } (from null = sin limite inferior). */
export function presetRange(p, desde, hasta) {
  const hoy = startOfDay(new Date());
  const man = addDays(hoy, 1);
  switch (p) {
    case 'turno': { const lc = lastCloseAt(); return { from: lc ? new Date(lc) : null, to: null, strict: true, label: lc ? `Desde el cierre del ${fecha(lc)} a las ${hora(lc)}` : 'Sin cierres de caja todavía: todo el historial' }; }
    case 'hoy': return { from: hoy, to: man, label: `Hoy, ${fecha(hoy)}` };
    case '7': return { from: addDays(hoy, -6), to: man, label: `Del ${fecha(addDays(hoy, -6))} al ${fecha(hoy)}` };
    case '30': return { from: addDays(hoy, -29), to: man, label: `Del ${fecha(addDays(hoy, -29))} al ${fecha(hoy)}` };
    case 'mes': { const i = new Date(hoy.getFullYear(), hoy.getMonth(), 1); return { from: i, to: man, label: `${MESES[i.getMonth()][0].toUpperCase() + MESES[i.getMonth()].slice(1)} ${i.getFullYear()}` }; }
    case 'todo': return { from: null, to: null, label: 'Todo el historial' };
    case 'rango': {
      const d = desde ? new Date(desde + 'T00:00') : addDays(hoy, -6);
      const h = hasta ? addDays(new Date(hasta + 'T00:00'), 1) : man;
      return { from: d, to: h, label: `Del ${fecha(d)} al ${fecha(addDays(h, -1))}` };
    }
    default: return { from: null, to: null, label: '' };
  }
}
export function inRange(at, r) {
  const t = new Date(at).getTime();
  if (r.from && (r.strict ? t <= r.from.getTime() : t < r.from.getTime())) return false;
  if (r.to && t >= r.to.getTime()) return false;
  return true;
}
export function rangeInputs(st) {
  return st.preset === 'rango' ? html`<div class="row">
    <input class="input sm" type="date" data-k="desde" value="${st.desde || inputDate(addDays(new Date(), -6))}" aria-label="Desde">
    <span class="muted">a</span>
    <input class="input sm" type="date" data-k="hasta" value="${st.hasta || inputDate(new Date())}" aria-label="Hasta"></div>` : '';
}

/** Semana (lunes a domingo) o mes, con desplazamiento hacia atras. */
export function calendarPeriod(modo, offset) {
  const n = new Date();
  if (modo === 'semana') {
    const ini = addDays(mondayOf(n), 7 * offset);
    const fin = addDays(ini, 7);
    return { from: ini, to: fin, label: `Del ${fecha(ini)} al ${fecha(addDays(fin, -1))}`, days: 7 };
  }
  const ini = new Date(n.getFullYear(), n.getMonth() + offset, 1);
  const fin = new Date(ini.getFullYear(), ini.getMonth() + 1, 1);
  const m = MESES[ini.getMonth()];
  return { from: ini, to: fin, label: `${m[0].toUpperCase() + m.slice(1)} ${ini.getFullYear()}`, days: Math.round((fin - ini) / 864e5) };
}

export function origen(s) {
  if (s.table_number) return `Mesa ${s.table_number}`;
  return s.customer ? `Para llevar: ${s.customer}` : 'Para llevar';
}

/** Registra eventos en la vista; se cancelan solos al redibujar (ctx.signal). */
export function listen(root, ctx, handlers) {
  for (const [type, fn] of Object.entries(handlers)) root.addEventListener(type, fn, { signal: ctx.signal });
  // Enter sobre una fila con tabindex abre su detalle
  if (!handlers.keydown) root.addEventListener('keydown', (e) => { if (e.key === 'Enter' && e.target.matches('tr[data-id][tabindex]')) e.target.click(); }, { signal: ctx.signal });
}
/** Re-dibuja manteniendo el foco en el buscador. */
export function keepFocus(root, sel) {
  const i = root.querySelector(sel);
  if (i) { i.focus(); const n = i.value.length; try { i.setSelectionRange(n, n); } catch { /* type=search en algunos navegadores */ } }
}

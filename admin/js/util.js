// Utilidades: plantillas HTML seguras, formato de numeros y fechas, avisos, ventanas.

// ---------- Plantillas HTML con escape automatico ----------
class Safe { constructor(s) { this.s = s; } toString() { return this.s; } }
export const raw = (s) => new Safe(String(s ?? ''));
export function esc(v) {
  return String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
function part(v) {
  if (v === null || v === undefined || v === false) return '';
  if (v instanceof Safe) return v.s;
  if (Array.isArray(v)) return v.map(part).join('');
  return esc(v);
}
export function html(strings, ...vals) {
  let out = strings[0];
  for (let i = 0; i < vals.length; i++) out += part(vals[i]) + strings[i + 1];
  return new Safe(out);
}

// ---------- Numeros (formato venezolano: 1.234,56) ----------
export function num(v, dec = 2) {
  const n = Number(v) || 0;
  const neg = n < 0;
  const [ent, frac] = Math.abs(n).toFixed(dec).split('.');
  const g = ent.replace(/\B(?=(\d{3})+(?!\d))/g, '.');
  return (neg ? '-' : '') + (dec > 0 ? `${g},${frac}` : g);
}
export const usd = (v) => (Number(v) < 0 ? '-$' : '$') + num(Math.abs(Number(v) || 0));
export const bs = (v) => 'Bs ' + num(v);
export function qty(v) {
  const n = Number(v) || 0;
  return Number.isInteger(n) ? num(n, 0) : num(n, 2).replace(/,?0+$/, '');
}
export function compact(v) {
  const n = Math.abs(v);
  if (n >= 1e6) return (v / 1e6).toFixed(1).replace('.', ',') + ' M';
  if (n >= 1e4) return Math.round(v / 1e3) + ' mil';
  return num(v, n < 10 && n % 1 ? 1 : 0);
}
export function parseNum(s) {
  if (s === null || s === undefined) return NaN;
  let t = String(s).trim().replace(/\s/g, '');
  if (t === '') return NaN;
  // "1.234,56" -> 1234.56 ; "12,5" -> 12.5 ; "12.5" -> 12.5
  if (t.includes(',') && t.includes('.')) t = t.replace(/\./g, '').replace(',', '.');
  else t = t.replace(',', '.');
  const n = Number(t);
  return Number.isFinite(n) ? n : NaN;
}
export const pct = (v) => (Number.isFinite(v) ? num(v * 100, 0) + '%' : '—');

// ---------- Fechas (hora local del navegador) ----------
const two = (n) => String(n).padStart(2, '0');
export const toDate = (v) => (v instanceof Date ? v : new Date(v));
export const fecha = (v) => { const d = toDate(v); return `${two(d.getDate())}/${two(d.getMonth() + 1)}/${d.getFullYear()}`; };
export const hora = (v) => { const d = toDate(v); return `${two(d.getHours())}:${two(d.getMinutes())}`; };
export const fechaHora = (v) => `${fecha(v)} ${hora(v)}`;
export const DIAS = ['dom', 'lun', 'mar', 'mié', 'jue', 'vie', 'sáb'];
export const MESES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
export const dayKey = (v) => { const d = toDate(v); return `${d.getFullYear()}-${two(d.getMonth() + 1)}-${two(d.getDate())}`; };
export const startOfDay = (v) => { const d = toDate(v); return new Date(d.getFullYear(), d.getMonth(), d.getDate()); };
export const addDays = (v, n) => { const d = toDate(v); return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n); };
export const mondayOf = (v) => { const d = startOfDay(v); return addDays(d, -((d.getDay() + 6) % 7)); };
export const inputDate = (v) => dayKey(v);
export const inputDateTime = (v) => { const d = toDate(v); return `${dayKey(d)}T${two(d.getHours())}:${two(d.getMinutes())}`; };
export function haceRato(v) {
  if (!v) return '';
  const s = Math.round((Date.now() - toDate(v).getTime()) / 1000);
  if (s < 45) return 'hace un momento';
  if (s < 3600) return `hace ${Math.round(s / 60)} min`;
  return 'a las ' + hora(v);
}

// ---------- DOM ----------
export const $ = (sel, root = document) => root.querySelector(sel);
export const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
export function setHTML(el, safe) { el.innerHTML = String(safe); }
export function debounce(fn, ms = 250) { let t; return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); }; }
export function formData(form) {
  const o = {};
  for (const [k, v] of new FormData(form).entries()) o[k] = typeof v === 'string' ? v.trim() : v;
  for (const cb of form.querySelectorAll('input[type=checkbox][name]')) o[cb.name] = cb.checked;
  return o;
}
export const storage = {
  get(k, def = null) { try { const v = localStorage.getItem(k); return v === null ? def : v; } catch { return def; } },
  set(k, v) { try { v === null ? localStorage.removeItem(k) : localStorage.setItem(k, v); } catch { /* sin almacenamiento */ } },
};

// ---------- Avisos ----------
export function toast(msg, kind = '') {
  const box = document.getElementById('toasts');
  const t = document.createElement('div');
  t.className = 'toast ' + kind;
  t.textContent = msg;
  box.appendChild(t);
  setTimeout(() => t.remove(), kind === 'bad' ? 6000 : 3200);
}

// ---------- Ventanas: confirmacion y panel lateral ----------
const overlays = () => document.getElementById('overlays');
let lastFocus = null;
function trapEsc(close) {
  const h = (e) => { if (e.key === 'Escape') { e.preventDefault(); close(); } };
  document.addEventListener('keydown', h);
  return () => document.removeEventListener('keydown', h);
}

export function confirmDialog({ title, body = '', confirm = 'Confirmar', danger = false, cancel = 'Cancelar' }) {
  return new Promise((resolve) => {
    lastFocus = document.activeElement;
    const wrap = document.createElement('div');
    wrap.innerHTML = String(html`<div class="scrim top"></div>
      <div class="modal" role="dialog" aria-modal="true" aria-labelledby="m-title">
        <h2 id="m-title">${title}</h2>
        <div class="m-body">${body}</div>
        <div class="m-actions">
          <button class="btn" data-r="0">${cancel}</button>
          <button class="btn ${danger ? 'btn-danger solid' : 'btn-primary'}" data-r="1">${confirm}</button>
        </div>
      </div>`);
    overlays().appendChild(wrap);
    const done = (v) => { off(); wrap.remove(); lastFocus?.focus?.(); resolve(v); };
    const off = trapEsc(() => done(false));
    wrap.addEventListener('click', (e) => {
      const b = e.target.closest('[data-r]');
      if (b) done(b.dataset.r === '1');
      else if (e.target.classList.contains('scrim')) done(false);
    });
    wrap.querySelector('[data-r="1"]').focus();
  });
}

/**
 * Panel lateral con formulario.
 *  title, body (html), submitLabel, wide, danger: {label, onClick}
 *  onSubmit(data, form) -> Promise; si lanza error se muestra arriba del formulario.
 *  onMount(drawerEl, close)
 */
export function openDrawer({ title, body, submitLabel = 'Guardar', wide = false, onSubmit, onMount, extraFoot = '', noSubmit = false }) {
  lastFocus = document.activeElement;
  const wrap = document.createElement('div');
  wrap.innerHTML = String(html`<div class="scrim"></div>
    <form class="drawer ${wide ? 'wide' : ''}" role="dialog" aria-modal="true" aria-labelledby="d-title" novalidate>
      <div class="drawer-head">
        <h2 id="d-title">${title}</h2>
        <button type="button" class="icon-btn" data-close aria-label="Cerrar">${raw(ICON_X)}</button>
      </div>
      <div class="drawer-body">
        <div class="form-error hidden" role="alert"></div>
        ${body}
      </div>
      <div class="drawer-foot">
        ${raw(String(extraFoot))}
        <button type="button" class="btn" data-close>${noSubmit ? 'Cerrar' : 'Cancelar'}</button>
        ${noSubmit ? '' : html`<button type="submit" class="btn btn-primary" data-submit>${submitLabel}</button>`}
      </div>
    </form>`);
  overlays().appendChild(wrap);
  const form = wrap.querySelector('form');
  const errBox = wrap.querySelector('.form-error');
  const close = () => { off(); wrap.remove(); lastFocus?.focus?.(); };
  const off = trapEsc(close);
  wrap.addEventListener('click', (e) => {
    if (e.target.closest('[data-close]') || e.target.classList.contains('scrim')) close();
  });
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    if (!onSubmit) return;
    const btn = form.querySelector('[data-submit]');
    errBox.classList.add('hidden');
    btn.disabled = true;
    const label = btn.textContent;
    btn.textContent = 'Guardando…';
    try {
      const r = await onSubmit(formData(form), form);
      if (r !== false) close();
    } catch (err) {
      errBox.textContent = err?.message || String(err);
      errBox.classList.remove('hidden');
      errBox.scrollIntoView({ block: 'nearest' });
    } finally {
      btn.disabled = false; btn.textContent = label;
    }
  });
  const first = form.querySelector('.drawer-body input:not([type=hidden]), .drawer-body select, .drawer-body textarea');
  (first || form.querySelector('[data-close]')).focus();
  onMount?.(form, close);
  return { form, close, error(msg) { errBox.textContent = msg; errBox.classList.remove('hidden'); } };
}
const ICON_X = '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg>';

// ---------- CSV ----------
export function downloadCSV(name, rows) {
  const cell = (v) => {
    const s = v === null || v === undefined ? '' : typeof v === 'object' ? JSON.stringify(v) : String(v);
    return /[";\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  // ";" como separador: Excel en espanol lo abre en columnas sin configurar nada.
  const text = '﻿' + rows.map((r) => r.map(cell).join(';')).join('\r\n');
  const url = URL.createObjectURL(new Blob([text], { type: 'text/csv;charset=utf-8' }));
  const a = Object.assign(document.createElement('a'), { href: url, download: name });
  document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 2000);
}

// ---------- PIN (misma regla que la base de datos) ----------
export function pinDebil(p) {
  if (!/^[0-9]{6}$/.test(p)) return false;
  if (/^(\d)\1{5}$/.test(p) || /^(\d\d)\1\1$/.test(p) || /^(\d\d\d)\1$/.test(p)) return true;
  if (/^(\d)(\d)(\d)\3\2\1$/.test(p) || /^(\d)\1(\d)\2(\d)\3$/.test(p)) return true;
  const e = '0123456789012345678901234567890';
  return e.includes(p) || [...e].reverse().join('').includes(p);
}
export function revisarPin(p) {
  if (!/^[0-9]{6}$/.test(p)) return 'El PIN debe ser de 6 números';
  if (pinDebil(p)) return 'Ese PIN es muy fácil de adivinar (como 123456 o 111111). Elige otro.';
  return null;
}

// Graficos en SVG sin librerias: columnas agrupadas (con tooltip) y barras horizontales.
import { esc, html, raw } from './util.js';

function niceStep(max, ticks = 4) {
  if (max <= 0) return 1;
  const rough = max / ticks;
  const p = Math.pow(10, Math.floor(Math.log10(rough)));
  const n = rough / p;
  return (n <= 1 ? 1 : n <= 2 ? 2 : n <= 2.5 ? 2.5 : n <= 5 ? 5 : 10) * p;
}

/**
 * Columnas agrupadas.
 * el: contenedor; labels: ['lun 3', ...]; titles: textos largos del tooltip
 * series: [{ name, cls: 'bar-1', values: [...] }]
 * fmt: formato de valores; tick: formato de eje
 */
export function columns(el, { labels, titles, series, fmt, tick = fmt, height = 240 }) {
  const draw = () => {
    const W = Math.max(280, el.clientWidth || 600);
    const H = height;
    const m = { t: 10, r: 8, b: 26, l: 52 };
    const iw = W - m.l - m.r, ih = H - m.t - m.b;
    const max = Math.max(0, ...series.flatMap((s) => s.values));
    const step = niceStep(max || 1);
    const top = Math.max(step, Math.ceil((max || 1) / step) * step);
    const y = (v) => m.t + ih - (v / top) * ih;
    const n = labels.length;
    const band = iw / Math.max(1, n);
    const gap = 2;
    const bw = Math.max(3, Math.min(24, (band * 0.72 - gap * (series.length - 1)) / series.length));
    const groupW = bw * series.length + gap * (series.length - 1);
    const every = Math.max(1, Math.ceil(n / Math.floor(iw / 46)));
    let g = '';
    for (let v = 0; v <= top + 1e-9; v += step) {
      g += `<line class="${v === 0 ? 'baseline' : 'gridline'}" x1="${m.l}" x2="${W - m.r}" y1="${y(v)}" y2="${y(v)}"/>`;
      g += `<text class="tick" x="${m.l - 8}" y="${y(v) + 4}" text-anchor="end">${esc(tick(v))}</text>`;
    }
    let bars = '';
    labels.forEach((lab, i) => {
      const x0 = m.l + band * i + (band - groupW) / 2;
      let marks = '';
      series.forEach((s, k) => {
        const v = s.values[i] || 0;
        if (v <= 0) return;
        const x = x0 + k * (bw + gap);
        const h = Math.max(1, y(0) - y(v));
        const r = Math.min(4, bw / 2, h);
        const yt = y(0) - h;
        // esquinas redondeadas solo arriba; base recta sobre la linea de cero
        marks += `<path class="bar ${s.cls}" d="M${x},${y(0)} V${yt + r} Q${x},${yt} ${x + r},${yt} H${x + bw - r} Q${x + bw},${yt} ${x + bw},${yt + r} V${y(0)} Z"/>`;
      });
      const label = i % every === 0 ? `<text class="tick" x="${m.l + band * i + band / 2}" y="${H - 8}" text-anchor="middle">${esc(lab)}</text>` : '';
      bars += `<g class="band" tabindex="0" data-i="${i}" role="img" aria-label="${esc((titles || labels)[i] + ': ' + series.map((s) => `${s.name} ${fmt(s.values[i] || 0)}`).join(', '))}">
        <rect class="hit" x="${m.l + band * i}" y="${m.t}" width="${band}" height="${ih}" rx="4"/>${marks}</g>${label}`;
    });
    el.innerHTML = `<svg viewBox="0 0 ${W} ${H}" height="${H}" role="group">${g}${bars}</svg><div class="tooltip hidden"></div>`;
    const tip = el.querySelector('.tooltip');
    const show = (gEl) => {
      const i = Number(gEl.dataset.i);
      tip.innerHTML = String(html`<div class="tt-title">${(titles || labels)[i]}</div>${series.map((s) => html`<div class="tt-row"><span class="key" style="background:var(--series-${s.cls === 'bar-2' ? 2 : 1})"></span><b>${fmt(s.values[i] || 0)}</b><span class="nm">${s.name}</span></div>`)}`);
      const x = m.l + band * i + band / 2;
      const ymax = Math.min(...series.map((s) => y(s.values[i] || 0)));
      tip.style.left = `${Math.min(Math.max(x, 90), W - 90)}px`;
      tip.style.top = `${Math.max(ymax - 8, 40)}px`;
      tip.classList.remove('hidden');
      el.querySelectorAll('.band.focus').forEach((b) => b.classList.remove('focus'));
      gEl.classList.add('focus');
    };
    const hide = () => { tip.classList.add('hidden'); el.querySelectorAll('.band.focus').forEach((b) => b.classList.remove('focus')); };
    el.querySelectorAll('.band').forEach((b) => {
      b.addEventListener('pointerenter', () => show(b));
      b.addEventListener('focus', () => show(b));
      b.addEventListener('blur', hide);
    });
    el.querySelector('svg').addEventListener('pointerleave', hide);
  };
  draw();
  const ro = new ResizeObserver(() => { if (el.isConnected) draw(); else ro.disconnect(); });
  ro.observe(el);
}

export function legend(series) {
  return html`<div class="legend">${series.map((s) => html`<span><i style="background:var(--series-${s.cls === 'bar-2' ? 2 : 1})"></i>${s.name}</span>`)}</div>`;
}

/** Barras horizontales de una sola serie (valor al final de la etiqueta). */
export function hbars(items, fmt) {
  const max = Math.max(0, ...items.map((x) => x.value));
  if (!items.length) return html`<div class="empty small">Sin datos en este periodo</div>`;
  return html`<div class="hbars">${items.map((x) => html`
    <div class="hbar" title="${x.label}: ${fmt(x.value)}">
      <span class="hb-label">${x.label}${x.sub ? html` <span class="muted small">${x.sub}</span>` : ''}</span>
      <span class="hb-val">${fmt(x.value)}</span>
      <div class="hb-track"><div class="hb-fill" style="width:${max > 0 ? Math.max(1, (x.value / max) * 100) : 0}%"></div></div>
    </div>`)}</div>`;
}
export { raw };

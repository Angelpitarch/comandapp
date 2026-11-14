// Datos del negocio en memoria + las mismas reglas de calculo que usa la app (lib/main.dart).
import { db, f } from './api.js';
import { addDays, startOfDay } from './util.js';

export const GASTO_CATS = {
  ingredientes: 'Ingredientes / compras',
  servicios: 'Servicios (luz, agua, gas)',
  sueldos: 'Sueldos',
  alquiler: 'Alquiler',
  transporte: 'Transporte',
  otros: 'Otros',
};
export const METODOS = ['Efectivo Bs', 'Efectivo USD', 'Pago movil', 'Tarjeta'];
export const ROLES = { admin: 'Administrador', mesero: 'Mesero / Cajero', cocina: 'Cocina' };
export const UNIDADES = ['kg', 'g', 'unidad', 'litro', 'ml', 'paquete', 'bolsa'];
export const TAMANOS = [{ name: 'Pequena', delta: -0.5 }, { name: 'Mediana', delta: 0 }, { name: 'Grande', delta: 0.8 }];

export const S = {
  me: null,
  config: { rate: 0, business_name: '' },
  products: [], ingredients: [], categories: [], users: [], employees: [],
  tables: [], takeaways: [], accountItems: [], openTickets: [],
  closes: [], gastos: [], cancellations: [], turnoSales: [],
  loadedAt: null,
};

const listeners = new Set();
export const onChange = (fn) => { listeners.add(fn); return () => listeners.delete(fn); };
export const emit = () => listeners.forEach((fn) => fn());

// ---------- Carga ----------
const salesCache = new Map();
export const load = {
  async config() { const r = await db.select('app_config', 'select=*&id=eq.1'); if (r[0]) S.config = r[0]; },
  async products() { S.products = await db.all('products', 'select=*&order=name'); },
  async ingredients() { S.ingredients = await db.all('ingredients', 'select=*&order=name'); },
  async categories() { S.categories = await db.all('categories', 'select=*&order=position'); },
  async users() { S.users = await db.all('app_users', 'select=id,name,role,active,email,created_at&order=name'); },
  async employees() { S.employees = await db.all('employees', 'select=*&order=name'); },
  async tables() { S.tables = await db.all('dining_tables', 'select=*&order=number'); },
  async takeaways() { S.takeaways = await db.all('takeaways', 'select=*&order=created_at'); },
  async accountItems() { S.accountItems = await db.all('account_items', 'select=*'); },
  async openTickets() { S.openTickets = await db.all('tickets', 'select=*&status=not.in.(entregada,anulada)&order=sent_at'); },
  async closes() { S.closes = await db.all('cash_closes', 'select=*&order=closed_at.desc'); },
  async gastos() { S.gastos = await db.all('gastos', 'select=*&order=at.desc'); },
  async cancellations() { S.cancellations = await db.all('cancellations', 'select=*&order=at.desc'); },
  async turnoSales() {
    const lc = lastCloseAt();
    S.turnoSales = await db.all('sales', 'select=*&order=at.desc' + (lc ? '&' + f.gt('at', lc) : ''));
  },
};

/** Carga inicial completa. */
export async function loadAll() {
  await load.closes(); // el turno depende del ultimo cierre
  await Promise.all([
    load.config(), load.products(), load.ingredients(), load.categories(), load.users(), load.employees(),
    load.tables(), load.takeaways(), load.accountItems(), load.openTickets(), load.gastos(), load.cancellations(), load.turnoSales(),
  ]);
  salesCache.clear();
  S.loadedAt = new Date();
}
/** Actualizacion periodica: solo lo que cambia durante el turno. */
export async function loadLive() {
  await load.closes();
  await Promise.all([load.config(), load.tables(), load.takeaways(), load.accountItems(), load.openTickets(), load.turnoSales(), load.gastos(), load.ingredients()]);
  salesCache.clear();
  S.loadedAt = new Date();
}

/** Ventas en un rango [desde, hasta). Se guarda en memoria hasta la siguiente actualizacion. */
export async function salesBetween(from, to) {
  const key = `${+from}-${+to}`;
  if (!salesCache.has(key)) {
    salesCache.set(key, db.all('sales', `select=*&order=at.desc&${f.gte('at', from.toISOString())}&${f.lt('at', to.toISOString())}`)
      .catch((e) => { salesCache.delete(key); throw e; }));
  }
  return salesCache.get(key);
}
export const clearSalesCache = () => salesCache.clear();

// ---------- Reglas del negocio (iguales a la app) ----------
export const rate = () => Number(S.config.rate) || 0;
export const toUsd = (amt, cur) => (cur === 'ves' ? (rate() > 0 ? Number(amt) / rate() : 0) : Number(amt) || 0);
export const toBs = (usdAmount) => (Number(usdAmount) || 0) * rate();
export const lastCloseAt = () => S.closes[0]?.closed_at || null;
export const productById = (id) => S.products.find((p) => p.id === id) || null;
export const ingredientById = (id) => S.ingredients.find((i) => i.id === id) || null;
export const catLabel = (key) => S.categories.find((c) => c.key === key)?.label || (key ? key : 'Otros');
export const catEmoji = (key) => S.categories.find((c) => c.key === key)?.emoji || '';
export const priceUsd = (p) => toUsd(p.price, p.currency);

export function productCost(p, depth = 0) {
  if (!p || depth > 6) return 0;
  if ((p.combo_items || []).length) {
    return p.combo_items.reduce((s, c) => { const cp = productById(c.product_id); return s + (cp ? productCost(cp, depth + 1) * Number(c.qty || 0) : 0); }, 0);
  }
  return (p.recipe || []).reduce((s, r) => { const i = ingredientById(r.ingredient_id); return s + (i ? toUsd(i.cost, i.cost_currency) * Number(r.qty || 0) : 0); }, 0);
}
export const hasCostData = (p) => (p.combo_items || []).length > 0 || (p.recipe || []).length > 0;

/** Cuantas unidades alcanzan con el inventario actual. -1 = no aplica (sin receta). */
export function maxMakeable(p, depth = 0) {
  if (!p || depth > 6) return -1;
  const BIG = 1e9;
  let m = BIG;
  if ((p.combo_items || []).length) {
    for (const c of p.combo_items) {
      const cp = productById(c.product_id);
      if (!cp || !(c.qty > 0)) continue;
      const cm = maxMakeable(cp, depth + 1);
      if (cm < 0) continue;
      m = Math.min(m, Math.floor(cm / c.qty));
    }
    return m === BIG ? -1 : m;
  }
  if ((p.recipe || []).length) {
    for (const r of p.recipe) {
      const i = ingredientById(r.ingredient_id);
      if (!i || !(r.qty > 0)) continue;
      m = Math.min(m, Math.floor(Number(i.stock) / r.qty));
    }
    return m === BIG ? -1 : m;
  }
  return -1;
}

/** Costo estimado de una lista de ventas (por nombre de producto, con costos de hoy). */
export function salesCost(list) {
  const byName = new Map();
  for (const p of S.products) if (!byName.has(p.name)) byName.set(p.name, p);
  let c = 0;
  for (const s of list) for (const l of s.lines || []) { const p = byName.get(l.name); if (p) c += productCost(p) * Number(l.qty || 0); }
  return c;
}

export function summarize(sales) {
  const byMethod = new Map();
  const units = new Map();
  const revenue = new Map();
  let total = 0;
  for (const s of sales) {
    total += Number(s.total_usd) || 0;
    for (const p of s.payments || []) byMethod.set(p.method, (byMethod.get(p.method) || 0) + (Number(p.amountUsd) || 0));
    for (const l of s.lines || []) {
      units.set(l.name, (units.get(l.name) || 0) + (Number(l.qty) || 0));
      revenue.set(l.name, (revenue.get(l.name) || 0) + (Number(l.lineUsd) || 0));
    }
  }
  return { total, count: sales.length, byMethod, units, revenue };
}

export function gastosSince(fromIso) {
  return fromIso ? S.gastos.filter((g) => new Date(g.at) > new Date(fromIso)) : S.gastos.slice();
}
export const sum = (arr, fn) => arr.reduce((s, x) => s + (Number(fn(x)) || 0), 0);

export function tableHasAccount(n) { return S.accountItems.some((a) => a.table_number === n); }
/** Lo que falta por cobrar antes de cerrar la caja (misma regla que la app). */
export function pendingToClose() {
  const mesas = S.tables.filter((t) => !['pago_espera', 'pago_servido', 'pagada'].includes(t.status) && tableHasAccount(t.number));
  const llevar = S.takeaways.filter((t) => t.status !== 'pagada');
  return { mesas, llevar };
}
export const openAccountsUsd = () => sum(S.accountItems, (a) => Number(a.unit_usd) * Number(a.qty));

export function lowIngredients() { return S.ingredients.filter((i) => Number(i.stock) <= Number(i.min_stock)); }
export function lowProducts(threshold = 5) {
  return S.products.map((p) => ({ p, m: maxMakeable(p) })).filter((x) => x.m >= 0 && x.m <= threshold).sort((a, b) => a.m - b.m);
}

// ---------- Acciones que combinan varias tablas ----------
export async function cerrarCaja() {
  await load.closes();
  await load.turnoSales();
  const lc = lastCloseAt();
  const ventas = S.turnoSales;
  const r = summarize(ventas);
  const gastosUsd = sum(gastosSince(lc), (g) => g.amount_usd);
  await db.insert('cash_closes', {
    from_at: lc,
    total_usd: r.total,
    accounts_count: r.count,
    by_method: Object.fromEntries(r.byMethod),
    units: Object.fromEntries(r.units),
    gastos_usd: gastosUsd,
  });
  // Igual que "cierreDeTurno" en la app: reinicia mesas, pedidos y comandas. No borra ventas.
  const todos = 'id=neq.00000000-0000-0000-0000-000000000000';
  await db.removeMany('account_items', todos);
  await db.removeMany('takeaways', todos);
  await db.patchMany('tickets', 'status=not.in.(anulada,entregada)', { status: 'entregada' });
  await db.patchMany('dining_tables', 'number=gt.0', { status: 'disponible', waiter: null, opened_at: null });
}

export function slug(s) {
  const base = s.trim().toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
  return base || `cat_${Date.now()}`;
}

export const periodo = {
  hoy: () => [startOfDay(new Date()), addDays(startOfDay(new Date()), 1)],
};

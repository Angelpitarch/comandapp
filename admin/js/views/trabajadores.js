// Trabajadores: ficha, cargo, horario y sueldo.
import { html, raw, num, parseNum, openDrawer, confirmDialog, toast, debounce, downloadCSV } from '../util.js';
import { icon } from '../icons.js';
import { db, f } from '../api.js';
import { S, load as L, emit, sum } from '../store.js';
import { tile, empty, listen, keepFocus } from './common.js';

const st = { q: '', activos: true };

function lista() {
  const q = st.q.toLowerCase();
  return S.employees.filter((e) => (!st.activos || e.active) && (!q || `${e.name} ${e.position || ''} ${e.cedula || ''}`.toLowerCase().includes(q)));
}

function render() {
  const rows = lista();
  const activos = S.employees.filter((e) => e.active);
  const nomina = sum(activos, (e) => Number(e.salary) - Number(e.deductions));
  return html`
  <div class="tiles">
    ${tile('Trabajadores activos', num(activos.length, 0), `${S.employees.length - activos.length} inactivos`)}
    ${tile('Nómina neta', num(nomina), 'Suma de sueldos menos descuentos de los activos')}
  </div>
  <div class="toolbar">
    <label class="search">${icon('search', 16)}<span class="sr-only">Buscar trabajador</span><input class="input sm" type="search" data-k="q" placeholder="Buscar nombre, cargo o cédula" value="${st.q}"></label>
    <label class="switch"><input type="checkbox" data-k="activos" ${st.activos ? 'checked' : ''}><span class="track"></span>Solo activos</label>
    <div class="grow"></div>
    <button class="btn btn-sm" data-act="csv">${icon('download', 16)}Exportar</button>
    <button class="btn btn-primary" data-act="nuevo">${icon('plus', 16)}Nuevo trabajador</button>
  </div>
  <section class="card card-flush">
    ${rows.length ? html`<div class="table-wrap"><table class="table">
      <thead><tr><th>Nombre</th><th>Cargo</th><th>Horario</th><th>Teléfono</th><th class="r">Sueldo</th><th class="r">Descuentos</th><th class="r">Neto</th><th>Estado</th></tr></thead>
      <tbody>${rows.map((e) => html`<tr class="clickable" data-id="${e.id}" tabindex="0">
        <td><div class="t-main">${e.name || '(sin nombre)'}</div>${e.cedula ? html`<div class="t-sub">C.I. ${e.cedula}</div>` : ''}</td>
        <td>${e.position || html`<span class="muted">—</span>`}</td><td>${e.schedule || html`<span class="muted">—</span>`}</td>
        <td class="nowrap">${e.phone || html`<span class="muted">—</span>`}</td>
        <td class="r">${num(e.salary)}</td><td class="r">${num(e.deductions)}</td><td class="r t-main">${num(Number(e.salary) - Number(e.deductions))}</td>
        <td>${e.active ? html`<span class="badge good">${icon('checkCircle', 13)}Activo</span>` : html`<span class="badge neutral">${icon('xCircle', 13)}Inactivo</span>`}</td></tr>`)}</tbody>
    </table></div>` : empty('No hay trabajadores', S.employees.length ? 'Cambia la búsqueda o muestra también los inactivos.' : 'Agrega el primero con "Nuevo trabajador".')}
  </section>
  <p class="muted small" style="margin-top:10px">Los sueldos se guardan como número, sin moneda, igual que en la app.</p>`;
}

function form(e) {
  const nuevo = !e;
  e = e || { name: '', cedula: '', birthdate: '', phone: '', address: '', position: '', schedule: '', salary: 0, deductions: 0, notes: '', active: true };
  const campo = (name, label, extra = '') => html`<div class="field"><label for="e-${name}">${label}</label><input class="input" id="e-${name}" name="${name}" value="${e[name] || ''}" ${raw(extra)}></div>`;
  openDrawer({
    title: nuevo ? 'Nuevo trabajador' : `Editar ${e.name}`,
    submitLabel: nuevo ? 'Guardar trabajador' : 'Guardar cambios',
    extraFoot: nuevo ? '' : html`<button type="button" class="btn btn-danger left" data-borrar>${icon('trash', 16)}Eliminar</button>`,
    body: html`<div class="form-grid">
      <div class="field full"><label for="e-name">Nombre completo</label><input class="input" id="e-name" name="name" value="${e.name}" required></div>
      ${campo('cedula', 'Cédula o documento')}${campo('birthdate', 'Fecha de nacimiento', 'placeholder="DD/MM/AAAA"')}
      ${campo('phone', 'Teléfono', 'inputmode="tel"')}${campo('position', 'Cargo')}
      <div class="field full"><label for="e-address">Lugar de residencia</label><input class="input" id="e-address" name="address" value="${e.address || ''}"></div>
      <div class="field full"><label for="e-schedule">Horario de trabajo</label><input class="input" id="e-schedule" name="schedule" value="${e.schedule || ''}"></div>
      <div class="field"><label for="e-salary">Sueldo</label><input class="input" id="e-salary" name="salary" inputmode="decimal" value="${Number(e.salary) ? num(e.salary) : ''}"></div>
      <div class="field"><label for="e-ded">Descuentos</label><input class="input" id="e-ded" name="deductions" inputmode="decimal" value="${Number(e.deductions) ? num(e.deductions) : ''}"><span class="hint" id="e-neto"></span></div>
      <div class="field full"><label for="e-notes">Currículum o información adicional</label><textarea class="input" id="e-notes" name="notes" rows="4">${e.notes || ''}</textarea></div>
      <div class="field full"><label class="switch"><input type="checkbox" name="active" ${e.active ? 'checked' : ''}><span class="track"></span>Activo</label></div>
    </div>`,
    onMount(frm, close) {
      const neto = () => { frm.querySelector('#e-neto').textContent = `Sueldo neto: ${num((parseNum(frm.salary.value) || 0) - (parseNum(frm.deductions.value) || 0))}`; };
      frm.addEventListener('input', neto); neto();
      frm.addEventListener('click', async (ev) => {
        if (!ev.target.closest('[data-borrar]')) return;
        const ok = await confirmDialog({ title: `Eliminar a ${e.name}`, body: 'Se borra su ficha. Si solo dejó de trabajar, puedes marcarlo como inactivo.', confirm: 'Eliminar', danger: true });
        if (!ok) return;
        try { await db.remove('employees', f.eq('id', e.id)); await L.employees(); emit(); close(); toast('Trabajador eliminado'); } catch (ex) { toast(ex.message, 'bad'); }
      });
    },
    async onSubmit(d) {
      if (!d.name) throw new Error('Escribe el nombre');
      const salary = d.salary === '' ? 0 : parseNum(d.salary);
      const deductions = d.deductions === '' ? 0 : parseNum(d.deductions);
      if (!(salary >= 0) || !(deductions >= 0)) throw new Error('Revisa el sueldo y los descuentos');
      const row = { name: d.name, cedula: d.cedula, birthdate: d.birthdate, phone: d.phone, address: d.address, position: d.position, schedule: d.schedule, salary, deductions, notes: d.notes, active: !!d.active };
      if (nuevo) await db.insert('employees', row); else await db.update('employees', f.eq('id', e.id), row);
      await L.employees(); emit();
      toast(nuevo ? 'Trabajador guardado' : 'Cambios guardados');
    },
  });
}

function mount(root, ctx) {
  const onQ = debounce(() => { ctx.rerender(); keepFocus(document.getElementById('view'), '[data-k="q"]'); }, 200);
  listen(root, ctx, {
    click(ev) {
      const act = ev.target.closest('[data-act]')?.dataset.act;
      if (act === 'nuevo') return form(null);
      if (act === 'csv') {
        return downloadCSV('trabajadores.csv', [['Nombre', 'Cédula', 'Nacimiento', 'Teléfono', 'Dirección', 'Cargo', 'Horario', 'Sueldo', 'Descuentos', 'Neto', 'Activo'],
          ...lista().map((e) => [e.name, e.cedula, e.birthdate, e.phone, e.address, e.position, e.schedule, e.salary, e.deductions, Number(e.salary) - Number(e.deductions), e.active ? 'Sí' : 'No'])]);
      }
      const tr = ev.target.closest('tr[data-id]');
      if (tr) form(S.employees.find((x) => x.id === tr.dataset.id));
    },
    change(ev) { if (ev.target.dataset.k === 'activos') { st.activos = ev.target.checked; ctx.rerender(); } },
    input(ev) { if (ev.target.dataset.k === 'q') { st.q = ev.target.value; onQ(); } },
  });
}

export default { path: 'trabajadores', title: 'Trabajadores', icon: 'badge', subtitle: () => 'Fichas del personal', render, mount };

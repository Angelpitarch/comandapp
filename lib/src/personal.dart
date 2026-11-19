part of '../main.dart';

// Trabajadores y usuarios con acceso.

// ======================= TRABAJADORES =======================
class Employee {
  String id;
  String name;
  String cedula;
  String birthdate;
  String phone;
  String address;
  String position;
  String schedule;
  double salary;
  double deductions;
  String notes;
  bool active;
  Employee({required this.id, this.name = '', this.cedula = '', this.birthdate = '', this.phone = '',
      this.address = '', this.position = '', this.schedule = '', this.salary = 0, this.deductions = 0,
      this.notes = '', this.active = true});
  factory Employee.fromRow(Map<String, dynamic> r) => Employee(
        id: r['id'] as String,
        name: (r['name'] ?? '') as String,
        cedula: (r['cedula'] ?? '') as String,
        birthdate: (r['birthdate'] ?? '') as String,
        phone: (r['phone'] ?? '') as String,
        address: (r['address'] ?? '') as String,
        position: (r['position'] ?? '') as String,
        schedule: (r['schedule'] ?? '') as String,
        salary: ((r['salary'] ?? 0) as num).toDouble(),
        deductions: ((r['deductions'] ?? 0) as num).toDouble(),
        notes: (r['notes'] ?? '') as String,
        active: (r['active'] ?? true) as bool,
      );
  Map<String, dynamic> toRow() => <String, dynamic>{
        'name': name, 'cedula': cedula, 'birthdate': birthdate, 'phone': phone, 'address': address,
        'position': position, 'schedule': schedule, 'salary': salary, 'deductions': deductions,
        'notes': notes, 'active': active,
      };
}

class EmployeesScreen extends StatelessWidget {
  const EmployeesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trabajadores')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EmployeeForm())),
        icon: const Icon(Icons.person_add), label: const Text('Nuevo')),
      body: AnimatedBuilder(animation: store, builder: (context, _) {
        final list = store.employees;
        if (list.isEmpty) {
          return const Center(child: Padding(padding: EdgeInsets.all(24),
            child: Text('Aun no hay trabajadores.\nToca "Nuevo" para agregar.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))));
        }
        return ListView(padding: const EdgeInsets.all(16), children: [
          for (final e in list)
            Card(margin: const EdgeInsets.only(bottom: 6), child: ListTile(
              leading: CircleAvatar(backgroundColor: e.active ? Colors.teal.shade100 : Colors.grey.shade300,
                child: Icon(Icons.person, color: e.active ? Colors.teal : Colors.grey)),
              title: Text(e.name.isEmpty ? '(sin nombre)' : e.name),
              subtitle: Text([if (e.position.isNotEmpty) e.position, if (e.schedule.isNotEmpty) e.schedule, if (!e.active) 'Inactivo'].join(' · '), style: const TextStyle(fontSize: 12)),
              trailing: e.salary > 0 ? Text('Neto: ' + fmtQty(e.salary - e.deductions), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)) : null,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EmployeeForm(existing: e))),
            )),
        ]);
      }),
    );
  }
}

class EmployeeForm extends StatefulWidget {
  final Employee? existing;
  const EmployeeForm({super.key, this.existing});
  @override
  State<EmployeeForm> createState() => _EmployeeFormState();
}
class _EmployeeFormState extends State<EmployeeForm> {
  late TextEditingController _name, _cedula, _birth, _phone, _address, _position, _schedule, _salary, _deductions, _notes;
  bool _active = true;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _cedula = TextEditingController(text: e?.cedula ?? '');
    _birth = TextEditingController(text: e?.birthdate ?? '');
    _phone = TextEditingController(text: e?.phone ?? '');
    _address = TextEditingController(text: e?.address ?? '');
    _position = TextEditingController(text: e?.position ?? '');
    _schedule = TextEditingController(text: e?.schedule ?? '');
    _salary = TextEditingController(text: e != null && e.salary > 0 ? fmtQty(e.salary) : '');
    _deductions = TextEditingController(text: e != null && e.deductions > 0 ? fmtQty(e.deductions) : '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _active = e?.active ?? true;
  }
  @override
  void dispose() {
    for (final c in [_name, _cedula, _birth, _phone, _address, _position, _schedule, _salary, _deductions, _notes]) { c.dispose(); }
    super.dispose();
  }
  Future<void> _save() async {
    if (_saving) return;
    if (_name.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Escribe el nombre'))); return; }
    setState(() => _saving = true);
    final e = widget.existing ?? Employee(id: '');
    e.name = _name.text.trim();
    e.cedula = _cedula.text.trim();
    e.birthdate = _birth.text.trim();
    e.phone = _phone.text.trim();
    e.address = _address.text.trim();
    e.position = _position.text.trim();
    e.schedule = _schedule.text.trim();
    e.salary = double.tryParse(_salary.text.replaceAll(',', '.')) ?? 0;
    e.deductions = double.tryParse(_deductions.text.replaceAll(',', '.')) ?? 0;
    e.notes = _notes.text.trim();
    e.active = _active;
    if (widget.existing != null) { await store.updateEmployee(e); } else { await store.addEmployee(e); }
    if (!mounted) return;
    Navigator.pop(context);
  }
  Widget _field(TextEditingController c, String label, {int lines = 1, bool number = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(controller: c, maxLines: lines,
          keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
          decoration: InputDecoration(labelText: label)),
      );
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'Nuevo trabajador' : 'Editar trabajador'), actions: [
        if (widget.existing != null)
          IconButton(icon: const Icon(Icons.delete), onPressed: () {
            showDialog<void>(context: context, builder: (dctx) => AlertDialog(
              title: const Text('Eliminar trabajador'),
              content: Text('Eliminar a "' + widget.existing!.name + '"?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancelar')),
                FilledButton(onPressed: () async { Navigator.pop(dctx); await store.deleteEmployee(widget.existing!); if (mounted) Navigator.pop(context); }, child: const Text('Eliminar')),
              ]));
          }),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _field(_name, 'Nombre completo'),
        _field(_cedula, 'Cedula / documento'),
        _field(_birth, 'Fecha de nacimiento (DD/MM/AAAA)'),
        _field(_phone, 'Telefono'),
        _field(_address, 'Lugar de residencia'),
        _field(_position, 'Cargo'),
        _field(_schedule, 'Horario de trabajo'),
        Row(children: [
          Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(controller: _salary, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Sueldo')))),
          const SizedBox(width: 12),
          Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(controller: _deductions, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Descuentos')))),
        ]),
        Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(children: [
          const Text('Sueldo neto:', style: TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          Text(fmtQty((double.tryParse(_salary.text.replaceAll(',', '.')) ?? 0) - (double.tryParse(_deductions.text.replaceAll(',', '.')) ?? 0)), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ])),
        _field(_notes, 'Curriculum / informacion adicional', lines: 4),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Activo'), value: _active, onChanged: (v) => setState(() => _active = v)),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, height: 50, child: FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save),
          label: Text(_saving ? 'Guardando...' : 'Guardar trabajador'))),
      ]),
    );
  }
}

// ======================= USUARIOS (login/roles) =======================
class AppUser {
  String id;
  String name;
  String pin;
  String role;
  bool active;
  String email; // vacio = sin acceso; termina en .local = acceso interno (entra solo con PIN)
  AppUser({required this.id, this.name = '', this.pin = '', this.role = 'mesero', this.active = true, this.email = ''});
  bool get tieneAcceso => email.isNotEmpty;
  bool get correoReal => email.isNotEmpty && !email.toLowerCase().endsWith('.local');
  factory AppUser.fromRow(Map<String, dynamic> r) => AppUser(
        id: r['id'] as String,
        name: (r['name'] ?? '') as String,
        pin: (r['pin'] ?? '') as String,
        role: (r['role'] ?? 'mesero') as String,
        active: (r['active'] ?? true) as bool,
        email: (r['email'] ?? '') as String,
      );
  Map<String, dynamic> toRow() => <String, dynamic>{'name': name, 'pin': pin, 'role': role, 'active': active};
}

String roleLabel(String r) => switch (r) {
      'admin' => 'Administrador',
      'cocina' => 'Cocina',
      _ => 'Mesero / Cajero',
    };

class UsersScreen extends StatelessWidget {
  const UsersScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Usuarios')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserForm())),
        icon: const Icon(Icons.person_add), label: const Text('Nuevo')),
      body: AnimatedBuilder(animation: store, builder: (context, _) {
        final list = store.appUsers;
        if (list.isEmpty) {
          return const Center(child: Padding(padding: EdgeInsets.all(24),
            child: Text('Sin usuarios cargados.', style: TextStyle(color: Colors.grey))));
        }
        return ListView(padding: const EdgeInsets.all(16), children: [
          for (final u in list)
            Card(margin: const EdgeInsets.only(bottom: 6), child: ListTile(
              leading: CircleAvatar(backgroundColor: u.active ? Colors.indigo.shade100 : Colors.grey.shade300,
                child: Icon(u.role == 'admin' ? Icons.admin_panel_settings : (u.role == 'cocina' ? Icons.soup_kitchen : Icons.room_service),
                  color: u.active ? Colors.indigo : Colors.grey)),
              title: Text(u.name.isEmpty ? '(sin nombre)' : u.name),
              subtitle: Text(roleLabel(u.role) + (u.active ? '' : '  ·  inactivo') + (u.tieneAcceso ? '' : '  ·  sin acceso'), style: const TextStyle(fontSize: 12)),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserForm(existing: u))),
            )),
        ]);
      }),
    );
  }
}

class UserForm extends StatefulWidget {
  final AppUser? existing;
  const UserForm({super.key, this.existing});
  @override
  State<UserForm> createState() => _UserFormState();
}
class _UserFormState extends State<UserForm> {
  late TextEditingController _name, _pin;
  final _correo = TextEditingController();
  late String _role;
  bool _active = true;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    final u = widget.existing;
    _name = TextEditingController(text: u?.name ?? '');
    _pin = TextEditingController();
    _role = u?.role ?? 'mesero';
    _active = u?.active ?? true;
  }
  @override
  void dispose() { _name.dispose(); _pin.dispose(); _correo.dispose(); super.dispose(); }
  void _aviso(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  // El correo solo se pide al crear un administrador (o al darle acceso), para que pueda entrar al panel web.
  bool get _pideCorreo => _role == 'admin' && !(widget.existing?.tieneAcceso ?? false);
  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    final pin = _pin.text.trim();
    final correo = _correo.text.trim().toLowerCase();
    final u = widget.existing;
    if (name.isEmpty) { _aviso('Escribe el nombre'); return; }
    final darAcceso = u == null || !u.tieneAcceso;
    if ((darAcceso || pin.isNotEmpty) && (pin.length != 6 || int.tryParse(pin) == null)) { _aviso('El PIN debe ser de 6 numeros'); return; }
    if (pin.isNotEmpty && pinDebil(pin)) { _aviso(kMsgPinFacil); return; }
    if (_pideCorreo && !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(correo)) { _aviso('El administrador necesita un correo valido para entrar al panel web'); return; }
    setState(() => _saving = true);
    String? err;
    if (u == null) {
      err = await store.usuarioNube(<String, dynamic>{'accion': 'crear', 'nombre': name, 'correo': _pideCorreo ? correo : '',
          'pin': pin, 'rol': _role, 'activo': _active});
    } else if (!u.tieneAcceso) {
      await store.saveUser(id: u.id, name: name, pin: '', role: _role, active: _active);
      err = await store.usuarioNube(<String, dynamic>{'accion': 'acceso', 'id': u.id, 'correo': _pideCorreo ? correo : '', 'pin': pin});
    } else {
      await store.saveUser(id: u.id, name: name, pin: pin, role: _role, active: _active);
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (err != null) { _aviso(err); return; }
    _aviso(u == null ? '$name ya puede entrar con su PIN' : 'Cambios guardados');
    Navigator.pop(context);
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'Nuevo usuario' : 'Editar usuario'), actions: [
        if (widget.existing != null)
          IconButton(icon: const Icon(Icons.delete), onPressed: () {
            showDialog<void>(context: context, builder: (dctx) => AlertDialog(
              title: const Text('Eliminar usuario'),
              content: Text('Eliminar a "' + widget.existing!.name + '"?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancelar')),
                FilledButton(onPressed: () async {
                  Navigator.pop(dctx);
                  final err = await store.usuarioNube(<String, dynamic>{'accion': 'eliminar', 'id': widget.existing!.id});
                  if (!mounted) return;
                  if (err != null) { _aviso(err); return; }
                  Navigator.pop(context);
                }, child: const Text('Eliminar')),
              ]));
          }),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre', helperText: 'Asi aparecera en la pantalla de entrada')),
        const SizedBox(height: 12),
        if (widget.existing != null && !widget.existing!.tieneAcceso)
          const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('Este usuario todavia no tiene acceso. Ponle un PIN para que pueda entrar.',
            style: TextStyle(color: kBad, fontWeight: FontWeight.w600))),
        TextField(controller: _pin, keyboardType: TextInputType.number, maxLength: 6,
          decoration: InputDecoration(labelText: (widget.existing?.tieneAcceso ?? false) ? 'PIN nuevo (vacio = no cambiar)' : 'PIN (6 numeros)', counterText: '')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(value: _role,
          decoration: const InputDecoration(labelText: 'Rol'),
          items: const [
            DropdownMenuItem(value: 'admin', child: Text('Administrador')),
            DropdownMenuItem(value: 'mesero', child: Text('Mesero / Cajero')),
            DropdownMenuItem(value: 'cocina', child: Text('Cocina')),
          ],
          onChanged: (v) => setState(() => _role = v ?? 'mesero')),
        if (_pideCorreo) ...[
          const SizedBox(height: 12),
          TextField(controller: _correo, keyboardType: TextInputType.emailAddress, autocorrect: false,
            decoration: const InputDecoration(labelText: 'Correo del administrador', helperText: 'Para entrar al panel web. Meseros y cocina no lo necesitan.')),
        ],
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Activo'), value: _active, onChanged: (v) => setState(() => _active = v)),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, height: 50, child: FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save),
          label: Text(_saving ? 'Guardando...' : 'Guardar usuario'))),
      ]),
    );
  }
}

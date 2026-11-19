part of '../main.dart';

// Entrada: codigo del negocio, personal y PIN; cambiar mi PIN.

// ======================= ENTRADA =======================
// 1) codigo del negocio (se recuerda en este telefono)  2) quien eres  3) PIN
const kLoginBg = Color(0xFF0D0D0D);
const kLoginCard = Color(0xFF1B1B1B);
const kLoginErr = Color(0xFFFF8A80);
const kPrefCodigo = 'negocio_codigo';
const kRoles = {'admin': 'Administrador', 'mesero': 'Mesero / Cajero', 'cocina': 'Cocina'};

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}
class _LoginScreenState extends State<LoginScreen> {
  String _pin = '';
  String? _err;
  bool _checking = false;
  bool _loading = true;
  String? _codigo;          // codigo del negocio guardado en este telefono
  String _negocio = '';     // nombre del negocio
  List<Map<String, dynamic>> _staff = [];
  Map<String, dynamic>? _sel;
  bool _noEncontrado = false; // el codigo guardado ya no lleva a un negocio activo
  bool _ancho = false;        // computadora o tableta horizontal: entrada en dos paneles
  final _codigoCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _arrancar();
  }

  @override
  void dispose() {
    _codigoCtrl.dispose();
    super.dispose();
  }

  Future<void> _arrancar() async {
    String? c;
    try { c = (await SharedPreferences.getInstance()).getString(kPrefCodigo); } catch (_) {}
    if (!mounted) return;
    if (c == null || c.isEmpty) { setState(() => _loading = false); return; }
    _codigo = c;
    await _cargarStaff();
  }

  Future<void> _cargarStaff() async {
    final codigo = _codigo;
    if (codigo == null) return;
    setState(() { _loading = true; _err = null; });
    final s = await store.loadStaff(codigo);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _noEncontrado = s != null && s.isEmpty;
      if (s == null) {
        _err = 'Sin conexion. Revisa internet e intenta de nuevo.';
      } else {
        _staff = s;
        _negocio = s.isNotEmpty ? (s.first['negocio_nombre'] ?? '') as String : '';
        if (s.isEmpty) _err = 'Este dispositivo esta vinculado al negocio "$codigo", pero ese negocio no esta activo en este momento.';
      }
    });
  }

  Future<void> _usarCodigo() async {
    final c = _codigoCtrl.text.trim().toLowerCase();
    if (c.isEmpty) { setState(() => _err = 'Escribe el codigo de tu negocio'); return; }
    setState(() { _loading = true; _err = null; });
    final s = await store.loadStaff(c);
    if (!mounted) return;
    if (s == null) { setState(() { _loading = false; _err = 'Sin conexion. Revisa internet e intenta de nuevo.'; }); return; }
    if (s.isEmpty) { setState(() { _loading = false; _err = 'No encontramos un negocio activo con ese codigo. Revisalo con el administrador.'; }); return; }
    try { await (await SharedPreferences.getInstance()).setString(kPrefCodigo, c); } catch (_) {}
    if (!mounted) return;
    setState(() { _codigo = c; _staff = s; _negocio = (s.first['negocio_nombre'] ?? '') as String; _loading = false; });
  }

  Future<void> _cambiarNegocio() async {
    try { await (await SharedPreferences.getInstance()).remove(kPrefCodigo); } catch (_) {}
    if (!mounted) return;
    setState(() { _codigo = null; _staff = []; _sel = null; _pin = ''; _err = null; _noEncontrado = false; _codigoCtrl.text = ''; });
  }

  void _tap(String d) {
    if (_pin.length >= 6 || _checking) return;
    setState(() { _pin += d; _err = null; });
    if (_pin.length == 6) _validate();
  }

  Future<void> _validate() async {
    setState(() => _checking = true);
    await store.saliendo; // si alguien acaba de salir en este telefono, se espera a que termine
    final (correo, motivo) = await store.comprobarPin(_sel ?? const <String, dynamic>{}, _pin);
    final ok = correo != null && await store.signInStaff(correo, _pin);
    final me = ok ? await store.myProfile() : null;
    if (!mounted) return;
    setState(() => _checking = false);
    if (!ok || me == null) {
      if (ok) { sb.auth.signOut(); }
      setState(() {
        _err = !ok ? (motivo ?? 'PIN incorrecto')
            : (store.negocioSuspendido ? 'Este negocio no esta activo. Contacta a ComandApp.' : 'Tu usuario no tiene permisos');
        _pin = '';
      });
      return;
    }
    store.currentUser = me.name;
    store.currentUserRole = me.role;
    store.init();
    store.registerPush();
    final legacy = _pin.length < 6;
    final usado = _pin;
    final destino = legacy
        ? ChangePinScreen(forzadoActual: usado)
        : _homeForRole(store.currentUserRole);
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => destino));
    setState(() => _pin = '');
  }

  void _back() { if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1)); }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final paso = _codigo == null ? 'codigo' : (_sel == null ? 'personal' : 'pin');
    _ancho = esAncho(context);
    final contenido = DefaultTextStyle.merge(
      style: const TextStyle(color: Colors.white),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: KeyedSubtree(
          key: ValueKey(paso),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_ancho) Padding(padding: const EdgeInsets.only(bottom: 14), child: Text(
                'PASO ${paso == 'codigo' ? 1 : (paso == 'personal' ? 2 : 3)} DE 3',
                textAlign: paso == 'pin' ? TextAlign.center : TextAlign.start,
                style: const TextStyle(color: kAmber, fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 1.4))),
            paso == 'codigo' ? _pasoCodigo() : (paso == 'personal' ? _listaPersonal() : _pinPad()),
          ]),
        ),
      ),
    );
    return Theme(
      data: t.copyWith(
        colorScheme: t.colorScheme.copyWith(primary: kAmber, onPrimary: kInk),
        textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: kAmber)),
        inputDecorationTheme: InputDecorationTheme(
          filled: true, fillColor: kLoginCard,
          hintStyle: const TextStyle(color: Colors.white38),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: kAmber, width: 1.6)),
        ),
      ),
      child: Scaffold(
        backgroundColor: kLoginBg,
        body: _ancho
            ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(flex: 11, child: _ladoMarca()),
                Expanded(flex: 9, child: Container(
                  decoration: const BoxDecoration(color: Color(0xFF121212), border: Border(left: BorderSide(color: Colors.white10))),
                  child: Center(child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
                    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: contenido),
                  )),
                )),
              ])
            : SafeArea(child: Center(child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 400), child: contenido),
              ))),
      ),
    );
  }

  // Panel izquierdo de la entrada en computadora: marca y lo que ofrece ComandApp.
  Widget _ladoMarca() => Container(
        decoration: const BoxDecoration(gradient: RadialGradient(
          center: Alignment(-1, -1), radius: 1.6, colors: [Color(0xFF2A1E05), kLoginBg], stops: [0, 0.62])),
        padding: const EdgeInsets.fromLTRB(64, 52, 64, 36),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Image.asset('assets/marca/logo-horizontal.png', height: 50,
              errorBuilder: (_, __, ___) => const Text('ComandApp', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700))),
          const Spacer(),
          const Text('Comandas, caja e inventario\nen un solo lugar',
              style: TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w700, height: 1.15, letterSpacing: -0.5)),
          const SizedBox(height: 16),
          const SizedBox(width: 520, child: Text(
              'Pedidos directo a cocina, cobros en dolares y bolivares, y el control de tu negocio en tiempo real desde cualquier equipo.',
              style: TextStyle(color: Colors.white70, fontSize: 16, height: 1.45))),
          const SizedBox(height: 30),
          _ventaja(Icons.receipt_long_outlined, 'Comandas a cocina con aviso al instante'),
          _ventaja(Icons.point_of_sale_outlined, 'Cobros en USD y Bs con la tasa del dia'),
          _ventaja(Icons.inventory_2_outlined, 'Inventario con recetas y alertas de stock'),
          const Spacer(flex: 2),
          Text('© ${DateTime.now().year} ComandApp', style: const TextStyle(color: Colors.white38, fontSize: 12.5)),
        ]),
      );
  Widget _ventaja(IconData i, String t) => Padding(padding: const EdgeInsets.only(bottom: 14), child: Row(children: [
        Container(width: 36, height: 36, alignment: Alignment.center,
          decoration: BoxDecoration(color: kAmber.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
          child: Icon(i, color: kAmber, size: 20)),
        const SizedBox(width: 14),
        Text(t, style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w500)),
      ]));

  Widget _simbolo(double ancho) => Image.asset('assets/marca/simbolo.png', width: ancho, fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Icon(Icons.lunch_dining, size: ancho * 0.6, color: kAmber));

  Widget _pasoCodigo() => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!_ancho) ...[
          Center(child: _simbolo(170)),
          const SizedBox(height: 12),
          Center(child: Image.asset('assets/marca/texto.png', width: 200,
            errorBuilder: (_, __, ___) => const Text('ComandApp', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700)))),
          const SizedBox(height: 40),
        ],
        Text(_ancho ? 'Vincula este equipo' : 'Bienvenido', textAlign: _ancho ? TextAlign.start : TextAlign.center,
            style: TextStyle(fontSize: _ancho ? 30 : 26, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('Escribe el codigo de tu negocio (te lo da el administrador). Solo se pide la primera vez en este dispositivo.',
            textAlign: _ancho ? TextAlign.start : TextAlign.center, style: const TextStyle(color: Colors.white70, height: 1.35)),
        const SizedBox(height: 24),
        TextField(
          controller: _codigoCtrl,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.go,
          style: const TextStyle(color: Colors.white, fontSize: 17),
          decoration: const InputDecoration(hintText: 'ej: mi-restaurante',
              prefixIcon: Icon(Icons.storefront_outlined, color: Colors.white54)),
          onSubmitted: (_) => _usarCodigo(),
        ),
        SizedBox(height: 44, child: Center(child: Text(_err ?? '', textAlign: TextAlign.center, style: const TextStyle(color: kLoginErr)))),
        SizedBox(height: 54, child: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: kAmber, foregroundColor: kInk,
              textStyle: const TextStyle(fontFamily: 'Outfit', fontSize: 17, fontWeight: FontWeight.w700)),
          onPressed: _loading ? null : _usarCodigo,
          child: _loading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: kInk))
              : const Text('Continuar'),
        )),
      ]);

  Widget _listaPersonal() => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!_ancho) ...[Center(child: _simbolo(110)), const SizedBox(height: 18)],
        Text(_negocio.isEmpty ? 'Tu negocio' : _negocio, textAlign: _ancho ? TextAlign.start : TextAlign.center,
            style: TextStyle(fontSize: _ancho ? 30 : 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(_ancho ? 'Elige tu nombre para entrar' : 'Toca tu nombre para entrar',
            textAlign: _ancho ? TextAlign.start : TextAlign.center, style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 22),
        if (_loading)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: kAmber)))
        else if (_staff.isEmpty) ...[
          Text(_err ?? 'No hay personal activo en este negocio.', textAlign: TextAlign.center, style: const TextStyle(color: kLoginErr)),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24)),
            onPressed: _cargarStaff, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
          // Solo si el negocio guardado ya no existe o no esta activo se puede vincular otro.
          if (_noEncontrado) ...[
            const SizedBox(height: 8),
            Center(child: TextButton.icon(onPressed: _cambiarNegocio,
                icon: const Icon(Icons.link, size: 18), label: const Text('Vincular a otro negocio'))),
          ],
        ] else
          for (final p in _staff) _personaTile(p),
      ]);

  Widget _personaTile(Map<String, dynamic> p) {
    final name = ((p['name'] ?? '') as String).trim();
    final role = (p['role'] ?? '') as String;
    final partes = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2);
    final ini = partes.isEmpty ? '?' : partes.map((w) => w[0].toUpperCase()).join();
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: Material(
      color: kLoginCard, borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => setState(() { _sel = p; _pin = ''; _err = null; }),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), child: Row(children: [
          CircleAvatar(radius: 22, backgroundColor: kAmber, foregroundColor: kInk,
              child: Text(ini, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name.isEmpty ? 'Sin nombre' : name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white)),
            Text(kRoles[role] ?? role, style: const TextStyle(fontSize: 13, color: Colors.white60)),
          ])),
          const Icon(Icons.chevron_right, color: Colors.white38),
        ])),
      ),
    ));
  }

  // En computadora se puede escribir el PIN con el teclado: numeros, borrar y Enter.
  KeyEventResult _tecla(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final ch = e.character;
    if (ch != null && ch.length == 1 && '0123456789'.contains(ch)) { _tap(ch); return KeyEventResult.handled; }
    if (e.logicalKey == LogicalKeyboardKey.backspace) { _back(); return KeyEventResult.handled; }
    if ((e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.numpadEnter) &&
        _pin.length >= 4 && _pin.length < 6 && !_checking) { _validate(); return KeyEventResult.handled; }
    return KeyEventResult.ignored;
  }

  Widget _pinPad() {
    final name = ((_sel?['name'] ?? '') as String).trim();
    return Focus(autofocus: true, onKeyEvent: _tecla, child: Column(mainAxisSize: MainAxisSize.min, children: [
      if (!_ancho) ...[_simbolo(84), const SizedBox(height: 14)],
      Text(name.isEmpty ? 'Hola' : 'Hola, $name', textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(_ancho ? 'Ingresa tu PIN de 6 numeros (puedes usar el teclado)' : 'Ingresa tu PIN de 6 numeros', style: const TextStyle(color: Colors.white70)),
      const SizedBox(height: 22),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(6, (i) => AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            margin: const EdgeInsets.symmetric(horizontal: 7), width: 16, height: 16,
            decoration: BoxDecoration(shape: BoxShape.circle,
                color: i < _pin.length ? kAmber : Colors.transparent,
                border: Border.all(color: i < _pin.length ? kAmber : Colors.white30, width: 2))))),
      SizedBox(height: 44, child: Center(child: _checking
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: kAmber))
          : Text(_err ?? '', textAlign: TextAlign.center, style: const TextStyle(color: kLoginErr)))),
      _keypad(),
      // PIN antiguo de 4 o 5 numeros: se entra con este boton y la app pide crear uno de 6.
      SizedBox(height: 44, child: (_pin.length >= 4 && _pin.length < 6 && !_checking)
          ? TextButton(onPressed: _validate, child: const Text('Entrar con PIN de 4 numeros'))
          : null),
      TextButton.icon(
        onPressed: _checking ? null : () => setState(() { _sel = null; _pin = ''; _err = null; }),
        icon: const Icon(Icons.arrow_back, size: 18), label: const Text('No soy yo')),
    ]));
  }

  Widget _k(String label, {VoidCallback? action, Widget? child}) => Padding(
        padding: const EdgeInsets.all(7),
        child: SizedBox(width: 76, height: 64, child: Material(
          color: kLoginCard, borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: _checking ? null : (action ?? () => _tap(label)),
            child: Center(child: child ?? Text(label,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: Colors.white))),
          ),
        )),
      );
  Widget _keypad() => Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [_k('1'), _k('2'), _k('3')]),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [_k('4'), _k('5'), _k('6')]),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [_k('7'), _k('8'), _k('9')]),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [const SizedBox(width: 90), _k('0'),
            _k('', action: _back, child: const Icon(Icons.backspace_outlined, color: Colors.white70))]),
      ]);
}

// ======================= CAMBIAR MI PIN =======================
class ChangePinScreen extends StatefulWidget {
  /// Si viene con valor, es el cambio obligatorio tras entrar con un PIN antiguo:
  /// no pide el PIN actual y no se puede salir sin crear el nuevo.
  final String? forzadoActual;
  const ChangePinScreen({super.key, this.forzadoActual});
  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}
class _ChangePinScreenState extends State<ChangePinScreen> {
  final _actual = TextEditingController();
  final _nuevo = TextEditingController();
  final _repite = TextEditingController();
  bool _saving = false;
  String? _err;

  @override
  void dispose() { _actual.dispose(); _nuevo.dispose(); _repite.dispose(); super.dispose(); }

  Future<void> _guardar() async {
    if (_saving) return;
    final actual = widget.forzadoActual ?? _actual.text.trim();
    final nuevo = _nuevo.text.trim();
    final rep = _repite.text.trim();
    if (nuevo.length != 6 || int.tryParse(nuevo) == null) {
      setState(() => _err = 'El PIN nuevo debe ser de 6 numeros'); return;
    }
    if (nuevo != rep) { setState(() => _err = 'Los PIN nuevos no coinciden'); return; }
    if (pinDebil(nuevo)) { setState(() => _err = kMsgPinFacil); return; }
    if (nuevo == actual) { setState(() => _err = 'El PIN nuevo debe ser distinto al actual'); return; }
    setState(() { _saving = true; _err = null; });
    final err = await store.cambiarMiPin(actual, nuevo);
    if (!mounted) return;
    setState(() => _saving = false);
    if (err != null) { setState(() => _err = err); return; }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PIN actualizado. Usalo la proxima vez que entres.')));
    if (widget.forzadoActual != null) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => _homeForRole(store.currentUserRole)));
    } else {
      Navigator.pop(context);
    }
  }

  Widget _campo(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextField(controller: c, keyboardType: TextInputType.number, maxLength: 6, obscureText: true,
          decoration: InputDecoration(labelText: label, counterText: '')),
      );

  @override
  Widget build(BuildContext context) {
    final forzado = widget.forzadoActual != null;
    return PopScope(canPop: !forzado, child: Scaffold(
      appBar: AppBar(title: Text(forzado ? 'Crea tu PIN nuevo' : 'Cambiar mi PIN'),
        automaticallyImplyLeading: !forzado,
        actions: [
          if (forzado) TextButton(
            onPressed: () => _logout(context),
            child: const Text('Salir')),
        ]),
      body: Center(child: SingleChildScrollView(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.lock_reset, size: 56, color: kPrimary),
          const SizedBox(height: 6),
          Text(store.currentUser, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text(forzado ? 'Por seguridad, el PIN ahora es de 6 numeros. Crea el tuyo para continuar.' : 'Solo tu puedes cambiar tu PIN',
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 20),
          if (!forzado) _campo(_actual, 'PIN actual'),
          _campo(_nuevo, 'PIN nuevo (6 numeros)'),
          _campo(_repite, 'Repite el PIN nuevo'),
          if (_err != null) Padding(padding: const EdgeInsets.only(bottom: 10),
            child: Text(_err!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600))),
          SizedBox(width: double.infinity, height: 50, child: FilledButton.icon(
            onPressed: _saving ? null : _guardar,
            icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save),
            label: Text(_saving ? 'Guardando...' : 'Guardar PIN nuevo'))),
        ])),
      ))),
    ));
  }
}

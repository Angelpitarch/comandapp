part of '../main.dart';

// Store: estado de la app conectado a Supabase en tiempo real (lecturas, comandas, cobros, inventario).

// ======================= STORE (conectado a Supabase) =======================
class Store extends ChangeNotifier {
  String? error;
  bool connected = false;
  double rate = 36.5;
  bool tasaAuto = false;        // el negocio usa la tasa oficial del BCV (se actualiza sola)
  String tasaOrigen = 'manual'; // 'bcv' o 'manual': de donde viene la tasa en uso
  DateTime? tasaFecha;          // fecha valor del BCV de la tasa en uso
  bool get tasaEsBcv => tasaOrigen == 'bcv' && tasaFecha != null;
  String businessName = 'Mi negocio';
  List<Product> products = [];
  List<TableModel> tables = [];
  List<Ticket> tickets = [];
  Map<int, List<AccLine>> accounts = {};
  List<Takeaway> takeaways = [];
  List<Cancellation> cancellations = [];
  List<Employee> employees = [];
  List<Gasto> gastos = [];
  Map<String, List<AccLine>> takeawayAccounts = {};
  List<Sale> sales = [];
  List<CashClose> cashCloses = [];
  List<CatDef> categories = [];
  bool motivShown = true;
  List<Ingredient> ingredients = [];
  final List<String> methods = ['Efectivo Bs', 'Efectivo USD', 'Pago movil', 'Tarjeta'];
  final Map<String, List<CartItem>> _carts = {};
  String currentUser = '';
  String currentUserRole = '';
  bool _inited = false;
  List<AppUser> appUsers = [];

  final List<StreamSubscription<List<Map<String, dynamic>>>> _subs = [];
  bool ticketsListos = false; // ya llego la primera carga de comandas (para no avisar de las viejas)
  Future<void>? saliendo;      // cierre de sesion en curso: la entrada espera a que termine

  // Cada rol escucha solo lo que usa: cocina 2 tablas, mesero 8, administrador todas.
  // Las tablas que crecen todos los dias (comandas, ventas, gastos...) se limitan a lo mas reciente.
  void init() {
    if (_inited) return;
    _inited = true;
    final admin = currentUserRole == 'admin';
    final salon = admin || currentUserRole == 'mesero';
    void escuchar(Stream<List<Map<String, dynamic>>> st, void Function(List<Map<String, dynamic>>) alLlegar) {
      _subs.add(st.listen((rows) { alLlegar(rows); notifyListeners(); }, onError: _onErr));
    }
    escuchar(sb.from('app_config').stream(primaryKey: ['id']), (rows) {
      if (rows.isEmpty) return;
      rate = ((rows.first['rate'] ?? 36.5) as num).toDouble();
      _leerTasa(rows.first);
      businessName = (rows.first['business_name'] ?? 'Mi negocio') as String;
      motivShown = (rows.first['motiv_shown'] ?? true) as bool;
      connected = true;
    });
    escuchar(sb.from('tickets').stream(primaryKey: ['id']).order('sent_at').limit(300), (rows) {
      tickets = rows.map((r) => Ticket.fromRow(r)).toList();
      ticketsListos = true;
    });
    if (salon) {
      escuchar(sb.from('products').stream(primaryKey: ['id']).order('name', ascending: true), (rows) {
        products = rows.map((r) => Product.fromRow(r)).toList(); connected = true;
      });
      escuchar(sb.from('dining_tables').stream(primaryKey: ['number']).order('number', ascending: true), (rows) {
        tables = rows.map((r) => TableModel.fromRow(r)).toList();
      });
      escuchar(sb.from('account_items').stream(primaryKey: ['id']), (rows) {
        final m = <int, List<AccLine>>{};
        final tm = <String, List<AccLine>>{};
        for (final r in rows) {
          final a = AccLine.fromRow(r);
          if (a.table != null) { (m[a.table!] ??= []).add(a); }
          else if (a.takeawayId != null) { (tm[a.takeawayId!] ??= []).add(a); }
        }
        accounts = m; takeawayAccounts = tm;
      });
      escuchar(sb.from('takeaways').stream(primaryKey: ['id']).order('created_at'), (rows) {
        takeaways = rows.map((r) => Takeaway.fromRow(r)).toList();
      });
      escuchar(sb.from('categories').stream(primaryKey: ['id']).order('position', ascending: true), (rows) {
        categories = rows.map((r) => CatDef.fromRow(r)).toList();
      });
      escuchar(sb.from('ingredients').stream(primaryKey: ['id']).order('name', ascending: true), (rows) {
        ingredients = rows.map((r) => Ingredient.fromRow(r)).toList();
      });
    }
    if (admin) {
      escuchar(sb.from('cancellations').stream(primaryKey: ['id']).order('at', ascending: false).limit(300), (rows) {
        cancellations = rows.map((r) => Cancellation.fromRow(r)).toList();
      });
      escuchar(sb.from('employees').stream(primaryKey: ['id']).order('name', ascending: true), (rows) {
        employees = rows.map((r) => Employee.fromRow(r)).toList();
      });
      escuchar(sb.from('gastos').stream(primaryKey: ['id']).order('at', ascending: false).limit(500), (rows) {
        gastos = rows.map((r) => Gasto.fromRow(r)).toList();
      });
      escuchar(sb.from('app_users').stream(primaryKey: ['id']).order('name', ascending: true), (rows) {
        appUsers = rows.map((r) => AppUser.fromRow(r)).toList();
      });
      // Las 1000 ventas mas recientes (el turno y los ultimos dias). Los reportes largos estan en el panel web.
      escuchar(sb.from('sales').stream(primaryKey: ['id']).order('at', ascending: false).limit(1000), (rows) {
        sales = rows.map((r) => Sale.fromRow(r)).toList();
      });
      escuchar(sb.from('cash_closes').stream(primaryKey: ['id']).order('closed_at', ascending: false).limit(400), (rows) {
        cashCloses = rows.map((r) => CashClose.fromRow(r)).toList();
      });
    }
  }

  /// Al cerrar sesion: deja de escuchar y borra de la memoria los datos del usuario anterior,
  /// para que quien entre despues (en el mismo telefono) cargue solo lo suyo y con sus permisos.
  Future<void> reset() async {
    final subs = List.of(_subs);
    _subs.clear();
    for (final x in subs) { try { await x.cancel(); } catch (_) {} }
    try { await sb.removeAllChannels(); } catch (_) {}
    _inited = false;
    ticketsListos = false;
    connected = false;
    error = null;
    products = []; tables = []; tickets = []; accounts = {}; takeaways = []; cancellations = [];
    employees = []; gastos = []; takeawayAccounts = {}; sales = []; cashCloses = []; categories = [];
    ingredients = []; appUsers = [];
    tasaAuto = false; tasaOrigen = 'manual'; tasaFecha = null;
    _carts.clear();
    notifyListeners();
  }

  void _onErr(Object e) { error = mensajeDe(e); notifyListeners(); }
  /// Convierte un error tecnico en un mensaje para el personal.
  String mensajeDe(Object e) {
    if (e is PostgrestException) {
      if (e.code == '22023' || e.code == 'P0001' || e.code == 'P0002') return e.message; // mensajes escritos para el usuario
      if (e.code == '42501') return 'No tienes permiso para hacer esto.';
      return 'No se pudo guardar. Intenta de nuevo (codigo ${e.code ?? '?'}).';
    }
    if (e is AuthException) return 'Tu sesion expiro. Sal y vuelve a entrar.';
    final t = e.toString();
    if (RegExp('SocketException|ClientException|Failed host lookup|TimeoutException|Connection').hasMatch(t)) {
      return 'Sin conexion a internet. Revisa la senal e intenta de nuevo.';
    }
    return 'Ocurrio un error: $t';
  }
  String? errorCobro; // ultimo motivo por el que no se pudo cobrar (lo muestra la pantalla de cobro)
  void clearError() { error = null; notifyListeners(); }

  List<CartItem> cart(String key) => _carts.putIfAbsent(key, () => []);
  void touch() => notifyListeners();

  double toUsd(double amt, Currency c) => c == Currency.usd ? amt : amt / rate;
  double toVes(double amt, Currency c) => c == Currency.ves ? amt : amt * rate;
  double lineUsd(CartItem it) => toUsd(it.unit(), it.p.cur) * it.qty;
  double cartTotalUsd(String key) => cart(key).fold(0.0, (s, it) => s + lineUsd(it));
  int cartCount(String key) => cart(key).fold(0, (s, it) => s + it.qty);
  List<AccLine> account(int n) => accounts[n] ?? const [];
  double accountTotalUsd(int n) => account(n).fold(0.0, (s, a) => s + a.lineUsd);
  List<Ticket> ticketsOf(int n) => tickets.where((x) => x.table == n && x.status != 'anulada').toList();
  List<Product> get lowStock => products.where((p) => p.trackStock && p.stock <= p.minStock).toList();
  List<Ingredient> get lowIngredients => ingredients.where((i) => i.low).toList();
  Future<void> addIngredient(Ingredient i) async { try { await sb.from('ingredients').insert(i.toRow()); } catch (e) { _onErr(e); } }
  Future<void> updateIngredient(Ingredient i) async { try { await sb.from('ingredients').update(i.toRow()).eq('id', i.id); } catch (e) { _onErr(e); } }
  Future<void> deleteIngredient(Ingredient i) async { try { await sb.from('ingredients').delete().eq('id', i.id); } catch (e) { _onErr(e); } }
  /// Deja la app lista para el proximo turno.
  /// Libera mesas, cierra para-llevar y limpia comandas colgadas.
  /// NO borra ventas, anulaciones ni configuracion.
  Future<void> cierreDeTurno() async {
    try {
      await sb.from('account_items').delete().neq('id', '00000000-0000-0000-0000-000000000000');
      await sb.from('takeaways').delete().neq('id', '00000000-0000-0000-0000-000000000000');
      await sb.from('tickets').update(<String, dynamic>{'status': 'entregada'})
          .neq('status', 'anulada').neq('status', 'entregada');
      await sb.from('dining_tables').update(<String, dynamic>{'status': 'disponible', 'waiter': null, 'opened_at': null})
          .gt('number', 0);
    } catch (e) { _onErr(e); }
  }

  /// Cierra la caja: guarda un resumen del periodo actual en el historial
  /// de dias y luego reinicia mesas, pedidos y comandas (conserva las ventas).
  Future<void> hacerCierreDeCaja() async {
    try {
      final ventas = todaySales;
      final total = ventas.fold(0.0, (s, e) => s + e.totalUsd);
      final byMethod = <String, double>{};
      for (final s in ventas) { for (final p in s.payments) { byMethod[p.method] = (byMethod[p.method] ?? 0) + p.amountUsd; } }
      final units = <String, int>{};
      for (final s in ventas) { for (final l in s.lines) { units[l.name] = (units[l.name] ?? 0) + l.qty; } }
      await sb.from('cash_closes').insert(<String, dynamic>{
        'from_at': lastCloseAt?.toUtc().toIso8601String(),
        'total_usd': total,
        'accounts_count': ventas.length,
        'by_method': byMethod,
        'units': units,
        'gastos_usd': todayGastosUsd,
      });
      await cierreDeTurno();
    } catch (e) { _onErr(e); }
  }
  Future<void> freeTable(int n) async {
    try {
      await sb.from('account_items').delete().eq('table_number', n);
      await sb.from('dining_tables').update(<String, dynamic>{'status': 'disponible', 'waiter': null, 'opened_at': null}).eq('number', n);
    } catch (e) { _onErr(e); }
  }
  Future<void> setTableStatus(int n, String status) async {
    try { await sb.from('dining_tables').update(<String, dynamic>{'status': status}).eq('number', n); } catch (e) { _onErr(e); }
  }
  Future<void> markDelivered(int table) async {
    try { await sb.from('tickets').update(<String, dynamic>{'status': 'entregada'}).eq('table_number', table).neq('status', 'anulada'); } catch (e) { _onErr(e); }
  }
  String kitchenStateTable(int n) {
    final tks = tickets.where((x) => x.table == n && x.status != 'anulada' && x.status != 'entregada');
    if (tks.any((x) => x.status == 'lista')) return 'listo';
    if (tks.any((x) => x.status == 'nueva' || x.status == 'preparando')) return 'cocina';
    return '';
  }
  String kitchenStateTakeaway(String id) {
    final tks = tickets.where((x) => x.takeawayId == id && x.status != 'anulada' && x.status != 'entregada');
    if (tks.any((x) => x.status == 'lista')) return 'listo';
    if (tks.any((x) => x.status == 'nueva' || x.status == 'preparando')) return 'cocina';
    return '';
  }
  List<AccLine> takeawayAccount(String id) => takeawayAccounts[id] ?? const [];
  double takeawayTotalUsd(String id) => takeawayAccount(id).fold(0.0, (s, a) => s + a.lineUsd);
  List<Ticket> ticketsOfTakeaway(String id) => tickets.where((x) => x.takeawayId == id && x.status != 'anulada').toList();
  Future<String?> createTakeaway(String name) async {
    try {
      final res = await sb.from('takeaways').insert(<String, dynamic>{'name': name, 'status': 'abierta'}).select();
      if (res.isNotEmpty) return res.first['id'] as String;
    } catch (e) { _onErr(e); }
    return null;
  }
  Future<void> markDeliveredTakeaway(String id) async {
    try { await sb.from('tickets').update(<String, dynamic>{'status': 'entregada'}).eq('takeaway_id', id).neq('status', 'anulada'); } catch (e) { _onErr(e); }
  }
  Future<void> closeTakeaway(String id) async {
    try {
      await sb.from('account_items').delete().eq('takeaway_id', id);
      await sb.from('takeaways').delete().eq('id', id);
    } catch (e) { _onErr(e); }
  }
  Future<void> addEmployee(Employee e) async { try { await sb.from('employees').insert(e.toRow()); } catch (x) { _onErr(x); } }
  Future<void> updateEmployee(Employee e) async { try { await sb.from('employees').update(e.toRow()).eq('id', e.id); } catch (x) { _onErr(x); } }
  Future<void> deleteEmployee(Employee e) async { try { await sb.from('employees').delete().eq('id', e.id); } catch (x) { _onErr(x); } }
  // Gastos (solo admin; la base de datos lo exige)
  Future<void> addGasto(Gasto g) async {
    try { await sb.from('gastos').insert(<String, dynamic>{...g.toRow(), 'by_user': currentUser}); } catch (x) { _onErr(x); }
  }
  Future<void> updateGasto(Gasto g) async { try { await sb.from('gastos').update(g.toRow()).eq('id', g.id); } catch (x) { _onErr(x); } }
  Future<void> deleteGasto(Gasto g) async { try { await sb.from('gastos').delete().eq('id', g.id); } catch (x) { _onErr(x); } }
  // Mismo criterio que las ventas: "hoy" = desde el ultimo cierre de caja.
  List<Gasto> get todayGastos {
    final lc = lastCloseAt;
    if (lc == null) return List<Gasto>.from(gastos);
    return gastos.where((g) => g.at.isAfter(lc)).toList();
  }
  double get todayGastosUsd => todayGastos.fold(0.0, (s, g) => s + g.amountUsd);
  /// Rol real de quien acaba de iniciar sesion, leido de la base de datos (no de la lista publica).
  // ---- Avisos push (solo cocina y admin). Si algo falla, la app sigue igual. ----
  String? _pushToken;
  StreamSubscription<String>? _pushRefresh;
  Future<void> registerPush() async {
    if (kIsWeb) return;
    try {
      final fm = FirebaseMessaging.instance;
      if (currentUserRole != 'cocina' && currentUserRole != 'admin') {
        // este celular ya no debe recibir avisos de cocina (por si lo usaba otro rol antes)
        final old = await fm.getToken();
        if (old != null) { await sb.rpc('unregister_device', params: <String, dynamic>{'p_token': old}); }
        return;
      }
      await fm.requestPermission();
      final t = await fm.getToken();
      if (t == null) return;
      _pushToken = t;
      await sb.rpc('register_device', params: <String, dynamic>{'p_token': t});
      await _pushRefresh?.cancel();
      _pushRefresh = fm.onTokenRefresh.listen((n) async {
        _pushToken = n;
        try { await sb.rpc('register_device', params: <String, dynamic>{'p_token': n}); } catch (e) { debugPrint('push refresh: $e'); }
      });
    } catch (e) { debugPrint('registerPush: $e'); }
  }
  Future<void> unregisterPush() async {
    if (kIsWeb) return;
    try {
      await _pushRefresh?.cancel();
      _pushRefresh = null;
      final t = _pushToken;
      _pushToken = null;
      if (t != null) { await sb.rpc('unregister_device', params: <String, dynamic>{'p_token': t}); }
    } catch (e) { debugPrint('unregisterPush: $e'); }
  }

  String negocioNombre = '';
  String negocioCodigo = '';
  bool negocioSuspendido = false;

  Future<AppUser?> myProfile() async {
    try {
      final res = await sb.rpc('my_profile');
      if (res is List && res.isNotEmpty) {
        final r = res.first as Map;
        negocioNombre = (r['negocio_nombre'] ?? '') as String;
        negocioCodigo = (r['negocio_codigo'] ?? '') as String;
        negocioSuspendido = r['negocio_activo'] == false;
        if (negocioSuspendido) return null;
        return AppUser(id: r['id'] as String, name: (r['name'] ?? '') as String, role: (r['role'] ?? 'mesero') as String);
      }
    } catch (e) { _onErr(e); }
    return null;
  }
  /// Personal activo del negocio con ese codigo. null = sin conexion; lista vacia = codigo no existe.
  /// Personal del negocio para la pantalla de entrada (nombre y rol, sin correos).
  Future<List<Map<String, dynamic>>?> loadStaff(String codigo) async {
    try {
      final res = await sb.rpc('personal_para_entrar', params: <String, dynamic>{'p_codigo': codigo});
      return List<Map<String, dynamic>>.from(res as List);
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST202') { debugPrint('personal: $e'); return null; }
      try { // base de datos anterior a 0016
        final res = await sb.rpc('personal_del_negocio', params: <String, dynamic>{'p_codigo': codigo});
        return List<Map<String, dynamic>>.from(res as List);
      } catch (e2) { debugPrint('personal: $e2'); return null; }
    } catch (e) { debugPrint('personal: $e'); return null; }
  }
  /// Comprueba el PIN en el servidor (con bloqueo tras varios intentos). Devuelve el correo para abrir la
  /// sesion si es correcto, o el mensaje para mostrar.
  Future<(String?, String?)> comprobarPin(Map<String, dynamic> persona, String pin) async {
    final viejo = persona['email'] as String?;
    if (viejo != null && viejo.isNotEmpty) return (viejo, null); // base de datos anterior a 0016
    try {
      final r = await sb.rpc('entrar_con_pin', params: <String, dynamic>{'p_usuario': persona['id'], 'p_pin': pin});
      final m = Map<String, dynamic>.from(r as Map);
      if (m['ok'] == true) return (m['correo'] as String?, null);
      if (m['motivo'] == 'bloqueado') {
        return (null, 'Demasiados intentos. Por seguridad espera ${m['espera_min']} min y vuelve a intentar.');
      }
      final quedan = (m['restantes'] as num?)?.toInt();
      return (null, quedan != null && quedan <= 2 ? 'PIN incorrecto. Te quedan $quedan intentos.' : 'PIN incorrecto');
    } catch (e) {
      return (null, mensajeDe(e));
    }
  }
  /// Cambia el PIN del usuario que tiene la sesion abierta.
  /// Usa la funcion 'cambiar_pin' de Supabase (aplica al instante).
  /// Devuelve null si todo bien, o un mensaje de error para mostrar.
  Future<String?> cambiarMiPin(String actual, String nuevo) async {
    try {
      final res = await sb.rpc('cambiar_pin',
          params: <String, dynamic>{'p_actual': actual, 'p_nuevo': nuevo});
      switch (res.toString()) {
        case 'ok': return null;
        case 'pin_actual_incorrecto': return 'El PIN actual no es correcto';
        case 'pin_nuevo_invalido': return 'El PIN nuevo debe ser de 6 numeros';
        case 'pin_nuevo_facil': return kMsgPinFacil;
        case 'sin_sesion': return 'Tu sesion expiro. Vuelve a entrar e intenta de nuevo.';
        default: return 'No se pudo cambiar el PIN. Revisa tu conexion.';
      }
    } catch (_) { return 'No se pudo cambiar el PIN. Revisa tu conexion.'; }
  }
  Future<bool> signInStaff(String email, String pin) async {
    try {
      await sb.auth.signInWithPassword(email: email, password: '$pin-comandas');
      return true;
    } catch (_) { return false; }
  }
  /// Crea, da acceso o elimina usuarios con su acceso real (funcion admin-usuarios). Devuelve null si todo bien o el mensaje de error.
  Future<String?> usuarioNube(Map<String, dynamic> body) async {
    const sinRed = 'No se pudo completar. Revisa tu conexion e intenta de nuevo.';
    try {
      final r = await sb.functions.invoke('admin-usuarios', body: body);
      final d = r.data;
      if (d is Map && d['error'] != null) return d['error'].toString();
      return null;
    } on FunctionException catch (e) {
      final d = e.details;
      if (d is Map && d['error'] != null) return d['error'].toString();
      return sinRed;
    } catch (_) {
      return sinRed;
    }
  }
  Future<void> saveUser({String? id, required String name, required String pin, required String role, required bool active}) async {
    try { await sb.rpc('save_user', params: <String, dynamic>{'p_id': id, 'p_name': name, 'p_pin': pin, 'p_role': role, 'p_active': active}); } catch (e) { _onErr(e); }
  }
  Future<void> transferTable(int from, int to) async {
    try {
      await sb.from('account_items').update(<String, dynamic>{'table_number': to}).eq('table_number', from);
      await sb.from('tickets').update(<String, dynamic>{'table_number': to}).eq('table_number', from).neq('status', 'anulada');
      await sb.from('dining_tables').update(<String, dynamic>{'status': 'ocupada', 'waiter': currentUser}).eq('number', to);
      await sb.from('dining_tables').update(<String, dynamic>{'status': 'disponible', 'waiter': null, 'opened_at': null}).eq('number', from);
    } catch (e) { _onErr(e); }
  }
  Product? productById(String id) { for (final p in products) { if (p.id == id) return p; } return null; }
  Ingredient? ingredientById(String id) { for (final i in ingredients) { if (i.id == id) return i; } return null; }
  int maxMakeable(Product p) {
    const big = 1000000000;
    if (p.comboItems.isNotEmpty) {
      var m = big;
      for (final c in p.comboItems) {
        final cp = productById(c.productId);
        if (cp == null || c.qty <= 0) continue;
        final cm = maxMakeable(cp);
        if (cm < 0) continue;
        final canDo = (cm / c.qty).floor();
        if (canDo < m) m = canDo;
      }
      return m == big ? -1 : m;
    }
    if (p.recipe.isNotEmpty) {
      var m = big;
      for (final r in p.recipe) {
        final ing = ingredientById(r.ingredientId);
        if (ing == null || r.qty <= 0) continue;
        final canDo = (ing.stock / r.qty).floor();
        if (canDo < m) m = canDo;
      }
      return m == big ? -1 : m;
    }
    return -1;
  }
  List<Product> lowAvailabilityProducts({int threshold = 5}) {
    final res = products.where((p) { final m = maxMakeable(p); return m >= 0 && m <= threshold; }).toList();
    res.sort((a, b) => maxMakeable(a).compareTo(maxMakeable(b)));
    return res;
  }
  double productCostUsd(Product p) {
    if (p.comboItems.isNotEmpty) {
      var c = 0.0;
      for (final ci in p.comboItems) { final cp = productById(ci.productId); if (cp != null) c += productCostUsd(cp) * ci.qty; }
      return c;
    }
    var c = 0.0;
    for (final r in p.recipe) { final ing = ingredientById(r.ingredientId); if (ing != null) c += toUsd(ing.cost, ing.costCurrency) * r.qty; }
    return c;
  }
  double productProfitUsd(Product p) => toUsd(p.price, p.cur) - productCostUsd(p);
  double get todayCostUsd => salesCostUsd(todaySales);
  /// Reporte de un periodo calculado en el servidor con TODAS las ventas (null si no hay conexion).
  Future<Map<String, dynamic>?> reportePeriodo(DateTime ini, DateTime fin) async {
    try {
      final r = await sb.rpc('reporte_periodo', params: <String, dynamic>{
        'p_desde': ini.toUtc().toIso8601String(), 'p_hasta': fin.toUtc().toIso8601String()});
      return Map<String, dynamic>.from(r as Map);
    } catch (e) {
      debugPrint('reporte: $e');
      return null;
    }
  }
  /// Costo estimado de unas unidades vendidas ({producto: cantidad}) con los costos actuales.
  double costoDeUnidades(Map<String, int> unidades) {
    var c = 0.0;
    for (final e in unidades.entries) {
      final ps = products.where((x) => x.name == e.key).toList();
      if (ps.isNotEmpty) c += productCostUsd(ps.first) * e.value;
    }
    return c;
  }
  double salesCostUsd(Iterable<Sale> list) {
    var c = 0.0;
    for (final s in list) {
      for (final l in s.lines) {
        final ps = products.where((x) => x.name == l.name).toList();
        if (ps.isNotEmpty) c += productCostUsd(ps.first) * l.qty;
      }
    }
    return c;
  }
  // Suma cuanto se gasta de cada insumo (recetas y combos). "skip" = ingredientes que el cliente pidio quitar.
  void _acumularInsumos(Product p, double q, Map<String, double> acc, {Set<String> skip = const <String>{}, int nivel = 0}) {
    if (nivel > 6) return;
    if (p.comboItems.isNotEmpty) {
      for (final c in p.comboItems) {
        final cp = productById(c.productId);
        if (cp != null) _acumularInsumos(cp, c.qty * q, acc, nivel: nivel + 1);
      }
      return;
    }
    for (final r in p.recipe) {
      if (skip.contains(r.ingredientId)) continue;
      acc[r.ingredientId] = (acc[r.ingredientId] ?? 0) + r.qty * q;
    }
  }
  // Descuenta todo en UNA llamada (antes era una por ingrediente y el mesero esperaba varios segundos).
  Future<void> _descontarInsumos(Map<String, double> acc) async {
    final items = [for (final e in acc.entries) if (e.value > 0) <String, dynamic>{'id': e.key, 'qty': e.value}];
    if (items.isEmpty) return;
    try {
      await sb.rpc('descontar_insumos', params: <String, dynamic>{'p_items': items});
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST202') rethrow; // base de datos sin la funcion nueva: se descuenta uno por uno
      for (final it in items) {
        await sb.rpc('deduct_ingredient', params: <String, dynamic>{'i_id': it['id'], 'i_qty': it['qty']});
      }
    }
  }

  String _slug(String s) {
    final base = s.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    return base.isEmpty ? 'cat_${DateTime.now().millisecondsSinceEpoch}' : base;
  }
  Future<void> addCategory(String label, String emoji) async {
    if (label.trim().isEmpty) return;
    final pos = categories.isEmpty ? 10 : categories.map((c) => c.position).reduce((a, b) => a > b ? a : b) + 10;
    try { await sb.from('categories').insert(<String, dynamic>{'key': _slug(label), 'label': label.trim(), 'emoji': emoji.trim().isEmpty ? '🍽️' : emoji.trim(), 'position': pos, 'protected': false}); } catch (e) { _onErr(e); }
  }
  Future<void> updateCategory(String id, String label, String emoji) async {
    try { await sb.from('categories').update(<String, dynamic>{'label': label.trim(), 'emoji': emoji.trim().isEmpty ? '🍽️' : emoji.trim()}).eq('id', id); } catch (e) { _onErr(e); }
  }
  Future<void> deleteCategory(CatDef c) async {
    if (c.protected) return;
    try {
      await sb.from('products').update(<String, dynamic>{'category': 'otros'}).eq('category', c.key);
      await sb.from('categories').delete().eq('id', c.id);
    } catch (e) { _onErr(e); }
  }

  int _nextTicketNumber() {
    var m = 0;
    for (final t in tickets) { if (t.number > m) m = t.number; }
    return m + 1;
  }

  String tableStatus(int n) {
    final t = tables.where((e) => e.number == n).toList();
    final st = t.isEmpty ? 'disponible' : t.first.status;
    if (st == 'pago_espera') return 'pago_espera';
    if (st == 'pago_servido' || st == 'pagada') return 'pago_servido';
    if (account(n).isEmpty) return 'disponible';
    final tk = tickets.where((x) => x.table == n && x.status != 'anulada' && x.status != 'entregada').toList();
    if (tk.any((x) => x.status == 'lista')) return 'listo';
    if (tk.isNotEmpty) return 'cocina';
    return 'servido';
  }

  Future<void> setBusinessName(String n) async {
    try { await sb.from('app_config').update(<String, dynamic>{'business_name': n, 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', 1); }
    catch (e) { _onErr(e); }
  }
  Future<void> markMotivShown() async {
    motivShown = true; notifyListeners();
    try { await sb.from('app_config').update(<String, dynamic>{'motiv_shown': true}).eq('id', 1); } catch (e) { _onErr(e); }
  }
  void _leerTasa(Map<String, dynamic> r) {
    if (r.containsKey('rate') && r['rate'] != null) rate = (r['rate'] as num).toDouble();
    tasaAuto = (r['tasa_auto'] ?? false) as bool;
    tasaOrigen = (r['tasa_origen'] ?? 'manual') as String;
    tasaFecha = DateTime.tryParse('${r['tasa_fecha'] ?? ''}');
  }
  /// Activa o apaga la tasa oficial del BCV. Devuelve un mensaje de error, o null si salio bien.
  Future<String?> usarTasaBcv(bool activar) async {
    try {
      final r = await sb.rpc('usar_tasa_bcv', params: {'p_activar': activar});
      if (r is Map) _leerTasa(Map<String, dynamic>.from(r));
      notifyListeners();
      return null;
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202') return 'El servidor todavia no tiene esta opcion.';
      return mensajeDe(e);
    } catch (e) { return mensajeDe(e); }
  }
  Future<void> setRate(double r) async {
    try { await sb.from('app_config').update(<String, dynamic>{'rate': r, 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', 1); }
    catch (e) { _onErr(e); }
  }
  Future<void> toggleProduct(Product p) async {
    try { await sb.from('products').update(<String, dynamic>{'available': !p.available}).eq('id', p.id); }
    catch (e) { _onErr(e); }
  }
  Future<void> addProduct(Product p) async {
    try { await sb.from('products').insert(p.toRow()); } catch (e) { _onErr(e); }
  }
  Future<void> updateProduct(Product p) async {
    try { await sb.from('products').update(p.toRow()).eq('id', p.id); } catch (e) { _onErr(e); }
  }
  Future<void> deleteProduct(Product p) async {
    try { await sb.from('products').delete().eq('id', p.id); } catch (e) { _onErr(e); }
  }
  Future<void> openTable(int n) async {
    try {
      final t = tables.firstWhere((e) => e.number == n);
      if (t.status == 'disponible') {
        await sb.from('dining_tables').update(<String, dynamic>{
          'status': 'ocupada', 'waiter': currentUser, 'opened_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('number', n);
      }
    } catch (e) { _onErr(e); }
  }

  Future<int?> send(String key, {int? table, String? takeawayId, String? takeawayName, String? note, bool keepCart = false}) async {
    final items = cart(key);
    if (items.isEmpty) return null;

    // Si la mesa / para-llevar tiene una cuenta abierta SIN cobrar y ya existe
    // una comanda valida, la adicion reusa ESE mismo numero.
    // Si ya se cobro, o la comanda anterior fue anulada, se genera un numero nuevo.
    int? numeroSesion;
    if (table != null && account(table).isNotEmpty) {
      final st = tableStatus(table);
      if (st != 'pago_espera' && st != 'pago_servido') {
        final previas = tickets.where((t) => t.table == table && t.status != 'anulada').toList();
        if (previas.isNotEmpty) {
          previas.sort((a, b) => a.sentAt.compareTo(b.sentAt));
          numeroSesion = previas.last.number;
        }
      }
    } else if (takeawayId != null && takeawayAccount(takeawayId).isNotEmpty) {
      final tw = takeaways.where((t) => t.id == takeawayId).toList();
      final yaPagada = tw.isNotEmpty && tw.first.status == 'pagada';
      if (!yaPagada) {
        final previas = tickets.where((t) => t.takeawayId == takeawayId && t.status != 'anulada').toList();
        if (previas.isNotEmpty) {
          previas.sort((a, b) => a.sentAt.compareTo(b.sentAt));
          numeroSesion = previas.last.number;
        }
      }
    }
    final adicion = numeroSesion != null;
    List<String> exNames(CartItem it) => [for (final e in it.p.extras) if (it.extras.contains(e.id)) e.name];
    List<String> quitaNames(CartItem it) => [
      ...it.quita,
      for (final id in it.quitaIng) if (ingredientById(id) != null) ingredientById(id)!.name,
    ];
    final lines = [for (final it in items) <String, dynamic>{
      'name': it.p.name, 'qty': it.qty, 'size': it.size?.name, 'extras': exNames(it), 'quita': quitaNames(it), 'note': it.note,
    }];
    final insumos = <String, double>{};
    for (final it in items) { _acumularInsumos(it.p, it.qty.toDouble(), insumos, skip: it.quitaIng); }
    final conCuenta = table != null || takeawayId != null;
    final cuenta = [if (conCuenta) for (final it in items) <String, dynamic>{
      'product_name': it.p.name, 'qty': it.qty, 'size': it.size?.name, 'extras': exNames(it), 'quita': quitaNames(it),
      'note': it.note, 'unit_usd': toUsd(it.unit(), it.p.cur),
    }];
    // Mismo id mientras el pedido no cambie: si la senal falla y se reintenta, la comanda no se duplica.
    final firma = '$table|$takeawayId|$note|$lines';
    final pendiente = _envioPendiente[key];
    final idComanda = (pendiente != null && pendiente.$1 == firma) ? pendiente.$2 : nuevoId();
    _envioPendiente[key] = (firma, idComanda);
    try {
      int number;
      try {
        // Comanda, cuenta, mesa e inventario en UNA operacion: o se guarda todo, o nada.
        final r = await sb.rpc('enviar_comanda', params: <String, dynamic>{'p': <String, dynamic>{
          'id': idComanda, 'numero': numeroSesion, 'mesa': table, 'llevar_id': takeawayId, 'llevar_nombre': takeawayName,
          'mesero': currentUser, 'nota': note, 'lineas': lines, 'cuenta': cuenta,
          'insumos': [for (final e in insumos.entries) if (e.value > 0) <String, dynamic>{'id': e.key, 'qty': e.value}],
        }});
        number = (r as num).toInt();
      } on PostgrestException catch (e) {
        if (e.code != 'PGRST202') rethrow;
        number = await _enviarPorPartes(idComanda, numeroSesion, table, takeawayId, takeawayName, note, lines, cuenta, insumos);
      }
      _envioPendiente.remove(key);
      if (!keepCart) items.clear();
      notifyListeners();
      return number;
    } catch (e) { _onErr(e); return null; }
  }

  final Map<String, (String, String)> _envioPendiente = {};

  // Solo si la base de datos aun no tiene enviar_comanda (antes de aplicar 0015): los pasos por separado.
  Future<int> _enviarPorPartes(String id, int? numero, int? table, String? takeawayId, String? takeawayName, String? note,
      List<Map<String, dynamic>> lines, List<Map<String, dynamic>> cuenta, Map<String, double> insumos) async {
    final tRes = await sb.from('tickets').insert(<String, dynamic>{
      'id': id, if (numero != null) 'number': numero,
      'table_number': table, 'takeaway_id': takeawayId, 'takeaway_name': takeawayName, 'waiter': currentUser,
      'status': 'nueva', 'adicion': numero != null, 'note': note, 'lines': lines,
    }).select();
    final number = tRes.isNotEmpty ? ((tRes.first['number'] ?? 0) as num).toInt() : 0;
    await Future.wait<dynamic>([
      if (cuenta.isNotEmpty)
        sb.from('account_items').insert([for (final c in cuenta) <String, dynamic>{...c, 'table_number': table, 'takeaway_id': takeawayId, 'ticket_id': id}]),
      if (table != null)
        sb.from('dining_tables').update(<String, dynamic>{'status': 'ocupada', 'waiter': currentUser, 'opened_at': DateTime.now().toUtc().toIso8601String()}).eq('number', table),
      _descontarInsumos(insumos),
    ]);
    return number;
  }

  Future<void> advance(Ticket t) async {
    final next = switch (t.status) { 'nueva' => 'preparando', 'preparando' => 'lista', 'lista' => 'entregada', _ => t.status };
    try { await sb.from('tickets').update(<String, dynamic>{'status': next}).eq('id', t.id); } catch (e) { _onErr(e); }
  }
  Future<void> cancelTicket(Ticket t) async {
    try { await sb.from('tickets').update(<String, dynamic>{'status': 'anulada'}).eq('id', t.id); } catch (e) { _onErr(e); }
  }
  double valueOfTicket(String ticketId) {
    var v = 0.0;
    for (final list in accounts.values) { for (final a in list) { if (a.ticketId == ticketId) v += a.lineUsd; } }
    for (final list in takeawayAccounts.values) { for (final a in list) { if (a.ticketId == ticketId) v += a.lineUsd; } }
    return v;
  }
  Future<void> cancelTicketFull(Ticket t, {required String reason, required bool merchandiseUsed}) async {
    try {
      final value = valueOfTicket(t.id);
      await sb.from('cancellations').insert(<String, dynamic>{
        'ticket_number': t.number, 'table_number': t.table, 'takeaway_name': t.takeawayName,
        'reason': reason, 'merchandise_used': merchandiseUsed, 'value_usd': merchandiseUsed ? value : 0, 'by_user': currentUser,
      });
      await sb.from('account_items').delete().eq('ticket_id', t.id);
      await sb.from('tickets').update(<String, dynamic>{'status': 'anulada'}).eq('id', t.id);
    } catch (e) { _onErr(e); }
  }
  Future<void> reprint(Ticket t) async {
    try { await sb.from('tickets').update(<String, dynamic>{'reprinted': true}).eq('id', t.id); } catch (e) { _onErr(e); }
  }

  /// [ventaId] lo crea la pantalla de cobro una sola vez: si la red falla y se reintenta, la venta no se duplica.
  Future<bool> pay(List<Payment> payments, {int? table, String? takeawayId, String? cartKey, String? ventaId}) async {
    try {
      List<Map<String, dynamic>> saleLines;
      double total;
      String? customer;
      if (table != null) {
        final acc = account(table);
        if (acc.isEmpty) return false;
        saleLines = [for (final a in acc) <String, dynamic>{'name': a.name, 'qty': a.qty, 'lineUsd': a.lineUsd}];
        total = acc.fold(0.0, (s, a) => s + a.lineUsd);
      } else if (takeawayId != null) {
        final acc = takeawayAccount(takeawayId);
        if (acc.isEmpty) return false;
        saleLines = [for (final a in acc) <String, dynamic>{'name': a.name, 'qty': a.qty, 'lineUsd': a.lineUsd}];
        total = acc.fold(0.0, (s, a) => s + a.lineUsd);
        final tk = takeaways.where((t) => t.id == takeawayId).toList();
        customer = tk.isNotEmpty ? tk.first.name : null;
      } else {
        final items = cart(cartKey ?? '');
        if (items.isEmpty) return false;
        saleLines = [for (final it in items) <String, dynamic>{'name': it.p.name, 'qty': it.qty, 'lineUsd': lineUsd(it)}];
        total = items.fold(0.0, (s, it) => s + lineUsd(it));
      }
      errorCobro = null;
      final pagos = [for (final p in payments) <String, dynamic>{'method': p.method, 'amountUsd': p.amountUsd, 'reference': p.reference}];
      final id = ventaId ?? nuevoId();
      try {
        // Venta y estado de la mesa (o del pedido para llevar) en UNA operacion. Reintentar con el mismo id no duplica,
        // y una mesa ya cobrada no se puede cobrar otra vez.
        await sb.rpc('cobrar', params: <String, dynamic>{'p': <String, dynamic>{
          'id': id, 'mesa': table, 'llevar_id': takeawayId, 'pagos': pagos,
          if (table == null && takeawayId == null) ...<String, dynamic>{'lineas': saleLines, 'total': total},
        }});
      } on PostgrestException catch (e) {
        if (e.code != 'PGRST202') rethrow;
        // base de datos sin la funcion nueva (antes de aplicar 0015): los pasos por separado
        try {
          await sb.from('sales').insert(<String, dynamic>{
            'id': id, 'table_number': table, 'customer': customer, 'total_usd': total, 'lines': saleLines, 'payments': pagos,
          });
        } on PostgrestException catch (e2) {
          if (e2.code != '23505') rethrow; // ya se habia guardado en el intento anterior
        }
        if (takeawayId != null) await sb.from('takeaways').update(<String, dynamic>{'status': 'pagada'}).eq('id', takeawayId);
      }
      if (table == null && takeawayId == null) cart(cartKey ?? '').clear();
      notifyListeners();
      return true;
    } catch (e) { errorCobro = mensajeDe(e); return false; }
  }

  DateTime? get lastCloseAt => cashCloses.isNotEmpty ? cashCloses.first.closedAt : null;
  // "Hoy" = ventas desde el ultimo cierre de caja (no por fecha del calendario).
  List<Sale> get todaySales {
    final lc = lastCloseAt;
    if (lc == null) return List<Sale>.from(sales);
    return sales.where((s) => s.at.isAfter(lc)).toList();
  }
  double get todayTotalUsd => todaySales.fold(0.0, (s, e) => s + e.totalUsd);
  Map<String, int> unitsToday() {
    final m = <String, int>{};
    for (final s in todaySales) { for (final l in s.lines) { m[l.name] = (m[l.name] ?? 0) + l.qty; } }
    return m;
  }
  Map<String, double> byMethodToday() {
    final m = <String, double>{};
    for (final s in todaySales) { for (final p in s.payments) { m[p.method] = (m[p.method] ?? 0) + p.amountUsd; } }
    return m;
  }
}

final store = Store();

part of '../main.dart';

// Tema visual de ComandApp, barra con la marca y pantalla raiz.

// ======================= APP / TEMA =======================
// Colores de la marca ComandApp (tomados del logo).
const kAmber = Color(0xFFFCAC0C);   // ambar del logo: rellenos y acentos
const kInk = Color(0xFF111111);     // negro del logo: barras y texto fuerte
const kPrimary = Color(0xFFA05F00); // ambar tostado: texto e iconos sobre fondo claro (buen contraste)
const kOk = Color(0xFF3E8E1E);      // verde (lechuga)
const kBad = Color(0xFFC8352A);     // rojo (tomate)
const kBg = Color(0xFFF5F4F1);
const kLine = Color(0xFFE6E2DC);
const kMuted = Color(0xFF6F6A63);

ThemeData temaComandApp() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: kInk, onPrimary: Colors.white,
    primaryContainer: kAmber, onPrimaryContainer: Color(0xFF231700),
    secondary: kPrimary, onSecondary: Colors.white,
    secondaryContainer: Color(0xFFFFEDC2), onSecondaryContainer: Color(0xFF2B1D00),
    tertiary: kOk, onTertiary: Colors.white,
    error: kBad, onError: Colors.white,
    surface: Colors.white, onSurface: kInk,
    surfaceContainerLowest: Colors.white, surfaceContainerLow: Color(0xFFFAF9F7),
    surfaceContainer: Color(0xFFF3F1ED), surfaceContainerHigh: Color(0xFFEDEAE5), surfaceContainerHighest: Color(0xFFE6E2DC),
    onSurfaceVariant: kMuted, outline: Color(0xFFCFCAC2), outlineVariant: kLine,
  );
  final round = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  const btnText = TextStyle(fontFamily: 'Outfit', fontSize: 15.5, fontWeight: FontWeight.w600);
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'Outfit');
  return base.copyWith(
    scaffoldBackgroundColor: kBg,
    appBarTheme: const AppBarTheme(
      backgroundColor: kInk, foregroundColor: Colors.white, elevation: 0, scrolledUnderElevation: 0, centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: 'Outfit', fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
      iconTheme: IconThemeData(color: Colors.white), actionsIconTheme: IconThemeData(color: Colors.white),
    ),
    cardTheme: CardThemeData(
      color: Colors.white, surfaceTintColor: Colors.transparent, elevation: 0, margin: const EdgeInsets.all(4),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: kLine)),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(64, 48), shape: round, textStyle: btnText)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
      minimumSize: const Size(64, 48), shape: round, textStyle: btnText, foregroundColor: kInk,
      side: const BorderSide(color: Color(0xFFCFCAC2)))),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: kPrimary, shape: round,
      textStyle: const TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600))),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kAmber, foregroundColor: kInk, elevation: 2,
      extendedTextStyle: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w700, fontSize: 15)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFCFCAC2))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFCFCAC2))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kInk, width: 1.6)),
    ),
    chipTheme: ChipThemeData(
      selectedColor: const Color(0xFFFFEDC2), backgroundColor: Colors.white,
      side: const BorderSide(color: Color(0xFFCFCAC2)), shape: const StadiumBorder(),
      labelStyle: const TextStyle(fontFamily: 'Outfit', color: kInk)),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white, surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      titleTextStyle: const TextStyle(fontFamily: 'Outfit', fontSize: 20, fontWeight: FontWeight.w700, color: kInk)),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white, surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24)))),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating, backgroundColor: kInk,
      contentTextStyle: const TextStyle(fontFamily: 'Outfit', color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    listTileTheme: const ListTileThemeData(iconColor: kMuted),
    dividerTheme: const DividerThemeData(color: kLine, space: 24),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: kAmber),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? kInk : null),
      trackColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? kAmber : null),
    ),
  );
}

// Pantalla ancha (computadora o tableta horizontal): se usa un diseno propio, no el del telefono.
// Identificador unico (UUID v4) creado en el telefono.
String nuevoId() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

bool esAncho(BuildContext context) => MediaQuery.sizeOf(context).width >= 900;

// Barra superior con la marca. En pantalla ancha muestra el logo, el negocio y quien tiene la sesion.
PreferredSizeWidget barraMarca(BuildContext context, String titulo, {List<Widget> actions = const []}) {
  if (!esAncho(context)) return AppBar(title: Text(titulo), actions: actions);
  return AppBar(
    toolbarHeight: 64,
    titleSpacing: Navigator.canPop(context) ? 0 : 20,
    title: AnimatedBuilder(animation: store, builder: (_, __) => Row(children: [
      Image.asset('assets/marca/simbolo.png', height: 30, errorBuilder: (_, __, ___) => const SizedBox()),
      const SizedBox(width: 14),
      Text(titulo),
      if (store.businessName.isNotEmpty) ...[
        Container(width: 1, height: 22, margin: const EdgeInsets.symmetric(horizontal: 14), color: Colors.white24),
        Flexible(child: Text(store.businessName, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white60, fontSize: 16, fontWeight: FontWeight.w500))),
      ],
    ])),
    actions: [
      if (store.currentUser.isNotEmpty)
        Padding(padding: const EdgeInsets.only(right: 10), child: Center(child: Container(
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
          decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(99)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            CircleAvatar(radius: 13, backgroundColor: kAmber, foregroundColor: kInk,
                child: Text(store.currentUser.trim().isEmpty ? '?' : store.currentUser.trim()[0].toUpperCase(),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
            const SizedBox(width: 8),
            Text(store.currentUser, style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600)),
            Text('  ·  ${kRoles[store.currentUserRole] ?? store.currentUserRole}', style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
          ]),
        ))),
      ...actions,
      const SizedBox(width: 12),
    ],
  );
}

Widget _homeForRole(String role) =>
    role == 'admin' ? const AdminScreen() : (role == 'cocina' ? const KitchenScreen() : const TablesScreen());
void _logout(BuildContext context) {
  store.currentUser = '';
  store.currentUserRole = '';
  // primero se quita el aviso de este celular (necesita la sesion abierta), despues se limpia la memoria y se cierra la sesion
  store.saliendo = store.unregisterPush().whenComplete(() async {
    await store.reset();
    try { await sb.auth.signOut(); } catch (_) {}
  });
  Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
}

class ComandApp extends StatelessWidget {
  const ComandApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ComandApp',
      debugShowCheckedModeBanner: false,
      theme: temaComandApp(),
      home: const LoginScreen(),
      builder: (context, child) => AnimatedBuilder(
        animation: store,
        builder: (_, __) => Stack(children: [
          Positioned.fill(child: child ?? const SizedBox()),
          if (store.error != null)
            Positioned(left: 12, right: 12, bottom: 12, child: SafeArea(
              child: Material(color: kBad, borderRadius: BorderRadius.circular(14), child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: store.clearError,
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), child: Row(children: [
                  const Icon(Icons.wifi_off, color: Colors.white, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text(store.error!, style: const TextStyle(color: Colors.white, fontSize: 13))),
                  const Icon(Icons.close, color: Colors.white, size: 18),
                ])),
              )),
            )),
        ]),
      ),
    );
  }
}

Color statusColor(String s) => switch (s) {
      'disponible' => kOk,
      'ocupada' => const Color(0xFFE09400),
      'cocina' => const Color(0xFF2F6FDB),
      'listo' => const Color(0xFF0E9F8E),
      'servido' => const Color(0xFF7C4DCC),
      'pago_espera' => const Color(0xFFE8590C),
      'pago_servido' => const Color(0xFF6B5B4E),
      _ => const Color(0xFF8A8F98),
    };
String statusLabel(String s) => switch (s) {
      'disponible' => 'Disponible',
      'ocupada' => 'Ocupada',
      'cocina' => 'En cocina',
      'listo' => 'Pedido listo',
      'servido' => 'Servido',
      'pago_espera' => 'Pagado - en espera',
      'pago_servido' => 'Pagado - servido',
      _ => s,
    };

Widget lowStockCard() {
  final low = store.lowStock;
  return Card(color: Colors.red.shade50, child: Padding(padding: const EdgeInsets.all(12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: const [Icon(Icons.warning_amber, color: Colors.red), SizedBox(width: 8),
        Text('Inventario bajo', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red))]),
      const SizedBox(height: 6),
      for (final p in low)
        Text('- ' + p.name + ': ' + (p.stock <= 0 ? 'AGOTADO' : 'quedan ' + p.stock.toStringAsFixed(0)) + ' (min ' + p.minStock.toStringAsFixed(0) + ')',
            style: const TextStyle(fontSize: 12.5)),
    ])));
}

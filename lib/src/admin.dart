part of '../main.dart';

// Inicio del administrador.

// ======================= ADMINISTRADOR =======================
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}
class _AdminScreenState extends State<AdminScreen> {
  final _rate = TextEditingController();
  final _bizName = TextEditingController();
  final _rateFocus = FocusNode();
  bool _bizTocado = false;
  void _syncRate() {
    if (!_rateFocus.hasFocus) _rate.text = store.rate.toStringAsFixed(2);
    if (!_bizTocado && _bizName.text != store.businessName) _bizName.text = store.businessName;
  }
  bool _motivDone = false;
  void _checkMotiv() {
    // Mensaje personal del fundador: solo en su propio negocio, nunca en los de clientes.
    if (_motivDone || store.motivShown || !mounted || store.negocioCodigo != 'puesto-de-comida') return;
    _motivDone = true;
    store.markMotivShown();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(context: context, builder: (dctx) => AlertDialog(
        icon: const Icon(Icons.favorite, color: kPrimary, size: 48),
        title: const Text('Ángel David'),
        content: const Text('Esto que construiste es prueba de lo que eres capaz. '
            'No te rindas nunca con tus metas. Y en los días difíciles, cuando pese, no cargues solo: '
            'llama a tu tío, que siempre estará para ti. 💪'),
        actions: [FilledButton(onPressed: () => Navigator.pop(dctx), child: const Text('Gracias'))]));
    });
  }

  void _cierreDeCaja(BuildContext context) {
    // Mesas con cuenta abierta que todavia NO se han cobrado
    final mesasPend = store.tables.where((t) {
      final s = store.tableStatus(t.number);
      return s != 'disponible' && s != 'pago_espera' && s != 'pago_servido';
    }).length;
    // Pedidos para llevar sin cobrar
    final llevarPend = store.takeaways.where((t) => t.status != 'pagada').length;

    // No se puede cerrar la caja si queda algo sin cobrar
    if (mesasPend > 0 || llevarPend > 0) {
      showDialog<void>(context: context, builder: (dctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 40),
        title: const Text('Todavia no puedes cerrar la caja'),
        content: Text('Hay $mesasPend mesa(s) y $llevarPend pedido(s) para llevar sin cobrar.\n\n'
            'Cobra o anula todo antes de cerrar la caja.'),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(dctx), child: const Text('Entendido')),
        ],
      ));
      return;
    }

    // Todo cobrado: mostrar el reporte de caja y confirmar el reinicio
    final byMethod = store.byMethodToday();
    showDialog<void>(context: context, builder: (dctx) => AlertDialog(
      icon: const Icon(Icons.point_of_sale, color: kPrimary, size: 40),
      title: const Text('Cierre de caja'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Resumen de ventas de hoy', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text('Total vendido: ${dualUsd(store.todayTotalUsd)}', style: const TextStyle(fontWeight: FontWeight.bold)),
        Text('${store.todaySales.length} cuentas cobradas'),
        if (store.todayGastosUsd > 0) ...[
          const SizedBox(height: 6),
          Text('Gastos del turno: ${dualUsd(store.todayGastosUsd)}'),
          Text('Ventas menos gastos: ${dualUsd(store.todayTotalUsd - store.todayGastosUsd)}', style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
        const SizedBox(height: 10),
        if (byMethod.isEmpty) const Text('Sin ventas registradas hoy', style: TextStyle(color: Colors.grey))
        else ...[
          const Text('Por medio de pago:', style: TextStyle(fontWeight: FontWeight.w600)),
          for (final e in byMethod.entries) Padding(padding: const EdgeInsets.only(top: 2),
            child: Text('- ${e.key}: ${dualUsd(e.value)}')),
        ],
        const SizedBox(height: 12),
        const Text('Al cerrar la caja se reinician mesas, pedidos y comandas. Las ventas y el historial NO se borran.',
          style: TextStyle(fontSize: 12, color: Colors.grey)),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancelar')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: kPrimary),
          onPressed: () async {
            Navigator.pop(dctx);
            await store.hacerCierreDeCaja();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Caja cerrada. Mesas, pedidos y comandas reiniciados.')));
            }
          }, child: const Text('Cerrar caja')),
      ],
    ));
  }
  @override
  void initState() { super.initState(); _rate.text = store.rate.toStringAsFixed(2); _bizName.text = store.businessName; store.addListener(_syncRate); store.addListener(_checkMotiv); WidgetsBinding.instance.addPostFrameCallback((_) => _checkMotiv()); }
  @override
  void dispose() { store.removeListener(_syncRate); store.removeListener(_checkMotiv); _rateFocus.dispose(); _rate.dispose(); _bizName.dispose(); super.dispose(); }
  void _ir(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));

  // Quita el codigo del negocio guardado en este telefono (por ejemplo, si el equipo pasa a otro negocio).
  void _desvincular() {
    showDialog<void>(context: context, builder: (dctx) => AlertDialog(
      icon: const Icon(Icons.link_off, color: kBad, size: 36),
      title: const Text('Desvincular este dispositivo'),
      content: Text('Se cerrara la sesion y este dispositivo dejara de estar vinculado a "${store.businessName}". '
          'Para volver a usarlo habra que escribir el codigo del negocio.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancelar')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: kBad), onPressed: () async {
          Navigator.pop(dctx);
          try { await (await SharedPreferences.getInstance()).remove(kPrefCodigo); } catch (_) {}
          if (mounted) _logout(context);
        }, child: const Text('Desvincular')),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: barraMarca(context, 'Administrador', actions: [
        IconButton(tooltip: 'Cambiar mi PIN', icon: const Icon(Icons.lock_reset),
          onPressed: () => _ir(const ChangePinScreen())),
        IconButton(tooltip: 'Salir', icon: const Icon(Icons.logout), onPressed: () => _logout(context)),
      ]),
      body: AnimatedBuilder(animation: store, builder: (context, _) => LayoutBuilder(builder: (context, c) {
        // Computadora o tableta horizontal: dos columnas (resumen y ajustes a la izquierda, accesos y productos a la derecha).
        if (c.maxWidth >= 1000) {
          return Align(alignment: Alignment.topCenter, child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 400, child: ListView(padding: const EdgeInsets.fromLTRB(24, 24, 12, 32), children: [
                _resumenHoy(),
                const SizedBox(height: 14),
                if (store.lowStock.isNotEmpty) ...[lowStockCard(), const SizedBox(height: 14)],
                ..._bloqueAjustes(context),
              ])),
              Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(12, 4, 24, 32), children: [
                ..._bloqueAtajos(),
                ..._bloqueProductos(columnas: c.maxWidth >= 1300 ? 3 : 2),
              ])),
            ]),
          ));
        }
        return Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
            _resumenHoy(),
            const SizedBox(height: 14),
            if (store.lowStock.isNotEmpty) ...[lowStockCard(), const SizedBox(height: 14)],
            ..._bloqueAtajos(),
            ..._bloqueAjustes(context),
            ..._bloqueProductos(columnas: 1),
          ]),
        ));
      })),
    );
  }

  List<Widget> _bloqueAtajos() => [
        _seccion('Ventas y caja', [
          _Atajo(Icons.today_outlined, 'Historial de hoy', () => _ir(const HistoryScreen())),
          _Atajo(Icons.calendar_month_outlined, 'Historial de dias', () => _ir(const HistoryDaysScreen())),
          _Atajo(Icons.bar_chart_rounded, 'Reportes', () => _ir(const ReportesScreen())),
          _Atajo(Icons.trending_up_rounded, 'Rentabilidad', () => _ir(const RentabilidadScreen())),
          _Atajo(Icons.receipt_long_outlined, 'Gastos', () => _ir(const GastosScreen())),
          _Atajo(Icons.money_off_rounded, 'Anulaciones', () => _ir(const CancellationsScreen())),
        ]),
        _seccion('Menu e inventario', [
          _Atajo(Icons.add_circle_outline, 'Nuevo producto', () => _ir(const ProductForm())),
          _Atajo(Icons.category_outlined, 'Categorias', () => _ir(const CategoriesScreen())),
          _Atajo(Icons.inventory_2_outlined, 'Inventario', () => _ir(const InventoryScreen())),
        ]),
        _seccion('Equipo y operacion', [
          _Atajo(Icons.badge_outlined, 'Trabajadores', () => _ir(const EmployeesScreen())),
          _Atajo(Icons.manage_accounts_outlined, 'Usuarios', () => _ir(const UsersScreen())),
          _Atajo(Icons.table_bar_outlined, 'Mesas', () => _ir(const TablesScreen())),
          _Atajo(Icons.soup_kitchen_outlined, 'Cocina', () => _ir(const KitchenScreen())),
        ]),
      ];

  List<Widget> _bloqueAjustes(BuildContext context) => [
        _titulo('Ajustes del negocio'),
        Card(child: Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 16), child: Column(children: [
          if (store.negocioCodigo.isNotEmpty) ...[
            Row(children: [
              const Icon(Icons.key_outlined, color: kPrimary, size: 20),
              const SizedBox(width: 10),
              const Expanded(child: Text('Codigo para entrar a la app', style: TextStyle(color: kMuted))),
              SelectableText(store.negocioCodigo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: kInk)),
              IconButton(tooltip: 'Copiar codigo', icon: const Icon(Icons.copy_rounded, size: 18), onPressed: () {
                Clipboard.setData(ClipboardData(text: store.negocioCodigo));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Codigo copiado')));
              }),
            ]),
            const Padding(padding: EdgeInsets.only(left: 30, bottom: 10), child: Align(alignment: Alignment.centerLeft,
              child: Text('Daselo a tu personal: lo escriben una sola vez en cada telefono y queda vinculado.', style: TextStyle(fontSize: 12, color: kMuted)))),
          ],
          Row(children: [
            Expanded(child: TextField(controller: _bizName, onChanged: (_) => _bizTocado = true,
              decoration: const InputDecoration(labelText: 'Nombre del negocio', helperText: 'Sale en los comprobantes', isDense: true))),
            const SizedBox(width: 10),
            FilledButton(onPressed: () async {
              final n = _bizName.text.trim();
              if (n.isEmpty) return;
              await store.setBusinessName(n);
              _bizTocado = false;
              if (!context.mounted) return;
              FocusScope.of(context).unfocus();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nombre actualizado')));
            }, child: const Text('Guardar')),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: TextField(controller: _rate, focusNode: _rateFocus, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Tasa de cambio', prefixText: '1 USD = ', suffixText: 'Bs', isDense: true))),
            const SizedBox(width: 10),
            FilledButton(onPressed: () async {
              final v = double.tryParse(_rate.text.replaceAll(',', '.'));
              if (v != null && v > 0) {
                await store.setRate(v);
                if (!context.mounted) return;
                FocusScope.of(context).unfocus();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tasa actualizada')));
              }
            }, child: const Text('Guardar')),
          ]),
        ]))),
        const SizedBox(height: 18),
        SizedBox(width: double.infinity, height: 52, child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: kBad, side: const BorderSide(color: kBad, width: 1.4)),
          onPressed: () => _cierreDeCaja(context),
          icon: const Icon(Icons.point_of_sale), label: const Text('Cierre de caja'))),
        const Padding(padding: EdgeInsets.only(top: 6), child: Text(
          'Muestra el reporte del dia y reinicia mesas, pedidos y comandas. Solo cuando todo este cobrado. No borra las ventas.',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: kMuted))),
        Center(child: TextButton.icon(onPressed: _desvincular,
            style: TextButton.styleFrom(foregroundColor: kMuted),
            icon: const Icon(Icons.link_off, size: 18), label: const Text('Desvincular este dispositivo del negocio'))),
      ];

  List<Widget> _bloqueProductos({required int columnas}) => [
        _titulo('Productos y precios', ayuda: 'Toca un producto para editarlo'),
        if (store.products.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Cargando productos...', style: TextStyle(color: Colors.grey))),
        for (final c in store.categories) ...[
          if (store.products.any((p) => p.cat == c.key)) ...[
            Padding(padding: const EdgeInsets.only(top: 10, bottom: 6, left: 4),
              child: Text('${c.emoji}  ${c.label}', style: const TextStyle(fontWeight: FontWeight.w700, color: kPrimary, fontSize: 15))),
            LayoutBuilder(builder: (context, cc) {
              const gap = 8.0;
              final w = (cc.maxWidth - gap * (columnas - 1)) / columnas;
              return Wrap(spacing: gap, children: [
                for (final p in store.products.where((p) => p.cat == c.key))
                  SizedBox(width: w, child: Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(
                    leading: Container(width: 44, height: 44, alignment: Alignment.center,
                      decoration: BoxDecoration(color: const Color(0xFFFFF3D6), borderRadius: BorderRadius.circular(12)),
                      child: Text(p.emoji, style: const TextStyle(fontSize: 22))),
                    title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${dualPrice(p.price, p.cur)}${p.trackStock ? '  ·  stock: ${p.stock.toStringAsFixed(0)}' : ''}${store.maxMakeable(p) >= 0 ? '  ·  alcanza ~${store.maxMakeable(p)}' : ''}', style: const TextStyle(fontSize: 12)),
                    onTap: () => _ir(ProductForm(existing: p)),
                    trailing: Switch(value: p.available, onChanged: (_) => store.toggleProduct(p))))),
              ]);
            }),
          ],
        ],
      ];

  Widget _titulo(String t, {String? ayuda}) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(t, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: kInk)),
          if (ayuda != null) ...[const SizedBox(width: 10), Expanded(child: Text(ayuda, style: const TextStyle(fontSize: 12.5, color: kMuted)))],
        ]),
      );

  Widget _seccion(String t, List<_Atajo> atajos) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _titulo(t),
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 980 ? 6 : (c.maxWidth >= 720 ? 4 : (c.maxWidth >= 440 ? 3 : 2));
          const gap = 10.0;
          final w = (c.maxWidth - gap * (cols - 1)) / cols;
          return Wrap(spacing: gap, runSpacing: gap, children: [for (final a in atajos) SizedBox(width: w, child: a)]);
        }),
      ]);

  // Tarjeta negra de arriba: nombre del negocio y como va el dia.
  Widget _resumenHoy() {
    final neto = store.todayTotalUsd - store.todayGastosUsd;
    final abiertas = store.tables.where((t) => store.tableStatus(t.number) != 'disponible').length;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(color: kInk, borderRadius: BorderRadius.circular(22)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Image.asset('assets/marca/simbolo.png', height: 30, errorBuilder: (_, __, ___) => const Icon(Icons.storefront, color: kAmber)),
          const SizedBox(width: 12),
          Expanded(child: Text(store.businessName, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 18),
        const Text('Vendido hoy', style: TextStyle(color: Colors.white60, fontSize: 13)),
        const SizedBox(height: 2),
        Text(dualUsd(store.todayTotalUsd), style: const TextStyle(color: kAmber, fontSize: 28, fontWeight: FontWeight.w800, height: 1.15)),
        const SizedBox(height: 14),
        Wrap(spacing: 22, runSpacing: 8, children: [
          _dato('Cuentas cobradas', '${store.todaySales.length}'),
          _dato('Mesas abiertas', '$abiertas'),
          _dato('Tasa del dia', '${store.rate.toStringAsFixed(2)} Bs'),
          if (store.todayGastosUsd > 0) _dato('Ventas menos gastos', dualUsd(neto)),
        ]),
      ]),
    );
  }
  Widget _dato(String k, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        Text(v, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
      ]);
}

// Boton grande de acceso rapido del panel del administrador.
class _Atajo extends StatelessWidget {
  final IconData icono;
  final String texto;
  final VoidCallback onTap;
  const _Atajo(this.icono, this.texto, this.onTap);
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: kLine)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 40, height: 40, alignment: Alignment.center,
              decoration: BoxDecoration(color: const Color(0xFFFFF3D6), borderRadius: BorderRadius.circular(12)),
              child: Icon(icono, color: kPrimary, size: 22)),
            const SizedBox(height: 12),
            Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: kInk)),
          ]),
        )),
      );
}

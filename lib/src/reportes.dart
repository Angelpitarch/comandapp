part of '../main.dart';

// Reportes por semana o mes y rentabilidad.

// ======================= REPORTES (semana / mes) =======================
class ReportesScreen extends StatefulWidget {
  const ReportesScreen({super.key});
  @override
  State<ReportesScreen> createState() => _ReportesScreenState();
}
class _ReportesScreenState extends State<ReportesScreen> {
  bool _semana = true;
  int _offset = 0; // 0 = periodo actual, -1 = anterior, ...
  Future<Map<String, dynamic>?>? _remoto; // reporte del servidor para el periodo elegido
  @override
  void initState() { super.initState(); _recargar(); }
  void _recargar() => _remoto = store.reportePeriodo(_inicio, _fin);
  static const _meses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

  DateTime get _inicio {
    final n = DateTime.now();
    if (_semana) {
      final lunes = DateTime(n.year, n.month, n.day - (n.weekday - 1));
      return DateTime(lunes.year, lunes.month, lunes.day + 7 * _offset);
    }
    return DateTime(n.year, n.month + _offset, 1);
  }
  DateTime get _fin {
    final i = _inicio;
    return _semana ? DateTime(i.year, i.month, i.day + 7) : DateTime(i.year, i.month + 1, 1);
  }
  String get _titulo {
    final i = _inicio;
    if (!_semana) return '${_meses[i.month - 1]} ${i.year}';
    final f = _fin.subtract(const Duration(days: 1));
    return '${fecha(i)} al ${fecha(f)}';
  }
  void _cambiar(bool semana) => setState(() { _semana = semana; _offset = 0; _recargar(); });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reportes')),
      body: FutureBuilder<Map<String, dynamic>?>(future: _remoto, builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        return AnimatedBuilder(animation: store, builder: (context, _) {
        final ini = _inicio, fin = _fin;
        final m = snap.data;
        late final double totalVentas, totalGastos;
        late final int cuentas;
        final porMetodo = <String, double>{};
        final unidades = <String, int>{};
        final dias = <String, List<double>>{}; // clave AAAA-MM-DD -> [ventas, gastos]
        if (m != null) {
          // del servidor: todas las ventas del periodo
          totalVentas = (m['ventas'] as num? ?? 0).toDouble();
          totalGastos = (m['gastos'] as num? ?? 0).toDouble();
          cuentas = (m['cuentas'] as num? ?? 0).toInt();
          (m['por_metodo'] as Map? ?? {}).forEach((k, v) => porMetodo['$k'] = (v as num).toDouble());
          (m['unidades'] as Map? ?? {}).forEach((k, v) => unidades['$k'] = (v as num).round());
          for (final d in (m['por_dia'] as List? ?? [])) {
            dias['${d['dia']}'] = [((d['ventas'] ?? 0) as num).toDouble(), ((d['gastos'] ?? 0) as num).toDouble()];
          }
        } else {
          // sin conexion: con las ventas guardadas en este telefono
          final ventas = store.sales.where((s) => !s.at.isBefore(ini) && s.at.isBefore(fin)).toList();
          final gastos = store.gastos.where((g) => !g.at.isBefore(ini) && g.at.isBefore(fin)).toList();
          totalVentas = ventas.fold<double>(0, (a, s) => a + s.totalUsd);
          totalGastos = gastos.fold<double>(0, (a, g) => a + g.amountUsd);
          cuentas = ventas.length;
          String key(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
          for (final s in ventas) {
            for (final p in s.payments) { porMetodo[p.method] = (porMetodo[p.method] ?? 0) + p.amountUsd; }
            for (final l in s.lines) { unidades[l.name] = (unidades[l.name] ?? 0) + l.qty; }
            (dias[key(s.at)] ??= [0, 0])[0] += s.totalUsd;
          }
          for (final g in gastos) { (dias[key(g.at)] ??= [0, 0])[1] += g.amountUsd; }
        }
        final costo = store.costoDeUnidades(unidades);
        final ganancia = totalVentas - costo;
        final neta = ganancia - totalGastos;
        final topProductos = unidades.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        final diasOrd = dias.entries.toList()..sort((a, b) => b.key.compareTo(a.key));
        Widget fila(String label, double v, {bool bold = false, Color? color}) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
                const Spacer(),
                Text(dualUsd(v), style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w500, color: color)),
              ]));
        return ListView(padding: const EdgeInsets.all(16), children: [
          SegmentedButton<bool>(
            segments: const [ButtonSegment(value: true, label: Text('Semana')), ButtonSegment(value: false, label: Text('Mes'))],
            selected: {_semana},
            onSelectionChanged: (v) => _cambiar(v.first)),
          const SizedBox(height: 8),
          Row(children: [
            IconButton(onPressed: () => setState(() { _offset--; _recargar(); }), icon: const Icon(Icons.chevron_left)),
            Expanded(child: Text(_titulo, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
            IconButton(onPressed: _offset >= 0 ? null : () => setState(() { _offset++; _recargar(); }), icon: const Icon(Icons.chevron_right)),
          ]),
          const SizedBox(height: 4),
          Card(color: Colors.green.shade50, child: Padding(padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              fila('Ventas', totalVentas, bold: true),
              fila('Costo estimado', costo),
              const Divider(),
              fila('Ganancia', ganancia),
              fila('Gastos', totalGastos),
              const Divider(),
              fila('Ganancia neta', neta, bold: true, color: neta >= 0 ? Colors.green.shade800 : Colors.red),
              const SizedBox(height: 4),
              Text('$cuentas cuentas cobradas', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              if (m == null) const Text('Sin conexion: calculado con las ventas guardadas en este telefono.',
                  style: TextStyle(fontSize: 12, color: kBad)),
            ]))),
          const SizedBox(height: 4),
          const Text('El costo usa los precios de compra actuales de los ingredientes, no los de esa fecha. '
              'Los montos en Bs usan la tasa de hoy.', style: TextStyle(fontSize: 11.5, color: Colors.grey)),
          const Divider(height: 24),
          const Text('Por dia', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          if (diasOrd.isEmpty) const Text('Sin movimientos en este periodo', style: TextStyle(color: Colors.grey))
          else for (final e in diasOrd)
            Card(margin: const EdgeInsets.only(bottom: 6), child: ListTile(dense: true,
              title: Text(() { final p = e.key.split('-'); return '${p[2]}/${p[1]}/${p[0]}'; }()),
              subtitle: Text('Ventas ${usd(e.value[0])}  ·  Gastos ${usd(e.value[1])}', style: const TextStyle(fontSize: 12)),
              trailing: Text(usd(e.value[0] - e.value[1]), style: TextStyle(fontWeight: FontWeight.bold, color: e.value[0] - e.value[1] >= 0 ? Colors.green.shade700 : Colors.red)))),
          const Divider(height: 24),
          const Text('Por medio de pago', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          if (porMetodo.isEmpty) const Text('Sin ventas', style: TextStyle(color: Colors.grey))
          else for (final e in porMetodo.entries)
            ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.payments), title: Text(e.key),
              trailing: Text(dualUsd(e.value), style: const TextStyle(fontWeight: FontWeight.w600))),
          const Divider(height: 24),
          const Text('Productos mas vendidos', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          if (topProductos.isEmpty) const Text('Sin ventas', style: TextStyle(color: Colors.grey))
          else for (final e in topProductos.take(10))
            ListTile(dense: true, contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(radius: 15, backgroundColor: Colors.orange.shade50, child: Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
              title: Text(e.key)),
        ]);
        });
      }),
    );
  }
}


// ======================= RENTABILIDAD =======================
class RentabilidadScreen extends StatelessWidget {
  const RentabilidadScreen({super.key});
  static Widget _row(String label, double v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          const Spacer(),
          Text(dualUsd(v), style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
        ]));
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rentabilidad')),
      body: AnimatedBuilder(animation: store, builder: (context, _) {
        final rev = store.todayTotalUsd;
        final cost = store.todayCostUsd;
        final profit = rev - cost;
        final gastosHoy = store.todayGastosUsd;
        final neta = profit - gastosHoy;
        return ListView(padding: const EdgeInsets.all(16), children: [
          Card(color: Colors.green.shade50, child: Padding(padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Resumen de hoy', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              _row('Ventas', rev),
              _row('Costo estimado', cost),
              const Divider(),
              _row('Ganancia', profit, bold: true),
              _row('Gastos', gastosHoy),
              const Divider(),
              _row('Ganancia neta', neta, bold: true),
            ]))),
          const SizedBox(height: 6),
          const Text('El costo usa los precios de compra de los ingredientes. Los gastos son los registrados desde el ultimo cierre de caja.', style: TextStyle(fontSize: 11.5, color: Colors.grey)),
          const Divider(height: 24),
          const Text('Ganancia por producto', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          for (final p in store.products)
            Card(margin: const EdgeInsets.only(bottom: 6), child: ListTile(dense: true,
              leading: Text(p.emoji, style: const TextStyle(fontSize: 22)),
              title: Text(p.name, style: const TextStyle(fontSize: 13.5)),
              subtitle: Text('Precio ' + usd(store.toUsd(p.price, p.cur)) + '  -  Costo ' + usd(store.productCostUsd(p)), style: const TextStyle(fontSize: 11.5)),
              trailing: Text(usd(store.productProfitUsd(p)), style: TextStyle(fontWeight: FontWeight.bold, color: store.productProfitUsd(p) >= 0 ? Colors.green.shade700 : Colors.red)),
            )),
        ]);
      }),
    );
  }
}

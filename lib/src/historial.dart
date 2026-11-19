part of '../main.dart';

// Historial del dia, resumen imprimible y anulaciones.

// ======================= HISTORIAL DEL DIA =======================
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});
  void _editar(BuildContext context, {CatDef? c}) {
    final nombre = TextEditingController(text: c?.label ?? '');
    final emoji = TextEditingController(text: c?.emoji ?? '🍽️');
    showDialog<void>(context: context, builder: (dctx) => AlertDialog(
      title: Text(c == null ? 'Nueva categoria' : 'Editar categoria'),
      content: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 70, child: TextField(controller: emoji, textAlign: TextAlign.center, decoration: const InputDecoration(labelText: 'Icono'))),
        const SizedBox(width: 10),
        Expanded(child: TextField(controller: nombre, decoration: const InputDecoration(labelText: 'Nombre'))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancelar')),
        FilledButton(onPressed: () async {
          final n = nombre.text.trim();
          if (n.isEmpty) return;
          if (c == null) { await store.addCategory(n, emoji.text); } else { await store.updateCategory(c.id, n, emoji.text); }
          if (dctx.mounted) Navigator.pop(dctx);
        }, child: const Text('Guardar')),
      ],
    ));
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Categorias')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _editar(context), icon: const Icon(Icons.add), label: const Text('Nueva')),
      body: AnimatedBuilder(animation: store, builder: (context, _) {
        final cats = store.categories;
        return ListView(padding: const EdgeInsets.all(12), children: [
          const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Toca el lapiz para editar. Las que tienen candado son fijas del sistema y no se borran.', style: TextStyle(fontSize: 12, color: Colors.grey))),
          for (final c in cats)
            Card(child: ListTile(
              leading: Text(c.emoji, style: const TextStyle(fontSize: 26)),
              title: Text(c.label),
              subtitle: Text('${store.products.where((p) => p.cat == c.key).length} productos'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(icon: const Icon(Icons.edit), onPressed: () => _editar(context, c: c)),
                if (c.protected) const Padding(padding: EdgeInsets.only(right: 8), child: Icon(Icons.lock, size: 18, color: Colors.grey))
                else IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () {
                  showDialog<void>(context: context, builder: (dctx) => AlertDialog(
                    title: Text('Borrar "${c.label}"?'),
                    content: const Text('Los productos de esta categoria pasaran a "Otros". No se borra ningun producto.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancelar')),
                      FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () async { Navigator.pop(dctx); await store.deleteCategory(c); }, child: const Text('Borrar')),
                    ]));
                }),
              ]),
            )),
        ]);
      }),
    );
  }
}

class HistoryDaysScreen extends StatelessWidget {
  const HistoryDaysScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historial de dias')),
      body: AnimatedBuilder(animation: store, builder: (context, _) {
        final cierres = store.cashCloses;
        if (cierres.isEmpty) {
          return const Center(child: Padding(padding: EdgeInsets.all(24),
            child: Text('Aun no hay cierres de caja.', style: TextStyle(color: Colors.grey))));
        }
        return ListView(padding: const EdgeInsets.all(16), children: [
          for (final c in cierres)
            Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(
              leading: const Icon(Icons.event_available, color: kPrimary),
              title: Text(fecha(c.closedAt), style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${c.accountsCount} cuentas  ·  cerrado ${hhmm(c.closedAt)}'),
              trailing: Text(usd(c.totalUsd), style: const TextStyle(fontWeight: FontWeight.bold)),
              onTap: () => showDialog<void>(context: context, builder: (dctx) => AlertDialog(
                title: Text('Cierre del ${fecha(c.closedAt)}'),
                content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Total: ${dualUsd(c.totalUsd)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('${c.accountsCount} cuentas cobradas'),
                  if (c.gastosUsd > 0) ...[
                    Text('Gastos: ${dualUsd(c.gastosUsd)}'),
                    Text('Ventas menos gastos: ${dualUsd(c.totalUsd - c.gastosUsd)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                  const SizedBox(height: 10),
                  const Text('Por medio de pago:', style: TextStyle(fontWeight: FontWeight.w600)),
                  if (c.byMethod.isEmpty) const Text('-', style: TextStyle(color: Colors.grey))
                  else for (final e in c.byMethod.entries) Text('- ${e.key}: ${dualUsd(e.value)}'),
                  const SizedBox(height: 10),
                  const Text('Unidades por producto:', style: TextStyle(fontWeight: FontWeight.w600)),
                  if (c.units.isEmpty) const Text('-', style: TextStyle(color: Colors.grey))
                  else for (final e in (c.units.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))) Text('- ${e.value}  ${e.key}'),
                ])),
                actions: [TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cerrar'))],
              )),
            )),
        ]);
      }),
    );
  }
}

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historial de hoy')),
      body: AnimatedBuilder(animation: store, builder: (context, _) {
        final sales = store.todaySales;
        final units = store.unitsToday();
        final byMethod = store.byMethodToday();
        final sortedUnits = units.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        return ListView(padding: const EdgeInsets.all(16), children: [
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DaySummaryScreen())),
            icon: const Icon(Icons.print), label: const Text('Resumen para imprimir'))),
          const SizedBox(height: 12),
          Card(color: kPrimary.withOpacity(0.08), child: Padding(padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Ventas de hoy', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(dualUsd(store.todayTotalUsd), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              Text('${sales.length} cuentas cobradas'),
              if (store.currentUserRole == 'admin' && store.todayGastosUsd > 0) ...[
                const SizedBox(height: 4),
                Text('Gastos: ${dualUsd(store.todayGastosUsd)}'),
                Text('Ventas menos gastos: ${dualUsd(store.todayTotalUsd - store.todayGastosUsd)}', style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ]))),
          const SizedBox(height: 12),
          const Text('Por medio de pago', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          if (byMethod.isEmpty) const Text('Sin ventas aun', style: TextStyle(color: Colors.grey))
          else for (final e in byMethod.entries)
            ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.payments), title: Text(e.key), trailing: Text(dualUsd(e.value), style: const TextStyle(fontWeight: FontWeight.w600))),
          const Divider(height: 24),
          const Text('Unidades vendidas por producto', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          if (sortedUnits.isEmpty) const Text('Sin ventas aun', style: TextStyle(color: Colors.grey))
          else for (final e in sortedUnits)
            ListTile(dense: true, contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(radius: 15, backgroundColor: Colors.orange.shade50, child: Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
              title: Text(e.key)),
          const Divider(height: 24),
          const Text('Detalle de cuentas', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          if (sales.isEmpty) const Text('Sin ventas aun', style: TextStyle(color: Colors.grey))
          else for (final s in sales)
            Card(margin: const EdgeInsets.only(bottom: 6), child: ListTile(
              title: Text('${s.table != null ? 'Mesa ${s.table}' : 'Para llevar'}  ·  ${hhmm(s.at)}'),
              subtitle: Text(s.payments.map((p) => p.reference != null && p.reference!.isNotEmpty ? '${p.method} (ref ${p.reference})' : p.method).join(', ')),
              trailing: Text(usd(s.totalUsd), style: const TextStyle(fontWeight: FontWeight.bold)))),
        ]);
      }),
    );
  }
}

// ======================= RESUMEN DEL DIA (IMPRIMIBLE) =======================
class DaySummaryScreen extends StatelessWidget {
  const DaySummaryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Resumen del dia')),
      body: AnimatedBuilder(animation: store, builder: (context, _) {
        final sales = store.todaySales;
        final units = store.unitsToday().entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        final byMethod = store.byMethodToday();
        final total = store.todayTotalUsd;
        final now = DateTime.now();
        const mono = TextStyle(fontFamily: 'monospace', fontSize: 13.5, height: 1.5, color: Colors.black);
        return Center(child: SingleChildScrollView(child: Container(
          margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(18),
          constraints: const BoxConstraints(maxWidth: 380), color: Colors.white,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Center(child: Text(store.businessName.toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.bold))),
            const Center(child: Text('RESUMEN DEL DIA', style: TextStyle(fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.bold))),
            Center(child: Text('${two(now.day)}/${two(now.month)}/${now.year}  ${hhmm(now)}', style: mono)),
            const Text('==============================', style: mono),
            const Text('PRODUCTOS VENDIDOS', style: mono),
            if (units.isEmpty) const Text('  (sin ventas)', style: mono)
            else for (final e in units) Text('  ${e.value} x ${e.key}', style: mono),
            const Text('------------------------------', style: mono),
            const Text('INGRESOS POR METODO', style: mono),
            if (byMethod.isEmpty) const Text('  (sin ventas)', style: mono)
            else for (final e in byMethod.entries) Text('  ${e.key}: ${usd(e.value)}  |  ${ves(e.value * store.rate)}', style: mono),
            const Text('==============================', style: mono),
            Text('TOTAL: ${usd(total)}', style: mono.copyWith(fontWeight: FontWeight.bold, fontSize: 15)),
            Text('       ${ves(total * store.rate)}', style: mono.copyWith(fontWeight: FontWeight.bold)),
            if (store.currentUserRole == 'admin' && store.todayGastosUsd > 0) ...[
              Text('GASTOS: ${usd(store.todayGastosUsd)}  |  ${ves(store.todayGastosUsd * store.rate)}', style: mono),
              Text('NETO: ${usd(total - store.todayGastosUsd)}', style: mono.copyWith(fontWeight: FontWeight.bold)),
            ],
            Text('Cuentas cobradas: ${sales.length}', style: mono),
            Text('Tasa: ${ves(store.rate)} / \$', style: mono.copyWith(fontSize: 11)),
            const SizedBox(height: 14),
          ]),
        )));
      }),
    );
  }
}


// ======================= ANULACIONES =======================
class Cancellation {
  final int number;
  final int? table;
  final String? takeawayName;
  final String reason;
  final bool merchandiseUsed;
  final double valueUsd;
  final String byUser;
  final DateTime at;
  Cancellation(this.number, this.table, this.takeawayName, this.reason, this.merchandiseUsed, this.valueUsd, this.byUser, this.at);
  factory Cancellation.fromRow(Map<String, dynamic> r) => Cancellation(
        ((r['ticket_number'] ?? 0) as num).toInt(),
        r['table_number'] != null ? (r['table_number'] as num).toInt() : null,
        r['takeaway_name'] as String?,
        (r['reason'] ?? '') as String,
        (r['merchandise_used'] ?? false) as bool,
        ((r['value_usd'] ?? 0) as num).toDouble(),
        (r['by_user'] ?? '') as String,
        (DateTime.tryParse((r['at'] ?? '') as String)?.toLocal()) ?? DateTime.now(),
      );
}

class CancellationsScreen extends StatelessWidget {
  const CancellationsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Anulaciones / Perdidas')),
      body: AnimatedBuilder(animation: store, builder: (context, _) {
        final list = store.cancellations;
        final now = DateTime.now();
        bool sameDay(DateTime d) => d.year == now.year && d.month == now.month && d.day == now.day;
        final totalPerdida = list.where((c) => sameDay(c.at)).fold(0.0, (v, c) => v + c.valueUsd);
        return ListView(padding: const EdgeInsets.all(16), children: [
          Card(color: Colors.red.shade50, child: Padding(padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Perdida de hoy (mercancia usada)', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(dualUsd(totalPerdida), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
            ]))),
          const SizedBox(height: 12),
          if (list.isEmpty) const Text('Sin anulaciones registradas', style: TextStyle(color: Colors.grey))
          else for (final c in list)
            Card(margin: const EdgeInsets.only(bottom: 6), child: ListTile(
              leading: Icon(c.merchandiseUsed ? Icons.money_off : Icons.cancel, color: c.merchandiseUsed ? Colors.red : Colors.grey),
              title: Text('Comanda #' + c.number.toString().padLeft(6, '0') + ' - ' + (c.table != null ? 'Mesa ' + c.table.toString() : (c.takeawayName ?? 'Llevar'))),
              subtitle: Text((c.reason.isEmpty ? 'Sin motivo' : c.reason) + '\n' + hhmm(c.at) + ' - ' + c.byUser + (c.merchandiseUsed ? ' - mercancia usada' : ' - sin usar')),
              isThreeLine: true,
              trailing: c.merchandiseUsed ? Text('-' + usd(c.valueUsd), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)) : null,
            )),
        ]);
      }),
    );
  }
}

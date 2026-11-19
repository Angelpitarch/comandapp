part of '../main.dart';

// Mesas, detalle de mesa, historial de comandas de la mesa y pedidos para llevar.

// ======================= SELECTOR DE PERFIL =======================
// ======================= MESAS =======================
class TablesScreen extends StatelessWidget {
  const TablesScreen({super.key});

  void _nuevoLlevar(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog<void>(context: context, builder: (dctx) => AlertDialog(
      title: const Text('Nuevo pedido para llevar'),
      content: TextField(controller: ctrl, autofocus: true,
        decoration: const InputDecoration(labelText: 'Nombre del cliente')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancelar')),
        FilledButton(onPressed: () async {
          final name = ctrl.text.trim().isEmpty ? 'Cliente' : ctrl.text.trim();
          Navigator.pop(dctx);
          final id = await store.createTakeaway(name);
          if (id != null && context.mounted) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => OrderScreen(cartKey: 'llevar-$id', table: null, takeawayId: id, takeawayName: name)));
          }
        }, child: const Text('Crear')),
      ],
    ));
  }

  Widget _takeawaySection(BuildContext context) {
    return SizedBox(
      height: 118,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.fromLTRB(14, 8, 14, 4), child: Text('Para llevar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
        Expanded(child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10), children: [
          for (final t in store.takeaways) _takeawayCard(context, t),
        ])),
      ]),
    );
  }

  Widget _takeawayCard(BuildContext context, Takeaway t, {double ancho = 150}) {
    final total = store.takeawayTotalUsd(t.id);
    final pagada = t.status == 'pagada';
    final c = pagada ? const Color(0xFF8D6E63) : const Color(0xFF00897B);
    return SizedBox(width: ancho, child: Card(child: InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TakeawayDetailScreen(id: t.id, name: t.name))),
      child: Container(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: c, width: 5))),
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Icon(Icons.takeout_dining, size: 16), const SizedBox(width: 4),
            Expanded(child: Text(t.name.isEmpty ? 'Cliente' : t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)))]),
          const Spacer(),
          Text(pagada ? 'PAGADO' : 'Abierto', style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 11)),
          if (total > 0) Text('Cuenta: ${usd(total)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          if (store.kitchenStateTakeaway(t.id) == 'listo') Text('🔔 LISTO', style: TextStyle(fontSize: 10.5, color: Colors.green.shade700, fontWeight: FontWeight.bold))
          else if (store.kitchenStateTakeaway(t.id) == 'cocina') Text('En cocina...', style: TextStyle(fontSize: 10.5, color: Colors.blue.shade700)),
        ]),
      ),
    )));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: barraMarca(context, 'Mesas', actions: [
        IconButton(tooltip: 'Cambiar mi PIN', icon: const Icon(Icons.lock_reset, color: Colors.white),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChangePinScreen()))),
        IconButton(tooltip: 'Salir', icon: const Icon(Icons.logout, color: Colors.white), onPressed: () => _logout(context)),
      ]),
      floatingActionButton: esAncho(context) ? null : FloatingActionButton.extended(
        onPressed: () => _nuevoLlevar(context),
        icon: const Icon(Icons.takeout_dining), label: const Text('Para llevar'),
      ),
      body: AnimatedBuilder(animation: store, builder: (context, _) {
        if (store.tables.isEmpty) return const Center(child: CircularProgressIndicator());
        // Computadora o tableta: mesas a la izquierda y pedidos para llevar en un panel fijo a la derecha.
        if (esAncho(context)) {
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: Column(children: [
              lowStockWaiterBanner(),
              _resumenMesas(),
              Expanded(child: _gridMesas(context)),
            ])),
            _panelLlevar(context),
          ]);
        }
        return Column(children: [
          lowStockWaiterBanner(),
          if (store.takeaways.isNotEmpty) _takeawaySection(context),
          Expanded(child: _gridMesas(context)),
        ]);
      }),
    );
  }

  // Conteo rapido arriba de las mesas (solo en pantalla ancha).
  Widget _resumenMesas() {
    final estados = [for (final t in store.tables) store.tableStatus(t.number)];
    final libres = estados.where((e) => e == 'disponible').length;
    final listos = estados.where((e) => e == 'listo').length;
    Widget dato(Color c, String txt) => Padding(padding: const EdgeInsets.only(right: 18), child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 7),
          Text(txt, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kInk)),
        ]));
    return Padding(padding: const EdgeInsets.fromLTRB(20, 18, 20, 0), child: Row(children: [
      const Text('Salon', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: kInk)),
      const SizedBox(width: 24),
      dato(statusColor('disponible'), libres == 1 ? '1 libre' : '$libres libres'),
      dato(statusColor('ocupada'), estados.length - libres == 1 ? '1 ocupada' : '${estados.length - libres} ocupadas'),
      if (listos > 0) dato(statusColor('listo'), '$listos con pedido listo'),
    ]));
  }

  // Panel fijo de pedidos para llevar (pantalla ancha).
  Widget _panelLlevar(BuildContext context) => Container(
        width: 320,
        decoration: const BoxDecoration(color: Colors.white, border: Border(left: BorderSide(color: kLine))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.fromLTRB(18, 18, 18, 10), child: Row(children: [
            const Icon(Icons.takeout_dining_outlined, color: kPrimary),
            const SizedBox(width: 10),
            const Expanded(child: Text('Para llevar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kInk))),
            Builder(builder: (_) { final n = store.takeaways.where((t) => t.status != 'pagada').length;
              return Text(n == 1 ? '1 abierto' : '$n abiertos', style: const TextStyle(color: kMuted, fontSize: 13)); }),
          ])),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: kAmber, foregroundColor: kInk),
            onPressed: () => _nuevoLlevar(context), icon: const Icon(Icons.add), label: const Text('Nuevo pedido para llevar'))),
          const SizedBox(height: 12),
          const Divider(height: 1),
          Expanded(child: store.takeaways.isEmpty
              ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Sin pedidos para llevar', style: TextStyle(color: kMuted))))
              : ListView(padding: const EdgeInsets.all(12), children: [
                  for (final t in store.takeaways) Padding(padding: const EdgeInsets.only(bottom: 8),
                      child: SizedBox(height: 104, child: _takeawayCard(context, t, ancho: double.infinity))),
                ])),
        ]),
      );

  Widget _gridMesas(BuildContext context) => LayoutBuilder(builder: (context, cns) {
          final cols = (cns.maxWidth / 180).floor().clamp(2, 6).toInt();
          return GridView.builder(
            padding: const EdgeInsets.all(14),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.0),
            itemCount: store.tables.length,
            itemBuilder: (context, i) {
              final t = store.tables[i];
              final s = store.tableStatus(t.number);
              final total = store.accountTotalUsd(t.number);
              final c = statusColor(s);
              return Card(child: InkWell(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TableDetailScreen(table: t.number))),
                child: Container(
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: c, width: 6))),
                  padding: const EdgeInsets.all(10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text('Mesa ${t.number}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Icon(Icons.event_seat, size: 15, color: Colors.grey[600]),
                      Text(' ${t.cap}', style: TextStyle(color: Colors.grey[600])),
                    ]),
                    const SizedBox(height: 6),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: c.withOpacity(0.18), borderRadius: BorderRadius.circular(20)),
                        child: Text(statusLabel(s), style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 11.5))),
                    const Spacer(),
                    if (s != 'disponible' && t.waiter != null) Text(t.waiter!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5)),
                    if (total > 0) Text('Cuenta: ${usd(total)}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                    if (store.kitchenStateTable(t.number) == 'listo') Text('🔔 LISTO', style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.bold))
                    else if (store.kitchenStateTable(t.number) == 'cocina') Text('En cocina...', style: TextStyle(fontSize: 11, color: Colors.blue.shade700)),
                  ]),
                ),
              ));
            },
          );
        });
}

// ======================= DETALLE DE MESA =======================
class TableDetailScreen extends StatelessWidget {
  final int table;
  const TableDetailScreen({super.key, required this.table});

  void _cambiarMesa(BuildContext context) {
    final destinos = store.tables.where((t) => t.number != table && store.tableStatus(t.number) == 'disponible').toList();
    showDialog<void>(context: context, builder: (dctx) => AlertDialog(
      title: const Text('Cambiar de mesa'),
      content: destinos.isEmpty
          ? const Text('No hay mesas disponibles.')
          : SizedBox(width: double.maxFinite, child: ListView(shrinkWrap: true, children: [
              for (final t in destinos)
                ListTile(leading: const Icon(Icons.table_bar), title: Text('Mesa ${t.number}'),
                  onTap: () async {
                    Navigator.pop(dctx);
                    await store.transferTable(table, t.number);
                    if (context.mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Comanda movida a Mesa ${t.number}'))); }
                  }),
            ])),
      actions: [TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancelar'))],
    ));
  }

  void _paraLlevar(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog<void>(context: context, builder: (dctx) => AlertDialog(
      title: const Text('Pedido para llevar'),
      content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: 'Nombre del cliente')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancelar')),
        FilledButton(onPressed: () async {
          final nm = ctrl.text.trim().isEmpty ? 'Cliente' : ctrl.text.trim();
          Navigator.pop(dctx);
          final id = await store.createTakeaway(nm);
          if (id != null && context.mounted) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => OrderScreen(cartKey: 'llevar-$id', table: null, takeawayId: id, takeawayName: nm)));
          }
        }, child: const Text('Crear')),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Mesa $table'), actions: [
        IconButton(tooltip: 'Historial de comandas', icon: const Icon(Icons.history),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TableTicketsScreen(table: table)))),
        IconButton(tooltip: 'Pedido para llevar', icon: const Icon(Icons.takeout_dining), onPressed: () => _paraLlevar(context)),
        IconButton(tooltip: 'Cambiar de mesa', icon: const Icon(Icons.swap_horiz), onPressed: () => _cambiarMesa(context)),
      ]),
      body: AnimatedBuilder(animation: store, builder: (context, _) {
        final acc = store.account(table);
        final total = store.accountTotalUsd(table);
        return Column(children: [
          Expanded(child: ListView(padding: const EdgeInsets.all(14), children: [
            const Text('Lo pedido en esta mesa', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            if (acc.isEmpty)
              const Padding(padding: EdgeInsets.all(12), child: Text('Aun no hay productos. Toca "Agregar".', style: TextStyle(color: Colors.grey)))
            else
              for (final a in acc)
                Card(margin: const EdgeInsets.only(bottom: 6), child: ListTile(dense: true,
                  leading: CircleAvatar(radius: 14, backgroundColor: Colors.orange.shade50, child: Text('${a.qty}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                  title: Text(a.name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  subtitle: Text([if (a.size != null) a.size!, ...a.extras.map((e) => '+$e'), ...a.quita.map((q) => 'Sin $q'), if (a.note != null) 'Nota: ${a.note}'].join(' · '), style: const TextStyle(fontSize: 11)),
                  trailing: Text(usd(a.lineUsd), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)))),
          ])),
          Material(elevation: 8, child: SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [const Text('Total mesa', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), const Spacer(), Text(dualUsd(total), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))]),
              const SizedBox(height: 10),
              if (store.tableStatus(table) == 'pago_espera') ...[
                const Text('Pagado - el cliente esta esperando su pedido.', style: TextStyle(fontSize: 12.5, color: Color(0xFF6D4C41))),
                const SizedBox(height: 8),
                SizedBox(width: double.infinity, height: 50, child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF6C00)),
                  onPressed: () async { await store.markDelivered(table); await store.setTableStatus(table, 'pago_servido'); },
                  icon: const Icon(Icons.room_service), label: const Text('Marcar como entregado'))),
              ] else if (store.tableStatus(table) == 'pago_servido') ...[
                const Text('Pagado y servido. Libera la mesa cuando el cliente se retire.', style: TextStyle(fontSize: 12.5, color: Color(0xFF6D4C41))),
                const SizedBox(height: 8),
                SizedBox(width: double.infinity, height: 50, child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF66BB6A)),
                  onPressed: () async { await store.freeTable(table); if (context.mounted) Navigator.pop(context); },
                  icon: const Icon(Icons.check_circle), label: const Text('Liberar mesa'))),
              ] else ...[
                Row(children: [
                  Expanded(child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderScreen(cartKey: 'mesa-$table', table: table))),
                    icon: const Icon(Icons.add), label: const Text('Agregar'))),
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton.icon(
                    onPressed: acc.isEmpty ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReceiptScreen(table: table))),
                    icon: const Icon(Icons.receipt_long), label: const Text('Comprobante'))),
                ]),
                const SizedBox(height: 8),
                SizedBox(width: double.infinity, height: 50, child: FilledButton.icon(
                  onPressed: acc.isEmpty ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentScreen(table: table))),
                  icon: const Icon(Icons.point_of_sale), label: const Text('Cobrar'))),
              ],
            ]))))
        ]);
      }),
    );
  }
}

Color _kColor(String s) => switch (s) {
      'nueva' => const Color(0xFF42A5F5), 'preparando' => const Color(0xFFFFA726),
      'lista' => const Color(0xFF26C6DA), 'entregada' => const Color(0xFF66BB6A), _ => Colors.grey };
IconData _kIcon(String s) => switch (s) {
      'nueva' => Icons.fiber_new, 'preparando' => Icons.outdoor_grill,
      'lista' => Icons.room_service, 'entregada' => Icons.check_circle, _ => Icons.cancel };
String _kLabel(String s) => switch (s) {
      'nueva' => 'Recibida', 'preparando' => 'Preparando', 'lista' => 'Lista', 'entregada' => 'Entregada', _ => s };

// ======================= DETALLE PARA LLEVAR =======================
class TakeawayDetailScreen extends StatelessWidget {
  final String id;
  final String name;
  const TakeawayDetailScreen({super.key, required this.id, required this.name});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Llevar - $name')),
      body: AnimatedBuilder(animation: store, builder: (context, _) {
        final acc = store.takeawayAccount(id);
        final tk = store.ticketsOfTakeaway(id);
        final total = store.takeawayTotalUsd(id);
        final st = store.takeaways.where((t) => t.id == id).map((t) => t.status).toList();
        final isPaid = st.isNotEmpty && st.first == 'pagada';
        return Column(children: [
          Expanded(child: ListView(padding: const EdgeInsets.all(14), children: [
            if (tk.isNotEmpty) ...[
              const Text('Estado en cocina', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              for (final k in tk)
                Card(margin: const EdgeInsets.only(bottom: 6), child: ListTile(dense: true,
                  leading: CircleAvatar(backgroundColor: _kColor(k.status).withOpacity(0.18), child: Icon(_kIcon(k.status), color: _kColor(k.status), size: 20)),
                  title: Text('Comanda #' + k.number.toString().padLeft(6, '0')),
                  subtitle: Text(k.lines.length.toString() + ' productos - enviada ' + hhmm(k.sentAt)),
                  trailing: Text(_kLabel(k.status), style: TextStyle(color: _kColor(k.status), fontWeight: FontWeight.w600)))),
              const SizedBox(height: 12),
            ],
            const Text('Lo pedido', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            if (acc.isEmpty)
              const Padding(padding: EdgeInsets.all(12), child: Text('Aun no hay productos. Toca "Agregar".', style: TextStyle(color: Colors.grey)))
            else
              for (final a in acc)
                Card(margin: const EdgeInsets.only(bottom: 6), child: ListTile(dense: true,
                  leading: CircleAvatar(radius: 14, backgroundColor: Colors.orange.shade50, child: Text(a.qty.toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                  title: Text(a.name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  subtitle: Text([if (a.size != null) a.size!, ...a.extras.map((e) => '+' + e), ...a.quita.map((q) => 'Sin ' + q), if (a.note != null) 'Nota: ' + a.note!].join(' - '), style: const TextStyle(fontSize: 11)),
                  trailing: Text(usd(a.lineUsd), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)))),
          ])),
          Material(elevation: 8, child: SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [const Text('Total', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), const Spacer(), Text(dualUsd(total), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))]),
              const SizedBox(height: 10),
              if (isPaid) ...[
                const Text('PAGADO. Cierra la casilla cuando entregues el pedido.', style: TextStyle(fontSize: 12.5, color: Color(0xFF6D4C41))),
                const SizedBox(height: 8),
                SizedBox(width: double.infinity, height: 50, child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF66BB6A)),
                  onPressed: () async { await store.markDeliveredTakeaway(id); await store.closeTakeaway(id); if (context.mounted) Navigator.pop(context); },
                  icon: const Icon(Icons.check_circle), label: const Text('Entregado y cerrar'))),
              ] else ...[
                Row(children: [
                  Expanded(child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderScreen(cartKey: 'llevar-' + id, table: null, takeawayId: id, takeawayName: name))),
                    icon: const Icon(Icons.add), label: const Text('Agregar'))),
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton.icon(
                    onPressed: () async { await store.closeTakeaway(id); if (context.mounted) Navigator.pop(context); },
                    icon: const Icon(Icons.delete_outline), label: const Text('Cancelar'))),
                ]),
                const SizedBox(height: 8),
                SizedBox(width: double.infinity, height: 50, child: FilledButton.icon(
                  onPressed: acc.isEmpty ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentScreen(takeawayId: id))),
                  icon: const Icon(Icons.point_of_sale), label: const Text('Cobrar'))),
              ],
            ]))))
        ]);
      }),
    );
  }
}


// ======================= AVISO DE DISPONIBILIDAD (mesero) =======================
Widget lowStockWaiterBanner() {
  final low = store.lowAvailabilityProducts();
  if (low.isEmpty) return const SizedBox.shrink();
  return Container(
    width: double.infinity,
    color: const Color(0xFFFFF3E0),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [
        Icon(Icons.warning_amber, color: Color(0xFFEF6C00), size: 18),
        SizedBox(width: 6),
        Expanded(child: Text('Por agotarse - ofrece alternativas o sugiere cambiar un ingrediente',
            style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFE65100), fontSize: 12.5))),
      ]),
      const SizedBox(height: 4),
      for (final p in low.take(6))
        Text('- ' + p.name + ': ' + (store.maxMakeable(p) == 0 ? 'AGOTADO' : 'quedan ~' + store.maxMakeable(p).toString()),
            style: TextStyle(fontSize: 12, color: store.maxMakeable(p) == 0 ? Colors.red : const Color(0xFFBF360C))),
      if (low.length > 6) Text('... y ' + (low.length - 6).toString() + ' mas', style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
    ]),
  );
}


// ======================= HISTORIAL DE COMANDAS DE LA MESA =======================
class TableTicketsScreen extends StatelessWidget {
  final int table;
  const TableTicketsScreen({super.key, required this.table});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Comandas de la mesa $table')),
      body: AnimatedBuilder(animation: store, builder: (context, _) {
        final list = store.tickets.where((t) => t.table == table).toList();
        if (list.isEmpty) {
          return const Center(child: Padding(padding: EdgeInsets.all(24),
            child: Text('Esta mesa aun no tiene comandas.', style: TextStyle(color: Colors.grey))));
        }
        return ListView(padding: const EdgeInsets.all(14), children: [
          for (final k in list)
            Card(margin: const EdgeInsets.only(bottom: 8), child: Padding(padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  CircleAvatar(radius: 14, backgroundColor: _kColor(k.status).withOpacity(0.18),
                    child: Icon(_kIcon(k.status), color: _kColor(k.status), size: 16)),
                  const SizedBox(width: 8),
                  Text('#' + k.number.toString().padLeft(6, '0'), style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (k.adicion) Container(margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), color: Colors.amber,
                    child: const Text('ADICION', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                  const Spacer(),
                  Text(_kLabel(k.status), style: TextStyle(color: _kColor(k.status), fontWeight: FontWeight.w600, fontSize: 12)),
                ]),
                const SizedBox(height: 4),
                Text('Enviada ' + hhmm(k.sentAt) + '  -  ' + k.waiter, style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
                const Divider(height: 14),
                for (final l in k.lines)
                  Padding(padding: const EdgeInsets.only(bottom: 2),
                    child: Text(l.qty.toString() + '  ' + l.name + (l.size != null ? ' (' + l.size! + ')' : ''),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                if (k.note != null) Padding(padding: const EdgeInsets.only(top: 4),
                  child: Text('Obs: ' + k.note!, style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic))),
              ]))),
        ]);
      }),
    );
  }
}

part of '../main.dart';

// Cobro y comprobante.

// ======================= COBRO / PAGO =======================
class _Line {
  final String name;
  final int qty;
  final double lineUsd;
  _Line(this.name, this.qty, this.lineUsd);
}

class PaymentScreen extends StatefulWidget {
  final int? table;
  final String? takeawayId;
  final String? cartKey;
  const PaymentScreen({super.key, this.table, this.takeawayId, this.cartKey});
  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}
class _PaymentScreenState extends State<PaymentScreen> {
  final String _ventaId = nuevoId(); // mismo id en cada reintento: la venta nunca se guarda dos veces
  int _mode = 0;
  int _persons = 2;
  bool _paying = false;
  final Map<int, int> _assign = {};
  final Map<int, String> _method = {};
  final Map<int, TextEditingController> _refCtrls = {};
  TextEditingController _refFor(int i) => _refCtrls.putIfAbsent(i, () => TextEditingController());
  @override
  void dispose() { for (final c in _refCtrls.values) { c.dispose(); } super.dispose(); }

  List<_Line> get _lines => widget.table != null
      ? store.account(widget.table!).map((a) => _Line(a.name, a.qty, a.lineUsd)).toList()
      : widget.takeawayId != null
          ? store.takeawayAccount(widget.takeawayId!).map((a) => _Line(a.name, a.qty, a.lineUsd)).toList()
          : store.cart(widget.cartKey ?? '').map((it) => _Line(it.p.name, it.qty, store.lineUsd(it))).toList();
  double get _totalUsd => _lines.fold(0.0, (s, l) => s + l.lineUsd);

  List<double> _parts() {
    final lines = _lines;
    if (_mode == 0) return [_totalUsd];
    if (_mode == 1) return List.filled(_persons, _totalUsd / _persons);
    final res = List.filled(_persons, 0.0);
    for (var i = 0; i < lines.length; i++) {
      final person = (_assign[i] ?? 0).clamp(0, _persons - 1).toInt();
      res[person] += lines[i].lineUsd;
    }
    return res;
  }

  Future<void> _confirm() async {
    if (_paying) return;
    final parts = _parts();
    final payments = <Payment>[];
    for (var i = 0; i < parts.length; i++) {
      if (parts[i] <= 0) continue;
      payments.add(Payment(_method[i] ?? store.methods.first, parts[i], reference: _refFor(i).text.trim().isEmpty ? null : _refFor(i).text.trim()));
    }
    if (payments.isEmpty) return;
    setState(() => _paying = true);
    final nav = Navigator.of(context);
    final ok = await store.pay(payments, table: widget.table, takeawayId: widget.takeawayId, cartKey: widget.cartKey, ventaId: _ventaId);
    if (!mounted) return;
    setState(() => _paying = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(store.errorCobro ?? 'No se pudo cobrar. Revisa la conexion.')));
      return;
    }
    if (widget.table != null) {
      await showDialog<void>(context: context, barrierDismissible: false, builder: (dctx) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
        title: Text('Mesa ${widget.table}: cuenta pagada'),
        content: const Text('El cliente ya recibio su pedido, o esta esperando?'),
        actions: [
          OutlinedButton(onPressed: () async { await store.setTableStatus(widget.table!, 'pago_espera'); if (dctx.mounted) Navigator.pop(dctx); }, child: const Text('Esta esperando')),
          FilledButton(onPressed: () async { await store.markDelivered(widget.table!); await store.setTableStatus(widget.table!, 'pago_servido'); if (dctx.mounted) Navigator.pop(dctx); }, child: const Text('Ya se le entrego')),
        ]));
    } else {
      await showDialog<void>(context: context, builder: (dctx) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
        title: const Text('Cobro registrado'),
        content: const Text('Pedido para llevar cobrado.'),
        actions: [FilledButton(onPressed: () => Navigator.pop(dctx), child: const Text('Listo'))]));
    }
    if (!mounted) return;
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.table != null ? 'Cobrar - Mesa ${widget.table}' : 'Cobrar - Para llevar')),
      body: AnimatedBuilder(animation: store, builder: (context, _) {
        final lines = _lines;
        final parts = _parts();
        return Column(children: [
          Expanded(child: ListView(padding: const EdgeInsets.all(14), children: [
            Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
              const Text('Total a cobrar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(), Text(dualUsd(_totalUsd), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ]))),
            const SizedBox(height: 6),
            const Text('Dividir la cuenta', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            SegmentedButton<int>(
              segments: const [ButtonSegment(value: 0, label: Text('Completa')), ButtonSegment(value: 1, label: Text('Iguales')), ButtonSegment(value: 2, label: Text('Por productos'))],
              selected: {_mode}, onSelectionChanged: (s) => setState(() => _mode = s.first)),
            if (_mode != 0) ...[
              const SizedBox(height: 10),
              Row(children: [
                const Text('Personas:', style: TextStyle(fontWeight: FontWeight.w600)), const SizedBox(width: 8),
                IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: _persons > 2 ? () => setState(() => _persons--) : null),
                Text('$_persons', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: _persons < 10 ? () => setState(() => _persons++) : null),
              ]),
            ],
            if (_mode == 2) ...[
              const Divider(),
              const Text('Asigna cada producto a una persona', style: TextStyle(fontWeight: FontWeight.w600)),
              for (var i = 0; i < lines.length; i++)
                ListTile(dense: true, contentPadding: EdgeInsets.zero,
                  title: Text('${lines[i].qty}  ${lines[i].name}', style: const TextStyle(fontSize: 13)),
                  subtitle: Text(usd(lines[i].lineUsd), style: const TextStyle(fontSize: 11.5)),
                  trailing: DropdownButton<int>(
                    value: (_assign[i] ?? 0).clamp(0, _persons - 1).toInt(),
                    items: [for (var p = 0; p < _persons; p++) DropdownMenuItem(value: p, child: Text('Persona ${p + 1}'))],
                    onChanged: (v) => setState(() => _assign[i] = v ?? 0))),
            ],
            const Divider(height: 24),
            const Text('Pago', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            for (var i = 0; i < parts.length; i++)
              Card(margin: const EdgeInsets.only(bottom: 8), child: Padding(padding: const EdgeInsets.all(10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Text(parts.length == 1 ? 'Monto' : 'Persona ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w600)), const Spacer(), Text(dualUsd(parts[i]), style: const TextStyle(fontWeight: FontWeight.bold))]),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, children: [for (final m in store.methods) ChoiceChip(label: Text(m, style: const TextStyle(fontSize: 12)), selected: (_method[i] ?? store.methods.first) == m, onSelected: (_) => setState(() => _method[i] = m))]),
                  const SizedBox(height: 8),
                  TextField(controller: _refFor(i), style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(isDense: true, labelText: 'Referencia bancaria (opcional)', prefixIcon: Icon(Icons.confirmation_number_outlined))),
                ]))),
          ])),
          SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(12),
            child: SizedBox(width: double.infinity, height: 52, child: FilledButton.icon(
              onPressed: (lines.isEmpty || _paying) ? null : _confirm,
              icon: _paying ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check),
              label: Text(_paying ? 'Procesando...' : 'Confirmar cobro'))))),
        ]);
      }),
    );
  }
}

// ======================= COMPROBANTE =======================
class ReceiptScreen extends StatelessWidget {
  final int table;
  const ReceiptScreen({super.key, required this.table});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Comprobante')),
      body: AnimatedBuilder(animation: store, builder: (context, _) {
        final acc = store.account(table);
        final total = store.accountTotalUsd(table);
        final now = DateTime.now();
        final t = store.tables.where((e) => e.number == table).toList();
        final waiter = t.isNotEmpty ? (t.first.waiter ?? '-') : '-';
        const mono = TextStyle(fontFamily: 'monospace', fontSize: 13.5, height: 1.4, color: Colors.black);
        return Center(child: SingleChildScrollView(child: Container(
          margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(18),
          constraints: const BoxConstraints(maxWidth: 360), color: Colors.white,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Center(child: Text(store.businessName.toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'monospace', fontSize: 15, fontWeight: FontWeight.bold))),
            const Center(child: Text('PRECUENTA (no fiscal)', style: mono)),
            const Text('------------------------------', style: mono),
            Text('MESA $table', style: mono.copyWith(fontWeight: FontWeight.bold)),
            Text('${two(now.day)}/${two(now.month)}/${now.year}  ${hhmm(now)}', style: mono),
            Text('MESERO: $waiter', style: mono),
            const Text('------------------------------', style: mono),
            for (final a in acc) ...[
              Text('${a.qty} x ${a.name}', style: mono.copyWith(fontWeight: FontWeight.w600)),
              if (a.size != null || a.extras.isNotEmpty || a.quita.isNotEmpty)
                Text('   ${[if (a.size != null) a.size!, ...a.extras.map((e) => '+$e'), ...a.quita.map((q) => 'sin $q')].join(', ')}', style: mono.copyWith(fontSize: 12)),
              Text('   ${usd(a.lineUsd)}   ${ves(a.lineUsd * store.rate)}', style: mono),
            ],
            const Text('------------------------------', style: mono),
            Text('TOTAL: ${usd(total)}', style: mono.copyWith(fontWeight: FontWeight.bold, fontSize: 15)),
            Text('       ${ves(total * store.rate)}', style: mono.copyWith(fontWeight: FontWeight.bold)),
            Text('Tasa: ${ves(store.rate)} / \$', style: mono.copyWith(fontSize: 11)),
            const SizedBox(height: 14),
          ]),
        )));
      }),
    );
  }
}

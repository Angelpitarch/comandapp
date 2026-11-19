part of '../main.dart';

// Gastos.

// ======================= GASTOS =======================
const Map<String, String> kGastoCats = {
  'ingredientes': 'Ingredientes / compras',
  'servicios': 'Servicios (luz, agua, gas)',
  'sueldos': 'Sueldos',
  'alquiler': 'Alquiler',
  'transporte': 'Transporte',
  'otros': 'Otros',
};

class Gasto {
  String id;
  String concept;
  String category;
  double amountUsd;
  String paymentMethod;
  String note;
  String byUser;
  DateTime at;
  Gasto({required this.id, this.concept = '', this.category = 'otros', this.amountUsd = 0,
      this.paymentMethod = '', this.note = '', this.byUser = '', DateTime? at}) : at = at ?? DateTime.now();
  factory Gasto.fromRow(Map<String, dynamic> r) => Gasto(
        id: r['id'] as String,
        concept: (r['concept'] ?? '') as String,
        category: (r['category'] ?? 'otros') as String,
        amountUsd: ((r['amount_usd'] ?? 0) as num).toDouble(),
        paymentMethod: (r['payment_method'] ?? '') as String,
        note: (r['note'] ?? '') as String,
        byUser: (r['by_user'] ?? '') as String,
        at: (DateTime.tryParse((r['at'] ?? '') as String)?.toLocal()) ?? DateTime.now(),
      );
  Map<String, dynamic> toRow() => <String, dynamic>{
        'concept': concept, 'category': category, 'amount_usd': amountUsd,
        'payment_method': paymentMethod, 'note': note,
      };
}

class GastosScreen extends StatefulWidget {
  const GastosScreen({super.key});
  @override
  State<GastosScreen> createState() => _GastosScreenState();
}
class _GastosScreenState extends State<GastosScreen> {
  bool _soloHoy = true;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gastos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GastoForm())),
        icon: const Icon(Icons.add), label: const Text('Nuevo gasto')),
      body: AnimatedBuilder(animation: store, builder: (context, _) {
        final list = _soloHoy ? store.todayGastos : store.gastos;
        final total = list.fold<double>(0, (s, g) => s + g.amountUsd);
        final porCat = <String, double>{};
        for (final g in list) { porCat[g.category] = (porCat[g.category] ?? 0) + g.amountUsd; }
        return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
          SegmentedButton<bool>(
            segments: const [ButtonSegment(value: true, label: Text('Desde el cierre')), ButtonSegment(value: false, label: Text('Todos'))],
            selected: {_soloHoy},
            onSelectionChanged: (v) => setState(() => _soloHoy = v.first)),
          const SizedBox(height: 12),
          Card(color: Colors.red.shade50, child: Padding(padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_soloHoy ? 'Gastos desde el ultimo cierre de caja' : 'Todos los gastos', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(dualUsd(total), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              Text('${list.length} gastos', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              if (porCat.isNotEmpty) const Divider(),
              for (final e in porCat.entries)
                Padding(padding: const EdgeInsets.symmetric(vertical: 1), child: Row(children: [
                  Text(kGastoCats[e.key] ?? e.key, style: const TextStyle(fontSize: 12.5)),
                  const Spacer(),
                  Text(usd(e.value), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                ])),
            ]))),
          const SizedBox(height: 8),
          if (list.isEmpty)
            const Padding(padding: EdgeInsets.all(24),
              child: Text('Sin gastos registrados.\nToca "Nuevo gasto" para agregar.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))),
          for (final g in list)
            Card(margin: const EdgeInsets.only(bottom: 6), child: ListTile(
              title: Text(g.concept.isEmpty ? '(sin concepto)' : g.concept),
              subtitle: Text([kGastoCats[g.category] ?? g.category, if (g.paymentMethod.isNotEmpty) g.paymentMethod,
                '${fecha(g.at)} ${hhmm(g.at)}', if (g.byUser.isNotEmpty) g.byUser].join(' · '), style: const TextStyle(fontSize: 11.5)),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(usd(g.amountUsd), style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(ves(g.amountUsd * store.rate), style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ]),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GastoForm(existing: g))),
            )),
        ]);
      }),
    );
  }
}

class GastoForm extends StatefulWidget {
  final Gasto? existing;
  const GastoForm({super.key, this.existing});
  @override
  State<GastoForm> createState() => _GastoFormState();
}
class _GastoFormState extends State<GastoForm> {
  late TextEditingController _concept, _amount, _note;
  String _cat = 'otros';
  String _method = '';
  Currency _cur = Currency.usd;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    final g = widget.existing;
    _concept = TextEditingController(text: g?.concept ?? '');
    _amount = TextEditingController(text: g != null && g.amountUsd > 0 ? fmtQty(g.amountUsd) : '');
    _note = TextEditingController(text: g?.note ?? '');
    _cat = kGastoCats.containsKey(g?.category) ? g!.category : 'otros';
    _method = g?.paymentMethod ?? '';
  }
  @override
  void dispose() {
    _concept.dispose(); _amount.dispose(); _note.dispose();
    super.dispose();
  }
  double get _typed => double.tryParse(_amount.text.replaceAll(',', '.')) ?? 0;
  double get _asUsd => _cur == Currency.usd ? _typed : (store.rate > 0 ? _typed / store.rate : 0);
  Future<void> _save() async {
    if (_saving) return;
    if (_concept.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Escribe el concepto'))); return; }
    if (_asUsd <= 0) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Escribe un monto mayor a cero'))); return; }
    setState(() => _saving = true);
    final g = widget.existing ?? Gasto(id: '');
    g.concept = _concept.text.trim();
    g.category = _cat;
    g.amountUsd = double.parse(_asUsd.toStringAsFixed(2));
    g.paymentMethod = _method;
    g.note = _note.text.trim();
    if (widget.existing != null) { await store.updateGasto(g); } else { await store.addGasto(g); }
    if (!mounted) return;
    Navigator.pop(context);
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'Nuevo gasto' : 'Editar gasto'), actions: [
        if (widget.existing != null)
          IconButton(icon: const Icon(Icons.delete), onPressed: () {
            showDialog<void>(context: context, builder: (dctx) => AlertDialog(
              title: const Text('Eliminar gasto'),
              content: Text('Eliminar "' + widget.existing!.concept + '"?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancelar')),
                FilledButton(onPressed: () async { Navigator.pop(dctx); await store.deleteGasto(widget.existing!); if (mounted) Navigator.pop(context); }, child: const Text('Eliminar')),
              ]));
          }),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(controller: _concept,
          decoration: const InputDecoration(labelText: 'Concepto (ej: pan, gas, bolsas)'))),
        Padding(padding: const EdgeInsets.only(bottom: 12), child: DropdownButtonFormField<String>(
          value: _cat,
          decoration: const InputDecoration(labelText: 'Categoria'),
          items: [for (final e in kGastoCats.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => setState(() => _cat = v ?? 'otros'))),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: TextField(controller: _amount, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Monto'))),
          const SizedBox(width: 12),
          SegmentedButton<Currency>(
            segments: const [ButtonSegment(value: Currency.usd, label: Text('USD')), ButtonSegment(value: Currency.ves, label: Text('Bs'))],
            selected: {_cur},
            onSelectionChanged: (v) => setState(() => _cur = v.first)),
        ]),
        Padding(padding: const EdgeInsets.only(top: 6, bottom: 12), child: Text(
          _cur == Currency.ves ? 'Equivale a ${usd(_asUsd)} (tasa ${ves(store.rate)} por \$)' : 'Equivale a ${ves(_asUsd * store.rate)}',
          style: const TextStyle(fontSize: 12, color: Colors.grey))),
        const Text('Pagado con', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, children: [
          for (final m in store.methods) ChoiceChip(label: Text(m, style: const TextStyle(fontSize: 12)), selected: _method == m,
            onSelected: (sel) => setState(() => _method = sel ? m : '')),
        ]),
        const SizedBox(height: 12),
        TextField(controller: _note, maxLines: 3, decoration: const InputDecoration(labelText: 'Nota (opcional)')),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, height: 50, child: FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save),
          label: Text(_saving ? 'Guardando...' : 'Guardar gasto'))),
      ]),
    );
  }
}

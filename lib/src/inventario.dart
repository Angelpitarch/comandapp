part of '../main.dart';

// Ingredientes e inventario.

// ======================= INGREDIENTES (INVENTARIO) =======================
String fmtQty(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

class Ingredient {
  String id;
  String name;
  String unit;
  double stock;
  double minStock;
  double cost;
  Currency costCurrency;
  String kind;
  String emoji;
  Ingredient(this.id, this.name, this.unit, this.stock, this.minStock, {this.cost = 0, this.costCurrency = Currency.usd, this.kind = 'comida', this.emoji = '📦'});
  factory Ingredient.fromRow(Map<String, dynamic> r) => Ingredient(
        r['id'] as String,
        (r['name'] ?? '') as String,
        (r['unit'] ?? 'unidad') as String,
        ((r['stock'] ?? 0) as num).toDouble(),
        ((r['min_stock'] ?? 0) as num).toDouble(),
        cost: ((r['cost'] ?? 0) as num).toDouble(),
        costCurrency: curFrom((r['cost_currency'] ?? 'usd') as String),
        kind: (r['kind'] ?? 'comida') as String,
        emoji: (r['emoji'] ?? '📦') as String,
      );
  Map<String, dynamic> toRow() => <String, dynamic>{'name': name, 'unit': unit, 'stock': stock, 'min_stock': minStock, 'cost': cost, 'cost_currency': curStr(costCurrency), 'kind': kind, 'emoji': emoji};
  bool get low => stock <= minStock;
}

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inventario de ingredientes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IngredientForm())),
        icon: const Icon(Icons.add), label: const Text('Nuevo')),
      body: AnimatedBuilder(animation: store, builder: (context, _) {
        final low = store.lowIngredients;
        final list = store.ingredients;
        return ListView(padding: const EdgeInsets.all(16), children: [
          if (low.isNotEmpty) ...[
            Card(color: Colors.red.shade50, child: Padding(padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: const [Icon(Icons.warning_amber, color: Colors.red), SizedBox(width: 8),
                  Text('Ingredientes por agotarse', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red))]),
                const SizedBox(height: 6),
                for (final i in low)
                  Text('- ${i.name}: ${i.stock <= 0 ? 'AGOTADO' : 'quedan ${fmtQty(i.stock)} ${i.unit}'}',
                      style: const TextStyle(fontSize: 12.5)),
              ]))),
            const SizedBox(height: 12),
          ],
          if (list.isEmpty)
            const Padding(padding: EdgeInsets.all(24),
              child: Center(child: Text('Aun no hay ingredientes.\nToca "Nuevo" para agregar.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)))),
          for (final grupo in const [['bebida', '🥤 Bebestibles'], ['comida', '🍔 Ingredientes de comida']])
            if (list.any((i) => i.kind == grupo[0])) ...[
              Padding(padding: const EdgeInsets.only(top: 6, bottom: 4), child: Text(grupo[1], style: const TextStyle(fontWeight: FontWeight.bold, color: kPrimary, fontSize: 15))),
              for (final i in list.where((i) => i.kind == grupo[0]))
                Card(margin: const EdgeInsets.only(bottom: 6), child: ListTile(
                  leading: Text(i.emoji, style: const TextStyle(fontSize: 26)),
                  title: Text(i.name),
                  subtitle: Text('Stock: ${fmtQty(i.stock)} ${i.unit}  ·  minimo: ${fmtQty(i.minStock)} ${i.unit}', style: const TextStyle(fontSize: 12)),
                  trailing: i.low ? const Icon(Icons.error, color: Colors.red) : const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => IngredientForm(existing: i))),
                )),
            ],
        ]);
      }),
    );
  }
}

class IngredientForm extends StatefulWidget {
  final Ingredient? existing;
  const IngredientForm({super.key, this.existing});
  @override
  State<IngredientForm> createState() => _IngredientFormState();
}
class _IngredientFormState extends State<IngredientForm> {
  static const _units = ['kg', 'g', 'unidad', 'litro', 'ml', 'paquete', 'bolsa'];
  late TextEditingController _name, _stock, _minStock, _cost, _emoji;
  late String _unit;
  String _kind = 'comida';
  Currency _costCur = Currency.usd;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _stock = TextEditingController(text: e != null ? fmtQty(e.stock) : '0');
    _minStock = TextEditingController(text: e != null ? fmtQty(e.minStock) : '0');
    _unit = e?.unit ?? 'kg';
    if (!_units.contains(_unit)) _unit = 'kg';
    _cost = TextEditingController(text: e != null && e.cost > 0 ? fmtQty(e.cost) : '');
    _costCur = e?.costCurrency ?? Currency.usd;
    _emoji = TextEditingController(text: e?.emoji ?? '📦');
    _kind = e?.kind ?? 'comida';
  }
  @override
  void dispose() { _name.dispose(); _stock.dispose(); _minStock.dispose(); _cost.dispose(); _emoji.dispose(); super.dispose(); }
  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    if (name.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Escribe el nombre'))); return; }
    final stock = double.tryParse(_stock.text.replaceAll(',', '.')) ?? 0;
    final minStock = double.tryParse(_minStock.text.replaceAll(',', '.')) ?? 0;
    setState(() => _saving = true);
    final cost = double.tryParse(_cost.text.replaceAll(',', '.')) ?? 0;
    final e = widget.existing;
    final emoji = _emoji.text.trim().isEmpty ? '📦' : _emoji.text.trim();
    if (e != null) { e.name = name; e.unit = _unit; e.stock = stock; e.minStock = minStock; e.cost = cost; e.costCurrency = _costCur; e.kind = _kind; e.emoji = emoji; await store.updateIngredient(e); }
    else { await store.addIngredient(Ingredient('', name, _unit, stock, minStock, cost: cost, costCurrency: _costCur, kind: _kind, emoji: emoji)); }
    if (!mounted) return;
    Navigator.pop(context);
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'Nuevo ingrediente' : 'Editar ingrediente'), actions: [
        if (widget.existing != null)
          IconButton(icon: const Icon(Icons.delete), onPressed: () {
            showDialog<void>(context: context, builder: (dctx) => AlertDialog(
              title: const Text('Eliminar ingrediente'),
              content: Text('Eliminar "${widget.existing!.name}"?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancelar')),
                FilledButton(onPressed: () async { Navigator.pop(dctx); await store.deleteIngredient(widget.existing!); if (mounted) Navigator.pop(context); }, child: const Text('Eliminar')),
              ]));
          }),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          SizedBox(width: 80, child: TextField(controller: _emoji, textAlign: TextAlign.center, decoration: const InputDecoration(labelText: 'Icono'))),
          const SizedBox(width: 12),
          Expanded(child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Ej: Carne, Queso, Refresco'))),
        ]),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'comida', label: Text('Comida'), icon: Icon(Icons.restaurant)),
            ButtonSegment(value: 'bebida', label: Text('Bebida'), icon: Icon(Icons.local_drink)),
          ],
          selected: {_kind}, onSelectionChanged: (s) => setState(() => _kind = s.first)),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(value: _unit,
          decoration: const InputDecoration(labelText: 'Unidad de medida'),
          items: [for (final u in _units) DropdownMenuItem(value: u, child: Text(u))],
          onChanged: (v) => setState(() => _unit = v ?? 'kg')),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: _stock, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Stock actual'))),
          const SizedBox(width: 12),
          Expanded(child: TextField(controller: _minStock, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Stock minimo (alerta)'))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: _cost, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Costo por unidad (compra)'))),
          const SizedBox(width: 12),
          SegmentedButton<Currency>(segments: const [ButtonSegment(value: Currency.usd, label: Text('USD')), ButtonSegment(value: Currency.ves, label: Text('Bs'))], selected: {_costCur}, onSelectionChanged: (v) => setState(() => _costCur = v.first)),
        ]),
        const SizedBox(height: 20),
        SizedBox(width: double.infinity, height: 50, child: FilledButton.icon(onPressed: _saving ? null : _save,
          icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save),
          label: Text(_saving ? 'Guardando...' : 'Guardar ingrediente'))),
      ]),
    );
  }
}

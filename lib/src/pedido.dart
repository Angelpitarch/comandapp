part of '../main.dart';

// Tomar pedido (menu) y editor de cada producto del pedido.

// ======================= PEDIDO (menu) =======================
class OrderScreen extends StatefulWidget {
  final String cartKey;
  final int? table;
  final String? takeawayId;
  final String? takeawayName;
  const OrderScreen({super.key, required this.cartKey, required this.table, this.takeawayId, this.takeawayName});
  @override
  State<OrderScreen> createState() => _OrderScreenState();
}
class _OrderScreenState extends State<OrderScreen> {
  String _cat = '';
  bool _sending = false;
  bool _sentTakeaway = false;
  final _noteCtrl = TextEditingController();
  @override
  void dispose() { _noteCtrl.dispose(); super.dispose(); }

  Future<void> _addOrEdit(Product p, {CartItem? existing}) async {
    final item = await showModalBottomSheet<CartItem>(context: context, isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => ItemEditor(product: p, existing: existing));
    if (item != null && existing == null) { store.cart(widget.cartKey).add(item); store.touch(); }
    else if (item != null) { store.touch(); }
  }

  Future<void> _send() async {
    if (_sending || store.cart(widget.cartKey).isEmpty) return;
    setState(() => _sending = true);
    final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();
    final number = await store.send(widget.cartKey, table: widget.table, takeawayId: widget.takeawayId, takeawayName: widget.takeawayName, note: note);
    if (!mounted) return;
    setState(() => _sending = false);
    _noteCtrl.clear();
    if (number == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo enviar. Revisa la conexion.')));
      return;
    }
    await showDialog<void>(context: context, builder: (_) => AlertDialog(
      icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
      title: Text('Comanda #${number.toString().padLeft(6, '0')}'),
      content: const Text('Comanda enviada a cocina.'),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))]));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.table != null ? 'Agregar - Mesa ${widget.table}' : (widget.takeawayName != null ? 'Llevar - ${widget.takeawayName}' : 'Para llevar');
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: AnimatedBuilder(animation: store, builder: (context, _) {
        final items = store.cart(widget.cartKey);
        final total = store.cartTotalUsd(widget.cartKey);
        final cats = store.categories;
        if ((_cat.isEmpty || !cats.any((c) => c.key == _cat)) && cats.isNotEmpty) _cat = cats.first.key;
        final prods = store.products.where((p) => p.cat == _cat).toList();
        return Column(children: [
          lowStockWaiterBanner(),
          SizedBox(height: 52, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10), children: [
            for (final c in cats) Padding(padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Center(child: ChoiceChip(label: Text('${c.emoji} ${c.label}'), selected: c.key == _cat, onSelected: (_) => setState(() => _cat = c.key)))),
          ])),
          Expanded(child: prods.isEmpty
              ? const Center(child: Text('Sin productos en esta categoria', style: TextStyle(color: Colors.grey)))
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 190, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.9),
                  itemCount: prods.length,
                  itemBuilder: (context, i) {
                    final p = prods[i];
                    final mk = store.maxMakeable(p);
                    final disponible = p.available && mk != 0;
                    return Card(child: InkWell(onTap: disponible ? () => _addOrEdit(p) : null,
                      child: Opacity(opacity: disponible ? 1 : 0.4, child: Padding(padding: const EdgeInsets.all(8),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Center(child: Text(p.emoji, style: const TextStyle(fontSize: 38))),
                          const Spacer(),
                          Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.1, fontSize: 13)),
                          const SizedBox(height: 3),
                          Text(dualPrice(p.price, p.cur), style: const TextStyle(fontSize: 10.5)),
                          if (mk > 0) Text('Alcanza ~' + mk.toString(), style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                          if (mk == 0) const Text('Sin ingredientes', style: TextStyle(color: Colors.red, fontSize: 10)),
                          if (!p.available) const Text('No disponible', style: TextStyle(color: Colors.red, fontSize: 10)),
                        ])))));
                  })),
          Material(elevation: 8, child: SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (items.isNotEmpty)
                ConstrainedBox(constraints: const BoxConstraints(maxHeight: 150), child: ListView(shrinkWrap: true, children: [
                  for (final it in items)
                    Dismissible(key: ValueKey(it), direction: DismissDirection.endToStart,
                      background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 16), child: const Icon(Icons.delete, color: Colors.white)),
                      onDismissed: (_) { items.remove(it); store.touch(); },
                      child: ListTile(dense: true,
                        leading: CircleAvatar(radius: 14, backgroundColor: Colors.orange.shade50, child: Text('${it.qty}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        title: Text(it.p.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: Text([if (it.size != null) it.size!.name, ...it.p.extras.where((e) => it.extras.contains(e.id)).map((e) => '+${e.name}'), ...it.quita.map((q) => 'Sin $q'), if (it.note != null) 'Nota: ${it.note}'].join(' · '), style: const TextStyle(fontSize: 11)),
                        trailing: Text(usd(store.lineUsd(it)), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        onTap: () => _addOrEdit(it.p, existing: it))),
                ]))
              else const Padding(padding: EdgeInsets.all(8), child: Text('Agrega productos del menu', style: TextStyle(color: Colors.grey))),
              TextField(controller: _noteCtrl, decoration: const InputDecoration(isDense: true, labelText: 'Observacion general', hintText: 'Ej: entregar bebidas primero', prefixIcon: Icon(Icons.sticky_note_2_outlined))),
              const SizedBox(height: 10),
              Row(children: [const Text('Total', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), const Spacer(), Text(dualUsd(total), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))]),
              const SizedBox(height: 8),
              if (widget.table != null || widget.takeawayId != null)
                SizedBox(width: double.infinity, height: 50, child: FilledButton.icon(
                  onPressed: (items.isEmpty || _sending) ? null : _send,
                  icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send),
                  label: Text(_sending ? 'Enviando...' : 'Enviar a cocina')))
              else Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: (items.isEmpty || _sending) ? null : _send, icon: const Icon(Icons.send), label: Text(_sentTakeaway ? 'Enviar de nuevo' : 'Enviar a cocina'))),
                const SizedBox(width: 8),
                Expanded(child: FilledButton.icon(onPressed: items.isEmpty ? null : () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentScreen(table: null, cartKey: widget.cartKey)));
                  if (mounted && store.cart(widget.cartKey).isEmpty) Navigator.pop(context);
                }, icon: const Icon(Icons.point_of_sale), label: const Text('Cobrar'))),
              ]),
            ]))))
        ]);
      }),
    );
  }
}

// ======================= EDITOR DE ITEM =======================
class ItemEditor extends StatefulWidget {
  final Product product;
  final CartItem? existing;
  const ItemEditor({super.key, required this.product, this.existing});
  @override
  State<ItemEditor> createState() => _ItemEditorState();
}
class _ItemEditorState extends State<ItemEditor> {
  late Sz? _size;
  late int _qty;
  late Set<String> _extras;
  late Set<String> _quita;
  late Set<String> _quitaIng;
  late TextEditingController _note;
  @override
  void initState() {
    super.initState();
    final p = widget.product;
    final e = widget.existing;
    _size = e?.size ?? (p.sizes.isNotEmpty ? p.sizes[1] : null);
    _qty = e?.qty ?? 1;
    _extras = {...?e?.extras};
    _quita = {...?e?.quita};
    _quitaIng = {...?e?.quitaIng};
    _note = TextEditingController(text: e?.note ?? '');
  }
  @override
  void dispose() { _note.dispose(); super.dispose(); }
  double get _unit {
    final p = widget.product;
    var t = p.price + (_size?.delta ?? 0);
    for (final ex in p.extras) { if (_extras.contains(ex.id)) t += ex.price; }
    return t;
  }
  void _confirm() {
    final e = widget.existing;
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();
    if (e != null) { e.size = _size; e.qty = _qty; e.extras = _extras; e.quita = _quita; e.quitaIng = _quitaIng; e.note = note; Navigator.pop(context, e); }
    else { Navigator.pop(context, CartItem(widget.product, qty: _qty, size: _size, extras: _extras, quita: _quita, quitaIng: _quitaIng, note: note)); }
  }
  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(expand: false, initialChildSize: 0.75, maxChildSize: 0.95, minChildSize: 0.5,
        builder: (context, scroll) => Column(children: [
          const SizedBox(height: 10),
          Container(width: 44, height: 5, decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(4))),
          Expanded(child: ListView(controller: scroll, padding: const EdgeInsets.all(20), children: [
            Row(children: [Text(p.emoji, style: const TextStyle(fontSize: 30)), const SizedBox(width: 10), Expanded(child: Text(p.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)))]),
            const SizedBox(height: 4),
            Text(dualPrice(_unit, p.cur), style: const TextStyle(fontWeight: FontWeight.w600)),
            const Divider(height: 26),
            if (p.sizes.isNotEmpty) ...[
              const Text('Tamano', style: TextStyle(fontWeight: FontWeight.w600)), const SizedBox(height: 8),
              Wrap(spacing: 8, children: [for (final s in p.sizes) ChoiceChip(label: Text(s.name), selected: _size?.name == s.name, onSelected: (_) => setState(() => _size = s))]),
              const SizedBox(height: 16),
            ],
            if (p.extras.isNotEmpty) ...[
              const Text('Extras', style: TextStyle(fontWeight: FontWeight.w600)),
              for (final ex in p.extras) CheckboxListTile(contentPadding: EdgeInsets.zero, dense: true,
                  value: _extras.contains(ex.id), title: Text(ex.name), secondary: Text('+ ${usd(ex.price)}'),
                  onChanged: (v) => setState(() => v == true ? _extras.add(ex.id) : _extras.remove(ex.id))),
              const SizedBox(height: 12),
            ],
            if (p.recipe.isNotEmpty) ...[
              const Text('Quitar ingredientes', style: TextStyle(fontWeight: FontWeight.w600)),
              const Text('Lo que quites no se descuenta del inventario', style: TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                for (final r in p.recipe)
                  if (store.ingredientById(r.ingredientId) != null)
                    FilterChip(
                      label: Text('Sin ${store.ingredientById(r.ingredientId)!.name}'),
                      selected: _quitaIng.contains(r.ingredientId),
                      onSelected: (v) => setState(() => v ? _quitaIng.add(r.ingredientId) : _quitaIng.remove(r.ingredientId))),
              ]),
              const SizedBox(height: 16),
            ],
            if (p.quita.isNotEmpty) ...[
              const Text('Quitar (personalizado)', style: TextStyle(fontWeight: FontWeight.w600)), const SizedBox(height: 8),
              Wrap(spacing: 8, children: [for (final ing in p.quita) FilterChip(label: Text('Sin $ing'), selected: _quita.contains(ing), onSelected: (v) => setState(() => v ? _quita.add(ing) : _quita.remove(ing)))]),
              const SizedBox(height: 16),
            ],
            TextField(controller: _note, maxLines: 2, decoration: const InputDecoration(labelText: 'Observacion del producto')),
          ])),
          SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: Row(children: [
            Container(decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                IconButton(icon: const Icon(Icons.remove), onPressed: _qty > 1 ? () => setState(() => _qty--) : null),
                Text('$_qty', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.add), onPressed: () => setState(() => _qty++)),
              ])),
            const SizedBox(width: 12),
            Expanded(child: FilledButton.icon(onPressed: _confirm, icon: const Icon(Icons.add_shopping_cart), label: Text(widget.existing == null ? 'Agregar' : 'Guardar'))),
          ]))),
        ])));
  }
}

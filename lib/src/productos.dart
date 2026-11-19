part of '../main.dart';

// Formulario de producto (precios, tamanos, extras, recetas y combos).

// ======================= FORMULARIO DE PRODUCTO =======================
class ProductForm extends StatefulWidget {
  final Product? existing;
  const ProductForm({super.key, this.existing});
  @override
  State<ProductForm> createState() => _ProductFormState();
}
class _ProductFormState extends State<ProductForm> {
  late TextEditingController _name, _emoji, _price, _quita, _stock, _minStock;
  late String _cat;
  late Currency _cur;
  late bool _available, _useSizes, _track;
  final List<List<TextEditingController>> _extras = [];
  final List<_RRow> _recipeRows = [];
  final List<_CRow> _comboRows = [];
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _emoji = TextEditingController(text: e?.emoji ?? '🍽️');
    _price = TextEditingController(text: e != null ? e.price.toStringAsFixed(2) : '');
    _quita = TextEditingController(text: e?.quita.join(', ') ?? '');
    _cat = e?.cat ?? (store.categories.isNotEmpty ? store.categories.first.key : 'otros');
    _cur = e?.cur ?? Currency.usd;
    _available = e?.available ?? true;
    _useSizes = e != null && e.sizes.isNotEmpty;
    _track = e?.trackStock ?? false;
    _stock = TextEditingController(text: e != null ? e.stock.toStringAsFixed(0) : '0');
    _minStock = TextEditingController(text: e != null ? e.minStock.toStringAsFixed(0) : '0');
    if (e != null) for (final ex in e.extras) { _extras.add([TextEditingController(text: ex.name), TextEditingController(text: ex.price.toStringAsFixed(2))]); }
    if (e != null) {
      for (final r in e.recipe) { _recipeRows.add(_RRow(r.ingredientId, TextEditingController(text: fmtQty(r.qty)))); }
      for (final c in e.comboItems) { _comboRows.add(_CRow(c.productId, TextEditingController(text: fmtQty(c.qty)))); }
    }
  }
  @override
  void dispose() {
    _name.dispose(); _emoji.dispose(); _price.dispose(); _quita.dispose(); _stock.dispose(); _minStock.dispose();
    for (final row in _extras) { for (final c in row) { c.dispose(); } }
    for (final r in _recipeRows) { r.qty.dispose(); }
    for (final c in _comboRows) { c.qty.dispose(); }
    super.dispose();
  }
  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    final price = double.tryParse(_price.text.replaceAll(',', '.'));
    if (name.isEmpty || price == null || price < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Revisa el nombre y el precio')));
      return;
    }
    final sizes = _useSizes ? [Sz('Pequena', -0.5), Sz('Mediana', 0), Sz('Grande', 0.8)] : <Sz>[];
    final extras = <Extra>[];
    for (var i = 0; i < _extras.length; i++) {
      final n = _extras[i][0].text.trim();
      final pr = double.tryParse(_extras[i][1].text.replaceAll(',', '.')) ?? 0;
      if (n.isNotEmpty) extras.add(Extra('e${i + 1}', n, pr));
    }
    final quita = _quita.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final emoji = _emoji.text.trim().isEmpty ? '🍽️' : _emoji.text.trim();
    final stock = double.tryParse(_stock.text.replaceAll(',', '.')) ?? 0;
    final minStock = double.tryParse(_minStock.text.replaceAll(',', '.')) ?? 0;
    final recipe = <RecipeItem>[
      for (final r in _recipeRows)
        if (r.ingredientId != null) RecipeItem(r.ingredientId!, double.tryParse(r.qty.text.replaceAll(',', '.')) ?? 0),
    ];
    final comboItems = <ComboItem>[
      for (final c in _comboRows)
        if (c.productId != null) ComboItem(c.productId!, double.tryParse(c.qty.text.replaceAll(',', '.')) ?? 0),
    ];
    setState(() => _saving = true);
    final e = widget.existing;
    if (e != null) {
      e.name = name; e.emoji = emoji; e.cat = _cat; e.price = price; e.cur = _cur;
      e.available = _available; e.sizes = sizes; e.extras = extras; e.quita = quita;
      e.stock = 0; e.minStock = 0; e.trackStock = false;
      e.recipe = _cat == 'combos' ? <RecipeItem>[] : recipe;
      e.comboItems = _cat == 'combos' ? comboItems : <ComboItem>[];
      await store.updateProduct(e);
    } else {
      await store.addProduct(Product('', name, emoji, _cat, price, _cur, sizes: sizes, extras: extras, quita: quita, available: _available, stock: 0, minStock: 0, trackStock: false, recipe: _cat == 'combos' ? <RecipeItem>[] : recipe, comboItems: _cat == 'combos' ? comboItems : <ComboItem>[]));
    }
    if (!mounted) return;
    Navigator.pop(context);
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'Nuevo producto' : 'Editar producto'), actions: [
        if (widget.existing != null)
          IconButton(icon: const Icon(Icons.delete), onPressed: () {
            showDialog<void>(context: context, builder: (dctx) => AlertDialog(
              title: const Text('Eliminar producto'),
              content: Text('Eliminar "${widget.existing!.name}"?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancelar')),
                FilledButton(onPressed: () async {
                  Navigator.pop(dctx);
                  await store.deleteProduct(widget.existing!);
                  if (mounted) Navigator.pop(context);
                }, child: const Text('Eliminar')),
              ]));
          }),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre')),
        const SizedBox(height: 12),
        Row(children: [
          SizedBox(width: 90, child: TextField(controller: _emoji, textAlign: TextAlign.center, decoration: const InputDecoration(labelText: 'Icono'))),
          const SizedBox(width: 12),
          Expanded(child: DropdownButtonFormField<String>(value: store.categories.any((c) => c.key == _cat) ? _cat : null,
            decoration: const InputDecoration(labelText: 'Categoria'),
            items: [for (final c in store.categories) DropdownMenuItem(value: c.key, child: Text('${c.emoji} ${c.label}'))],
            onChanged: (v) => setState(() => _cat = v ?? 'otros'))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: _price, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Precio'))),
          const SizedBox(width: 12),
          SegmentedButton<Currency>(segments: const [ButtonSegment(value: Currency.usd, label: Text('USD')), ButtonSegment(value: Currency.ves, label: Text('Bs'))],
              selected: {_cur}, onSelectionChanged: (s) => setState(() => _cur = s.first)),
        ]),
        const SizedBox(height: 6),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Disponible'), value: _available, onChanged: (v) => setState(() => _available = v)),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Usar tamanos (Pequena/Mediana/Grande)'), value: _useSizes, onChanged: (v) => setState(() => _useSizes = v)),
        const SizedBox(height: 6),
        TextField(controller: _quita, decoration: const InputDecoration(labelText: 'Ingredientes que se pueden quitar (separados por coma)', hintText: 'Cebolla, Tomate, Salsas')),
        const SizedBox(height: 16),
        Row(children: [
          const Text('Extras', style: TextStyle(fontWeight: FontWeight.bold)), const Spacer(),
          TextButton.icon(onPressed: () => setState(() => _extras.add([TextEditingController(), TextEditingController(text: '0')])), icon: const Icon(Icons.add), label: const Text('Agregar extra')),
        ]),
        for (var i = 0; i < _extras.length; i++)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
            Expanded(flex: 3, child: TextField(controller: _extras[i][0], decoration: const InputDecoration(labelText: 'Nombre extra', isDense: true))),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: TextField(controller: _extras[i][1], keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Precio', isDense: true))),
            IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.red), onPressed: () => setState(() { _extras[i][0].dispose(); _extras[i][1].dispose(); _extras.removeAt(i); })),
          ])),
        const Divider(height: 24),
        if (_cat == 'combos') ...[
          Row(children: [
            const Expanded(child: Text('Componentes del combo', style: TextStyle(fontWeight: FontWeight.bold))),
            TextButton.icon(onPressed: () => setState(() => _comboRows.add(_CRow(null, TextEditingController(text: '1')))), icon: const Icon(Icons.add), label: const Text('Agregar')),
          ]),
          const Text('Elige productos ya creados y su cantidad. El precio del combo lo pones tu arriba (no se suma solo).', style: TextStyle(fontSize: 11.5, color: Colors.grey)),
          for (var i = 0; i < _comboRows.length; i++)
            Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [
              Expanded(flex: 3, child: DropdownButtonFormField<String>(
                value: store.products.any((x) => x.id == _comboRows[i].productId && x.cat != 'combos') ? _comboRows[i].productId : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Producto', isDense: true),
                items: [for (final pr in store.products.where((x) => x.cat != 'combos')) DropdownMenuItem(value: pr.id, child: Text(pr.name, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() => _comboRows[i].productId = v))),
              const SizedBox(width: 8),
              SizedBox(width: 64, child: TextField(controller: _comboRows[i].qty, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Cant.', isDense: true))),
              IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.red), onPressed: () => setState(() { _comboRows[i].qty.dispose(); _comboRows.removeAt(i); })),
            ])),
        ] else ...[
          Row(children: [
            const Expanded(child: Text('Receta (ingredientes)', style: TextStyle(fontWeight: FontWeight.bold))),
            TextButton.icon(onPressed: () => setState(() => _recipeRows.add(_RRow(null, TextEditingController(text: '1')))), icon: const Icon(Icons.add), label: const Text('Agregar')),
          ]),
          const Text('Que ingredientes consume y cuanto. Se descuentan del inventario al vender.', style: TextStyle(fontSize: 11.5, color: Colors.grey)),
          if (store.ingredients.isEmpty)
            const Padding(padding: EdgeInsets.only(top: 6), child: Text('Primero agrega ingredientes en el Inventario.', style: TextStyle(fontSize: 12, color: Colors.red))),
          for (var i = 0; i < _recipeRows.length; i++)
            Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [
              Expanded(flex: 3, child: DropdownButtonFormField<String>(
                value: store.ingredients.any((ing) => ing.id == _recipeRows[i].ingredientId) ? _recipeRows[i].ingredientId : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Ingrediente', isDense: true),
                items: [for (final ing in store.ingredients) DropdownMenuItem(value: ing.id, child: Text('${ing.name} (${ing.unit})', overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() => _recipeRows[i].ingredientId = v))),
              const SizedBox(width: 8),
              SizedBox(width: 64, child: TextField(controller: _recipeRows[i].qty, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Cant.', isDense: true))),
              IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.red), onPressed: () => setState(() { _recipeRows[i].qty.dispose(); _recipeRows.removeAt(i); })),
            ])),
        ],
        const SizedBox(height: 20),
        SizedBox(width: double.infinity, height: 50, child: FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save),
          label: Text(_saving ? 'Guardando...' : 'Guardar producto'))),
      ]),
    );
  }
}

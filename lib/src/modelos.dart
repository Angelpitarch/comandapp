part of '../main.dart';

// Modelos de datos (productos, mesas, comandas, ventas, recetas, para llevar...).

// ======================= MODELOS =======================
enum Currency { usd, ves }
extension CurCode on Currency { String get code => this == Currency.usd ? 'USD' : 'VES'; }
Currency curFrom(String s) => s == 'ves' ? Currency.ves : Currency.usd;
String curStr(Currency c) => c == Currency.usd ? 'usd' : 'ves';

// Categoria de producto (dinamica: el usuario la crea/edita/borra)
class CatDef {
  final String id;
  final String key;
  final String label;
  final String emoji;
  final int position;
  final bool protected;
  CatDef(this.id, this.key, this.label, this.emoji, this.position, this.protected);
  factory CatDef.fromRow(Map<String, dynamic> r) => CatDef(
        (r['id'] ?? '') as String,
        (r['key'] ?? '') as String,
        (r['label'] ?? '') as String,
        (r['emoji'] ?? '🍽️') as String,
        ((r['position'] ?? 100) as num).toInt(),
        (r['protected'] ?? false) as bool,
      );
}
String catLabel(String key) {
  final c = store.categories.where((x) => x.key == key);
  return c.isNotEmpty ? c.first.label : (key.isEmpty ? 'Otros' : key);
}

class Extra {
  String id;
  String name;
  double price;
  Extra(this.id, this.name, this.price);
}
class Sz {
  String name;
  double delta;
  Sz(this.name, this.delta);
}

class Product {
  String id;
  String name;
  String emoji;
  String cat;
  double price;
  Currency cur;
  List<Sz> sizes;
  List<Extra> extras;
  List<String> quita;
  bool available;
  double stock;
  double minStock;
  bool trackStock;
  List<RecipeItem> recipe;
  List<ComboItem> comboItems;
  Product(this.id, this.name, this.emoji, this.cat, this.price, this.cur,
      {this.sizes = const [], this.extras = const [], this.quita = const [], this.available = true, this.stock = 0, this.minStock = 0, this.trackStock = false, this.recipe = const [], this.comboItems = const []});

  factory Product.fromRow(Map<String, dynamic> r) => Product(
        r['id'] as String,
        (r['name'] ?? '') as String,
        (r['emoji'] ?? '🍽️') as String,
        (r['category'] ?? 'otros') as String,
        ((r['price'] ?? 0) as num).toDouble(),
        curFrom((r['currency'] ?? 'usd') as String),
        available: (r['available'] ?? true) as bool,
        stock: ((r['stock'] ?? 0) as num).toDouble(),
        minStock: ((r['min_stock'] ?? 0) as num).toDouble(),
        trackStock: (r['track_stock'] ?? false) as bool,
        recipe: [for (final x in (r['recipe'] as List? ?? [])) RecipeItem((x['ingredient_id'] ?? '') as String, ((x['qty'] ?? 0) as num).toDouble())],
        comboItems: [for (final x in (r['combo_items'] as List? ?? [])) ComboItem((x['product_id'] ?? '') as String, ((x['qty'] ?? 0) as num).toDouble())],
        sizes: [for (final s in (r['sizes'] as List? ?? [])) Sz(s['name'] as String, (s['delta'] as num).toDouble())],
        extras: [for (final e in (r['extras'] as List? ?? [])) Extra((e['id'] ?? '') as String, e['name'] as String, ((e['price'] ?? 0) as num).toDouble())],
        quita: [for (final q in (r['quita'] as List? ?? [])) q.toString()],
      );

  Map<String, dynamic> toRow() => <String, dynamic>{
        'name': name,
        'emoji': emoji,
        'category': cat,
        'price': price,
        'currency': curStr(cur),
        'available': available,
        'stock': stock,
        'min_stock': minStock,
        'track_stock': trackStock,
        'recipe': [for (final r in recipe) <String, dynamic>{'ingredient_id': r.ingredientId, 'qty': r.qty}],
        'combo_items': [for (final c in comboItems) <String, dynamic>{'product_id': c.productId, 'qty': c.qty}],
        'sizes': [for (final s in sizes) <String, dynamic>{'name': s.name, 'delta': s.delta}],
        'extras': [for (final e in extras) <String, dynamic>{'id': e.id, 'name': e.name, 'price': e.price}],
        'quita': quita,
      };
}

class CartItem {
  final Product p;
  int qty;
  Sz? size;
  Set<String> extras;
  Set<String> quita;
  Set<String> quitaIng;
  String? note;
  CartItem(this.p, {this.qty = 1, this.size, Set<String>? extras, Set<String>? quita, Set<String>? quitaIng, this.note})
      : extras = extras ?? {},
        quita = quita ?? {},
        quitaIng = quitaIng ?? {};
  double unit() {
    var t = p.price + (size?.delta ?? 0);
    for (final e in p.extras) { if (extras.contains(e.id)) t += e.price; }
    return t;
  }
}

class TableModel {
  final int number;
  final int cap;
  String status;
  String? waiter;
  DateTime? openedAt;
  TableModel(this.number, this.cap, {this.status = 'disponible', this.waiter, this.openedAt});
  factory TableModel.fromRow(Map<String, dynamic> r) => TableModel(
        (r['number'] as num).toInt(),
        ((r['capacity'] ?? 2) as num).toInt(),
        status: (r['status'] ?? 'disponible') as String,
        waiter: r['waiter'] as String?,
        openedAt: r['opened_at'] != null ? DateTime.tryParse(r['opened_at'] as String)?.toLocal() : null,
      );
}

class TLine {
  final String name;
  final int qty;
  final String? size;
  final List<String> extras;
  final List<String> quita;
  final String? note;
  const TLine(this.name, this.qty, {this.size, this.extras = const [], this.quita = const [], this.note});
  factory TLine.fromJson(Map<String, dynamic> r) => TLine(
        (r['name'] ?? '') as String,
        ((r['qty'] ?? 1) as num).toInt(),
        size: r['size'] as String?,
        extras: [for (final e in (r['extras'] as List? ?? [])) e.toString()],
        quita: [for (final q in (r['quita'] as List? ?? [])) q.toString()],
        note: r['note'] as String?,
      );
}

class Ticket {
  final String id;
  final int number;
  final int? table;
  final String waiter;
  final DateTime sentAt;
  final String status;
  final List<TLine> lines;
  final String? note;
  final bool adicion;
  final bool reprinted;
  final String? takeawayId;
  final String? takeawayName;
  Ticket(this.id, this.number, this.table, this.waiter, this.sentAt, this.status, this.lines,
      {this.note, this.adicion = false, this.reprinted = false, this.takeawayId, this.takeawayName});
  factory Ticket.fromRow(Map<String, dynamic> r) => Ticket(
        r['id'] as String,
        ((r['number'] ?? 0) as num).toInt(),
        r['table_number'] != null ? (r['table_number'] as num).toInt() : null,
        (r['waiter'] ?? '') as String,
        DateTime.tryParse((r['sent_at'] ?? '') as String) ?? DateTime.now(),
        (r['status'] ?? 'nueva') as String,
        [for (final l in (r['lines'] as List? ?? [])) TLine.fromJson(Map<String, dynamic>.from(l as Map))],
        note: r['note'] as String?,
        adicion: (r['adicion'] ?? false) as bool,
        reprinted: (r['reprinted'] ?? false) as bool,
        takeawayId: r['takeaway_id'] as String?,
        takeawayName: r['takeaway_name'] as String?,
      );
}

class AccLine {
  final String id;
  final int? table;
  final String? takeawayId;
  final String name;
  final int qty;
  final String? size;
  final List<String> extras;
  final List<String> quita;
  final String? note;
  final double unitUsd;
  final String? ticketId;
  AccLine(this.id, this.table, this.takeawayId, this.name, this.qty, this.size, this.extras, this.quita, this.note, this.unitUsd, {this.ticketId});
  factory AccLine.fromRow(Map<String, dynamic> r) => AccLine(
        r['id'] as String,
        r['table_number'] != null ? (r['table_number'] as num).toInt() : null,
        r['takeaway_id'] as String?,
        (r['product_name'] ?? '') as String,
        ((r['qty'] ?? 1) as num).toInt(),
        r['size'] as String?,
        [for (final e in (r['extras'] as List? ?? [])) e.toString()],
        [for (final q in (r['quita'] as List? ?? [])) q.toString()],
        r['note'] as String?,
        ((r['unit_usd'] ?? 0) as num).toDouble(),
        ticketId: r['ticket_id'] as String?,
      );
  double get lineUsd => unitUsd * qty;
}

class Payment {
  final String method;
  final double amountUsd;
  final String? reference;
  Payment(this.method, this.amountUsd, {this.reference});
}
class SaleLine {
  final String name;
  final int qty;
  final double lineUsd;
  SaleLine(this.name, this.qty, this.lineUsd);
}
class Sale {
  final int? table;
  final DateTime at;
  final List<SaleLine> lines;
  final double totalUsd;
  final List<Payment> payments;
  Sale(this.table, this.at, this.lines, this.totalUsd, this.payments);
  factory Sale.fromRow(Map<String, dynamic> r) => Sale(
        r['table_number'] != null ? (r['table_number'] as num).toInt() : null,
        (DateTime.tryParse((r['at'] ?? '') as String)?.toLocal()) ?? DateTime.now(),
        [for (final l in (r['lines'] as List? ?? [])) SaleLine((l['name'] ?? '') as String, ((l['qty'] ?? 0) as num).toInt(), ((l['lineUsd'] ?? 0) as num).toDouble())],
        ((r['total_usd'] ?? 0) as num).toDouble(),
        [for (final p in (r['payments'] as List? ?? [])) Payment((p['method'] ?? '') as String, ((p['amountUsd'] ?? 0) as num).toDouble(), reference: p['reference'] as String?)],
      );
}

class CashClose {
  final DateTime closedAt;
  final DateTime? fromAt;
  final double totalUsd;
  final int accountsCount;
  final Map<String, double> byMethod;
  final Map<String, int> units;
  final double gastosUsd;
  CashClose(this.closedAt, this.fromAt, this.totalUsd, this.accountsCount, this.byMethod, this.units, {this.gastosUsd = 0});
  factory CashClose.fromRow(Map<String, dynamic> r) => CashClose(
        (DateTime.tryParse((r['closed_at'] ?? '') as String)?.toLocal()) ?? DateTime.now(),
        r['from_at'] != null ? DateTime.tryParse(r['from_at'] as String)?.toLocal() : null,
        ((r['total_usd'] ?? 0) as num).toDouble(),
        ((r['accounts_count'] ?? 0) as num).toInt(),
        {for (final e in ((r['by_method'] ?? <String, dynamic>{}) as Map).entries) e.key as String: ((e.value ?? 0) as num).toDouble()},
        {for (final e in ((r['units'] ?? <String, dynamic>{}) as Map).entries) e.key as String: ((e.value ?? 0) as num).toInt()},
        gastosUsd: ((r['gastos_usd'] ?? 0) as num).toDouble(),
      );
}

// ======================= RECETAS Y COMBOS (modelos) =======================
class RecipeItem {
  String ingredientId;
  double qty;
  RecipeItem(this.ingredientId, this.qty);
}
class ComboItem {
  String productId;
  double qty;
  ComboItem(this.productId, this.qty);
}
class _RRow {
  String? ingredientId;
  final TextEditingController qty;
  _RRow(this.ingredientId, this.qty);
}
class _CRow {
  String? productId;
  final TextEditingController qty;
  _CRow(this.productId, this.qty);
}


// ======================= PARA LLEVAR (modelo) =======================
class Takeaway {
  final String id;
  final String name;
  final String status;
  Takeaway(this.id, this.name, this.status);
  factory Takeaway.fromRow(Map<String, dynamic> r) => Takeaway(
        r['id'] as String,
        (r['name'] ?? '') as String,
        (r['status'] ?? 'abierta') as String,
      );
}

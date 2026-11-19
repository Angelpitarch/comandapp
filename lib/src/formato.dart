part of '../main.dart';

// Formato de montos y fechas.

// ======================= FORMATO =======================
String _grp(String s) {
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) { if (i > 0 && (s.length - i) % 3 == 0) b.write('.'); b.write(s[i]); }
  return b.toString();
}
String _fmt(double v, {int dec = 2}) {
  final f = v.abs().toStringAsFixed(dec);
  final parts = f.split('.');
  final g = _grp(parts[0]);
  return dec == 0 ? g : '$g,${parts[1]}';
}
String usd(double v) => '\$${_fmt(v)}';
String ves(double v) => 'Bs ${_fmt(v)}';
String dualUsd(double u) => '${usd(u)} · ${ves(u * store.rate)}';
String dualPrice(double amt, Currency c) => '${usd(store.toUsd(amt, c))} · ${ves(store.toVes(amt, c))}';
String two(int n) => n.toString().padLeft(2, '0');
String hhmm(DateTime d) => '${two(d.hour)}:${two(d.minute)}';
String fecha(DateTime d) => '${two(d.day)}/${two(d.month)}/${d.year}';

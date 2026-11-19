part of '../main.dart';

// Pantalla de cocina.

// ======================= COCINA =======================
class KitchenScreen extends StatefulWidget {
  const KitchenScreen({super.key});
  @override
  State<KitchenScreen> createState() => _KitchenScreenState();
}
class _KitchenScreenState extends State<KitchenScreen> {
  Timer? _timer;
  // Solo los cronometros se redibujan cada segundo (antes se redibujaba toda la pantalla).
  final _ahora = ValueNotifier<DateTime>(DateTime.now());
  final Set<String> _vistas = {}; // comandas ya mostradas: se avisa solo por las que llegan despues
  bool _cargada = false;          // la primera carga no suena (son comandas que ya estaban)
  bool _flash = false;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _ahora.value = DateTime.now());
  }
  @override
  void dispose() { _timer?.cancel(); _ahora.dispose(); super.dispose(); }
  void _alertNueva() {
    HapticFeedback.heavyImpact();
    var count = 0;
    Timer.periodic(const Duration(milliseconds: 500), (t) {
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.mediumImpact();
      count++;
      if (count >= 4) t.cancel();
    });
    setState(() => _flash = true);
    Future.delayed(const Duration(milliseconds: 1500), () { if (mounted) setState(() => _flash = false); });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Row(children: [Icon(Icons.notifications_active, color: kInk), SizedBox(width: 10),
        Text('NUEVA COMANDA', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kInk))]),
      backgroundColor: kAmber, duration: Duration(seconds: 3)));
  }
  String _elapsed(DateTime d, DateTime ahora) {
    final s = ahora.difference(d);
    return '${(s.inMinutes).toString().padLeft(2, '0')}:${(s.inSeconds % 60).toString().padLeft(2, '0')}';
  }
  Color _c(String s) => switch (s) { 'nueva' => const Color(0xFF2F6FDB), 'preparando' => kAmber, 'lista' => kOk, _ => Colors.grey };
  // texto sobre el color del estado (el ambar lleva texto negro para que se lea bien)
  Color _fg(String s) => s == 'preparando' ? kInk : Colors.white;
  String _estado(String s) => switch (s) { 'nueva' => 'NUEVA', 'preparando' => 'PREPARANDO', 'lista' => 'LISTA', _ => s.toUpperCase() };

  void _anular(Ticket t) {
    final reasonCtrl = TextEditingController();
    bool usada = true;
    showDialog<void>(context: context, builder: (dctx) => StatefulBuilder(builder: (dctx, setD) {
      final value = store.valueOfTicket(t.id);
      return AlertDialog(
        title: Text('Anular comanda #' + t.number.toString().padLeft(6, '0')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: reasonCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Motivo de la anulacion')),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Se uso la mercancia?'),
            subtitle: const Text('Si los alimentos ya se prepararon o gastaron'),
            value: usada, onChanged: (v) => setD(() => usada = v)),
          if (usada) Text('Total a descontar: ' + dualUsd(value), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cerrar')),
          FilledButton(onPressed: () async {
            Navigator.pop(dctx);
            await store.cancelTicketFull(t, reason: reasonCtrl.text.trim(), merchandiseUsed: usada);
          }, child: const Text('Anular comanda')),
        ],
      );
    }));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _flash ? const Color(0xFF5A3D00) : kLoginBg,
      appBar: barraMarca(context, 'Cocina', actions: [
        IconButton(tooltip: 'Cambiar mi PIN', icon: const Icon(Icons.lock_reset, color: Colors.white),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChangePinScreen()))),
        IconButton(tooltip: 'Salir', icon: const Icon(Icons.logout, color: Colors.white), onPressed: () => _logout(context)),
      ]),
      body: AnimatedBuilder(animation: store, builder: (context, _) {
        final list = store.tickets.where((t) => t.status != 'entregada' && t.status != 'anulada').toList();
        if (store.ticketsListos) {
          if (_cargada && list.any((t) => t.status == 'nueva' && !_vistas.contains(t.id))) {
            WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _alertNueva(); });
          }
          _vistas.addAll(list.map((t) => t.id));
          _cargada = true;
        }
        if (list.isEmpty) {
          return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.check_circle_outline, color: Colors.white24, size: 64),
            SizedBox(height: 12),
            Text('Sin comandas pendientes', style: TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.w600)),
            SizedBox(height: 4),
            Text('Las nuevas apareceran aqui con un aviso', style: TextStyle(color: Colors.white38, fontSize: 13)),
          ]));
        }
        final grid = LayoutBuilder(builder: (context, cns) {
          final cols = (cns.maxWidth / 300).floor().clamp(1, 5).toInt();
          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.72),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final t = list[i];
              final c = _c(t.status);
              final fg = _fg(t.status);
              return Card(color: Colors.white, clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(color: c, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: Row(children: [
                  Text('#${t.number.toString().padLeft(6, '0')}', style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(width: 8),
                  Text(_estado(t.status), style: TextStyle(color: fg.withOpacity(0.8), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                  const Spacer(), Icon(Icons.timer_outlined, color: fg, size: 16), const SizedBox(width: 4),
                  ValueListenableBuilder<DateTime>(valueListenable: _ahora, builder: (_, ahora, __) => Text(_elapsed(t.sentAt, ahora),
                      style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()]))),
                ])),
                Padding(padding: const EdgeInsets.fromLTRB(14, 10, 14, 2), child: Row(children: [
                  Expanded(child: Text(t.table != null ? 'MESA ${t.table}' : (t.takeawayName != null ? 'LLEVAR - ${t.takeawayName}' : 'PARA LLEVAR'),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
                  if (t.adicion) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: kAmber, borderRadius: BorderRadius.circular(99)),
                      child: const Text('ADICION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: kInk))),
                ])),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text(t.waiter, style: const TextStyle(fontSize: 12.5, color: kMuted))),
                const Divider(height: 10),
                Expanded(child: ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                  for (final l in t.lines) ...[
                    Text('${l.qty}  ${l.name}${l.size != null ? ' (${l.size})' : ''}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    for (final e in l.extras) Text('   + $e', style: const TextStyle(fontSize: 12.5, color: Color(0xFF2E7D32))),
                    for (final q in l.quita) Text('   - Sin $q', style: const TextStyle(fontSize: 12.5, color: Colors.red)),
                    if (l.note != null) Text('   * ${l.note}', style: const TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic)),
                    const SizedBox(height: 3),
                  ],
                  if (t.note != null) ...[const Divider(), Text('OBS: ${t.note}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5))],
                  if (t.reprinted) const Center(child: Text('** REIMPRESION **', style: TextStyle(fontWeight: FontWeight.bold))),
                ])),
                Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  IconButton(tooltip: 'Reimprimir', icon: const Icon(Icons.print), onPressed: () {
                    store.reprint(t);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marcada como reimpresa')));
                  }),
                  if (store.currentUserRole == 'admin')
                    IconButton(tooltip: 'Anular', icon: const Icon(Icons.cancel, color: Colors.red), onPressed: () => _anular(t)),
                ]),
                Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 8), child: SizedBox(width: double.infinity, child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: c, foregroundColor: fg), onPressed: () => store.advance(t),
                  child: Text(switch (t.status) { 'nueva' => 'Empezar a preparar', 'preparando' => 'Marcar lista', 'lista' => 'Marcar entregada', _ => t.status })))),
              ]));
            },
          );
        });
        if (!esAncho(context)) return grid;
        // Pantalla ancha (monitor de cocina): conteo por estado arriba de las comandas.
        int n(String e) => list.where((t) => t.status == e).length;
        Widget dato(Color c, String txt) => Container(
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(99)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 9, height: 9, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(txt, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5)),
              ]),
            );
        return Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Row(children: [
            const Text('Comandas en curso', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(width: 18),
            dato(_c('nueva'), n('nueva') == 1 ? '1 nueva' : '${n('nueva')} nuevas'),
            dato(_c('preparando'), '${n('preparando')} preparando'),
            dato(_c('lista'), n('lista') == 1 ? '1 lista' : '${n('lista')} listas'),
          ])),
          Expanded(child: grid),
        ]);
      }),
    );
  }
}

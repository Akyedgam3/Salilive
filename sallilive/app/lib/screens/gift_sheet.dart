import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'wallet_screen.dart';

void showGiftSheet(
  BuildContext context, {
  required String roomId,
  required List<Map<String, dynamic>> receivers,
  String? initial,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _GiftSheet(roomId: roomId, receivers: receivers, initial: initial),
  );
}

class _GiftSheet extends StatefulWidget {
  final String roomId;
  final List<Map<String, dynamic>> receivers;
  final String? initial;
  const _GiftSheet({required this.roomId, required this.receivers, this.initial});

  @override
  State<_GiftSheet> createState() => _GiftSheetState();
}

class _GiftSheetState extends State<_GiftSheet> {
  List<Map<String, dynamic>> _gifts = [];
  Map<String, dynamic>? _gift;
  String? _to;
  int _qty = 1;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _to = widget.initial ?? (widget.receivers.isNotEmpty ? widget.receivers.first['id'] : null);
    sb.from('gifts').select().eq('active', true).order('sort').then((r) {
      if (mounted) setState(() => _gifts = List<Map<String, dynamic>>.from(r));
    });
  }

  Future<void> _send() async {
    if (_gift == null || _to == null) return;
    setState(() => _busy = true);
    try {
      await sb.rpc('send_gift', params: {
        'p_room': widget.roomId,
        'p_receiver': _to,
        'p_gift': _gift!['id'],
        'p_qty': _qty,
      });
      await Me.refresh();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        snack(context, errText(e));
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * .62,
          child: Column(children: [
            const SizedBox(height: 14),
            if (widget.receivers.isEmpty)
              const Padding(padding: EdgeInsets.all(12), child: Text('لا يوجد أحد على المايك لإرسال هدية له'))
            else
              SizedBox(
                height: 56,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final u in widget.receivers)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: GestureDetector(
                          onTap: () => setState(() => _to = u['id']),
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: _to == u['id'] ? kGradient : null,
                            ),
                            child: Avatar(url: u['avatar_url'], name: u['name'], radius: 22),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  childAspectRatio: .8,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: _gifts.length,
                itemBuilder: (_, i) {
                  final g = _gifts[i];
                  final sel = _gift?['id'] == g['id'];
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => setState(() => _gift = g),
                    child: Container(
                      decoration: BoxDecoration(
                        color: kBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: sel ? kPink : Colors.transparent, width: 2),
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        GiftIcon(g['icon'], size: 40),
                        const SizedBox(height: 4),
                        Text(g['name'], style: const TextStyle(fontSize: 11)),
                        Text('🪙 ${g['price']}', style: const TextStyle(fontSize: 11, color: kOrange)),
                      ]),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(children: [
                InkWell(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen())),
                  child: ValueListenableBuilder(
                    valueListenable: Me.wallet,
                    builder: (_, __, ___) => Text('🪙 ${Me.coins}  +', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const Spacer(),
                for (final q in [1, 5, 10])
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: ChoiceChip(label: Text('x$q'), selected: _qty == q, onSelected: (_) => setState(() => _qty = q)),
                  ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 100,
                  child: GradientButton(
                    text: 'إرسال',
                    loading: _busy,
                    onTap: _gift == null || _to == null ? null : _send,
                  ),
                ),
              ]),
            ),
          ]),
        ),
      );
}

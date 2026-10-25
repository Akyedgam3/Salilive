import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  List<Map<String, dynamic>> _packages = [];
  List<Map<String, dynamic>> _methods = [];
  List<Map<String, dynamic>> _requests = [];

  @override
  void initState() {
    super.initState();
    Me.refresh();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([
        sb.from('coin_packages').select().eq('active', true).order('sort'),
        sb.from('payment_methods').select().eq('active', true).order('sort'),
        sb.from('recharge_requests').select().eq('user_id', myId!).order('created_at', ascending: false).limit(20),
      ]);
      if (!mounted) return;
      setState(() {
        _packages = List<Map<String, dynamic>>.from(r[0]);
        _methods = List<Map<String, dynamic>>.from(r[1]);
        _requests = List<Map<String, dynamic>>.from(r[2]);
      });
    } catch (e) {
      if (mounted) snack(context, errText(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('المحفظة')),
        body: RefreshIndicator(
          onRefresh: () async {
            await Me.refresh();
            await _load();
          },
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(gradient: kGradient, borderRadius: BorderRadius.circular(20)),
              child: ValueListenableBuilder(
                valueListenable: Me.wallet,
                builder: (_, w, __) => Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  _bal('🪙 كوينز', '${w?['coins'] ?? 0}'),
                  _bal('💎 ماس', '${w?['diamonds'] ?? 0}'),
                ]),
              ),
            ),
            const SizedBox(height: 18),
            const Text('اشحن كوينز', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              childAspectRatio: 1.7,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              children: [for (final p in _packages) _packageCard(p)],
            ),
            if (_requests.isNotEmpty) ...[
              const SizedBox(height: 22),
              const Text('طلباتي', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              for (final r in _requests) _requestTile(r),
            ],
          ]),
        ),
      );

  Widget _bal(String t, String v) => Column(children: [
        Text(t, style: const TextStyle(color: Colors.white70)),
        Text(v, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
      ]);

  Widget _packageCard(Map<String, dynamic> p) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _checkout(p),
        child: Container(
          decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(16)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('🪙 ${p['coins']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            if ((p['bonus'] as num) > 0)
              Text('+${p['bonus']} هدية', style: const TextStyle(color: kOrange, fontSize: 12)),
            const SizedBox(height: 4),
            Text('${p['price']} ${p['currency']}', style: const TextStyle(color: kPink, fontWeight: FontWeight.bold)),
          ]),
        ),
      );

  Widget _requestTile(Map<String, dynamic> r) {
    const label = {'pending': 'قيد المراجعة', 'approved': 'تمت الإضافة', 'rejected': 'مرفوض'};
    final color = {'pending': Colors.amber, 'approved': Colors.green, 'rejected': Colors.red}[r['status']] ?? Colors.grey;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('🪙 ${r['coins']}  •  ${r['amount']} ${r['currency']}'),
      subtitle: Text('${r['method_name'] ?? ''}${(r['note'] ?? '').toString().isNotEmpty ? '\n${r['note']}' : ''}'),
      trailing: Chip(label: Text(label[r['status']] ?? ''), backgroundColor: color.withOpacity(.25)),
    );
  }

  void _checkout(Map<String, dynamic> pkg) {
    if (_methods.isEmpty) return snack(context, 'لا توجد طرق دفع متاحة حالياً');
    var method = _methods.first;
    final ref = TextEditingController();
    XFile? receipt;
    var busy = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('🪙 ${pkg['coins']}  —  ${pkg['price']} ${pkg['currency']}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text('اختر طريقة الدفع'),
              for (final m in _methods)
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: m['id'],
                  groupValue: method['id'],
                  onChanged: (_) => setS(() => method = m),
                  title: Text(m['name']),
                ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(12)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: SelectableText(method['details'] ?? '')),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: method['details'] ?? ''));
                      snack(ctx, 'تم النسخ');
                    },
                  ),
                ]),
              ),
              const SizedBox(height: 10),
              const Text('حوّل المبلغ ثم أرفق صورة الإيصال:'),
              const SizedBox(height: 8),
              TextField(controller: ref, decoration: const InputDecoration(hintText: 'رقم العملية / اسم المحوِّل (اختياري)')),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1600);
                  if (f != null) setS(() => receipt = f);
                },
                icon: Icon(receipt == null ? Icons.attach_file : Icons.check_circle, color: receipt == null ? null : Colors.green),
                label: Text(receipt == null ? 'إرفاق صورة الإيصال' : 'تم اختيار الإيصال'),
              ),
              const SizedBox(height: 14),
              GradientButton(
                text: 'إرسال الطلب',
                loading: busy,
                onTap: () async {
                  if (receipt == null) return snack(ctx, 'أرفق صورة الإيصال');
                  setS(() => busy = true);
                  try {
                    final path = await uploadImage('receipts', receipt!);
                    await sb.rpc('request_recharge', params: {
                      'p_package': pkg['id'],
                      'p_method': method['id'],
                      'p_reference': ref.text.trim(),
                      'p_receipt': path,
                    });
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    if (mounted) snack(context, 'تم إرسال طلبك. ستضاف الكوينز بعد المراجعة');
                    _load();
                  } catch (e) {
                    if (ctx.mounted) snack(ctx, errText(e));
                    setS(() => busy = false);
                  }
                },
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'wallet_screen.dart';

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  Future<void> _changeAvatar(BuildContext context) async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 800);
    if (f == null) return;
    try {
      final path = await uploadImage('avatars', f);
      await sb.from('profiles').update({'avatar_url': publicUrl('avatars', path)}).eq('id', myId!);
      await Me.refresh();
    } catch (e) {
      if (context.mounted) snack(context, errText(e));
    }
  }

  Future<void> _editField(BuildContext context, String field, String title, String current) async {
    final c = TextEditingController(text: current);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, maxLength: field == 'bio' ? 120 : 30, maxLines: field == 'bio' ? 3 : 1),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('حفظ')),
        ],
      ),
    );
    if (v == null || (field == 'name' && v.isEmpty)) return;
    try {
      await sb.from('profiles').update({field: v}).eq('id', myId!);
      await Me.refresh();
    } catch (e) {
      if (context.mounted) snack(context, errText(e));
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: ValueListenableBuilder<Map<String, dynamic>?>(
          valueListenable: Me.profile,
          builder: (context, p, _) {
            if (p == null) return const Center(child: CircularProgressIndicator());
            return ListView(padding: const EdgeInsets.all(20), children: [
              Center(
                child: GestureDetector(
                  onTap: () => _changeAvatar(context),
                  child: Stack(children: [
                    Avatar(url: p['avatar_url'], name: p['name'], radius: 52),
                    const Positioned(
                      bottom: 0,
                      right: 0,
                      child: CircleAvatar(radius: 16, backgroundColor: kPink, child: Icon(Icons.camera_alt, size: 16, color: Colors.white)),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(p['name'], style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _editField(context, 'name', 'الاسم', p['name'])),
                LevelBadge(p['wealth'] ?? 0),
              ]),
              Center(
                child: InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: '${p['display_id']}'));
                    snack(context, 'تم نسخ الـ ID');
                  },
                  child: Text('ID: ${p['display_id']}  ⧉', style: const TextStyle(color: Colors.white54)),
                ),
              ),
              const SizedBox(height: 18),
              _tile(Icons.account_balance_wallet, 'المحفظة وشحن الكوينز',
                  trailing: ValueListenableBuilder(
                    valueListenable: Me.wallet,
                    builder: (_, __, ___) => Text('🪙 ${Me.coins}'),
                  ),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()))),
              _tile(Icons.info_outline, (p['bio'] ?? '').toString().isEmpty ? 'أضف نبذة عنك' : p['bio'],
                  onTap: () => _editField(context, 'bio', 'النبذة', p['bio'] ?? '')),
              _tile(Icons.logout, 'تسجيل الخروج', onTap: () async {
                Me.profile.value = null;
                Me.wallet.value = null;
                await sb.auth.signOut();
              }),
            ]);
          },
        ),
      );

  Widget _tile(IconData i, String t, {Widget? trailing, VoidCallback? onTap}) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(16)),
        child: ListTile(leading: Icon(i, color: kPink), title: Text(t), trailing: trailing, onTap: onTap),
      );
}

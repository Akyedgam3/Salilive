import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api.dart';
import '../widgets.dart';

void showUserSheet(
  BuildContext context,
  String userId, {
  VoidCallback? onGift,
  List<Widget> extra = const [],
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _UserSheet(userId: userId, onGift: onGift, extra: extra),
  );
}

class _UserSheet extends StatefulWidget {
  final String userId;
  final VoidCallback? onGift;
  final List<Widget> extra;
  const _UserSheet({required this.userId, this.onGift, this.extra = const []});

  @override
  State<_UserSheet> createState() => _UserSheetState();
}

class _UserSheetState extends State<_UserSheet> {
  Map<String, dynamic>? _u;
  int _followers = 0;
  int _following = 0;
  bool _isFollowing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.userId;
    final r = await Future.wait([
      sb.from('profiles').select().eq('id', id).single(),
      sb.from('follows').select('follower').eq('following', id).count(CountOption.exact),
      sb.from('follows').select('following').eq('follower', id).count(CountOption.exact),
      sb.from('follows').select('follower').eq('follower', myId!).eq('following', id),
    ]);
    if (!mounted) return;
    setState(() {
      _u = r[0] as Map<String, dynamic>;
      _followers = (r[1] as dynamic).count as int;
      _following = (r[2] as dynamic).count as int;
      _isFollowing = (r[3] as List).isNotEmpty;
    });
  }

  Future<void> _toggleFollow() async {
    try {
      if (_isFollowing) {
        await sb.from('follows').delete().eq('follower', myId!).eq('following', widget.userId);
      } else {
        await sb.from('follows').insert({'follower': myId, 'following': widget.userId});
      }
      _load();
    } catch (e) {
      if (mounted) snack(context, errText(e));
    }
  }

  Future<void> _report() async {
    final c = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إبلاغ عن مستخدم'),
        content: TextField(controller: c, maxLines: 3, decoration: const InputDecoration(hintText: 'سبب البلاغ')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('إرسال')),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) return;
    try {
      await sb.from('reports').insert({'reporter_id': myId, 'target_id': widget.userId, 'reason': reason});
      if (mounted) snack(context, 'تم إرسال البلاغ');
    } catch (e) {
      if (mounted) snack(context, errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = _u;
    if (u == null) return const SizedBox(height: 240, child: Center(child: CircularProgressIndicator()));
    final me = widget.userId == myId;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Avatar(url: u['avatar_url'], name: u['name'], radius: 40),
          const SizedBox(height: 8),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(u['name'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            LevelBadge(u['wealth'] ?? 0),
          ]),
          Text('ID: ${u['display_id']}', style: const TextStyle(color: Colors.white54)),
          if ((u['bio'] ?? '').toString().isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(u['bio'], textAlign: TextAlign.center)),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _stat('متابِعون', _followers),
            _stat('يتابع', _following),
          ]),
          const SizedBox(height: 14),
          if (!me)
            Row(children: [
              Expanded(
                child: GradientButton(text: _isFollowing ? 'إلغاء المتابعة' : 'متابعة', onTap: _toggleFollow),
              ),
              if (widget.onGift != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onGift!();
                    },
                    icon: const Icon(Icons.card_giftcard),
                    label: const Text('هدية'),
                  ),
                ),
              ],
            ]),
          ...widget.extra,
          if (!me) TextButton.icon(onPressed: _report, icon: const Icon(Icons.flag, size: 16), label: const Text('إبلاغ')),
        ]),
      ),
    );
  }

  Widget _stat(String t, int n) => Column(children: [
        Text('$n', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(t, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ]);
}

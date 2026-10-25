import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient get sb => Supabase.instance.client;
String? get myId => sb.auth.currentUser?.id;

/// Cached profile + wallet of the signed-in user.
class Me {
  static final profile = ValueNotifier<Map<String, dynamic>?>(null);
  static final wallet = ValueNotifier<Map<String, dynamic>?>(null);

  static Future<void> refresh() async {
    final id = myId;
    if (id == null) return;
    profile.value = await sb.from('profiles').select().eq('id', id).single();
    wallet.value = await sb.from('wallets').select().eq('user_id', id).single();
  }

  static int get coins => (wallet.value?['coins'] as num?)?.toInt() ?? 0;
}

const _errors = {
  'insufficient_coins': 'رصيدك غير كافٍ، اشحن كوينز أولاً',
  'seat_unavailable': 'المقعد غير متاح',
  'room_closed': 'الغرفة مغلقة',
  'banned': 'حسابك محظور',
  'self_gift': 'لا يمكنك إهداء نفسك',
  'too_many_pending': 'عندك طلبات شحن معلّقة كثيرة، انتظر المراجعة',
  'forbidden': 'غير مسموح',
  'Invalid login credentials': 'البريد أو كلمة المرور غير صحيحة',
  'User already registered': 'هذا البريد مسجّل مسبقاً',
  'Password should be': 'كلمة المرور قصيرة (6 أحرف على الأقل)',
};

String errText(Object e) {
  final String m;
  if (e is PostgrestException) {
    m = e.message;
  } else if (e is AuthException) {
    m = e.message;
  } else if (e is FunctionException) {
    m = '${e.details ?? e.reasonPhrase ?? ''}';
  } else {
    m = e.toString();
  }
  for (final k in _errors.keys) {
    if (m.contains(k)) return _errors[k]!;
  }
  return m;
}

/// Uploads [f] to [bucket]/<uid>/<timestamp>.<ext> and returns the storage path.
Future<String> uploadImage(String bucket, XFile f) async {
  final bytes = await f.readAsBytes();
  var ext = f.path.split('.').last.toLowerCase();
  if (ext.length > 4) ext = 'jpg';
  final path = '$myId/${DateTime.now().millisecondsSinceEpoch}.$ext';
  await sb.storage.from(bucket).uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(upsert: true, contentType: 'image/${ext == 'jpg' ? 'jpeg' : ext}'),
      );
  return path;
}

String publicUrl(String bucket, String path) => sb.storage.from(bucket).getPublicUrl(path);

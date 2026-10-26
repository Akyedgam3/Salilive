import 'dart:async';
import 'dart:convert';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'gift_sheet.dart';
import 'user_sheet.dart';

class RoomScreen extends StatefulWidget {
  final Map<String, dynamic> room;
  const RoomScreen({super.key, required this.room});

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  late final String roomId = widget.room['id'];
  late final bool isOwner = widget.room['owner_id'] == myId;

  RtcEngine? _engine;
  RealtimeChannel? _ch;
  Timer? _ping;
  Timer? _giftTimer;

  List<Map<String, dynamic>> seats = [];
  final msgs = <Map<String, dynamic>>[];
  final _profiles = <String, Map<String, dynamic>>{};
  final speaking = <int>{};
  int listeners = 1;
  int _myUid = 0;
  bool _publishing = false;
  bool selfMuted = false;
  bool _closing = false;
  String? audioError;
  Map<String, dynamic>? giftAnim;

  final _input = TextEditingController();
  final _scroll = ScrollController();

  int get mySeat => seats.indexWhere((s) => s['user_id'] == myId);

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      await Me.refresh();
      await _loadSeats();
      await _loadMsgs();
      _subscribe();
      _ping = Timer.periodic(const Duration(seconds: 30), (_) => _pingNow());
    } catch (e) {
      if (mounted) snack(context, errText(e));
    }
    try {
      await _joinAudio();
    } catch (e) {
      if (mounted) setState(() => audioError = errText(e));
    }
  }

  Future<void> _pingNow() async {
    try {
      await sb.rpc('room_ping', params: {'p_room': roomId});
    } catch (_) {}
  }

  // ---------------- data ----------------
  Future<void> _loadSeats() async {
    final rows = await sb
        .from('room_seats')
        .select('*, user:profiles(id,display_id,name,avatar_url)')
        .eq('room_id', roomId)
        .order('seat_no');
    if (!mounted) return;
    setState(() => seats = List<Map<String, dynamic>>.from(rows));
    _syncRole();
  }

  Future<void> _loadMsgs() async {
    final rows = await sb
        .from('room_messages')
        .select('*, user:profiles(id,name,avatar_url,display_id,wealth)')
        .eq('room_id', roomId)
        .order('id', ascending: false)
        .limit(40);
    final list = List<Map<String, dynamic>>.from(rows).reversed.toList();
    for (final m in list) {
      final u = m['user'];
      if (u != null) _profiles[m['user_id']] = Map<String, dynamic>.from(u);
    }
    if (!mounted) return;
    setState(() => msgs
      ..clear()
      ..addAll(list));
    _scrollDown();
  }

  void _subscribe() {
    PostgresChangeFilter roomFilter(String col) =>
        PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: col, value: roomId);

    _ch = sb
        .channel('room:$roomId', opts: RealtimeChannelConfig(key: myId ?? ''))
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'room_seats',
          filter: roomFilter('room_id'),
          callback: (_) => _loadSeats(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'room_messages',
          filter: roomFilter('room_id'),
          callback: (p) => _onMsg(Map<String, dynamic>.from(p.newRecord)),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'rooms',
          filter: roomFilter('id'),
          callback: (p) {
            if (p.newRecord['is_live'] == false) _roomClosed();
          },
        )
        .onPresenceSync((_) {
          if (mounted) setState(() => listeners = _ch?.presenceState().length ?? 1);
        })
        .subscribe((status, [error]) async {
          if (status == RealtimeSubscribeStatus.subscribed) {
            await _ch?.track({'uid': myId});
          }
        });
  }

  Future<void> _onMsg(Map<String, dynamic> r) async {
    final uid = r['user_id'] as String;
    var u = _profiles[uid];
    if (u == null) {
      try {
        u = Map<String, dynamic>.from(
            await sb.from('profiles').select('id,name,avatar_url,display_id,wealth').eq('id', uid).single());
        _profiles[uid] = u;
      } catch (_) {}
    }
    r['user'] = u;
    if (!mounted) return;
    setState(() {
      msgs.add(r);
      if (msgs.length > 120) msgs.removeAt(0);
    });
    if (r['kind'] == 'gift') _showGift(r);
    _scrollDown();
  }

  void _showGift(Map<String, dynamic> m) {
    try {
      final g = jsonDecode(m['content']) as Map<String, dynamic>;
      setState(() => giftAnim = {'id': m['id'], 'icon': g['icon'], 'text': '${m['user']?['name'] ?? ''} ← ${g['gift']} x${g['qty']} ← ${g['to']}'});
      _giftTimer?.cancel();
      _giftTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => giftAnim = null);
      });
    } catch (_) {}
  }

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });

  void _roomClosed() {
    if (_closing || !mounted) return;
    _closing = true;
    if (!isOwner) snack(context, 'أغلق المضيف الغرفة');
    Navigator.of(context).maybePop();
  }

  // ---------------- audio ----------------
  Future<void> _joinAudio() async {
    final res = await sb.functions.invoke('agora-token', body: {'room_id': roomId});
    final d = Map<String, dynamic>.from(res.data as Map);
    if (d['error'] != null) throw d['error'];
    _myUid = (d['uid'] as num).toInt();

    final e = createAgoraRtcEngine();
    await e.initialize(RtcEngineContext(
      appId: d['app_id'] as String,
      channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
    ));
    e.registerEventHandler(RtcEngineEventHandler(
      onAudioVolumeIndication: (conn, list, n, total) {
        final s = <int>{};
        for (final x in list) {
          if ((x.volume ?? 0) > 30) s.add((x.uid ?? 0) == 0 ? _myUid : x.uid!);
        }
        if (mounted) {
          setState(() => speaking
            ..clear()
            ..addAll(s));
        }
      },
    ));
    _engine = e;
    await e.enableAudio();
    await e.enableAudioVolumeIndication(interval: 300, smooth: 3, reportVad: true);
    await e.joinChannel(
      token: d['token'] as String,
      channelId: roomId,
      uid: _myUid,
      options: const ChannelMediaOptions(
        clientRoleType: ClientRoleType.clientRoleAudience,
        channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        autoSubscribeAudio: true,
        publishMicrophoneTrack: false,
      ),
    );
    await e.setEnableSpeakerphone(true);
    await _syncRole();
  }

  /// Makes the Agora role match the seat state (seated = speaker, otherwise listener).
  Future<void> _syncRole() async {
    final e = _engine;
    if (e == null) return;
    final i = mySeat;
    final seated = i >= 0;
    try {
      if (seated && !(await Permission.microphone.request()).isGranted) {
        if (mounted) snack(context, 'يلزم السماح باستخدام الميكروفون');
        return;
      }
      if (seated != _publishing) {
        _publishing = seated;
        await e.updateChannelMediaOptions(ChannelMediaOptions(
          clientRoleType: seated ? ClientRoleType.clientRoleBroadcaster : ClientRoleType.clientRoleAudience,
          publishMicrophoneTrack: seated,
        ));
      }
      if (seated) {
        final forced = seats[i]['muted'] == true;
        await e.muteLocalAudioStream(forced || selfMuted);
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  // ---------------- actions ----------------
  Future<void> _rpc(String fn, Map<String, dynamic> params) async {
    try {
      await sb.rpc(fn, params: params);
    } catch (e) {
      if (mounted) snack(context, errText(e));
    }
  }

  Future<void> _sendText() async {
    final t = _input.text.trim();
    if (t.isEmpty) return;
    _input.clear();
    try {
      await sb.from('room_messages').insert({'room_id': roomId, 'user_id': myId, 'content': t});
    } catch (e) {
      if (mounted) snack(context, errText(e));
    }
  }

  void _sheet(List<(String, IconData, VoidCallback)> acts) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final a in acts)
            ListTile(
              leading: Icon(a.$2),
              title: Text(a.$1),
              onTap: () {
                Navigator.pop(ctx);
                a.$3();
              },
            ),
        ]),
      ),
    );
  }

  void _seatTap(Map<String, dynamic> s) {
    final n = s['seat_no'] as int;
    final uid = s['user_id'];
    final locked = s['locked'] == true;
    if (uid == null) {
      if (isOwner) {
        _sheet([
          if (!locked) ('الصعود للمايك', Icons.mic, () => _rpc('take_seat', {'p_room': roomId, 'p_seat': n})),
          if (!locked && n != 0) ('قفل المقعد', Icons.lock, () => _rpc('manage_seat', {'p_room': roomId, 'p_seat': n, 'p_action': 'lock'})),
          if (locked) ('فتح المقعد', Icons.lock_open, () => _rpc('manage_seat', {'p_room': roomId, 'p_seat': n, 'p_action': 'unlock'})),
        ]);
      } else if (locked) {
        snack(context, 'المقعد مقفل');
      } else {
        _rpc('take_seat', {'p_room': roomId, 'p_seat': n});
      }
    } else if (uid == myId) {
      _sheet([
        (selfMuted ? 'تشغيل المايك' : 'كتم المايك', selfMuted ? Icons.mic : Icons.mic_off, _toggleMute),
        if (!(isOwner && n == 0)) ('النزول من المايك', Icons.logout, () => _rpc('leave_seat', {'p_room': roomId})),
      ]);
    } else {
      showUserSheet(
        context,
        uid,
        onGift: () => _openGifts(uid),
        extra: isOwner
            ? [
                ListTile(
                  leading: Icon(s['muted'] == true ? Icons.mic : Icons.mic_off),
                  title: Text(s['muted'] == true ? 'السماح بالكلام' : 'كتم'),
                  onTap: () {
                    Navigator.pop(context);
                    _rpc('manage_seat', {'p_room': roomId, 'p_seat': n, 'p_action': s['muted'] == true ? 'unmute' : 'mute'});
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.person_remove),
                  title: const Text('إنزال من المايك'),
                  onTap: () {
                    Navigator.pop(context);
                    _rpc('manage_seat', {'p_room': roomId, 'p_seat': n, 'p_action': 'kick'});
                  },
                ),
              ]
            : const [],
      );
    }
  }

  Future<void> _toggleMute() async {
    selfMuted = !selfMuted;
    await _syncRole();
  }

  void _openGifts([String? receiver]) {
    final users = [
      for (final s in seats)
        if (s['user'] != null && s['user_id'] != myId) Map<String, dynamic>.from(s['user']),
    ];
    showGiftSheet(context, roomId: roomId, receivers: users, initial: receiver);
  }

  Future<void> _exit() async {
    if (!isOwner) return Navigator.of(context).pop();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إغلاق الغرفة؟'),
        content: const Text('سيتم إنهاء البث لجميع المستمعين.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إغلاق')),
        ],
      ),
    );
    if (ok != true) return;
    _closing = true;
    await _rpc('close_room', {'p_room': roomId});
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _ping?.cancel();
    _giftTimer?.cancel();
    final ch = _ch;
    final e = _engine;
    () async {
      try {
        if (ch != null) await sb.removeChannel(ch);
        if (e != null) {
          await e.leaveChannel();
          await e.release();
        }
        if (!isOwner) await sb.rpc('leave_seat', params: {'p_room': roomId});
      } catch (_) {}
    }();
    super.dispose();
  }

  // ---------------- ui ----------------
  @override
  Widget build(BuildContext context) {
    final cols = 4;
    return PopScope(
      canPop: !isOwner,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit();
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF2A0F4A), kBg],
            ),
          ),
          child: SafeArea(
            child: Stack(children: [
              Column(children: [
                _header(),
                if (audioError != null)
                  Container(
                    width: double.infinity,
                    color: Colors.red.withOpacity(.25),
                    padding: const EdgeInsets.all(6),
                    child: Text('الصوت غير متاح: $audioError', style: const TextStyle(fontSize: 11), textAlign: TextAlign.center),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: cols,
                    childAspectRatio: .85,
                    children: [
                      for (final s in seats)
                        _SeatTile(
                          seat: s,
                          speaking: s['user'] != null && speaking.contains((s['user']['display_id'] as num).toInt()),
                          micOff: s['muted'] == true || (s['user_id'] == myId && selfMuted),
                          onTap: () => _seatTap(s),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(16)),
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(10),
                      itemCount: msgs.length,
                      itemBuilder: (_, i) => _msgTile(msgs[i]),
                    ),
                  ),
                ),
                _bottomBar(),
              ]),
              if (giftAnim != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: TweenAnimationBuilder<double>(
                        key: ValueKey(giftAnim!['id']),
                        tween: Tween(begin: .3, end: 1),
                        duration: const Duration(milliseconds: 700),
                        curve: Curves.elasticOut,
                        builder: (_, v, child) => Transform.scale(scale: v, child: child),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          GiftIcon(giftAnim!['icon'] ?? '🎁', size: 130),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(99)),
                            child: Text(giftAnim!['text'], style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
        child: Row(children: [
          IconButton(icon: const Icon(Icons.keyboard_arrow_down, size: 30), onPressed: _exit),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.room['title'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text('ID ${widget.room['id'].toString().substring(0, 6)}', style: const TextStyle(fontSize: 11, color: Colors.white54)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(99)),
            child: Row(children: [const Icon(Icons.headphones, size: 14), Text(' $listeners')]),
          ),
          const SizedBox(width: 6),
        ]),
      );

  Widget _bottomBar() {
    final seated = mySeat >= 0;
    final micOff = selfMuted || (seated && seats[mySeat]['muted'] == true);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _input,
            maxLength: 200,
            onSubmitted: (_) => _sendText(),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'اكتب رسالة…',
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(99), borderSide: BorderSide.none),
              suffixIcon: IconButton(icon: const Icon(Icons.send, color: kPink), onPressed: _sendText),
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (seated)
          _roundBtn(micOff ? Icons.mic_off : Icons.mic, micOff ? Colors.red : Colors.green, _toggleMute),
        const SizedBox(width: 8),
        _roundBtn(Icons.card_giftcard, kPink, () => _openGifts()),
      ]),
    );
  }

  Widget _roundBtn(IconData i, Color c, VoidCallback f) => InkWell(
        onTap: f,
        customBorder: const CircleBorder(),
        child: CircleAvatar(radius: 22, backgroundColor: c, child: Icon(i, color: Colors.white)),
      );

  Widget _msgTile(Map<String, dynamic> m) {
    final u = m['user'] as Map<String, dynamic>?;
    final name = u?['name'] ?? '';
    if (m['kind'] == 'gift') {
      try {
        final g = jsonDecode(m['content']) as Map<String, dynamic>;
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: kPink.withOpacity(.2), borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: Text('$name أهدى ${g['to']} ', style: const TextStyle(fontSize: 13))),
            GiftIcon(g['icon'] ?? '🎁', size: 22),
            Text(' x${g['qty']}', style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
        );
      } catch (_) {
        return const SizedBox.shrink();
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text.rich(TextSpan(children: [
        TextSpan(text: '$name: ', style: const TextStyle(color: kPink, fontWeight: FontWeight.bold)),
        TextSpan(text: m['content']),
      ])),
    );
  }
}

class _SeatTile extends StatelessWidget {
  final Map<String, dynamic> seat;
  final bool speaking;
  final bool micOff;
  final VoidCallback onTap;
  const _SeatTile({required this.seat, required this.speaking, required this.micOff, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final u = seat['user'] as Map<String, dynamic>?;
    final locked = seat['locked'] == true;
    final host = seat['seat_no'] == 0;
    return InkWell(
      onTap: onTap,
      child: Column(children: [
        Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: speaking ? kGradient : null,
              color: speaking ? null : Colors.white12,
            ),
            child: u != null
                ? Avatar(url: u['avatar_url'], name: u['name'], radius: 28)
                : CircleAvatar(
                    radius: 28,
                    backgroundColor: kCard,
                    child: Icon(locked ? Icons.lock : Icons.add, color: Colors.white38),
                  ),
          ),
          if (u != null && micOff)
            const Positioned(
              bottom: 0,
              right: 0,
              child: CircleAvatar(radius: 9, backgroundColor: Colors.red, child: Icon(Icons.mic_off, size: 12, color: Colors.white)),
            ),
          if (host) const Positioned(top: -10, child: Text('👑', style: TextStyle(fontSize: 16))),
        ]),
        const SizedBox(height: 4),
        Text(
          u?['name'] ?? '${(seat['seat_no'] as int) + 1}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11),
        ),
      ]),
    );
  }
}

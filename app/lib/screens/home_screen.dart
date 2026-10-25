import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'profile_tab.dart';
import 'room_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    Me.refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: _tab, children: const [RoomsTab(), ProfileTab()]),
        floatingActionButton: _tab == 0
            ? FloatingActionButton.extended(
                backgroundColor: kPink,
                onPressed: () => showCreateRoom(context),
                icon: const Icon(Icons.mic),
                label: const Text('افتح غرفة'),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          backgroundColor: kCard,
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.graphic_eq), label: 'الغرف'),
            NavigationDestination(icon: Icon(Icons.person), label: 'حسابي'),
          ],
        ),
      );
}

class RoomsTab extends StatefulWidget {
  const RoomsTab({super.key});

  @override
  State<RoomsTab> createState() => _RoomsTabState();
}

class _RoomsTabState extends State<RoomsTab> {
  List<Map<String, dynamic>> _rooms = [];
  List<Map<String, dynamic>> _banners = [];
  String _announcement = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final since = DateTime.now().toUtc().subtract(const Duration(seconds: 90)).toIso8601String();
      final r = await Future.wait([
        sb
            .from('rooms')
            .select('*, owner:profiles(name,avatar_url,display_id), room_seats(user_id)')
            .eq('is_live', true)
            .gt('last_ping', since)
            .order('created_at', ascending: false),
        sb.from('banners').select().eq('active', true).order('sort'),
        sb.from('app_settings').select().eq('key', 'announcement'),
      ]);
      if (!mounted) return;
      setState(() {
        _rooms = List<Map<String, dynamic>>.from(r[0]);
        _banners = List<Map<String, dynamic>>.from(r[1]);
        final a = List<Map<String, dynamic>>.from(r[2]);
        _announcement = a.isEmpty ? '' : (a.first['value'] as String? ?? '');
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        snack(context, errText(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(children: [
                    ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.asset('assets/logo.webp', width: 40)),
                    const SizedBox(width: 10),
                    const Text('SalliLive', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
              if (_banners.isNotEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 130,
                    child: PageView(
                      children: [
                        for (final b in _banners)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: CachedNetworkImage(imageUrl: b['image_url'], fit: BoxFit.cover),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              if (_announcement.isNotEmpty)
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      const Icon(Icons.campaign, color: kOrange),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_announcement, style: const TextStyle(fontSize: 13))),
                    ]),
                  ),
                ),
              if (_loading)
                const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
              else if (_rooms.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: Text('ما في غرف مباشرة الآن\nافتح أول غرفة!', textAlign: TextAlign.center)),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverGrid.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: .95,
                    ),
                    itemCount: _rooms.length,
                    itemBuilder: (_, i) => _RoomCard(_rooms[i], onBack: _load),
                  ),
                ),
            ],
          ),
        ),
      );
}

class _RoomCard extends StatelessWidget {
  final Map<String, dynamic> room;
  final VoidCallback onBack;
  const _RoomCard(this.room, {required this.onBack});

  @override
  Widget build(BuildContext context) {
    final owner = room['owner'] as Map<String, dynamic>? ?? {};
    final seats = List<Map<String, dynamic>>.from(room['room_seats'] ?? []);
    final used = seats.where((s) => s['user_id'] != null).length;
    final cover = (room['cover_url'] as String?) ?? (owner['avatar_url'] as String?);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => RoomScreen(room: room)));
        onBack();
      },
      child: Container(
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(18),
          image: cover != null && cover.isNotEmpty
              ? DecorationImage(image: CachedNetworkImageProvider(cover), fit: BoxFit.cover)
              : null,
          gradient: cover == null || cover.isEmpty ? kGradient : null,
        ),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black87],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(99)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.mic, size: 12, color: kPink),
                  Text(' $used/${room['seat_count']}', style: const TextStyle(fontSize: 11)),
                ]),
              ),
              const SizedBox(height: 6),
              Text(room['title'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(owner['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ],
          ),
        ),
      ),
    );
  }
}

void showCreateRoom(BuildContext context) {
  final title = TextEditingController();
  var seats = 8;
  var busy = false;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('غرفة جديدة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          TextField(controller: title, maxLength: 60, decoration: const InputDecoration(hintText: 'اسم الغرفة')),
          const Text('عدد المقاعد'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final n in [4, 8, 12])
              ChoiceChip(label: Text('$n'), selected: seats == n, onSelected: (_) => setS(() => seats = n)),
          ]),
          const SizedBox(height: 18),
          GradientButton(
            text: 'ابدأ البث',
            loading: busy,
            onTap: () async {
              if (title.text.trim().isEmpty) return snack(ctx, 'اكتب اسم الغرفة');
              setS(() => busy = true);
              try {
                final id = await sb.rpc('create_room', params: {'p_title': title.text, 'p_cover': null, 'p_seats': seats});
                final room = await sb.from('rooms').select().eq('id', id).single();
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (!context.mounted) return;
                Navigator.push(context, MaterialPageRoute(builder: (_) => RoomScreen(room: room)));
              } catch (e) {
                if (ctx.mounted) snack(ctx, errText(e));
                setS(() => busy = false);
              }
            },
          ),
        ]),
      ),
    ),
  );
}

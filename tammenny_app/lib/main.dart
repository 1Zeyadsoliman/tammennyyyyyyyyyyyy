// وصلت؟ طمّني — Flutter client
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const baseUrl = 'https://paver-rumbling-runt.ngrok-free.dev ';

Future<Map<String, dynamic>> api(String path,
    {Map<String, dynamic>? body, bool post = false}) async {
  final uri = Uri.parse('$baseUrl/api$path');
  final r = post
      ? await http
          .post(uri,
              headers: {'Content-Type': 'application/json', 'ngrok-skip-browser-warning': '1'},
              body: jsonEncode(body ?? {}))
          .timeout(const Duration(seconds: 25))
      : await http.get(uri, headers: {'ngrok-skip-browser-warning': '1'}).timeout(const Duration(seconds: 25));
  final d = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  if (r.statusCode >= 400) throw Exception(d['error'] ?? 'حصل خطأ');
  return d;
}

String errText(Object e) => '$e'.replaceFirst('Exception: ', '');

const statusText = {
  'onway': 'في الطريق 🚶',
  'arrived': 'وصل بالسلامة ✅',
  'late': 'اتأخر ⚠️',
  'silent': 'الإشارة مقطوعة 📡',
};

Color statusColor(String s) => switch (s) {
      'arrived' => Colors.green.shade700,
      'late' => Colors.red.shade700,
      'silent' => Colors.orange.shade800,
      _ => Colors.blue.shade700,
    };

String fmt(int ms) {
  final s = ms.abs() ~/ 1000;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  final t = '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  return '${ms < 0 ? '-' : ''}${h > 0 ? '$h:' : ''}$t';
}

String ago(Map? last) {
  if (last == null) return 'لسه مفيش موقع';
  final m = (DateTime.now().millisecondsSinceEpoch - (last['t'] as num)) ~/ 60000;
  return m < 1 ? 'آخر تحديث: دلوقتي' : 'آخر تحديث: من $m دقيقة';
}

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'وصلت؟ طمّني',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFFFF9EC),
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B2A63)).copyWith(
            primary: const Color(0xFF101B3D),
            onPrimary: Colors.white,
            secondaryContainer: const Color(0xFFFFC93C),
            onSecondaryContainer: const Color(0xFF101B3D),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF101B3D),
            foregroundColor: Colors.white,
          ),
        ),
        builder: (c, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: const Home(),
      );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int i = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Column(children: [
            Text('وصلت؟ طمّني 🏠', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('اطمن وطمنهم', style: TextStyle(fontSize: 12)),
          ]),
          centerTitle: true,
        ),
        body: IndexedStack(index: i, children: const [TripTab(), WatchTab(), NewsTab()]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: i,
          onDestinationSelected: (v) => setState(() => i = v),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.directions_walk), label: 'رحلتي'),
            NavigationDestination(icon: Icon(Icons.visibility), label: 'متابعة'),
            NavigationDestination(icon: Icon(Icons.fact_check), label: 'كشف الأخبار'),
          ],
        ),
      );
}

// ---------- كارت الحالة (بيتستخدم في رحلتي والمتابعة) ----------
class StatusCard extends StatelessWidget {
  final Map<String, dynamic> v;
  const StatusCard(this.v, {super.key});
  @override
  Widget build(BuildContext context) {
    final st = v['status'] as String;
    final left = (v['eta'] as num).toInt() - DateTime.now().millisecondsSinceEpoch;
    final route = [v['from'], v['to']].where((x) => x != null && '$x'.isNotEmpty).join(' ← ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Text('${v['name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          if (route.isNotEmpty) Text(route, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 10),
          Chip(
            label: Text(statusText[st] ?? st,
                style: TextStyle(color: statusColor(st), fontWeight: FontWeight.bold)),
          ),
          Text(st == 'arrived' ? '🎉' : fmt(left),
              style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800)),
          Text(st == 'late' ? 'متأخر ${v['lateMinutes']} دقيقة' : ago(v['last'] as Map?),
              style: const TextStyle(color: Colors.grey)),
        ]),
      ),
    );
  }
}

// ---------- رحلتي ----------
class TripTab extends StatefulWidget {
  const TripTab({super.key});
  @override
  State<TripTab> createState() => _TripTabState();
}

class _TripTabState extends State<TripTab> {
  final name = TextEditingController(),
      from = TextEditingController(),
      to = TextEditingController(),
      mins = TextEditingController(text: '45');
  String? id, token, msg;
  Map<String, dynamic>? v;
  bool busy = false;
  StreamSubscription<Position>? sub;
  Timer? tick, poll;
  int lastSent = 0;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _stop();
    for (final c in [name, from, to, mins]) {
      c.dispose();
    }
    super.dispose();
  }

  void _stop() {
    sub?.cancel();
    tick?.cancel();
    poll?.cancel();
    sub = null;
    tick = null;
    poll = null;
  }

  Future<void> _restore() async {
    final p = await SharedPreferences.getInstance();
    id = p.getString('id');
    token = p.getString('token');
    if (id != null) await _run();
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    final m = int.tryParse(mins.text.trim()) ?? 0;
    if (name.text.trim().isEmpty || m < 1) {
      setState(() => msg = 'اكتب اسمك ووقت الوصول بالدقايق');
      return;
    }
    setState(() {
      busy = true;
      msg = null;
    });
    try {
      final r = await api('/trips', post: true, body: {
        'name': name.text, 'from': from.text, 'to': to.text, 'etaMinutes': m,
      });
      id = r['id'] as String;
      token = r['token'] as String;
      final p = await SharedPreferences.getInstance();
      await p.setString('id', id!);
      await p.setString('token', token!);
      await _run();
    } catch (e) {
      msg = errText(e);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _run() async {
    await _refresh();
    poll = Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
    tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    if (v != null && v!['status'] != 'arrived') await _track();
  }

  Future<void> _refresh() async {
    try {
      v = await api('/trips/$id');
      if (v!['status'] == 'arrived') sub?.cancel();
    } catch (e) {
      if ('$e'.contains('مش موجودة')) await _reset();
    }
    if (mounted) setState(() {});
  }

  Future<void> _track() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      setState(() => msg = 'لازم تسمح بإذن الموقع من إعدادات الموبايل');
      return;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      setState(() => msg = 'شغّل الـ GPS في الموبايل');
      return;
    }
    final LocationSettings settings = defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            intervalDuration: const Duration(seconds: 15),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'وصلت؟ طمّني',
              notificationText: 'بنشارك موقعك لحد ما توصل',
              enableWakeLock: true,
            ),
          )
        : AppleSettings(
            accuracy: LocationAccuracy.high,
            allowBackgroundLocationUpdates: true,
            showBackgroundLocationIndicator: true,
          );
    sub = Geolocator.getPositionStream(locationSettings: settings).listen((p) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - lastSent < 15000) return;
      lastSent = now;
      api('/trips/$id/location',
              post: true, body: {'token': token, 'lat': p.latitude, 'lng': p.longitude})
          .catchError((_) => <String, dynamic>{});
    });
  }

  Future<void> _arrived() async {
    try {
      await api('/trips/$id/arrived', post: true, body: {'token': token});
      sub?.cancel();
      await _refresh();
    } catch (e) {
      setState(() => msg = errText(e));
    }
  }

  Future<void> _extend(int m) async {
    try {
      await api('/trips/$id/extend', post: true, body: {'token': token, 'minutes': m});
      await _refresh();
    } catch (e) {
      setState(() => msg = errText(e));
    }
  }

  Future<void> _reset() async {
    _stop();
    final p = await SharedPreferences.getInstance();
    await p.remove('id');
    await p.remove('token');
    id = null;
    token = null;
    v = null;
    msg = null;
    if (mounted) setState(() {});
  }

  Widget _field(TextEditingController c, String label, {bool num = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: num ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (id == null) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        _field(name, 'اسمك'),
        _field(from, 'من (مثلاً: الجامعة)'),
        _field(to, 'إلى (مثلاً: البيت)'),
        _field(mins, 'هوصل كمان كام دقيقة؟', num: true),
        if (msg != null) Text(msg!, style: const TextStyle(color: Colors.red)),
        FilledButton(
          onPressed: busy ? null : _start,
          child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(busy ? 'استنى...' : 'ابدأ الرحلة وشارك الموقع')),
        ),
        const SizedBox(height: 8),
        const Text('الموقع بيتبعت بس طول الرحلة، وبيقف أول ما تدوس "وصلت".',
            style: TextStyle(color: Colors.grey)),
      ]);
    }
    final arrived = v?['status'] == 'arrived';
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (v != null) StatusCard(v!) else const Center(child: CircularProgressIndicator()),
      if (msg != null)
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(msg!, style: const TextStyle(color: Colors.red))),
      if (!arrived) ...[
        FilledButton.icon(
            onPressed: _arrived,
            icon: const Icon(Icons.check_circle),
            label: const Padding(padding: EdgeInsets.all(8), child: Text('وصلت بالسلامة'))),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => _extend(10), child: const Text('+10 دقايق'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton(onPressed: () => _extend(20), child: const Text('+20 دقيقة'))),
        ]),
      ],
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('كود المتابعة', style: TextStyle(fontWeight: FontWeight.bold)),
            SelectableText('$id', style: const TextStyle(fontSize: 22, letterSpacing: 2)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Share.share('تابع رحلتي لحد ما أوصل 🏠\n$baseUrl/t/$id\nأو الكود: $id'),
              icon: const Icon(Icons.share),
              label: const Text('شارك اللينك'),
            ),
          ]),
        ),
      ),
      TextButton(onPressed: _reset, child: const Text('رحلة جديدة')),
    ]);
  }
}

// ---------- متابعة ----------
class WatchTab extends StatefulWidget {
  const WatchTab({super.key});
  @override
  State<WatchTab> createState() => _WatchTabState();
}

class _WatchTabState extends State<WatchTab> {
  final code = TextEditingController();
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: code,
          decoration: const InputDecoration(
              labelText: 'اكتب كود الرحلة أو الصق اللينك', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () {
            final id = code.text.trim().split('/').last;
            if (id.isEmpty) return;
            Navigator.push(context, MaterialPageRoute(builder: (_) => WatchScreen(id)));
          },
          child: const Padding(padding: EdgeInsets.all(8), child: Text('تابع')),
        ),
      ]);
}

class WatchScreen extends StatefulWidget {
  final String id;
  const WatchScreen(this.id, {super.key});
  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  Map<String, dynamic>? v;
  String? err, last;
  Timer? poll, tick;

  @override
  void initState() {
    super.initState();
    _load();
    poll = Timer.periodic(const Duration(seconds: 10), (_) => _load());
    tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    poll?.cancel();
    tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await api('/trips/${widget.id}');
      final st = d['status'] as String;
      if (last != null && last != st && (st == 'late' || st == 'silent' || st == 'arrived')) {
        HapticFeedback.heavyImpact();
        SystemSound.play(SystemSoundType.alert);
      }
      last = st;
      if (mounted) setState(() { v = d; err = null; });
    } catch (e) {
      if (mounted) setState(() => err = errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = v?['status'] as String?;
    final lastLoc = v?['last'] as Map?;
    return Scaffold(
      appBar: AppBar(title: const Text('متابعة الرحلة')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (err != null) Text(err!, style: const TextStyle(color: Colors.red)),
        if (st == 'late' || st == 'silent')
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
                color: Colors.red.shade50,
                border: Border.all(color: Colors.red.shade700),
                borderRadius: BorderRadius.circular(12)),
            child: Text(
              st == 'late'
                  ? '⚠️ ${v!['name']} اتأخر ${v!['lateMinutes']} دقيقة عن الميعاد. جرّب تكلمه.'
                  : '📡 مفيش تحديث للموقع بقاله فترة. اتصل بيه تتطمن.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold),
            ),
          ),
        if (v != null) StatusCard(v!) else if (err == null) const Center(child: CircularProgressIndicator()),
        if (lastLoc != null)
          OutlinedButton.icon(
            onPressed: () => launchUrl(
                Uri.parse('https://www.google.com/maps?q=${lastLoc['lat']},${lastLoc['lng']}'),
                mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.map),
            label: const Text('افتح آخر موقع في الخرائط'),
          ),
      ]),
    );
  }
}

// ---------- كشف الأخبار ----------
class NewsTab extends StatefulWidget {
  const NewsTab({super.key});
  @override
  State<NewsTab> createState() => _NewsTabState();
}

class _NewsTabState extends State<NewsTab> {
  final text = TextEditingController();
  Map<String, dynamic>? r;
  bool busy = false;
  String? err;

  Future<void> _check() async {
    if (text.text.trim().length < 10) {
      setState(() => err = 'اكتب الخبر الأول');
      return;
    }
    setState(() { busy = true; err = null; });
    try {
      r = await api('/factcheck', post: true, body: {'text': text.text});
    } catch (e) {
      err = errText(e);
    }
    if (mounted) setState(() => busy = false);
  }

  List<Widget> _list(String title, dynamic items) => [
        const SizedBox(height: 8),
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        for (final x in (items as List? ?? [])) Text('• $x'),
      ];

  @override
  Widget build(BuildContext context) {
    final verdict = r?['verdict'] as String?;
    final bad = verdict != null && (verdict.contains('كاذب') || verdict.contains('مشكوك'));
    final mid = verdict != null && (verdict.contains('تحقق') || verdict.contains('لا يمكن'));
    final col = bad ? Colors.red.shade700 : mid ? Colors.orange.shade800 : Colors.green.shade700;
    return ListView(padding: const EdgeInsets.all(16), children: [
      TextField(
        controller: text,
        maxLines: 6,
        decoration: const InputDecoration(
            labelText: 'الصق الخبر أو الرسالة اللي وصلتك', border: OutlineInputBorder()),
      ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: busy ? null : _check,
        child: Padding(padding: const EdgeInsets.all(8), child: Text(busy ? 'بنفحص...' : 'افحص الخبر 🔍')),
      ),
      if (err != null) Text(err!, style: const TextStyle(color: Colors.red)),
      if (r != null)
        Card(
          margin: const EdgeInsets.only(top: 12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(verdict ?? '', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: col)),
              Text('نسبة الثقة: ${r!['confidence']}%', style: const TextStyle(color: Colors.grey)),
              ..._list('ليه؟', r!['reasons']),
              ..._list('اتأكد إزاي؟', r!['tips']),
              const SizedBox(height: 8),
              Text('${r!['note'] ?? ''}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ]),
          ),
        ),
    ]);
  }
}

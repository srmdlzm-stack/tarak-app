// tarak - مترجم ملفات PDF من الإنجليزية إلى العربية
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const TarakApp());

class TarakApp extends StatelessWidget {
  const TarakApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'tarak',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        builder: (c, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: const HomePage(),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final cloud = TextEditingController();
  final oracle = TextEditingController();
  final keyCtl = TextEditingController();
  String profile = 'cloud';
  String engine = 'auto';
  String status = 'اختر ملف PDF إنجليزي لترجمته إلى العربية';
  double? progress;
  bool busy = false;

  TextEditingController get cur => profile == 'cloud' ? cloud : oracle;
  Map<String, String> get hdr =>
      keyCtl.text.trim().isEmpty ? {} : {'X-API-Key': keyCtl.text.trim()};

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      cloud.text = p.getString('cloud') ?? '';
      oracle.text = p.getString('oracle') ?? '';
      keyCtl.text = p.getString('key') ?? '';
      profile = p.getString('profile') ?? 'cloud';
      engine = p.getString('engine') ?? 'auto';
      setState(() {});
    });
  }

  Future<void> run() async {
    final base = cur.text.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) {
      setState(() => status = 'أدخل عنوان الخادم المختار أولًا');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cloud', cloud.text.trim());
    await prefs.setString('oracle', oracle.text.trim());
    await prefs.setString('key', keyCtl.text.trim());
    await prefs.setString('profile', profile);
    await prefs.setString('engine', engine);
    final pick = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (pick == null || pick.files.single.path == null) return;
    setState(() {
      busy = true;
      progress = null;
      status = 'جارٍ رفع الملف...';
    });
    try {
      final file = File(pick.files.single.path!);
      final r1 = await http.post(Uri.parse('$base/upload-url'), headers: hdr);
      if (r1.statusCode == 401) throw 'مفتاح الحماية غير صحيح';
      if (r1.statusCode != 200) throw 'خطأ من الخادم (${r1.statusCode})';
      final j = jsonDecode(r1.body);
      final job = j['job'];
      final upUrl = j['upload_url'] as String;
      final up = http.StreamedRequest('PUT', Uri.parse(upUrl))
        ..headers['Content-Type'] = 'application/pdf'
        ..contentLength = await file.length();
      if (upUrl.startsWith(base)) up.headers.addAll(hdr);
      file.openRead().listen(up.sink.add, onDone: up.sink.close);
      final upRes = await up.send();
      if (upRes.statusCode != 200) throw 'فشل الرفع (${upRes.statusCode})';
      await http.post(Uri.parse('$base/process/$job?engine=$engine'),
          headers: hdr);
      while (true) {
        await Future.delayed(const Duration(seconds: 5));
        final st = jsonDecode(
            (await http.get(Uri.parse('$base/status/$job'), headers: hdr))
                .body);
        if (st['state'] == 'error') throw st['error'] ?? 'خطأ في الخادم';
        if (st['state'] == 'done') {
          setState(() {
            status = 'جارٍ تنزيل الملف المترجم...';
            progress = null;
          });
          final dir = await getApplicationDocumentsDirectory();
          final name = pick.files.single.name.replaceAll('.pdf', '_ar.pdf');
          final out = File('${dir.path}/$name');
          final dlUrl = st['download_url'] as String;
          final req = http.Request('GET', Uri.parse(dlUrl));
          if (dlUrl.startsWith(base)) req.headers.addAll(hdr);
          final dl = await http.Client().send(req);
          if (dl.statusCode != 200) throw 'فشل التنزيل (${dl.statusCode})';
          await dl.stream.pipe(out.openWrite());
          setState(() => status = 'تمت الترجمة وحُفظ الملف: $name');
          await OpenFilex.open(out.path);
          break;
        }
        final p = (st['progress'] ?? 0) as num;
        setState(() {
          progress = p / 100;
          status = 'جارٍ الترجمة... $p%';
        });
      }
    } catch (e) {
      setState(() => status = 'فشلت العملية: $e');
    } finally {
      setState(() {
        busy = false;
        progress = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('tarak')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const Icon(Icons.translate, size: 72),
            const SizedBox(height: 16),
            const Text('الخادم'),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'cloud', label: Text('Google Cloud')),
                ButtonSegment(value: 'oracle', label: Text('Oracle مجاني')),
              ],
              selected: {profile},
              onSelectionChanged: busy
                  ? null
                  : (s) => setState(() {
                        profile = s.first;
                        engine = profile == 'oracle' ? 'argos' : 'auto';
                      }),
            ),
            const SizedBox(height: 12),
            TextField(
              key: ValueKey(profile),
              controller: cur,
              textDirection: TextDirection.ltr,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                  labelText: profile == 'cloud'
                      ? 'عنوان Cloud Run'
                      : 'عنوان Oracle',
                  hintText: profile == 'cloud'
                      ? 'https://tarak-xxxx.run.app'
                      : 'http://123.45.67.89:8000',
                  border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: keyCtl,
              obscureText: true,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                  labelText: 'مفتاح الحماية (اختياري)',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            const Text('محرك الترجمة'),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'auto', label: Text('تلقائي')),
                ButtonSegment(value: 'argos', label: Text('مجاني')),
                ButtonSegment(value: 'google', label: Text('Google')),
              ],
              selected: {engine},
              onSelectionChanged:
                  busy ? null : (s) => setState(() => engine = s.first),
            ),
            const SizedBox(height: 24),
            Text(status, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            if (busy) LinearProgressIndicator(value: progress),
            const SizedBox(height: 16),
            FilledButton.icon(
                onPressed: busy ? null : run,
                icon: const Icon(Icons.upload_file),
                label: const Text('اختيار ملف PDF وترجمته')),
          ]),
        ),
      );
}

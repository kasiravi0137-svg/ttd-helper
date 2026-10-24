import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'cdp.dart';
import 'sms.dart';
import 'models.dart';
import 'theme.dart';
import 'page_script_steps.dart';

/// Official TTD booking site. Change here if TTD moves the portal.
const kTtdUrl = 'https://ttdevasthanams.ap.gov.in';

class _Step {
  const _Step(this.label, this.hint, {this.maxAttempts = 10});
  final String label;
  final String hint;
  final int? maxAttempts; // null = keep waiting
}

const _specialSteps = [
  _Step('Open login',
      'Tap the login icon (top right) yourself, then tap Done, next.',
      maxAttempts: 4),
  _Step('Phone and OTP request',
      'Type your phone number and tap Get OTP yourself, then tap Done, next.',
      maxAttempts: 12),
  _Step('Enter OTP',
      'Type the OTP on the page. The app continues when you are signed in.',
      maxAttempts: null),
  _Step('Special entry darshan',
      'Tap the Special Entry Darshan tile yourself, then tap Done, next.',
      maxAttempts: 10),
  _Step('Pick date',
      'Tap your date on the calendar yourself, then tap Done, next.',
      maxAttempts: 5),
  _Step('Number of tickets',
      'Choose the number of tickets yourself, then tap Done, next.',
      maxAttempts: 4),
  _Step('Pick slot',
      'Tap your slot yourself, then tap Done, next.',
      maxAttempts: 4),
  _Step('Continue to details',
      'Tap Continue until the Pilgrim Details page opens, then tap Done, next.',
      maxAttempts: 8),
  _Step('Devotee details',
      'Fill the pilgrim fields shown above yourself, then tap Done, next.',
      maxAttempts: 3),
  _Step('General details',
      'Fill email, city, state and pincode yourself, then tap Done, next.',
      maxAttempts: 3),
  _Step('Check and pay',
      'Check everything, tap Continue yourself, then do captcha and payment.'),
];

// Arjitha Seva: the first 3 steps (login, phone, OTP) are the same as Special Entry.
const _arjithaSteps = [
  _Step('Open login',
      'Tap the login icon (top right) yourself, then tap Done, next.',
      maxAttempts: 4),
  _Step('Phone and OTP request',
      'Type your phone number and tap Get OTP yourself, then tap Done, next.',
      maxAttempts: 12),
  _Step('Enter OTP',
      'Type the OTP on the page. The app continues when you are signed in.',
      maxAttempts: null),
  _Step('Arjitha Seva tile',
      'Tap the Arjitha Sevas tile yourself, then tap Done, next.',
      maxAttempts: 10),
  _Step('Select seva',
      'Choose the seva in the Select Seva box yourself, then tap Done, next.',
      maxAttempts: 6),
  _Step('Pick date',
      'Tap your date on the calendar yourself, then tap Done, next.',
      maxAttempts: 5),
  _Step('Seva time and tickets',
      'Choose the seva time and number of tickets yourself, then tap Done, next.',
      maxAttempts: 10),
  _Step('General details',
      'Fill email, city, state and pincode yourself, then tap Done, next.',
      maxAttempts: 3),
  _Step('Pilgrim details',
      'Fill the pilgrim fields yourself, then tap Done, next.',
      maxAttempts: 3),
  _Step('Continue',
      'Tap Continue yourself, then tap Done, next.',
      maxAttempts: 6),
  _Step('Check and pay',
      'Check everything, then do captcha and payment yourself.'),
];

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key, required this.booking});
  final Booking booking;

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  late final WebViewController _c;
  final GlobalKey _webKey = GlobalKey();
  int _ptr = 900;
  final List<String> _log = [];
  Timer? _timer;
  StreamSubscription<String>? _sms;
  String? _lastOtp;
  Completer<Map<String, dynamic>>? _pending;
  String _helper = '';

  int _i = 0;
  int _attempts = 0;
  int _progress = 0;
  bool _paused = false;
  bool _manual = false;
  DateTime _touched = DateTime.fromMillisecondsSinceEpoch(0); // last finger on the page
  bool _ownTap = false;
  DateTime _ownTapUntil = DateTime.fromMillisecondsSinceEpoch(0);
  int _gen = 0; // bumps whenever the step changes, so a late result of a skipped step is ignored
  bool _busy = false;
  bool _expanded = false;
  String _msg = 'Loading the TTD site...';

  Booking get _b => widget.booking;
  List<_Step> get _steps =>
      _b.service == kServiceArjitha ? _arjithaSteps : _specialSteps;

  @override
  void initState() {
    super.initState();
    _helper = kAutomationJs;
    if (Platform.isAndroid) {
      // Lets the app type into the page with real key events (see cdp.dart).
      AndroidWebViewController.enableDebugging(true).catchError((_) {});
      _startSms();
    }
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('TTD', onMessageReceived: _onMessage)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      ))
      ..loadRequest(Uri.parse(kTtdUrl));
    _timer = Timer.periodic(const Duration(milliseconds: 1500), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sms?.cancel();
    super.dispose();
  }

  Future<void> _startSms() async {
    var ok = await SmsOtp.hasPermission();
    if (!ok) {
      await SmsOtp.requestPermission();
      await Future.delayed(const Duration(seconds: 6));
      ok = await SmsOtp.hasPermission();
    }
    _addLog('sms: permission ${ok ? 'granted' : 'NOT granted'}');
    _sms = SmsOtp.bodies().listen((b) {
      final masked = b.replaceAll(RegExp(r'\d'), '#').replaceAll('\n', ' ');
      _addLog('sms: got "${masked.length > 70 ? masked.substring(0, 70) : masked}"');
      final c = SmsOtp.extract(b);
      if (c != null) _onSmsCode(c);
    }, onError: (_) {});
    _addLog('sms: consent ${await SmsOtp.startConsent()}');
    _addLog('sms: listening');
  }

  /// A new OTP arrived by SMS: type it into the OTP boxes.
  Future<void> _onSmsCode(String code) async {
    _addLog('sms: code found');
    if (code == _lastOtp) return;
    for (var w = 0; w < 20 && (_busy || _i != 2); w++) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
    }
    if (!mounted || _i != 2) return;
    _busy = true;
    try {
      final prep = await _exec('__ttd.prepOtp()');
      _addLog('otp boxes: ok=${prep['ok']} ${prep['msg'] ?? ''}');
      if (prep['ok'] != true) return;
      setState(() => _msg = 'Typing the OTP from your SMS...');
      _tapAt(prep);
      await Future.delayed(const Duration(milliseconds: 300));
      final cdp = await Cdp.connect();
      if (cdp == null) {
        _addLog('otp keys unavailable (${Cdp.status})');
        return;
      }
      try {
        await cdp.typeDigits(code);
        _lastOtp = code;
        _addLog('otp typed');
        await Future.delayed(const Duration(milliseconds: 250));
        final sub = await _exec('__ttd.submitOtp()');
        _addLog('login: ok=${sub['ok']} ${sub['msg'] ?? ''}');
        if (sub['ok'] == true) {
          // Login pressed: once the OTP boxes are gone we are signed in, so go on by ourselves.
          for (var k = 0; k < 24; k++) {
            await Future.delayed(const Duration(milliseconds: 400));
            if (!mounted) return;
            final chk = await _exec('__ttd.prepOtp()');
            if (chk['ok'] != true) {
              _addLog('signed in, moving on');
              if (_i == 2) _advance(note: 'Signed in');
              break;
            }
          }
        }
      } catch (e) {
        _addLog('otp typing failed: $e');
      } finally {
        cdp.close();
      }
    } finally {
      _busy = false;
    }
  }

  void _onMessage(JavaScriptMessage m) {
    try {
      final j = jsonDecode(m.message) as Map<String, dynamic>;
      final p = _pending;
      if (j['type'] == 'result' && p != null && !p.isCompleted) p.complete(j);
      if (j['type'] == 'tap') {
        _tapAt(j);
        return;
      }
      if (j['type'] == 'touch') {
        if (DateTime.now().isAfter(_ownTapUntil)) _touched = DateTime.now();
        return;
      }
      if (j['type'] == 'log') _addLog('page: ${j['msg']}');
      if (j['type'] == 'progress' && mounted && !_manual) {
        setState(() => _msg = (j['msg'] ?? '').toString());
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _exec(String call) async {
    if (_helper.isEmpty) return {'ok': false, 'msg': 'Starting...'};
    final c = Completer<Map<String, dynamic>>();
    _pending = c;
    try {
      await _c.runJavaScript(_helper);
      await _c.runJavaScript(call);
    } catch (e) {
      return {'ok': false, 'msg': '$e'};
    }
    return c.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () => {'ok': false, 'msg': 'The page did not answer'},
    );
  }

  // ---------- data sent to the page ----------

  Map<String, dynamic> _siteDevotee(Devotee d) => {
        'name': d.name.trim(),
        'age': d.age.trim(),
        'gender': d.gender,
        'idType': d.idType,
        'idNumber': d.siteIdNumber,
      };

  Map<String, dynamic> get _generalArgs => {
        'email': _b.email,
        'city': _b.city,
        'state': _b.state,
        'country': _b.country,
        'pincode': _b.pincode,
      };

  Map<String, dynamic> get _dateArgs {
    final d = _b.date!;
    return {'day': d.day, 'month': d.month, 'year': d.year};
  }

  String _call(int i) {
    if (_b.service == kServiceArjitha && i >= 3) {
      switch (i) {
        case 3:
          return '__ttd.click(${jsonEncode(['arjitha sevas', 'arjitha seva'])}, true)';
        case 4:
          return '__ttd.selectSeva(${jsonEncode({'seva': _b.seva})})';
        case 5:
          return '__ttd.pickDate(${jsonEncode(_dateArgs)})';
        case 6:
          return '__ttd.sevaPick(${jsonEncode({
                'seva': _b.seva,
                'slots': slotVariants(_b.slot),
                'count': _b.devotees.length,
              })})';
        case 7:
          return '__ttd.general(${jsonEncode(_generalArgs)})';
        case 8:
          return '__ttd.devotees(${jsonEncode({
                'list': _b.devotees.map(_siteDevotee).toList()
              })})';
        case 9:
          return '__ttd.goContinue()';
      }
      return '';
    }
    switch (i) {
      case 0:
        return '__ttd.openLogin()';
      case 1:
        return '__ttd.fillPhone(${jsonEncode(_b.phone)})';
      case 2:
        return '__ttd.loggedIn()';
      case 3:
        return '__ttd.click(${jsonEncode(['special entry darshan'])}, true)';
      case 4:
        return '__ttd.pickDate(${jsonEncode(_dateArgs)})';
      case 5:
        return '__ttd.tickets(${_b.devotees.length})';
      case 6:
        return '__ttd.slot(${jsonEncode({'slots': slotVariants(_b.slot)})})';
      case 7:
        return '__ttd.next()';
      case 8:
        return '__ttd.devotees(${jsonEncode({
              'list': _b.devotees.map(_siteDevotee).toList()
            })})';
      case 9:
        return '__ttd.general(${jsonEncode(_generalArgs)})';
    }
    return '';
  }

  // ---------- step runner ----------

  Future<void> _tick() async {
    if (!mounted || _paused || _manual || _busy) return;
    if (_i >= _steps.length - 1) return;
    // The user is touching the page (picking a value, scrolling): leave it alone for a while.
    if (_i >= 3 && DateTime.now().difference(_touched).inMilliseconds < 7000) {
      if (mounted && _msg != 'Waiting while you use the page...') {
        setState(() => _msg = 'Waiting while you use the page...');
      }
      return;
    }
    _busy = true;
    final gen = _gen;
    try {
      final r = _i == 1 ? await _phoneStep() : await _exec(_call(_i));
      if (!mounted || gen != _gen) return; // user skipped meanwhile: no taps, no log
      if (_i != 1) _addLog('step ${_i + 1} ${_steps[_i].label}: ok=${r['ok']} ${r['msg'] ?? ''}');
      if (r['ok'] == true) {
        if (r['skip'] == true && _i == 0) {
          // Already signed in: jump straight to Special Entry Darshan.
          setState(() {
            final j = (r['jump'] as num?)?.toInt() ?? 3;
            // The calendar page is step 5 in the Arjitha Seva flow (step 4 in Special Entry).
            _i = (_b.service == kServiceArjitha && j == 4) ? 5 : j;
            _attempts = 0;
            _msg = (r['msg'] ?? 'Already signed in').toString();
          });
        } else {
          _advance(note: r['msg']?.toString());
        }
      } else {
        if (r['needTap'] == true && gen == _gen) _tapAt(r);
        // In TTD's virtual queue the site decides when to let us in: keep waiting, do not give up.
        if (_i >= 3) {
          final q = await _exec('__ttd.inQueue()');
          if (gen != _gen) return;
          if (q['ok'] == true) {
            if (mounted) setState(() => _msg = (q['msg'] ?? '').toString());
            return;
          }
        }
        _attempts++;
        final max = _steps[_i].maxAttempts;
        final m = (r['msg'] ?? '').toString();
        setState(() {
          _msg = m.isEmpty ? _steps[_i].hint : m;
          if (max != null && _attempts >= max * 2) {
            _manual = true;
            _msg = m.isEmpty ? _steps[_i].hint : '${_steps[_i].hint}\n($m)';
          }
        });
      }
    } finally {
      _busy = false;
    }
  }

  void _addLog(String s) {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    _log.add('${two(t.hour)}:${two(t.minute)}:${two(t.second)} $s');
    if (_log.length > 200) _log.removeAt(0);
  }

  void _showLog() {
    final text = _log.isEmpty ? 'Nothing logged yet.' : _log.join('\n');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.8,
          child: Column(
            children: [
              ListTile(
                title: const Text('Log'),
                subtitle: Text('Step ${_i + 1}: ${_steps[_i].label}'),
                trailing: TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: text));
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('Log copied')));
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy'),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(text,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _probe(String label) async {
    final r = await _exec('__ttd.probe()');
    _addLog('$label: ${r['info'] ?? r['msg']}');
  }

  /// Phone step: get the box ready, type the number with real key events, then let the
  /// page script check it and press Get OTP.
  Future<Map<String, dynamic>> _phoneStep() async {
    _addLog('--- phone step ---');
    final prep = await _exec('__ttd.prepPhone(${jsonEncode(_b.phone)})');
    _addLog('prepare: ok=${prep['ok']} ${prep['msg'] ?? ''}');
    if (prep['ok'] != true) return prep;
    var how = 'already typed';
    if (prep['ready'] == true) {
      if (mounted) setState(() => _msg = 'Typing your number...');
      final cdp = await Cdp.connect();
      _addLog('real keys: ${Cdp.status}');
      for (final t in Cdp.trace) {
        _addLog('  $t');
      }
      if (cdp != null) {
        try {
          await cdp.typeDigits(_b.phone);
          how = 'typed with real keys';
        } catch (e) {
          how = 'key typing failed: $e';
        } finally {
          cdp.close();
        }
        for (final t in Cdp.trace.skip(1)) {
          _addLog('  $t');
        }
        _addLog('real keys result: $how');
        await Future.delayed(const Duration(milliseconds: 250));
      } else {
        how = 'keys unavailable (${Cdp.status})';
      }
    }
    _addLog('sms: consent ${await SmsOtp.startConsent()}');
    final r = await _exec(_call(1));
    _addLog('fill/click: ok=${r['ok']} ${r['msg'] ?? ''}');
    if (r['ok'] != true) {
      await _probe('after failed fill');
      r['msg'] = '${r['msg'] ?? ''}  [$how]';
    }
    return r;
  }

  /// Taps the page where the page said (the phone box), so the page gets real focus.
  void _tapAt(Map<String, dynamic> r) {
    try {
      final box = _webKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) return;
      final iw = (r['iw'] as num).toDouble();
      if (iw <= 0) return;
      final k = box.size.width / iw;
      final g = box.localToGlobal(
          Offset((r['x'] as num).toDouble() * k, (r['y'] as num).toDouble() * k));
      final id = _ptr++;
      final t = WidgetsBinding.instance.currentSystemFrameTimeStamp;
      final gb = GestureBinding.instance;
      _ownTap = true;
      _ownTapUntil = DateTime.now().add(const Duration(milliseconds: 700));
      gb.handlePointerEvent(PointerDownEvent(
          timeStamp: t, pointer: id, kind: PointerDeviceKind.touch, device: id, position: g));
      _ownTap = false;
      Future.delayed(const Duration(milliseconds: 80), () {
        gb.handlePointerEvent(PointerUpEvent(
            timeStamp: t + const Duration(milliseconds: 80),
            pointer: id,
            kind: PointerDeviceKind.touch,
            device: id,
            position: g));
      });
    } catch (_) {}
  }

  void _advance({String? note}) {
    if (_i >= _steps.length - 1) return;
    _gen++;
    setState(() {
      _i++;
      _attempts = 0;
      _manual = false;
      _msg = _i == _steps.length - 1
          ? _steps[_i].hint
          : ((note == null || note.isEmpty) ? _steps[_i].label : note);
    });
    // Do not wait for the next timer tick: start the next step right away.
    Future.delayed(const Duration(milliseconds: 300), _tick);
  }

  Future<void> _autofill() async {
    final args = jsonEncode({
      'list': _b.devotees.map(_siteDevotee).toList(),
      'general': _generalArgs,
    });
    final r = await _exec('__ttd.fillAll($args)');
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 6),
        content: Text((r['msg'] ?? '').toString().isNotEmpty
            ? r['msg'].toString()
            : 'No matching fields on this page yet'),
      ));
  }

  Future<void> _back() async {
    if (await _c.canGoBack()) {
      await _c.goBack();
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  void _showSteps() {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Steps'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (var k = 0; k < _steps.length; k++)
                ListTile(
                  dense: true,
                  leading: Icon(
                    k < _i
                        ? Icons.check_circle
                        : (k == _i
                            ? Icons.play_circle_fill
                            : Icons.radio_button_unchecked),
                    color: k < _i
                        ? Colors.green.shade700
                        : (k == _i ? kSaffron : Colors.black38),
                  ),
                  title: Text(_steps[k].label),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close')),
        ],
      ),
    );
  }

  // ---------- UI ----------

  Widget _panel() {
    final isOtp = _i == 2;
    final last = _i == _steps.length - 1;
    final status = last
        ? 'Your turn'
        : _paused
            ? 'Paused'
            : (_manual || isOtp)
                ? 'Needs you'
                : 'Working';
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: kLine)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Step ${_i + 1} of ${_steps.length}: ${_steps[_i].label}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, color: kMaroon),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAEEDA),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(status,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF633806))),
                  ),
                  Icon(_expanded ? Icons.expand_more : Icons.expand_less,
                      color: kClay),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(_msg,
                maxLines: (_expanded || _manual) ? 6 : 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13)),
            if (_expanded) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() => _paused = !_paused),
                      icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                      label: Text(_paused ? 'Resume' : 'Pause'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _autofill,
                      icon: const Icon(Icons.auto_fix_high),
                      label: const Text('Autofill page'),
                    ),
                  ),
                ],
              ),
            ],
            if (!_manual && !isOtp && !last) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _advance(note: 'Skipped - you did it yourself'),
                  icon: const Icon(Icons.skip_next),
                  label: const Text("Skip - I'll do this step"),
                ),
              ),
            ],
            if ((_manual || isOtp) && !last) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (_manual) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() {
                          _manual = false;
                          _attempts = 0;
                          _msg = 'Retrying...';
                        }),
                        child: const Text('Retry'),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 46)),
                      onPressed: () => _advance(),
                      child: Text(isOtp ? "I've entered OTP" : 'Done, next'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kMaroon,
        foregroundColor: Colors.white,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back), onPressed: _back),
        title: const Text('TTD booking'),
        actions: [
          IconButton(
              tooltip: 'Log',
              onPressed: _showLog,
              icon: const Icon(Icons.bug_report_outlined)),
          IconButton(
              tooltip: 'Steps',
              onPressed: _showSteps,
              icon: const Icon(Icons.checklist)),
          IconButton(
              tooltip: 'Reload',
              onPressed: () => _c.reload(),
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          if (_progress < 100)
            LinearProgressIndicator(
                value: _progress / 100, minHeight: 3, color: kSaffron),
          Expanded(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) {
                if (!_ownTap) _touched = DateTime.now();
              },
              child: WebViewWidget(key: _webKey, controller: _c),
            ),
          ),
          _panel(),
        ],
      ),
    );
  }
}

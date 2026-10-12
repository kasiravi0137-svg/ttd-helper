import 'dart:async';
import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
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

const _steps = [
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
  Timer? _timer;
  Completer<Map<String, dynamic>>? _pending;
  String _helper = '';

  int _i = 0;
  int _attempts = 0;
  int _progress = 0;
  bool _paused = false;
  bool _manual = false;
  bool _busy = false;
  bool _expanded = false;
  String _msg = 'Loading the TTD site...';

  Booking get _b => widget.booking;

  @override
  void initState() {
    super.initState();
    _helper = kAutomationJs;
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('TTD', onMessageReceived: _onMessage)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      ))
      ..loadRequest(Uri.parse(kTtdUrl));
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _onMessage(JavaScriptMessage m) {
    try {
      final j = jsonDecode(m.message) as Map<String, dynamic>;
      final p = _pending;
      if (j['type'] == 'result' && p != null && !p.isCompleted) p.complete(j);
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
    _busy = true;
    try {
      final r = await _exec(_call(_i));
      if (!mounted) return;
      if (r['ok'] == true) {
        if (r['skip'] == true && _i == 0) {
          // Already signed in: jump straight to Special Entry Darshan.
          setState(() {
            _i = 3;
            _attempts = 0;
            _msg = 'Already signed in';
          });
        } else {
          _advance(note: r['msg']?.toString());
        }
      } else {
        if (r['needTap'] == true) _tapAt(r);
        _attempts++;
        final max = _steps[_i].maxAttempts;
        final m = (r['msg'] ?? '').toString();
        setState(() {
          _msg = m.isEmpty ? _steps[_i].hint : m;
          if (max != null && _attempts >= max) {
            _manual = true;
            _msg = m.isEmpty ? _steps[_i].hint : '${_steps[_i].hint}\n($m)';
          }
        });
      }
    } finally {
      _busy = false;
    }
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
      gb.handlePointerEvent(PointerDownEvent(
          timeStamp: t, pointer: id, kind: PointerDeviceKind.touch, device: id, position: g));
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
    setState(() {
      _i++;
      _attempts = 0;
      _manual = false;
      _msg = _i == _steps.length - 1
          ? _steps[_i].hint
          : ((note == null || note.isEmpty) ? _steps[_i].label : note);
    });
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
          Expanded(child: WebViewWidget(key: _webKey, controller: _c)),
          _panel(),
        ],
      ),
    );
  }
}

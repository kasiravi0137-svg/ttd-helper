import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Types into the page with real key events through the WebView's own debugging
/// socket (the app talks to its own WebView; nothing leaves the phone).
/// Real key events are the one thing masked phone boxes always accept.
class Cdp {
  Cdp._(this._socket);

  /// What happened the last time we tried to connect, for the on-screen note.
  static String status = '';

  /// Short notes about every command sent (for the log screen).
  static final List<String> trace = [];

  final Socket _socket;
  final Map<int, Completer<Map<String, dynamic>>> _waiting = {};
  final List<int> _buf = [];
  final _rnd = Random();
  int _id = 0;
  bool _open = false;
  final Completer<void> _ready = Completer<void>();

  static InternetAddress get _addr =>
      InternetAddress('@webview_devtools_remote_$pid', type: InternetAddressType.unix);

  static Future<String> _httpGet(String path) async {
    final s = await Socket.connect(_addr, 0, timeout: const Duration(seconds: 3));
    final done = Completer<String>();
    final chunks = <int>[];
    // The debugging server keeps the connection open, so stop once the body is complete.
    bool complete() {
      final text = latin1.decode(chunks, allowInvalid: true);
      final end = text.indexOf('\r\n\r\n');
      if (end < 0) return false;
      final m = RegExp(r'content-length:\s*(\d+)', caseSensitive: false)
          .firstMatch(text.substring(0, end));
      if (m != null) return chunks.length - (end + 4) >= int.parse(m.group(1)!);
      final body = text.substring(end + 4).trim();
      return body.startsWith('[') && body.endsWith(']');
    }

    s.listen(
      (d) {
        chunks.addAll(d);
        if (!done.isCompleted && complete()) {
          done.complete(utf8.decode(chunks, allowMalformed: true));
        }
      },
      onError: (Object e) {
        if (!done.isCompleted) done.completeError(e);
      },
      onDone: () {
        if (!done.isCompleted) done.complete(utf8.decode(chunks, allowMalformed: true));
      },
    );
    s.write('GET $path HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n');
    try {
      return await done.future.timeout(const Duration(seconds: 5), onTimeout: () {
        return utf8.decode(chunks, allowMalformed: true);
      });
    } finally {
      s.destroy();
    }
  }

  static Future<Cdp?> connect() async {
    trace.clear();
    try {
      final body = await _httpGet('/json');
      final a = body.indexOf('[');
      final z = body.lastIndexOf(']');
      if (a < 0 || z <= a) {
        final head = body.replaceAll(RegExp(r'\s+'), ' ');
        status = 'no target list, got: ${head.length > 120 ? head.substring(0, 120) : head}';
        return null;
      }
      final list = jsonDecode(body.substring(a, z + 1)) as List;
      Map<String, dynamic>? pick;
      for (final t in list) {
        final m = t as Map<String, dynamic>;
        if (m['webSocketDebuggerUrl'] == null) continue;
        if ((m['url'] ?? '').toString().contains('ttdevasthanams')) {
          pick = m;
          break;
        }
        pick ??= m;
      }
      if (pick == null) {
        status = 'no page target';
        return null;
      }
      trace.add('target: ${pick['type']} ${pick['url']}');
      final path = Uri.parse(pick['webSocketDebuggerUrl'].toString()).path;
      final s = await Socket.connect(_addr, 0, timeout: const Duration(seconds: 3));
      final c = Cdp._(s);
      c._start(path);
      await c._ready.future.timeout(const Duration(seconds: 4));
      status = 'connected';
      return c;
    } catch (e) {
      status = e.toString().split('\n').first;
      return null;
    }
  }

  void _start(String path) {
    final key = base64.encode(List<int>.generate(16, (_) => _rnd.nextInt(256)));
    _socket.write('GET $path HTTP/1.1\r\n'
        'Host: localhost\r\n'
        'Upgrade: websocket\r\n'
        'Connection: Upgrade\r\n'
        'Sec-WebSocket-Key: $key\r\n'
        'Sec-WebSocket-Version: 13\r\n\r\n');
    _socket.listen(_onData, onError: (_) => _fail('socket error'), onDone: () => _open = false);
  }

  void _fail(String why) {
    status = why;
    if (!_ready.isCompleted) _ready.completeError(why);
  }

  void _onData(List<int> data) {
    _buf.addAll(data);
    if (!_open) {
      final text = latin1.decode(_buf, allowInvalid: true);
      final end = text.indexOf('\r\n\r\n');
      if (end < 0) return;
      if (!text.startsWith('HTTP/1.1 101')) {
        _fail('handshake refused: ${text.split('\r\n').first}');
        return;
      }
      _buf.removeRange(0, end + 4);
      _open = true;
      if (!_ready.isCompleted) _ready.complete();
    }
    _parseFrames();
  }

  void _parseFrames() {
    while (_buf.length >= 2) {
      final op = _buf[0] & 0x0F;
      var len = _buf[1] & 0x7F;
      var off = 2;
      if (len == 126) {
        if (_buf.length < 4) return;
        len = (_buf[2] << 8) | _buf[3];
        off = 4;
      } else if (len == 127) {
        if (_buf.length < 10) return;
        len = 0;
        for (var i = 2; i < 10; i++) {
          len = (len << 8) | _buf[i];
        }
        off = 10;
      }
      if (_buf.length < off + len) return;
      final payload = _buf.sublist(off, off + len);
      _buf.removeRange(0, off + len);
      if (op == 1) {
        try {
          final m = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
          final id = m['id'];
          if (id is int) _waiting.remove(id)?.complete(m);
        } catch (_) {}
      }
    }
  }

  void _sendText(String text) {
    final payload = utf8.encode(text);
    final mask = List<int>.generate(4, (_) => _rnd.nextInt(256));
    final b = BytesBuilder();
    b.addByte(0x81);
    if (payload.length < 126) {
      b.addByte(0x80 | payload.length);
    } else {
      b.addByte(0x80 | 126);
      b.addByte((payload.length >> 8) & 255);
      b.addByte(payload.length & 255);
    }
    b.add(mask);
    for (var i = 0; i < payload.length; i++) {
      b.addByte(payload[i] ^ mask[i % 4]);
    }
    _socket.add(b.toBytes());
  }

  Future<Map<String, dynamic>> call(String method, [Map<String, dynamic>? params]) {
    final id = ++_id;
    final c = Completer<Map<String, dynamic>>();
    _waiting[id] = c;
    _sendText(jsonEncode({'id': id, 'method': method, 'params': params ?? {}}));
    return c.future.timeout(const Duration(seconds: 5), onTimeout: () {
      _waiting.remove(id);
      return {'error': 'timeout'};
    }).then((m) {
      if (m['error'] != null && trace.length < 40) trace.add('$method -> ${m['error']}');
      return m;
    });
  }

  /// Types digits like a real keyboard into whatever box has the focus.
  Future<void> typeDigits(String digits) async {
    await call('Emulation.setFocusEmulationEnabled', {'enabled': true});
    for (final ch in digits.split('')) {
      final n = int.tryParse(ch);
      if (n == null) continue;
      final vk = 48 + n;
      await call('Input.dispatchKeyEvent', {
        'type': 'keyDown',
        'text': ch,
        'unmodifiedText': ch,
        'key': ch,
        'code': 'Digit$ch',
        'windowsVirtualKeyCode': vk,
        'nativeVirtualKeyCode': vk,
      });
      await call('Input.dispatchKeyEvent', {
        'type': 'keyUp',
        'key': ch,
        'code': 'Digit$ch',
        'windowsVirtualKeyCode': vk,
        'nativeVirtualKeyCode': vk,
      });
      await Future.delayed(const Duration(milliseconds: 90));
    }
  }

  void close() {
    try {
      _socket.destroy();
    } catch (_) {}
  }
}

import 'package:flutter/material.dart';
import 'models.dart';
import 'storage.dart';
import 'theme.dart';
import 'details_screen.dart';
import 'browser_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Booking _b = Booking();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final b = await Store.load();
    if (!mounted) return;
    setState(() {
      _b = b;
      _loading = false;
    });
  }

  Future<void> _edit() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DetailsScreen(initial: _b)),
    );
    _load();
  }

  Future<void> _start() async {
    if (_b.service != kServiceSpecial) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${serviceName(_b.service)} booking is coming soon'),
      ));
      return;
    }
    final m = _b.missing();
    if (m.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Fill these first: ${m.take(4).join(', ')}'),
        action: SnackBarAction(label: 'Fill', onPressed: _edit),
      ));
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BrowserScreen(booking: _b)),
    );
  }

  Future<void> _deleteAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete saved details'),
        content: const Text(
            'This removes the phone number, devotees and ID numbers saved on this phone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await Store.clear();
    _load();
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 92,
                child: Text(k,
                    style: const TextStyle(color: kClay, fontSize: 13))),
            Expanded(
                child: Text(v,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w500))),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final missing = _b.missing();
    return Scaffold(
      body: Column(
        children: [
          Header(
            title: _b.service == kServiceArjitha
                ? 'Tirumala Arjitha Seva'
                : 'Tirumala special entry darshan',
            subtitle: _b.service == kServiceArjitha
                ? 'Booking flow coming soon'
                : 'Rs 300 per devotee',
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_b.isBlank)
                        AppCard(
                          child: Column(
                            children: [
                              const Icon(Icons.temple_hindu_outlined,
                                  size: 40, color: kClay),
                              const SizedBox(height: 8),
                              const Text('Add your booking details',
                                  style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              const Text(
                                'Save them once. The app fills the TTD form for you.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 14),
                              FilledButton(
                                  onPressed: _edit,
                                  child: const Text('Add details')),
                            ],
                          ),
                        )
                      else ...[
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Saved booking',
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600)),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: missing.isEmpty
                                          ? const Color(0xFFEAF3DE)
                                          : const Color(0xFFFAEEDA),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      _b.service != kServiceSpecial
                                          ? 'Coming soon'
                                          : missing.isEmpty
                                              ? 'Ready'
                                              : '${missing.length} missing',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: missing.isEmpty
                                              ? const Color(0xFF27500A)
                                              : const Color(0xFF633806)),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              _row('Service', serviceName(_b.service)),
                              _row('Phone',
                                  _b.phone.isEmpty ? '-' : '+91 ${_b.phone}'),
                              if (_b.service == kServiceSpecial) ...[
                              _row('Date',
                                  _b.date == null ? '-' : fmtDate(_b.date!)),
                              _row('Slot', _b.slot.isEmpty ? '-' : _b.slot),
                              _row(
                                  'Devotees',
                                  _b.devotees.isEmpty
                                      ? '-'
                                      : _b.devotees
                                          .map((d) => d.name)
                                          .join(', ')),
                              ],
                              _row('Email', _b.email.isEmpty ? '-' : _b.email),
                              _row(
                                  'Address',
                                  [_b.city, _b.state, _b.country, _b.pincode]
                                          .where((e) => e.isNotEmpty)
                                          .join(', ')
                                          .isEmpty
                                      ? '-'
                                      : [_b.city, _b.state, _b.country, _b.pincode]
                                          .where((e) => e.isNotEmpty)
                                          .join(', ')),
                              if (_b.service == kServiceSpecial) ...[
                              const Divider(height: 22),
                              _row('Total', 'Rs ${_b.total}'),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: _start,
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('Start booking'),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _edit,
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('Edit details'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _deleteAll,
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Delete all'),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 18),
                      const Text(
                        'OTP, captcha and payment are always done by you on the TTD page.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

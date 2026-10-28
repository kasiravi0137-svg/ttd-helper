import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models.dart';
import 'storage.dart';
import 'theme.dart';
import 'devotee_sheet.dart';

const _slotChips = ['10:00 AM', '12:00 PM', '03:00 PM', '05:00 PM'];

class DetailsScreen extends StatefulWidget {
  const DetailsScreen({super.key, required this.initial});
  final Booking initial;

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _slot;
  late final TextEditingController _phone, _email, _city, _state, _country, _pincode;
  late String _service;
  String? _seva; // a kSevas entry or kSevaOther
  final _sevaOther = TextEditingController();
  bool _sevaError = false;
  DateTime? _date;
  bool _dateError = false;
  late List<Devotee> _devotees;
  bool _editContact = false;

  @override
  void initState() {
    super.initState();
    final b = widget.initial;
    _slot = TextEditingController(text: b.slot);
    _phone = TextEditingController(text: b.phone);
    _email = TextEditingController(text: b.email);
    _city = TextEditingController(text: b.city);
    _state = TextEditingController(text: b.state);
    _country = TextEditingController(text: b.country);
    _pincode = TextEditingController(text: b.pincode);
    _service = b.service;
    if (kSevas.contains(b.seva)) {
      _seva = b.seva;
    } else if (b.seva.isNotEmpty) {
      _seva = kSevaOther;
      _sevaOther.text = b.seva;
    }
    _date = b.date;
    _devotees = b.devotees.map((d) => d.copy()).toList();
  }

  @override
  void dispose() {
    _slot.dispose();
    for (final c in [_phone, _email, _city, _state, _country, _pincode]) {
      c.dispose();
    }
    _sevaOther.dispose();
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = (_date != null && !_date!.isBefore(today))
        ? _date!
        : today.add(const Duration(days: 1));
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (d != null) {
      setState(() {
        _date = d;
        _dateError = false;
      });
    }
  }

  Future<void> _pickTime() async {
    final c = TextEditingController(text: _slot.text);
    final res = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kCream,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Time (optional)',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Most available = the app picks the time with the most seats.',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                    label: const Text('Most available'),
                    onPressed: () => Navigator.pop(ctx, '')),
                for (final s in _slotChips)
                  ActionChip(label: Text(s), onPressed: () => Navigator.pop(ctx, s)),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: c,
              decoration: const InputDecoration(
                  labelText: 'Or type a time', hintText: '07:30 AM'),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, c.text.trim()),
                child: const Text('Done')),
          ],
        ),
      ),
    );
    c.dispose();
    if (res != null) setState(() => _slot.text = res);
  }

  Future<void> _addDevotee() async {
    final d = await showDevoteeSheet(context);
    if (d != null) setState(() => _devotees.add(d));
  }

  Future<void> _editDevotee(int i) async {
    final d = await showDevoteeSheet(context, existing: _devotees[i].copy());
    if (d != null) setState(() => _devotees[i] = d);
  }

  void _deleteDevotee(int i) {
    final removed = _devotees[i];
    setState(() => _devotees.removeAt(i));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Removed ${removed.name}'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => setState(
              () => _devotees.insert(i.clamp(0, _devotees.length), removed)),
        ),
      ));
  }

  Future<void> _clearForm() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Clear form'),
        content: const Text('Remove everything typed on this screen?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true) return;
    _form.currentState?.reset();
    _slot.clear();
    setState(() {
      _date = null;
      _dateError = false;
      _devotees.clear();
    });
  }

  bool _contactOk() =>
      _phone.text.trim().length == 10 &&
      _email.text.contains('@') &&
      _city.text.trim().isNotEmpty &&
      _state.text.trim().isNotEmpty &&
      _country.text.trim().isNotEmpty &&
      _pincode.text.trim().length == 6;

  Future<void> _save() async {
    if (!_contactOk()) {
      setState(() => _editContact = true);
      _snack('Check your contact details');
      return;
    }
    if (_service == kServiceArjitha) {
      final okForm = _form.currentState!.validate();
      setState(() {
        _sevaError = _seva == null;
        _dateError = _date == null;
      });
      if (!okForm || _seva == null || _date == null) {
        _snack('Fix the highlighted fields');
        return;
      }
      if (_devotees.isEmpty) {
        _snack('Add at least one devotee');
        return;
      }
      await Store.save(Booking(
        service: _service,
        seva: _sevaName,
        slot: _slot.text.trim(),
        date: _date,
        devotees: _devotees,
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        city: _city.text.trim(),
        state: _state.text.trim(),
        country: _country.text.trim(),
        pincode: _pincode.text.trim(),
      ));
      if (!mounted) return;
      Navigator.pop(context, true);
      return;
    }
    final formOk = _form.currentState!.validate();
    setState(() => _dateError = _date == null);
    if (!formOk || _date == null) {
      _snack('Fix the highlighted fields');
      return;
    }
    if (_devotees.isEmpty) {
      _snack('Add at least one devotee');
      return;
    }
    final b = Booking(
      service: _service,
      seva: _sevaName,
      date: _date,
      slot: _slot.text.trim(),
      devotees: _devotees,
      phone: _phone.text.trim(),
      email: _email.text.trim(),
      city: _city.text.trim(),
      state: _state.text.trim(),
      country: _country.text.trim(),
      pincode: _pincode.text.trim(),
    );
    await Store.save(b);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  String get _sevaName =>
      _seva == null ? '' : (_seva == kSevaOther ? _sevaOther.text.trim() : _seva!);

  String? _required(String? v, String what) =>
      (v == null || v.trim().isEmpty) ? 'Enter $what' : null;

  Widget _devoteeTile(int i) {
    final d = _devotees[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kLine),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${i + 1}. ${d.name}',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('${d.age} yrs, ${d.gender}',
                    style: const TextStyle(fontSize: 13)),
                Text('${d.idType}: ${d.idNumber}',
                    style: const TextStyle(fontSize: 13, color: kClay)),
              ],
            ),
          ),
          IconButton(
              tooltip: 'Edit',
              onPressed: () => _editDevotee(i),
              icon: const Icon(Icons.edit_outlined, color: kClay)),
          IconButton(
              tooltip: 'Delete',
              onPressed: () => _deleteDevotee(i),
              icon: const Icon(Icons.delete_outline, color: kClay)),
        ],
      ),
    );
  }

  Widget _card(String title, List<Widget> children) => Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kLine),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    color: kClay, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      );

  Widget _row(String label, String value, VoidCallback onTap,
      {String? error, bool muted = false}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(label,
                        style: const TextStyle(fontSize: 15, color: Colors.black54))),
                Text(value,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: muted ? Colors.black45 : Colors.black87)),
                const Icon(Icons.chevron_right, size: 20, color: Colors.black45),
              ],
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(error,
                    style: const TextStyle(color: Colors.red, fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _contactFields() => Column(
        children: [
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            decoration: const InputDecoration(
                labelText: 'Mobile number (login OTP goes here)',
                prefixText: '+91 '),
            validator: (v) => (v ?? '').trim().length == 10 ? null : 'Enter 10 digits',
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
            validator: (v) => (v ?? '').contains('@') ? null : 'Enter a valid email',
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _city,
            decoration: const InputDecoration(labelText: 'City'),
            validator: (v) => _required(v, 'city'),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _state,
            decoration: const InputDecoration(labelText: 'State'),
            validator: (v) => _required(v, 'state'),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _country,
            decoration: const InputDecoration(labelText: 'Country'),
            validator: (v) => _required(v, 'country'),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _pincode,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            decoration: const InputDecoration(labelText: 'Pincode'),
            validator: (v) => (v ?? '').trim().length == 6 ? null : 'Enter 6 digits',
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final arjitha = _service == kServiceArjitha;
    final timeText = _slot.text.trim().isEmpty ? 'Most available' : _slot.text.trim();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kMaroon,
        foregroundColor: Colors.white,
        title: const Text('Booking details'),
        actions: [
          IconButton(
              tooltip: 'Clear form',
              onPressed: _clearForm,
              icon: const Icon(Icons.cleaning_services_outlined)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(onPressed: _save, child: const Text('Save details')),
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                for (final e in kServices.entries)
                  ButtonSegment(
                      value: e.key,
                      label: Text(e.key == kServiceSpecial ? 'Special Entry' : 'Arjitha Seva')),
              ],
              selected: {_service},
              onSelectionChanged: (v) => setState(() => _service = v.first),
            ),
            _card('1. When', [
              if (arjitha) ...[
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Select Seva',
                    errorText: _sevaError ? 'Pick a seva' : null,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _seva,
                      hint: const Text('Select seva'),
                      isExpanded: true,
                      borderRadius: BorderRadius.circular(12),
                      items: [
                        for (final v in [...kSevas, kSevaOther])
                          DropdownMenuItem(value: v, child: Text(v)),
                      ],
                      onChanged: (v) => setState(() {
                        _seva = v;
                        _sevaError = false;
                      }),
                    ),
                  ),
                ),
                if (_seva == kSevaOther) ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _sevaOther,
                    decoration: const InputDecoration(
                        labelText: 'Seva name (as shown on the TTD page)'),
                    validator: (v) => _required(v, 'the seva name'),
                  ),
                ],
                const SizedBox(height: 4),
              ],
              _row('Date', _date == null ? 'Select' : fmtDate(_date!), _pickDate,
                  error: _dateError ? 'Pick a date' : null, muted: _date == null),
              const Divider(height: 1),
              _row('Time (optional)', timeText, _pickTime,
                  muted: _slot.text.trim().isEmpty),
            ]),
            _card('2. Who is coming', [
              for (var i = 0; i < _devotees.length; i++) _devoteeTile(i),
              OutlinedButton.icon(
                onPressed: _addDevotee,
                icon: const Icon(Icons.add),
                label: const Text('Add person'),
              ),
              const SizedBox(height: 8),
              Text(
                _devotees.isEmpty
                    ? 'Add everyone who is coming. Tickets = number of people.'
                    : 'Tickets = number of people (${_devotees.length})'
                        '${arjitha ? '' : '  -  Rs ${_devotees.length * 300}'}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ]),
            _card('3. Your contact', [
              if (!_editContact) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text('+91 ${_phone.text}',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                    TextButton(
                        onPressed: () => setState(() => _editContact = true),
                        child: const Text('Edit')),
                  ],
                ),
                Text('${_email.text}  -  ${_city.text}, ${_pincode.text}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ] else ...[
                const SizedBox(height: 4),
                _contactFields(),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                      onPressed: () {
                        if (_contactOk()) setState(() => _editContact = false);
                        else _form.currentState?.validate();
                      },
                      child: const Text('Done')),
                ),
              ],
            ]),
          ],
        ),
      ),
    );
  }
}

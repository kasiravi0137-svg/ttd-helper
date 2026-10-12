import 'package:flutter/material.dart';
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
  late final TextEditingController _phone, _slot, _email, _city, _state,
      _country, _pin;
  DateTime? _date;
  bool _dateError = false;
  late List<Devotee> _devotees;

  @override
  void initState() {
    super.initState();
    final b = widget.initial;
    _phone = TextEditingController(text: b.phone);
    _slot = TextEditingController(text: b.slot);
    _email = TextEditingController(text: b.email);
    _city = TextEditingController(text: b.city);
    _state = TextEditingController(text: b.state);
    _country = TextEditingController(text: b.country);
    _pin = TextEditingController(text: b.pincode);
    _date = b.date;
    _devotees = b.devotees.map((d) => d.copy()).toList();
  }

  @override
  void dispose() {
    for (final c in [_phone, _slot, _email, _city, _state, _country, _pin]) {
      c.dispose();
    }
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
    for (final c in [_phone, _slot, _email, _city, _state, _pin]) {
      c.clear();
    }
    _country.text = 'India';
    setState(() {
      _date = null;
      _dateError = false;
      _devotees.clear();
    });
  }

  Future<void> _save() async {
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
      phone: _phone.text.trim(),
      date: _date,
      slot: _slot.text.trim(),
      devotees: _devotees,
      email: _email.text.trim(),
      city: _city.text.trim(),
      state: _state.text.trim(),
      country: _country.text.trim(),
      pincode: _pin.text.trim(),
    );
    await Store.save(b);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

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

  @override
  Widget build(BuildContext context) {
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
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SectionTitle('Login'),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              decoration: const InputDecoration(
                  labelText: 'Mobile number', prefixText: '+91  ', counterText: ''),
              validator: (v) => (v ?? '').trim().length == 10
                  ? null
                  : 'Enter a 10 digit number',
            ),
            const SectionTitle('Darshan'),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _pickDate,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Darshan date',
                  suffixIcon: const Icon(Icons.calendar_today_outlined),
                  errorText: _dateError ? 'Pick a date' : null,
                ),
                child: Text(_date == null ? 'Select date' : fmtDate(_date!)),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _slot,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  labelText: 'Slot time', hintText: '10:00 AM'),
              validator: (v) => _required(v, 'a slot time'),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final s in _slotChips)
                  ChoiceChip(
                    label: Text(s),
                    selected: _slot.text.trim() == s,
                    selectedColor: kSaffron.withValues(alpha: 0.35),
                    onSelected: (_) => setState(() => _slot.text = s),
                  ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SectionTitle('Devotees (${_devotees.length})'),
                Text('Rs ${_devotees.length * 300}',
                    style: const TextStyle(
                        color: kMaroon, fontWeight: FontWeight.w600)),
              ],
            ),
            for (var i = 0; i < _devotees.length; i++) _devoteeTile(i),
            OutlinedButton.icon(
              onPressed: _addDevotee,
              icon: const Icon(Icons.add),
              label: const Text('Add devotee'),
            ),
            const SectionTitle('General details'),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email ID'),
              validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                      .hasMatch((v ?? '').trim())
                  ? null
                  : 'Enter a valid email',
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _city,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'City'),
                    validator: (v) => _required(v, 'city'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _pin,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                        labelText: 'Pincode', counterText: ''),
                    validator: (v) => (v ?? '').trim().length == 6
                        ? null
                        : 'Enter 6 digits',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _state,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'State'),
                    validator: (v) => _required(v, 'state'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _country,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Country'),
                    validator: (v) => _required(v, 'country'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            FilledButton(onPressed: _save, child: const Text('Save details')),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _clearForm,
              icon: const Icon(Icons.cleaning_services_outlined),
              label: const Text('Clear form'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

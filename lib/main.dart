import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:webview_flutter/webview_flutter.dart';

// ===== models.dart =====
const genders = ['Male', 'Female', 'Other'];
const idTypes = [
  'Aadhaar Card',
  'Passport',
  'Voter ID',
  'PAN Card',
  'Driving License',
];

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String fmtDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// Different spellings of a slot time, so the page text can be matched.
List<String> slotVariants(String s) {
  final t = s.trim();
  if (t.isEmpty) return [];
  // Most specific first (with AM/PM), so "12:00 PM" is tried before "12:00".
  final out = <String>{};
  final m = RegExp(r'^(\d{1,2})(?::(\d{2}))?\s*([AaPp][Mm])?$').firstMatch(t);
  if (m != null) {
    final h = int.parse(m[1]!);
    final mm = m[2] ?? '00';
    final ap = m[3]?.toUpperCase();
    final h2 = h.toString().padLeft(2, '0');
    if (ap != null) out.addAll(['$h:$mm $ap', '$h2:$mm $ap']);
    out.addAll([t, '$h:$mm', '$h2:$mm']);
    if (ap != null) out.add('$h $ap');
  } else {
    out.add(t);
  }
  out.add(t.replaceAll(' ', ''));
  return out.toList();
}

class Devotee {
  Devotee({
    String? id,
    this.name = '',
    this.age = '',
    this.gender = 'Male',
    this.idType = 'Aadhaar Card',
    this.idNumber = '',
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();

  final String id;
  String name, age, gender, idType, idNumber;

  bool get isAadhaar => idType.toLowerCase().contains('aadhaar');

  /// Value typed into the TTD site (Aadhaar without spaces).
  String get siteIdNumber =>
      isAadhaar ? idNumber.replaceAll(RegExp(r'\D'), '') : idNumber.trim();

  Devotee copy() => Devotee(
        id: id,
        name: name,
        age: age,
        gender: gender,
        idType: idType,
        idNumber: idNumber,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'age': age,
        'gender': gender,
        'idType': idType,
        'idNumber': idNumber,
      };

  factory Devotee.fromJson(Map<String, dynamic> j) => Devotee(
        id: j['id'] as String?,
        name: (j['name'] ?? '') as String,
        age: (j['age'] ?? '') as String,
        gender: (j['gender'] ?? 'Male') as String,
        idType: (j['idType'] ?? 'Aadhaar Card') as String,
        idNumber: (j['idNumber'] ?? '') as String,
      );
}

class Booking {
  Booking({
    this.phone = '',
    this.date,
    this.slot = '',
    List<Devotee>? devotees,
    this.email = '',
    this.city = '',
    this.state = '',
    this.country = 'India',
    this.pincode = '',
  }) : devotees = devotees ?? [];

  String phone, slot, email, city, state, country, pincode;
  DateTime? date;
  List<Devotee> devotees;

  int get total => devotees.length * 300;

  bool get isBlank =>
      phone.isEmpty &&
      date == null &&
      slot.isEmpty &&
      devotees.isEmpty &&
      email.isEmpty &&
      city.isEmpty &&
      state.isEmpty &&
      pincode.isEmpty;

  /// Names of required things that are still empty.
  List<String> missing() {
    final m = <String>[];
    if (phone.length != 10) m.add('phone number');
    if (date == null) m.add('date');
    if (slot.trim().isEmpty) m.add('slot time');
    if (devotees.isEmpty) m.add('devotees');
    if (email.trim().isEmpty) m.add('email');
    if (city.trim().isEmpty) m.add('city');
    if (state.trim().isEmpty) m.add('state');
    if (country.trim().isEmpty) m.add('country');
    if (pincode.length != 6) m.add('pincode');
    return m;
  }

  Map<String, dynamic> toJson() => {
        'phone': phone,
        'date': date?.toIso8601String(),
        'slot': slot,
        'devotees': devotees.map((d) => d.toJson()).toList(),
        'email': email,
        'city': city,
        'state': state,
        'country': country,
        'pincode': pincode,
      };

  factory Booking.fromJson(Map<String, dynamic> j) => Booking(
        phone: (j['phone'] ?? '') as String,
        date: j['date'] == null ? null : DateTime.tryParse(j['date'] as String),
        slot: (j['slot'] ?? '') as String,
        devotees: ((j['devotees'] ?? []) as List)
            .map((e) => Devotee.fromJson(e as Map<String, dynamic>))
            .toList(),
        email: (j['email'] ?? '') as String,
        city: (j['city'] ?? '') as String,
        state: (j['state'] ?? '') as String,
        country: (j['country'] ?? 'India') as String,
        pincode: (j['pincode'] ?? '') as String,
      );

  String encode() => jsonEncode(toJson());
}

// ===== storage.dart =====
/// Saves the booking details (including ID numbers) in encrypted storage.
class Store {
  static const _key = 'booking_v1';
  static const _s = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static Future<Booking> load() async {
    try {
      final raw = await _s.read(key: _key);
      if (raw == null || raw.isEmpty) return Booking();
      return Booking.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return Booking();
    }
  }

  static Future<void> save(Booking b) => _s.write(key: _key, value: b.encode());

  static Future<void> clear() => _s.delete(key: _key);
}

// ===== theme.dart =====
const kMaroon = Color(0xFF4A1B0C);
const kClay = Color(0xFF993C1D);
const kSaffron = Color(0xFFEF9F27);
const kCream = Color(0xFFFFF8EC);
const kLine = Color(0xFFE8C99A);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: kClay).copyWith(
    primary: kClay,
    secondary: kSaffron,
  );
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c, width: w),
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kCream,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: border(kLine),
      enabledBorder: border(kLine),
      focusedBorder: border(kClay, 1.5),
      errorBorder: border(Colors.red.shade700),
      focusedErrorBorder: border(Colors.red.shade700, 1.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kSaffron,
        foregroundColor: kMaroon,
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kClay,
        minimumSize: const Size.fromHeight(46),
        side: const BorderSide(color: kClay),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}

/// Maroon banner at the top of a screen.
class Header extends StatelessWidget {
  const Header({super.key, required this.title, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: kMaroon,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Om namo venkatesaya',
                    style: TextStyle(color: kSaffron, fontSize: 13)),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 14),
            Text(title,
                style: const TextStyle(
                    color: Color(0xFFFAEEDA),
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    height: 1.2)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!,
                  style:
                      const TextStyle(color: Color(0xFFF5C4B3), fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}

/// White rounded card with a thin saffron border.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kLine),
      ),
      child: child,
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(text,
            style: const TextStyle(
                color: kClay, fontSize: 14, fontWeight: FontWeight.w600)),
      );
}

// ===== screens/devotee_sheet.dart =====
/// Bottom sheet to add or edit one devotee. Returns the saved devotee.
Future<Devotee?> showDevoteeSheet(BuildContext context, {Devotee? existing}) {
  return showModalBottomSheet<Devotee>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: kCream,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _DevoteeSheet(existing: existing),
  );
}

class _DevoteeSheet extends StatefulWidget {
  const _DevoteeSheet({this.existing});
  final Devotee? existing;

  @override
  State<_DevoteeSheet> createState() => _DevoteeSheetState();
}

class _DevoteeSheetState extends State<_DevoteeSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name, _age, _idNo;
  late String _gender, _idType;

  @override
  void initState() {
    super.initState();
    final d = widget.existing;
    _name = TextEditingController(text: d?.name ?? '');
    _age = TextEditingController(text: d?.age ?? '');
    _idNo = TextEditingController(text: d?.idNumber ?? '');
    _gender = d?.gender ?? genders.first;
    _idType = d?.idType ?? idTypes.first;
  }

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _idNo.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final d = widget.existing ?? Devotee();
    d.name = _name.text.trim();
    d.age = _age.text.trim();
    d.gender = _gender;
    d.idType = _idType;
    d.idNumber = _idNo.text.trim();
    Navigator.pop(context, d);
  }

  @override
  Widget build(BuildContext context) {
    final isAadhaar = _idType.toLowerCase().contains('aadhaar');
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.existing == null ? 'Add devotee' : 'Edit devotee',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: kMaroon)),
              const SizedBox(height: 14),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter the name' : null,
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _age,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Age'),
                      validator: (v) {
                        final n = int.tryParse((v ?? '').trim());
                        return (n == null || n < 1 || n > 120)
                            ? 'Enter age'
                            : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _gender,
                      decoration: const InputDecoration(labelText: 'Gender'),
                      items: genders
                          .map((g) =>
                              DropdownMenuItem(value: g, child: Text(g)))
                          .toList(),
                      onChanged: (v) => setState(() => _gender = v ?? _gender),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _idType,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Photo ID proof'),
                items: idTypes
                    .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                    .toList(),
                onChanged: (v) => setState(() => _idType = v ?? _idType),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _idNo,
                keyboardType:
                    isAadhaar ? TextInputType.number : TextInputType.text,
                decoration: const InputDecoration(labelText: 'Photo ID number'),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return 'Enter the ID number';
                  if (isAadhaar && t.replaceAll(RegExp(r'\D'), '').length != 12) {
                    return 'Aadhaar must have 12 digits';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 18),
              FilledButton(onPressed: _save, child: const Text('Save devotee')),
            ],
          ),
        ),
      ),
    );
  }
}

// ===== screens/details_screen.dart =====
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

// ===== screens/home_screen.dart =====
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
          const Header(
            title: 'Tirumala special entry darshan',
            subtitle: 'Rs 300 per devotee',
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
                                      missing.isEmpty
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
                              _row('Phone',
                                  _b.phone.isEmpty ? '-' : '+91 ${_b.phone}'),
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
                              const Divider(height: 22),
                              _row('Total', 'Rs ${_b.total}'),
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

// ===== screens/browser_screen.dart =====
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
      maxAttempts: 8),
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
      const Duration(seconds: 20),
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
          Expanded(child: WebViewWidget(controller: _c)),
          _panel(),
        ],
      ),
    );
  }
}

// ===== main.dart =====
void main() => runApp(const TtdApp());

class TtdApp extends StatelessWidget {
  const TtdApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TTD Helper',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const HomeScreen(),
    );
  }
}

// ===== page automation script (runs inside the TTD page) =====
const kAutomationJs = r'''
(function () {
  if (window.__ttd && window.__ttd.v === 4) return;
  const state = (window.__ttd && window.__ttd.state) || { sawDialog: false, gone: 0, iconClicks: 0 };

  // ---------- small helpers ----------
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const norm = (s) =>
    (s || '')
      .toString()
      .replace(/([a-z])([A-Z])/g, '$1 $2')
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, ' ')
      .trim();
  const vis = (e) => {
    if (!e || !e.getBoundingClientRect) return false;
    const r = e.getBoundingClientRect();
    if (r.width <= 0 || r.height <= 0) return false;
    const s = getComputedStyle(e);
    return s.visibility !== 'hidden' && s.display !== 'none';
  };
  const has = (text, keys) => {
    const x = ' ' + norm(text) + ' ';
    return keys.some((k) => x.includes(' ' + norm(k) + ' '));
  };
  const post = (o) => {
    try {
      TTD.postMessage(JSON.stringify(o));
    } catch (e) {}
  };
  const done = (ok, msg, extra) =>
    post(Object.assign({ type: 'result', ok: !!ok, msg: msg || '' }, extra || {}));
  const run = async (fn) => {
    try {
      await fn();
    } catch (e) {
      done(false, String(e));
    }
  };
  const PE = typeof PointerEvent === 'function' ? PointerEvent : MouseEvent;

  function fireClick(el) {
    try {
      el.scrollIntoView({ block: 'center' });
    } catch (e) {}
    const r = el.getBoundingClientRect();
    const o = {
      bubbles: true,
      cancelable: true,
      view: window,
      clientX: r.left + r.width / 2,
      clientY: r.top + r.height / 2,
    };
    el.dispatchEvent(new PE('pointerdown', o));
    el.dispatchEvent(new MouseEvent('mousedown', o));
    el.dispatchEvent(new PE('pointerup', o));
    el.dispatchEvent(new MouseEvent('mouseup', o));
    el.dispatchEvent(new MouseEvent('click', o));
  }

  const PHONE = ['mobile', 'mobile number', 'registered mobile number', 'phone', 'phone number'];

  function labelOf(el) {
    let t = [
      el.placeholder,
      el.getAttribute('aria-label'),
      el.getAttribute('formcontrolname'),
      el.getAttribute('name'),
    ]
      .filter(Boolean)
      .join(' ');
    let lab = null;
    if (el.id) {
      try {
        lab = document.querySelector('label[for="' + el.id + '"]');
      } catch (e) {}
    }
    if (!lab) {
      const ff = el.closest('mat-form-field,.mat-form-field,.mat-mdc-form-field');
      if (ff) lab = ff.querySelector('label,mat-label');
    }
    if (!lab && el.parentElement) lab = el.parentElement.querySelector('label');
    if (lab) t += ' ' + lab.innerText;
    return t;
  }

  function setVal(el, v) {
    el.scrollIntoView({ block: 'center' });
    el.focus();
    let ok = false;
    // Typing through execCommand fires real input events, which frameworks trust most.
    try {
      if (typeof document.execCommand === 'function') {
        if (el.select) el.select();
        ok = document.execCommand('insertText', false, v) && el.value === v;
      }
    } catch (e) {}
    if (!ok) {
      const proto =
        el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
      const d = Object.getOwnPropertyDescriptor(proto, 'value');
      d.set.call(el, v);
      el.dispatchEvent(new Event('input', { bubbles: true }));
    }
    el.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    el.dispatchEvent(new Event('blur', { bubbles: true }));
  }

  const SKIP = ['hidden', 'checkbox', 'radio', 'button', 'submit', 'file'];
  const inputs = (keys) =>
    [...document.querySelectorAll('input,textarea')].filter(
      (e) => vis(e) && !SKIP.includes(e.type) && has(labelOf(e), keys)
    );
  const selects = (keys) =>
    [...document.querySelectorAll('select,mat-select,[role=combobox]')].filter(
      (e) => e.tagName !== 'INPUT' && vis(e) && has(labelOf(e), keys)
    );

  function findText(texts, exact) {
    const want = texts.map(norm);
    let best = null;
    let bl = 1e9;
    document
      .querySelectorAll(
        'button,a,li,span,div,label,mat-option,[role=button],[role=option],[role=menuitem],[role=tab]'
      )
      .forEach((e) => {
        if (!vis(e)) return;
        const t = norm(e.innerText);
        if (!t || t.length > 60) return;
        const ok = want.some((w) =>
          exact ? t === w : t === w || (' ' + t + ' ').includes(' ' + w + ' ')
        );
        if (ok && t.length <= bl) {
          best = e;
          bl = t.length;
        }
      });
    return best;
  }

  function clickText(texts, exact) {
    const best = findText(texts, exact);
    if (best) {
      best.scrollIntoView({ block: 'center' });
      best.click();
      return true;
    }
    return false;
  }

  function isDisabled(el) {
    const b = el.closest('button,[role=button]') || el;
    return (
      b.disabled === true ||
      b.getAttribute('aria-disabled') === 'true' ||
      /disabled/i.test(b.className || '') ||
      getComputedStyle(b).pointerEvents === 'none'
    );
  }

  // ---------- typing (works with masked / framework inputs) ----------
  const digits = (s) => (s || '').replace(/\D/g, '');
  function sameVal(cur, want) {
    if (digits(want).length >= 6) return digits(cur).endsWith(digits(want));
    const a = norm(cur);
    const b = norm(want);
    return a === b || (b.length > 0 && a.includes(b));
  }
  function setNative(el, v) {
    const proto =
      el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, v);
  }
  async function typeInto(el, text, keysOnly) {
    el.scrollIntoView({ block: 'center' });
    el.focus();
    try {
      el.click();
    } catch (e) {}
    if (!keysOnly) {
      try {
        el.select();
        document.execCommand('delete');
        document.execCommand('insertText', false, text);
      } catch (e) {}
      await sleep(200);
      if (sameVal(el.value, text)) return true;
    }
    // fall back to key-by-key typing
    setNative(el, '');
    el.dispatchEvent(new Event('input', { bubbles: true }));
    for (const ch of text) {
      el.dispatchEvent(new KeyboardEvent('keydown', { key: ch, bubbles: true }));
      el.dispatchEvent(new KeyboardEvent('keypress', { key: ch, bubbles: true }));
      el.dispatchEvent(
        new InputEvent('beforeinput', { data: ch, inputType: 'insertText', bubbles: true, cancelable: true })
      );
      setNative(el, el.value + ch);
      el.dispatchEvent(new InputEvent('input', { data: ch, inputType: 'insertText', bubbles: true }));
      el.dispatchEvent(new KeyboardEvent('keyup', { key: ch, bubbles: true }));
      await sleep(45);
    }
    el.dispatchEvent(new Event('change', { bubbles: true }));
    await sleep(150);
    return sameVal(el.value, text);
  }
  async function enter(el, value) {
    setVal(el, value);
    await sleep(150);
    if (sameVal(el.value, value)) return true;
    return await typeInto(el, value);
  }

  function present(texts) {
    const want = texts.map(norm);
    return [
      ...document.querySelectorAll('a,button,span,li,div,p,h1,h2,h3,h4,[role=button],[role=menuitem]'),
    ].some((e) => {
      if (!vis(e)) return false;
      const t = norm(e.innerText);
      return t && t.length < 40 && want.some((w) => t === w);
    });
  }

  // ---------- dropdowns (works with native, mat-select and custom ones) ----------
  function labelEls(keys) {
    const want = keys.map(norm);
    const c = [];
    document
      .querySelectorAll('label,mat-label,span,div,p,legend,h1,h2,h3,h4,h5,h6')
      .forEach((e) => {
        if (!vis(e)) return;
        const t = norm(e.innerText);
        if (t && t.length < 40 && want.includes(t)) c.push(e);
      });
    return c.filter((e) => !c.some((o) => o !== e && e.contains(o)));
  }

  function controlFor(lab) {
    let c = lab;
    for (let i = 0; i < 5 && c.parentElement; i++) {
      c = c.parentElement;
      const r = c.getBoundingClientRect();
      if (r.height >= 40 && r.height <= 170) return c;
    }
    return lab.parentElement || lab;
  }

  const OPT_STRICT = 'mat-option,[role=option],li,.mat-option,.mat-mdc-option,.option';
  const OPT_LOOSE = OPT_STRICT + ',.dropdown-item,button,a,div,span,p';

  function findOption(value, ctl, strict) {
    const w = norm(value);
    const pool = [...document.querySelectorAll(strict ? OPT_STRICT : OPT_LOOSE)].filter(
      (e) => vis(e) && !ctl.contains(e) && !e.contains(ctl)
    );
    const t = (e) => norm(e.innerText);
    let c = pool.filter((e) => t(e) === w);
    if (!c.length && !strict) {
      c = pool.filter((e) => {
        const x = t(e);
        return x && x.length <= w.length + 6 && x.startsWith(w.slice(0, 4));
      });
    }
    return c.length ? c[c.length - 1] : null;
  }

  function optionTexts(ctl) {
    return [...document.querySelectorAll('mat-option,[role=option],li')]
      .filter((e) => vis(e) && !ctl.contains(e))
      .map((e) => (e.innerText || '').trim())
      .filter((s) => s && s.length < 30);
  }

  async function openAndPick(ctl, value, strict) {
    ctl.scrollIntoView({ block: 'center' });
    await sleep(250);
    const r = ctl.getBoundingClientRect();
    const hit =
      (document.elementFromPoint && document.elementFromPoint(r.left + r.width * 0.5, r.top + r.height * 0.7)) ||
      ctl;
    fireClick(hit);
    await sleep(700);
    let opt = findOption(value, ctl, strict);
    if (!opt) {
      const trig = ctl.querySelector(
        'mat-select,[role=combobox],[role=button],.mat-select-trigger,.mat-mdc-select-trigger,mat-icon,svg,button'
      );
      if (trig) {
        fireClick(trig);
        await sleep(700);
        opt = findOption(value, ctl, strict);
      }
    }
    if (!opt) {
      const seen = optionTexts(ctl).slice(0, 6).join(' | ');
      return { ok: false, why: 'option "' + value + '" not found' + (seen ? ' (page shows: ' + seen + ')' : '') };
    }
    fireClick(opt);
    await sleep(500);
    return { ok: true };
  }

  async function pickFrom(el, value) {
    const w = norm(value);
    if (el.tagName === 'SELECT') {
      const o =
        [...el.options].find((x) => norm(x.text) === w) ||
        [...el.options].find((x) => norm(x.text).includes(w));
      if (!o) return false;
      el.value = o.value;
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
      return true;
    }
    el.scrollIntoView({ block: 'center' });
    fireClick(el);
    await sleep(600);
    const o = findOption(value, el, true);
    if (!o) return false;
    fireClick(o);
    await sleep(400);
    return true;
  }

  async function fillDropdown(keys, value, idx) {
    if (!value) return { ok: false, why: 'no value' };
    const s = selects(keys)[idx];
    if (s && (await pickFrom(s, value))) return { ok: true };
    const labs = labelEls(keys);
    if (!labs[idx]) return { ok: false, why: 'field not found' };
    const lab = labs[idx];
    const ctl = controlFor(lab);
    const res = await openAndPick(ctl, value, false);
    if (!res.ok) return res;
    const after = norm(ctl.innerText);
    if (after === norm(lab.innerText) || after.length <= norm(lab.innerText).length) {
      return { ok: false, why: 'tapped but nothing was selected' };
    }
    return { ok: true };
  }

  async function fillAny(keys, value, idx) {
    if (!value) return false;
    const i = inputs(keys)[idx];
    if (!i || i.disabled) return false;
    await enter(i, value);
    await sleep(450);
    const w = norm(value);
    const opts = [...document.querySelectorAll('mat-option,[role=option]')].filter(vis);
    const o =
      opts.find((e) => norm(e.innerText) === w) ||
      opts.find((e) => norm(e.innerText).includes(w));
    if (o) {
      fireClick(o);
      await sleep(300);
    }
    return true;
  }

  // ---------- forms ----------
  async function fillDevotees(list) {
    let n = 0;
    const fails = [];
    for (let i = 0; i < list.length; i++) {
      const x = list[i];
      let names = inputs(['name']);
      if (!names[i] && i > 0) {
        clickText(['add devotee', 'add pilgrim', 'add member', 'add more devotee'], false);
        await sleep(900);
        names = inputs(['name']);
      }
      if (!names[i]) {
        if (i === 0) return { n: -1, fails };
        fails.push('devotee ' + (i + 1) + ' form');
        continue;
      }
      const tag = list.length > 1 ? ' ' + (i + 1) : '';
      if (await fillAny(['name'], x.name, i)) n++;
      else fails.push('name' + tag);
      if (!(await fillAny(['age'], x.age, i))) fails.push('age' + tag);
      const g = await fillDropdown(['gender', 'sex'], x.gender, i);
      if (!g.ok) fails.push('gender' + tag + ' (' + g.why + ')');
      const p = await fillDropdown(['photo id proof', 'id proof', 'id type'], x.idType, i);
      if (!p.ok) fails.push('ID proof' + tag + ' (' + p.why + ')');
      await sleep(600);
      if (!(await fillAny(['photo id number', 'id number', 'id no'], x.idNumber, i)))
        fails.push('ID number' + tag);
    }
    return { n, fails };
  }

  async function fillGeneral(g) {
    let n = 0;
    const fails = [];
    const items = [
      ['email', ['email', 'email id', 'mail id'], g.email],
      ['city', ['city'], g.city],
      ['state', ['state'], g.state],
      ['country', ['country'], g.country],
      ['pincode', ['pincode', 'pin code', 'zip', 'postal code'], g.pincode],
    ];
    for (const it of items) {
      if (await fillAny(it[1], it[2], 0)) n++;
      else fails.push(it[0]);
      await sleep(250);
    }
    return { n, fails };
  }

  // ---------- login icon ----------
  const LOGIN_RE = /log[-_ ]?in|sign[-_ ]?in|exit_to_app/i;
  const LOGOUT_RE = /log[-_ ]?out|sign[-_ ]?out|power/i;

  // The element must really be on screen and on top (not hidden, off-screen or covered).
  function hitOk(e) {
    if (!document.elementFromPoint) return true;
    const r = e.getBoundingClientRect();
    const cx = r.left + r.width / 2;
    const cy = r.top + r.height / 2;
    if (cx < 0 || cy < 0 || cx > window.innerWidth || cy > window.innerHeight) return false;
    const h = document.elementFromPoint(cx, cy);
    return !!h && (h === e || e.contains(h));
  }
  const smallNoText = (e, min, max) => {
    const r = e.getBoundingClientRect();
    return (
      r.width >= min && r.width <= max && r.height >= min && r.height <= max &&
      (e.innerText || '').trim().length <= 20
    );
  };
  const clickableOf = (e) => e.closest('button,a,[role=button]') || e;

  const LOGIN_ATTR =
    '[class*="login" i],[id*="login" i],[aria-label*="login" i],[title*="login" i],' +
    '[alt*="login" i],[src*="login" i],[class*="signin" i],[aria-label*="sign in" i]';

  let lastIconInfo = '';
  function headerIcon() {
    // 1) elements that say "login" in their class, id, title or image name
    const byAttr = [...document.querySelectorAll(LOGIN_ATTR)].filter(
      (e) => vis(e) && smallNoText(e, 16, 100) && hitOk(e)
    );
    if (byAttr.length) {
      lastIconInfo = 'by name';
      return clickableOf(byAttr[0]);
    }
    // 2) the right-most small icon near the top of the page
    const W = window.innerWidth;
    const c = [
      ...document.querySelectorAll('button,a,[role=button],mat-icon,i,svg,img,span,div'),
    ].filter((e) => {
      if (!vis(e) || !smallNoText(e, 18, 90)) return false;
      const r = e.getBoundingClientRect();
      return r.left > W * 0.7 && r.top + (window.scrollY || 0) < 650 && hitOk(e);
    });
    lastIconInfo = c.length + ' icons near top right';
    if (!c.length) return null;
    c.sort((a, b) => {
      const ra = a.getBoundingClientRect();
      const rb = b.getBoundingClientRect();
      return rb.right - ra.right || rb.width * rb.height - ra.width * ra.height;
    });
    return clickableOf(c[0]);
  }

  // The mobile number box, found by label, by type, or by the text around it.
  function phoneInput() {
    let el = inputs(PHONE)[0];
    if (el) return el;
    const all = [...document.querySelectorAll('input,textarea')].filter(
      (e) => vis(e) && !SKIP.includes(e.type)
    );
    el = all.find(
      (e) =>
        e.type === 'tel' ||
        /tel|numeric|decimal/i.test(e.getAttribute('inputmode') || '') ||
        /tel/i.test(e.getAttribute('autocomplete') || '')
    );
    if (el) return el;
    for (const e of all) {
      let c = e;
      for (let i = 0; i < 5 && c.parentElement; i++) {
        c = c.parentElement;
        const t = norm(c.innerText);
        if (t.length > 120) break;
        const n = [...c.querySelectorAll('input,textarea')].filter(
          (x) => vis(x) && !SKIP.includes(x.type)
        ).length;
        if (n === 1 && has(t, PHONE)) return e;
      }
    }
    if (all.length === 1 && present(['get otp'])) return all[0];
    return null;
  }
  function iconKind(el) {
    const h = (el.outerHTML || '').slice(0, 600);
    if (LOGOUT_RE.test(h)) return 'logout';
    if (LOGIN_RE.test(h)) return 'login';
    return 'unknown';
  }
  // The phone box of the login dialog. Falls back to "the input next to the Get OTP button"
  // because the site's label may not be a normal <label>.
  function getOtpButton() {
    const m = [...document.querySelectorAll('button,[role=button],a,div,span')].filter(
      (e) => vis(e) && norm(e.innerText) === 'get otp'
    );
    if (!m.length) return null;
    const inner = m[m.length - 1];
    return inner.closest('button,[role=button]') || inner;
  }
  const loginOpen = () => !!getOtpButton() || !!phoneInput();

  // Possible places to tap for the login icon, best guess first.
  function loginTargets() {
    const out = [];
    const add = (e) => {
      if (e && vis(e) && !out.includes(e)) out.push(e);
    };
    const hi = headerIcon();
    if (hi) {
      add(hi);
      const r = hi.getBoundingClientRect();
      add(document.elementFromPoint && document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2));
      add(hi.querySelector('svg,img,i,mat-icon'));
    }
    return out;
  }
  const descr = (e) =>
    e.tagName.toLowerCase() + (typeof e.className === 'string' && e.className ? '.' + e.className.split(' ')[0] : '');

  function otpVisible() {
    return [...document.querySelectorAll('input,button,label,span,div,p,h1,h2,h3')].some((e) => {
      if (!vis(e)) return false;
      const t = e.tagName === 'INPUT' ? labelOf(e) : e.innerText;
      const n = norm(t);
      return n && n.length < 80 && (' ' + n + ' ').includes(' otp ');
    });
  }

  // ---------- calendar ----------
  const MONTHS = ['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december'];
  const MONTH_RE = new RegExp('^(' + MONTHS.join('|') + ')\\s+\\d{4}$', 'i');

  function calHeader() {
    return [...document.querySelectorAll('div,span,h1,h2,h3,h4,h5,p,th,button')].find(
      (e) => vis(e) && MONTH_RE.test((e.innerText || '').trim())
    );
  }

  async function gotoMonth(year, month0) {
    for (let k = 0; k < 14; k++) {
      const h = calHeader();
      if (!h) return true;
      const parts = h.innerText.trim().toLowerCase().split(/\s+/);
      const diff = (year - parseInt(parts[1], 10)) * 12 + (month0 - MONTHS.indexOf(parts[0]));
      if (diff === 0) return true;
      const hr = h.getBoundingClientRect();
      const W = window.innerWidth;
      const arrows = [
        ...document.querySelectorAll('button,[role=button],a,mat-icon,i,svg,img,span,div'),
      ].filter((e) => {
        if (!vis(e)) return false;
        const r = e.getBoundingClientRect();
        const sideOk = diff > 0 ? r.left > W * 0.7 : r.right < W * 0.3;
        return (
          r.width >= 18 && r.width <= 80 && r.height >= 18 && r.height <= 80 &&
          r.top > hr.top && r.top < hr.bottom + 520 && sideOk &&
          (e.innerText || '').trim().length <= 16
        );
      });
      if (!arrows.length) return false;
      arrows.sort((a, b) => {
        const ra = a.getBoundingClientRect();
        const rb = b.getBoundingClientRect();
        return rb.width * rb.height - ra.width * ra.height;
      });
      fireClick(arrows[0].closest('button,[role=button],a') || arrows[0]);
      await sleep(650);
    }
    return false;
  }

  function bgOf(el) {
    let e = el;
    for (let i = 0; i < 5 && e; i++) {
      const c = getComputedStyle(e).backgroundColor || '';
      const m = c.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)/);
      if (m && (m[4] === undefined || parseFloat(m[4]) > 0.2)) return [+m[1], +m[2], +m[3]];
      e = e.parentElement;
    }
    return null;
  }
  function dateState(rgb) {
    if (!rgb) return 'ok';
    const r = rgb[0], g = rgb[1], b = rgb[2];
    if (r > 110 && g < 80 && b < 80) return 'full';
    if (Math.abs(r - g) < 14 && Math.abs(g - b) < 14 && r > 170 && r < 236) return 'na';
    if (b > r + 30 && g > 140 && b > g) return 'notreleased'; // light blue, not the purple "selected" cell
    return 'ok';
  }

  // ---------- public API ----------
  window.__ttd = {
    v: 4,
    state,

    openLogin() {
      return run(async () => {
        if (loginOpen()) return done(true, 'Login box is open');
        window.scrollTo(0, 0);
        await sleep(300);
        if (present(['login', 'log in', 'sign in']) && clickText(['login', 'log in', 'sign in'], true)) {
          await sleep(1000);
          if (loginOpen()) return done(true, 'Opened login');
        }
        const t = loginTargets();
        if (!t.length) return done(false, 'Login icon not found (' + lastIconInfo + ')');
        if (iconKind(t[0]) === 'logout') return done(true, 'Already signed in', { skip: true });
        state.iconClicks++;
        const tried = [];
        for (const el of t.slice(0, 4)) {
          if (iconKind(el) === 'logout') continue;
          tried.push(descr(el));
          fireClick(el);
          await sleep(1000);
          if (loginOpen()) return done(true, 'Opened login');
        }
        done(false, 'Tapped ' + tried.join(', ') + ' but no login box appeared.');
      });
    },

    fillPhone(p) {
      return run(async () => {
        const el = phoneInput();
        if (!el) return done(false, 'Waiting for the phone box...');
        const ok = await enter(el, p);
        await sleep(700);
        if (!ok) return done(false, 'Could not type the number (box shows "' + (el.value || '') + '")');
        let btn = getOtpButton();
        if (btn && isDisabled(btn)) {
          // The page may only trust real key events: type the number again key by key.
          await typeInto(el, p, true);
          await sleep(800);
          btn = getOtpButton();
        }
        if (!btn) return done(true, 'Phone filled, tap Get OTP');
        if (isDisabled(btn)) return done(false, 'Number typed but Get OTP is still disabled');
        fireClick(btn);
        await sleep(1000);
        done(true, 'Phone filled, OTP requested');
      });
    },

    loggedIn() {
      return run(async () => {
        const dlg = inputs(['otp', 'enter otp']);
        if (dlg.length || phoneInput() || otpVisible()) {
          state.sawDialog = true;
          state.gone = 0;
          return done(false, '');
        }
        const ic = headerIcon();
        if (ic && iconKind(ic) === 'logout') return done(true, 'Signed in');
        if (state.sawDialog) {
          state.gone++;
          if (state.gone >= 2) return done(true, 'Signed in');
        }
        done(false, '');
      });
    },

    click(texts, exact) {
      return run(async () => {
        if (clickText(texts, !!exact)) {
          await sleep(900);
          done(true, 'Opened ' + texts[0]);
        } else {
          done(false, 'Waiting for "' + texts[0] + '"...');
        }
      });
    },

    pickDate(a) {
      return run(async () => {
        const ok = await gotoMonth(a.year, a.month - 1);
        if (!ok) return done(false, 'Could not reach that month on the calendar');
        const hdr = calHeader();
        const top = hdr ? hdr.getBoundingClientRect().bottom : 0;
        const day = String(a.day);
        let c = [
          ...document.querySelectorAll('td,button,a,div,span,li,[role=gridcell]'),
        ].filter((e) => {
          if (!vis(e)) return false;
          const r = e.getBoundingClientRect();
          return norm(e.innerText) === day && r.width <= 150 && r.height <= 150 && r.top >= top - 5 && r.top < top + 800;
        });
        c = c.filter((e) => !c.some((o) => o !== e && e.contains(o)));
        if (!c.length) return done(false, 'Waiting for day ' + day + ' on the calendar...');
        const cell = c[0];
        const st = dateState(bgOf(cell));
        if (st === 'full') return done(false, 'Quota is full on this date. Pick another date.');
        if (st === 'na') return done(false, 'Slots are not available on this date.');
        if (st === 'notreleased') return done(false, 'Quota is not released for this date yet.');
        fireClick(cell);
        await sleep(900);
        done(true, 'Date ' + day + ' selected');
      });
    },

    tickets(n) {
      return run(async () => {
        const want = String(n);
        const keys = ['number of tickets', 'no of tickets', 'tickets'];
        const s = selects(keys)[0];
        if (s && (await pickFrom(s, want))) return done(true, 'Tickets set to ' + want);
        const labs = labelEls(keys);
        if (!labs[0]) return done(false, 'Waiting for the tickets box...');
        const ctl = controlFor(labs[0]);
        const words = norm(ctl.innerText).split(' ');
        if (words[words.length - 1] === want) return done(true, 'Tickets already ' + want);
        const r = await openAndPick(ctl, want, true);
        done(r.ok, r.ok ? 'Tickets set to ' + want : 'Tickets: ' + r.why);
      });
    },

    slot(a) {
      return run(async () => {
        const all = [...document.querySelectorAll('div,span,p,label,li,mat-radio-button')].filter(
          (e) => vis(e) && (e.innerText || '').length < 90
        );
        let el = null;
        let used = '';
        for (const v of a.slots) {
          const w = ' ' + norm(v) + ' ';
          const c = all.filter((e) => (' ' + norm(e.innerText) + ' ').includes(w));
          const pref = c.filter((e) => norm(e.innerText).includes('slot time'));
          const pool = pref.length ? pref : c;
          if (pool.length) {
            el = pool.sort((x, y) => x.innerText.length - y.innerText.length)[0];
            used = v;
            break;
          }
        }
        if (!el) {
          const seen = all
            .map((e) => (e.innerText || '').trim())
            .filter((s) => /^slot time/i.test(s) && s.length < 30)
            .slice(0, 6)
            .join(' | ');
          return done(false, 'Slot ' + (a.slots[0] || '') + ' not found' + (seen ? ' (page shows: ' + seen + ')' : ''));
        }
        let card = el;
        let radio = null;
        for (let i = 0; i < 7 && card; i++) {
          radio = card.querySelector(
            'input[type=radio],mat-radio-button,[role=radio],.mat-radio-outer-circle,.mat-mdc-radio-button'
          );
          if (radio) break;
          card = card.parentElement;
        }
        if (!card) card = el;
        if (/\b(sold out|full|not available)\b/.test(norm(card.innerText)))
          return done(false, 'That slot is full. Pick another slot.');
        if (radio) {
          if (radio.tagName === 'INPUT') radio.click();
          else fireClick(radio);
        } else {
          fireClick(card);
        }
        await sleep(500);
        const inp = card.querySelector('input[type=radio]');
        if (inp && !inp.checked) {
          fireClick(card);
          await sleep(500);
          if (!inp.checked) return done(false, 'Could not tick the slot, tap it yourself');
        }
        done(true, 'Slot ' + used + ' selected');
      });
    },

    next() {
      return run(async () => {
        const onForm = () =>
          present(['pilgrim details']) || (inputs(['name']).length > 0 && inputs(['age']).length > 0);
        if (onForm()) return done(true, 'Pilgrim form is open');
        const btns = [...document.querySelectorAll('button,[role=button],a')].filter(
          (e) =>
            vis(e) &&
            !e.disabled &&
            e.getAttribute('aria-disabled') !== 'true' &&
            ['continue', 'proceed', 'next'].includes(norm(e.innerText))
        );
        if (!btns.length) return done(false, 'Waiting for the Continue button...');
        const b = btns[btns.length - 1];
        b.scrollIntoView({ block: 'center' });
        b.click();
        await sleep(1500);
        done(onForm(), 'Clicked Continue');
      });
    },

    devotees(a) {
      return run(async () => {
        const r = await fillDevotees(a.list);
        if (r.n < 0) return done(false, 'Waiting for the devotee form...');
        done(
          r.n > 0 && r.fails.length === 0,
          r.fails.length
            ? 'Not filled: ' + r.fails.join(', ') + '. Fill these yourself.'
            : 'Filled ' + r.n + ' of ' + a.list.length + ' devotees'
        );
      });
    },

    general(a) {
      return run(async () => {
        const r = await fillGeneral(a);
        done(
          r.n >= 3 && r.fails.length <= 1,
          r.fails.length ? 'Not filled: ' + r.fails.join(', ') : 'General details filled'
        );
      });
    },

    fillAll(a) {
      return run(async () => {
        const d = await fillDevotees(a.list);
        const g = await fillGeneral(a.general);
        const fails = d.fails.concat(g.fails);
        done(
          d.n > 0 || g.n > 0,
          fails.length
            ? 'Filled what I could. Not filled: ' + fails.join(', ')
            : 'Filled devotees and general details'
        );
      });
    },
  };
})();
''';

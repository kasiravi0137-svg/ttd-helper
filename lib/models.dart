import 'dart:convert';

// Contact details that are always used on the TTD site (never asked in the app).
const kPhone = '7730004220';
const kEmail = 'ravanam8@gmail.com';
const kCity = 'Dornala';
const kState = 'Andhra Pradesh';
const kCountry = 'India';
const kPincode = '523331';

// Which TTD service the app books.
const kServiceSpecial = 'special';
const kServiceArjitha = 'arjitha';
const kServices = {
  kServiceSpecial: 'Special Entry Darshan',
  kServiceArjitha: 'Arjitha Seva',
};
// Arjitha Seva names offered on the TTD "Select Seva" dropdown.
const kSevas = [
  'All',
  'Unjal Seva',
  'Arjitha Brahmotsavam',
  'Kalyanotsavam',
  'Sahasra Deepalankara Seva',
  'Pushpayagam',
  'Float Festival',
];
const kSevaOther = 'Other';
String serviceName(String s) => kServices[s] ?? kServices[kServiceSpecial]!;

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
    this.phone = kPhone,
    this.service = kServiceSpecial,
    this.seva = '',
    this.date,
    this.slot = '',
    List<Devotee>? devotees,
    this.email = kEmail,
    this.city = kCity,
    this.state = kState,
    this.country = kCountry,
    this.pincode = kPincode,
  }) : devotees = devotees ?? [];

  String phone, service, seva, slot, email, city, state, country, pincode;
  DateTime? date;
  List<Devotee> devotees;

  int get total => devotees.length * 300;

  bool get isBlank =>
      service == kServiceSpecial && date == null && slot.isEmpty && devotees.isEmpty;

  /// Names of required things that are still empty.
  List<String> missing() {
    final m = <String>[];
    if (service == kServiceArjitha) {
      if (phone.length != 10) m.add('phone number');
      if (seva.trim().isEmpty) m.add('seva');
      if (devotees.isEmpty) m.add('devotees');
      return m;
    }
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
        'service': service,
        'seva': seva,
        'date': date?.toIso8601String(),
        'slot': slot,
        'devotees': devotees.map((d) => d.toJson()).toList(),
        'email': email,
        'city': city,
        'state': state,
        'country': country,
        'pincode': pincode,
      };

  // Contact details are fixed: whatever was saved before is ignored for them.
  factory Booking.fromJson(Map<String, dynamic> j) => Booking(
        service: kServices.containsKey(j['service']) ? j['service'] as String : kServiceSpecial,
        date: j['date'] == null ? null : DateTime.tryParse(j['date'] as String),
        seva: (j['seva'] ?? '') as String,
        slot: (j['slot'] ?? '') as String,
        devotees: ((j['devotees'] ?? []) as List)
            .map((e) => Devotee.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  String encode() => jsonEncode(toJson());
}

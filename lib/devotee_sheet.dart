import 'package:flutter/material.dart';
import 'models.dart';
import 'theme.dart';

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

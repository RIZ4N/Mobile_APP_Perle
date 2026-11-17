import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/utils/ids.dart';
import '../../../core/widgets/common.dart';
import '../../auth/auth_providers.dart';
import '../../data_providers.dart';
import '../data/item.dart';

/// Formulir tambah barang (tanpa [itemId]) atau ubah barang.
class ItemFormScreen extends ConsumerStatefulWidget {
  const ItemFormScreen({super.key, this.itemId});

  final String? itemId;

  @override
  ConsumerState<ItemFormScreen> createState() => _ItemFormScreenState();
}

class _ItemFormScreenState extends ConsumerState<ItemFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _category = TextEditingController();
  final _unit = TextEditingController(text: defaultUnits.first);
  final _source = TextEditingController();
  final _carrier = TextEditingController();
  final _notes = TextEditingController();
  int _quantity = 1;
  ItemStatus _status = ItemStatus.ada;

  Item? _existing;
  bool _loading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.itemId != null) {
      _loading = true;
      _load();
    }
  }

  Future<void> _load() async {
    final item = await ref.read(itemRepositoryProvider).byId(widget.itemId!);
    if (!mounted) return;
    if (item == null) {
      context.pop();
      return;
    }
    setState(() {
      _existing = item;
      _name.text = item.name;
      _category.text = item.category;
      _unit.text = item.unit;
      _source.text = item.source ?? '';
      _carrier.text = item.carrierName ?? '';
      _notes.text = item.notes ?? '';
      _quantity = item.quantity;
      _status = item.status;
      _loading = false;
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _category, _unit, _source, _carrier, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    // Bila nama pembawa cocok dengan anggota terdaftar, tautkan ke akunnya
    // supaya filter "Punya saya" di checklist packing bekerja.
    final carrierName = _text(_carrier);
    final members = await ref.read(membersProvider.future);
    final carrier = carrierName == null
        ? null
        : members
              .where(
                (m) => m.fullName.toLowerCase() == carrierName.toLowerCase(),
              )
              .firstOrNull;

    await ref
        .read(itemRepositoryProvider)
        .save(
          Item(
            id: _existing?.id ?? newId(),
            name: _name.text.trim(),
            category: _text(_category) ?? 'Lainnya',
            quantity: _quantity,
            unit: _text(_unit) ?? defaultUnits.first,
            status: _status,
            source: _text(_source),
            carrierId: carrier?.id,
            carrierName: carrier?.fullName ?? carrierName,
            notes: _text(_notes),
            createdBy: _existing?.createdBy ?? ref.read(currentUserIdProvider),
            createdAt: _existing?.createdAt ?? nowIso(),
          ),
        );
    if (mounted) context.pop();
  }

  String? _text(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(membersProvider).value ?? const [];
    final categories = {
      ...defaultItemCategories,
      ...?ref.watch(itemsProvider).value?.map((i) => i.category),
    }.toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.itemId == null ? 'Tambah barang' : 'Ubah barang'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Nama barang'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Masukkan nama barang'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _category,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Kategori'),
                    onChanged: (_) => setState(() {}),
                  ),
                  SuggestionChips(
                    options: categories,
                    selected: _category.text,
                    onSelected: (v) => setState(() => _category.text = v),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      QuantityStepper(
                        value: _quantity,
                        min: 0,
                        onChanged: (v) => setState(() => _quantity = v),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _unit,
                          decoration: const InputDecoration(
                            labelText: 'Satuan',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('Status', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  SegmentedButton<ItemStatus>(
                    segments: [
                      for (final s in ItemStatus.values)
                        ButtonSegment(value: s, label: Text(s.label)),
                    ],
                    selected: {_status},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) =>
                        setState(() => _status = s.first),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _source,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: switch (_status) {
                        ItemStatus.ada => 'Milik siapa',
                        ItemStatus.pinjam => 'Dipinjam dari',
                        ItemStatus.harusBeli => 'Rencana beli di (opsional)',
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _carrier,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Penanggung jawab pembawa',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  SuggestionChips(
                    options: [for (final m in members) m.fullName],
                    selected: _carrier.text,
                    onSelected: (v) => setState(() => _carrier.text = v),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _notes,
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 3,
                    minLines: 1,
                    decoration: const InputDecoration(
                      labelText: 'Catatan (opsional)',
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: const Text('Simpan'),
                  ),
                ],
              ),
            ),
    );
  }
}

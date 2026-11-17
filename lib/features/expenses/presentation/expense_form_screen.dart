import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/utils/ids.dart';
import '../../../core/widgets/common.dart';
import '../../auth/auth_providers.dart';
import '../../data_providers.dart';
import '../data/expense.dart';
import 'receipt_image.dart';

/// Formulir tambah pengeluaran (tanpa [expenseId]) atau lihat/ubah. Anggota
/// hanya bisa mengubah catatannya sendiri; admin bisa mengubah semuanya.
class ExpenseFormScreen extends ConsumerStatefulWidget {
  const ExpenseFormScreen({super.key, this.expenseId});

  final String? expenseId;

  @override
  ConsumerState<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends ConsumerState<ExpenseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _amount = TextEditingController();
  final _category = TextEditingController();
  final _paidBy = TextEditingController();
  final _note = TextEditingController();
  late final String _id = widget.expenseId ?? newId();
  DateTime _spentOn = DateTime.now();
  String? _receiptPath;
  String? _receiptLocalPath;

  Expense? _existing;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.expenseId == null) {
      // Bawaan: yang mencatat dianggap yang menalangi.
      final me = await ref.read(currentProfileProvider.future);
      if (!mounted) return;
      setState(() {
        _paidBy.text = me?.fullName ?? '';
        _loading = false;
      });
      return;
    }
    final e = await ref.read(expenseRepositoryProvider).byId(widget.expenseId!);
    if (!mounted) return;
    if (e == null) {
      context.pop();
      return;
    }
    setState(() {
      _existing = e;
      _description.text = e.description;
      _amount.text = formatThousands(e.amount);
      _category.text = e.category ?? '';
      _paidBy.text = e.paidByName ?? '';
      _note.text = e.note ?? '';
      _spentOn = e.spentOn;
      _receiptPath = e.receiptPath;
      _receiptLocalPath = e.receiptLocalPath;
      _loading = false;
    });
  }

  @override
  void dispose() {
    for (final c in [_description, _amount, _category, _paidBy, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _spentOn,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _spentOn = picked);
  }

  Future<void> _pickReceipt(ImageSource source) async {
    final XFile? picked;
    try {
      // Diperkecil agar unggahan ringan di sinyal lemah.
      picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 70,
      );
    } on Exception {
      if (mounted) {
        showSnack(context, 'Kamera/galeri tidak bisa dibuka. Periksa izinnya.');
      }
      return;
    }
    if (picked == null) return;

    // Salin ke folder aplikasi: berkas hasil kamera bisa dihapus sistem
    // sebelum sempat diunggah.
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'receipts'));
    await dir.create(recursive: true);
    final target = p.join(
      dir.path,
      '${_id}_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await File(picked.path).copy(target);

    if (!mounted) return;
    setState(() {
      _receiptLocalPath = target;
      _receiptPath = null; // foto baru → diunggah ulang saat sinkron
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    String? text(TextEditingController c) {
      final v = c.text.trim();
      return v.isEmpty ? null : v;
    }

    await ref
        .read(expenseRepositoryProvider)
        .save(
          Expense(
            id: _id,
            description: _description.text.trim(),
            amount: parseAmount(_amount.text)!,
            category: text(_category),
            spentOn: _spentOn,
            paidByName: text(_paidBy),
            receiptPath: _receiptPath,
            receiptLocalPath: _receiptLocalPath,
            note: text(_note),
            createdBy: _existing?.createdBy ?? ref.read(currentUserIdProvider),
            createdAt: _existing?.createdAt ?? nowIso(),
          ),
        );
    if (mounted) context.pop();
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: 'Hapus pengeluaran ini?',
      message: 'Total pengeluaran akan dihitung ulang.',
    );
    if (!ok) return;
    await ref.read(expenseRepositoryProvider).delete(_id);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final canEdit =
        _existing == null ||
        ref.watch(isAdminProvider) ||
        _existing!.createdBy == ref.watch(currentUserIdProvider);
    final hasReceipt = _receiptLocalPath != null || _receiptPath != null;
    final members = ref.watch(membersProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _existing == null
              ? 'Tambah pengeluaran'
              : canEdit
              ? 'Ubah pengeluaran'
              : 'Detail pengeluaran',
        ),
        actions: [
          if (_existing != null && canEdit)
            IconButton(
              tooltip: 'Hapus',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _description,
                    enabled: canEdit,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Keterangan',
                      hintText: 'mis. Gas 3 kg',
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Masukkan keterangan'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _amount,
                    enabled: canEdit,
                    keyboardType: TextInputType.number,
                    inputFormatters: [ThousandsInputFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Nominal',
                      prefixText: 'Rp ',
                    ),
                    validator: (v) => parseAmount(v ?? '') == null
                        ? 'Masukkan nominal'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: canEdit ? _pickDate : null,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Tanggal',
                        suffixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                      child: Text(formatDate(_spentOn)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _category,
                    enabled: canEdit,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Kategori'),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (canEdit)
                    SuggestionChips(
                      options: defaultExpenseCategories,
                      selected: _category.text,
                      onSelected: (v) => setState(() => _category.text = v),
                    ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _paidBy,
                    enabled: canEdit,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Dibayar oleh',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (canEdit)
                    SuggestionChips(
                      options: [for (final m in members) m.fullName],
                      selected: _paidBy.text,
                      onSelected: (v) => setState(() => _paidBy.text = v),
                    ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _note,
                    enabled: canEdit,
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 3,
                    minLines: 1,
                    decoration: const InputDecoration(
                      labelText: 'Catatan (opsional)',
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Foto struk',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  if (hasReceipt)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        height: 220,
                        child: InkWell(
                          onTap: () => openReceiptViewer(
                            context,
                            localPath: _receiptLocalPath,
                            remotePath: _receiptPath,
                          ),
                          child: ReceiptImage(
                            localPath: _receiptLocalPath,
                            remotePath: _receiptPath,
                          ),
                        ),
                      ),
                    )
                  else if (!canEdit)
                    const Text('Tidak ada foto struk.'),
                  if (canEdit) ...[
                    const SizedBox(height: 8),
                    Row(
                      spacing: 8,
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickReceipt(ImageSource.camera),
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: const Text('Kamera'),
                          ),
                        ),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickReceipt(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('Galeri'),
                          ),
                        ),
                      ],
                    ),
                    if (hasReceipt)
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _receiptLocalPath = null;
                          _receiptPath = null;
                        }),
                        icon: const Icon(Icons.close),
                        label: const Text('Lepas foto struk'),
                      ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: const Text('Simpan'),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

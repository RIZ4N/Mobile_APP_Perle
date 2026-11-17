import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/common.dart';
import '../../auth/auth_providers.dart';
import '../../data_providers.dart';
import '../../items/data/item.dart';
import '../data/loan_log.dart';

/// Lembar bawah untuk mencatat pinjam/kembali satu barang. Dibuka setelah
/// QR terpindai, atau dari halaman detail barang.
Future<void> showLoanSheet(BuildContext context, Item item) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => Padding(
      // Naik bersama keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _LoanForm(item: item),
    ),
  );
}

class _LoanForm extends ConsumerStatefulWidget {
  const _LoanForm({required this.item});

  final Item item;

  @override
  ConsumerState<_LoanForm> createState() => _LoanFormState();
}

class _LoanFormState extends ConsumerState<_LoanForm> {
  final _person = TextEditingController();
  final _note = TextEditingController();
  LoanAction? _action;
  int _quantity = 1;
  bool _saving = false;

  @override
  void dispose() {
    _person.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save(LoanAction action, int quantity) async {
    final person = _person.text.trim();
    if (person.isEmpty) {
      showSnack(
        context,
        action == LoanAction.pinjam
            ? 'Isi nama peminjam dulu.'
            : 'Isi nama yang mengembalikan dulu.',
      );
      return;
    }
    setState(() => _saving = true);
    final note = _note.text.trim();
    await ref
        .read(loanRepositoryProvider)
        .record(
          itemId: widget.item.id,
          action: action,
          quantity: quantity,
          personName: person,
          note: note.isEmpty ? null : note,
          recordedBy: ref.read(currentUserIdProvider),
        );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '${action.label} $quantity ${widget.item.unit} '
            '${widget.item.name} tercatat.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final holders = ref.watch(outstandingProvider(item.id)).value ?? const [];
    final me = ref.watch(currentProfileProvider).value;

    final onLoan = holders.fold<int>(0, (sum, h) => sum + h.quantity);
    final available = (item.quantity - onLoan).clamp(0, item.quantity);

    // Bawaan: bila semua sedang dipinjam, kemungkinan besar ini pengembalian.
    final action =
        _action ??
        (available == 0 && onLoan > 0 ? LoanAction.kembali : LoanAction.pinjam);

    // Batas jumlah: stok tersedia untuk pinjam; untuk kembali, sebanyak yang
    // dipegang orang itu (atau total dipinjam bila namanya belum dikenali).
    final personKey = _person.text.trim().toLowerCase();
    final heldByPerson = holders
        .where((h) => h.personName.trim().toLowerCase() == personKey)
        .firstOrNull
        ?.quantity;
    final max = action == LoanAction.pinjam
        ? available
        : (heldByPerson ?? onLoan);
    final quantity = max == 0 ? 0 : _quantity.clamp(1, max);

    final blocked = switch (action) {
      LoanAction.pinjam when available == 0 =>
        'Semua unit sedang dipinjam — tidak ada yang bisa dipinjamkan.',
      LoanAction.kembali when onLoan == 0 =>
        'Tidak ada unit yang sedang dipinjam.',
      _ => null,
    };

    final suggestions = action == LoanAction.kembali
        ? [for (final h in holders) h.personName]
        : [?me?.fullName];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(item.name, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Tersedia $available dari ${item.quantity} ${item.unit}'
            '${onLoan > 0 ? ' · $onLoan sedang dipinjam' : ''}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<LoanAction>(
            segments: const [
              ButtonSegment(
                value: LoanAction.pinjam,
                icon: Icon(Icons.north_east),
                label: Text('Pinjam'),
              ),
              ButtonSegment(
                value: LoanAction.kembali,
                icon: Icon(Icons.south_west),
                label: Text('Kembali'),
              ),
            ],
            selected: {action},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _action = s.first),
          ),
          const SizedBox(height: 16),
          if (blocked != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(blocked, textAlign: TextAlign.center),
            )
          else ...[
            TextField(
              controller: _person,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: action == LoanAction.pinjam
                    ? 'Nama peminjam'
                    : 'Dikembalikan oleh',
              ),
              onChanged: (_) => setState(() {}),
            ),
            SuggestionChips(
              options: suggestions,
              selected: _person.text,
              onSelected: (v) => setState(() => _person.text = v),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                // Expanded: label panjang/huruf besar membungkus, tidak
                // mendorong tombol jumlah keluar layar.
                Expanded(
                  child: Text(
                    'Jumlah (${item.unit})',
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
                QuantityStepper(
                  value: quantity,
                  max: max,
                  onChanged: (v) => setState(() => _quantity = v),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Catatan (opsional)',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : () => _save(action, quantity),
              child: Text(
                action == LoanAction.pinjam ? 'Catat pinjam' : 'Catat kembali',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

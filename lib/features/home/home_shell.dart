import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/sync/sync_controller.dart';

/// Kerangka utama: empat tab + tombol Scan di tengah bilah navigasi.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  /// Posisi tombol Scan di bilah navigasi (bukan tab; membuka kamera penuh).
  static const _scanIndex = 2;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Sinkron pertama begitu masuk.
    Future.microtask(() => ref.read(syncControllerProvider.notifier).syncNow());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(syncControllerProvider.notifier).syncNow();
    }
  }

  void _onTap(int index) {
    if (index == _scanIndex) {
      context.push('/scan');
      return;
    }
    final branch = index > _scanIndex ? index - 1 : index;
    widget.shell.goBranch(
      branch,
      initialLocation: branch == widget.shell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final branch = widget.shell.currentIndex;
    return Scaffold(
      body: widget.shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: branch >= _scanIndex ? branch + 1 : branch,
        onDestinationSelected: _onTap,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Barang',
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist_outlined),
            selectedIcon: Icon(Icons.checklist),
            label: 'Packing',
          ),
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner),
            label: 'Scan',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Biaya',
          ),
          NavigationDestination(icon: Icon(Icons.menu), label: 'Lainnya'),
        ],
      ),
    );
  }
}

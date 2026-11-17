import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/widgets/common.dart';
import '../../data_providers.dart';
import '../../qr/qr_codec.dart';
import 'loan_sheet.dart';

/// Kamera pemindai QR. Label barang yang dikenali langsung membuka lembar
/// catat pinjam/kembali; pencarian barang memakai data lokal sehingga tetap
/// bekerja tanpa internet.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionTimeoutMs: 800,
  );

  /// true selama satu hasil pindai sedang ditangani, agar bingkai kamera
  /// berikutnya tidak membuka lembar kedua.
  bool _handling = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;

    _handling = true;
    try {
      final itemId = decodeItemQr(raw);
      final item = itemId == null
          ? null
          : await ref.read(itemRepositoryProvider).byId(itemId);
      if (!mounted) return;

      if (item == null) {
        showSnack(
          context,
          itemId == null
              ? 'QR ini bukan label barang Perle.'
              : 'Barang tidak ada di HP ini. Sinkronkan dulu, atau barangnya '
                    'sudah dihapus.',
        );
        // Jeda supaya pesan yang sama tidak muncul berulang-ulang.
        await Future<void>.delayed(const Duration(seconds: 2));
        return;
      }

      await _controller.stop();
      if (!mounted) return;
      await showLoanSheet(context, item);
      if (mounted) await _controller.start();
    } finally {
      _handling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan QR barang'),
        actions: [
          ValueListenableBuilder(
            valueListenable: _controller,
            builder: (context, state, _) => IconButton(
              tooltip: 'Senter',
              onPressed: state.torchState == TorchState.unavailable
                  ? null
                  : _controller.toggleTorch,
              icon: Icon(
                state.torchState == TorchState.on
                    ? Icons.flash_on
                    : Icons.flash_off,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _CameraError(error: error),
          ),
          const IgnorePointer(child: _ScanFrame()),
        ],
      ),
    );
  }
}

class _ScanFrame extends StatelessWidget {
  const _ScanFrame();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 240,
          height: 240,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white, width: 3),
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Text(
            'Arahkan kamera ke label QR barang',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: EmptyState(
        icon: Icons.no_photography_outlined,
        title: denied ? 'Izin kamera ditolak' : 'Kamera tidak bisa dibuka',
        subtitle: denied
            ? 'Izinkan akses kamera untuk Perle KKN di Pengaturan HP. '
                  'Sementara itu, pinjam/kembali bisa dicatat dari halaman '
                  'detail barang.'
            : 'Pinjam/kembali tetap bisa dicatat dari halaman detail barang.',
      ),
    );
  }
}

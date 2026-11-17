import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data_providers.dart';

/// Foto struk: pakai salinan di HP bila ada (bisa dilihat offline), kalau
/// tidak ambil dari Supabase Storage lewat URL bertanda tangan.
class ReceiptImage extends ConsumerWidget {
  const ReceiptImage({
    super.key,
    this.localPath,
    this.remotePath,
    this.fit = BoxFit.cover,
  });

  final String? localPath;
  final String? remotePath;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = localPath == null ? null : File(localPath!);
    if (local != null && local.existsSync()) {
      return Image.file(local, fit: fit);
    }
    if (remotePath == null) return const _Unavailable();

    return ref
        .watch(receiptUrlProvider(remotePath!))
        .when(
          data: (url) => Image.network(
            url,
            fit: fit,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : const Center(child: CircularProgressIndicator()),
            errorBuilder: (_, _, _) => const _Unavailable(),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const _Unavailable(),
        );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, color: scheme.outline),
              const SizedBox(height: 8),
              const Text(
                'Foto struk belum bisa dimuat.\nPerlu koneksi internet.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Membuka foto struk layar penuh; bisa dicubit untuk memperbesar.
void openReceiptViewer(
  BuildContext context, {
  String? localPath,
  String? remotePath,
}) {
  Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: const Text('Foto struk')),
        body: InteractiveViewer(
          maxScale: 5,
          child: Center(
            child: ReceiptImage(
              localPath: localPath,
              remotePath: remotePath,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    ),
  );
}

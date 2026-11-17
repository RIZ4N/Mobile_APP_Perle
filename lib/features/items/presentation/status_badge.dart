import 'package:material_ui/material_ui.dart';

import '../data/item.dart';

({Color background, Color foreground, IconData icon}) statusStyle(
  BuildContext context,
  ItemStatus status,
) {
  final scheme = Theme.of(context).colorScheme;
  return switch (status) {
    ItemStatus.ada => (
      background: scheme.primaryContainer,
      foreground: scheme.onPrimaryContainer,
      icon: Icons.check_circle_outline,
    ),
    ItemStatus.harusBeli => (
      background: scheme.errorContainer,
      foreground: scheme.onErrorContainer,
      icon: Icons.shopping_cart_outlined,
    ),
    ItemStatus.pinjam => (
      background: scheme.tertiaryContainer,
      foreground: scheme.onTertiaryContainer,
      icon: Icons.handshake_outlined,
    ),
  };
}

/// Label status berwarna dengan ikon (tidak hanya mengandalkan warna).
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final ItemStatus status;

  @override
  Widget build(BuildContext context) {
    final style = statusStyle(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 14, color: style.foreground),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: style.foreground),
          ),
        ],
      ),
    );
  }
}

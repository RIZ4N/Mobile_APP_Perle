import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/expenses/presentation/expense_form_screen.dart';
import '../../features/expenses/presentation/expenses_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/items/presentation/item_detail_screen.dart';
import '../../features/items/presentation/item_form_screen.dart';
import '../../features/items/presentation/items_screen.dart';
import '../../features/loans/presentation/loan_history_screen.dart';
import '../../features/loans/presentation/scan_screen.dart';
import '../../features/more/members_screen.dart';
import '../../features/more/more_screen.dart';
import '../../features/packing/presentation/packing_screen.dart';
import '../sync/sync_controller.dart';

final _rootKey = GlobalKey<NavigatorState>();

/// Memberi tahu router setiap kali status masuk/keluar berubah.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Stream<Object?> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<Object?> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(supabaseProvider).auth;
  final refresh = _AuthRefresh(auth.onAuthStateChange);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/items',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = auth.currentSession != null;
      final atAuth =
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';
      if (!loggedIn) return atAuth ? null : '/login';
      return atAuth ? '/items' : null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(
        path: '/scan',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const ScanScreen(),
      ),
      // Empat tab utama; layar formulir/detail dibuka penuh di atasnya.
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/items',
                builder: (_, _) => const ItemsScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    parentNavigatorKey: _rootKey,
                    builder: (_, _) => const ItemFormScreen(),
                  ),
                  GoRoute(
                    path: ':id',
                    parentNavigatorKey: _rootKey,
                    builder: (_, state) =>
                        ItemDetailScreen(itemId: state.pathParameters['id']!),
                    routes: [
                      GoRoute(
                        path: 'edit',
                        parentNavigatorKey: _rootKey,
                        builder: (_, state) =>
                            ItemFormScreen(itemId: state.pathParameters['id']),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/packing',
                builder: (_, _) => const PackingScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/expenses',
                builder: (_, _) => const ExpensesScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    parentNavigatorKey: _rootKey,
                    builder: (_, _) => const ExpenseFormScreen(),
                  ),
                  GoRoute(
                    path: ':id',
                    parentNavigatorKey: _rootKey,
                    builder: (_, state) => ExpenseFormScreen(
                      expenseId: state.pathParameters['id'],
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/more',
                builder: (_, _) => const MoreScreen(),
                routes: [
                  GoRoute(
                    path: 'members',
                    parentNavigatorKey: _rootKey,
                    builder: (_, _) => const MembersScreen(),
                  ),
                  GoRoute(
                    path: 'loans',
                    parentNavigatorKey: _rootKey,
                    builder: (_, _) => const LoanHistoryScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

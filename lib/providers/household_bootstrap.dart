import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wherein_kitchen/providers/providers.dart';

/// Resolves the signed-in user's household and keeps [householdIdProvider] in
/// sync with the *current* auth state.
///
/// This is the single source of truth for "which household am I in", and it is
/// deliberately re-run on every auth change (login, logout, account switch) by
/// watching [authStateProvider]. It never trusts a previously cached id, so a
/// stale household can't leak across a logout/login or between accounts —
/// which was the cause of the post-logout "permission denied / blank" bugs.
final householdBootstrapProvider = FutureProvider<void>((ref) async {
  final user = ref.watch(authStateProvider).valueOrNull;
  final notifier = ref.read(householdIdProvider.notifier);

  if (user == null) {
    // Logged out: drop every piece of per-user state so no screen keeps
    // reading a household it can no longer access. Defer the writes so we
    // don't mutate other providers during this provider's build, and only
    // clear if we're *still* logged out (guards a fast logout/login).
    Future.microtask(() {
      if (ref.read(authStateProvider).valueOrNull != null) return;
      notifier.state = null;
      ref.read(searchQueryProvider.notifier).state = '';
      ref.read(highlightSlotIdProvider.notifier).state = null;
      ref.read(highlightItemNameProvider.notifier).state = null;
    });
    return;
  }

  // Always resolve fresh for the signed-in user.
  String? resolved;
  try {
    resolved = await ref
        .read(householdRepositoryProvider)
        .findHouseholdForUser(user.uid);
  } catch (_) {
    // Lookup denied/offline: fall through to the setup screen. Creating or
    // joining a household there will re-link the user.
    resolved = null;
  }

  // Guard against a stale write: only apply if this is still the signed-in
  // user (a fast logout/login could otherwise clobber the newer result).
  if (ref.read(authStateProvider).valueOrNull?.uid == user.uid) {
    notifier.state = resolved;
  }
});

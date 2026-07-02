import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wherein_kitchen/providers/household_bootstrap.dart';
import 'package:wherein_kitchen/providers/providers.dart';
import 'package:wherein_kitchen/screens/auth/auth_screen.dart';
import 'package:wherein_kitchen/screens/auth/household_setup_screen.dart';
import 'package:wherein_kitchen/screens/home/home_screen.dart';
import 'package:wherein_kitchen/theme.dart';

class WhereInKitchenApp extends ConsumerWidget {
  const WhereInKitchenApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return MaterialApp(
      title: 'WhereInKitchen',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      home: authState.when(
        data: (user) {
          if (user == null) return const AuthScreen();

          final bootstrap = ref.watch(householdBootstrapProvider);
          return bootstrap.when(
            data: (_) {
              final householdId = ref.watch(householdIdProvider);
              if (householdId == null) {
                return const HouseholdSetupScreen();
              }
              return const HomeScreen();
            },
            loading: () => const _BrandedSplash(),
            error: (error, _) => Scaffold(
              body: Center(child: Text('Setup error: $error')),
            ),
          );
        },
        loading: () => const _BrandedSplash(),
        error: (error, _) => Scaffold(
          body: Center(child: Text('Auth error: $error')),
        ),
      ),
    );
  }
}

/// A branded loading screen shown while auth/household state resolves.
class _BrandedSplash extends StatelessWidget {
  const _BrandedSplash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/icon/icon.png',
              width: 120,
              height: 120,
            ),
            const SizedBox(height: 20),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wherein_kitchen/providers/household_bootstrap.dart';
import 'package:wherein_kitchen/providers/providers.dart';
import 'package:wherein_kitchen/screens/auth/auth_screen.dart';
import 'package:wherein_kitchen/screens/auth/household_setup_screen.dart';
import 'package:wherein_kitchen/screens/home/home_screen.dart';

class WhereInKitchenApp extends ConsumerWidget {
  const WhereInKitchenApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return MaterialApp(
      title: 'WhereInKitchen',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D32),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF66BB6A),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
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
            loading: () => const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Scaffold(
              body: Center(child: Text('Setup error: $error')),
            ),
          );
        },
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => Scaffold(
          body: Center(child: Text('Auth error: $error')),
        ),
      ),
    );
  }
}

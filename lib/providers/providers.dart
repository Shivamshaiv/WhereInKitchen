import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wherein_kitchen/data/repositories/household_repository.dart';
import 'package:wherein_kitchen/data/repositories/item_repository.dart';
import 'package:wherein_kitchen/data/repositories/product_repository.dart';
import 'package:wherein_kitchen/data/repositories/room_repository.dart';
import 'package:wherein_kitchen/data/repositories/slot_repository.dart';
import 'package:wherein_kitchen/data/repositories/unit_repository.dart';
import 'package:wherein_kitchen/models/household.dart';
import 'package:wherein_kitchen/models/elevation.dart';
import 'package:wherein_kitchen/models/measure.dart';
import 'package:wherein_kitchen/models/item.dart';
import 'package:wherein_kitchen/models/room.dart';
import 'package:wherein_kitchen/models/slot.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';
import 'package:wherein_kitchen/services/api_usage_service.dart';
import 'package:wherein_kitchen/services/auth_service.dart';
import 'package:wherein_kitchen/services/product_lookup_service.dart';

final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

final householdRepositoryProvider = Provider<HouseholdRepository>((ref) {
  return HouseholdRepository(ref.watch(firestoreProvider));
});

final roomRepositoryProvider = Provider<RoomRepository>((ref) {
  return RoomRepository(ref.watch(firestoreProvider));
});

final unitRepositoryProvider = Provider<UnitRepository>((ref) {
  return UnitRepository(ref.watch(firestoreProvider));
});

final slotRepositoryProvider = Provider<SlotRepository>((ref) {
  return SlotRepository(ref.watch(firestoreProvider));
});

final itemRepositoryProvider = Provider<ItemRepository>((ref) {
  return ItemRepository(ref.watch(firestoreProvider));
});

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepository(ref.watch(firestoreProvider));
});

final apiUsageServiceProvider = Provider<ApiUsageService>((ref) {
  return ApiUsageService();
});

final productLookupServiceProvider = Provider<ProductLookupService>((ref) {
  return ProductLookupService(usage: ref.watch(apiUsageServiceProvider));
});

/// Snapshot of barcode API usage for the Settings screen. Invalidate to refresh.
final apiUsageProvider = FutureProvider.autoDispose<ApiUsageSnapshot>((ref) {
  return ref.watch(apiUsageServiceProvider).load();
});

final householdIdProvider = StateProvider<String?>((ref) => null);

final householdProvider = StreamProvider<Household?>((ref) {
  final householdId = ref.watch(householdIdProvider);
  if (householdId == null) return const Stream.empty();
  return ref
      .watch(householdRepositoryProvider)
      .watchHousehold(householdId);
});

/// All homes the signed-in user belongs to (for the house switcher).
final myHouseholdsProvider = StreamProvider<List<Household>>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return const Stream.empty();
  return ref.watch(householdRepositoryProvider).watchMyHouseholds(uid);
});

final roomsProvider = StreamProvider<List<Room>>((ref) {
  final householdId = ref.watch(householdIdProvider);
  if (householdId == null) return const Stream.empty();
  return ref.watch(roomRepositoryProvider).watchRooms(householdId);
});

final unitsProvider = StreamProvider<List<StorageUnit>>((ref) {
  final householdId = ref.watch(householdIdProvider);
  if (householdId == null) return const Stream.empty();
  return ref.watch(unitRepositoryProvider).watchUnits(householdId);
});

final itemsProvider = StreamProvider<List<Item>>((ref) {
  final householdId = ref.watch(householdIdProvider);
  if (householdId == null) return const Stream.empty();
  return ref.watch(itemRepositoryProvider).watchItems(householdId);
});

final slotsProvider = StreamProvider<List<Slot>>((ref) {
  final householdId = ref.watch(householdIdProvider);
  if (householdId == null) return const Stream.empty();
  return ref.watch(slotRepositoryProvider).watchAllSlots(householdId);
});

final searchQueryProvider = StateProvider<String>((ref) => '');

final searchResultsProvider = Provider<AsyncValue<List<Item>>>((ref) {
  final query = ref.watch(searchQueryProvider);
  final items = ref.watch(itemsProvider);
  return items.whenData((allItems) {
    if (query.trim().isEmpty) return <Item>[];
    return allItems.where((item) => item.matchesQuery(query)).toList();
  });
});

final highlightSlotIdProvider = StateProvider<String?>((ref) => null);
final highlightItemNameProvider = StateProvider<String?>((ref) => null);

final slotsForUnitProvider =
    StreamProvider.autoDispose.family<List<Slot>, String>((ref, unitId) {
  final householdId = ref.watch(householdIdProvider);
  if (householdId == null) return const Stream.empty();
  return ref
      .watch(slotRepositoryProvider)
      .watchSlotsForUnit(householdId, unitId);
});

final itemsForSlotProvider =
    StreamProvider.autoDispose.family<List<Item>, String>((ref, slotId) {
  final householdId = ref.watch(householdIdProvider);
  if (householdId == null) return const Stream.empty();
  return ref
      .watch(itemRepositoryProvider)
      .watchItemsForSlot(householdId, slotId);
});

/// An immutable snapshot of a unit's shape, copied in the wall-elevation editor
/// so it can be pasted onto any surface (persists across pushed editor routes).
/// Deliberately holds only geometry/config — never items — so paste creates a
/// fresh empty unit rather than duplicating inventory.
class ElevClipboard {
  const ElevClipboard({
    required this.name,
    required this.type,
    required this.mount,
    required this.rows,
    required this.columns,
    required this.heightCm,
    required this.widthCm,
    required this.hCm,
    required this.depthCm,
    required this.zCm,
  });

  final String name;
  final StorageUnitType type;
  final UnitMount mount;
  final int rows;
  final int columns;
  final int heightCm;
  final double widthCm;
  final double hCm;
  final double depthCm;
  final double zCm;
}

final elevationClipboardProvider = StateProvider<ElevClipboard?>((ref) => null);

/// The user's chosen measurement units (cm vs feet & inches), persisted on the
/// device. All lengths are stored in cm; this only affects display/entry.
class UnitSystemNotifier extends StateNotifier<UnitSystem> {
  UnitSystemNotifier() : super(UnitSystem.metric) {
    _load();
  }

  static const _key = 'unit_system_v1';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_key) == 'imperial') state = UnitSystem.imperial;
  }

  Future<void> setSystem(UnitSystem system) async {
    state = system;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, system.isMetric ? 'metric' : 'imperial');
  }
}

final unitSystemProvider =
    StateNotifierProvider<UnitSystemNotifier, UnitSystem>(
        (ref) => UnitSystemNotifier());

/// App theme mode (System / Light / Dark), persisted on the device.
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.system) {
    _load();
  }

  static const _key = 'theme_mode_v1';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    switch (prefs.getString(_key)) {
      case 'light':
        state = ThemeMode.light;
      case 'dark':
        state = ThemeMode.dark;
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      },
    );
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
    (ref) => ThemeModeNotifier());

/// A single double preference persisted in SharedPreferences under [_key].
class DoublePrefNotifier extends StateNotifier<double> {
  DoublePrefNotifier(this._key, double initial) : super(initial) {
    _load();
  }

  final String _key;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getDouble(_key);
    if (v != null) state = v;
  }

  Future<void> set(double value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_key, value);
  }
}

/// Counter-top height (cm): the wall-editor guideline + a snap target.
final counterHeightProvider = StateNotifierProvider<DoublePrefNotifier, double>(
    (ref) => DoublePrefNotifier('counter_height_cm_v1', kCounterHeightCm));

/// Height (cm) where wall/upper cabinets are mounted: editor guideline + snap,
/// and the default z for a newly-added wall unit.
final wallCabinetHeightProvider =
    StateNotifierProvider<DoublePrefNotifier, double>(
        (ref) => DoublePrefNotifier('wall_cabinet_cm_v1', kWallUnitBaseCm));

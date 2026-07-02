import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wherein_kitchen/data/repositories/household_repository.dart';
import 'package:wherein_kitchen/data/repositories/item_repository.dart';
import 'package:wherein_kitchen/data/repositories/product_repository.dart';
import 'package:wherein_kitchen/data/repositories/room_repository.dart';
import 'package:wherein_kitchen/data/repositories/slot_repository.dart';
import 'package:wherein_kitchen/data/repositories/unit_repository.dart';
import 'package:wherein_kitchen/models/household.dart';
import 'package:wherein_kitchen/models/item.dart';
import 'package:wherein_kitchen/models/room.dart';
import 'package:wherein_kitchen/models/slot.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';
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

final productLookupServiceProvider = Provider<ProductLookupService>((ref) {
  return ProductLookupService();
});

final householdIdProvider = StateProvider<String?>((ref) => null);

final householdProvider = StreamProvider<Household?>((ref) {
  final householdId = ref.watch(householdIdProvider);
  if (householdId == null) return const Stream.empty();
  return ref
      .watch(householdRepositoryProvider)
      .watchHousehold(householdId);
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
    StreamProvider.family<List<Slot>, String>((ref, unitId) {
  final householdId = ref.watch(householdIdProvider);
  if (householdId == null) return const Stream.empty();
  return ref
      .watch(slotRepositoryProvider)
      .watchSlotsForUnit(householdId, unitId);
});

final itemsForSlotProvider =
    StreamProvider.family<List<Item>, String>((ref, slotId) {
  final householdId = ref.watch(householdIdProvider);
  if (householdId == null) return const Stream.empty();
  return ref
      .watch(itemRepositoryProvider)
      .watchItemsForSlot(householdId, slotId);
});

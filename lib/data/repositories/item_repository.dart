import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wherein_kitchen/data/firestore_paths.dart';
import 'package:wherein_kitchen/models/item.dart';

class ItemRepository {
  ItemRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _collection(String householdId) =>
      _firestore.collection(FirestorePaths.items(householdId));

  Stream<List<Item>> watchItems(String householdId) {
    return _collection(householdId).snapshots().map((snapshot) {
      final items = snapshot.docs
          .map((doc) => Item.fromMap(doc.id, doc.data()))
          .toList();
      _sortStable(items);
      return items;
    });
  }

  Stream<List<Item>> watchItemsForSlot(String householdId, String slotId) {
    return _collection(householdId)
        .where('slotId', isEqualTo: slotId)
        .snapshots()
        .map((snapshot) {
      final items = snapshot.docs
          .map((doc) => Item.fromMap(doc.id, doc.data()))
          .toList();
      _sortStable(items);
      return items;
    });
  }

  /// Deterministic order (name, then id) so items don't reshuffle between
  /// snapshots — otherwise a shelf's contents appear to jump around on every
  /// rebuild or reopen.
  static void _sortStable(List<Item> items) {
    items.sort((a, b) {
      final byName =
          a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.id.compareTo(b.id);
    });
  }

  Future<List<Item>> searchItems(String householdId, String query) async {
    final snapshot = await _collection(householdId).get();
    return snapshot.docs
        .map((doc) => Item.fromMap(doc.id, doc.data()))
        .where((item) => item.matchesQuery(query))
        .toList();
  }

  Future<Item?> getItemByBarcode(String householdId, String barcode) async {
    final snapshot = await _collection(householdId)
        .where('barcode', isEqualTo: barcode)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    final doc = snapshot.docs.first;
    return Item.fromMap(doc.id, doc.data());
  }

  Future<Item> addItem(Item item) async {
    final doc = _collection(item.householdId).doc();
    final newItem = Item(
      id: doc.id,
      householdId: item.householdId,
      name: item.name,
      aliases: item.aliases,
      category: item.category,
      slotId: item.slotId,
      quantity: item.quantity,
      updatedAt: DateTime.now(),
      barcode: item.barcode,
      imageUrl: item.imageUrl,
      thumbB64: item.thumbB64,
      notes: item.notes,
    );
    await doc.set(newItem.toMap());
    return newItem;
  }

  Future<void> updateItem(Item item) async {
    await _collection(item.householdId)
        .doc(item.id)
        .update(item.copyWith(updatedAt: DateTime.now()).toMap());
  }

  Future<void> moveItem({
    required Item item,
    required String newSlotId,
  }) async {
    await updateItem(item.copyWith(slotId: newSlotId));
  }

  Future<void> deleteItem(String householdId, String itemId) async {
    await _collection(householdId).doc(itemId).delete();
  }

  /// Fast path: add an item with just a name to a known slot.
  Future<Item> quickAdd({
    required String householdId,
    required String slotId,
    required String name,
  }) {
    return addItem(Item(
      id: '',
      householdId: householdId,
      name: name,
      aliases: const [],
      category: 'General',
      slotId: slotId,
      quantity: '1',
      updatedAt: DateTime.now(),
    ));
  }

  /// Fast path for scan-to-place: add a scanned product straight onto a shelf.
  Future<Item> placeInSlot({
    required String householdId,
    required String slotId,
    required String name,
    String category = 'General',
    String? barcode,
    String? imageUrl,
  }) {
    return addItem(Item(
      id: '',
      householdId: householdId,
      name: name,
      aliases: const [],
      category: category,
      slotId: slotId,
      quantity: '1',
      updatedAt: DateTime.now(),
      barcode: barcode,
      imageUrl: imageUrl,
    ));
  }

  Future<void> deleteItems(String householdId, List<String> itemIds) async {
    final batch = _firestore.batch();
    for (final id in itemIds) {
      batch.delete(_collection(householdId).doc(id));
    }
    await batch.commit();
  }

  /// Deletes every item stored in [unitId]'s slots. Authoritative: it looks up
  /// the unit's slots on the server rather than trusting a (possibly empty or
  /// stale) client-cached [slotIds] list, so a fast unit-delete can't leave
  /// orphaned items behind. Any [slotIds] passed in are merged in as a fallback.
  Future<void> deleteItemsForUnit(String householdId, String unitId,
      [List<String>? slotIds]) async {
    final slotSnap = await _firestore
        .collection(FirestorePaths.slots(householdId))
        .where('unitId', isEqualTo: unitId)
        .get();
    final ids = <String>{
      ...slotSnap.docs.map((d) => d.id),
      ...?slotIds,
    };
    if (ids.isEmpty) return;
    final batch = _firestore.batch();
    for (final slotId in ids) {
      final snapshot = await _collection(householdId)
          .where('slotId', isEqualTo: slotId)
          .get();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
    }
    await batch.commit();
  }
}

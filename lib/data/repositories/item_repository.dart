import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wherein_kitchen/data/firestore_paths.dart';
import 'package:wherein_kitchen/models/item.dart';

class ItemRepository {
  ItemRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _collection(String householdId) =>
      _firestore.collection(FirestorePaths.items(householdId));

  Stream<List<Item>> watchItems(String householdId) {
    return _collection(householdId).snapshots().map((snapshot) => snapshot.docs
        .map((doc) => Item.fromMap(doc.id, doc.data()))
        .toList());
  }

  Stream<List<Item>> watchItemsForSlot(String householdId, String slotId) {
    return _collection(householdId)
        .where('slotId', isEqualTo: slotId)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Item.fromMap(doc.id, doc.data()))
            .toList());
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

  Future<void> deleteItems(String householdId, List<String> itemIds) async {
    final batch = _firestore.batch();
    for (final id in itemIds) {
      batch.delete(_collection(householdId).doc(id));
    }
    await batch.commit();
  }

  Future<void> deleteItemsForUnit(String householdId, String unitId,
      List<String> slotIds) async {
    if (slotIds.isEmpty) return;
    final batch = _firestore.batch();
    for (final slotId in slotIds) {
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

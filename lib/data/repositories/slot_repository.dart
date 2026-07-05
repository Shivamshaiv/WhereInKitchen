import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wherein_kitchen/data/firestore_paths.dart';
import 'package:wherein_kitchen/models/slot.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';

class SlotRepository {
  SlotRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _collection(String householdId) =>
      _firestore.collection(FirestorePaths.slots(householdId));

  Stream<List<Slot>> watchSlotsForUnit(String householdId, String unitId) {
    return _collection(householdId)
        .where('unitId', isEqualTo: unitId)
        .snapshots()
        .map((snapshot) {
      final slots = snapshot.docs
          .map((doc) => Slot.fromMap(doc.id, doc.data()))
          .toList();
      slots.sort((a, b) {
        final rowCompare = a.row.compareTo(b.row);
        if (rowCompare != 0) return rowCompare;
        return a.column.compareTo(b.column);
      });
      return slots;
    });
  }

  Stream<List<Slot>> watchAllSlots(String householdId) {
    return _collection(householdId).snapshots().map((snapshot) => snapshot.docs
        .map((doc) => Slot.fromMap(doc.id, doc.data()))
        .toList());
  }

  Future<Slot?> getSlot(String householdId, String slotId) async {
    final doc = await _collection(householdId).doc(slotId).get();
    if (!doc.exists) return null;
    return Slot.fromMap(doc.id, doc.data()!);
  }

  Future<List<Slot>> ensureSlotsForUnit({
    required String householdId,
    required StorageUnit unit,
  }) async {
    // Appliances / open spaces hold no items, so they get no slots.
    if (!unit.holdsItems) return const [];

    final existing = await _collection(householdId)
        .where('unitId', isEqualTo: unit.id)
        .get();
    if (existing.docs.isNotEmpty) {
      return existing.docs
          .map((doc) => Slot.fromMap(doc.id, doc.data()))
          .toList();
    }

    final batch = _firestore.batch();
    final slots = <Slot>[];

    for (final comp in defaultCompartments(unit)) {
      final doc = _collection(householdId).doc();
      final slot = Slot(
        id: doc.id,
        householdId: householdId,
        unitId: unit.id,
        label: comp.label,
        row: comp.row,
        column: comp.column,
      );
      batch.set(doc, slot.toMap());
      slots.add(slot);
    }

    await batch.commit();
    return slots;
  }

  /// Adds or removes slots so the unit has exactly [unit.rows] x [unit.columns].
  /// Existing slots (and their items) are preserved; extra slots are removed
  /// only if empty of a matching row/column position.
  Future<void> reconcileSlotsForUnit({
    required String householdId,
    required StorageUnit unit,
  }) async {
    final existing = await _collection(householdId)
        .where('unitId', isEqualTo: unit.id)
        .get();

    // If the unit no longer holds items (e.g. changed to an appliance),
    // remove any stale slots.
    if (!unit.holdsItems) {
      if (existing.docs.isEmpty) return;
      final removeBatch = _firestore.batch();
      for (final doc in existing.docs) {
        removeBatch.delete(doc.reference);
      }
      await removeBatch.commit();
      return;
    }

    final byPosition = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final doc in existing.docs) {
      final data = doc.data();
      byPosition['${data['row']}_${data['column']}'] = doc;
    }

    final batch = _firestore.batch();
    final wanted = <String>{};

    for (final comp in defaultCompartments(unit)) {
      final key = '${comp.row}_${comp.column}';
      wanted.add(key);
      if (!byPosition.containsKey(key)) {
        final doc = _collection(householdId).doc();
        batch.set(
          doc,
          Slot(
            id: doc.id,
            householdId: householdId,
            unitId: unit.id,
            label: comp.label,
            row: comp.row,
            column: comp.column,
          ).toMap(),
        );
      }
    }

    await batch.commit();

    // Remove now-out-of-range slots that are empty. Check-and-delete each one
    // immediately (instead of staging into a batch committed later) so the
    // window between the empty-check and the delete is as small as possible —
    // a populated slot is never destroyed, while shrinking rows/columns still
    // tidies away the empty extras.
    for (final entry in byPosition.entries) {
      if (wanted.contains(entry.key)) continue;
      final itemsSnap = await _firestore
          .collection(FirestorePaths.items(householdId))
          .where('slotId', isEqualTo: entry.value.id)
          .limit(1)
          .get();
      if (itemsSnap.docs.isEmpty) {
        await entry.value.reference.delete();
      }
    }
  }

  Future<void> renameSlot(
    String householdId,
    String slotId,
    String label,
  ) async {
    await _collection(householdId).doc(slotId).update({'label': label});
  }

  Future<void> deleteSlotsForUnit(String householdId, String unitId) async {
    final existing = await _collection(householdId)
        .where('unitId', isEqualTo: unitId)
        .get();
    final batch = _firestore.batch();
    for (final doc in existing.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wherein_kitchen/data/firestore_paths.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';

class UnitRepository {
  UnitRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _collection(String householdId) =>
      _firestore.collection(FirestorePaths.units(householdId));

  Stream<List<StorageUnit>> watchUnits(String householdId) {
    return _collection(householdId)
        .orderBy('sortOrder')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => StorageUnit.fromMap(doc.id, doc.data()))
            .toList());
  }

  Stream<List<StorageUnit>> watchUnitsForRoom(
    String householdId,
    String roomId,
  ) {
    return _collection(householdId)
        .where('roomId', isEqualTo: roomId)
        .snapshots()
        .map((snapshot) {
      final units = snapshot.docs
          .map((doc) => StorageUnit.fromMap(doc.id, doc.data()))
          .toList();
      units.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return units;
    });
  }

  Future<StorageUnit> createUnit({
    required String householdId,
    required String roomId,
    required String name,
    required StorageUnitType type,
    required int rows,
    required int columns,
    required int sortOrder,
  }) async {
    final doc = _collection(householdId).doc();
    final unit = StorageUnit(
      id: doc.id,
      householdId: householdId,
      roomId: roomId,
      name: name,
      type: type,
      rows: rows,
      columns: columns,
      sortOrder: sortOrder,
    );
    await doc.set(unit.toMap());
    return unit;
  }

  Future<StorageUnit?> getUnit(String householdId, String unitId) async {
    final doc = await _collection(householdId).doc(unitId).get();
    if (!doc.exists) return null;
    return StorageUnit.fromMap(doc.id, doc.data()!);
  }

  Future<void> updateUnit(StorageUnit unit) async {
    await _collection(unit.householdId).doc(unit.id).update(unit.toMap());
  }

  Future<void> updateLayout(
    String householdId,
    String unitId, {
    required int gx,
    required int gy,
    required int gw,
    required int gh,
  }) async {
    await _collection(householdId).doc(unitId).update({
      'gx': gx,
      'gy': gy,
      'gw': gw,
      'gh': gh,
    });
  }

  Future<void> deleteUnit(String householdId, String unitId) async {
    await _collection(householdId).doc(unitId).delete();
  }
}

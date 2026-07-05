import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wherein_kitchen/data/firestore_paths.dart';
import 'package:wherein_kitchen/models/room.dart';

class RoomRepository {
  RoomRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _collection(String householdId) =>
      _firestore.collection(FirestorePaths.rooms(householdId));

  Stream<List<Room>> watchRooms(String householdId) {
    return _collection(householdId)
        .orderBy('sortOrder')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Room.fromMap(doc.id, doc.data()))
            .toList());
  }

  Future<Room> createRoom({
    required String householdId,
    required String name,
    required int sortOrder,
  }) async {
    final doc = _collection(householdId).doc();
    final room = Room(
      id: doc.id,
      householdId: householdId,
      name: name,
      sortOrder: sortOrder,
    );
    await doc.set(room.toMap());
    return room;
  }

  Future<void> renameRoom(
      String householdId, String roomId, String name) async {
    await _collection(householdId).doc(roomId).update({'name': name});
  }

  /// Deletes a room AND everything under it (its units, their slots, and the
  /// items in those slots) in chunked WriteBatches. Without this cascade the
  /// contents would become permanently orphaned — invisible in room views yet
  /// still streamed and counted.
  Future<void> deleteRoom(String householdId, String roomId) async {
    final unitsCol = _firestore.collection(FirestorePaths.units(householdId));
    final slotsCol = _firestore.collection(FirestorePaths.slots(householdId));
    final itemsCol = _firestore.collection(FirestorePaths.items(householdId));

    final unitSnap = await unitsCol.where('roomId', isEqualTo: roomId).get();
    final unitIds = unitSnap.docs.map((d) => d.id).toList();

    final slotDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (var i = 0; i < unitIds.length; i += 30) {
      final chunk = unitIds.sublist(i, math.min(i + 30, unitIds.length));
      final snap = await slotsCol.where('unitId', whereIn: chunk).get();
      slotDocs.addAll(snap.docs);
    }
    final slotIds = slotDocs.map((d) => d.id).toList();

    final itemDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (var i = 0; i < slotIds.length; i += 30) {
      final chunk = slotIds.sublist(i, math.min(i + 30, slotIds.length));
      final snap = await itemsCol.where('slotId', whereIn: chunk).get();
      itemDocs.addAll(snap.docs);
    }

    final refs = <DocumentReference<Map<String, dynamic>>>[
      ...itemDocs.map((d) => d.reference),
      ...slotDocs.map((d) => d.reference),
      ...unitSnap.docs.map((d) => d.reference),
      _collection(householdId).doc(roomId),
    ];
    for (var i = 0; i < refs.length; i += 450) {
      final batch = _firestore.batch();
      for (final ref in refs.sublist(i, math.min(i + 450, refs.length))) {
        batch.delete(ref);
      }
      await batch.commit();
    }
  }

  /// Updates the room's interior dimensions (cm).
  Future<void> updateDimensions(
    String householdId,
    String roomId, {
    required double widthCm,
    required double lengthCm,
    required double wallHeightCm,
  }) async {
    await _collection(householdId).doc(roomId).update({
      'widthCm': widthCm,
      'lengthCm': lengthCm,
      'wallHeightCm': wallHeightCm,
    });
  }

  /// Replaces the room's islands with [islands].
  Future<void> updateIslands(
    String householdId,
    String roomId,
    List<Island> islands,
  ) async {
    await _collection(householdId).doc(roomId).update({
      'islands': islands.map((i) => i.toMap()).toList(),
    });
  }
}

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

  Future<void> deleteRoom(String householdId, String roomId) async {
    await _collection(householdId).doc(roomId).delete();
  }
}

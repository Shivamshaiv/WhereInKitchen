import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wherein_kitchen/data/firestore_paths.dart';
import 'package:wherein_kitchen/models/household.dart';

class HouseholdRepository {
  HouseholdRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(FirestorePaths.households());

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection(FirestorePaths.users());

  Future<void> _linkUserToHousehold(String uid, String householdId) async {
    await _users.doc(uid).set({'householdId': householdId});
  }

  Future<String?> getUserHousehold(String uid) async {
    final doc = await _users.doc(uid).get();
    if (!doc.exists) return null;
    return doc.data()?['householdId'] as String?;
  }

  Stream<Household?> watchHousehold(String householdId) {
    return _collection.doc(householdId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return Household.fromMap(doc.id, doc.data()!);
    });
  }

  /// Every household this user is a member of (for the house switcher).
  Stream<List<Household>> watchMyHouseholds(String uid) {
    return _collection
        .where('members', arrayContains: uid)
        .snapshots()
        .map((snapshot) {
      final households = snapshot.docs
          .map((doc) => Household.fromMap(doc.id, doc.data()))
          .toList();
      households.sort((a, b) => a.name.toLowerCase().compareTo(
            b.name.toLowerCase(),
          ));
      return households;
    });
  }

  /// Marks [householdId] as the user's active home (persists across launches).
  Future<void> setActiveHousehold(String uid, String householdId) =>
      _linkUserToHousehold(uid, householdId);

  /// Joins the household by id (from an invite QR/code) and makes it active.
  /// Returns the household, or null if it doesn't exist.
  Future<Household?> joinHousehold(String uid, String householdId) async {
    final household = await getHousehold(householdId);
    if (household == null) return null;
    await addMember(householdId, uid);
    return household;
  }

  Future<Household?> getHousehold(String householdId) async {
    final doc = await _collection.doc(householdId).get();
    if (!doc.exists) return null;
    return Household.fromMap(doc.id, doc.data()!);
  }

  Future<Household> createHousehold({
    required String id,
    required String name,
    required String ownerUid,
  }) async {
    final household = Household(
      id: id,
      name: name,
      members: [ownerUid],
      createdAt: DateTime.now(),
    );
    await _collection.doc(id).set(household.toMap());
    await _linkUserToHousehold(ownerUid, id);
    return household;
  }

  Future<void> addMember(String householdId, String uid) async {
    await _collection.doc(householdId).update({
      'members': FieldValue.arrayUnion([uid]),
    });
    await _linkUserToHousehold(uid, householdId);
  }

  Future<String?> findHouseholdForUser(String uid) async {
    final mapped = await getUserHousehold(uid);
    if (mapped != null) return mapped;

    final snapshot = await _collection
        .where('members', arrayContains: uid)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;

    final householdId = snapshot.docs.first.id;
    await _linkUserToHousehold(uid, householdId);
    return householdId;
  }
}

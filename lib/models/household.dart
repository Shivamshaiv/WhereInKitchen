import 'package:cloud_firestore/cloud_firestore.dart';

/// Scheme used in invite QR codes so a scan can jump straight into joining.
const String kJoinUriPrefix = 'whereinkitchen://join/';

/// The payload encoded in a household's invite QR code.
String householdInvitePayload(String householdId) =>
    '$kJoinUriPrefix$householdId';

/// Extracts a household id from an invite payload (QR content or raw id).
/// Accepts either the full `whereinkitchen://join/<id>` URI or a bare id.
String parseHouseholdInvite(String payload) {
  final trimmed = payload.trim();
  if (trimmed.startsWith(kJoinUriPrefix)) {
    return trimmed.substring(kJoinUriPrefix.length);
  }
  return trimmed;
}

class Household {
  const Household({
    required this.id,
    required this.name,
    required this.members,
    required this.createdAt,
    this.ownerUid,
  });

  final String id;
  final String name;
  final List<String> members;
  final DateTime createdAt;

  /// Creator/owner uid. Null on legacy homes created before ownership existed;
  /// owner-only actions (remove member, delete home) are unavailable for those.
  final String? ownerUid;

  bool isOwner(String uid) => ownerUid != null && ownerUid == uid;

  factory Household.fromMap(String id, Map<String, dynamic> map) {
    final raw = map['createdAt'];
    return Household(
      id: id,
      name: map['name'] as String? ?? 'My Home',
      members: List<String>.from(map['members'] as List? ?? []),
      createdAt: raw is Timestamp ? raw.toDate() : DateTime.now(),
      ownerUid: map['ownerUid'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'members': members,
        'createdAt': createdAt,
        if (ownerUid != null) 'ownerUid': ownerUid,
      };
}

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
  });

  final String id;
  final String name;
  final List<String> members;
  final DateTime createdAt;

  factory Household.fromMap(String id, Map<String, dynamic> map) {
    return Household(
      id: id,
      name: map['name'] as String? ?? 'My Home',
      members: List<String>.from(map['members'] as List? ?? []),
      createdAt: (map['createdAt'] as dynamic)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'members': members,
        'createdAt': createdAt,
      };
}

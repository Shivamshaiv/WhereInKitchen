class Room {
  const Room({
    required this.id,
    required this.householdId,
    required this.name,
    required this.sortOrder,
  });

  final String id;
  final String householdId;
  final String name;
  final int sortOrder;

  factory Room.fromMap(String id, Map<String, dynamic> map) {
    return Room(
      id: id,
      householdId: map['householdId'] as String? ?? '',
      name: map['name'] as String? ?? 'Room',
      sortOrder: map['sortOrder'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'householdId': householdId,
        'name': name,
        'sortOrder': sortOrder,
      };
}

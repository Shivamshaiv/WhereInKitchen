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

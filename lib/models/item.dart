class Item {
  const Item({
    required this.id,
    required this.householdId,
    required this.name,
    required this.aliases,
    required this.category,
    required this.slotId,
    required this.quantity,
    required this.updatedAt,
    this.barcode,
    this.imageUrl,
    this.thumbB64,
    this.notes,
  });

  final String id;
  final String householdId;
  final String name;
  final List<String> aliases;
  final String category;
  final String slotId;
  final String quantity;
  final DateTime updatedAt;
  final String? barcode;
  final String? imageUrl;
  final String? thumbB64;
  final String? notes;

  factory Item.fromMap(String id, Map<String, dynamic> map) {
    return Item(
      id: id,
      householdId: map['householdId'] as String? ?? '',
      name: map['name'] as String? ?? 'Item',
      aliases: List<String>.from(map['aliases'] as List? ?? []),
      category: map['category'] as String? ?? 'General',
      slotId: map['slotId'] as String? ?? '',
      quantity: map['quantity'] as String? ?? '1',
      updatedAt: (map['updatedAt'] as dynamic)?.toDate() ?? DateTime.now(),
      barcode: map['barcode'] as String?,
      imageUrl: map['imageUrl'] as String?,
      thumbB64: map['thumbB64'] as String?,
      notes: map['notes'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'householdId': householdId,
        'name': name,
        'aliases': aliases,
        'category': category,
        'slotId': slotId,
        'quantity': quantity,
        'updatedAt': updatedAt,
        if (barcode != null) 'barcode': barcode,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (thumbB64 != null) 'thumbB64': thumbB64,
        if (notes != null) 'notes': notes,
      };

  Item copyWith({
    String? name,
    List<String>? aliases,
    String? category,
    String? slotId,
    String? quantity,
    DateTime? updatedAt,
    String? barcode,
    String? imageUrl,
    String? thumbB64,
    String? notes,
  }) {
    return Item(
      id: id,
      householdId: householdId,
      name: name ?? this.name,
      aliases: aliases ?? this.aliases,
      category: category ?? this.category,
      slotId: slotId ?? this.slotId,
      quantity: quantity ?? this.quantity,
      updatedAt: updatedAt ?? this.updatedAt,
      barcode: barcode ?? this.barcode,
      imageUrl: imageUrl ?? this.imageUrl,
      thumbB64: thumbB64 ?? this.thumbB64,
      notes: notes ?? this.notes,
    );
  }

  bool matchesQuery(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return false;
    if (name.toLowerCase().contains(q)) return true;
    if (category.toLowerCase().contains(q)) return true;
    for (final alias in aliases) {
      if (alias.toLowerCase().contains(q)) return true;
    }
    return false;
  }
}

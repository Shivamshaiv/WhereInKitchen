class Slot {
  const Slot({
    required this.id,
    required this.householdId,
    required this.unitId,
    required this.label,
    required this.row,
    required this.column,
  });

  final String id;
  final String householdId;
  final String unitId;
  final String label;
  final int row;
  final int column;

  factory Slot.fromMap(String id, Map<String, dynamic> map) {
    return Slot(
      id: id,
      householdId: map['householdId'] as String? ?? '',
      unitId: map['unitId'] as String? ?? '',
      label: map['label'] as String? ?? 'Shelf',
      row: (map['row'] as num?)?.toInt() ?? 1,
      column: (map['column'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toMap() => {
        'householdId': householdId,
        'unitId': unitId,
        'label': label,
        'row': row,
        'column': column,
      };
}

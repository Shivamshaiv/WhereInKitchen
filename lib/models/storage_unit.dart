enum StorageUnitType { shelf, drawer, cabinet, fridge, freezer, other }

extension StorageUnitTypeLabel on StorageUnitType {
  String get label => switch (this) {
        StorageUnitType.shelf => 'Shelf / Pantry',
        StorageUnitType.drawer => 'Drawer',
        StorageUnitType.cabinet => 'Cabinet',
        StorageUnitType.fridge => 'Fridge',
        StorageUnitType.freezer => 'Freezer',
        StorageUnitType.other => 'Other',
      };
}

/// Room layout uses a simple grid. Each unit occupies a rectangle
/// (gx, gy, gw, gh) in grid cells on its room's canvas.
const int kRoomGridColumns = 4;

class StorageUnit {
  const StorageUnit({
    required this.id,
    required this.householdId,
    required this.roomId,
    required this.name,
    required this.type,
    required this.rows,
    required this.columns,
    required this.sortOrder,
    this.gx = 0,
    this.gy = 0,
    this.gw = 2,
    this.gh = 2,
  });

  final String id;
  final String householdId;
  final String roomId;
  final String name;
  final StorageUnitType type;
  final int rows;
  final int columns;
  final int sortOrder;

  /// Position and size on the room layout grid.
  final int gx;
  final int gy;
  final int gw;
  final int gh;

  factory StorageUnit.fromMap(String id, Map<String, dynamic> map) {
    return StorageUnit(
      id: id,
      householdId: map['householdId'] as String? ?? '',
      roomId: map['roomId'] as String? ?? '',
      name: map['name'] as String? ?? 'Storage',
      type: StorageUnitType.values.firstWhere(
        (t) => t.name == map['type'],
        orElse: () => StorageUnitType.shelf,
      ),
      rows: map['rows'] as int? ?? 4,
      columns: map['columns'] as int? ?? 1,
      sortOrder: map['sortOrder'] as int? ?? 0,
      gx: map['gx'] as int? ?? -1,
      gy: map['gy'] as int? ?? -1,
      gw: map['gw'] as int? ?? 2,
      gh: map['gh'] as int? ?? 2,
    );
  }

  Map<String, dynamic> toMap() => {
        'householdId': householdId,
        'roomId': roomId,
        'name': name,
        'type': type.name,
        'rows': rows,
        'columns': columns,
        'sortOrder': sortOrder,
        'gx': gx,
        'gy': gy,
        'gw': gw,
        'gh': gh,
      };

  bool get hasLayoutPosition => gx >= 0 && gy >= 0;

  StorageUnit copyWith({
    String? name,
    StorageUnitType? type,
    int? rows,
    int? columns,
    int? sortOrder,
    int? gx,
    int? gy,
    int? gw,
    int? gh,
  }) {
    return StorageUnit(
      id: id,
      householdId: householdId,
      roomId: roomId,
      name: name ?? this.name,
      type: type ?? this.type,
      rows: rows ?? this.rows,
      columns: columns ?? this.columns,
      sortOrder: sortOrder ?? this.sortOrder,
      gx: gx ?? this.gx,
      gy: gy ?? this.gy,
      gw: gw ?? this.gw,
      gh: gh ?? this.gh,
    );
  }
}

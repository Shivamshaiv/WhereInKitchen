enum StorageUnitType {
  shelf,
  drawer,
  cabinet,
  fridge,
  freezer,
  // Appliances / gaps: occupy floor space but hold no inventory.
  range,
  sink,
  dishwasher,
  oven,
  gap,
  other,
}

extension StorageUnitTypeLabel on StorageUnitType {
  String get label => switch (this) {
        StorageUnitType.shelf => 'Shelf / Pantry',
        StorageUnitType.drawer => 'Drawer',
        StorageUnitType.cabinet => 'Cabinet',
        StorageUnitType.fridge => 'Fridge',
        StorageUnitType.freezer => 'Freezer',
        StorageUnitType.range => 'Cooktop / Range',
        StorageUnitType.sink => 'Sink',
        StorageUnitType.dishwasher => 'Dishwasher',
        StorageUnitType.oven => 'Oven',
        StorageUnitType.gap => 'Open space',
        StorageUnitType.other => 'Other',
      };

  /// Appliances and gaps have no shelves/slots to store items in.
  bool get holdsItems => switch (this) {
        StorageUnitType.range ||
        StorageUnitType.sink ||
        StorageUnitType.dishwasher ||
        StorageUnitType.gap =>
          false,
        _ => true,
      };
}

/// Where a unit is mounted vertically. This is what lets "shelves on top of
/// shelves" work: a [base] and a [wall] unit can share the same floor
/// footprint but live in different vertical bands.
enum UnitMount { base, wall, tall, island, freestanding }

extension UnitMountLabel on UnitMount {
  String get label => switch (this) {
        UnitMount.base => 'Base',
        UnitMount.wall => 'Wall',
        UnitMount.tall => 'Tall',
        UnitMount.island => 'Island',
        UnitMount.freestanding => 'Free-standing',
      };

  /// Occupies the lower band (floor → counter).
  bool get occupiesLower => this != UnitMount.wall;

  /// Occupies the upper band (above counter).
  bool get occupiesUpper =>
      this == UnitMount.wall ||
      this == UnitMount.tall ||
      this == UnitMount.freestanding;
}

/// Room layout uses a simple grid. Each unit occupies a rectangle
/// (gx, gy, gw, gh) in grid cells on its room's canvas.
const int kRoomGridColumns = 4;

/// Human label for a facing direction (quarter turns from "front").
String facingLabel(int facing) => switch (facing % 4) {
      0 => 'Front',
      1 => 'Right',
      2 => 'Back',
      _ => 'Left',
    };

/// Max shelf rows used across the layout renderers.
const int kMaxShelfRows = 8;

/// Centimetres per "storey" factor (≈ one grid cell of height). Used to map an
/// explicit [StorageUnit.heightCm] into the abstract z-bands the renderers use.
const double kCmPerStorey = 100.0;

/// Vertical band a unit occupies, in "storey" factors where ~1.0 is one grid
/// cell of height. This is the single source of truth for unit height across
/// the 2D, 2.5D and 3D views.
///
/// If the unit has an explicit [StorageUnit.heightCm] it drives the height;
/// otherwise it falls back to a sensible height derived from shelf [rows].
({double bottom, double top}) unitZBand(StorageUnit unit) {
  final shelves = unit.rows.clamp(1, kMaxShelfRows);
  final cm = unit.heightCm;
  final explicit = cm != null ? cm / kCmPerStorey : null;

  switch (unit.mount) {
    case UnitMount.wall:
      const bottom = 1.75;
      return (bottom: bottom, top: bottom + (explicit ?? 0.5 + shelves * 0.12));
    case UnitMount.tall:
      return (bottom: 0, top: explicit ?? 2.9 + shelves * 0.02);
    case UnitMount.island:
      return (bottom: 0, top: explicit ?? 0.85 + shelves * 0.05);
    case UnitMount.freestanding:
      return (bottom: 0, top: explicit ?? 2.5);
    case UnitMount.base:
      return (bottom: 0, top: explicit ?? 0.85 + shelves * 0.07);
  }
}

/// Effective height in centimetres (explicit if set, else derived from rows).
int effectiveHeightCm(StorageUnit unit) {
  if (unit.heightCm != null) return unit.heightCm!;
  final band = unitZBand(unit);
  return ((band.top - band.bottom) * kCmPerStorey).round();
}

/// Max doors/bays (columns) a unit can have.
const int kMaxDoors = 4;

/// A ready-made cabinet configuration for the "Add" flow, so common pieces are
/// one tap away instead of a dozen steppers.
class UnitTemplate {
  const UnitTemplate({
    required this.label,
    required this.type,
    required this.mount,
    required this.rows,
    required this.columns,
    required this.heightCm,
    required this.gw,
    required this.gh,
    this.defaultName,
  });

  final String label;
  final StorageUnitType type;
  final UnitMount mount;
  final int rows;
  final int columns;
  final int heightCm;
  final int gw;
  final int gh;
  final String? defaultName;
}

/// Ordered so the first entry is the default when adding a cabinet.
const List<UnitTemplate> kUnitTemplates = [
  UnitTemplate(
    label: 'Big cabinet (2 doors)',
    type: StorageUnitType.cabinet,
    mount: UnitMount.base,
    rows: 3,
    columns: 2,
    heightCm: 90,
    gw: 2,
    gh: 2,
    defaultName: 'Cabinet',
  ),
  UnitTemplate(
    label: 'Drawer stack',
    type: StorageUnitType.drawer,
    mount: UnitMount.base,
    rows: 4,
    columns: 1,
    heightCm: 90,
    gw: 2,
    gh: 2,
    defaultName: 'Drawers',
  ),
  UnitTemplate(
    label: 'Wall cabinet (2 doors)',
    type: StorageUnitType.cabinet,
    mount: UnitMount.wall,
    rows: 2,
    columns: 2,
    heightCm: 70,
    gw: 2,
    gh: 1,
    defaultName: 'Wall cabinet',
  ),
  UnitTemplate(
    label: 'Tall pantry',
    type: StorageUnitType.shelf,
    mount: UnitMount.tall,
    rows: 6,
    columns: 1,
    heightCm: 210,
    gw: 2,
    gh: 2,
    defaultName: 'Pantry',
  ),
  UnitTemplate(
    label: 'Fridge',
    type: StorageUnitType.fridge,
    mount: UnitMount.freestanding,
    rows: 4,
    columns: 1,
    heightCm: 180,
    gw: 2,
    gh: 2,
    defaultName: 'Fridge',
  ),
  UnitTemplate(
    label: 'Sink base',
    type: StorageUnitType.sink,
    mount: UnitMount.base,
    rows: 1,
    columns: 1,
    heightCm: 90,
    gw: 2,
    gh: 2,
    defaultName: 'Sink',
  ),
  UnitTemplate(
    label: 'Cooktop / range',
    type: StorageUnitType.range,
    mount: UnitMount.base,
    rows: 1,
    columns: 1,
    heightCm: 90,
    gw: 2,
    gh: 2,
    defaultName: 'Range',
  ),
];

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
    this.mount = UnitMount.base,
    this.facing = 0,
    this.heightCm,
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

  /// Vertical mounting band.
  final UnitMount mount;

  /// Which way the unit's door/opening faces, in quarter turns (0-3) around
  /// its own center: 0 = front (+y), 1 = right (+x), 2 = back (-y), 3 = left
  /// (-x). Rotating changes this while the footprint stays fixed.
  final int facing;

  /// Explicit physical height in centimetres. When null, height is derived
  /// from [rows] (shelf count) for backward compatibility.
  final int? heightCm;

  /// Position and size on the room layout grid.
  final int gx;
  final int gy;
  final int gw;
  final int gh;

  /// Whether this unit has interior shelves/slots for storing items.
  bool get holdsItems => type.holdsItems;

  static UnitMount _defaultMountFor(StorageUnitType type) {
    return switch (type) {
      StorageUnitType.fridge || StorageUnitType.freezer =>
        UnitMount.freestanding,
      _ => UnitMount.base,
    };
  }

  factory StorageUnit.fromMap(String id, Map<String, dynamic> map) {
    final type = StorageUnitType.values.firstWhere(
      (t) => t.name == map['type'],
      orElse: () => StorageUnitType.shelf,
    );
    return StorageUnit(
      id: id,
      householdId: map['householdId'] as String? ?? '',
      roomId: map['roomId'] as String? ?? '',
      name: map['name'] as String? ?? 'Storage',
      type: type,
      rows: map['rows'] as int? ?? 4,
      columns: map['columns'] as int? ?? 1,
      sortOrder: map['sortOrder'] as int? ?? 0,
      mount: UnitMount.values.firstWhere(
        (m) => m.name == map['mount'],
        orElse: () => _defaultMountFor(type),
      ),
      facing: (map['facing'] as int? ?? 0) % 4,
      heightCm: map['heightCm'] as int?,
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
        'mount': mount.name,
        'facing': facing,
        if (heightCm != null) 'heightCm': heightCm,
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
    UnitMount? mount,
    int? facing,
    int? heightCm,
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
      mount: mount ?? this.mount,
      facing: facing ?? this.facing,
      heightCm: heightCm ?? this.heightCm,
      gx: gx ?? this.gx,
      gy: gy ?? this.gy,
      gw: gw ?? this.gw,
      gh: gh ?? this.gh,
    );
  }
}

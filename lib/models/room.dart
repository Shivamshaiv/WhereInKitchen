/// A free-standing island on the room floor. Each of its four faces is an
/// elevation surface that can hold storage (referenced as
/// `"island:{id}:{N|E|S|W}"`). Stored as an array of maps on the room doc.
class Island {
  const Island({
    required this.id,
    required this.xCm,
    required this.yCm,
    required this.widthCm,
    required this.depthCm,
    this.rotationQuarters = 0,
  });

  final String id;

  /// Footprint origin (top-left) on the floor, in room coordinates (cm).
  final double xCm;
  final double yCm;
  final double widthCm;
  final double depthCm;

  /// Quarter-turns of rotation about the island centre (0-3). Even turns keep
  /// the footprint axis-aligned; odd turns swap width/depth.
  final int rotationQuarters;

  factory Island.fromMap(Map<String, dynamic> map) {
    return Island(
      id: map['id'] as String? ?? '',
      xCm: (map['xCm'] as num?)?.toDouble() ?? 0,
      yCm: (map['yCm'] as num?)?.toDouble() ?? 0,
      widthCm: (map['widthCm'] as num?)?.toDouble() ?? 120,
      depthCm: (map['depthCm'] as num?)?.toDouble() ?? 90,
      rotationQuarters: ((map['rotationQuarters'] as num?)?.toInt() ?? 0) % 4,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'xCm': xCm,
        'yCm': yCm,
        'widthCm': widthCm,
        'depthCm': depthCm,
        'rotationQuarters': rotationQuarters,
      };

  Island copyWith({
    double? xCm,
    double? yCm,
    double? widthCm,
    double? depthCm,
    int? rotationQuarters,
  }) {
    return Island(
      id: id,
      xCm: xCm ?? this.xCm,
      yCm: yCm ?? this.yCm,
      widthCm: widthCm ?? this.widthCm,
      depthCm: depthCm ?? this.depthCm,
      rotationQuarters: rotationQuarters ?? this.rotationQuarters,
    );
  }
}

class Room {
  const Room({
    required this.id,
    required this.householdId,
    required this.name,
    required this.sortOrder,
    this.widthCm = 360,
    this.lengthCm = 300,
    this.wallHeightCm = 270,
    this.islands = const [],
  });

  final String id;
  final String householdId;
  final String name;
  final int sortOrder;

  /// Interior room dimensions (cm). [widthCm] spans the N/S walls (X axis),
  /// [lengthCm] spans the E/W walls (Y axis). [wallHeightCm] is the elevation
  /// canvas height. Defaults keep existing docs (which lack these) valid.
  final double widthCm;
  final double lengthCm;
  final double wallHeightCm;

  final List<Island> islands;

  factory Room.fromMap(String id, Map<String, dynamic> map) {
    return Room(
      id: id,
      householdId: map['householdId'] as String? ?? '',
      name: map['name'] as String? ?? 'Room',
      sortOrder: (map['sortOrder'] as num?)?.toInt() ?? 0,
      widthCm: (map['widthCm'] as num?)?.toDouble() ?? 360,
      lengthCm: (map['lengthCm'] as num?)?.toDouble() ?? 300,
      wallHeightCm: (map['wallHeightCm'] as num?)?.toDouble() ?? 270,
      islands: (map['islands'] as List?)
              ?.map((e) => Island.fromMap(
                    (e as Map).cast<String, dynamic>(),
                  ))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toMap() => {
        'householdId': householdId,
        'name': name,
        'sortOrder': sortOrder,
        'widthCm': widthCm,
        'lengthCm': lengthCm,
        'wallHeightCm': wallHeightCm,
        'islands': islands.map((i) => i.toMap()).toList(),
      };

  Room copyWith({
    String? name,
    int? sortOrder,
    double? widthCm,
    double? lengthCm,
    double? wallHeightCm,
    List<Island>? islands,
  }) {
    return Room(
      id: id,
      householdId: householdId,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      widthCm: widthCm ?? this.widthCm,
      lengthCm: lengthCm ?? this.lengthCm,
      wallHeightCm: wallHeightCm ?? this.wallHeightCm,
      islands: islands ?? this.islands,
    );
  }
}

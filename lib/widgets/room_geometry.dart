import 'dart:math' as math;

/// A minimal 3D vector shared by the room views and the elevation→world math.
/// World units are metres (centimetre values are divided by 100 before use).
class Vec3 {
  const Vec3(this.x, this.y, this.z);
  final double x, y, z;

  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 scale(double s) => Vec3(x * s, y * s, z * s);

  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;
  Vec3 cross(Vec3 o) =>
      Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(dot(this));
  Vec3 get normalized {
    final l = length;
    return l == 0 ? this : Vec3(x / l, y / l, z / l);
  }
}

/// An axis-aligned world-space box (metres), produced by `worldPlacementOf`
/// and consumed by both the 3D painter/hit-test and the 2.5D iso view so all
/// views agree on where a unit sits. `front` marks the outward-facing side so
/// shelves/handles draw on the correct face.
class WorldBox {
  const WorldBox({
    required this.min,
    required this.max,
    required this.front,
  });

  final Vec3 min;
  final Vec3 max;
  final BoxFace front;

  double get width => max.x - min.x;
  double get depth => max.y - min.y;
  double get height => max.z - min.z;
  Vec3 get center => Vec3(
        (min.x + max.x) / 2,
        (min.y + max.y) / 2,
        (min.z + max.z) / 2,
      );
}

/// Which side of a [WorldBox] faces out into the room (the door/shelf side).
enum BoxFace { north, south, east, west }

import 'dart:math' as math;

import 'package:wherein_kitchen/models/room.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';
import 'package:wherein_kitchen/widgets/room_geometry.dart';

/// The four walls of a rectangular room. Room +y is treated as "south" to
/// match the existing 3D face naming (a unit on the NORTH wall faces +y/south).
enum WallSide { north, east, south, west }

extension WallSideLabel on WallSide {
  String get code => switch (this) {
        WallSide.north => 'N',
        WallSide.east => 'E',
        WallSide.south => 'S',
        WallSide.west => 'W',
      };

  String get label => switch (this) {
        WallSide.north => 'North wall',
        WallSide.east => 'East wall',
        WallSide.south => 'South wall',
        WallSide.west => 'West wall',
      };
}

WallSide? wallSideFromCode(String code) => switch (code.toUpperCase()) {
      'N' => WallSide.north,
      'E' => WallSide.east,
      'S' => WallSide.south,
      'W' => WallSide.west,
      _ => null,
    };

// ---- surfaceId helpers -----------------------------------------------------

String wallSurfaceId(WallSide side) => 'wall:${side.code}';
String islandSurfaceId(String islandId, WallSide face) =>
    'island:$islandId:${face.code}';

bool isWallSurface(String surfaceId) => surfaceId.startsWith('wall:');
bool isIslandSurface(String surfaceId) => surfaceId.startsWith('island:');

/// Parses `"wall:N"` → the wall side, else null.
WallSide? wallOfSurface(String surfaceId) {
  if (!isWallSurface(surfaceId)) return null;
  return wallSideFromCode(surfaceId.substring(5));
}

/// Parses `"island:{id}:{face}"` → (islandId, face), else null.
({String islandId, WallSide face})? islandOfSurface(String surfaceId) {
  if (!isIslandSurface(surfaceId)) return null;
  final parts = surfaceId.split(':'); // island : id : F
  if (parts.length != 3) return null;
  final face = wallSideFromCode(parts[2]);
  if (face == null) return null;
  return (islandId: parts[1], face: face);
}

// ---- reference heights (cm) ------------------------------------------------

const double kCounterHeightCm = 90;
const double kWallUnitBaseCm = 145;
const double kDefaultDepthCm = 60;

// ---- surface dimensions ----------------------------------------------------

/// Usable horizontal length (cm) of a surface: a wall's room span, or an
/// island face's edge length. Returns 0 if the surface can't be resolved.
double surfaceLengthCm(Room room, String surfaceId) {
  final wall = wallOfSurface(surfaceId);
  if (wall != null) {
    return (wall == WallSide.north || wall == WallSide.south)
        ? room.widthCm
        : room.lengthCm;
  }
  final isl = islandOfSurface(surfaceId);
  if (isl != null) {
    final island = _islandById(room, isl.islandId);
    if (island == null) return 0;
    final (w, d) = _islandExtents(island);
    return (isl.face == WallSide.north || isl.face == WallSide.south) ? w : d;
  }
  return 0;
}

double surfaceHeightCm(Room room) => room.wallHeightCm;

Island? _islandById(Room room, String id) {
  for (final i in room.islands) {
    if (i.id == id) return i;
  }
  return null;
}

/// Island footprint (widthCm, depthCm) with quarter-turn rotation applied
/// (odd turns swap width/depth so the box stays axis-aligned).
(double, double) _islandExtents(Island island) {
  final odd = island.rotationQuarters.isOdd;
  return odd ? (island.depthCm, island.widthCm) : (island.widthCm, island.depthCm);
}

// ---- world placement -------------------------------------------------------

/// Places [unit] into world space (metres) for the given [room]. Prefers the
/// elevation model (surface + xCm/zCm/widthCm/hCm/depthCm); falls back to the
/// legacy floor-grid + [unitZBand] so un-migrated units still render.
WorldBox worldPlacementOf(StorageUnit unit, Room room) {
  if (unit.hasElevationPlacement) {
    final placed = _worldFromSurface(unit, room);
    if (placed != null) return placed;
  }
  return _worldFromLegacyGrid(unit, room);
}

WorldBox? _worldFromSurface(StorageUnit unit, Room room) {
  final surfaceId = unit.surfaceId!;
  final x = unit.xCm! / 100;
  final z = (unit.zCm ?? 0) / 100;
  final w = unit.widthCm! / 100;
  final h = unit.hCm! / 100;
  final d = (unit.depthCm ?? kDefaultDepthCm) / 100;
  final roomW = room.widthCm / 100;
  final roomL = room.lengthCm / 100;

  final wall = wallOfSurface(surfaceId);
  if (wall != null) {
    switch (wall) {
      case WallSide.north: // wall at y=0, faces +y (south)
        return WorldBox(
          min: Vec3(x, 0, z),
          max: Vec3(x + w, d, z + h),
          front: BoxFace.south,
        );
      case WallSide.south: // wall at y=roomL, faces -y (north)
        return WorldBox(
          min: Vec3(x, roomL - d, z),
          max: Vec3(x + w, roomL, z + h),
          front: BoxFace.north,
        );
      case WallSide.west: // wall at x=0, faces +x (east); surface axis = Y
        return WorldBox(
          min: Vec3(0, x, z),
          max: Vec3(d, x + w, z + h),
          front: BoxFace.east,
        );
      case WallSide.east: // wall at x=roomW, faces -x (west); surface axis = Y
        return WorldBox(
          min: Vec3(roomW - d, x, z),
          max: Vec3(roomW, x + w, z + h),
          front: BoxFace.west,
        );
    }
  }

  final isl = islandOfSurface(surfaceId);
  if (isl != null) {
    final island = _islandById(room, isl.islandId);
    if (island == null) return null;
    final ix = island.xCm / 100;
    final iy = island.yCm / 100;
    final (iwCm, idCm) = _islandExtents(island);
    final iw = iwCm / 100;
    final id = idCm / 100;
    switch (isl.face) {
      case WallSide.north: // -y side, faces north (into -y); axis = X
        return WorldBox(
          min: Vec3(ix + x, iy - d, z),
          max: Vec3(ix + x + w, iy, z + h),
          front: BoxFace.north,
        );
      case WallSide.south: // +y side, faces south; axis = X
        return WorldBox(
          min: Vec3(ix + x, iy + id, z),
          max: Vec3(ix + x + w, iy + id + d, z + h),
          front: BoxFace.south,
        );
      case WallSide.west: // -x side, faces west; axis = Y
        return WorldBox(
          min: Vec3(ix - d, iy + x, z),
          max: Vec3(ix, iy + x + w, z + h),
          front: BoxFace.west,
        );
      case WallSide.east: // +x side, faces east; axis = Y
        return WorldBox(
          min: Vec3(ix + iw, iy + x, z),
          max: Vec3(ix + iw + d, iy + x + w, z + h),
          front: BoxFace.east,
        );
    }
  }
  return null;
}

/// Legacy path: map the abstract 14×14 floor grid + z-band into metres so an
/// un-migrated unit still appears roughly where it used to.
WorldBox _worldFromLegacyGrid(StorageUnit unit, Room room) {
  const cells = 14.0;
  final cellX = (room.widthCm / 100) / cells;
  final cellY = (room.lengthCm / 100) / cells;
  final gx = unit.gx < 0 ? 0 : unit.gx;
  final gy = unit.gy < 0 ? 0 : unit.gy;
  final band = unitZBand(unit); // storeys ≈ metres
  return WorldBox(
    min: Vec3(gx * cellX, gy * cellY, band.bottom),
    max: Vec3((gx + unit.gw) * cellX, (gy + unit.gh) * cellY, band.top),
    front: switch (unit.facing % 4) {
      0 => BoxFace.south,
      1 => BoxFace.east,
      2 => BoxFace.north,
      _ => BoxFace.west,
    },
  );
}

// ---- elevation-editor geometry (cm space) ----------------------------------

/// Whether two elements on the SAME surface overlap. Each is a cm rect
/// (xCm, zCm, widthCm, hCm). Elements in disjoint height bands (e.g. a wall
/// unit above a base unit) do not overlap.
bool elevationRectsOverlap(
  double ax,
  double az,
  double aw,
  double ah,
  double bx,
  double bz,
  double bw,
  double bh,
) {
  return ax < bx + bw &&
      bx < ax + aw &&
      az < bz + bh &&
      bz < az + ah;
}

/// Snaps [value] to the nearest of [targets] within [threshold] cm.
double snapCm(double value, Iterable<double> targets, {double threshold = 3}) {
  var best = value;
  var bestDist = threshold;
  for (final t in targets) {
    final d = (value - t).abs();
    if (d <= bestDist) {
      bestDist = d;
      best = t;
    }
  }
  return best;
}

/// Like [snapCm] but returns the matched target (or null if nothing was within
/// [threshold]). Used to draw an alignment guide only when a snap is active.
double? snappedTo(double value, Iterable<double> targets, {double threshold = 3}) {
  double? best;
  var bestDist = threshold;
  for (final t in targets) {
    final d = (value - t).abs();
    if (d <= bestDist) {
      bestDist = d;
      best = t;
    }
  }
  return best;
}

/// Default bottom (zCm) for a newly placed unit given its mount tag.
double defaultZCmFor(UnitMount mount) => switch (mount) {
      UnitMount.wall => kWallUnitBaseCm,
      _ => 0,
    };

/// Clamp helper shared by the editor.
double clampCm(double v, double lo, double hi) => math.max(lo, math.min(hi, v));

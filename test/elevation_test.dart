import 'package:flutter_test/flutter_test.dart';
import 'package:wherein_kitchen/models/elevation.dart';
import 'package:wherein_kitchen/models/room.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';
import 'package:wherein_kitchen/widgets/room_geometry.dart';

/// Tolerance for floating-point (metre) comparisons.
const double _eps = 1e-9;

Matcher _closeTo(double v) => closeTo(v, _eps);

StorageUnit _unit({
  String? surfaceId,
  double? xCm,
  double? zCm,
  double? widthCm,
  double? hCm,
  double? depthCm,
  int gx = -1,
  int gy = -1,
  int gw = 2,
  int gh = 2,
  int facing = 0,
  int rows = 4,
  int columns = 1,
  UnitMount mount = UnitMount.base,
  StorageUnitType type = StorageUnitType.cabinet,
  int? heightCm,
}) {
  return StorageUnit(
    id: 'u1',
    householdId: 'h1',
    roomId: 'r1',
    name: 'Unit',
    type: type,
    rows: rows,
    columns: columns,
    sortOrder: 0,
    mount: mount,
    facing: facing,
    heightCm: heightCm,
    gx: gx,
    gy: gy,
    gw: gw,
    gh: gh,
    surfaceId: surfaceId,
    xCm: xCm,
    zCm: zCm,
    widthCm: widthCm,
    hCm: hCm,
    depthCm: depthCm,
  );
}

Room _room({
  double widthCm = 360,
  double lengthCm = 300,
  double wallHeightCm = 270,
  List<Island> islands = const [],
}) {
  return Room(
    id: 'r1',
    householdId: 'h1',
    name: 'Kitchen',
    sortOrder: 0,
    widthCm: widthCm,
    lengthCm: lengthCm,
    wallHeightCm: wallHeightCm,
    islands: islands,
  );
}

void main() {
  group('surfaceId round-trips', () {
    test('wallSurfaceId -> wallOfSurface for every side', () {
      for (final side in WallSide.values) {
        final id = wallSurfaceId(side);
        expect(isWallSurface(id), isTrue);
        expect(isIslandSurface(id), isFalse);
        expect(wallOfSurface(id), side);
        // A wall id is never an island id.
        expect(islandOfSurface(id), isNull);
      }
      // Sanity on the exact encoding.
      expect(wallSurfaceId(WallSide.north), 'wall:N');
      expect(wallSurfaceId(WallSide.east), 'wall:E');
      expect(wallSurfaceId(WallSide.south), 'wall:S');
      expect(wallSurfaceId(WallSide.west), 'wall:W');
    });

    test('islandSurfaceId -> islandOfSurface preserves id and face', () {
      final id = islandSurfaceId('isl-42', WallSide.east);
      expect(id, 'island:isl-42:E');
      expect(isIslandSurface(id), isTrue);
      expect(isWallSurface(id), isFalse);
      final parsed = islandOfSurface(id);
      expect(parsed, isNotNull);
      expect(parsed!.islandId, 'isl-42');
      expect(parsed.face, WallSide.east);
      // An island id is never a wall id.
      expect(wallOfSurface(id), isNull);
    });

    test('malformed surfaceIds return null', () {
      // wallOfSurface: prefix present but bad code.
      expect(wallOfSurface('wall:Z'), isNull);
      // Not a wall surface at all.
      expect(wallOfSurface('island:a:N'), isNull);
      expect(wallOfSurface('garbage'), isNull);

      // islandOfSurface: wrong number of parts.
      expect(islandOfSurface('island:onlyid'), isNull);
      expect(islandOfSurface('island:a:b:c'), isNull);
      // Valid shape but bad face code.
      expect(islandOfSurface('island:a:Q'), isNull);
      // Not an island surface at all.
      expect(islandOfSurface('wall:N'), isNull);
    });

    test('wallSideFromCode is case-insensitive and rejects unknowns', () {
      expect(wallSideFromCode('n'), WallSide.north);
      expect(wallSideFromCode('E'), WallSide.east);
      expect(wallSideFromCode('x'), isNull);
    });
  });

  group('surfaceLengthCm', () {
    test('walls report room span along their axis', () {
      final room = _room(widthCm: 360, lengthCm: 300);
      // N/S walls span the width (X axis).
      expect(surfaceLengthCm(room, wallSurfaceId(WallSide.north)), 360);
      expect(surfaceLengthCm(room, wallSurfaceId(WallSide.south)), 360);
      // E/W walls span the length (Y axis).
      expect(surfaceLengthCm(room, wallSurfaceId(WallSide.east)), 300);
      expect(surfaceLengthCm(room, wallSurfaceId(WallSide.west)), 300);
    });

    test('unresolvable surface returns 0', () {
      final room = _room();
      expect(surfaceLengthCm(room, 'garbage'), 0);
      // Island id that does not exist.
      expect(surfaceLengthCm(room, islandSurfaceId('missing', WallSide.north)),
          0);
    });

    test('island face length uses extents, swapped on odd rotation', () {
      const island = Island(
        id: 'i1',
        xCm: 100,
        yCm: 80,
        widthCm: 120,
        depthCm: 90,
      );
      final room = _room(islands: [island]);
      // rotation 0: N/S face = width, E/W face = depth.
      expect(surfaceLengthCm(room, islandSurfaceId('i1', WallSide.north)), 120);
      expect(surfaceLengthCm(room, islandSurfaceId('i1', WallSide.east)), 90);

      // rotation 1 (odd): width/depth swap.
      final rotatedRoom =
          _room(islands: [island.copyWith(rotationQuarters: 1)]);
      expect(
          surfaceLengthCm(rotatedRoom, islandSurfaceId('i1', WallSide.north)),
          90);
      expect(surfaceLengthCm(rotatedRoom, islandSurfaceId('i1', WallSide.east)),
          120);
    });
  });

  group('worldPlacementOf on walls', () {
    // xCm=50, zCm=90, widthCm=60, hCm=70, depthCm=40 -> metres 0.5/0.9/0.6/0.7/0.4
    final room = _room(widthCm: 360, lengthCm: 300);

    test('north wall: at y=0, faces south', () {
      final u = _unit(
        surfaceId: wallSurfaceId(WallSide.north),
        xCm: 50,
        zCm: 90,
        widthCm: 60,
        hCm: 70,
        depthCm: 40,
      );
      final box = worldPlacementOf(u, room);
      expect(box.min.x, _closeTo(0.5));
      expect(box.min.y, _closeTo(0.0));
      expect(box.min.z, _closeTo(0.9));
      expect(box.max.x, _closeTo(1.1));
      expect(box.max.y, _closeTo(0.4));
      expect(box.max.z, _closeTo(1.6));
      expect(box.front, BoxFace.south);
    });

    test('south wall: at y=roomL, faces north', () {
      final u = _unit(
        surfaceId: wallSurfaceId(WallSide.south),
        xCm: 50,
        zCm: 90,
        widthCm: 60,
        hCm: 70,
        depthCm: 40,
      );
      final box = worldPlacementOf(u, room);
      expect(box.min.x, _closeTo(0.5));
      expect(box.min.y, _closeTo(2.6)); // 3.0 - 0.4
      expect(box.min.z, _closeTo(0.9));
      expect(box.max.x, _closeTo(1.1));
      expect(box.max.y, _closeTo(3.0));
      expect(box.max.z, _closeTo(1.6));
      expect(box.front, BoxFace.north);
    });

    test('west wall: at x=0, faces east, surface axis is Y', () {
      final u = _unit(
        surfaceId: wallSurfaceId(WallSide.west),
        xCm: 50,
        zCm: 90,
        widthCm: 60,
        hCm: 70,
        depthCm: 40,
      );
      final box = worldPlacementOf(u, room);
      expect(box.min.x, _closeTo(0.0));
      expect(box.min.y, _closeTo(0.5));
      expect(box.min.z, _closeTo(0.9));
      expect(box.max.x, _closeTo(0.4)); // depth
      expect(box.max.y, _closeTo(1.1)); // x + w
      expect(box.max.z, _closeTo(1.6));
      expect(box.front, BoxFace.east);
    });

    test('east wall: at x=roomW, faces west, surface axis is Y', () {
      final u = _unit(
        surfaceId: wallSurfaceId(WallSide.east),
        xCm: 50,
        zCm: 90,
        widthCm: 60,
        hCm: 70,
        depthCm: 40,
      );
      final box = worldPlacementOf(u, room);
      expect(box.min.x, _closeTo(3.2)); // 3.6 - 0.4
      expect(box.min.y, _closeTo(0.5));
      expect(box.min.z, _closeTo(0.9));
      expect(box.max.x, _closeTo(3.6));
      expect(box.max.y, _closeTo(1.1));
      expect(box.max.z, _closeTo(1.6));
      expect(box.front, BoxFace.west);
    });

    test('depthCm defaults to kDefaultDepthCm when null', () {
      final u = _unit(
        surfaceId: wallSurfaceId(WallSide.north),
        xCm: 0,
        zCm: 0,
        widthCm: 100,
        hCm: 100,
        // depthCm intentionally null -> 60cm -> 0.6m
      );
      final box = worldPlacementOf(u, room);
      expect(box.max.y, _closeTo(0.6));
    });

    test('zCm defaults to 0 when null', () {
      final u = _unit(
        surfaceId: wallSurfaceId(WallSide.north),
        xCm: 0,
        widthCm: 100,
        hCm: 100,
        depthCm: 60,
      );
      final box = worldPlacementOf(u, room);
      expect(box.min.z, _closeTo(0.0));
      expect(box.max.z, _closeTo(1.0));
    });
  });

  group('worldPlacementOf on an island face', () {
    const island = Island(
      id: 'i1',
      xCm: 100,
      yCm: 80,
      widthCm: 120,
      depthCm: 90,
    );
    final room = _room(islands: [island]);

    test('south face: offset by island origin + depth', () {
      final u = _unit(
        surfaceId: islandSurfaceId('i1', WallSide.south),
        xCm: 50,
        zCm: 90,
        widthCm: 60,
        hCm: 70,
        depthCm: 40,
      );
      final box = worldPlacementOf(u, room);
      // ix=1.0 iy=0.8 iw=1.2 id=0.9 ; x=0.5 w=0.6 d=0.4 z=0.9 h=0.7
      expect(box.min.x, _closeTo(1.5)); // ix + x
      expect(box.min.y, _closeTo(1.7)); // iy + id
      expect(box.min.z, _closeTo(0.9));
      expect(box.max.x, _closeTo(2.1)); // ix + x + w
      expect(box.max.y, _closeTo(2.1)); // iy + id + d
      expect(box.max.z, _closeTo(1.6));
      expect(box.front, BoxFace.south);
    });

    test('north face: on -y side of island', () {
      final u = _unit(
        surfaceId: islandSurfaceId('i1', WallSide.north),
        xCm: 50,
        zCm: 0,
        widthCm: 60,
        hCm: 70,
        depthCm: 40,
      );
      final box = worldPlacementOf(u, room);
      expect(box.min.x, _closeTo(1.5)); // ix + x
      expect(box.min.y, _closeTo(0.4)); // iy - d = 0.8 - 0.4
      expect(box.max.x, _closeTo(2.1));
      expect(box.max.y, _closeTo(0.8)); // iy
      expect(box.front, BoxFace.north);
    });

    test('east face: on +x side, axis is Y', () {
      final u = _unit(
        surfaceId: islandSurfaceId('i1', WallSide.east),
        xCm: 50,
        zCm: 0,
        widthCm: 60,
        hCm: 70,
        depthCm: 40,
      );
      final box = worldPlacementOf(u, room);
      expect(box.min.x, _closeTo(2.2)); // ix + iw = 1.0 + 1.2
      expect(box.min.y, _closeTo(1.3)); // iy + x = 0.8 + 0.5
      expect(box.max.x, _closeTo(2.6)); // ix + iw + d
      expect(box.max.y, _closeTo(1.9)); // iy + x + w
      expect(box.front, BoxFace.east);
    });

    test('missing island falls back to legacy grid', () {
      // surfaceId points at an island the room does not have, so
      // _worldFromSurface returns null and worldPlacementOf uses the grid.
      final u = _unit(
        surfaceId: islandSurfaceId('does-not-exist', WallSide.south),
        xCm: 50,
        zCm: 90,
        widthCm: 60,
        hCm: 70,
        depthCm: 40,
        gx: 0,
        gy: 0,
        gw: 2,
        gh: 2,
      );
      final box = worldPlacementOf(u, room);
      // Legacy grid starts at origin for gx=gy=0.
      expect(box.min.x, _closeTo(0.0));
      expect(box.min.y, _closeTo(0.0));
    });
  });

  group('worldPlacementOf legacy-grid fallback', () {
    test('surfaceId null -> maps 14x14 grid into metres', () {
      final room = _room(widthCm: 360, lengthCm: 300);
      final u = _unit(
        gx: 2,
        gy: 3,
        gw: 2,
        gh: 2,
        facing: 0,
        rows: 4,
        mount: UnitMount.base,
      );
      final box = worldPlacementOf(u, room);
      const cellX = 3.6 / 14;
      const cellY = 3.0 / 14;
      expect(box.min.x, _closeTo(2 * cellX));
      expect(box.min.y, _closeTo(3 * cellY));
      expect(box.max.x, _closeTo(4 * cellX));
      expect(box.max.y, _closeTo(5 * cellY));
      // base mount, rows=4 -> top = 0.85 + 4*0.07 = 1.13
      final band = unitZBand(u);
      expect(box.min.z, _closeTo(band.bottom));
      expect(box.max.z, _closeTo(band.top));
      expect(box.front, BoxFace.south); // facing 0
    });

    test('negative grid coords clamp to 0', () {
      final room = _room();
      final u = _unit(gx: -1, gy: -1, gw: 2, gh: 2);
      final box = worldPlacementOf(u, room);
      expect(box.min.x, _closeTo(0.0));
      expect(box.min.y, _closeTo(0.0));
    });

    test('facing maps to the outward face', () {
      final room = _room();
      expect(worldPlacementOf(_unit(gx: 0, gy: 0, facing: 0), room).front,
          BoxFace.south);
      expect(worldPlacementOf(_unit(gx: 0, gy: 0, facing: 1), room).front,
          BoxFace.east);
      expect(worldPlacementOf(_unit(gx: 0, gy: 0, facing: 2), room).front,
          BoxFace.north);
      expect(worldPlacementOf(_unit(gx: 0, gy: 0, facing: 3), room).front,
          BoxFace.west);
    });

    test('incomplete elevation placement still uses grid', () {
      // surfaceId set but hCm null -> hasElevationPlacement is false.
      final room = _room();
      final u = _unit(
        surfaceId: wallSurfaceId(WallSide.north),
        xCm: 50,
        widthCm: 60,
        // hCm null
        gx: 1,
        gy: 1,
      );
      expect(u.hasElevationPlacement, isFalse);
      final box = worldPlacementOf(u, room);
      const cellX = 3.6 / 14;
      expect(box.min.x, _closeTo(1 * cellX));
    });
  });

  group('elevationRectsOverlap', () {
    test('edge-touching does NOT overlap (horizontal)', () {
      // A occupies x in [0,60), B starts exactly at 60 -> touching, no overlap.
      expect(
        elevationRectsOverlap(0, 0, 60, 70, 60, 0, 60, 70),
        isFalse,
      );
    });

    test('edge-touching does NOT overlap (vertical z-band)', () {
      // A z-band [0,70), B starts at z=70 (a wall unit above a base unit).
      expect(
        elevationRectsOverlap(0, 0, 60, 70, 0, 70, 60, 50),
        isFalse,
      );
    });

    test('real overlap in both axes', () {
      // A x[0,60) z[0,70) ; B x[30,90) z[40,110) -> overlaps.
      expect(
        elevationRectsOverlap(0, 0, 60, 70, 30, 40, 60, 70),
        isTrue,
      );
    });

    test('disjoint z-bands do not overlap even if x overlaps', () {
      // Same x span, but A z[0,70) and B z[145,195) (wall unit high up).
      expect(
        elevationRectsOverlap(0, 0, 60, 70, 0, 145, 60, 50),
        isFalse,
      );
    });

    test('disjoint horizontally do not overlap', () {
      expect(
        elevationRectsOverlap(0, 0, 60, 70, 100, 0, 60, 70),
        isFalse,
      );
    });

    test('fully contained overlaps', () {
      expect(
        elevationRectsOverlap(0, 0, 100, 100, 10, 10, 20, 20),
        isTrue,
      );
    });
  });

  group('snapCm / snappedTo', () {
    test('snaps to nearest target within threshold', () {
      expect(snapCm(101, [100, 200], threshold: 3), 100);
      expect(snapCm(198, [100, 200], threshold: 3), 200);
    });

    test('exactly at threshold snaps (<=)', () {
      expect(snapCm(103, [100], threshold: 3), 100);
    });

    test('outside threshold returns original value', () {
      expect(snapCm(110, [100, 200], threshold: 3), 110);
    });

    test('empty targets returns original value', () {
      expect(snapCm(42, const [], threshold: 3), 42);
    });

    test('snappedTo returns matched target or null', () {
      expect(snappedTo(101, [100, 200], threshold: 3), 100);
      expect(snappedTo(198, [100, 200], threshold: 3), 200);
      expect(snappedTo(110, [100, 200], threshold: 3), isNull);
      expect(snappedTo(42, const [], threshold: 3), isNull);
    });

    test('snappedTo picks the closest when several are in range', () {
      // Both 100 and 102 within 3 of 101; 102 is closer.
      expect(snappedTo(101.5, [100, 102], threshold: 3), 102);
    });
  });

  group('defaultZCmFor / clampCm / constants', () {
    test('wall units default to the wall-unit base height', () {
      expect(defaultZCmFor(UnitMount.wall), kWallUnitBaseCm);
      expect(kWallUnitBaseCm, 145);
    });

    test('non-wall mounts default to floor (0)', () {
      expect(defaultZCmFor(UnitMount.base), 0);
      expect(defaultZCmFor(UnitMount.tall), 0);
      expect(defaultZCmFor(UnitMount.island), 0);
      expect(defaultZCmFor(UnitMount.freestanding), 0);
    });

    test('counter-height constant', () {
      expect(kCounterHeightCm, 90);
    });

    test('clampCm clamps into [lo, hi]', () {
      expect(clampCm(-5, 0, 100), 0);
      expect(clampCm(50, 0, 100), 50);
      expect(clampCm(150, 0, 100), 100);
    });
  });
}

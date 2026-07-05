import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wherein_kitchen/data/firestore_paths.dart';
import 'package:wherein_kitchen/models/elevation.dart';
import 'package:wherein_kitchen/models/room.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';

class UnitRepository {
  UnitRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _collection(String householdId) =>
      _firestore.collection(FirestorePaths.units(householdId));

  Stream<List<StorageUnit>> watchUnits(String householdId) {
    return _collection(householdId)
        .orderBy('sortOrder')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => StorageUnit.fromMap(doc.id, doc.data()))
            .toList());
  }

  Stream<List<StorageUnit>> watchUnitsForRoom(
    String householdId,
    String roomId,
  ) {
    return _collection(householdId)
        .where('roomId', isEqualTo: roomId)
        .snapshots()
        .map((snapshot) {
      final units = snapshot.docs
          .map((doc) => StorageUnit.fromMap(doc.id, doc.data()))
          .toList();
      units.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return units;
    });
  }

  Future<StorageUnit> createUnit({
    required String householdId,
    required String roomId,
    required String name,
    required StorageUnitType type,
    required int rows,
    required int columns,
    required int sortOrder,
    UnitMount mount = UnitMount.base,
    int? heightCm,
  }) async {
    final doc = _collection(householdId).doc();
    final unit = StorageUnit(
      id: doc.id,
      householdId: householdId,
      roomId: roomId,
      name: name,
      type: type,
      rows: rows,
      columns: columns,
      sortOrder: sortOrder,
      mount: mount,
      heightCm: heightCm,
    );
    await doc.set(unit.toMap());
    return unit;
  }

  Future<StorageUnit?> getUnit(String householdId, String unitId) async {
    final doc = await _collection(householdId).doc(unitId).get();
    if (!doc.exists) return null;
    return StorageUnit.fromMap(doc.id, doc.data()!);
  }

  Future<void> updateUnit(StorageUnit unit) async {
    await _collection(unit.householdId).doc(unit.id).update(unit.toMap());
  }

  Future<void> updateLayout(
    String householdId,
    String unitId, {
    required int gx,
    required int gy,
    required int gw,
    required int gh,
  }) async {
    await _collection(householdId).doc(unitId).update({
      'gx': gx,
      'gy': gy,
      'gw': gw,
      'gh': gh,
    });
  }

  Future<void> deleteUnit(String householdId, String unitId) async {
    await _collection(householdId).doc(unitId).delete();
  }

  /// Atomically deletes a unit together with all its slots and the items in
  /// those slots, in chunked WriteBatches. Replaces the old three-separate-await
  /// sequence (which could half-complete and orphan items) and the per-slot
  /// item query (N+1) with a single gather-then-batch pass.
  Future<void> deleteUnitCascade(String householdId, String unitId) async {
    final slotsCol = _firestore.collection(FirestorePaths.slots(householdId));
    final itemsCol = _firestore.collection(FirestorePaths.items(householdId));

    final slotSnap =
        await slotsCol.where('unitId', isEqualTo: unitId).get();
    final slotIds = slotSnap.docs.map((d) => d.id).toList();

    final refs = <DocumentReference<Map<String, dynamic>>>[];
    // Items live in those slots — query in chunks (whereIn caps at 30).
    for (var i = 0; i < slotIds.length; i += 30) {
      final chunk = slotIds.sublist(i, math.min(i + 30, slotIds.length));
      final itemSnap =
          await itemsCol.where('slotId', whereIn: chunk).get();
      refs.addAll(itemSnap.docs.map((d) => d.reference));
    }
    refs.addAll(slotSnap.docs.map((d) => d.reference));
    refs.add(_collection(householdId).doc(unitId));

    await _commitDeletesInChunks(refs);
  }

  Future<void> _commitDeletesInChunks(
      List<DocumentReference<Map<String, dynamic>>> refs) async {
    // Firestore caps a batch at 500 writes; stay well under.
    for (var i = 0; i < refs.length; i += 450) {
      final batch = _firestore.batch();
      for (final ref in refs.sublist(i, math.min(i + 450, refs.length))) {
        batch.delete(ref);
      }
      await batch.commit();
    }
  }

  /// Persists a unit's elevation placement (wall/island surface + free dims).
  Future<void> updateElevation(
    String householdId,
    String unitId, {
    required String surfaceId,
    required double xCm,
    required double zCm,
    required double widthCm,
    required double hCm,
    required double depthCm,
  }) async {
    await _collection(householdId).doc(unitId).update({
      'surfaceId': surfaceId,
      'xCm': xCm,
      'zCm': zCm,
      'widthCm': widthCm,
      'hCm': hCm,
      'depthCm': depthCm,
    });
  }

  /// Best-effort, idempotent migration of a room's legacy floor-grid units into
  /// the wall-elevation model. Only touches units that are placed on the old
  /// grid and not yet on a surface (`surfaceId == null`), so it never clobbers
  /// manual placements and is safe to re-run. Slots/items are untouched.
  Future<void> migrateRoomToElevation({
    required String householdId,
    required Room room,
    required List<StorageUnit> unitsInRoom,
  }) async {
    // Migrate every unit not yet on a surface (including ones with no legacy
    // grid position — they default to the north wall, sequenced left-to-right —
    // so nothing is left invisible).
    final todo = unitsInRoom.where((u) => u.surfaceId == null).toList();
    if (todo.isEmpty) return;

    const cells = 14.0;
    final cellX = room.widthCm / cells;
    final cellY = room.lengthCm / cells;

    WallSide wallFor(StorageUnit u) {
      // Free-standing/island units: nearest wall by footprint centre.
      if (u.mount == UnitMount.island || u.mount == UnitMount.freestanding) {
        final cx = u.gx + u.gw / 2;
        final cy = u.gy + u.gh / 2;
        final dN = cy, dS = cells - cy, dW = cx, dE = cells - cx;
        final m = [dN, dS, dW, dE].reduce(math.min);
        if (m == dN) return WallSide.north;
        if (m == dS) return WallSide.south;
        if (m == dW) return WallSide.west;
        return WallSide.east;
      }
      // Everything else: the wall its door faces away from.
      return switch (u.facing % 4) {
        0 => WallSide.north,
        1 => WallSide.west,
        2 => WallSide.south,
        _ => WallSide.east,
      };
    }

    final placements = <_Placement>[];
    for (final u in todo) {
      final wall = wallFor(u);
      final band = unitZBand(u);
      final zCm = (band.bottom * kCmPerStorey).clamp(0.0, room.wallHeightCm);
      final hCm = ((band.top - band.bottom) * kCmPerStorey)
          .clamp(10.0, room.wallHeightCm - zCm);
      final double xCm;
      final double widthCm;
      final double depthCm;
      if (wall == WallSide.north || wall == WallSide.south) {
        xCm = u.gx * cellX;
        widthCm = math.max(20.0, u.gw * cellX);
        depthCm = (u.gh * cellY).clamp(30.0, 65.0);
      } else {
        xCm = u.gy * cellY;
        widthCm = math.max(20.0, u.gh * cellY);
        depthCm = (u.gw * cellX).clamp(30.0, 65.0);
      }
      double round5(double v) => ((v / 5).round() * 5).toDouble();
      placements.add(_Placement(
        unitId: u.id,
        wall: wall,
        xCm: math.max(0.0, xCm),
        zCm: round5(zCm.toDouble()),
        widthCm: round5(widthCm),
        hCm: round5(math.max(10.0, hCm.toDouble())),
        depthCm: round5(depthCm.toDouble()),
      ));
    }

    // Resolve same-band overlaps per wall with a push-right pass.
    for (final wall in WallSide.values) {
      final onWall = placements.where((p) => p.wall == wall).toList()
        ..sort((a, b) => a.xCm.compareTo(b.xCm));
      final placed = <_Placement>[];
      for (final p in onWall) {
        var guard = 0;
        _Placement? blocker() => placed.cast<_Placement?>().firstWhere(
              (q) => q != null &&
                  elevationRectsOverlap(p.xCm, p.zCm, p.widthCm, p.hCm,
                      q.xCm, q.zCm, q.widthCm, q.hCm),
              orElse: () => null,
            );
        for (var b = blocker(); b != null && guard++ < 200; b = blocker()) {
          p.xCm = b.xCm + b.widthCm;
        }
        // Keep the unit on the wall: never let the push shove it off the end.
        final maxX = surfaceLengthCm(room, wallSurfaceId(wall));
        p.xCm = math.min(p.xCm, math.max(0.0, maxX - p.widthCm));
        placed.add(p);
      }
    }

    final batch = _firestore.batch();
    for (final p in placements) {
      batch.update(_collection(householdId).doc(p.unitId), {
        'surfaceId': wallSurfaceId(p.wall),
        'xCm': p.xCm,
        'zCm': p.zCm,
        'widthCm': p.widthCm,
        'hCm': p.hCm,
        'depthCm': p.depthCm,
      });
    }
    await batch.commit();
  }
}

class _Placement {
  _Placement({
    required this.unitId,
    required this.wall,
    required this.xCm,
    required this.zCm,
    required this.widthCm,
    required this.hCm,
    required this.depthCm,
  });

  final String unitId;
  final WallSide wall;
  double xCm;
  final double zCm;
  final double widthCm;
  final double hCm;
  final double depthCm;
}

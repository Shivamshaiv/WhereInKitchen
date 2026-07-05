import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wherein_kitchen/models/elevation.dart';
import 'package:wherein_kitchen/models/room.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';
import 'package:wherein_kitchen/providers/providers.dart';
import 'package:wherein_kitchen/screens/room/wall_elevation_screen.dart';
import 'package:wherein_kitchen/screens/unit/unit_peek_screen.dart';
import 'package:wherein_kitchen/widgets/room_geometry.dart';
import 'package:wherein_kitchen/widgets/unit_colors.dart';

/// True 3D room view with an orbiting camera. Assembles the room from every
/// wall/island surface's elevation placement (world units = metres).
///
/// - One-finger drag orbits the camera (yaw + pitch); pinch zooms.
/// - Tap a unit to select it and open its shelves.
class Room3DScreen extends ConsumerStatefulWidget {
  const Room3DScreen({super.key, required this.room, this.focusUnitId});

  final Room room;

  /// When set, the camera frames this unit on open and it starts selected —
  /// used by "See it in 3D" from a search result.
  final String? focusUnitId;

  @override
  ConsumerState<Room3DScreen> createState() => _Room3DScreenState();
}

class _Room3DScreenState extends ConsumerState<Room3DScreen> {
  static const double _defaultYaw = math.pi / 4;
  static const double _defaultPitch = 0.5;
  double _yaw = _defaultYaw;
  double _pitch = _defaultPitch;
  double _distance = 6;
  double _startDistance = 6;

  Vec3 _target = const Vec3(1.8, 1.5, 0.9);
  bool _framed = false;

  String? _selectedUnitId;

  @override
  void initState() {
    super.initState();
    _selectedUnitId = widget.focusUnitId;
  }

  Room _liveRoom() {
    final rooms = ref.read(roomsProvider).value;
    if (rooms != null) {
      for (final r in rooms) {
        if (r.id == widget.room.id) return r;
      }
    }
    return widget.room;
  }

  List<StorageUnit> _unitsForRoom(List<StorageUnit> all) {
    final units = all.where((u) => u.roomId == widget.room.id).toList();
    units.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return units;
  }

  void _frameUnits(List<StorageUnit> units, Room room, Size size) {
    final cx = room.widthCm / 200;
    final cy = room.lengthCm / 200;
    if (units.isEmpty) {
      _target = Vec3(cx, cy, 0.9);
      _distance = math.max(room.widthCm, room.lengthCm) / 100 * 1.4 + 2;
      return;
    }

    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = -double.infinity,
        maxY = -double.infinity,
        maxZ = -double.infinity;
    for (final u in units) {
      final b = worldPlacementOf(u, room);
      minX = math.min(minX, b.min.x);
      minY = math.min(minY, b.min.y);
      minZ = math.min(minZ, b.min.z);
      maxX = math.max(maxX, b.max.x);
      maxY = math.max(maxY, b.max.y);
      maxZ = math.max(maxZ, b.max.z);
    }

    _target = Vec3((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2);
    final radius =
        Vec3(maxX - minX, maxY - minY, maxZ - minZ).scale(0.5).length + 0.8;
    _distance = (radius / 0.32 * 1.15).clamp(2.5, 30.0);
  }

  /// Frame the camera tightly on a single unit (for "See it in 3D").
  void _frameOnUnit(StorageUnit unit, Room room) {
    final b = worldPlacementOf(unit, room);
    _target = b.center;
    final radius = Vec3(b.width, b.depth, b.height).scale(0.5).length + 0.5;
    _distance = (radius / 0.32 * 1.15).clamp(1.4, 20.0);
  }

  _Camera _camera(Size size) {
    return _Camera(
      target: _target,
      yaw: _yaw,
      pitch: _pitch,
      distance: _distance,
      viewport: size,
    );
  }

  void _onScaleStart(ScaleStartDetails details) {
    _startDistance = _distance;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      if (details.pointerCount >= 2) {
        _distance = (_startDistance / details.scale).clamp(1.2, 40.0);
      }
      _yaw -= details.focalPointDelta.dx * 0.008;
      _pitch =
          (_pitch + details.focalPointDelta.dy * 0.006).clamp(0.12, 1.35);
    });
  }

  void _onTapUp(
      TapUpDetails details, Size size, List<StorageUnit> units, Room room) {
    final camera = _camera(size);
    final hit = _hitTest(details.localPosition, camera, units, room);
    setState(() => _selectedUnitId = hit?.id);
  }

  StorageUnit? _hitTest(
      Offset position, _Camera camera, List<StorageUnit> units, Room room) {
    // Ray from the camera through the tapped pixel; pick the nearest box hit.
    final dir = camera.rayDirThrough(position);
    StorageUnit? best;
    var bestT = double.infinity;
    for (final unit in units) {
      final b = worldPlacementOf(unit, room);
      final t = _rayBoxT(camera.eye, dir, b.min.x, b.max.x, b.min.y, b.max.y,
          b.min.z, b.max.z);
      if (t != null && t < bestT) {
        bestT = t;
        best = unit;
      }
    }
    return best;
  }

  double? _rayBoxT(Vec3 o, Vec3 d, double x0, double x1, double y0, double y1,
      double z0, double z1) {
    var tmin = -double.infinity;
    var tmax = double.infinity;

    bool slab(double origin, double dir, double lo, double hi) {
      if (dir.abs() < 1e-9) return origin >= lo && origin <= hi;
      var t1 = (lo - origin) / dir;
      var t2 = (hi - origin) / dir;
      if (t1 > t2) {
        final tmp = t1;
        t1 = t2;
        t2 = tmp;
      }
      if (t1 > tmin) tmin = t1;
      if (t2 < tmax) tmax = t2;
      return true;
    }

    if (!slab(o.x, d.x, x0, x1)) return null;
    if (!slab(o.y, d.y, y0, y1)) return null;
    if (!slab(o.z, d.z, z0, z1)) return null;
    if (tmax < tmin || tmax < 0) return null;
    return tmin >= 0 ? tmin : tmax;
  }

  void _editOnWall(StorageUnit unit, Room room) {
    final sid = unit.surfaceId;
    if (sid == null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(
            content: Text("This unit isn't placed on a wall yet")));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WallElevationScreen(room: room, surfaceId: sid),
      ),
    );
  }

  void _openSelected(List<StorageUnit> units) {
    final unit = units.where((u) => u.id == _selectedUnitId).firstOrNull;
    if (unit == null) return;
    if (!unit.holdsItems) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text('${unit.name} · ${unit.type.label}')),
        );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => UnitPeekScreen(unit: unit)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final room = _liveRoom();
    final unitsAsync = ref.watch(unitsProvider);
    final items = ref.watch(itemsProvider).value ?? [];
    final slots = ref.watch(slotsProvider).value ?? [];

    final slotToUnit = {for (final s in slots) s.id: s.unitId};
    final itemCountByUnit = <String, int>{};
    for (final item in items) {
      final unitId = slotToUnit[item.slotId];
      if (unitId != null) {
        itemCountByUnit[unitId] = (itemCountByUnit[unitId] ?? 0) + 1;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${room.name} · 3D',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Reset camera',
            icon: const Icon(Icons.restart_alt),
            onPressed: () => setState(() {
              _yaw = _defaultYaw;
              _pitch = _defaultPitch;
              _framed = false;
            }),
          ),
        ],
      ),
      body: unitsAsync.when(
        data: (allUnits) {
          final units = _unitsForRoom(allUnits);
          final selected =
              units.where((u) => u.id == _selectedUnitId).firstOrNull;

          return Stack(
            children: [
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size =
                        Size(constraints.maxWidth, constraints.maxHeight);
                    if (!_framed && size.width.isFinite) {
                      final focus = widget.focusUnitId == null
                          ? null
                          : units
                              .where((u) => u.id == widget.focusUnitId)
                              .firstOrNull;
                      if (focus != null) {
                        _frameOnUnit(focus, room);
                      } else {
                        _frameUnits(units, room, size);
                      }
                      _framed = true;
                    }
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onScaleStart: _onScaleStart,
                      onScaleUpdate: _onScaleUpdate,
                      onTapUp: (d) => _onTapUp(d, size, units, room),
                      child: CustomPaint(
                        size: size,
                        painter: _Room3DPainter(
                          units: units,
                          room: room,
                          camera: _camera(size),
                          selectedUnitId: _selectedUnitId,
                          itemCountByUnit: itemCountByUnit,
                          scheme: Theme.of(context).colorScheme,
                        ),
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 8,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      selected == null
                          ? 'Drag to orbit · pinch to zoom · tap a unit'
                          : 'Design placement on the wall elevation',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ),
              ),
              if (selected != null)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 16,
                  child: _Selected3DToolbar(
                    unit: selected,
                    onEditOnWall: () => _editOnWall(selected, room),
                    onOpen: () => _openSelected(units),
                    onClose: () => setState(() => _selectedUnitId = null),
                  ),
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

/// Bottom toolbar for the selected unit: open its shelves.
class _Selected3DToolbar extends StatelessWidget {
  const _Selected3DToolbar({
    required this.unit,
    required this.onEditOnWall,
    required this.onOpen,
    required this.onClose,
  });

  final StorageUnit unit;
  final VoidCallback onEditOnWall;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    unit.name,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    unit.type.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Edit on wall',
              icon: const Icon(Icons.dashboard_customize_outlined),
              onPressed: onEditOnWall,
            ),
            if (unit.holdsItems)
              IconButton(
                tooltip: 'Open shelves',
                icon: const Icon(Icons.visibility_outlined),
                onPressed: onOpen,
              ),
            IconButton(
              tooltip: 'Deselect',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close),
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Camera
// ---------------------------------------------------------------------------

class _Projected {
  const _Projected(this.offset, this.depth);
  final Offset offset;
  final double depth;
}

/// Perspective camera orbiting [target] at [distance], angles in radians.
class _Camera {
  _Camera({
    required this.target,
    required double yaw,
    required double pitch,
    required double distance,
    required this.viewport,
  }) {
    eye = target +
        Vec3(
          math.cos(pitch) * math.sin(yaw),
          math.cos(pitch) * math.cos(yaw),
          math.sin(pitch),
        ).scale(distance);
    forward = (target - eye).normalized;
    right = forward.cross(const Vec3(0, 0, 1)).normalized;
    up = right.cross(forward);
    focal = math.min(viewport.width, viewport.height) * 1.45;
  }

  final Vec3 target;
  final Size viewport;
  late final Vec3 eye;
  late final Vec3 forward;
  late final Vec3 right;
  late final Vec3 up;
  late final double focal;

  _Projected? project(Vec3 p) {
    final v = p - eye;
    final zc = v.dot(forward);
    if (zc <= 0.1) return null;
    final xc = v.dot(right);
    final yc = v.dot(up);
    final sx = viewport.width / 2 + focal * xc / zc;
    final sy = viewport.height / 2 - focal * yc / zc;
    if (!sx.isFinite || !sy.isFinite) return null;
    // Clamp far outside any viewport so CanvasKit never has to rasterize a
    // runaway-size polygon — that blocks the single-threaded web canvas and
    // hangs the whole tab. Off-screen corners stay off-screen; visible shape
    // is unchanged.
    return _Projected(
      Offset(sx.clamp(-1e4, 1e4).toDouble(), sy.clamp(-1e4, 1e4).toDouble()),
      zc,
    );
  }

  Vec3 rayDirThrough(Offset p) {
    final nx = (p.dx - viewport.width / 2) / focal;
    final ny = -(p.dy - viewport.height / 2) / focal;
    return (forward + right.scale(nx) + up.scale(ny)).normalized;
  }
}

// ---------------------------------------------------------------------------
// Unit geometry
// ---------------------------------------------------------------------------

enum _FaceDir { top, bottom, north, south, east, west }

class _Face {
  const _Face(this.corners, this.normal, this.dir);
  final List<Vec3> corners;
  final Vec3 normal;
  final _FaceDir dir;
}

/// Six faces of a unit's world-space box, plus which face is its front.
class _UnitBox {
  _UnitBox(this.box) {
    final x0 = box.min.x, x1 = box.max.x;
    final y0 = box.min.y, y1 = box.max.y;
    final z0 = box.min.z, z1 = box.max.z;
    faces = [
      _Face(
        [Vec3(x0, y0, z1), Vec3(x1, y0, z1), Vec3(x1, y1, z1), Vec3(x0, y1, z1)],
        const Vec3(0, 0, 1),
        _FaceDir.top,
      ),
      _Face(
        [Vec3(x0, y0, z0), Vec3(x1, y0, z0), Vec3(x1, y1, z0), Vec3(x0, y1, z0)],
        const Vec3(0, 0, -1),
        _FaceDir.bottom,
      ),
      _Face(
        [Vec3(x0, y1, z0), Vec3(x1, y1, z0), Vec3(x1, y1, z1), Vec3(x0, y1, z1)],
        const Vec3(0, 1, 0),
        _FaceDir.south,
      ),
      _Face(
        [Vec3(x1, y0, z0), Vec3(x0, y0, z0), Vec3(x0, y0, z1), Vec3(x1, y0, z1)],
        const Vec3(0, -1, 0),
        _FaceDir.north,
      ),
      _Face(
        [Vec3(x1, y1, z0), Vec3(x1, y0, z0), Vec3(x1, y0, z1), Vec3(x1, y1, z1)],
        const Vec3(1, 0, 0),
        _FaceDir.east,
      ),
      _Face(
        [Vec3(x0, y0, z0), Vec3(x0, y1, z0), Vec3(x0, y1, z1), Vec3(x0, y0, z1)],
        const Vec3(-1, 0, 0),
        _FaceDir.west,
      ),
    ];
  }

  final WorldBox box;
  late final List<_Face> faces;

  _FaceDir get frontDir => switch (box.front) {
        BoxFace.north => _FaceDir.north,
        BoxFace.south => _FaceDir.south,
        BoxFace.east => _FaceDir.east,
        BoxFace.west => _FaceDir.west,
      };

  Vec3 get center => box.center;
}

// ---------------------------------------------------------------------------
// Painter
// ---------------------------------------------------------------------------

class _PaintFace {
  const _PaintFace({
    required this.unit,
    required this.face,
    required this.points,
    required this.depth,
    required this.isFront,
  });
  final StorageUnit unit;
  final _Face face;
  final List<Offset> points;
  final double depth;
  final bool isFront;
}

class _Room3DPainter extends CustomPainter {
  _Room3DPainter({
    required this.units,
    required this.room,
    required this.camera,
    required this.selectedUnitId,
    required this.itemCountByUnit,
    required this.scheme,
  });

  final List<StorageUnit> units;
  final Room room;
  final _Camera camera;
  final String? selectedUnitId;
  final Map<String, int> itemCountByUnit;
  final ColorScheme scheme;

  double get _roomW => room.widthCm / 100;
  double get _roomL => room.lengthCm / 100;
  double get _wallHeight => room.wallHeightCm / 100;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(scheme.surfaceContainerLow, scheme.primary, 0.05)!,
            scheme.surfaceContainerLowest,
          ],
        ).createShader(Offset.zero & size),
    );

    _paintWalls(canvas);
    _paintFloor(canvas);

    // Gaps are floor decals — draw first.
    for (final unit in units.where((u) => u.type == StorageUnitType.gap)) {
      _paintGap(canvas, unit);
    }

    // Collect unit faces AND island faces into ONE depth-sorted list, so
    // islands correctly occlude / are occluded by units (not a blind pre-pass).
    final drawables = <({double depth, void Function(Canvas) draw})>[];

    for (final unit in units) {
      if (unit.type == StorageUnitType.gap) continue;
      final box = _UnitBox(worldPlacementOf(unit, room));
      for (final face in box.faces) {
        if (face.dir == _FaceDir.bottom) continue;
        final faceCenter = face.corners
            .reduce((a, b) => a + b)
            .scale(1 / face.corners.length);
        if (face.normal.dot(camera.eye - faceCenter) <= 0) continue;

        final pts = <Offset>[];
        var depth = 0.0;
        var behind = false;
        for (final v in face.corners) {
          final p = camera.project(v);
          if (p == null) {
            behind = true;
            break;
          }
          pts.add(p.offset);
          depth += p.depth;
        }
        if (behind) continue;
        final pf = _PaintFace(
          unit: unit,
          face: face,
          points: pts,
          depth: depth / face.corners.length,
          isFront: face.dir == box.frontDir,
        );
        drawables.add((depth: pf.depth, draw: (c) => _paintFace(c, pf)));
      }
    }

    for (final island in room.islands) {
      for (final f in _islandFaces(island)) {
        final faceCenter =
            f.corners.reduce((a, b) => a + b).scale(1 / f.corners.length);
        if (f.normal.dot(camera.eye - faceCenter) <= 0) continue;
        final pts = <Offset>[];
        var depth = 0.0;
        var behind = false;
        for (final v in f.corners) {
          final p = camera.project(v);
          if (p == null) {
            behind = true;
            break;
          }
          pts.add(p.offset);
          depth += p.depth;
        }
        if (behind) continue;
        final color = _shade(
            Color.lerp(scheme.surfaceContainerHighest, scheme.tertiary, 0.1)!,
            f.shade);
        final poly = pts;
        drawables.add((
          depth: depth / f.corners.length,
          draw: (c) {
            final path = Path()..addPolygon(poly, true);
            c.drawPath(path, Paint()..color = color);
            c.drawPath(
              path,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1
                ..color = Colors.black.withValues(alpha: 0.25),
            );
          },
        ));
      }
    }

    drawables.sort((a, b) => b.depth.compareTo(a.depth));
    for (final d in drawables) {
      d.draw(canvas);
    }

    final labelOrder = [...units]..sort((a, b) {
        final da =
            (camera.eye - worldPlacementOf(a, room).center).length;
        final db =
            (camera.eye - worldPlacementOf(b, room).center).length;
        return db.compareTo(da);
      });
    for (final unit in labelOrder) {
      _paintLabel(canvas, unit);
    }
  }

  void _paintFloor(Canvas canvas) {
    Offset? proj(double x, double y, [double z = 0]) =>
        camera.project(Vec3(x, y, z))?.offset;

    final c00 = proj(0, 0);
    final c10 = proj(_roomW, 0);
    final c11 = proj(_roomW, _roomL);
    final c01 = proj(0, _roomL);
    if (c00 == null || c10 == null || c11 == null || c01 == null) return;

    canvas.drawPath(
      Path()..addPolygon([c00, c10, c11, c01], true),
      Paint()
        ..color = Color.lerp(scheme.surfaceContainerHigh, scheme.primary, 0.05)!,
    );

    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = scheme.outlineVariant.withValues(alpha: 0.6);
    for (var x = 0.0; x <= _roomW + 0.001; x += 1.0) {
      final a = proj(x, 0);
      final b = proj(x, _roomL);
      if (a != null && b != null) canvas.drawLine(a, b, gridPaint);
    }
    for (var y = 0.0; y <= _roomL + 0.001; y += 1.0) {
      final a = proj(0, y);
      final b = proj(_roomW, y);
      if (a != null && b != null) canvas.drawLine(a, b, gridPaint);
    }
  }

  void _paintWalls(Canvas canvas) {
    final w = _roomW, l = _roomL, h = _wallHeight;
    final walls = <({List<Vec3> corners, Vec3 normal})>[
      (
        corners: [const Vec3(0, 0, 0), Vec3(w, 0, 0), Vec3(w, 0, h), Vec3(0, 0, h)],
        normal: const Vec3(0, -1, 0)
      ),
      (
        corners: [Vec3(0, l, 0), Vec3(w, l, 0), Vec3(w, l, h), Vec3(0, l, h)],
        normal: const Vec3(0, 1, 0)
      ),
      (
        corners: [const Vec3(0, 0, 0), Vec3(0, l, 0), Vec3(0, l, h), Vec3(0, 0, h)],
        normal: const Vec3(-1, 0, 0)
      ),
      (
        corners: [Vec3(w, 0, 0), Vec3(w, l, 0), Vec3(w, l, h), Vec3(w, 0, h)],
        normal: const Vec3(1, 0, 0)
      ),
    ];

    for (final wall in walls) {
      final center =
          wall.corners.reduce((a, b) => a + b).scale(1 / wall.corners.length);
      if (wall.normal.dot(camera.eye - center) > 0) continue;
      final pts = <Offset>[];
      var behind = false;
      for (final v in wall.corners) {
        final p = camera.project(v);
        if (p == null) {
          behind = true;
          break;
        }
        pts.add(p.offset);
      }
      if (behind) continue;
      final path = Path()..addPolygon(pts, true);
      canvas.drawPath(
        path,
        Paint()
          ..color =
              Color.lerp(scheme.surfaceContainerHighest, scheme.primary, 0.04)!
                  .withValues(alpha: 0.96),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = scheme.outlineVariant.withValues(alpha: 0.7),
      );
    }
  }

  /// The visible faces of an island block (top + 4 sides) with outward normals
  /// and a shade, for backface culling + depth sorting alongside unit faces.
  List<({List<Vec3> corners, Vec3 normal, double shade})> _islandFaces(
      Island island) {
    final odd = island.rotationQuarters.isOdd;
    final w = (odd ? island.depthCm : island.widthCm) / 100;
    final d = (odd ? island.widthCm : island.depthCm) / 100;
    final x0 = island.xCm / 100, y0 = island.yCm / 100;
    final x1 = x0 + w, y1 = y0 + d;
    const top = kCounterHeightCm / 100;
    return [
      (
        corners: [Vec3(x0, y0, top), Vec3(x1, y0, top), Vec3(x1, y1, top), Vec3(x0, y1, top)],
        normal: const Vec3(0, 0, 1),
        shade: 0.98
      ),
      (
        corners: [Vec3(x0, y0, 0), Vec3(x1, y0, 0), Vec3(x1, y0, top), Vec3(x0, y0, top)],
        normal: const Vec3(0, -1, 0),
        shade: 0.72
      ),
      (
        corners: [Vec3(x0, y1, 0), Vec3(x1, y1, 0), Vec3(x1, y1, top), Vec3(x0, y1, top)],
        normal: const Vec3(0, 1, 0),
        shade: 0.66
      ),
      (
        corners: [Vec3(x0, y0, 0), Vec3(x0, y1, 0), Vec3(x0, y1, top), Vec3(x0, y0, top)],
        normal: const Vec3(-1, 0, 0),
        shade: 0.6
      ),
      (
        corners: [Vec3(x1, y0, 0), Vec3(x1, y1, 0), Vec3(x1, y1, top), Vec3(x1, y0, top)],
        normal: const Vec3(1, 0, 0),
        shade: 0.54
      ),
    ];
  }

  void _paintGap(Canvas canvas, StorageUnit unit) {
    final b = worldPlacementOf(unit, room);
    final corners = [
      Vec3(b.min.x, b.min.y, 0.01),
      Vec3(b.max.x, b.min.y, 0.01),
      Vec3(b.max.x, b.max.y, 0.01),
      Vec3(b.min.x, b.max.y, 0.01),
    ];
    final pts = <Offset>[];
    for (final v in corners) {
      final p = camera.project(v);
      if (p == null) return;
      pts.add(p.offset);
    }
    final path = Path()..addPolygon(pts, true);
    canvas.drawPath(
        path, Paint()..color = scheme.outlineVariant.withValues(alpha: 0.18));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = unit.id == selectedUnitId ? 2.4 : 1.2
        ..color = unit.id == selectedUnitId
            ? scheme.primary
            : scheme.outline.withValues(alpha: 0.5),
    );
  }

  void _paintFace(Canvas canvas, _PaintFace pf) {
    final selected = pf.unit.id == selectedUnitId;
    final base = unitBaseColor(pf.unit.type, scheme);

    final light = const Vec3(0.4, -0.55, 0.73).normalized;
    final lit = (pf.face.normal.dot(light) + 1) / 2;
    var color = Color.lerp(
      _shade(base, 0.45),
      Color.lerp(base, Colors.white, 0.25)!,
      lit,
    )!;
    if (selected) color = Color.lerp(color, scheme.primary, 0.3)!;
    if (pf.isFront) {
      color = Color.lerp(color, const Color(0xFFFFE0B2), 0.14)!;
    }

    final path = Path()..addPolygon(pf.points, true);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 2.2 : 1
        ..color =
            selected ? scheme.primary : Colors.black.withValues(alpha: 0.35),
    );

    if (pf.isFront) _paintFrontDetails(canvas, pf);
  }

  void _paintFrontDetails(Canvas canvas, _PaintFace pf) {
    final unit = pf.unit;
    final pts = pf.points;
    if (pts.length != 4) return;
    final b0 = pts[0], b1 = pts[1], t1 = pts[2], t0 = pts[3];

    Offset at(double tx, double tz) {
      final bottom = Offset.lerp(b0, b1, tx)!;
      final top = Offset.lerp(t0, t1, tx)!;
      return Offset.lerp(bottom, top, tz)!;
    }

    final shelfPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..color = Colors.black.withValues(alpha: 0.3);

    if (unit.holdsItems) {
      final rowCount = unit.rows.clamp(1, kMaxShelfRows);
      for (var i = 1; i < rowCount; i++) {
        final tz = i / rowCount;
        canvas.drawLine(at(0.06, tz), at(0.94, tz), shelfPaint);
      }
      final colCount = unit.columns.clamp(1, kMaxDoors);
      if (colCount > 1) {
        for (var c = 1; c < colCount; c++) {
          final tx = c / colCount;
          canvas.drawLine(at(tx, 0.04), at(tx, 0.96), shelfPaint);
        }
      }
    }

    canvas.drawLine(
      at(0.9, 0.35),
      at(0.9, 0.65),
      Paint()
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = Colors.black.withValues(alpha: 0.4),
    );
  }

  void _paintLabel(Canvas canvas, StorageUnit unit) {
    final b = worldPlacementOf(unit, room);
    final anchor =
        camera.project(Vec3(b.center.x, b.center.y, b.max.z + 0.12));
    if (anchor == null) return;

    final alpha = (1.6 - anchor.depth / 8).clamp(0.35, 1.0);
    final selected = unit.id == selectedUnitId;
    final count = itemCountByUnit[unit.id] ?? 0;

    final text = selected && unit.holdsItems && count > 0
        ? '${unit.name} · $count items'
        : unit.name;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: selected ? 13 : 11,
          fontWeight: FontWeight.w700,
          color: Colors.black.withValues(alpha: 0.85 * alpha),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 140);

    final center = Offset(anchor.offset.dx, anchor.offset.dy - 12);
    final bg = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center,
        width: painter.width + 14,
        height: painter.height + 8,
      ),
      const Radius.circular(8),
    );
    canvas.drawRRect(
      bg,
      Paint()
        ..color =
            Colors.white.withValues(alpha: (selected ? 0.97 : 0.78) * alpha),
    );
    if (selected) {
      canvas.drawRRect(
        bg,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..color = scheme.primary,
      );
    }
    painter.paint(
      canvas,
      Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
    );
  }

  Color _shade(Color color, double factor) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness((hsl.lightness * factor).clamp(0.0, 1.0)).toColor();
  }

  @override
  bool shouldRepaint(covariant _Room3DPainter oldDelegate) => true;
}

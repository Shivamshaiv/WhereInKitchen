import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wherein_kitchen/models/room.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';
import 'package:wherein_kitchen/providers/providers.dart';
import 'package:wherein_kitchen/screens/unit/unit_peek_screen.dart';

/// True 3D room view with an orbiting camera.
///
/// - One-finger drag orbits the camera around the room (yaw + pitch), so you
///   can walk around and see the far side of the kitchen.
/// - Pinch zooms the camera in/out.
/// - Tap a unit to select it; the bottom toolbar lets you rotate the unit in
///   place (its doors/shelves face a new direction while its floor footprint
///   stays fixed) or open it to peek inside.
class Room3DScreen extends ConsumerStatefulWidget {
  const Room3DScreen({super.key, required this.room});

  final Room room;

  static const int gridCols = 14;
  static const int gridRows = 14;

  @override
  ConsumerState<Room3DScreen> createState() => _Room3DScreenState();
}

class _Room3DScreenState extends ConsumerState<Room3DScreen> {
  // Camera orbit state.
  static const double _defaultYaw = math.pi / 4; // Classic iso-like corner.
  static const double _defaultPitch = 0.5;
  double _yaw = _defaultYaw;
  double _pitch = _defaultPitch;
  double _distance = 24;
  double _startDistance = 24;

  // Auto-framed look-at point + whether we've framed the current units yet.
  _Vec3 _target = const _Vec3(
    Room3DScreen.gridCols / 2,
    Room3DScreen.gridRows / 2,
    0.9,
  );
  bool _framed = false;

  String? _selectedUnitId;

  List<StorageUnit> _unitsForRoom(List<StorageUnit> all) {
    final units = all.where((u) => u.roomId == widget.room.id).toList();
    units.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return units;
  }

  /// Points the camera at the cabinets and picks a distance that fills the
  /// view, so a couple of units in a big room aren't a tiny far-off diorama.
  void _frameUnits(List<StorageUnit> units, Size size) {
    if (units.isEmpty) {
      _target = const _Vec3(
          Room3DScreen.gridCols / 2, Room3DScreen.gridRows / 2, 0.9);
      _distance = 24;
      return;
    }

    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = -double.infinity,
        maxY = -double.infinity,
        maxZ = -double.infinity;
    for (final u in units) {
      final band = _zBand3D(u);
      minX = math.min(minX, u.gx.toDouble());
      minY = math.min(minY, u.gy.toDouble());
      minZ = math.min(minZ, band.bottom);
      maxX = math.max(maxX, (u.gx + u.gw).toDouble());
      maxY = math.max(maxY, (u.gy + u.gh).toDouble());
      maxZ = math.max(maxZ, band.top);
    }

    _target = _Vec3((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2);

    // Bounding radius of the content, then back off enough to fit it in the
    // camera's ~19° half-angle (focal = min(w,h) * 1.45).
    final radius = _Vec3(maxX - minX, maxY - minY, maxZ - minZ)
            .scale(0.5)
            .length +
        1.5;
    _distance = (radius / 0.32 * 1.15).clamp(9.0, 55.0);
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
        _distance = (_startDistance / details.scale).clamp(8.0, 60.0);
      }
      _yaw -= details.focalPointDelta.dx * 0.008;
      _pitch =
          (_pitch + details.focalPointDelta.dy * 0.006).clamp(0.12, 1.35);
    });
  }

  void _onTapUp(TapUpDetails details, Size size, List<StorageUnit> units) {
    final camera = _camera(size);
    final hit = _hitTest(details.localPosition, camera, units);
    setState(() => _selectedUnitId = hit?.id);
  }

  StorageUnit? _hitTest(
      Offset position, _Camera camera, List<StorageUnit> units) {
    StorageUnit? best;
    var bestDepth = double.infinity;
    for (final unit in units) {
      final box = _UnitBox(unit);
      for (final face in box.faces) {
        final projected = <Offset>[];
        var depth = 0.0;
        var behind = false;
        for (final v in face.corners) {
          final p = camera.project(v);
          if (p == null) {
            behind = true;
            break;
          }
          projected.add(p.offset);
          depth += p.depth;
        }
        if (behind) continue;
        depth /= face.corners.length;
        if (_pointInPolygon(position, projected) && depth < bestDepth) {
          bestDepth = depth;
          best = unit;
        }
      }
    }
    return best;
  }

  bool _pointInPolygon(Offset p, List<Offset> polygon) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[i];
      final b = polygon[j];
      if ((a.dy > p.dy) != (b.dy > p.dy) &&
          p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
        inside = !inside;
      }
    }
    return inside;
  }

  Future<void> _rotateSelected(List<StorageUnit> units, int delta) async {
    final unit =
        units.where((u) => u.id == _selectedUnitId).firstOrNull;
    if (unit == null) return;
    final updated = unit.copyWith(facing: (unit.facing + delta + 4) % 4);
    await ref.read(unitRepositoryProvider).updateUnit(updated);
  }

  void _openSelected(List<StorageUnit> units) {
    final unit =
        units.where((u) => u.id == _selectedUnitId).firstOrNull;
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
        title: Text('${widget.room.name} · 3D'),
        actions: [
          IconButton(
            tooltip: 'Reset camera',
            icon: const Icon(Icons.restart_alt),
            onPressed: () => setState(() {
              _yaw = _defaultYaw;
              _pitch = _defaultPitch;
              _framed = false; // Re-fit to the cabinets on next paint.
            }),
          ),
        ],
      ),
      body: unitsAsync.when(
        data: (allUnits) {
          final units =
              _unitsForRoom(allUnits).where((u) => u.hasLayoutPosition).toList();
          final selected =
              units.where((u) => u.id == _selectedUnitId).firstOrNull;

          return Stack(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final size =
                      Size(constraints.maxWidth, constraints.maxHeight);
                  if (!_framed && size.width.isFinite) {
                    _frameUnits(units, size);
                    _framed = true;
                  }
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: _onScaleStart,
                    onScaleUpdate: _onScaleUpdate,
                    onTapUp: (d) => _onTapUp(d, size, units),
                    child: CustomPaint(
                      size: size,
                      painter: _Room3DPainter(
                        units: units,
                        camera: _camera(size),
                        selectedUnitId: _selectedUnitId,
                        itemCountByUnit: itemCountByUnit,
                        scheme: Theme.of(context).colorScheme,
                      ),
                    ),
                  );
                },
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
                          : 'Rotate keeps its spot — only the facing changes',
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
                    onRotateLeft: () => _rotateSelected(units, 1),
                    onRotateRight: () => _rotateSelected(units, -1),
                    onOpen: () => _openSelected(units),
                    onClose: () =>
                        setState(() => _selectedUnitId = null),
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

/// Bottom toolbar for the selected unit: rotate in place + open.
class _Selected3DToolbar extends StatelessWidget {
  const _Selected3DToolbar({
    required this.unit,
    required this.onRotateLeft,
    required this.onRotateRight,
    required this.onOpen,
    required this.onClose,
  });

  final StorageUnit unit;
  final VoidCallback onRotateLeft;
  final VoidCallback onRotateRight;
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    unit.name,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Deselect',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
                ),
              ],
            ),
            Text(
              '${unit.mount.label} · faces ${facingLabel(unit.facing)}',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton.filledTonal(
                  tooltip: 'Rotate left',
                  icon: const Icon(Icons.rotate_left),
                  onPressed: onRotateLeft,
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Rotate right',
                  icon: const Icon(Icons.rotate_right),
                  onPressed: onRotateRight,
                ),
                const Spacer(),
                if (unit.holdsItems)
                  FilledButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('Open'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3D math
// ---------------------------------------------------------------------------

class _Vec3 {
  const _Vec3(this.x, this.y, this.z);
  final double x, y, z;

  _Vec3 operator -(_Vec3 o) => _Vec3(x - o.x, y - o.y, z - o.z);
  _Vec3 operator +(_Vec3 o) => _Vec3(x + o.x, y + o.y, z + o.z);
  _Vec3 scale(double s) => _Vec3(x * s, y * s, z * s);

  double dot(_Vec3 o) => x * o.x + y * o.y + z * o.z;
  _Vec3 cross(_Vec3 o) =>
      _Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(dot(this));
  _Vec3 get normalized {
    final l = length;
    return l == 0 ? this : _Vec3(x / l, y / l, z / l);
  }
}

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
        _Vec3(
          math.cos(pitch) * math.sin(yaw),
          math.cos(pitch) * math.cos(yaw),
          math.sin(pitch),
        ).scale(distance);
    forward = (target - eye).normalized;
    right = forward.cross(const _Vec3(0, 0, 1)).normalized;
    up = right.cross(forward);
    focal = math.min(viewport.width, viewport.height) * 1.45;
  }

  final _Vec3 target;
  final Size viewport;
  late final _Vec3 eye;
  late final _Vec3 forward;
  late final _Vec3 right;
  late final _Vec3 up;
  late final double focal;

  /// Projects a world point; null when behind the camera.
  _Projected? project(_Vec3 p) {
    final v = p - eye;
    final zc = v.dot(forward);
    if (zc <= 0.1) return null;
    final xc = v.dot(right);
    final yc = v.dot(up);
    return _Projected(
      Offset(
        viewport.width / 2 + focal * xc / zc,
        viewport.height / 2 - focal * yc / zc,
      ),
      zc,
    );
  }
}

// ---------------------------------------------------------------------------
// Unit geometry
// ---------------------------------------------------------------------------

/// Which world direction a face points.
enum _FaceDir { top, bottom, north, south, east, west }

class _Face {
  const _Face(this.corners, this.normal, this.dir);
  final List<_Vec3> corners;
  final _Vec3 normal;
  final _FaceDir dir;
}

/// Vertical band factors — shared with the 2.5D view so both stay consistent.
({double bottom, double top}) _zBand3D(StorageUnit unit) => unitZBand(unit);

class _UnitBox {
  _UnitBox(this.unit) {
    final band = _zBand3D(unit);
    final x0 = unit.gx.toDouble();
    final x1 = (unit.gx + unit.gw).toDouble();
    final y0 = unit.gy.toDouble();
    final y1 = (unit.gy + unit.gh).toDouble();
    final z0 = band.bottom;
    final z1 = band.top;

    faces = [
      _Face(
        [_Vec3(x0, y0, z1), _Vec3(x1, y0, z1), _Vec3(x1, y1, z1), _Vec3(x0, y1, z1)],
        const _Vec3(0, 0, 1),
        _FaceDir.top,
      ),
      _Face(
        [_Vec3(x0, y0, z0), _Vec3(x1, y0, z0), _Vec3(x1, y1, z0), _Vec3(x0, y1, z0)],
        const _Vec3(0, 0, -1),
        _FaceDir.bottom,
      ),
      _Face(
        [_Vec3(x0, y1, z0), _Vec3(x1, y1, z0), _Vec3(x1, y1, z1), _Vec3(x0, y1, z1)],
        const _Vec3(0, 1, 0),
        _FaceDir.south,
      ),
      _Face(
        [_Vec3(x1, y0, z0), _Vec3(x0, y0, z0), _Vec3(x0, y0, z1), _Vec3(x1, y0, z1)],
        const _Vec3(0, -1, 0),
        _FaceDir.north,
      ),
      _Face(
        [_Vec3(x1, y1, z0), _Vec3(x1, y0, z0), _Vec3(x1, y0, z1), _Vec3(x1, y1, z1)],
        const _Vec3(1, 0, 0),
        _FaceDir.east,
      ),
      _Face(
        [_Vec3(x0, y0, z0), _Vec3(x0, y1, z0), _Vec3(x0, y1, z1), _Vec3(x0, y0, z1)],
        const _Vec3(-1, 0, 0),
        _FaceDir.west,
      ),
    ];
  }

  final StorageUnit unit;
  late final List<_Face> faces;

  /// The face the unit's doors/shelves are on, from its [StorageUnit.facing].
  _FaceDir get frontDir => switch (unit.facing % 4) {
        0 => _FaceDir.south, // +y ("front" of the room grid)
        1 => _FaceDir.east,
        2 => _FaceDir.north,
        _ => _FaceDir.west,
      };

  _Vec3 get center => _Vec3(
        unit.gx + unit.gw / 2,
        unit.gy + unit.gh / 2,
        (_zBand3D(unit).bottom + _zBand3D(unit).top) / 2,
      );
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
    required this.camera,
    required this.selectedUnitId,
    required this.itemCountByUnit,
    required this.scheme,
  });

  final List<StorageUnit> units;
  final _Camera camera;
  final String? selectedUnitId;
  final Map<String, int> itemCountByUnit;
  final ColorScheme scheme;

  static const double _wallHeight = 3.4;

  Color _baseColor(StorageUnitType type) {
    final seed = switch (type) {
      StorageUnitType.shelf => const Color(0xFF8D6E63),
      StorageUnitType.drawer => const Color(0xFF78909C),
      StorageUnitType.cabinet => const Color(0xFFA1887F),
      StorageUnitType.fridge => const Color(0xFF90A4AE),
      StorageUnitType.freezer => const Color(0xFF81D4FA),
      StorageUnitType.range => const Color(0xFF546E7A),
      StorageUnitType.sink => const Color(0xFFB0BEC5),
      StorageUnitType.dishwasher => const Color(0xFF9E9E9E),
      StorageUnitType.oven => const Color(0xFF607D8B),
      StorageUnitType.gap => const Color(0xFF6D6D6D),
      StorageUnitType.other => const Color(0xFF9E9E9E),
    };
    return Color.lerp(seed, scheme.surfaceContainerHighest, 0.2)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Sky/room backdrop.
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

    // Collect all visible faces from all units and depth-sort globally.
    final paintFaces = <_PaintFace>[];
    for (final unit in units) {
      if (unit.type == StorageUnitType.gap) continue;
      final box = _UnitBox(unit);
      for (final face in box.faces) {
        if (face.dir == _FaceDir.bottom) continue;
        // Backface culling.
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
        paintFaces.add(_PaintFace(
          unit: unit,
          face: face,
          points: pts,
          depth: depth / face.corners.length,
          isFront: face.dir == box.frontDir,
        ));
      }
    }
    paintFaces.sort((a, b) => b.depth.compareTo(a.depth));

    // Gaps are just floor decals; draw before boxes.
    for (final unit in units.where((u) => u.type == StorageUnitType.gap)) {
      _paintGap(canvas, unit);
    }

    for (final pf in paintFaces) {
      _paintFace(canvas, pf);
    }

    // Labels last so they float above geometry (near units get bigger text).
    final labelOrder = [...units]..sort((a, b) {
        final da = (camera.eye - _UnitBox(a).center).length;
        final db = (camera.eye - _UnitBox(b).center).length;
        return db.compareTo(da);
      });
    for (final unit in labelOrder) {
      _paintLabel(canvas, unit);
    }
  }

  void _paintFloor(Canvas canvas) {
    const cols = Room3DScreen.gridCols;
    const rows = Room3DScreen.gridRows;

    Offset? proj(double x, double y, [double z = 0]) =>
        camera.project(_Vec3(x, y, z))?.offset;

    final c00 = proj(0, 0);
    final c10 = proj(cols.toDouble(), 0);
    final c11 = proj(cols.toDouble(), rows.toDouble());
    final c01 = proj(0, rows.toDouble());
    if (c00 == null || c10 == null || c11 == null || c01 == null) return;

    final floor = Path()..addPolygon([c00, c10, c11, c01], true);
    canvas.drawPath(
      floor,
      Paint()
        ..color =
            Color.lerp(scheme.surfaceContainerHigh, scheme.primary, 0.05)!,
    );

    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = scheme.outlineVariant.withValues(alpha: 0.7);
    for (var x = 0; x <= cols; x++) {
      final a = proj(x.toDouble(), 0);
      final b = proj(x.toDouble(), rows.toDouble());
      if (a != null && b != null) canvas.drawLine(a, b, gridPaint);
    }
    for (var y = 0; y <= rows; y++) {
      final a = proj(0, y.toDouble());
      final b = proj(cols.toDouble(), y.toDouble());
      if (a != null && b != null) canvas.drawLine(a, b, gridPaint);
    }
  }

  /// Draws the two room walls that are on the far side from the camera, so
  /// they frame the room without ever hiding the cabinets.
  void _paintWalls(Canvas canvas) {
    const cols = Room3DScreen.gridCols + 0.0;
    const rows = Room3DScreen.gridRows + 0.0;

    final walls = <({List<_Vec3> corners, _Vec3 normal})>[
      // North wall (y = 0), outward normal -y.
      (
        corners: [
          const _Vec3(0, 0, 0),
          const _Vec3(cols, 0, 0),
          const _Vec3(cols, 0, _wallHeight),
          const _Vec3(0, 0, _wallHeight),
        ],
        normal: const _Vec3(0, -1, 0)
      ),
      // South wall (y = rows), outward normal +y.
      (
        corners: [
          const _Vec3(0, rows, 0),
          const _Vec3(cols, rows, 0),
          const _Vec3(cols, rows, _wallHeight),
          const _Vec3(0, rows, _wallHeight),
        ],
        normal: const _Vec3(0, 1, 0)
      ),
      // West wall (x = 0), outward normal -x.
      (
        corners: [
          const _Vec3(0, 0, 0),
          const _Vec3(0, rows, 0),
          const _Vec3(0, rows, _wallHeight),
          const _Vec3(0, 0, _wallHeight),
        ],
        normal: const _Vec3(-1, 0, 0)
      ),
      // East wall (x = cols), outward normal +x.
      (
        corners: [
          const _Vec3(cols, 0, 0),
          const _Vec3(cols, rows, 0),
          const _Vec3(cols, rows, _wallHeight),
          const _Vec3(cols, 0, _wallHeight),
        ],
        normal: const _Vec3(1, 0, 0)
      ),
    ];

    for (final wall in walls) {
      final center = wall.corners
          .reduce((a, b) => a + b)
          .scale(1 / wall.corners.length);
      // Draw only walls whose outward normal points away from the camera —
      // those are behind the room content.
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
          ..color = Color.lerp(
                  scheme.surfaceContainerHighest, scheme.primary, 0.04)!
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

  void _paintGap(Canvas canvas, StorageUnit unit) {
    final pts = <Offset>[];
    final corners = [
      _Vec3(unit.gx.toDouble(), unit.gy.toDouble(), 0.01),
      _Vec3((unit.gx + unit.gw).toDouble(), unit.gy.toDouble(), 0.01),
      _Vec3((unit.gx + unit.gw).toDouble(), (unit.gy + unit.gh).toDouble(), 0.01),
      _Vec3(unit.gx.toDouble(), (unit.gy + unit.gh).toDouble(), 0.01),
    ];
    for (final v in corners) {
      final p = camera.project(v);
      if (p == null) return;
      pts.add(p.offset);
    }
    final path = Path()..addPolygon(pts, true);
    canvas.drawPath(
      path,
      Paint()..color = scheme.outlineVariant.withValues(alpha: 0.18),
    );
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
    final base = _baseColor(pf.unit.type);

    // Simple directional lighting.
    final light = const _Vec3(0.4, -0.55, 0.73).normalized;
    final lit = (pf.face.normal.dot(light) + 1) / 2; // 0..1
    var color = Color.lerp(
      _shade(base, 0.45),
      Color.lerp(base, Colors.white, 0.25)!,
      lit,
    )!;
    if (selected) color = Color.lerp(color, scheme.primary, 0.3)!;
    // The front (door) face gets a slight warm tint so rotation reads clearly.
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

    if (pf.isFront) {
      _paintFrontDetails(canvas, pf);
    }
    if (pf.face.dir == _FaceDir.top) {
      _paintFacingArrow(canvas, pf.unit);
    }
  }

  /// Shelf ledges + door split, drawn on the face the unit is facing.
  void _paintFrontDetails(Canvas canvas, _PaintFace pf) {
    final unit = pf.unit;
    final pts = pf.points; // 0-1 bottom edge, 2-3 top edge (corner order).
    if (pts.length != 4) return;

    // Corner order for side faces is (b0, b1, t1, t0).
    final b0 = pts[0], b1 = pts[1], t1 = pts[2], t0 = pts[3];

    Offset lerpEdge(Offset a, Offset b, double t) => Offset.lerp(a, b, t)!;
    Offset at(double tx, double tz) {
      final bottom = lerpEdge(b0, b1, tx);
      final top = lerpEdge(t0, t1, tx);
      return Offset.lerp(bottom, top, tz)!;
    }

    final shelfPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..color = Colors.black.withValues(alpha: 0.3);

    if (unit.holdsItems) {
      final rowCount = unit.rows.clamp(1, 8);
      for (var i = 1; i < rowCount; i++) {
        final tz = i / rowCount;
        canvas.drawLine(at(0.06, tz), at(0.94, tz), shelfPaint);
      }
      if (unit.columns > 1) {
        for (var c = 1; c < unit.columns; c++) {
          final tx = c / unit.columns;
          canvas.drawLine(at(tx, 0.04), at(tx, 0.96), shelfPaint);
        }
      }
    }

    // Door handle strip near one edge.
    canvas.drawLine(
      at(0.9, 0.35),
      at(0.9, 0.65),
      Paint()
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = Colors.black.withValues(alpha: 0.4),
    );
  }

  /// Small arrow on the top face pointing where the unit faces.
  void _paintFacingArrow(Canvas canvas, StorageUnit unit) {
    final band = _zBand3D(unit);
    final cx = unit.gx + unit.gw / 2;
    final cy = unit.gy + unit.gh / 2;
    final z = band.top + 0.02;

    final dir = switch (unit.facing % 4) {
      0 => const _Vec3(0, 1, 0),
      1 => const _Vec3(1, 0, 0),
      2 => const _Vec3(0, -1, 0),
      _ => const _Vec3(-1, 0, 0),
    };

    final len = math.min(unit.gw, unit.gh) * 0.3;
    final tipV = _Vec3(cx + dir.x * len, cy + dir.y * len, z);
    final baseV = _Vec3(cx - dir.x * len * 0.5, cy - dir.y * len * 0.5, z);
    // Perpendicular on the floor plane for arrowhead wings.
    final perp = _Vec3(-dir.y, dir.x, 0);
    final w1 = _Vec3(cx + dir.x * len * 0.4 + perp.x * len * 0.35,
        cy + dir.y * len * 0.4 + perp.y * len * 0.35, z);
    final w2 = _Vec3(cx + dir.x * len * 0.4 - perp.x * len * 0.35,
        cy + dir.y * len * 0.4 - perp.y * len * 0.35, z);

    final tip = camera.project(tipV)?.offset;
    final tail = camera.project(baseV)?.offset;
    final wing1 = camera.project(w1)?.offset;
    final wing2 = camera.project(w2)?.offset;
    if (tip == null || tail == null || wing1 == null || wing2 == null) return;

    final paint = Paint()
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = Colors.black.withValues(alpha: 0.45);
    canvas.drawLine(tail, tip, paint);
    canvas.drawLine(tip, wing1, paint);
    canvas.drawLine(tip, wing2, paint);
  }

  void _paintLabel(Canvas canvas, StorageUnit unit) {
    final band = _zBand3D(unit);
    final anchor = camera.project(_Vec3(
      unit.gx + unit.gw / 2,
      unit.gy + unit.gh / 2,
      band.top + 0.15,
    ));
    if (anchor == null) return;

    // Fade labels with distance so far-side text doesn't clutter.
    final alpha = (1.6 - anchor.depth / 30).clamp(0.35, 1.0);
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
        ..color = Colors.white
            .withValues(alpha: (selected ? 0.97 : 0.78) * alpha),
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
    return hsl
        .withLightness((hsl.lightness * factor).clamp(0.0, 1.0))
        .toColor();
  }

  @override
  bool shouldRepaint(covariant _Room3DPainter oldDelegate) => true;
}

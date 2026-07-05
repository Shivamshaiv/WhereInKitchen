import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';
import 'package:wherein_kitchen/widgets/unit_colors.dart';

/// Layout rectangle of a unit on the room grid.
typedef UnitLayout = ({int gx, int gy, int gw, int gh});

/// Vertical band a unit occupies, in "storey" units where 1.0 ≈ one grid
/// cell of height. Both values feed [_IsoGeometry.project]'s z.
typedef ZBand = ({double bottom, double top});

/// Max shelf rows used for canvas headroom (matches editor max).
const int kIsoMaxShelfRows = kMaxShelfRows;

/// Tallest possible top factor (tall/wall units), for canvas headroom.
/// Accounts for a wall unit's raised base plus a tall explicit height.
const double _kMaxTopFactor = 4.6;

/// 2.5D isometric room renderer.
///
/// Units are extruded boxes on an isometric floor. Their vertical band comes
/// from [StorageUnit.mount] (base sits on the floor, wall floats above the
/// counter, tall runs floor-to-ceiling), and shelf count adds height within
/// the band.
class IsoRoomView extends StatefulWidget {
  const IsoRoomView({
    super.key,
    required this.units,
    required this.layoutOf,
    required this.itemCountByUnit,
    required this.editMode,
    required this.gridCols,
    required this.gridRows,
    this.cellSize = defaultCell,
    this.selectedUnitId,
    this.onTapUnit,
    this.onTapEmpty,
    this.onDragStart,
    this.onMoveUnit,
    this.onDragEnd,
  });

  /// Fixed on-screen size of one grid cell.
  static const double defaultCell = 58;

  final List<StorageUnit> units;
  final UnitLayout Function(StorageUnit unit) layoutOf;
  final Map<String, int> itemCountByUnit;
  final bool editMode;
  final int gridCols;
  final int gridRows;
  final double cellSize;
  final String? selectedUnitId;
  final void Function(StorageUnit unit, Offset globalPosition)? onTapUnit;
  final VoidCallback? onTapEmpty;
  final void Function(StorageUnit unit)? onDragStart;

  /// Called while dragging with absolute grid position (gx, gy).
  final void Function(StorageUnit unit, int gx, int gy)? onMoveUnit;
  final void Function(StorageUnit unit)? onDragEnd;

  /// Total pixel size of the drawn room for a given grid + cell size.
  static Size canvasSize(int cols, int rows, {double cell = defaultCell}) {
    final geo = _IsoGeometry(gridCols: cols, gridRows: rows, cell: cell);
    return Size(geo.canvasWidth, geo.canvasHeight);
  }

  @override
  State<IsoRoomView> createState() => _IsoRoomViewState();
}

ZBand _unitZBand(StorageUnit unit) => unitZBand(unit);

class _IsoRoomViewState extends State<IsoRoomView> {
  StorageUnit? _dragging;
  double _grabDx = 0;
  double _grabDy = 0;

  Color _baseColor(StorageUnitType type, ColorScheme scheme) {
    return unitBaseColor(type, scheme);
  }

  @override
  Widget build(BuildContext context) {
    final geometry = _IsoGeometry(
      gridCols: widget.gridCols,
      gridRows: widget.gridRows,
      cell: widget.cellSize,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) => _handleTap(details, geometry),
      onLongPressStart: widget.editMode
          ? (details) {
              final unit = _unitAt(details.localPosition, geometry);
              if (unit == null) return;
              final layout = widget.layoutOf(unit);
              final grid = geometry.unproject(details.localPosition);
              _dragging = unit;
              _grabDx = layout.gx - grid.x;
              _grabDy = layout.gy - grid.y;
              widget.onDragStart?.call(unit);
              widget.onTapUnit?.call(unit, details.globalPosition);
            }
          : null,
      onLongPressMoveUpdate: widget.editMode
          ? (details) {
              final unit = _dragging;
              if (unit == null) return;
              final layout = widget.layoutOf(unit);
              final grid = geometry.unproject(details.localPosition);
              final nx = (grid.x + _grabDx).round();
              final ny = (grid.y + _grabDy).round();
              final clampedGx =
                  nx.clamp(0, widget.gridCols - layout.gw).toInt();
              final clampedGy =
                  ny.clamp(0, widget.gridRows - layout.gh).toInt();
              if (clampedGx != layout.gx || clampedGy != layout.gy) {
                widget.onMoveUnit?.call(unit, clampedGx, clampedGy);
              }
            }
          : null,
      onLongPressEnd: widget.editMode
          ? (_) {
              final unit = _dragging;
              if (unit != null) {
                widget.onDragEnd?.call(unit);
              }
              _dragging = null;
            }
          : null,
      child: CustomPaint(
        size: Size(geometry.canvasWidth, geometry.canvasHeight),
        painter: _IsoRoomPainter(
          units: widget.units,
          layoutOf: widget.layoutOf,
          itemCountByUnit: widget.itemCountByUnit,
          geometry: geometry,
          editMode: widget.editMode,
          selectedUnitId: widget.selectedUnitId,
          scheme: Theme.of(context).colorScheme,
          baseColor: (type) => _baseColor(type, Theme.of(context).colorScheme),
        ),
      ),
    );
  }

  void _handleTap(TapUpDetails details, _IsoGeometry geometry) {
    final unit = _unitAt(details.localPosition, geometry);
    if (unit != null) {
      widget.onTapUnit?.call(unit, details.globalPosition);
    } else {
      widget.onTapEmpty?.call();
    }
  }

  StorageUnit? _unitAt(Offset position, _IsoGeometry geometry) {
    // Prefer topmost / frontmost units.
    final sorted = [...widget.units]..sort((a, b) {
        final la = widget.layoutOf(a);
        final lb = widget.layoutOf(b);
        final fa = la.gx + la.gy + _unitZBand(a).top;
        final fb = lb.gx + lb.gy + _unitZBand(b).top;
        return fb.compareTo(fa);
      });

    for (final unit in sorted) {
      final layout = widget.layoutOf(unit);
      final band = _unitZBand(unit);
      final zTop = geometry.zPx(band.top);
      final zBottom = geometry.zPx(band.bottom);
      final silhouette = geometry.silhouette(layout, zTop, zBottom);
      if (_pointInPolygon(position, silhouette)) return unit;

      final topCenter = geometry.project(
        layout.gx + layout.gw / 2,
        layout.gy + layout.gh / 2,
        zTop,
      );
      final labelRect = Rect.fromCenter(
        center: Offset(topCenter.dx, topCenter.dy - 28),
        width: 150,
        height: 52,
      );
      if (labelRect.contains(position)) return unit;
    }
    return null;
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
}

class _IsoGeometry {
  _IsoGeometry({
    required this.gridCols,
    required this.gridRows,
    required double cell,
  }) {
    halfW = cell;
    halfH = cell * 0.53;
    originX = gridRows * halfW;
  }

  final int gridCols;
  final int gridRows;
  late final double halfW;
  late final double halfH;
  late final double originX;

  /// Convert a storey factor into pixel z.
  double zPx(double factor) => halfH * 2 * factor;

  /// Headroom for tallest unit + floating label.
  double get originY => zPx(_kMaxTopFactor) + halfH * 4;

  double get canvasWidth => (gridCols + gridRows) * halfW;

  double get canvasHeight =>
      originY + (gridCols + gridRows) * halfH + halfH * 3;

  Offset project(double x, double y, [double z = 0]) {
    return Offset(
      originX + (x - y) * halfW,
      originY + (x + y) * halfH - z,
    );
  }

  /// Inverse project screen point onto the floor plane (z = 0).
  ({double x, double y}) unproject(Offset p) {
    final ux = (p.dx - originX) / halfW;
    final uy = (p.dy - originY) / halfH;
    return (x: (ux + uy) / 2, y: (uy - ux) / 2);
  }

  List<Offset> topFace(UnitLayout l, double zTop) => [
        project(l.gx.toDouble(), l.gy.toDouble(), zTop),
        project((l.gx + l.gw).toDouble(), l.gy.toDouble(), zTop),
        project((l.gx + l.gw).toDouble(), (l.gy + l.gh).toDouble(), zTop),
        project(l.gx.toDouble(), (l.gy + l.gh).toDouble(), zTop),
      ];

  List<Offset> rightFace(UnitLayout l, double zTop, double zBottom) => [
        project((l.gx + l.gw).toDouble(), l.gy.toDouble(), zTop),
        project((l.gx + l.gw).toDouble(), (l.gy + l.gh).toDouble(), zTop),
        project((l.gx + l.gw).toDouble(), (l.gy + l.gh).toDouble(), zBottom),
        project((l.gx + l.gw).toDouble(), l.gy.toDouble(), zBottom),
      ];

  List<Offset> frontFace(UnitLayout l, double zTop, double zBottom) => [
        project(l.gx.toDouble(), (l.gy + l.gh).toDouble(), zTop),
        project((l.gx + l.gw).toDouble(), (l.gy + l.gh).toDouble(), zTop),
        project((l.gx + l.gw).toDouble(), (l.gy + l.gh).toDouble(), zBottom),
        project(l.gx.toDouble(), (l.gy + l.gh).toDouble(), zBottom),
      ];

  List<Offset> silhouette(UnitLayout l, double zTop, double zBottom) => [
        project(l.gx.toDouble(), l.gy.toDouble(), zTop),
        project((l.gx + l.gw).toDouble(), l.gy.toDouble(), zTop),
        project((l.gx + l.gw).toDouble(), l.gy.toDouble(), zBottom),
        project((l.gx + l.gw).toDouble(), (l.gy + l.gh).toDouble(), zBottom),
        project(l.gx.toDouble(), (l.gy + l.gh).toDouble(), zBottom),
        project(l.gx.toDouble(), (l.gy + l.gh).toDouble(), zTop),
      ];
}

class _IsoRoomPainter extends CustomPainter {
  _IsoRoomPainter({
    required this.units,
    required this.layoutOf,
    required this.itemCountByUnit,
    required this.geometry,
    required this.editMode,
    required this.selectedUnitId,
    required this.scheme,
    required this.baseColor,
  });

  final List<StorageUnit> units;
  final UnitLayout Function(StorageUnit unit) layoutOf;
  final Map<String, int> itemCountByUnit;
  final _IsoGeometry geometry;
  final bool editMode;
  final String? selectedUnitId;
  final ColorScheme scheme;
  final Color Function(StorageUnitType) baseColor;

  @override
  void paint(Canvas canvas, Size size) {
    _paintFloor(canvas);
    if (editMode) _paintGrid(canvas);

    // Painter's algorithm: draw back-to-front, then lower band before upper
    // so wall cabinets sit visually above base cabinets.
    final sorted = [...units]..sort((a, b) {
        final la = layoutOf(a);
        final lb = layoutOf(b);
        final depthA = la.gx + la.gy;
        final depthB = lb.gx + lb.gy;
        if (depthA != depthB) return depthA.compareTo(depthB);
        return _unitZBand(a).bottom.compareTo(_unitZBand(b).bottom);
      });

    for (final unit in sorted) {
      _paintUnit(canvas, unit);
    }
  }

  void _paintFloor(Canvas canvas) {
    final floor = Path()
      ..addPolygon([
        geometry.project(0, 0),
        geometry.project(geometry.gridCols.toDouble(), 0),
        geometry.project(
            geometry.gridCols.toDouble(), geometry.gridRows.toDouble()),
        geometry.project(0, geometry.gridRows.toDouble()),
      ], true);

    canvas.drawPath(
      floor,
      Paint()
        ..color =
            Color.lerp(scheme.surfaceContainerLow, scheme.primary, 0.04)!,
    );
    canvas.drawPath(
      floor,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = scheme.outlineVariant.withValues(alpha: 0.6),
    );
  }

  void _paintGrid(Canvas canvas) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = scheme.outlineVariant.withValues(alpha: 0.35);

    for (var x = 1; x < geometry.gridCols; x++) {
      canvas.drawLine(
        geometry.project(x.toDouble(), 0),
        geometry.project(x.toDouble(), geometry.gridRows.toDouble()),
        paint,
      );
    }
    for (var y = 1; y < geometry.gridRows; y++) {
      canvas.drawLine(
        geometry.project(0, y.toDouble()),
        geometry.project(geometry.gridCols.toDouble(), y.toDouble()),
        paint,
      );
    }
  }

  void _paintUnit(Canvas canvas, StorageUnit unit) {
    final layout = layoutOf(unit);

    if (unit.type == StorageUnitType.gap) {
      _paintGap(canvas, unit, layout);
      return;
    }

    final selected = unit.id == selectedUnitId;
    final band = _unitZBand(unit);
    final zTop = geometry.zPx(band.top);
    final zBottom = geometry.zPx(band.bottom);

    final base = baseColor(unit.type);
    final top = selected
        ? Color.lerp(base, scheme.primary, 0.45)!
        : Color.lerp(base, Colors.white, 0.18)!;
    final right = _shade(
        selected ? Color.lerp(base, scheme.primary, 0.35)! : base, 0.75);
    final front = _shade(
        selected ? Color.lerp(base, scheme.primary, 0.35)! : base, 0.55);

    // Contact shadow at the band's bottom.
    final shadowPath = Path()
      ..addPolygon(
        geometry
            .topFace(layout, zBottom)
            .map((p) => p.translate(4, 3))
            .toList(),
        true,
      );
    canvas.drawPath(
      shadowPath,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.24)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    void face(List<Offset> pts, Color color) {
      final path = Path()..addPolygon(pts, true);
      canvas.drawPath(path, Paint()..color = color);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2.2 : 1
          ..color = selected
              ? scheme.primary
              : Colors.black.withValues(alpha: 0.35),
      );
    }

    face(geometry.rightFace(layout, zTop, zBottom), right);
    face(geometry.frontFace(layout, zTop, zBottom), front);
    face(geometry.topFace(layout, zTop), top);

    if (unit.holdsItems) {
      _paintSubShelves(canvas, unit, layout, zTop, zBottom);
    }
    _paintTypeDetails(canvas, unit, layout, zTop, zBottom);
    _paintFacingArrow(canvas, unit, layout, zTop);
    _paintLabel(canvas, unit, layout, zTop);
  }

  /// Open space: a translucent floor rectangle with a dashed edge + label.
  void _paintGap(Canvas canvas, StorageUnit unit, UnitLayout layout) {
    final poly = geometry.topFace(layout, 0);
    final path = Path()..addPolygon(poly, true);
    canvas.drawPath(
      path,
      Paint()..color = scheme.outlineVariant.withValues(alpha: 0.14),
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
    _paintLabel(canvas, unit, layout, geometry.zPx(0.05));
  }

  /// Horizontal shelf ledges for each row (sub-shelves) within the band.
  void _paintSubShelves(
    Canvas canvas,
    StorageUnit unit,
    UnitLayout layout,
    double zTop,
    double zBottom,
  ) {
    final rowCount = unit.rows.clamp(1, kIsoMaxShelfRows);
    final shelfPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.black.withValues(alpha: 0.32);
    final ledgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Colors.white.withValues(alpha: 0.32);

    // Shelves are drawn on the face the unit's doors point at. In this iso
    // projection only the front (+y, facing 0) and right (+x, facing 1)
    // faces are visible; for back/left facings we fall back to the front so
    // the interior is still readable, and the facing arrow tells the truth.
    final onRightFace = unit.facing % 4 == 1;

    Offset lerpFront(double t, double z) {
      if (onRightFace) {
        final a = geometry.project(
            (layout.gx + layout.gw).toDouble(), layout.gy.toDouble(), z);
        final b = geometry.project((layout.gx + layout.gw).toDouble(),
            (layout.gy + layout.gh).toDouble(), z);
        return Offset.lerp(a, b, t)!;
      }
      final a = geometry.project(
          layout.gx.toDouble(), (layout.gy + layout.gh).toDouble(), z);
      final b = geometry.project((layout.gx + layout.gw).toDouble(),
          (layout.gy + layout.gh).toDouble(), z);
      return Offset.lerp(a, b, t)!;
    }

    for (var i = 1; i < rowCount; i++) {
      final z = zBottom + (zTop - zBottom) * (i / rowCount);
      final left = lerpFront(0.05, z);
      final right = lerpFront(0.95, z);
      canvas.drawLine(left, right, shelfPaint);
      canvas.drawLine(left, right, ledgePaint);
    }

    // Vertical bay dividers (columns).
    if (unit.columns > 1) {
      for (var c = 1; c < unit.columns; c++) {
        final t = c / unit.columns;
        canvas.drawLine(
          lerpFront(t, zBottom),
          lerpFront(t, zTop),
          shelfPaint,
        );
      }
    }
  }

  void _paintTypeDetails(
    Canvas canvas,
    StorageUnit unit,
    UnitLayout layout,
    double zTop,
    double zBottom,
  ) {
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.black.withValues(alpha: 0.25);

    // Draw hardware on the same visible face as the shelves: the right (+x)
    // face for facing==1, otherwise the front (+y) face. Without this, a
    // right-facing unit shows its handle/door split on a different face than
    // its shelves.
    final onRightFace = unit.facing % 4 == 1;
    Offset lerpFront(double t, double z) {
      if (onRightFace) {
        final a = geometry.project(
            (layout.gx + layout.gw).toDouble(), layout.gy.toDouble(), z);
        final b = geometry.project((layout.gx + layout.gw).toDouble(),
            (layout.gy + layout.gh).toDouble(), z);
        return Offset.lerp(a, b, t)!;
      }
      final a = geometry.project(
          layout.gx.toDouble(), (layout.gy + layout.gh).toDouble(), z);
      final b = geometry.project((layout.gx + layout.gw).toDouble(),
          (layout.gy + layout.gh).toDouble(), z);
      return Offset.lerp(a, b, t)!;
    }

    Offset lerpTop(double tx, double ty) {
      final front = Offset.lerp(
        geometry.project(layout.gx.toDouble(), layout.gy.toDouble(), zTop),
        geometry.project(
            (layout.gx + layout.gw).toDouble(), layout.gy.toDouble(), zTop),
        tx,
      )!;
      final back = Offset.lerp(
        geometry.project(
            layout.gx.toDouble(), (layout.gy + layout.gh).toDouble(), zTop),
        geometry.project((layout.gx + layout.gw).toDouble(),
            (layout.gy + layout.gh).toDouble(), zTop),
        tx,
      )!;
      return Offset.lerp(front, back, ty)!;
    }

    switch (unit.type) {
      case StorageUnitType.cabinet:
        canvas.drawLine(lerpFront(0.5, zBottom + (zTop - zBottom) * 0.06),
            lerpFront(0.5, zBottom + (zTop - zBottom) * 0.94), linePaint);
      case StorageUnitType.fridge:
      case StorageUnitType.freezer:
        final mid = zBottom + (zTop - zBottom) * 0.62;
        canvas.drawLine(lerpFront(0.06, mid), lerpFront(0.94, mid), linePaint);
        canvas.drawLine(
            lerpFront(0.16, mid + (zTop - mid) * 0.12),
            lerpFront(0.16, mid + (zTop - mid) * 0.7),
            linePaint..strokeWidth = 2.4);
      case StorageUnitType.dishwasher:
      case StorageUnitType.oven:
        final hz = zBottom + (zTop - zBottom) * 0.82;
        canvas.drawLine(lerpFront(0.15, hz), lerpFront(0.85, hz),
            linePaint..strokeWidth = 2.2);
      case StorageUnitType.range:
        // Four burners on the cooktop surface.
        final burner = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.black.withValues(alpha: 0.4);
        for (final tx in [0.3, 0.7]) {
          for (final ty in [0.3, 0.7]) {
            canvas.drawCircle(lerpTop(tx, ty), geometry.halfW * 0.16, burner);
          }
        }
      case StorageUnitType.sink:
        // A basin outline on the surface + faucet dot.
        final basin = <Offset>[
          lerpTop(0.2, 0.25),
          lerpTop(0.8, 0.25),
          lerpTop(0.8, 0.75),
          lerpTop(0.2, 0.75),
        ];
        canvas.drawPath(
          Path()..addPolygon(basin, true),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.black.withValues(alpha: 0.4),
        );
        canvas.drawCircle(
          lerpTop(0.5, 0.12),
          geometry.halfW * 0.07,
          Paint()..color = Colors.black.withValues(alpha: 0.4),
        );
      case StorageUnitType.drawer:
      case StorageUnitType.shelf:
      case StorageUnitType.gap:
      case StorageUnitType.other:
        break;
    }
  }

  /// Small arrow on the top face showing which way the unit faces.
  void _paintFacingArrow(
      Canvas canvas, StorageUnit unit, UnitLayout layout, double zTop) {
    if (unit.facing % 4 == 0) return; // Default facing needs no marker.

    final cx = layout.gx + layout.gw / 2;
    final cy = layout.gy + layout.gh / 2;
    final (dx, dy) = switch (unit.facing % 4) {
      1 => (1.0, 0.0),
      2 => (0.0, -1.0),
      _ => (-1.0, 0.0),
    };
    final len = math.min(layout.gw, layout.gh) * 0.3;

    final tail = geometry.project(cx - dx * len * 0.5, cy - dy * len * 0.5, zTop);
    final tip = geometry.project(cx + dx * len, cy + dy * len, zTop);
    final wing1 = geometry.project(
        cx + dx * len * 0.4 - dy * len * 0.3, cy + dy * len * 0.4 + dx * len * 0.3, zTop);
    final wing2 = geometry.project(
        cx + dx * len * 0.4 + dy * len * 0.3, cy + dy * len * 0.4 - dx * len * 0.3, zTop);

    final paint = Paint()
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = Colors.black.withValues(alpha: 0.5);
    canvas.drawLine(tail, tip, paint);
    canvas.drawLine(tip, wing1, paint);
    canvas.drawLine(tip, wing2, paint);
  }

  void _paintLabel(
      Canvas canvas, StorageUnit unit, UnitLayout layout, double zTop) {
    final topCenter = geometry.project(
      layout.gx + layout.gw / 2,
      layout.gy + layout.gh / 2,
      zTop,
    );

    final count = itemCountByUnit[unit.id] ?? 0;
    final selected = unit.id == selectedUnitId;

    final namePainter = TextPainter(
      text: TextSpan(
        text: unit.name,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: Colors.black.withValues(alpha: 0.88),
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 150);

    final String subLine;
    if (!unit.holdsItems) {
      subLine = unit.type.label;
    } else {
      final shelfLine = '${unit.rows} shelf${unit.rows == 1 ? '' : 's'}';
      subLine = count == 0 ? shelfLine : '$shelfLine · $count items';
    }
    final countPainter = TextPainter(
      text: TextSpan(
        text: '${unit.mount.label} · $subLine',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: Colors.black.withValues(alpha: 0.55),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final totalH = namePainter.height + countPainter.height;
    final bubbleW = math.max(namePainter.width, countPainter.width) + 18;
    final bubbleH = totalH + 12;
    final bubbleCenter = Offset(topCenter.dx, topCenter.dy - bubbleH / 2 - 10);

    canvas.drawLine(
      Offset(topCenter.dx, bubbleCenter.dy + bubbleH / 2),
      topCenter,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.65)
        ..strokeWidth = 1.6,
    );

    final bg = RRect.fromRectAndRadius(
      Rect.fromCenter(center: bubbleCenter, width: bubbleW, height: bubbleH),
      const Radius.circular(9),
    );
    canvas.drawRRect(
      bg,
      Paint()..color = Colors.white.withValues(alpha: selected ? 0.97 : 0.9),
    );
    if (selected) {
      canvas.drawRRect(
        bg,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = scheme.primary,
      );
    }

    namePainter.paint(
      canvas,
      Offset(bubbleCenter.dx - namePainter.width / 2,
          bubbleCenter.dy - totalH / 2),
    );
    countPainter.paint(
      canvas,
      Offset(bubbleCenter.dx - countPainter.width / 2,
          bubbleCenter.dy - totalH / 2 + namePainter.height),
    );
  }

  Color _shade(Color color, double factor) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness * factor).clamp(0.0, 1.0))
        .toColor();
  }

  @override
  bool shouldRepaint(covariant _IsoRoomPainter oldDelegate) => true;
}

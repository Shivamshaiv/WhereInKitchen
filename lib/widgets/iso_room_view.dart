import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';

/// Layout rectangle of a unit on the room grid.
typedef UnitLayout = ({int gx, int gy, int gw, int gh});

/// 2.5D isometric room renderer.
///
/// Units are drawn as extruded boxes on an isometric floor. Heights vary by
/// unit type (fridge tall, drawer low) so the room reads like a miniature
/// kitchen instead of a flat plan.
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
    this.onDragUnit,
    this.onDragEnd,
  });

  /// Fixed on-screen size of one grid cell. The whole canvas grows with the
  /// grid so large/complex rooms overflow the viewport and are pan/zoomable.
  static const double defaultCell = 54;

  final List<StorageUnit> units;
  final UnitLayout Function(StorageUnit unit) layoutOf;
  final Map<String, int> itemCountByUnit;
  final bool editMode;
  final int gridCols;
  final int gridRows;
  final double cellSize;
  final String? selectedUnitId;
  final void Function(StorageUnit unit)? onTapUnit;
  final VoidCallback? onTapEmpty;

  /// Called continuously while dragging with grid-cell deltas.
  final void Function(StorageUnit unit, int dgx, int dgy)? onDragUnit;
  final void Function(StorageUnit unit)? onDragEnd;

  /// Total pixel size of the drawn room for a given grid + cell size.
  static Size canvasSize(int cols, int rows, {double cell = defaultCell}) {
    final halfH = cell * 0.53;
    final width = (cols + rows) * cell;
    final height = halfH * 2 * 3.6 + (cols + rows) * halfH + halfH * 5;
    return Size(width, height);
  }

  @override
  State<IsoRoomView> createState() => _IsoRoomViewState();
}

class _IsoRoomViewState extends State<IsoRoomView> {
  StorageUnit? _dragging;
  Offset _lastDragOffset = Offset.zero;

  double _heightFactor(StorageUnitType type) => switch (type) {
        StorageUnitType.fridge => 2.6,
        StorageUnitType.freezer => 2.4,
        StorageUnitType.cabinet => 1.9,
        StorageUnitType.shelf => 1.6,
        StorageUnitType.other => 1.2,
        StorageUnitType.drawer => 0.8,
      };

  Color _baseColor(StorageUnitType type, ColorScheme scheme) {
    final seed = switch (type) {
      StorageUnitType.shelf => const Color(0xFF8D6E63),
      StorageUnitType.drawer => const Color(0xFF78909C),
      StorageUnitType.cabinet => const Color(0xFFA1887F),
      StorageUnitType.fridge => const Color(0xFF90A4AE),
      StorageUnitType.freezer => const Color(0xFF81D4FA),
      StorageUnitType.other => const Color(0xFF9E9E9E),
    };
    return Color.lerp(seed, scheme.surfaceContainerHighest, 0.25)!;
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
      onTapUp: (details) => _handleTap(details.localPosition, geometry),
      // Long-press-drag moves a unit. Using long-press (not pan) leaves the
      // one-finger pan and pinch-zoom of the surrounding InteractiveViewer
      // free, so a big room stays fully navigable in edit mode.
      onLongPressStart: widget.editMode
          ? (details) {
              _dragging = _unitAt(details.localPosition, geometry);
              _lastDragOffset = Offset.zero;
              if (_dragging != null) {
                widget.onTapUnit?.call(_dragging!);
              }
            }
          : null,
      onLongPressMoveUpdate: widget.editMode
          ? (details) {
              final unit = _dragging;
              if (unit == null) return;
              final delta = details.localOffsetFromOrigin - _lastDragOffset;
              // Convert screen delta to grid delta (inverse iso basis).
              final dgx =
                  (delta.dx / geometry.halfW + delta.dy / geometry.halfH) / 2;
              final dgy =
                  (delta.dy / geometry.halfH - delta.dx / geometry.halfW) / 2;
              final stepX = dgx.round();
              final stepY = dgy.round();
              if (stepX != 0 || stepY != 0) {
                _lastDragOffset = details.localOffsetFromOrigin;
                widget.onDragUnit?.call(unit, stepX, stepY);
              }
            }
          : null,
      onLongPressEnd: widget.editMode
          ? (_) {
              if (_dragging != null) {
                widget.onDragEnd?.call(_dragging!);
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
          textTheme: Theme.of(context).textTheme,
          heightFactor: _heightFactor,
          baseColor: (type) => _baseColor(type, Theme.of(context).colorScheme),
        ),
      ),
    );
  }

  void _handleTap(Offset position, _IsoGeometry geometry) {
    final unit = _unitAt(position, geometry);
    if (unit != null) {
      widget.onTapUnit?.call(unit);
    } else {
      widget.onTapEmpty?.call();
    }
  }

  StorageUnit? _unitAt(Offset position, _IsoGeometry geometry) {
    // Front-most units first (reverse paint order).
    final sorted = [...widget.units]..sort((a, b) {
        final la = widget.layoutOf(a);
        final lb = widget.layoutOf(b);
        return (lb.gx + lb.gy + lb.gw + lb.gh)
            .compareTo(la.gx + la.gy + la.gw + la.gh);
      });

    for (final unit in sorted) {
      final layout = widget.layoutOf(unit);
      final h = geometry.halfH * 2 * _heightFactor(unit.type);
      final silhouette = geometry.silhouette(layout, h);
      if (_pointInPolygon(position, silhouette)) return unit;

      // Also accept taps on the floating label bubble above the box.
      final topCenter = geometry.project(
        layout.gx + layout.gw / 2,
        layout.gy + layout.gh / 2,
        h,
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
    // Fixed cell size: the canvas grows with the grid rather than being
    // squeezed to fit the screen, so complex layouts stay big and legible.
    halfW = cell;
    halfH = cell * 0.53;
    originX = gridRows * halfW; // left edge of floor sits at x = 0
    originY = halfH * 2 * 3.6; // headroom for tall units + labels
  }

  final int gridCols;
  final int gridRows;
  late final double halfW;
  late final double halfH;
  late final double originX;
  late final double originY;

  double get canvasWidth => (gridCols + gridRows) * halfW;

  double get canvasHeight =>
      originY + (gridCols + gridRows) * halfH + halfH * 5;

  Offset project(double x, double y, [double z = 0]) {
    return Offset(
      originX + (x - y) * halfW,
      originY + (x + y) * halfH - z,
    );
  }

  List<Offset> topFace(UnitLayout l, double h) => [
        project(l.gx.toDouble(), l.gy.toDouble(), h),
        project((l.gx + l.gw).toDouble(), l.gy.toDouble(), h),
        project((l.gx + l.gw).toDouble(), (l.gy + l.gh).toDouble(), h),
        project(l.gx.toDouble(), (l.gy + l.gh).toDouble(), h),
      ];

  List<Offset> rightFace(UnitLayout l, double h) => [
        project((l.gx + l.gw).toDouble(), l.gy.toDouble(), h),
        project((l.gx + l.gw).toDouble(), (l.gy + l.gh).toDouble(), h),
        project((l.gx + l.gw).toDouble(), (l.gy + l.gh).toDouble(), 0),
        project((l.gx + l.gw).toDouble(), l.gy.toDouble(), 0),
      ];

  List<Offset> frontFace(UnitLayout l, double h) => [
        project(l.gx.toDouble(), (l.gy + l.gh).toDouble(), h),
        project((l.gx + l.gw).toDouble(), (l.gy + l.gh).toDouble(), h),
        project((l.gx + l.gw).toDouble(), (l.gy + l.gh).toDouble(), 0),
        project(l.gx.toDouble(), (l.gy + l.gh).toDouble(), 0),
      ];

  /// Full outline used for hit-testing (top + both visible faces).
  List<Offset> silhouette(UnitLayout l, double h) => [
        project(l.gx.toDouble(), l.gy.toDouble(), h),
        project((l.gx + l.gw).toDouble(), l.gy.toDouble(), h),
        project((l.gx + l.gw).toDouble(), l.gy.toDouble(), 0),
        project((l.gx + l.gw).toDouble(), (l.gy + l.gh).toDouble(), 0),
        project(l.gx.toDouble(), (l.gy + l.gh).toDouble(), 0),
        project(l.gx.toDouble(), (l.gy + l.gh).toDouble(), h),
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
    required this.textTheme,
    required this.heightFactor,
    required this.baseColor,
  });

  final List<StorageUnit> units;
  final UnitLayout Function(StorageUnit unit) layoutOf;
  final Map<String, int> itemCountByUnit;
  final _IsoGeometry geometry;
  final bool editMode;
  final String? selectedUnitId;
  final ColorScheme scheme;
  final TextTheme textTheme;
  final double Function(StorageUnitType) heightFactor;
  final Color Function(StorageUnitType) baseColor;

  @override
  void paint(Canvas canvas, Size size) {
    _paintFloor(canvas);
    if (editMode) _paintGrid(canvas);

    // Back-to-front paint order.
    final sorted = [...units]..sort((a, b) {
        final la = layoutOf(a);
        final lb = layoutOf(b);
        return (la.gx + la.gy + la.gw + la.gh)
            .compareTo(lb.gx + lb.gy + lb.gw + lb.gh);
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
        ..color = Color.lerp(
            scheme.surfaceContainerLow, scheme.primary, 0.04)!,
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
      ..color = scheme.outlineVariant.withValues(alpha: 0.4);

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
    final selected = unit.id == selectedUnitId;
    final h = geometry.halfH * 2 * heightFactor(unit.type);

    final base = baseColor(unit.type);
    final top = selected
        ? Color.lerp(base, scheme.primary, 0.45)!
        : Color.lerp(base, Colors.white, 0.18)!;
    final right = _shade(selected
        ? Color.lerp(base, scheme.primary, 0.35)!
        : base, 0.75);
    final front = _shade(selected
        ? Color.lerp(base, scheme.primary, 0.35)!
        : base, 0.55);

    // Drop shadow on floor.
    final shadowPath = Path()
      ..addPolygon(
        geometry
            .topFace(layout, 0)
            .map((p) => p.translate(4, 3))
            .toList(),
        true,
      );
    canvas.drawPath(
      shadowPath,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.28)
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

    face(geometry.rightFace(layout, h), right);
    face(geometry.frontFace(layout, h), front);
    face(geometry.topFace(layout, h), top);

    _paintFaceDetails(canvas, unit, layout, h, front);
    _paintLabel(canvas, unit, layout, h);
  }

  /// Simple front-face detailing: drawer lines, cabinet doors, fridge handle.
  void _paintFaceDetails(
    Canvas canvas,
    StorageUnit unit,
    UnitLayout layout,
    double h,
    Color front,
  ) {
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.black.withValues(alpha: 0.25);

    Offset lerpFront(double t, double zFrac) {
      final a = geometry.project(
          layout.gx.toDouble(), (layout.gy + layout.gh).toDouble(), h * zFrac);
      final b = geometry.project((layout.gx + layout.gw).toDouble(),
          (layout.gy + layout.gh).toDouble(), h * zFrac);
      return Offset.lerp(a, b, t)!;
    }

    switch (unit.type) {
      case StorageUnitType.drawer:
      case StorageUnitType.shelf:
        final rowCount = math.min(unit.rows, 4);
        for (var i = 1; i < rowCount; i++) {
          final zFrac = i / rowCount;
          canvas.drawLine(lerpFront(0.06, zFrac), lerpFront(0.94, zFrac),
              linePaint);
        }
      case StorageUnitType.cabinet:
        canvas.drawLine(lerpFront(0.5, 0.06), lerpFront(0.5, 0.94), linePaint);
      case StorageUnitType.fridge:
      case StorageUnitType.freezer:
        canvas.drawLine(lerpFront(0.06, 0.62), lerpFront(0.94, 0.62),
            linePaint);
        canvas.drawLine(lerpFront(0.16, 0.7), lerpFront(0.16, 0.9),
            linePaint..strokeWidth = 2.4);
      case StorageUnitType.other:
        break;
    }
  }

  void _paintLabel(
      Canvas canvas, StorageUnit unit, UnitLayout layout, double h) {
    // Anchor above the top face so the box itself stays visible.
    final topCenter = geometry.project(
      layout.gx + layout.gw / 2,
      layout.gy + layout.gh / 2,
      h,
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

    final countPainter = TextPainter(
      text: TextSpan(
        text: count == 0 ? 'empty' : '$count item${count == 1 ? '' : 's'}',
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

    // Pointer line from bubble to box top.
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

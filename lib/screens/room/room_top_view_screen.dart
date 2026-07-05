import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:wherein_kitchen/models/elevation.dart';
import 'package:wherein_kitchen/models/measure.dart';
import 'package:wherein_kitchen/models/room.dart';
import 'package:wherein_kitchen/providers/providers.dart';
import 'package:wherein_kitchen/screens/room/room_3d_screen.dart';
import 'package:wherein_kitchen/screens/room/wall_elevation_screen.dart';

/// Top-down hub for the wall-elevation designer: set room size, place islands,
/// and tap a wall (or island face) to design its 2D front elevation. The 3D
/// view assembles everything.
class RoomTopViewScreen extends ConsumerStatefulWidget {
  const RoomTopViewScreen({super.key, required this.room});

  final Room room;

  @override
  ConsumerState<RoomTopViewScreen> createState() => _RoomTopViewScreenState();
}

class _RoomTopViewScreenState extends ConsumerState<RoomTopViewScreen> {
  bool _migrated = false;
  String? _selectedIslandId;

  // Optimistic island position during a drag.
  final Map<String, ({double xCm, double yCm})> _islandDrag = {};
  String? _draggingIslandId;
  Offset _grabCm = Offset.zero;

  // Canvas mapping (set in build).
  double _scale = 1;
  Offset _origin = Offset.zero;

  // Selects this screen's room from a rooms snapshot, falling back to the
  // Room passed in at construction time.
  Room _roomFrom(List<Room>? rooms) {
    if (rooms == null) return widget.room;
    for (final r in rooms) {
      if (r.id == widget.room.id) return r;
    }
    return widget.room;
  }

  // Read-only current room for use inside callbacks (never inside build, where
  // ref.watch must be used instead so resizes/edits re-render live).
  Room _liveRoom() => _roomFrom(ref.read(roomsProvider).value);

  ({double xCm, double yCm}) _islandPos(Island i) =>
      _islandDrag[i.id] ?? (xCm: i.xCm, yCm: i.yCm);

  (double, double) _islandExtent(Island i) => i.rotationQuarters.isOdd
      ? (i.depthCm, i.widthCm)
      : (i.widthCm, i.depthCm);

  Rect _islandRectCm(Island i) {
    final p = _islandPos(i);
    final (w, d) = _islandExtent(i);
    return Rect.fromLTWH(p.xCm, p.yCm, w, d);
  }

  Offset _toCm(Offset px) => (px - _origin) / _scale;

  double _wallBandCm(Room room) =>
      (math.min(room.widthCm, room.lengthCm) * 0.16).clamp(24.0, 70.0);

  // ---- gestures ------------------------------------------------------------

  void _onTapUp(TapUpDetails d, Room room) {
    final p = _toCm(d.localPosition);

    // Island first.
    for (final i in room.islands) {
      if (_islandRectCm(i).contains(p)) {
        setState(() => _selectedIslandId = i.id);
        return;
      }
    }

    // Wall band?
    final band = _wallBandCm(room);
    final dN = p.dy, dS = room.lengthCm - p.dy;
    final dW = p.dx, dE = room.widthCm - p.dx;
    final inside = p.dx >= 0 &&
        p.dx <= room.widthCm &&
        p.dy >= 0 &&
        p.dy <= room.lengthCm;
    if (inside) {
      final nearest = [dN, dS, dW, dE].reduce(math.min);
      if (nearest <= band) {
        WallSide side;
        if (nearest == dN) {
          side = WallSide.north;
        } else if (nearest == dS) {
          side = WallSide.south;
        } else if (nearest == dW) {
          side = WallSide.west;
        } else {
          side = WallSide.east;
        }
        _openSurface(wallSurfaceId(side));
        return;
      }
    }
    setState(() => _selectedIslandId = null);
  }

  void _onPanStart(DragStartDetails d, Room room) {
    final p = _toCm(d.localPosition);
    for (final i in room.islands) {
      if (_islandRectCm(i).contains(p)) {
        setState(() {
          _selectedIslandId = i.id;
          _draggingIslandId = i.id;
          _grabCm = p - _islandRectCm(i).topLeft;
        });
        return;
      }
    }
    _draggingIslandId = null;
  }

  void _onPanUpdate(DragUpdateDetails d, Room room) {
    final id = _draggingIslandId;
    if (id == null) return;
    final island = room.islands.where((i) => i.id == id).firstOrNull;
    if (island == null) return;
    final (w, dp) = _islandExtent(island);
    final p = _toCm(d.localPosition) - _grabCm;
    final x = p.dx.clamp(0.0, math.max(0.0, room.widthCm - w)).toDouble();
    final y = p.dy.clamp(0.0, math.max(0.0, room.lengthCm - dp)).toDouble();
    setState(() => _islandDrag[id] = (xCm: x, yCm: y));
  }

  Future<void> _onPanEnd(DragEndDetails d, Room room) async {
    final id = _draggingIslandId;
    setState(() => _draggingIslandId = null);
    if (id == null) return;
    final pos = _islandDrag[id];
    if (pos == null) return;
    final updated = room.islands
        .map((i) => i.id == id ? i.copyWith(xCm: pos.xCm, yCm: pos.yCm) : i)
        .toList();
    await _saveIslands(updated);
    // Drop the optimistic entry so the stored/live position becomes
    // authoritative (otherwise it masks the saved value forever).
    if (mounted) setState(() => _islandDrag.remove(id));
  }

  // ---- actions -------------------------------------------------------------

  void _openSurface(String surfaceId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WallElevationScreen(room: _liveRoom(), surfaceId: surfaceId),
      ),
    );
  }

  Future<void> _saveIslands(List<Island> islands) async {
    final hh = ref.read(householdIdProvider);
    if (hh == null) return;
    await ref
        .read(roomRepositoryProvider)
        .updateIslands(hh, widget.room.id, islands);
  }

  Future<void> _addIsland(Room room) async {
    final id = const Uuid().v4();
    final island = Island(
      id: id,
      xCm: (room.widthCm / 2 - 60).clamp(0.0, room.widthCm),
      yCm: (room.lengthCm / 2 - 45).clamp(0.0, room.lengthCm),
      widthCm: 120,
      depthCm: 90,
    );
    await _saveIslands([...room.islands, island]);
    if (mounted) setState(() => _selectedIslandId = id);
  }

  Future<void> _deleteIsland(Room room, String id) async {
    final hh = ref.read(householdIdProvider);
    if (hh == null) return;
    final all = ref.read(unitsProvider).value ?? [];
    final faceUnits = all
        .where((u) =>
            u.surfaceId != null && u.surfaceId!.startsWith('island:$id:'))
        .toList();

    if (faceUnits.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Delete island?'),
          content: Text(
              'This island holds ${faceUnits.length} unit(s). Deleting it also '
              'removes them and their items.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(dialogContext).colorScheme.error),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    // Remove the units on the island's faces first, so they don't linger as
    // phantoms (their surfaceId would otherwise point at a deleted island and
    // fall back to the legacy grid position in the 3D view).
    final unitRepo = ref.read(unitRepositoryProvider);
    for (final u in faceUnits) {
      await unitRepo.deleteUnitCascade(hh, u.id);
    }
    await _saveIslands(room.islands.where((i) => i.id != id).toList());
    if (mounted) setState(() => _selectedIslandId = null);
  }

  Future<void> _rotateIsland(Room room, String id) async {
    final updated = room.islands.map((i) {
      if (i.id != id) return i;
      final p = _islandPos(i);
      return i.copyWith(
        rotationQuarters: (i.rotationQuarters + 1) % 4,
        xCm: p.xCm,
        yCm: p.yCm,
      );
    }).toList();
    await _saveIslands(updated);
  }

  Future<void> _resizeIsland(Room room, String id, {double dw = 0, double dd = 0}) async {
    final updated = room.islands.map((i) {
      if (i.id != id) return i;
      final p = _islandPos(i);
      return i.copyWith(
        widthCm: (i.widthCm + dw).clamp(30.0, room.widthCm).toDouble(),
        depthCm: (i.depthCm + dd).clamp(30.0, room.lengthCm).toDouble(),
        xCm: p.xCm,
        yCm: p.yCm,
      );
    }).toList();
    await _saveIslands(updated);
  }

  Future<void> _editDimensions(Room room) async {
    var w = room.widthCm.round();
    var l = room.lengthCm.round();
    var h = room.wallHeightCm.round();
    final unitSystem = ref.read(unitSystemProvider);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(builder: (sheetContext, setSheet) {
        Widget stepper(String label, int value, int min, int max, ValueChanged<int> onChanged) {
          return Row(
            children: [
              Expanded(child: Text(label, style: Theme.of(sheetContext).textTheme.labelLarge)),
              IconButton(
                onPressed: value > min ? () => onChanged(value - 10) : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              SizedBox(width: 80, child: Text(formatLenValue(value.toDouble(), unitSystem), textAlign: TextAlign.center, style: Theme.of(sheetContext).textTheme.titleMedium)),
              IconButton(
                onPressed: value < max ? () => onChanged(value + 10) : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          );
        }

        return Padding(
          padding: EdgeInsets.only(left: 20, right: 20, bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Room size', style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 12),
              stepper('Width', w, 100, 1200, (v) => setSheet(() => w = v)),
              stepper('Length', l, 100, 1200, (v) => setSheet(() => l = v)),
              stepper('Wall height', h, 180, 400, (v) => setSheet(() => h = v)),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(sheetContext);
                  final hh = ref.read(householdIdProvider);
                  if (hh == null) return;
                  final newW = w.toDouble(), newL = l.toDouble();
                  final roomRepo = ref.read(roomRepositoryProvider);
                  await roomRepo.updateDimensions(
                    hh,
                    widget.room.id,
                    widthCm: newW,
                    lengthCm: newL,
                    wallHeightCm: h.toDouble(),
                  );
                  // Keep islands inside the (possibly smaller) new footprint.
                  if (room.islands.isNotEmpty) {
                    final clamped = room.islands.map((i) {
                      final odd = i.rotationQuarters.isOdd;
                      final iw = odd ? i.depthCm : i.widthCm;
                      final idp = odd ? i.widthCm : i.depthCm;
                      return i.copyWith(
                        xCm: i.xCm
                            .clamp(0.0, math.max(0.0, newW - iw))
                            .toDouble(),
                        yCm: i.yCm
                            .clamp(0.0, math.max(0.0, newL - idp))
                            .toDouble(),
                      );
                    }).toList();
                    await roomRepo.updateIslands(hh, widget.room.id, clamped);
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      }),
    );
  }

  Future<void> _pickIslandFace(String islandId) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final f in WallSide.values)
              ListTile(
                leading: const Icon(Icons.square_outlined),
                title: Text('${f.label.replaceAll(' wall', '')} face'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openSurface(islandSurfaceId(islandId, f));
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch (not read) the rooms stream so resizing/editing an island — which
    // persists via updateIslands/updateDimensions and re-emits from Firestore —
    // rebuilds this screen and updates the rendered size in realtime.
    final room = _roomFrom(ref.watch(roomsProvider).value);
    final unitSystem = ref.watch(unitSystemProvider);
    final unitsAsync = ref.watch(unitsProvider);
    final allUnits = unitsAsync.value ?? [];
    final roomUnits = allUnits.where((u) => u.roomId == room.id).toList();

    // Migrate this room's units into the surface model once, on open.
    if (!_migrated && roomUnits.isNotEmpty) {
      _migrated = true;
      final hh = ref.read(householdIdProvider);
      if (hh != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(unitRepositoryProvider).migrateRoomToElevation(
                householdId: hh,
                room: room,
                unitsInRoom: roomUnits,
              );
        });
      }
    }

    int countOn(String surfaceId) =>
        roomUnits.where((u) => u.surfaceId == surfaceId).length;
    final unplaced = roomUnits.where((u) => u.surfaceId == null).length;

    final selectedIsland =
        room.islands.where((i) => i.id == _selectedIslandId).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(room.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Room size',
            icon: const Icon(Icons.straighten),
            onPressed: () => _editDimensions(room),
          ),
          IconButton(
            tooltip: '3D walk-around',
            icon: const Icon(Icons.threed_rotation),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => Room3DScreen(room: room)),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addIsland(room),
        icon: const Icon(Icons.add),
        label: const Text('Add island'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Tap a wall to design it · drag an island to move it',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          if (unplaced > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Material(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text('$unplaced unit(s) still being placed…',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              ),
            ),
          Expanded(
            child: LayoutBuilder(builder: (context, c) {
              final margin = 40.0;
              final availW = c.maxWidth - margin * 2;
              final availH = c.maxHeight - margin * 2;
              final scale = math
                  .min(availW / room.widthCm, availH / room.lengthCm)
                  .clamp(0.05, 4.0);
              final drawnW = room.widthCm * scale;
              final drawnH = room.lengthCm * scale;
              _scale = scale;
              _origin = Offset(
                (c.maxWidth - drawnW) / 2,
                (c.maxHeight - drawnH) / 2,
              );
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => _onTapUp(d, room),
                onPanStart: (d) => _onPanStart(d, room),
                onPanUpdate: (d) => _onPanUpdate(d, room),
                onPanEnd: (d) => _onPanEnd(d, room),
                child: CustomPaint(
                  size: Size(c.maxWidth, c.maxHeight),
                  painter: _TopViewPainter(
                    room: room,
                    scale: scale,
                    origin: _origin,
                    countOn: countOn,
                    bandCm: _wallBandCm(room),
                    islandPos: _islandPos,
                    islandExtent: _islandExtent,
                    selectedIslandId: _selectedIslandId,
                    scheme: Theme.of(context).colorScheme,
                    textTheme: Theme.of(context).textTheme,
                  ),
                ),
              );
            }),
          ),
          if (selectedIsland != null)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: _IslandToolbar(
                  island: selectedIsland,
                  unitSystem: unitSystem,
                  onWidth: (d) => _resizeIsland(room, selectedIsland.id, dw: d),
                  onDepth: (d) => _resizeIsland(room, selectedIsland.id, dd: d),
                  onRotate: () => _rotateIsland(room, selectedIsland.id),
                  onFaces: () => _pickIslandFace(selectedIsland.id),
                  onDelete: () => _deleteIsland(room, selectedIsland.id),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _IslandToolbar extends StatelessWidget {
  const _IslandToolbar({
    required this.island,
    required this.unitSystem,
    required this.onWidth,
    required this.onDepth,
    required this.onRotate,
    required this.onFaces,
    required this.onDelete,
  });

  final Island island;
  final UnitSystem unitSystem;
  final ValueChanged<double> onWidth;
  final ValueChanged<double> onDepth;
  final VoidCallback onRotate;
  final VoidCallback onFaces;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                'Island · ${formatLen(island.widthCm, unitSystem)} × ${formatLen(island.depthCm, unitSystem)}',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                _mini(context, 'W-', () => onWidth(-15)),
                _mini(context, 'W+', () => onWidth(15)),
                _mini(context, 'D-', () => onDepth(-15)),
                _mini(context, 'D+', () => onDepth(15)),
                IconButton.filledTonal(
                    tooltip: 'Rotate',
                    onPressed: onRotate,
                    icon: const Icon(Icons.rotate_90_degrees_cw_outlined, size: 20)),
                FilledButton.icon(
                    onPressed: onFaces,
                    icon: const Icon(Icons.grid_view, size: 18),
                    label: const Text('Design faces')),
                IconButton.filledTonal(
                    tooltip: 'Delete',
                    onPressed: onDelete,
                    icon: Icon(Icons.delete_outline, size: 20, color: scheme.error)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _mini(BuildContext context, String label, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 40),
        padding: EdgeInsets.zero,
      ),
      child: Text(label),
    );
  }
}

class _TopViewPainter extends CustomPainter {
  _TopViewPainter({
    required this.room,
    required this.scale,
    required this.origin,
    required this.countOn,
    required this.bandCm,
    required this.islandPos,
    required this.islandExtent,
    required this.selectedIslandId,
    required this.scheme,
    required this.textTheme,
  });

  final Room room;
  final double scale;
  final Offset origin;
  final int Function(String) countOn;
  final double bandCm;
  final ({double xCm, double yCm}) Function(Island) islandPos;
  final (double, double) Function(Island) islandExtent;
  final String? selectedIslandId;
  final ColorScheme scheme;
  final TextTheme textTheme;

  Offset _p(double xCm, double yCm) =>
      origin + Offset(xCm * scale, yCm * scale);

  @override
  void paint(Canvas canvas, Size size) {
    final floor = Rect.fromPoints(_p(0, 0), _p(room.widthCm, room.lengthCm));

    // Floor.
    canvas.drawRect(
        floor,
        Paint()
          ..color = Color.lerp(
              scheme.surfaceContainerHigh, scheme.primary, 0.04)!);

    final band = bandCm * scale;
    final wallPaint = Paint()..color = scheme.surfaceContainerHighest;
    // Wall bands (inset strips along each edge).
    final north = Rect.fromLTWH(floor.left, floor.top, floor.width, band);
    final south =
        Rect.fromLTWH(floor.left, floor.bottom - band, floor.width, band);
    final west = Rect.fromLTWH(floor.left, floor.top, band, floor.height);
    final east =
        Rect.fromLTWH(floor.right - band, floor.top, band, floor.height);
    for (final r in [north, south, west, east]) {
      canvas.drawRect(r, wallPaint);
      canvas.drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = scheme.outlineVariant,
      );
    }

    // Floor border.
    canvas.drawRect(
      floor,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = scheme.outline,
    );

    // Wall labels + counts.
    void wallLabel(WallSide side, Offset at) {
      final n = countOn(wallSurfaceId(side));
      _label(canvas, '${side.label.replaceAll(' wall', '')}\n$n units', at,
          center: true);
    }

    wallLabel(WallSide.north, Offset(floor.center.dx, floor.top + band / 2));
    wallLabel(WallSide.south, Offset(floor.center.dx, floor.bottom - band / 2));
    wallLabel(WallSide.west, Offset(floor.left + band / 2, floor.center.dy));
    wallLabel(WallSide.east, Offset(floor.right - band / 2, floor.center.dy));

    // Islands.
    for (final i in room.islands) {
      final pos = islandPos(i);
      final (w, d) = islandExtent(i);
      final rect = Rect.fromPoints(
        _p(pos.xCm, pos.yCm),
        _p(pos.xCm + w, pos.yCm + d),
      );
      final selected = i.id == selectedIslandId;
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(6));
      canvas.drawRRect(
          rr,
          Paint()
            ..color = Color.lerp(
                scheme.tertiaryContainer, scheme.surface, 0.1)!);
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 3 : 1.5
          ..color = selected ? scheme.primary : scheme.outline,
      );
      _label(canvas, 'Island', rect.center, center: true);
    }
  }

  void _label(Canvas canvas, String text, Offset at, {bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurfaceVariant,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 120);
    final offset =
        center ? at - Offset(tp.width / 2, tp.height / 2) : at;
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _TopViewPainter oldDelegate) => true;
}

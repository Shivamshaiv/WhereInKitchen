import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wherein_kitchen/models/elevation.dart';
import 'package:wherein_kitchen/models/measure.dart';
import 'package:wherein_kitchen/models/room.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';
import 'package:wherein_kitchen/providers/providers.dart';
import 'package:wherein_kitchen/screens/unit/unit_view_screen.dart';
import 'package:wherein_kitchen/widgets/unit_colors.dart';

/// Immutable elevation placement used for optimistic local edits (cm).
typedef Elev = ({
  double xCm,
  double zCm,
  double widthCm,
  double hCm,
  double depthCm,
});

enum _DragMode { move, resizeWidth, resizeHeight, resizeBoth }

// Keyboard intents for the editor canvas.
class _DeleteIntent extends Intent {
  const _DeleteIntent();
}

class _CopyIntent extends Intent {
  const _CopyIntent();
}

class _PasteIntent extends Intent {
  const _PasteIntent();
}

class _DuplicateIntent extends Intent {
  const _DuplicateIntent();
}

class _DeselectIntent extends Intent {
  const _DeselectIntent();
}

class _NudgeIntent extends Intent {
  const _NudgeIntent(this.dx, this.dy);
  final double dx;
  final double dy;
}

/// A CallbackAction enabled only when [enabled] returns true. When disabled,
/// Shortcuts returns KeyEventResult.ignored so the key falls through to the
/// platform (e.g. arrow-key page scroll on web) instead of being swallowed.
class _GuardedAction<T extends Intent> extends CallbackAction<T> {
  _GuardedAction({required this.enabled, required super.onInvoke});
  final bool Function() enabled;
  @override
  bool isEnabled(T intent) => enabled();
}

const Map<ShortcutActivator, Intent> _kEditorShortcuts = {
  SingleActivator(LogicalKeyboardKey.delete): _DeleteIntent(),
  SingleActivator(LogicalKeyboardKey.backspace): _DeleteIntent(),
  SingleActivator(LogicalKeyboardKey.keyC, control: true): _CopyIntent(),
  SingleActivator(LogicalKeyboardKey.keyC, meta: true): _CopyIntent(),
  SingleActivator(LogicalKeyboardKey.keyV, control: true): _PasteIntent(),
  SingleActivator(LogicalKeyboardKey.keyV, meta: true): _PasteIntent(),
  SingleActivator(LogicalKeyboardKey.keyD, control: true): _DuplicateIntent(),
  SingleActivator(LogicalKeyboardKey.keyD, meta: true): _DuplicateIntent(),
  SingleActivator(LogicalKeyboardKey.escape): _DeselectIntent(),
  SingleActivator(LogicalKeyboardKey.arrowLeft): _NudgeIntent(-1, 0),
  SingleActivator(LogicalKeyboardKey.arrowRight): _NudgeIntent(1, 0),
  SingleActivator(LogicalKeyboardKey.arrowUp): _NudgeIntent(0, 1),
  SingleActivator(LogicalKeyboardKey.arrowDown): _NudgeIntent(0, -1),
  SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true): _NudgeIntent(-10, 0),
  SingleActivator(LogicalKeyboardKey.arrowRight, shift: true): _NudgeIntent(10, 0),
  SingleActivator(LogicalKeyboardKey.arrowUp, shift: true): _NudgeIntent(0, 10),
  SingleActivator(LogicalKeyboardKey.arrowDown, shift: true): _NudgeIntent(0, -10),
};

/// 2D front-elevation editor for one wall or island face. Place base/wall/tall
/// cabinets, drawers and open shelves freely: drag to move, drag the edge
/// handles to resize (any width/height), set depth in the toolbar. Pinch or use
/// the zoom buttons to work on walls bigger than the screen. Supports copy /
/// paste / duplicate and keyboard shortcuts.
class WallElevationScreen extends ConsumerStatefulWidget {
  const WallElevationScreen({
    super.key,
    required this.room,
    required this.surfaceId,
  });

  final Room room;
  final String surfaceId;

  @override
  ConsumerState<WallElevationScreen> createState() =>
      _WallElevationScreenState();
}

class _WallElevationScreenState extends ConsumerState<WallElevationScreen> {
  String? _selectedId;
  String? _draggingId;
  _DragMode _mode = _DragMode.move;
  Offset _grab = Offset.zero; // cm offset from element top-left at grab

  // View transform: base fit-scale × user zoom, plus a pan offset (pixels).
  double _baseScale = 1; // px per cm to fit the surface
  double _zoom = 1;
  Offset _pan = Offset.zero;
  double _s = 1; // effective px per cm (= _baseScale * _zoom)
  Offset _origin = Offset.zero; // screen px of surface (0,0)
  Size _viewport = Size.zero;

  // Gesture bookkeeping.
  Offset _startFocal = Offset.zero;
  Offset _startFocalCm = Offset.zero;
  double _startZoom = 1;
  bool _moved = false;
  String? _pressHitId;

  final Map<String, Elev> _local = {};

  // Units deleted this session: hidden immediately (optimistically) so they
  // vanish on tap without waiting for the Firestore delete stream to echo back.
  final Set<String> _deletedIds = {};

  // Repaint channel: bump this during a drag to repaint the canvas WITHOUT
  // rebuilding the whole widget tree every pointer frame.
  final ValueNotifier<int> _repaintTick = ValueNotifier(0);

  // Hardware-keyboard focus for the canvas (shortcuts route here when focused).
  final FocusNode _canvasFocus = FocusNode(debugLabel: 'wallCanvas');

  // Debounced persistence for arrow-key nudges (coalesces rapid presses).
  final Map<String, Timer> _saveTimers = {};

  // Active snap-alignment guides drawn during a drag (surface-space cm).
  final List<double> _activeVGuidesCm = []; // x positions
  final List<double> _activeHGuidesCm = []; // zCm-from-floor values

  double get _surfaceLen => surfaceLengthCm(widget.room, widget.surfaceId);
  double get _wallH => widget.room.wallHeightCm;

  @override
  void dispose() {
    // Flush any pending debounced nudge saves so a move made in the last 300ms
    // before leaving isn't dropped when the timers are cancelled. Read ref here
    // (still valid at dispose start); the Firestore write outlives this widget.
    if (_saveTimers.isNotEmpty) {
      final hh = ref.read(householdIdProvider);
      if (hh != null) {
        final repo = ref.read(unitRepositoryProvider);
        for (final id in _saveTimers.keys) {
          final e = _local[id];
          if (e == null) continue;
          repo.updateElevation(
            hh,
            id,
            surfaceId: widget.surfaceId,
            xCm: e.xCm,
            zCm: e.zCm,
            widthCm: e.widthCm,
            hCm: e.hCm,
            depthCm: e.depthCm,
          );
        }
      }
    }
    for (final t in _saveTimers.values) {
      t.cancel();
    }
    _saveTimers.clear();
    _repaintTick.dispose();
    _canvasFocus.dispose();
    super.dispose();
  }

  List<StorageUnit> _onSurface(List<StorageUnit> all) => all
      .where((u) =>
          u.roomId == widget.room.id &&
          u.surfaceId == widget.surfaceId &&
          !_deletedIds.contains(u.id))
      .toList()
    ..sort((a, b) => (a.xCm ?? 0).compareTo(b.xCm ?? 0));

  StorageUnit? _selected(List<StorageUnit> onSurface) =>
      onSurface.where((u) => u.id == _selectedId).firstOrNull;

  Elev _elevOf(StorageUnit u) {
    final l = _local[u.id];
    if (l != null) return l;
    return (
      xCm: u.xCm ?? 0,
      zCm: u.zCm ?? 0,
      widthCm: u.widthCm ?? 60,
      hCm: u.hCm ?? 60,
      depthCm: u.depthCm ?? kDefaultDepthCm,
    );
  }

  /// Element rect in cm-canvas space (y-down from the ceiling).
  Rect _rectOf(Elev e) =>
      Rect.fromLTWH(e.xCm, _wallH - (e.zCm + e.hCm), e.widthCm, e.hCm);

  Offset _toCm(Offset px) => (px - _origin) / _s;

  bool _overlapsOthers(String id, Elev e, List<StorageUnit> onSurface) {
    for (final o in onSurface) {
      if (o.id == id) continue;
      final oe = _elevOf(o);
      if (elevationRectsOverlap(e.xCm, e.zCm, e.widthCm, e.hCm, oe.xCm, oe.zCm,
          oe.widthCm, oe.hCm)) {
        return true;
      }
    }
    return false;
  }

  StorageUnit? _hitTest(Offset cm, List<StorageUnit> onSurface) {
    for (final u in onSurface.reversed) {
      if (_rectOf(_elevOf(u)).inflate(2 / _s).contains(cm)) return u;
    }
    return null;
  }

  // ---- unified gesture (drag units + pan/zoom the canvas) ------------------

  void _onScaleStart(ScaleStartDetails d, List<StorageUnit> onSurface) {
    _startFocal = d.localFocalPoint;
    _startFocalCm = _toCm(d.localFocalPoint);
    _startZoom = _zoom;
    _moved = false;
    final p = _startFocalCm;
    final hit = _hitTest(p, onSurface);
    _pressHitId = hit?.id;

    if (hit != null && d.pointerCount == 1) {
      final e = _elevOf(hit);
      final r = _rectOf(e);
      final pad = 22.0 / _s;
      // Only the selected unit shows resize handles, so only it exposes resize
      // hit-zones; grabbing any other unit always moves it.
      if (hit.id != _selectedId) {
        _mode = _DragMode.move;
      } else if ((p - Offset(r.right, r.top)).distance < pad) {
        // Corner (width+height) test first so it wins near the top-right.
        _mode = _DragMode.resizeBoth;
      } else if ((p - Offset(r.right, r.center.dy)).distance < pad) {
        _mode = _DragMode.resizeWidth;
      } else if ((p - Offset(r.center.dx, r.top)).distance < pad) {
        _mode = _DragMode.resizeHeight;
      } else {
        _mode = _DragMode.move;
      }
      // One rebuild so the painter learns the dragging unit + mode (the badge
      // and live handles need it); per-frame moves then repaint via the tick.
      setState(() {
        _draggingId = hit.id;
        _grab = p - r.topLeft;
      });
    } else {
      _draggingId = null;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d, List<StorageUnit> onSurface) {
    if ((d.localFocalPoint - _startFocal).distance > 3) _moved = true;

    if (_draggingId != null) {
      // Only mutate geometry once the gesture is a real drag; a sub-threshold
      // tap-jitter must not write a phantom (unpersisted) _local entry.
      if (_moved) _dragUnit(d, onSurface);
      return;
    }
    // Canvas pan + zoom, anchored to the focal point so content doesn't jump.
    // (Must stay setState: the LayoutBuilder recomputes _s/_origin from these.)
    setState(() {
      final z = (_startZoom * d.scale).clamp(0.2, 10.0);
      final s = _baseScale * z;
      final center = Offset(
        (_viewport.width - _surfaceLen * s) / 2,
        (_viewport.height - _wallH * s) / 2,
      );
      _zoom = z;
      _pan = d.localFocalPoint -
          Offset(_startFocalCm.dx * s, _startFocalCm.dy * s) -
          center;
    });
  }

  void _dragUnit(ScaleUpdateDetails d, List<StorageUnit> onSurface) {
    final id = _draggingId!;
    final unit = onSurface.where((u) => u.id == id).firstOrNull;
    if (unit == null) return;
    final e = _elevOf(unit);
    final p = _toCm(d.localFocalPoint);
    final neighbours = onSurface.where((u) => u.id != id).map(_elevOf).toList();

    _activeVGuidesCm.clear();
    _activeHGuidesCm.clear();

    Elev next;
    switch (_mode) {
      case _DragMode.move:
        final topLeft = p - _grab;
        var x = clampCm(topLeft.dx, 0, math.max(0, _surfaceLen - e.widthCm));
        final top = clampCm(topLeft.dy, 0, math.max(0, _wallH - e.hCm));
        var z = _wallH - (top + e.hCm);
        final xTargets = <double>[
          0,
          _surfaceLen - e.widthCm,
          ...neighbours.map((n) => n.xCm),
          ...neighbours.map((n) => n.xCm + n.widthCm - e.widthCm),
        ];
        final zTargets = <double>[
          0,
          ref.read(counterHeightProvider),
          ref.read(wallCabinetHeightProvider),
          ...neighbours.map((n) => n.zCm),
          ...neighbours.map((n) => n.zCm + n.hCm),
        ];
        x = snapCm(x, xTargets);
        z = snapCm(z, zTargets);
        if (snappedTo(x, xTargets) != null) {
          _activeVGuidesCm
            ..add(x)
            ..add(x + e.widthCm);
        }
        if (snappedTo(z, zTargets) != null) {
          _activeHGuidesCm
            ..add(z)
            ..add(z + e.hCm);
        }
        next =
            (xCm: x, zCm: z, widthCm: e.widthCm, hCm: e.hCm, depthCm: e.depthCm);
      case _DragMode.resizeWidth:
        final hiW = math.max(20.0, _surfaceLen - e.xCm);
        var w = clampCm(p.dx - e.xCm, 20, hiW);
        final wTargets = neighbours.map((n) => n.xCm - e.xCm).toList();
        w = snapCm(w, wTargets);
        if (snappedTo(w, wTargets) != null) _activeVGuidesCm.add(e.xCm + w);
        next =
            (xCm: e.xCm, zCm: e.zCm, widthCm: w, hCm: e.hCm, depthCm: e.depthCm);
      case _DragMode.resizeHeight:
        final bottomScreenY = _wallH - e.zCm;
        final h = clampCm(bottomScreenY - p.dy, 15, _wallH - e.zCm);
        next =
            (xCm: e.xCm, zCm: e.zCm, widthCm: e.widthCm, hCm: h, depthCm: e.depthCm);
      case _DragMode.resizeBoth:
        final hiW = math.max(20.0, _surfaceLen - e.xCm);
        var w = clampCm(p.dx - e.xCm, 20, hiW);
        final wTargets = neighbours.map((n) => n.xCm - e.xCm).toList();
        w = snapCm(w, wTargets);
        if (snappedTo(w, wTargets) != null) _activeVGuidesCm.add(e.xCm + w);
        final h = clampCm((_wallH - e.zCm) - p.dy, 15, _wallH - e.zCm);
        next =
            (xCm: e.xCm, zCm: e.zCm, widthCm: w, hCm: h, depthCm: e.depthCm);
    }

    // No setState: mutate the optimistic geometry and repaint via the tick, so
    // the tree isn't rebuilt every pointer frame (buttery on single-thread web).
    _local[id] = next;
    _repaintTick.value++;
  }

  Future<void> _onScaleEnd(ScaleEndDetails d, List<StorageUnit> onSurface) async {
    final id = _draggingId;
    // Rebuild once so the painter is reconstructed with draggingId == null; this
    // drops the alignment guides AND the drag dimension badge in the same frame.
    setState(() {
      _draggingId = null;
      _activeVGuidesCm.clear();
      _activeHGuidesCm.clear();
    });
    if (!_moved) {
      _canvasFocus.requestFocus();
      setState(() => _selectedId = _pressHitId);
      return;
    }
    if (id == null) return;
    final e = _local[id];
    if (e != null && _overlapsOthers(id, e, onSurface)) {
      // Dropped on another unit — discard the move rather than overlapping.
      setState(() => _local.remove(id));
      return;
    }
    final saved = await _persist(id);
    // Drop the optimistic entry once saved, unless a newer edit arrived during
    // the async write (compare-and-remove) so we don't clobber it.
    if (mounted && saved != null && _local[id] == saved) {
      setState(() => _local.remove(id));
    }
  }

  Future<Elev?> _persist(String id) async {
    final hh = ref.read(householdIdProvider);
    final e = _local[id];
    if (hh == null || e == null) return null;
    await ref.read(unitRepositoryProvider).updateElevation(
          hh,
          id,
          surfaceId: widget.surfaceId,
          xCm: e.xCm,
          zCm: e.zCm,
          widthCm: e.widthCm,
          hCm: e.hCm,
          depthCm: e.depthCm,
        );
    return e;
  }

  void _scheduleSave(String id) {
    _saveTimers[id]?.cancel();
    _saveTimers[id] = Timer(const Duration(milliseconds: 300), () async {
      _saveTimers.remove(id);
      final saved = await _persist(id);
      // Only drop the optimistic entry if no newer nudge arrived during the
      // async write; otherwise leave it for the next scheduled save to flush.
      if (mounted && saved != null && _local[id] == saved) {
        setState(() => _local.remove(id));
      }
    });
  }

  void _zoomBy(double factor) {
    setState(() => _zoom = (_zoom * factor).clamp(0.2, 10.0));
  }

  void _resetView() {
    setState(() {
      _zoom = 1;
      _pan = Offset.zero;
    });
  }

  // ---- add / copy / paste / duplicate / edit / delete ----------------------

  double _freeXAmong(double z, double h, double w, List<Elev> elevs) {
    final band = elevs
        .where((e) => e.zCm < z + h && z < e.zCm + e.hCm)
        .toList()
      ..sort((a, b) => a.xCm.compareTo(b.xCm));
    var x = 0.0;
    for (final e in band) {
      if (x + w <= e.xCm) break;
      x = math.max(x, e.xCm + e.widthCm);
    }
    return x;
  }

  double _firstFreeX(double z, double h, double w, List<StorageUnit> onSurface) =>
      _freeXAmong(z, h, w, onSurface.map(_elevOf).toList());

  /// A room-unique, human-friendly name: returns [base] if free, else the next
  /// numbered variant ("Cabinet" → "Cabinet 2" → "Cabinet 3"). If [base]
  /// already ends in a number it continues from there.
  String _uniqueName(String base, Iterable<StorageUnit> units) {
    final existing = units.map((u) => u.name).toSet();
    final trimmed = base.trim().isEmpty ? 'Unit' : base.trim();
    if (!existing.contains(trimmed)) return trimmed;
    var stem = trimmed;
    var start = 2;
    final numMatch = RegExp(r'^(.*\S)\s+(\d+)$').firstMatch(trimmed);
    if (numMatch != null) {
      stem = numMatch.group(1)!;
      start = (int.tryParse(numMatch.group(2)!) ?? 1) + 1;
    } else {
      // Drop a legacy trailing "copy" so old "X copy" names re-number cleanly.
      final stripped = trimmed
          .replaceAll(RegExp(r'\s+copy$', caseSensitive: false), '')
          .trim();
      if (stripped.isNotEmpty) stem = stripped;
    }
    var n = start;
    while (existing.contains('$stem $n')) {
      n++;
    }
    return '$stem $n';
  }

  /// Shared create → place → generate-slots pipeline used by add / duplicate /
  /// paste so all three behave identically.
  Future<void> _placeNewUnit({
    required String name,
    required StorageUnitType type,
    required UnitMount mount,
    required int rows,
    required int columns,
    required int heightCm,
    required double xCm,
    required double zCm,
    required double widthCm,
    required double hCm,
    required double depthCm,
    required List<StorageUnit> onSurface,
  }) async {
    final hh = ref.read(householdIdProvider);
    if (hh == null) return;
    // Refuse to place where it would overlap an existing unit (mirrors the
    // drag/nudge guards): _firstFreeX can only clamp back into occupied space
    // when the surface is too crowded to fit this footprint.
    final target =
        (xCm: xCm, zCm: zCm, widthCm: widthCm, hCm: hCm, depthCm: depthCm);
    if (_overlapsOthers('', target, onSurface)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No room on this surface')),
        );
      }
      return;
    }
    // sortOrder is a room-wide ordering, so derive it from all of the room's
    // units (across surfaces), not just this surface — avoids duplicate values.
    final roomUnits = (ref.read(unitsProvider).value ?? const <StorageUnit>[])
        .where((u) => u.roomId == widget.room.id)
        .toList();
    final sortOrder =
        roomUnits.fold<int>(-1, (m, u) => math.max(m, u.sortOrder)) + 1;
    final unitRepo = ref.read(unitRepositoryProvider);
    final unit = await unitRepo.createUnit(
      householdId: hh,
      roomId: widget.room.id,
      name: _uniqueName(name, roomUnits),
      type: type,
      rows: rows,
      columns: type.holdsItems ? columns : 1,
      sortOrder: sortOrder,
      mount: mount,
      heightCm: heightCm,
    );
    await unitRepo.updateElevation(
      hh,
      unit.id,
      surfaceId: widget.surfaceId,
      xCm: xCm,
      zCm: zCm,
      widthCm: widthCm,
      hCm: hCm,
      depthCm: depthCm,
    );
    await ref
        .read(slotRepositoryProvider)
        .ensureSlotsForUnit(householdId: hh, unit: unit);
    if (mounted) setState(() => _selectedId = unit.id);
  }

  Future<void> _addFromTemplate(
      UnitTemplate tpl, List<StorageUnit> onSurface) async {
    final z = tpl.mount == UnitMount.wall
        ? ref.read(wallCabinetHeightProvider)
        : defaultZCmFor(tpl.mount);
    final h = tpl.heightCm.toDouble();
    final x = math.min(
      _firstFreeX(z, h, tpl.widthCm, onSurface),
      math.max(0.0, _surfaceLen - tpl.widthCm),
    );
    await _placeNewUnit(
      name: tpl.defaultName ?? tpl.label,
      type: tpl.type,
      mount: tpl.mount,
      rows: tpl.rows,
      columns: tpl.columns,
      heightCm: tpl.heightCm,
      xCm: x,
      zCm: z,
      widthCm: tpl.widthCm,
      hCm: h,
      depthCm: tpl.depthCm,
      onSurface: onSurface,
    );
  }

  void _copySelected(List<StorageUnit> onSurface) {
    final u = _selected(onSurface);
    if (u == null) return;
    final e = _elevOf(u);
    ref.read(elevationClipboardProvider.notifier).state = ElevClipboard(
      name: u.name,
      type: u.type,
      mount: u.mount,
      rows: u.rows,
      columns: u.columns,
      heightCm: u.heightCm ?? e.hCm.round(),
      widthCm: e.widthCm,
      hCm: e.hCm,
      depthCm: e.depthCm,
      zCm: e.zCm,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('Copied ${u.name}'),
          duration: const Duration(seconds: 1)),
    );
  }

  Future<void> _duplicate(StorageUnit u, List<StorageUnit> onSurface) async {
    final e = _elevOf(u);
    final x = math.min(
      _firstFreeX(e.zCm, e.hCm, e.widthCm, onSurface),
      math.max(0.0, _surfaceLen - e.widthCm),
    );
    await _placeNewUnit(
      name: u.name,
      type: u.type,
      mount: u.mount,
      rows: u.rows,
      columns: u.columns,
      heightCm: u.heightCm ?? e.hCm.round(),
      xCm: x,
      zCm: e.zCm,
      widthCm: e.widthCm,
      hCm: e.hCm,
      depthCm: e.depthCm,
      onSurface: onSurface,
    );
  }

  Future<void> _paste(List<StorageUnit> onSurface) async {
    if (_draggingId != null) return; // guard mid-drag
    final clip = ref.read(elevationClipboardProvider);
    if (clip == null) return;
    final hCm = math.min(clip.hCm, math.max(15.0, _wallH));
    final z = clampCm(clip.zCm, 0, math.max(0.0, _wallH - hCm));
    final w = math.min(clip.widthCm, math.max(20.0, _surfaceLen));
    final x = math.min(
      _firstFreeX(z, hCm, w, onSurface),
      math.max(0.0, _surfaceLen - w),
    );
    await _placeNewUnit(
      name: clip.name,
      type: clip.type,
      mount: clip.mount,
      rows: clip.rows,
      columns: clip.columns,
      heightCm: clip.heightCm,
      xCm: x,
      zCm: z,
      widthCm: w,
      hCm: hCm,
      depthCm: clip.depthCm,
      onSurface: onSurface,
    );
  }

  void _nudgeSelected(double dx, double dy, List<StorageUnit> onSurface) {
    final id = _selectedId;
    if (id == null) return;
    final u = _selected(onSurface);
    if (u == null) return;
    final e = _elevOf(u);
    final x = clampCm(e.xCm + dx, 0, math.max(0, _surfaceLen - e.widthCm));
    final z = clampCm(e.zCm + dy, 0, math.max(0, _wallH - e.hCm));
    final next =
        (xCm: x, zCm: z, widthCm: e.widthCm, hCm: e.hCm, depthCm: e.depthCm);
    if (_overlapsOthers(id, next, onSurface)) return; // don't nudge into a wall
    setState(() => _local[id] = next);
    _scheduleSave(id);
  }

  Future<void> _pickTemplate(List<StorageUnit> onSurface) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        final unitSystem = ref.read(unitSystemProvider);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Add to this surface',
                      style: Theme.of(sheetContext).textTheme.titleMedium),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    for (final tpl in kUnitTemplates)
                      ListTile(
                        leading: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: unitBaseColor(tpl.type, scheme),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: Colors.black.withValues(alpha: 0.25)),
                          ),
                        ),
                        title: Text(tpl.label),
                        subtitle: Text(formatDims(tpl.widthCm,
                            tpl.heightCm.toDouble(), tpl.depthCm, unitSystem)),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _addFromTemplate(tpl, onSurface);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editUnit(StorageUnit unit) async {
    final hh = ref.read(householdIdProvider);
    if (hh == null) return;
    final unitSystem = ref.read(unitSystemProvider);
    final e = _elevOf(unit);
    final nameCtrl = TextEditingController(text: unit.name);
    var type = unit.type;
    var rows = unit.rows;
    var columns = unit.columns;
    var widthCm = e.widthCm.round();
    var heightCm = e.hCm.round();
    var depthCm = e.depthCm.round();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(builder: (sheetContext, setSheet) {
          Widget stepper(String label, int value, int min, int max, int step,
              ValueChanged<int> onChanged, {String Function(int)? display}) {
            return Row(
              children: [
                Expanded(
                    child: Text(label,
                        style: Theme.of(sheetContext).textTheme.labelLarge)),
                IconButton(
                  onPressed: value > min
                      ? () => onChanged(math.max(min, value - step))
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                SizedBox(
                  width: 76,
                  child: Text(display?.call(value) ?? '$value',
                      textAlign: TextAlign.center,
                      style: Theme.of(sheetContext).textTheme.titleMedium),
                ),
                IconButton(
                  onPressed: value < max
                      ? () => onChanged(math.min(max, value + step))
                      : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            );
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Edit ${unit.name}',
                      style: Theme.of(sheetContext).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  const SizedBox(height: 12),
                  Text('Type',
                      style: Theme.of(sheetContext).textTheme.labelLarge),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: StorageUnitType.values.map((t) {
                      return ChoiceChip(
                        label: Text(t.label),
                        selected: type == t,
                        onSelected: (_) => setSheet(() => type = t),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  if (type.holdsItems)
                    stepper('Shelves', rows, 1, kMaxShelfRows, 1,
                        (v) => setSheet(() => rows = v)),
                  if (type.holdsItems && type != StorageUnitType.freezer)
                    stepper(
                        type == StorageUnitType.fridge ? 'Doors' : 'Doors / bays',
                        columns,
                        1,
                        type == StorageUnitType.fridge ? 2 : kMaxDoors,
                        1,
                        (v) => setSheet(() => columns = v)),
                  stepper('Width', widthCm, 15, 400, 5,
                      (v) => setSheet(() => widthCm = v),
                      display: (v) => formatLenValue(v.toDouble(), unitSystem)),
                  stepper('Height', heightCm, 10, 300, 5,
                      (v) => setSheet(() => heightCm = v),
                      display: (v) => formatLenValue(v.toDouble(), unitSystem)),
                  stepper('Depth', depthCm, 10, 100, 5,
                      (v) => setSheet(() => depthCm = v),
                      display: (v) => formatLenValue(v.toDouble(), unitSystem)),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () async {
                      final name = nameCtrl.text.trim();
                      Navigator.pop(sheetContext);
                      final newColumns = type.holdsItems ? columns : 1;
                      final updated = unit.copyWith(
                        name: name.isEmpty ? unit.name : name,
                        type: type,
                        rows: rows,
                        columns: newColumns,
                      );
                      await ref
                          .read(unitRepositoryProvider)
                          .updateUnit(updated);
                      await ref.read(unitRepositoryProvider).updateElevation(
                            hh,
                            unit.id,
                            surfaceId: widget.surfaceId,
                            xCm: e.xCm,
                            zCm: e.zCm,
                            widthCm: math.min(widthCm.toDouble(),
                                math.max(20.0, _surfaceLen - e.xCm)),
                            hCm: math.min(heightCm.toDouble(),
                                math.max(15.0, _wallH - e.zCm)),
                            depthCm: depthCm.toDouble(),
                          );
                      if (rows != unit.rows ||
                          newColumns != unit.columns ||
                          type != unit.type) {
                        await ref
                            .read(slotRepositoryProvider)
                            .reconcileSlotsForUnit(
                                householdId: hh, unit: updated);
                      }
                      if (mounted) setState(() => _local.remove(unit.id));
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Future<void> _moveToSurface(StorageUnit unit) async {
    final hh = ref.read(householdIdProvider);
    if (hh == null) return;
    final e = _elevOf(unit);
    final surfaces = <({String id, String label})>[
      for (final w in WallSide.values) (id: wallSurfaceId(w), label: w.label),
      for (final island in widget.room.islands)
        for (final f in WallSide.values)
          (id: islandSurfaceId(island.id, f), label: 'Island · ${f.label}'),
    ].where((s) => s.id != widget.surfaceId).toList();

    final target = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Move ${unit.name} to',
                    style: Theme.of(sheetContext).textTheme.titleMedium),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  for (final s in surfaces)
                    ListTile(
                      leading: const Icon(Icons.arrow_forward),
                      title: Text(s.label),
                      onTap: () => Navigator.pop(sheetContext, s.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (target == null) return;
    final all = ref.read(unitsProvider).value ?? [];
    final targetElevs = all
        .where((u) => u.roomId == widget.room.id && u.surfaceId == target)
        .map(_elevOf)
        .toList();
    final targetLen = surfaceLengthCm(widget.room, target);
    final x = math.min(
      _freeXAmong(e.zCm, e.hCm, e.widthCm, targetElevs),
      math.max(0.0, targetLen - e.widthCm),
    );
    final overlaps = targetElevs.any((oe) => elevationRectsOverlap(
        x, e.zCm, e.widthCm, e.hCm, oe.xCm, oe.zCm, oe.widthCm, oe.hCm));
    if (overlaps) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No room on that surface')),
        );
      }
      return;
    }
    await ref.read(unitRepositoryProvider).updateElevation(
          hh,
          unit.id,
          surfaceId: target,
          xCm: x,
          zCm: e.zCm,
          widthCm: e.widthCm,
          hCm: e.hCm,
          depthCm: e.depthCm,
        );
    if (mounted) {
      setState(() {
        _selectedId = null;
        _local.remove(unit.id);
      });
    }
  }

  Future<void> _deleteUnit(StorageUnit unit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${unit.name}?'),
        content: const Text(
            'This removes the unit, its shelves, and every item stored in it.'),
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
    final hh = ref.read(householdIdProvider);
    if (hh == null) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    // Hide it right away so it disappears on tap, then persist. If the delete
    // fails, restore it and surface the error instead of silently leaving it.
    setState(() {
      _deletedIds.add(unit.id);
      _selectedId = null;
      _local.remove(unit.id);
    });
    try {
      await ref.read(unitRepositoryProvider).deleteUnitCascade(hh, unit.id);
    } catch (e) {
      if (mounted) setState(() => _deletedIds.remove(unit.id));
      messenger.showSnackBar(
        SnackBar(content: Text('Couldn’t delete ${unit.name}. Try again.')),
      );
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text('Deleted ${unit.name}')));
  }

  String get _surfaceTitle {
    final wall = wallOfSurface(widget.surfaceId);
    if (wall != null) return wall.label;
    final isl = islandOfSurface(widget.surfaceId);
    if (isl != null) return 'Island · ${isl.face.label}';
    return 'Elevation';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unitsAsync = ref.watch(unitsProvider);
    final clipboard = ref.watch(elevationClipboardProvider);
    final unitSystem = ref.watch(unitSystemProvider);
    final counterHeightCm = ref.watch(counterHeightProvider);
    final wallBaseCm = ref.watch(wallCabinetHeightProvider);
    final slots = ref.watch(slotsProvider).value ?? [];
    final items = ref.watch(itemsProvider).value ?? [];
    final countByUnit = <String, int>{};
    final unitOfSlot = {for (final s in slots) s.id: s.unitId};
    for (final it in items) {
      final uid = unitOfSlot[it.slotId];
      if (uid != null) countByUnit[uid] = (countByUnit[uid] ?? 0) + 1;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_surfaceTitle),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text('${(_zoom * 100).round()}%',
                  style: Theme.of(context).textTheme.labelMedium),
            ),
          ),
          IconButton(
            tooltip: 'Zoom out',
            icon: const Icon(Icons.zoom_out),
            onPressed: _zoom <= 0.2 ? null : () => _zoomBy(1 / 1.3),
          ),
          IconButton(
            tooltip: 'Zoom in',
            icon: const Icon(Icons.zoom_in),
            onPressed: _zoom >= 10 ? null : () => _zoomBy(1.3),
          ),
          IconButton(
            tooltip: 'Fit',
            icon: const Icon(Icons.fit_screen_outlined),
            onPressed: _resetView,
          ),
          IconButton(
            tooltip: 'Paste',
            icon: const Icon(Icons.content_paste),
            onPressed: clipboard == null
                ? null
                : () => _paste(_onSurface(ref.read(unitsProvider).value ?? [])),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Drag to move · corner/edge dots to resize · arrows nudge · ⌘C/⌘V copy',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: _selectedId != null
          ? null
          : unitsAsync.maybeWhen(
              data: (all) => FloatingActionButton.extended(
                onPressed: () => _pickTemplate(_onSurface(all)),
                icon: const Icon(Icons.add),
                label: const Text('Add unit'),
              ),
              orElse: () => null,
            ),
      body: unitsAsync.when(
        data: (all) {
          final onSurface = _onSurface(all);
          final selected =
              onSurface.where((u) => u.id == _selectedId).firstOrNull;
          if (_surfaceLen <= 0) {
            return const Center(child: Text('This surface has no length.'));
          }
          return FocusableActionDetector(
            focusNode: _canvasFocus,
            autofocus: true,
            shortcuts: _kEditorShortcuts,
            actions: <Type, Action<Intent>>{
              _DeleteIntent: _GuardedAction<_DeleteIntent>(
                enabled: () => _selectedId != null,
                onInvoke: (_) {
                  final s = _selected(onSurface);
                  if (s != null) _deleteUnit(s);
                  return null;
                },
              ),
              _CopyIntent: CallbackAction<_CopyIntent>(onInvoke: (_) {
                _copySelected(onSurface);
                return null;
              }),
              _PasteIntent: CallbackAction<_PasteIntent>(onInvoke: (_) {
                _paste(onSurface);
                return null;
              }),
              _DuplicateIntent: CallbackAction<_DuplicateIntent>(onInvoke: (_) {
                final s = _selected(onSurface);
                if (s != null) _duplicate(s, onSurface);
                return null;
              }),
              _DeselectIntent: CallbackAction<_DeselectIntent>(onInvoke: (_) {
                if (_selectedId != null) setState(() => _selectedId = null);
                return null;
              }),
              _NudgeIntent: _GuardedAction<_NudgeIntent>(
                enabled: () => _selectedId != null,
                onInvoke: (i) {
                  _nudgeSelected(i.dx, i.dy, onSurface);
                  return null;
                },
              ),
            },
            child: Stack(
              children: [
                Positioned.fill(
                  child: LayoutBuilder(builder: (context, c) {
                    _viewport = Size(c.maxWidth, c.maxHeight);
                    _baseScale = math
                        .min(c.maxWidth / _surfaceLen, c.maxHeight / _wallH)
                        .toDouble();
                    _s = _baseScale * _zoom;
                    _origin = Offset(
                          (c.maxWidth - _surfaceLen * _s) / 2,
                          (c.maxHeight - _wallH * _s) / 2,
                        ) +
                        _pan;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onScaleStart: (d) => _onScaleStart(d, onSurface),
                      onScaleUpdate: (d) => _onScaleUpdate(d, onSurface),
                      onScaleEnd: (d) => _onScaleEnd(d, onSurface),
                      child: RepaintBoundary(
                        child: CustomPaint(
                          size: Size(c.maxWidth, c.maxHeight),
                          painter: _ElevationPainter(
                            repaint: _repaintTick,
                            units: onSurface,
                            elevOf: _elevOf,
                            countByUnit: countByUnit,
                            selectedId: _selectedId,
                            draggingId: _draggingId,
                            dragMode: _mode,
                            vGuidesCm: _activeVGuidesCm,
                            hGuidesCm: _activeHGuidesCm,
                            surfaceLenCm: _surfaceLen,
                            wallHeightCm: _wallH,
                            origin: _origin,
                            scale: _s,
                            scheme: scheme,
                            unitSystem: unitSystem,
                            counterHeightCm: counterHeightCm,
                            wallBaseCm: wallBaseCm,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                if (onSurface.isEmpty)
                  IgnorePointer(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.shelves,
                                size: 40, color: scheme.onPrimaryContainer),
                          ),
                          const SizedBox(height: 14),
                          Text('This wall is empty',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text('Tap “Add unit” to place your first cabinet',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
                if (selected != null)
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: MediaQuery.of(context).padding.bottom + 12,
                    child: _ElevationToolbar(
                      unit: selected,
                      elev: _elevOf(selected),
                      unitSystem: unitSystem,
                      onEdit: () => _editUnit(selected),
                      onMove: () => _moveToSurface(selected),
                      onDuplicate: () => _duplicate(selected, onSurface),
                      onOpen: selected.holdsItems
                          ? () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      UnitViewScreen(unit: selected),
                                ),
                              )
                          : null,
                      onDelete: () => _deleteUnit(selected),
                      onClose: () => setState(() => _selectedId = null),
                    ),
                  ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _ElevationToolbar extends StatelessWidget {
  const _ElevationToolbar({
    required this.unit,
    required this.elev,
    required this.unitSystem,
    required this.onEdit,
    required this.onMove,
    required this.onDuplicate,
    required this.onOpen,
    required this.onDelete,
    required this.onClose,
  });

  final StorageUnit unit;
  final Elev elev;
  final UnitSystem unitSystem;
  final VoidCallback onEdit;
  final VoidCallback onMove;
  final VoidCallback onDuplicate;
  final VoidCallback? onOpen;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(unit.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  Text(
                    '${formatDims(elev.widthCm, elev.hCm, elev.depthCm, unitSystem)} · '
                    '${formatLen(elev.zCm, unitSystem)} up',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            if (onOpen != null)
              IconButton(
                tooltip: 'Open shelves',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.visibility_outlined),
                onPressed: onOpen,
              ),
            IconButton(
              tooltip: 'Duplicate',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.content_copy),
              onPressed: onDuplicate,
            ),
            IconButton(
              tooltip: 'Move to another wall',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.swap_horiz),
              onPressed: onMove,
            ),
            IconButton(
              tooltip: 'Edit size & shelves',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit,
            ),
            IconButton(
              tooltip: 'Delete',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.delete_outline, color: scheme.error),
              onPressed: onDelete,
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

class _ElevationPainter extends CustomPainter {
  _ElevationPainter({
    required Listenable repaint,
    required this.units,
    required this.elevOf,
    required this.countByUnit,
    required this.selectedId,
    required this.draggingId,
    required this.dragMode,
    required this.vGuidesCm,
    required this.hGuidesCm,
    required this.surfaceLenCm,
    required this.wallHeightCm,
    required this.origin,
    required this.scale,
    required this.scheme,
    required this.unitSystem,
    required this.counterHeightCm,
    required this.wallBaseCm,
  }) : super(repaint: repaint);

  final List<StorageUnit> units;
  final Elev Function(StorageUnit) elevOf;
  final Map<String, int> countByUnit;
  final String? selectedId;
  final String? draggingId;
  final _DragMode dragMode;
  final List<double> vGuidesCm;
  final List<double> hGuidesCm;
  final double surfaceLenCm;
  final double wallHeightCm;
  final Offset origin;
  final double scale;
  final ColorScheme scheme;
  final UnitSystem unitSystem;
  final double counterHeightCm;
  final double wallBaseCm;

  Offset _p(double xCm, double yCmFromTop) =>
      origin + Offset(xCm * scale, yCmFromTop * scale);

  Elev? _activeElev() {
    final id = draggingId ?? selectedId;
    if (id == null) return null;
    for (final u in units) {
      if (u.id == id) return elevOf(u);
    }
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final wallRect = Rect.fromLTWH(
      origin.dx,
      origin.dy,
      surfaceLenCm * scale,
      wallHeightCm * scale,
    );
    // Keep everything within the wall bounds (oversized units can't spill off).
    canvas.clipRect(wallRect);

    // Wall backdrop.
    canvas.drawRect(
      wallRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [scheme.surfaceContainerHigh, scheme.surfaceContainerLow],
        ).createShader(wallRect),
    );

    _paintGrid(canvas, wallRect, size);

    canvas.drawRect(
      wallRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = scheme.outlineVariant,
    );

    // Floor line.
    canvas.drawLine(
      Offset(wallRect.left, wallRect.bottom),
      Offset(wallRect.right, wallRect.bottom),
      Paint()
        ..color = scheme.outline
        ..strokeWidth = 2,
    );

    // Units sit above the wall backdrop + grid…
    for (final unit in units) {
      _paintUnit(canvas, unit, wallRect);
    }

    // …but the measurements + guidelines always draw ON TOP of the units (kept
    // light) so a cabinet can never hide the counter line or the cm rulers.
    _paintCounterGuide(canvas, wallRect, size);
    _paintRulers(canvas, wallRect, size);

    // Active alignment guides (only while a snap is engaged during a drag).
    if (vGuidesCm.isNotEmpty || hGuidesCm.isNotEmpty) {
      final gp = Paint()
        ..color = const Color(0xFFEC407A)
        ..strokeWidth = 1.5;
      for (final xCm in vGuidesCm) {
        canvas.drawLine(_p(xCm, 0), _p(xCm, wallHeightCm), gp);
      }
      for (final zCm in hGuidesCm) {
        final yTop = wallHeightCm - zCm;
        canvas.drawLine(_p(0, yTop), _p(surfaceLenCm, yTop), gp);
      }
    }
  }

  void _paintCounterGuide(Canvas canvas, Rect wall, Size size) {
    _hGuide(canvas, wall, size, counterHeightCm, 'Counter', 0.45);
    // The wall-cabinet guide is fainter, and hidden if it coincides with the
    // counter line.
    if ((wallBaseCm - counterHeightCm).abs() > 5) {
      _hGuide(canvas, wall, size, wallBaseCm, 'Wall units', 0.3);
    }
  }

  void _hGuide(Canvas canvas, Rect wall, Size size, double heightCm,
      String name, double alpha) {
    final y = wall.bottom - heightCm * scale;
    if (y < wall.top || y > wall.bottom) return;
    final guidePaint = Paint()
      ..color = scheme.primary.withValues(alpha: alpha)
      ..strokeWidth = 1;
    const dash = 8.0, gap = 6.0;
    const stride = dash + gap;
    final visLeft = math.max(wall.left, 0.0);
    final visRight = math.min(wall.right, size.width);
    if (visRight > visLeft) {
      final startX =
          wall.left + ((visLeft - wall.left) / stride).floorToDouble() * stride;
      for (var x = startX; x < visRight; x += stride) {
        canvas.drawLine(
            Offset(x, y), Offset(math.min(x + dash, wall.right), y), guidePaint);
      }
    }
    // Label with a faint scrim so it stays readable even over a cabinet.
    final tp = TextPainter(
      text: TextSpan(
        text: '$name · ${formatLen(heightCm, unitSystem)}',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: scheme.primary,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final lx = wall.left + 6;
    final ly = y - tp.height - 3;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(lx - 3, ly - 1, tp.width + 6, tp.height + 2),
        const Radius.circular(4),
      ),
      Paint()..color = scheme.surface.withValues(alpha: 0.7),
    );
    tp.paint(canvas, Offset(lx, ly));
  }

  void _paintGrid(Canvas canvas, Rect wall, Size size) {
    final step = scale > 2 ? 10.0 : (scale > 0.8 ? 25.0 : 50.0);
    final minor = Paint()
      ..color = scheme.outlineVariant.withValues(alpha: 0.22)
      ..strokeWidth = 0.5;
    final major = Paint()
      ..color = scheme.outlineVariant.withValues(alpha: 0.4)
      ..strokeWidth = 0.5;
    for (var cm = step; cm < wallHeightCm; cm += step) {
      final y = wall.bottom - cm * scale;
      if (y < 0 || y > size.height) continue; // cull off-viewport
      canvas.drawLine(Offset(wall.left, y), Offset(wall.right, y),
          cm % 50 == 0 ? major : minor);
    }
    for (var cm = step; cm < surfaceLenCm; cm += step) {
      final x = wall.left + cm * scale;
      if (x < 0 || x > size.width) continue; // cull off-viewport
      canvas.drawLine(Offset(x, wall.top), Offset(x, wall.bottom),
          cm % 50 == 0 ? major : minor);
    }
  }

  void _paintRulers(Canvas canvas, Rect wall, Size size) {
    // Metric ticks in cm (label every 50 cm); imperial ticks every 6" with a
    // label every foot, so the numbers stay round in the chosen units.
    final metric = unitSystem.isMetric;
    final minorStep =
        metric ? (scale > 2 ? 10.0 : (scale > 0.8 ? 25.0 : 50.0)) : imperialRulerMinorCm;
    final labelEvery = metric ? (50.0 / minorStep).round() : 2; // foot = 2×6"
    final showLabels = minorStep * labelEvery * scale >= 26;
    final tick = Paint()
      ..color = scheme.outlineVariant
      ..strokeWidth = 1;

    void tickLabel(String text, Offset at) {
      final tp = TextPainter(
        text: TextSpan(
            text: text,
            style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, at);
    }

    String labelFor(double cm) => metric ? '${cm.round()}' : feetLabel(cm);

    // Top ruler (width along the surface).
    for (var cm = 0.0; cm <= surfaceLenCm + 0.5; cm += minorStep) {
      final x = wall.left + cm * scale;
      if (x < 0 || x > size.width) continue; // cull off-viewport
      final major = (cm / minorStep).round() % labelEvery == 0;
      canvas.drawLine(
          Offset(x, wall.top), Offset(x, wall.top + (major ? 8 : 4)), tick);
      if (major && showLabels && cm > 0) {
        tickLabel(labelFor(cm), Offset(x + 2, wall.top + 2));
      }
    }
    // Left ruler (height off the floor).
    for (var cm = 0.0; cm <= wallHeightCm + 0.5; cm += minorStep) {
      final y = wall.bottom - cm * scale;
      if (y < 0 || y > size.height) continue; // cull off-viewport
      final major = (cm / minorStep).round() % labelEvery == 0;
      canvas.drawLine(
          Offset(wall.left, y), Offset(wall.left + (major ? 8 : 4), y), tick);
      if (major && showLabels && cm > 0) {
        tickLabel(labelFor(cm), Offset(wall.left + 3, y + 2));
      }
    }

    // Highlight the selected/dragging unit's extents on both rulers.
    final sel = _activeElev();
    if (sel != null) {
      final rp = Paint()
        ..color = scheme.primary
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(wall.left + sel.xCm * scale, wall.top + 1.5),
          Offset(wall.left + (sel.xCm + sel.widthCm) * scale, wall.top + 1.5), rp);
      canvas.drawLine(
          Offset(wall.left + 1.5, wall.bottom - sel.zCm * scale),
          Offset(wall.left + 1.5, wall.bottom - (sel.zCm + sel.hCm) * scale),
          rp);
    }
  }

  void _paintUnit(Canvas canvas, StorageUnit unit, Rect wallRect) {
    final e = elevOf(unit);
    final tl = _p(e.xCm, wallHeightCm - (e.zCm + e.hCm));
    final rect = Rect.fromLTWH(tl.dx, tl.dy, e.widthCm * scale, e.hCm * scale);
    final selected = unit.id == selectedId;
    final dragging = unit.id == draggingId;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));

    canvas.drawRRect(rrect, Paint()..color = unitBaseColor(unit.type, scheme));
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 3 : 1
        ..color =
            selected ? scheme.primary : Colors.black.withValues(alpha: 0.4),
    );

    final detail = rect.width > 28 && rect.height > 20;
    if (detail) _paintDetail(canvas, unit, rect);

    _paintLabel(canvas, unit, rect);

    if (dragging || selected) {
      _paintBadge(canvas, e, rect, wallRect, dragging);
    }
    if (selected) _paintHandles(canvas, rect);
  }

  void _drawKnob(Canvas canvas, Offset o) {
    canvas.drawCircle(o, 2.5, Paint()..color = Colors.black.withValues(alpha: 0.35));
  }

  void _drawBarPull(Canvas canvas, Offset a, Offset b) {
    canvas.drawLine(
        a,
        b,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.35)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round);
  }

  void _paintDrawers(Canvas canvas, Rect rect, int rowCount, Paint stroke) {
    final rows = rowCount.clamp(1, kMaxShelfRows);
    for (var r = 0; r < rows; r++) {
      final rh = rect.height / rows;
      final front =
          Rect.fromLTWH(rect.left + 2, rect.top + r * rh + 2, rect.width - 4, rh - 4);
      if (front.width > 4 && front.height > 4) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(front, const Radius.circular(2)), stroke);
        final half = math.min(14.0, front.width * 0.25);
        _drawBarPull(canvas, Offset(front.center.dx - half, front.center.dy),
            Offset(front.center.dx + half, front.center.dy));
      }
    }
  }

  // Faint interior shelf lines so a cabinet/fridge conveys how many shelves it
  // holds behind its doors — an at-a-glance capacity cue alongside the sprite.
  void _drawShelfLines(Canvas canvas, Rect area, int rowCount) {
    final rows = rowCount.clamp(1, kMaxShelfRows);
    if (rows < 2 || area.width < 8 || area.height < 14) return;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.black.withValues(alpha: 0.13);
    for (var i = 1; i < rows; i++) {
      final y = area.top + area.height * (i / rows);
      canvas.drawLine(Offset(area.left + 2, y), Offset(area.right - 2, y), p);
    }
  }

  void _paintDetail(Canvas canvas, StorageUnit unit, Rect rect) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.black.withValues(alpha: 0.18);
    switch (unit.type) {
      case StorageUnitType.cabinet:
        final cols = unit.columns.clamp(1, kMaxDoors);
        final cw = rect.width / cols;
        for (var c = 0; c < cols; c++) {
          final door = Rect.fromLTWH(
              rect.left + c * cw + 2, rect.top + 2, cw - 4, rect.height - 4);
          if (door.width > 4 && door.height > 4) {
            _drawShelfLines(canvas, door, unit.rows); // shelves behind the door
            canvas.drawRRect(
                RRect.fromRectAndRadius(door, const Radius.circular(2)), stroke);
            final knobX = c.isEven ? door.right - 5 : door.left + 5;
            _drawKnob(canvas, Offset(knobX, door.center.dy));
          }
        }
      case StorageUnitType.drawer:
        _paintDrawers(canvas, rect, unit.rows, stroke);
      case StorageUnitType.freezer:
        _paintDrawers(canvas, rect, unit.rows, stroke);
      case StorageUnitType.shelf:
        final rows = unit.rows.clamp(1, kMaxShelfRows);
        for (var i = 1; i < rows; i++) {
          final y = rect.top + rect.height * (i / rows);
          canvas.drawLine(
              Offset(rect.left + 2, y), Offset(rect.right - 2, y), stroke);
        }
      case StorageUnitType.fridge:
        final doors = unit.columns.clamp(1, 2);
        if (doors >= 2) {
          // French / double door.
          canvas.drawLine(Offset(rect.center.dx, rect.top + 3),
              Offset(rect.center.dx, rect.bottom - 3), stroke);
          _drawBarPull(canvas, Offset(rect.center.dx - 5, rect.top + rect.height * 0.2),
              Offset(rect.center.dx - 5, rect.top + rect.height * 0.5));
          _drawBarPull(canvas, Offset(rect.center.dx + 5, rect.top + rect.height * 0.2),
              Offset(rect.center.dx + 5, rect.top + rect.height * 0.5));
        } else {
          // Single door with a side handle.
          _drawBarPull(canvas, Offset(rect.right - 7, rect.top + rect.height * 0.2),
              Offset(rect.right - 7, rect.top + rect.height * 0.55));
        }
        _drawShelfLines(canvas, rect.deflate(4), unit.rows);
      case StorageUnitType.range:
        final r = math.min(rect.width / 10, rect.height / 8);
        if (r > 1.5) {
          final topY = rect.top + rect.height * 0.22;
          for (var i = 0; i < 4; i++) {
            final cx = rect.left + rect.width * (i.isEven ? 0.3 : 0.7);
            final cy = topY + (i < 2 ? 0 : rect.height * 0.34);
            canvas.drawCircle(Offset(cx, cy), r, stroke);
          }
        }
      case StorageUnitType.sink:
        final basin = Rect.fromLTWH(rect.left + rect.width * 0.15,
            rect.top + rect.height * 0.28, rect.width * 0.7, rect.height * 0.5);
        if (basin.width > 4 && basin.height > 4) {
          canvas.drawOval(basin, stroke);
          canvas.drawLine(Offset(rect.center.dx, rect.top + 3),
              Offset(rect.center.dx, basin.top), stroke);
        }
      case StorageUnitType.oven:
        final door = rect.deflate(4);
        if (door.width > 4 && door.height > 4) {
          canvas.drawRRect(
              RRect.fromRectAndRadius(door, const Radius.circular(2)), stroke);
          _drawBarPull(canvas, Offset(door.left + 4, door.top + 5),
              Offset(door.right - 4, door.top + 5));
        }
      case StorageUnitType.gap:
      case StorageUnitType.dishwasher:
      case StorageUnitType.other:
        break;
    }
  }

  void _paintLabel(Canvas canvas, StorageUnit unit, Rect rect) {
    if (!(rect.height > 20 && rect.width > 28)) return;
    final tp = TextPainter(
      text: TextSpan(
        text: unit.name,
        style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(0, rect.width - 16));
    final scrim = RRect.fromRectAndRadius(
      Rect.fromLTWH(rect.left + 4, rect.top + 4, tp.width + 8, tp.height + 4),
      const Radius.circular(4),
    );
    canvas.drawRRect(scrim, Paint()..color = Colors.black.withValues(alpha: 0.5));
    tp.paint(canvas, Offset(rect.left + 8, rect.top + 6));

    final count = countByUnit[unit.id] ?? 0;
    // Hide the count badge for the selected unit so it can't collide with the
    // top-right corner resize handle.
    if (count > 0 && rect.width > 28 && unit.id != selectedId) {
      final c = Offset(rect.right - 10, rect.top + 10);
      canvas.drawCircle(c, 8, Paint()..color = scheme.primary);
      final ct = TextPainter(
        text: TextSpan(
            text: '$count',
            style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.w700, color: scheme.onPrimary)),
        textDirection: TextDirection.ltr,
      )..layout();
      ct.paint(canvas, c - Offset(ct.width / 2, ct.height / 2));
    }
  }

  void _paintBadge(
      Canvas canvas, Elev e, Rect rect, Rect wallRect, bool dragging) {
    String text;
    if (dragging && dragMode == _DragMode.resizeWidth) {
      text = 'W ${formatLen(e.widthCm, unitSystem)}';
    } else if (dragging && dragMode == _DragMode.resizeHeight) {
      text = 'H ${formatLen(e.hCm, unitSystem)}';
    } else if (dragging && dragMode == _DragMode.resizeBoth) {
      text = '${formatLen(e.widthCm, unitSystem)} × ${formatLen(e.hCm, unitSystem)}';
    } else {
      text =
          '${formatDims(e.widthCm, e.hCm, e.depthCm, unitSystem)} · ${formatLen(e.zCm, unitSystem)} up';
    }
    final btp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: scheme.onInverseSurface)),
      textDirection: TextDirection.ltr,
    )..layout();
    const padH = 6.0, padV = 3.0;
    final boxH = btp.height + padV * 2;
    var bx = rect.left;
    var by = rect.top - boxH - 4;
    if (by < wallRect.top) by = rect.bottom + 4; // flip below near ceiling
    // Keep the badge inside the clipped wall so a full-height unit's live
    // dimension isn't clipped away at/below the floor.
    by = by.clamp(wallRect.top, math.max(wallRect.top, wallRect.bottom - boxH));
    bx = bx.clamp(
        wallRect.left, math.max(wallRect.left, wallRect.right - btp.width - padH * 2));
    final bg = RRect.fromRectAndRadius(
        Rect.fromLTWH(bx, by, btp.width + padH * 2, boxH),
        const Radius.circular(6));
    canvas.drawRRect(
        bg, Paint()..color = scheme.inverseSurface.withValues(alpha: 0.92));
    btp.paint(canvas, Offset(bx + padH, by + padV));
  }

  void _paintHandles(Canvas canvas, Rect rect) {
    final handle = Paint()..color = scheme.primary;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white;
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    for (final ch in [
      Offset(rect.right, rect.center.dy), // width
      Offset(rect.center.dx, rect.top), // height
      Offset(rect.right, rect.top), // corner (both)
    ]) {
      canvas.drawCircle(ch, 8, shadow);
      canvas.drawCircle(ch, 7, handle);
      canvas.drawCircle(ch, 7, ring);
    }
  }

  @override
  bool shouldRepaint(covariant _ElevationPainter oldDelegate) => true;
}

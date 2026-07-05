import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wherein_kitchen/models/room.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';
import 'package:wherein_kitchen/providers/providers.dart';
import 'package:wherein_kitchen/widgets/iso_room_view.dart' show UnitLayout;
import 'package:wherein_kitchen/widgets/unit_colors.dart';

/// Top-down 2D floor-plan editor.
///
/// This is the easiest way to lay a kitchen out: drag rectangles around a
/// simple grid, resize them, rotate which way they face, set their height, and
/// stack wall units over base units. Everything writes to the same units the
/// 2.5D and 3D views read, so the plan stays in sync everywhere.
class RoomPlan2DScreen extends ConsumerStatefulWidget {
  const RoomPlan2DScreen({super.key, required this.room});

  final Room room;

  static const int gridCols = 14;
  static const int gridRows = 14;

  @override
  ConsumerState<RoomPlan2DScreen> createState() => _RoomPlan2DScreenState();
}

class _RoomPlan2DScreenState extends ConsumerState<RoomPlan2DScreen> {
  static const double _cell = 44;

  String? _selectedUnitId;
  final Map<String, UnitLayout> _localLayout = {};
  String? _draggingUnitId;
  double _grabDx = 0;
  double _grabDy = 0;
  bool _placedUnpositioned = false;

  final TransformationController _transform = TransformationController();
  // Number of units we last auto-framed for. Firestore can emit a partial
  // (cached) list first, so we re-frame whenever the count changes rather than
  // framing once on the first — possibly incomplete — emission.
  int _framedForCount = -1;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  List<StorageUnit> _unitsForRoom(List<StorageUnit> all) {
    final units = all.where((u) => u.roomId == widget.room.id).toList();
    units.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return units;
  }

  UnitLayout _layoutOf(StorageUnit unit) {
    final local = _localLayout[unit.id];
    if (local != null) return local;
    if (unit.hasLayoutPosition) {
      return (gx: unit.gx, gy: unit.gy, gw: unit.gw, gh: unit.gh);
    }
    return (gx: 0, gy: 0, gw: 2, gh: 2);
  }

  /// A copy of [unit] with any pending, not-yet-synced drag/resize merged in,
  /// so edits that go through updateUnit (rotate, mount, height) don't overwrite
  /// an optimistic layout with stale Firestore coordinates. Unplaced units are
  /// left untouched so their -1 sentinel is preserved.
  StorageUnit _mergeLocalLayout(StorageUnit unit) {
    final l = _localLayout[unit.id];
    return l == null
        ? unit
        : unit.copyWith(gx: l.gx, gy: l.gy, gw: l.gw, gh: l.gh);
  }

  bool _overlaps(UnitLayout a, UnitLayout b) =>
      a.gx < b.gx + b.gw &&
      b.gx < a.gx + a.gw &&
      a.gy < b.gy + b.gh &&
      b.gy < a.gy + a.gh;

  bool _bandsConflict(UnitMount a, UnitMount b) {
    final bothLower = a.occupiesLower && b.occupiesLower;
    final bothUpper = a.occupiesUpper && b.occupiesUpper;
    return bothLower || bothUpper;
  }

  bool _wouldOverlap(
      StorageUnit moving, UnitLayout candidate, List<StorageUnit> units) {
    for (final other in units) {
      if (other.id == moving.id) continue;
      if (!_bandsConflict(moving.mount, other.mount)) continue;
      if (_overlaps(candidate, _layoutOf(other))) return true;
    }
    return false;
  }

  ({int gx, int gy})? _findFreeCell(
      List<StorageUnit> units, int gw, int gh, UnitMount mount) {
    for (var gy = 0; gy <= RoomPlan2DScreen.gridRows - gh; gy++) {
      for (var gx = 0; gx <= RoomPlan2DScreen.gridCols - gw; gx++) {
        final candidate = (gx: gx, gy: gy, gw: gw, gh: gh);
        final free = !units.any((u) =>
            _bandsConflict(mount, u.mount) &&
            _overlaps(candidate, _layoutOf(u)));
        if (free) return (gx: gx, gy: gy);
      }
    }
    return null;
  }

  Future<void> _autoPlaceUnplaced(List<StorageUnit> units) async {
    if (units.isEmpty || _placedUnpositioned) return;
    final unplaced = units.where((u) => !u.hasLayoutPosition).toList();
    _placedUnpositioned = true;
    if (unplaced.isEmpty) return;

    final householdId = ref.read(householdIdProvider);
    if (householdId == null) return;
    final repo = ref.read(unitRepositoryProvider);
    final placed = [...units.where((u) => u.hasLayoutPosition)];

    for (final unit in unplaced) {
      final l = _layoutOf(unit);
      final spot = _findFreeCell(placed, l.gw, l.gh, unit.mount);
      if (spot == null) continue;
      setState(() =>
          _localLayout[unit.id] = (gx: spot.gx, gy: spot.gy, gw: l.gw, gh: l.gh));
      await repo.updateLayout(householdId, unit.id,
          gx: spot.gx, gy: spot.gy, gw: l.gw, gh: l.gh);
      placed.add(unit);
    }
  }

  StorageUnit? _unitAt(Offset local, List<StorageUnit> units) {
    // Prefer the smallest unit under the point, then the upper (wall) band, so
    // stacked units are both reachable.
    final hits = units.where((u) {
      final l = _layoutOf(u);
      var rect = Rect.fromLTWH(
          l.gx * _cell, l.gy * _cell, l.gw * _cell, l.gh * _cell);
      // Match the painter, which insets upper (wall) units so a base unit
      // beneath them stays tappable at the exposed edge.
      final isUpper = u.mount.occupiesUpper && !u.mount.occupiesLower;
      if (isUpper) rect = rect.deflate(_cell * 0.16);
      return rect.contains(local);
    }).toList();
    if (hits.isEmpty) return null;
    hits.sort((a, b) {
      final la = _layoutOf(a);
      final lb = _layoutOf(b);
      final areaA = la.gw * la.gh;
      final areaB = lb.gw * lb.gh;
      if (areaA != areaB) return areaA.compareTo(areaB);
      return (b.mount.occupiesUpper ? 1 : 0)
          .compareTo(a.mount.occupiesUpper ? 1 : 0);
    });
    // If the current selection is among hits, cycle to the next for stacks.
    if (_selectedUnitId != null) {
      final idx = hits.indexWhere((u) => u.id == _selectedUnitId);
      if (idx >= 0) return hits[(idx + 1) % hits.length];
    }
    return hits.first;
  }

  StorageUnit? _selected(List<StorageUnit> units) =>
      units.where((u) => u.id == _selectedUnitId).firstOrNull;

  /// Centers and zooms the view on the actual cabinets (with a little margin)
  /// instead of showing the whole empty grid on open.
  void _fitToUnits(
    List<StorageUnit> units,
    BoxConstraints constraints,
    double planW,
    double planH,
  ) {
    final w = constraints.maxWidth;
    final h = constraints.maxHeight;

    Rect target;
    if (units.isEmpty) {
      target = Rect.fromLTWH(0, 0, planW, planH);
    } else {
      var minX = double.infinity, minY = double.infinity;
      var maxX = -double.infinity, maxY = -double.infinity;
      for (final u in units) {
        final l = _layoutOf(u);
        minX = math.min(minX, l.gx * _cell);
        minY = math.min(minY, l.gy * _cell);
        maxX = math.max(maxX, (l.gx + l.gw) * _cell);
        maxY = math.max(maxY, (l.gy + l.gh) * _cell);
      }
      // One-and-a-half cells of breathing room, clamped to the plan bounds.
      const margin = _cell * 1.5;
      target = Rect.fromLTRB(
        math.max(0, minX - margin),
        math.max(0, minY - margin),
        math.min(planW, maxX + margin),
        math.min(planH, maxY + margin),
      );
    }

    final s = (math.min(w / target.width, h / target.height)).clamp(0.4, 3.0);
    final tx = (w - target.width * s) / 2 - target.left * s;
    final ty = (h - target.height * s) / 2 - target.top * s;
    _transform.value = Matrix4.identity()
      ..setEntry(0, 0, s)
      ..setEntry(1, 1, s)
      ..setEntry(0, 3, tx)
      ..setEntry(1, 3, ty);
  }

  Future<void> _persist(StorageUnit unit) async {
    final householdId = ref.read(householdIdProvider);
    final l = _localLayout[unit.id];
    if (householdId == null || l == null) return;
    await ref.read(unitRepositoryProvider).updateLayout(householdId, unit.id,
        gx: l.gx, gy: l.gy, gw: l.gw, gh: l.gh);
  }

  Future<void> _resize(List<StorageUnit> units, {int dw = 0, int dh = 0}) async {
    final unit = _selected(units);
    if (unit == null) return;
    final l = _layoutOf(unit);
    final gw = (l.gw + dw).clamp(1, RoomPlan2DScreen.gridCols - l.gx);
    final gh = (l.gh + dh).clamp(1, RoomPlan2DScreen.gridRows - l.gy);
    if (gw == l.gw && gh == l.gh) return;
    final candidate = (gx: l.gx, gy: l.gy, gw: gw, gh: gh);
    if (_wouldOverlap(unit, candidate, units)) return;
    final householdId = ref.read(householdIdProvider);
    if (householdId == null) return;
    setState(() => _localLayout[unit.id] = candidate);
    await ref.read(unitRepositoryProvider).updateLayout(householdId, unit.id,
        gx: l.gx, gy: l.gy, gw: gw, gh: gh);
  }

  Future<void> _rotate(List<StorageUnit> units) async {
    final unit = _selected(units);
    if (unit == null) return;
    await ref
        .read(unitRepositoryProvider)
        .updateUnit(_mergeLocalLayout(unit).copyWith(facing: (unit.facing + 1) % 4));
  }

  static const List<UnitMount> _mountOrder = [
    UnitMount.base,
    UnitMount.wall,
    UnitMount.tall,
    UnitMount.island,
    UnitMount.freestanding,
  ];

  Future<void> _cycleMount(List<StorageUnit> units) async {
    final unit = _selected(units);
    if (unit == null) return;
    final idx = _mountOrder.indexOf(unit.mount);
    final next = _mountOrder[(idx + 1) % _mountOrder.length];
    final updated = _mergeLocalLayout(unit).copyWith(mount: next);
    if (_wouldOverlap(updated, _layoutOf(unit), units)) {
      _snack('Another unit already sits at ${next.label} level here');
      return;
    }
    await ref.read(unitRepositoryProvider).updateUnit(updated);
  }

  Future<void> _adjustHeight(List<StorageUnit> units, int delta) async {
    final unit = _selected(units);
    if (unit == null) return;
    final h = (effectiveHeightCm(unit) + delta).clamp(20, 260);
    await ref
        .read(unitRepositoryProvider)
        .updateUnit(_mergeLocalLayout(unit).copyWith(heightCm: h));
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
          content: Text(message), duration: const Duration(seconds: 1)));
  }

  static int _defaultHeightCm(UnitMount mount) => switch (mount) {
        UnitMount.base => 90,
        UnitMount.island => 90,
        UnitMount.wall => 70,
        UnitMount.tall => 210,
        UnitMount.freestanding => 180,
      };

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

    final selectedGlobal =
        _selected(_unitsForRoom(unitsAsync.value ?? const []));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.room.name} · 2D plan',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      floatingActionButton: selectedGlobal != null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showEditor(null),
              icon: const Icon(Icons.add),
              label: const Text('Add cabinet'),
            ),
      body: unitsAsync.when(
        data: (allUnits) {
          final units = _unitsForRoom(allUnits);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _autoPlaceUnplaced(units);
          });

          final selected = _selected(units);
          const planW = RoomPlan2DScreen.gridCols * _cell;
          const planH = RoomPlan2DScreen.gridRows * _cell;

          return Stack(
            children: [
              LayoutBuilder(builder: (context, constraints) {
                if (_framedForCount != units.length &&
                    constraints.maxWidth.isFinite) {
                  _fitToUnits(units, constraints, planW, planH);
                  _framedForCount = units.length;
                }
                return InteractiveViewer(
                  transformationController: _transform,
                  constrained: false,
                  minScale: 0.4,
                  maxScale: 3,
                  panEnabled: _draggingUnitId == null,
                  boundaryMargin: const EdgeInsets.all(200),
                  child: SizedBox(
                    width: planW,
                    height: planH,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (d) {
                        final unit = _unitAt(d.localPosition, units);
                        setState(() => _selectedUnitId = unit?.id);
                      },
                      onLongPressStart: (d) {
                        final unit = _unitAt(d.localPosition, units);
                        if (unit == null) return;
                        final l = _layoutOf(unit);
                        _draggingUnitId = unit.id;
                        _grabDx = l.gx - d.localPosition.dx / _cell;
                        _grabDy = l.gy - d.localPosition.dy / _cell;
                        setState(() => _selectedUnitId = unit.id);
                      },
                      onLongPressMoveUpdate: (d) {
                        final unit = units
                            .where((u) => u.id == _draggingUnitId)
                            .firstOrNull;
                        if (unit == null) return;
                        final l = _layoutOf(unit);
                        final nx = (d.localPosition.dx / _cell + _grabDx)
                            .round()
                            .clamp(0, RoomPlan2DScreen.gridCols - l.gw);
                        final ny = (d.localPosition.dy / _cell + _grabDy)
                            .round()
                            .clamp(0, RoomPlan2DScreen.gridRows - l.gh);
                        if (nx == l.gx && ny == l.gy) return;
                        final candidate =
                            (gx: nx, gy: ny, gw: l.gw, gh: l.gh);
                        if (_wouldOverlap(unit, candidate, units)) return;
                        setState(() => _localLayout[unit.id] = candidate);
                      },
                      onLongPressEnd: (_) {
                        final unit = units
                            .where((u) => u.id == _draggingUnitId)
                            .firstOrNull;
                        _draggingUnitId = null;
                        if (unit != null) _persist(unit);
                      },
                      child: CustomPaint(
                        size: const Size(planW, planH),
                        painter: _Plan2DPainter(
                          units: units,
                          layoutOf: _layoutOf,
                          itemCountByUnit: itemCountByUnit,
                          selectedUnitId: _selectedUnitId,
                          cell: _cell,
                          scheme: Theme.of(context).colorScheme,
                        ),
                      ),
                    ),
                  ),
                );
              }),
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
                          .withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      selected == null
                          ? 'Tap to select · long-press & drag to move · pinch to zoom'
                          : 'Tap again to cycle stacked units',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ),
              ),
              if (selected != null)
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: MediaQuery.of(context).padding.bottom + 12,
                  child: _Plan2DToolbar(
                    unit: selected,
                    onWidthDown: () => _resize(units, dw: -1),
                    onWidthUp: () => _resize(units, dw: 1),
                    onDepthDown: () => _resize(units, dh: -1),
                    onDepthUp: () => _resize(units, dh: 1),
                    onRotate: () => _rotate(units),
                    onHeightDown: () => _adjustHeight(units, -10),
                    onHeightUp: () => _adjustHeight(units, 10),
                    onCycleMount: () => _cycleMount(units),
                    onEdit: () => _showEditor(selected),
                    onDelete: () => _confirmDelete(selected),
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

  Future<void> _showEditor(StorageUnit? existing) async {
    final householdId = ref.read(householdIdProvider);
    if (householdId == null) return;

    final nameController = TextEditingController(text: existing?.name ?? '');
    final defaultTemplate = kUnitTemplates[0];
    var type = existing?.type ?? defaultTemplate.type;
    var mount = existing?.mount ?? defaultTemplate.mount;
    var rows = existing?.rows ?? defaultTemplate.rows;
    var columns = existing?.columns ?? defaultTemplate.columns;
    var heightCm = existing != null
        ? effectiveHeightCm(existing)
        : defaultTemplate.heightCm;
    var heightTouched = existing?.heightCm != null;
    var gw = existing != null && existing.hasLayoutPosition
        ? existing.gw
        : defaultTemplate.gw;
    var gh = existing != null && existing.hasLayoutPosition
        ? existing.gh
        : defaultTemplate.gh;
    final local = existing != null ? _localLayout[existing.id] : null;
    if (local != null) {
      gw = local.gw;
      gh = local.gh;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(builder: (sheetContext, setSheetState) {
          Widget stepper({
            required String label,
            required int value,
            required int min,
            required int max,
            required void Function(int) onChanged,
            int step = 1,
          }) {
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
                  width: 44,
                  child: Text('$value',
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
                  Text(existing == null ? 'Add cabinet' : 'Edit ${existing.name}',
                      style: Theme.of(sheetContext).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  if (existing == null) ...[
                    Text('Quick templates',
                        style: Theme.of(sheetContext).textTheme.labelLarge),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: kUnitTemplates.map((tpl) {
                        return ActionChip(
                          avatar: const Icon(Icons.auto_awesome, size: 16),
                          label: Text(tpl.label),
                          onPressed: () => setSheetState(() {
                            type = tpl.type;
                            mount = tpl.mount;
                            rows = tpl.rows;
                            columns = tpl.columns;
                            heightCm = tpl.heightCm;
                            heightTouched = false;
                            gw = tpl.gw;
                            gh = tpl.gh;
                            if (nameController.text.trim().isEmpty &&
                                tpl.defaultName != null) {
                              nameController.text = tpl.defaultName!;
                            }
                          }),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: nameController,
                    autofocus: existing == null,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      hintText: 'Main Pantry, Left Cabinet…',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Type',
                      style: Theme.of(sheetContext).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: StorageUnitType.values.map((t) {
                      return ChoiceChip(
                        label: Text(t.label),
                        selected: type == t,
                        onSelected: (_) => setSheetState(() => type = t),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Text('Level (where it is mounted)',
                      style: Theme.of(sheetContext).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: UnitMount.values.map((m) {
                      return ChoiceChip(
                        label: Text(m.label),
                        selected: mount == m,
                        onSelected: (_) => setSheetState(() {
                          mount = m;
                          if (!heightTouched) heightCm = _defaultHeightCm(m);
                        }),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  if (type.holdsItems)
                    stepper(
                      label: 'Shelves',
                      value: rows,
                      min: 1,
                      max: kMaxShelfRows,
                      onChanged: (v) => setSheetState(() => rows = v),
                    ),
                  if (type.holdsItems)
                    stepper(
                      label: 'Doors / bays',
                      value: columns,
                      min: 1,
                      max: kMaxDoors,
                      onChanged: (v) => setSheetState(() => columns = v),
                    ),
                  stepper(
                    label: 'Height (cm)',
                    value: heightCm,
                    min: 20,
                    max: 260,
                    step: 5,
                    onChanged: (v) => setSheetState(() {
                      heightCm = v;
                      heightTouched = true;
                    }),
                  ),
                  stepper(
                    label: 'Width on floor',
                    value: gw,
                    min: 1,
                    max: RoomPlan2DScreen.gridCols,
                    onChanged: (v) => setSheetState(() => gw = v),
                  ),
                  stepper(
                    label: 'Depth on floor',
                    value: gh,
                    min: 1,
                    max: RoomPlan2DScreen.gridRows,
                    onChanged: (v) => setSheetState(() => gh = v),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () async {
                      final name = nameController.text.trim();
                      if (name.isEmpty) return;
                      Navigator.pop(sheetContext);
                      if (existing == null) {
                        await _createUnit(name, type, mount, rows, columns,
                            heightCm, gw, gh);
                      } else {
                        await _saveEdits(existing, name, type, mount, rows,
                            columns, heightCm, gw, gh);
                      }
                    },
                    child: Text(existing == null ? 'Add to room' : 'Save'),
                  ),
                  if (existing != null)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                          foregroundColor:
                              Theme.of(sheetContext).colorScheme.error),
                      onPressed: () async {
                        Navigator.pop(sheetContext);
                        await _confirmDelete(existing);
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete unit and its items'),
                    ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Future<void> _createUnit(String name, StorageUnitType type, UnitMount mount,
      int rows, int columns, int heightCm, int gw, int gh) async {
    final householdId = ref.read(householdIdProvider);
    if (householdId == null) return;
    final all = ref.read(unitsProvider).value ?? [];
    final units = _unitsForRoom(all);
    final unitRepo = ref.read(unitRepositoryProvider);
    final slotRepo = ref.read(slotRepositoryProvider);

    final unit = await unitRepo.createUnit(
      householdId: householdId,
      roomId: widget.room.id,
      name: name,
      type: type,
      rows: rows,
      columns: type.holdsItems ? columns : 1,
      sortOrder: units.fold<int>(-1, (m, u) => math.max(m, u.sortOrder)) + 1,
      mount: mount,
      heightCm: heightCm,
    );
    final spot = _findFreeCell(units, gw, gh, mount);
    // Don't default to (0,0) when the room is full — that stacks this unit on
    // top of an existing one. Leave it unplaced instead.
    if (spot != null) {
      await unitRepo.updateLayout(householdId, unit.id,
          gx: spot.gx, gy: spot.gy, gw: gw, gh: gh);
    }
    await slotRepo.ensureSlotsForUnit(householdId: householdId, unit: unit);

    if (!mounted) return;
    setState(() {
      _selectedUnitId = unit.id;
      if (spot != null) {
        _localLayout[unit.id] = (gx: spot.gx, gy: spot.gy, gw: gw, gh: gh);
      }
    });
    if (spot == null) {
      _snack('$name added, but the room is full — move or remove a unit');
    }
  }

  Future<void> _saveEdits(StorageUnit unit, String name, StorageUnitType type,
      UnitMount mount, int rows, int columns, int heightCm, int gw,
      int gh) async {
    final householdId = ref.read(householdIdProvider);
    if (householdId == null) return;
    final current = _layoutOf(unit);
    final clampedGw = gw.clamp(1, RoomPlan2DScreen.gridCols - current.gx);
    final clampedGh = gh.clamp(1, RoomPlan2DScreen.gridRows - current.gy);
    final newColumns = type.holdsItems ? columns : 1;
    final updated = unit.copyWith(
      name: name,
      type: type,
      mount: mount,
      rows: rows,
      columns: newColumns,
      heightCm: heightCm,
      gx: current.gx,
      gy: current.gy,
      gw: clampedGw,
      gh: clampedGh,
    );
    final all = ref.read(unitsProvider).value ?? [];
    final units = _unitsForRoom(all);
    if (_wouldOverlap(
        updated,
        (gx: current.gx, gy: current.gy, gw: clampedGw, gh: clampedGh),
        units)) {
      _snack('That size would overlap another unit');
      return;
    }
    await ref.read(unitRepositoryProvider).updateUnit(updated);
    setState(() => _localLayout[unit.id] =
        (gx: current.gx, gy: current.gy, gw: clampedGw, gh: clampedGh));
    if (rows != unit.rows ||
        newColumns != unit.columns ||
        type != unit.type) {
      await ref.read(slotRepositoryProvider).reconcileSlotsForUnit(
            householdId: householdId,
            unit: updated,
          );
    }
  }

  Future<void> _confirmDelete(StorageUnit unit) async {
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
    final householdId = ref.read(householdIdProvider);
    if (householdId == null) return;
    final slots = ref.read(slotsProvider).value ?? [];
    final slotIds =
        slots.where((s) => s.unitId == unit.id).map((s) => s.id).toList();
    await ref
        .read(itemRepositoryProvider)
        .deleteItemsForUnit(householdId, unit.id, slotIds);
    await ref
        .read(slotRepositoryProvider)
        .deleteSlotsForUnit(householdId, unit.id);
    await ref.read(unitRepositoryProvider).deleteUnit(householdId, unit.id);
    setState(() {
      _selectedUnitId = null;
      _localLayout.remove(unit.id);
    });
  }
}

// ---------------------------------------------------------------------------
// Painter
// ---------------------------------------------------------------------------

class _Plan2DPainter extends CustomPainter {
  _Plan2DPainter({
    required this.units,
    required this.layoutOf,
    required this.itemCountByUnit,
    required this.selectedUnitId,
    required this.cell,
    required this.scheme,
  });

  final List<StorageUnit> units;
  final UnitLayout Function(StorageUnit) layoutOf;
  final Map<String, int> itemCountByUnit;
  final String? selectedUnitId;
  final double cell;
  final ColorScheme scheme;

  Color _baseColor(StorageUnitType type) {
    return unitBaseColor(type, scheme);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Floor + grid.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color =
            Color.lerp(scheme.surfaceContainerHigh, scheme.primary, 0.04)!,
    );
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = scheme.outlineVariant.withValues(alpha: 0.5);
    for (var x = 0; x <= RoomPlan2DScreen.gridCols; x++) {
      canvas.drawLine(Offset(x * cell, 0),
          Offset(x * cell, RoomPlan2DScreen.gridRows * cell), gridPaint);
    }
    for (var y = 0; y <= RoomPlan2DScreen.gridRows; y++) {
      canvas.drawLine(Offset(0, y * cell),
          Offset(RoomPlan2DScreen.gridCols * cell, y * cell), gridPaint);
    }

    // Draw base/lower units first, then upper (wall) so stacks read clearly.
    final ordered = [...units]..sort((a, b) =>
        (a.mount.occupiesUpper ? 1 : 0).compareTo(b.mount.occupiesUpper ? 1 : 0));
    for (final unit in ordered) {
      _paintUnit(canvas, unit);
    }
  }

  void _paintUnit(Canvas canvas, StorageUnit unit) {
    final l = layoutOf(unit);
    final selected = unit.id == selectedUnitId;
    final isUpper = unit.mount.occupiesUpper && !unit.mount.occupiesLower;

    var rect = Rect.fromLTWH(
        l.gx * cell, l.gy * cell, l.gw * cell, l.gh * cell);
    // Inset upper (wall) units so a base unit beneath them stays visible.
    if (isUpper) rect = rect.deflate(cell * 0.16);
    final rrect =
        RRect.fromRectAndRadius(rect.deflate(2), const Radius.circular(6));

    if (unit.type == StorageUnitType.gap) {
      canvas.drawRRect(
          rrect, Paint()..color = scheme.outlineVariant.withValues(alpha: 0.18));
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2.4 : 1.2
          ..color = selected
              ? scheme.primary
              : scheme.outline.withValues(alpha: 0.5),
      );
      _paintLabel(canvas, unit, rect);
      return;
    }

    final fill = _baseColor(unit.type);
    canvas.drawRRect(
      rrect,
      Paint()..color = isUpper ? fill.withValues(alpha: 0.55) : fill,
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 3 : 1.4
        ..color = selected ? scheme.primary : Colors.black.withValues(alpha: 0.4),
    );

    _paintDoor(canvas, unit, rect);
    _paintLabel(canvas, unit, rect);
  }

  /// Thick edge + swing hint on the side the unit's doors face.
  void _paintDoor(Canvas canvas, StorageUnit unit, Rect rect) {
    // facing: 0 front(+y)=bottom, 1 right(+x)=right, 2 back(-y)=top, 3 left=left
    final (Offset a, Offset b) = switch (unit.facing % 4) {
      0 => (rect.bottomLeft, rect.bottomRight),
      1 => (rect.topRight, rect.bottomRight),
      2 => (rect.topLeft, rect.topRight),
      _ => (rect.topLeft, rect.bottomLeft),
    };
    final doorPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..color = Color.lerp(scheme.primary, Colors.black, 0.15)!;
    // Shrink slightly from the corners.
    final inset = Offset.lerp(a, b, 0.12)!;
    final inset2 = Offset.lerp(a, b, 0.88)!;
    canvas.drawLine(inset, inset2, doorPaint);
  }

  void _paintLabel(Canvas canvas, StorageUnit unit, Rect rect) {
    final count = itemCountByUnit[unit.id] ?? 0;
    final sub = unit.holdsItems
        ? '${facingLabel(unit.facing)} · ${effectiveHeightCm(unit)}cm'
              '${count > 0 ? ' · $count' : ''}'
        : unit.type.label;

    final name = TextPainter(
      text: TextSpan(
        text: unit.name,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.black.withValues(alpha: 0.85),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: rect.width - 8);

    final subP = TextPainter(
      text: TextSpan(
        text: sub,
        style: TextStyle(
            fontSize: 9.5, color: Colors.black.withValues(alpha: 0.6)),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: rect.width - 8);

    final cx = rect.center.dx;
    final totalH = name.height + subP.height;
    name.paint(
        canvas, Offset(cx - name.width / 2, rect.center.dy - totalH / 2));
    if (rect.height > 34) {
      subP.paint(
          canvas,
          Offset(cx - subP.width / 2, rect.center.dy - totalH / 2 + name.height));
    }
  }

  @override
  bool shouldRepaint(covariant _Plan2DPainter oldDelegate) => true;
}

// ---------------------------------------------------------------------------
// Toolbar
// ---------------------------------------------------------------------------

class _Plan2DToolbar extends StatelessWidget {
  const _Plan2DToolbar({
    required this.unit,
    required this.onWidthDown,
    required this.onWidthUp,
    required this.onDepthDown,
    required this.onDepthUp,
    required this.onRotate,
    required this.onHeightDown,
    required this.onHeightUp,
    required this.onCycleMount,
    required this.onEdit,
    required this.onDelete,
  });

  final StorageUnit unit;
  final VoidCallback onWidthDown;
  final VoidCallback onWidthUp;
  final VoidCallback onDepthDown;
  final VoidCallback onDepthUp;
  final VoidCallback onRotate;
  final VoidCallback onHeightDown;
  final VoidCallback onHeightUp;
  final VoidCallback onCycleMount;
  final VoidCallback onEdit;
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
              '${unit.name} · ${unit.mount.label} · ${effectiveHeightCm(unit)}cm',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              runSpacing: 4,
              children: [
                _Ctrl(label: 'W', onDown: onWidthDown, onUp: onWidthUp),
                _Ctrl(label: 'D', onDown: onDepthDown, onUp: onDepthUp),
                _Ctrl(
                    label: 'H',
                    onDown: onHeightDown,
                    onUp: onHeightUp),
                IconButton.filledTonal(
                  tooltip: 'Rotate (faces ${facingLabel(unit.facing)})',
                  icon: const Icon(Icons.rotate_90_degrees_cw_outlined,
                      size: 20),
                  onPressed: onRotate,
                ),
                IconButton.filledTonal(
                  tooltip: 'Change level (${unit.mount.label})',
                  icon: const Icon(Icons.layers_outlined, size: 20),
                  onPressed: onCycleMount,
                ),
                IconButton.filledTonal(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: onEdit,
                ),
                IconButton.filledTonal(
                  tooltip: 'Delete',
                  icon: Icon(Icons.delete_outline, size: 20, color: scheme.error),
                  onPressed: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Ctrl extends StatelessWidget {
  const _Ctrl({required this.label, required this.onDown, required this.onUp});

  final String label;
  final VoidCallback onDown;
  final VoidCallback onUp;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label ', style: Theme.of(context).textTheme.labelSmall),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            icon: const Icon(Icons.remove, size: 18),
            onPressed: onDown,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            icon: const Icon(Icons.add, size: 18),
            onPressed: onUp,
          ),
        ],
      ),
    );
  }
}

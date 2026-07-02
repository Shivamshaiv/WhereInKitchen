import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wherein_kitchen/models/room.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';
import 'package:wherein_kitchen/providers/providers.dart';
import 'package:wherein_kitchen/screens/room/room_3d_screen.dart';
import 'package:wherein_kitchen/screens/room/room_plan_2d_screen.dart';
import 'package:wherein_kitchen/screens/unit/unit_peek_screen.dart';
import 'package:wherein_kitchen/screens/unit/unit_view_screen.dart';
import 'package:wherein_kitchen/widgets/iso_room_view.dart';

/// 2.5D isometric room view.
/// View mode: tap a unit to open it.
/// Edit mode: drag units around the floor, tap to select, use the floating
/// toolbar or pencil sheet to resize height (shelves), width, and depth.
class RoomLayoutScreen extends ConsumerStatefulWidget {
  const RoomLayoutScreen({super.key, required this.room});

  final Room room;

  @override
  ConsumerState<RoomLayoutScreen> createState() => _RoomLayoutScreenState();
}

class _RoomLayoutScreenState extends ConsumerState<RoomLayoutScreen> {
  bool _editMode = false;
  String? _selectedUnitId;
  String? _draggingUnitId;

  // Local layout during drags so movement is instant (Firestore lags behind).
  final Map<String, UnitLayout> _localLayout = {};

  static const int _gridCols = 14;
  static const int _gridRows = 14;

  final TransformationController _transform = TransformationController();
  bool _didFitView = false;
  bool _placedUnpositioned = false;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _fitViewOnce(BoxConstraints constraints) {
    if (_didFitView || !constraints.maxWidth.isFinite) return;
    final canvas = IsoRoomView.canvasSize(_gridCols, _gridRows);
    final scale = math
        .min(constraints.maxWidth / canvas.width,
            constraints.maxHeight / canvas.height)
        .clamp(0.15, 1.0);
    final tx = (constraints.maxWidth - canvas.width * scale) / 2;
    final ty = (constraints.maxHeight - canvas.height * scale) / 2;
    _transform.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(0, 3, tx < 0 ? 0.0 : tx)
      ..setEntry(1, 3, ty < 0 ? 0.0 : ty);
    _didFitView = true;
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

  bool _overlaps(UnitLayout a, UnitLayout b) {
    return a.gx < b.gx + b.gw &&
        b.gx < a.gx + a.gw &&
        a.gy < b.gy + b.gh &&
        b.gy < a.gy + a.gh;
  }

  /// Two units only conflict if they share the same vertical band. This lets a
  /// wall (upper) cabinet sit on the same footprint as a base (lower) cabinet.
  bool _bandsConflict(UnitMount a, UnitMount b) {
    final bothLower = a.occupiesLower && b.occupiesLower;
    final bothUpper = a.occupiesUpper && b.occupiesUpper;
    return bothLower || bothUpper;
  }

  bool _layoutWouldOverlap(
    StorageUnit moving,
    UnitLayout candidate,
    List<StorageUnit> units,
  ) {
    for (final other in units) {
      if (other.id == moving.id) continue;
      if (!_bandsConflict(moving.mount, other.mount)) continue;
      if (_overlaps(candidate, _layoutOf(other))) return true;
    }
    return false;
  }

  bool _wouldOverlap(
    StorageUnit moving,
    int gx,
    int gy,
    List<StorageUnit> units,
  ) {
    final layout = _layoutOf(moving);
    return _layoutWouldOverlap(
      moving,
      (gx: gx, gy: gy, gw: layout.gw, gh: layout.gh),
      units,
    );
  }

  /// First non-overlapping cell that fits [gw]×[gh].
  ///
  /// Candidates are ordered so the most visible spot wins: toward the front
  /// (bottom of the iso diamond, larger gx+gy) and horizontally centered
  /// (smaller |gx-gy|). This keeps new units clear of the top toolbar overlay
  /// instead of hiding them in the back corner.
  ({int gx, int gy})? _findFreeCell(
    List<StorageUnit> units,
    int gw,
    int gh,
    UnitMount mount,
  ) {
    final cells = <({int gx, int gy})>[];
    for (var gy = 0; gy <= _gridRows - gh; gy++) {
      for (var gx = 0; gx <= _gridCols - gw; gx++) {
        cells.add((gx: gx, gy: gy));
      }
    }

    int cost(({int gx, int gy}) c) {
      final front = (_gridCols + _gridRows) - (c.gx + c.gy);
      final offCenter = (c.gx - c.gy).abs();
      return front + offCenter;
    }

    cells.sort((a, b) => cost(a).compareTo(cost(b)));

    for (final c in cells) {
      final candidate = (gx: c.gx, gy: c.gy, gw: gw, gh: gh);
      final free = !units.any((u) =>
          _bandsConflict(mount, u.mount) &&
          _overlaps(candidate, _layoutOf(u)));
      if (free) return c;
    }
    return null;
  }

  /// Only assign positions to units that have never been placed.
  Future<void> _autoPlaceUnplaced(List<StorageUnit> units) async {
    if (units.isEmpty || _placedUnpositioned) return;

    final unplaced = units.where((u) => !u.hasLayoutPosition).toList();
    if (unplaced.isEmpty) {
      _placedUnpositioned = true;
      return;
    }

    _placedUnpositioned = true;
    final householdId = ref.read(householdIdProvider);
    if (householdId == null) return;

    final repo = ref.read(unitRepositoryProvider);
    final placed = [...units.where((u) => u.hasLayoutPosition)];

    for (final unit in unplaced) {
      final layout = _layoutOf(unit);
      final spot = _findFreeCell(placed, layout.gw, layout.gh, unit.mount);
      if (spot == null) continue;

      final newLayout =
          (gx: spot.gx, gy: spot.gy, gw: layout.gw, gh: layout.gh);
      setState(() => _localLayout[unit.id] = newLayout);
      await repo.updateLayout(
        householdId,
        unit.id,
        gx: spot.gx,
        gy: spot.gy,
        gw: layout.gw,
        gh: layout.gh,
      );
      placed.add(unit);
    }
  }

  Future<void> _persistLayout(StorageUnit unit) async {
    final householdId = ref.read(householdIdProvider);
    final layout = _localLayout[unit.id];
    if (householdId == null || layout == null) return;
    await ref.read(unitRepositoryProvider).updateLayout(
          householdId,
          unit.id,
          gx: layout.gx,
          gy: layout.gy,
          gw: layout.gw,
          gh: layout.gh,
        );
  }

  void _moveUnitTo(StorageUnit unit, int gx, int gy, List<StorageUnit> units) {
    final current = _localLayout[unit.id] ?? _layoutOf(unit);
    final clampedGx = gx.clamp(0, _gridCols - current.gw);
    final clampedGy = gy.clamp(0, _gridRows - current.gh);
    if (clampedGx == current.gx && clampedGy == current.gy) return;
    if (_wouldOverlap(unit, clampedGx, clampedGy, units)) return;

    setState(() {
      _localLayout[unit.id] =
          (gx: clampedGx, gy: clampedGy, gw: current.gw, gh: current.gh);
    });
  }

  StorageUnit? _selectedUnit(List<StorageUnit> units) {
    if (_selectedUnitId == null) return null;
    return units.where((u) => u.id == _selectedUnitId).firstOrNull;
  }

  Future<void> _adjustSelectedRows(List<StorageUnit> units, int delta) async {
    final unit = _selectedUnit(units);
    if (unit == null) return;
    final rows = (unit.rows + delta).clamp(1, kIsoMaxShelfRows);
    if (rows == unit.rows) return;

    final householdId = ref.read(householdIdProvider);
    if (householdId == null) return;

    final updated = unit.copyWith(rows: rows);
    await ref.read(unitRepositoryProvider).updateUnit(updated);
    await ref.read(slotRepositoryProvider).reconcileSlotsForUnit(
          householdId: householdId,
          unit: updated,
        );
    if (mounted) setState(() {});
  }

  Future<void> _adjustSelectedHeight(
      List<StorageUnit> units, int delta) async {
    final unit = _selectedUnit(units);
    if (unit == null) return;
    final h = (effectiveHeightCm(unit) + delta).clamp(20, 260);
    if (h == effectiveHeightCm(unit)) return;
    await ref
        .read(unitRepositoryProvider)
        .updateUnit(unit.copyWith(heightCm: h));
    if (mounted) setState(() {});
  }

  Future<void> _adjustSelectedWidth(List<StorageUnit> units, int delta) async {
    final unit = _selectedUnit(units);
    if (unit == null) return;
    final layout = _layoutOf(unit);
    final gw = (layout.gw + delta).clamp(1, _gridCols - layout.gx);
    if (gw == layout.gw) return;
    if (_layoutWouldOverlap(
      unit,
      (gx: layout.gx, gy: layout.gy, gw: gw, gh: layout.gh),
      units,
    )) {
      return;
    }

    final householdId = ref.read(householdIdProvider);
    if (householdId == null) return;

    setState(() {
      _localLayout[unit.id] =
          (gx: layout.gx, gy: layout.gy, gw: gw, gh: layout.gh);
    });
    await ref.read(unitRepositoryProvider).updateLayout(
          householdId,
          unit.id,
          gx: layout.gx,
          gy: layout.gy,
          gw: gw,
          gh: layout.gh,
        );
  }

  Future<void> _adjustSelectedDepth(List<StorageUnit> units, int delta) async {
    final unit = _selectedUnit(units);
    if (unit == null) return;
    final layout = _layoutOf(unit);
    final gh = (layout.gh + delta).clamp(1, _gridRows - layout.gy);
    if (gh == layout.gh) return;
    if (_layoutWouldOverlap(
      unit,
      (gx: layout.gx, gy: layout.gy, gw: layout.gw, gh: gh),
      units,
    )) {
      return;
    }

    final householdId = ref.read(householdIdProvider);
    if (householdId == null) return;

    setState(() {
      _localLayout[unit.id] =
          (gx: layout.gx, gy: layout.gy, gw: layout.gw, gh: gh);
    });
    await ref.read(unitRepositoryProvider).updateLayout(
          householdId,
          unit.id,
          gx: layout.gx,
          gy: layout.gy,
          gw: layout.gw,
          gh: gh,
        );
  }

  static const List<UnitMount> _mountOrder = [
    UnitMount.base,
    UnitMount.wall,
    UnitMount.tall,
    UnitMount.island,
    UnitMount.freestanding,
  ];

  Future<void> _adjustSelectedMount(
      List<StorageUnit> units, int delta) async {
    final unit = _selectedUnit(units);
    if (unit == null) return;
    final idx = _mountOrder.indexOf(unit.mount);
    final nidx = (idx + delta).clamp(0, _mountOrder.length - 1);
    if (nidx == idx) return;

    final updated = unit.copyWith(mount: _mountOrder[nidx]);
    if (_layoutWouldOverlap(updated, _layoutOf(unit), units)) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(
                'Another unit is already at ${updated.mount.label} level here',
              ),
            ),
          );
      }
      return;
    }

    await ref.read(unitRepositoryProvider).updateUnit(updated);
    if (mounted) setState(() {});
  }

  /// Quarter-turn the selected unit's facing; its footprint stays fixed.
  Future<void> _rotateSelected(List<StorageUnit> units, int delta) async {
    final unit = _selectedUnit(units);
    if (unit == null) return;
    final updated = unit.copyWith(facing: (unit.facing + delta + 4) % 4);
    await ref.read(unitRepositoryProvider).updateUnit(updated);
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content:
                Text('${unit.name} now faces ${facingLabel(updated.facing)}'),
            duration: const Duration(seconds: 1),
          ),
        );
    }
  }

  /// Zooms into the tapped unit and reveals a peek of what's inside.
  void _openUnit(StorageUnit unit, Offset globalPosition) {
    if (!unit.holdsItems) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text('${unit.name} · ${unit.type.label}')),
        );
      return;
    }

    final size = MediaQuery.of(context).size;
    final alignment = Alignment(
      (globalPosition.dx / size.width) * 2 - 1,
      (globalPosition.dy / size.height) * 2 - 1,
    );

    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 380),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, __, ___) => UnitPeekScreen(unit: unit),
        transitionsBuilder: (_, anim, __, child) {
          final curved =
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.35, end: 1.0).animate(curved),
              alignment: alignment,
              child: child,
            ),
          );
        },
      ),
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
        title: Text(widget.room.name),
        actions: [
          IconButton(
            tooltip: '2D floor plan',
            icon: const Icon(Icons.grid_on_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RoomPlan2DScreen(room: widget.room),
                ),
              );
            },
          ),
          IconButton(
            tooltip: '3D walk-around view',
            icon: const Icon(Icons.threed_rotation),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => Room3DScreen(room: widget.room),
                ),
              );
            },
          ),
          if (_editMode && _selectedUnitId != null)
            IconButton(
              tooltip: 'Edit unit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () {
                final units = unitsAsync.value ?? [];
                final unit = _selectedUnit(units);
                if (unit != null) _showUnitEditor(unit);
              },
            ),
          IconButton(
            tooltip: _editMode ? 'Done editing' : 'Edit layout',
            icon: Icon(_editMode ? Icons.check : Icons.view_in_ar_outlined),
            onPressed: () {
              setState(() {
                _editMode = !_editMode;
                _selectedUnitId = null;
                _draggingUnitId = null;
              });
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showUnitEditor(null),
        icon: const Icon(Icons.add),
        label: const Text('Add cabinet / storage'),
      ),
      body: unitsAsync.when(
        data: (allUnits) {
          final units = _unitsForRoom(allUnits);

          WidgetsBinding.instance.addPostFrameCallback((_) {
            _autoPlaceUnplaced(units);
          });

          if (units.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.view_in_ar_outlined, size: 64),
                  const SizedBox(height: 16),
                  const Text('This room is empty'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _showUnitEditor(null),
                    icon: const Icon(Icons.add),
                    label: const Text('Add first storage unit'),
                  ),
                ],
              ),
            );
          }

          final selected = _selectedUnit(units);

          final isoView = IsoRoomView(
            units: units,
            layoutOf: _layoutOf,
            itemCountByUnit: itemCountByUnit,
            editMode: _editMode,
            gridCols: _gridCols,
            gridRows: _gridRows,
            selectedUnitId: _selectedUnitId,
            onTapUnit: (unit, globalPosition) {
              if (_editMode) {
                setState(() => _selectedUnitId = unit.id);
              } else {
                _openUnit(unit, globalPosition);
              }
            },
            onTapEmpty: () {
              if (_editMode) {
                setState(() => _selectedUnitId = null);
              }
            },
            onDragStart: (unit) {
              setState(() => _draggingUnitId = unit.id);
            },
            onMoveUnit: (unit, gx, gy) => _moveUnitTo(unit, gx, gy, units),
            onDragEnd: (unit) {
              setState(() => _draggingUnitId = null);
              _persistLayout(unit);
            },
          );

          return Stack(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  _fitViewOnce(constraints);
                  return InteractiveViewer(
                    transformationController: _transform,
                    constrained: false,
                    minScale: 0.15,
                    maxScale: 3.5,
                    panEnabled: _draggingUnitId == null,
                    boundaryMargin: const EdgeInsets.all(280),
                    child: isoView,
                  );
                },
              ),
              if (_editMode && selected != null)
                Positioned(
                  left: 12,
                  right: 12,
                  top: 8,
                  child: _SelectedUnitToolbar(
                    unit: selected,
                    layout: _layoutOf(selected),
                    onDecreaseShelves: () => _adjustSelectedRows(units, -1),
                    onIncreaseShelves: () => _adjustSelectedRows(units, 1),
                    onDecreaseHeight: () => _adjustSelectedHeight(units, -10),
                    onIncreaseHeight: () => _adjustSelectedHeight(units, 10),
                    onDecreaseWidth: () => _adjustSelectedWidth(units, -1),
                    onIncreaseWidth: () => _adjustSelectedWidth(units, 1),
                    onDecreaseDepth: () => _adjustSelectedDepth(units, -1),
                    onIncreaseDepth: () => _adjustSelectedDepth(units, 1),
                    onLower: () => _adjustSelectedMount(units, -1),
                    onRaise: () => _adjustSelectedMount(units, 1),
                    onRotate: () => _rotateSelected(units, 1),
                    onRename: () => _showUnitEditor(selected),
                    onDelete: () => _confirmDeleteUnit(selected),
                  ),
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
      bottomNavigationBar: _editMode
          ? Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: Text(
                _selectedUnitId == null
                    ? 'Tap to select · long-press & drag to move · pinch to zoom'
                    : 'Toolbar: shelves = height · width/depth = floor · level = base/wall/tall',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          : null,
    );
  }

  Future<void> _showUnitEditor(StorageUnit? existing) async {
    final householdId = ref.read(householdIdProvider);
    if (householdId == null) return;

    final nameController = TextEditingController(text: existing?.name ?? '');
    // New units default to the first template (big 2-door cabinet).
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
    final localExisting =
        existing != null ? _localLayout[existing.id] : null;
    if (localExisting != null) {
      gw = localExisting.gw;
      gh = localExisting.gh;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final maxGw = existing != null
                ? _gridCols - (_localLayout[existing.id]?.gx ?? existing.gx)
                : _gridCols;
            final maxGh = existing != null
                ? _gridRows - (_localLayout[existing.id]?.gy ?? existing.gy)
                : _gridRows;

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
                        style: Theme.of(sheetContext).textTheme.labelLarge),
                  ),
                  IconButton(
                    onPressed: value > min
                        ? () => onChanged(math.max(min, value - step))
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(
                      '$value',
                      textAlign: TextAlign.center,
                      style: Theme.of(sheetContext).textTheme.titleMedium,
                    ),
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
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom +
                    MediaQuery.of(sheetContext).padding.bottom +
                    20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                  Text(
                    existing == null
                        ? 'Add storage unit'
                        : 'Edit ${existing.name}',
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
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
                          // Follow the mount's typical height until the user
                          // dials in their own.
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
                      max: kIsoMaxShelfRows,
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
                    value: gw.clamp(1, maxGw),
                    min: 1,
                    max: maxGw,
                    onChanged: (v) => setSheetState(() => gw = v),
                  ),
                  stepper(
                    label: 'Depth on floor',
                    value: gh.clamp(1, maxGh),
                    min: 1,
                    max: maxGh,
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
                        await _saveUnitEdits(existing, name, type, mount, rows,
                            columns, heightCm, gw, gh);
                      }
                    },
                    child: Text(existing == null ? 'Add to room' : 'Save'),
                  ),
                  if (existing != null)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor:
                            Theme.of(sheetContext).colorScheme.error,
                      ),
                      onPressed: () async {
                        Navigator.pop(sheetContext);
                        await _confirmDeleteUnit(existing);
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete unit and its items'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static int _defaultHeightCm(UnitMount mount) => switch (mount) {
        UnitMount.base => 90,
        UnitMount.island => 90,
        UnitMount.wall => 70,
        UnitMount.tall => 210,
        UnitMount.freestanding => 180,
      };

  Future<void> _createUnit(
    String name,
    StorageUnitType type,
    UnitMount mount,
    int rows,
    int columns,
    int heightCm,
    int gw,
    int gh,
  ) async {
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
      sortOrder: units.length,
      mount: mount,
      heightCm: heightCm,
    );

    final spot = _findFreeCell(units, gw, gh, mount);
    final gx = spot?.gx ?? 0;
    final gy = spot?.gy ?? 0;

    await unitRepo.updateLayout(
      householdId,
      unit.id,
      gx: gx,
      gy: gy,
      gw: gw,
      gh: gh,
    );
    await slotRepo.ensureSlotsForUnit(householdId: householdId, unit: unit);

    final placed = unit.copyWith(gx: gx, gy: gy, gw: gw, gh: gh);

    if (!mounted) return;
    setState(() {
      _editMode = true;
      _selectedUnitId = unit.id;
      _localLayout[unit.id] = (gx: gx, gy: gy, gw: gw, gh: gh);
    });

    final message = spot == null
        ? '$name added — room is crowded, zoom out to find it'
        : (unit.holdsItems
            ? '$name added — drag it into place'
            : '$name added');

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 5),
          action: unit.holdsItems
              ? SnackBarAction(
                  label: 'Add items',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => UnitViewScreen(unit: placed),
                      ),
                    );
                  },
                )
              : null,
        ),
      );
  }

  Future<void> _saveUnitEdits(
    StorageUnit unit,
    String name,
    StorageUnitType type,
    UnitMount mount,
    int rows,
    int columns,
    int heightCm,
    int gw,
    int gh,
  ) async {
    final householdId = ref.read(householdIdProvider);
    if (householdId == null) return;

    final current = _layoutOf(unit);
    final clampedGw = gw.clamp(1, _gridCols - current.gx);
    final clampedGh = gh.clamp(1, _gridRows - current.gy);
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
    if (_layoutWouldOverlap(
      updated,
      (gx: current.gx, gy: current.gy, gw: clampedGw, gh: clampedGh),
      units,
    )) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('That size would overlap another unit'),
          ),
        );
      }
      return;
    }

    await ref.read(unitRepositoryProvider).updateUnit(updated);
    setState(() {
      _localLayout[unit.id] = (
        gx: current.gx,
        gy: current.gy,
        gw: clampedGw,
        gh: clampedGh,
      );
    });

    if (rows != unit.rows ||
        newColumns != unit.columns ||
        type != unit.type) {
      await ref.read(slotRepositoryProvider).reconcileSlotsForUnit(
            householdId: householdId,
            unit: updated,
          );
    }
  }

  Future<void> _confirmDeleteUnit(StorageUnit unit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${unit.name}?'),
        content: const Text(
            'This removes the unit, its shelves, and every item stored in it. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
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

    final itemRepo = ref.read(itemRepositoryProvider);
    await itemRepo.deleteItemsForUnit(householdId, unit.id, slotIds);
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

class _SelectedUnitToolbar extends StatelessWidget {
  const _SelectedUnitToolbar({
    required this.unit,
    required this.layout,
    required this.onDecreaseShelves,
    required this.onIncreaseShelves,
    required this.onDecreaseHeight,
    required this.onIncreaseHeight,
    required this.onDecreaseWidth,
    required this.onIncreaseWidth,
    required this.onDecreaseDepth,
    required this.onIncreaseDepth,
    required this.onLower,
    required this.onRaise,
    required this.onRotate,
    required this.onRename,
    required this.onDelete,
  });

  final StorageUnit unit;
  final UnitLayout layout;
  final VoidCallback onDecreaseShelves;
  final VoidCallback onIncreaseShelves;
  final VoidCallback onDecreaseHeight;
  final VoidCallback onIncreaseHeight;
  final VoidCallback onDecreaseWidth;
  final VoidCallback onIncreaseWidth;
  final VoidCallback onDecreaseDepth;
  final VoidCallback onIncreaseDepth;
  final VoidCallback onLower;
  final VoidCallback onRaise;
  final VoidCallback onRotate;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      elevation: 6,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(14),
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              unit.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              runSpacing: 4,
              children: [
                _ToolbarControl(
                  label: 'Level',
                  value: unit.mount.label,
                  decreaseIcon: Icons.keyboard_arrow_down,
                  increaseIcon: Icons.keyboard_arrow_up,
                  onDecrease: onLower,
                  onIncrease: onRaise,
                ),
                if (unit.holdsItems)
                  _ToolbarControl(
                    label: 'Shelves',
                    value: '${unit.rows}',
                    onDecrease: onDecreaseShelves,
                    onIncrease: onIncreaseShelves,
                  ),
                _ToolbarControl(
                  label: 'Height',
                  value: '${effectiveHeightCm(unit)}',
                  onDecrease: onDecreaseHeight,
                  onIncrease: onIncreaseHeight,
                ),
                _ToolbarControl(
                  label: 'Width',
                  value: '${layout.gw}',
                  onDecrease: onDecreaseWidth,
                  onIncrease: onIncreaseWidth,
                ),
                _ToolbarControl(
                  label: 'Depth',
                  value: '${layout.gh}',
                  onDecrease: onDecreaseDepth,
                  onIncrease: onIncreaseDepth,
                ),
                IconButton.filledTonal(
                  tooltip: 'Rotate (faces ${facingLabel(unit.facing)})',
                  icon: const Icon(Icons.rotate_90_degrees_cw_outlined,
                      size: 20),
                  onPressed: onRotate,
                ),
                IconButton.filledTonal(
                  tooltip: 'Rename & more',
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: onRename,
                ),
                IconButton.filledTonal(
                  tooltip: 'Delete',
                  icon: Icon(Icons.delete_outline,
                      size: 20, color: scheme.error),
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

class _ToolbarControl extends StatelessWidget {
  const _ToolbarControl({
    required this.label,
    required this.value,
    required this.onDecrease,
    required this.onIncrease,
    this.decreaseIcon = Icons.remove,
    this.increaseIcon = Icons.add,
  });

  final String label;
  final String value;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final IconData decreaseIcon;
  final IconData increaseIcon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: Icon(decreaseIcon, size: 18),
            onPressed: onDecrease,
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: Icon(increaseIcon, size: 18),
            onPressed: onIncrease,
          ),
        ],
      ),
    );
  }
}

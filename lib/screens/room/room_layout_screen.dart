import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wherein_kitchen/models/room.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';
import 'package:wherein_kitchen/providers/providers.dart';
import 'package:wherein_kitchen/screens/unit/unit_view_screen.dart';
import 'package:wherein_kitchen/widgets/iso_room_view.dart';

/// 2.5D isometric room view.
/// View mode: tap a unit to open it.
/// Edit mode: drag units around the floor, tap to select, pencil to edit,
/// footprint (width/depth) adjusted in the edit sheet.
class RoomLayoutScreen extends ConsumerStatefulWidget {
  const RoomLayoutScreen({super.key, required this.room});

  final Room room;

  @override
  ConsumerState<RoomLayoutScreen> createState() => _RoomLayoutScreenState();
}

class _RoomLayoutScreenState extends ConsumerState<RoomLayoutScreen> {
  bool _editMode = false;
  String? _selectedUnitId;

  // Local layout during drags so movement is instant (Firestore lags behind).
  final Map<String, UnitLayout> _localLayout = {};

  // Large grid so complex, real-world kitchen layouts fit. The room canvas
  // grows past the screen and is pan/zoomable rather than being shrunk.
  static const int _gridCols = 10;
  static const int _gridRows = 10;

  final TransformationController _transform = TransformationController();
  bool _didFitView = false;

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
        .clamp(0.2, 1.0);
    final tx = (constraints.maxWidth - canvas.width * scale) / 2;
    final ty = (constraints.maxHeight - canvas.height * scale) / 2;
    // Compose translate * scale directly to avoid deprecated Matrix4 helpers.
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

  bool _rearranged = false;

  bool _overlaps(UnitLayout a, UnitLayout b) {
    return a.gx < b.gx + b.gw &&
        b.gx < a.gx + a.gw &&
        a.gy < b.gy + b.gh &&
        b.gy < a.gy + a.gh;
  }

  bool _anyOverlap(List<StorageUnit> units) {
    for (var i = 0; i < units.length; i++) {
      for (var j = i + 1; j < units.length; j++) {
        if (_overlaps(_layoutOf(units[i]), _layoutOf(units[j]))) {
          return true;
        }
      }
    }
    return false;
  }

  /// Places units along the room walls like a real kitchen:
  /// back wall left-to-right, then left wall, then right wall.
  Future<void> _autoArrange(List<StorageUnit> units) async {
    final householdId = ref.read(householdIdProvider);
    if (householdId == null) return;

    final repo = ref.read(unitRepositoryProvider);
    // Walk the perimeter like a real kitchen: back wall, then side walls,
    // then front wall, leaving the centre open as floor space.
    final spots = <({int gx, int gy})>[];
    for (var x = 0; x <= _gridCols - 2; x += 2) {
      spots.add((gx: x, gy: 0));
    }
    for (var y = 2; y <= _gridRows - 2; y += 2) {
      spots.add((gx: 0, gy: y));
      spots.add((gx: _gridCols - 2, gy: y));
    }
    for (var x = 2; x <= _gridCols - 4; x += 2) {
      spots.add((gx: x, gy: _gridRows - 2));
    }

    for (var i = 0; i < units.length; i++) {
      final spot = i < spots.length
          ? spots[i]
          : (
              gx: 2 + ((i - spots.length) % (_gridCols ~/ 2 - 1)) * 2,
              gy: 2 + ((i - spots.length) ~/ (_gridCols ~/ 2 - 1)) * 2,
            );
      final layout = _layoutOf(units[i]);
      setState(() {
        _localLayout[units[i].id] =
            (gx: spot.gx, gy: spot.gy, gw: layout.gw, gh: layout.gh);
      });
      await repo.updateLayout(householdId, units[i].id,
          gx: spot.gx, gy: spot.gy, gw: layout.gw, gh: layout.gh);
    }
  }

  Future<void> _autoPlaceUnplaced(List<StorageUnit> units) async {
    if (units.isEmpty || _rearranged) return;

    final needsPlacement = units.any((u) => !u.hasLayoutPosition);
    // Also rescue layouts migrated from the old flat grid that overlap.
    if (needsPlacement || _anyOverlap(units)) {
      _rearranged = true;
      await _autoArrange(units);
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

  void _handleDrag(StorageUnit unit, int dgx, int dgy) {
    final current = _localLayout[unit.id] ?? _layoutOf(unit);
    final ngx = (current.gx + dgx).clamp(0, _gridCols - current.gw);
    final ngy = (current.gy + dgy).clamp(0, _gridRows - current.gh);
    if (ngx == current.gx && ngy == current.gy) return;
    setState(() {
      _localLayout[unit.id] =
          (gx: ngx, gy: ngy, gw: current.gw, gh: current.gh);
    });
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
          if (_editMode && _selectedUnitId != null)
            IconButton(
              tooltip: 'Edit unit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () {
                final units = unitsAsync.value ?? [];
                final unit =
                    units.where((u) => u.id == _selectedUnitId).firstOrNull;
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

          final isoView = IsoRoomView(
            units: units,
            layoutOf: _layoutOf,
            itemCountByUnit: itemCountByUnit,
            editMode: _editMode,
            gridCols: _gridCols,
            gridRows: _gridRows,
            selectedUnitId: _selectedUnitId,
            onTapUnit: (unit) {
              if (_editMode) {
                setState(() => _selectedUnitId = unit.id);
              } else {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => UnitViewScreen(unit: unit),
                  ),
                );
              }
            },
            onTapEmpty: () {
              if (_editMode) {
                setState(() => _selectedUnitId = null);
              }
            },
            onDragUnit: _handleDrag,
            onDragEnd: _persistLayout,
          );

          // Large room canvas that overflows the screen. Both modes get
          // pan + pinch-zoom; unit dragging in edit mode uses long-press so
          // it never fights the pan gesture.
          return LayoutBuilder(
            builder: (context, constraints) {
              _fitViewOnce(constraints);
              return InteractiveViewer(
                transformationController: _transform,
                constrained: false,
                minScale: 0.2,
                maxScale: 3.0,
                boundaryMargin: const EdgeInsets.all(240),
                child: isoView,
              );
            },
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
                    ? 'Tap to select · long-press a unit and drag to move it · pinch to zoom'
                    : 'Long-press & drag to move · pinch to zoom · pencil (top right) renames & resizes',
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
    var type = existing?.type ?? StorageUnitType.shelf;
    var rows = existing?.rows ?? 4;
    var gw = existing != null && existing.hasLayoutPosition ? existing.gw : 2;
    var gh = existing != null && existing.hasLayoutPosition ? existing.gh : 2;
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
            Widget stepper({
              required String label,
              required int value,
              required int min,
              required int max,
              required void Function(int) onChanged,
            }) {
              return Row(
                children: [
                  Text(label,
                      style: Theme.of(sheetContext).textTheme.labelLarge),
                  const Spacer(),
                  IconButton(
                    onPressed:
                        value > min ? () => onChanged(value - 1) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  SizedBox(
                    width: 28,
                    child: Text(
                      '$value',
                      textAlign: TextAlign.center,
                      style: Theme.of(sheetContext).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    onPressed:
                        value < max ? () => onChanged(value + 1) : null,
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
                  const SizedBox(height: 12),
                  stepper(
                    label: 'Shelves / rows inside',
                    value: rows,
                    min: 1,
                    max: 8,
                    onChanged: (v) => setSheetState(() => rows = v),
                  ),
                  stepper(
                    label: 'Width on floor',
                    value: gw,
                    min: 1,
                    max: _gridCols,
                    onChanged: (v) => setSheetState(() => gw = v),
                  ),
                  stepper(
                    label: 'Depth on floor',
                    value: gh,
                    min: 1,
                    max: _gridRows,
                    onChanged: (v) => setSheetState(() => gh = v),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () async {
                      final name = nameController.text.trim();
                      if (name.isEmpty) return;
                      Navigator.pop(sheetContext);
                      if (existing == null) {
                        await _createUnit(name, type, rows, gw, gh);
                      } else {
                        await _saveUnitEdits(
                            existing, name, type, rows, gw, gh);
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
            );
          },
        );
      },
    );
  }

  Future<void> _createUnit(
    String name,
    StorageUnitType type,
    int rows,
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
      columns: 1,
      sortOrder: units.length,
    );
    // Drop it near the front of the room; the user drags it into place.
    final placed = unit.copyWith(
      gx: ((_gridCols - gw) / 2).floor().clamp(0, _gridCols - gw),
      gy: _gridRows - gh,
      gw: gw,
      gh: gh,
    );
    await unitRepo.updateLayout(householdId, unit.id,
        gx: placed.gx, gy: placed.gy, gw: placed.gw, gh: placed.gh);
    await slotRepo.ensureSlotsForUnit(householdId: householdId, unit: unit);

    if (!mounted) return;
    setState(() {
      _editMode = true;
      _selectedUnitId = unit.id;
    });

    // Offer to start filling it right away.
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('$name added — drag it into place'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Add items',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => UnitViewScreen(unit: placed),
                ),
              );
            },
          ),
        ),
      );
  }

  Future<void> _saveUnitEdits(
    StorageUnit unit,
    String name,
    StorageUnitType type,
    int rows,
    int gw,
    int gh,
  ) async {
    final householdId = ref.read(householdIdProvider);
    if (householdId == null) return;

    final current = _layoutOf(unit);
    final clampedGw = gw.clamp(1, _gridCols - current.gx);
    final clampedGh = gh.clamp(1, _gridRows - current.gy);

    final updated = unit.copyWith(
      name: name,
      type: type,
      rows: rows,
      gx: current.gx,
      gy: current.gy,
      gw: clampedGw,
      gh: clampedGh,
    );
    await ref.read(unitRepositoryProvider).updateUnit(updated);
    setState(() {
      _localLayout[unit.id] = (
        gx: current.gx,
        gy: current.gy,
        gw: clampedGw,
        gh: clampedGh,
      );
    });

    if (rows != unit.rows) {
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

    setState(() => _selectedUnitId = null);
  }
}

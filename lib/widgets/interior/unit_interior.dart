import 'package:flutter/material.dart';
import 'package:wherein_kitchen/models/item.dart';
import 'package:wherein_kitchen/models/slot.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';
import 'package:wherein_kitchen/widgets/interior/drawer_interior.dart';
import 'package:wherein_kitchen/widgets/interior/freezer_interior.dart';
import 'package:wherein_kitchen/widgets/interior/fridge_interior.dart';
import 'package:wherein_kitchen/widgets/interior/grid_interior.dart';
import 'package:wherein_kitchen/widgets/interior/shelf_interior.dart';
import 'package:wherein_kitchen/widgets/interior/slot_tile.dart';

/// Drop-in replacement for the old `ShelfMap`: a dispatcher that renders a
/// unit's interior in a layout that resembles the real thing (fridge, freezer,
/// drawer stack, open shelving, cabinet, or a generic grid) so items are easy
/// to locate. Same prop signature as the former ShelfMap.
class UnitInterior extends StatelessWidget {
  const UnitInterior({
    super.key,
    required this.unit,
    required this.slots,
    required this.itemCountBySlot,
    this.itemsBySlot,
    this.highlightSlotId,
    this.highlightItemName,
    this.onSlotTap,
    this.selectMode = false,
    this.selectedSlotId,
  });

  final StorageUnit unit;
  final List<Slot> slots;
  final Map<String, int> itemCountBySlot;
  final Map<String, List<Item>>? itemsBySlot;
  final String? highlightSlotId;
  final String? highlightItemName;
  final ValueChanged<Slot>? onSlotTap;
  final bool selectMode;
  final String? selectedSlotId;

  @override
  Widget build(BuildContext context) {
    final cells = [
      for (final slot in slots)
        SlotCellData(
          slot: slot,
          items: itemsBySlot?[slot.id] ?? const <Item>[],
          count: (itemsBySlot?[slot.id]?.isNotEmpty ?? false)
              ? itemsBySlot![slot.id]!.length
              : (itemCountBySlot[slot.id] ?? 0),
          highlighted: slot.id == highlightSlotId,
          selected: slot.id == selectedSlotId,
        ),
    ];

    final cols = unit.columns.clamp(1, kMaxDoors);

    return switch (unit.type) {
      StorageUnitType.fridge => FridgeInterior(
          unit: unit,
          cells: cells,
          selectMode: selectMode,
          highlightItemName: highlightItemName,
          onSlotTap: onSlotTap,
        ),
      StorageUnitType.freezer => FreezerInterior(
          unit: unit,
          cells: cells,
          selectMode: selectMode,
          highlightItemName: highlightItemName,
          onSlotTap: onSlotTap,
        ),
      StorageUnitType.drawer => DrawerStackInterior(
          unit: unit,
          cells: cells,
          selectMode: selectMode,
          highlightItemName: highlightItemName,
          onSlotTap: onSlotTap,
        ),
      StorageUnitType.shelf when cols <= 1 => ShelfStackInterior(
          unit: unit,
          cells: cells,
          selectMode: selectMode,
          highlightItemName: highlightItemName,
          onSlotTap: onSlotTap,
        ),
      StorageUnitType.cabinet => GridInterior(
          unit: unit,
          cells: cells,
          selectMode: selectMode,
          highlightItemName: highlightItemName,
          onSlotTap: onSlotTap,
          framed: true,
        ),
      _ => GridInterior(
          unit: unit,
          cells: cells,
          selectMode: selectMode,
          highlightItemName: highlightItemName,
          onSlotTap: onSlotTap,
        ),
    };
  }
}

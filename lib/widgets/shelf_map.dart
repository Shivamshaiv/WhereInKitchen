import 'package:flutter/material.dart';
import 'package:wherein_kitchen/models/item.dart';
import 'package:wherein_kitchen/models/slot.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';
import 'package:wherein_kitchen/widgets/interior/unit_interior.dart';

/// Deprecated: use [UnitInterior]. Kept as a thin delegating shim so any
/// remaining reference still renders the type-specific interior.
class ShelfMap extends StatelessWidget {
  const ShelfMap({
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
  Widget build(BuildContext context) => UnitInterior(
        unit: unit,
        slots: slots,
        itemCountBySlot: itemCountBySlot,
        itemsBySlot: itemsBySlot,
        highlightSlotId: highlightSlotId,
        highlightItemName: highlightItemName,
        onSlotTap: onSlotTap,
        selectMode: selectMode,
        selectedSlotId: selectedSlotId,
      );
}

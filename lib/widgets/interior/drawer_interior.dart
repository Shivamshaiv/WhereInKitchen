import 'package:flutter/material.dart';
import 'package:wherein_kitchen/models/slot.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';
import 'package:wherein_kitchen/widgets/interior/slot_tile.dart';

/// Interior that reads like a stack of drawers: full-width drawer fronts
/// top→bottom, each with a bar pull.
class DrawerStackInterior extends StatelessWidget {
  const DrawerStackInterior({
    super.key,
    required this.unit,
    required this.cells,
    required this.selectMode,
    required this.highlightItemName,
    required this.onSlotTap,
  });

  final StorageUnit unit;
  final List<SlotCellData> cells;
  final bool selectMode;
  final String? highlightItemName;
  final ValueChanged<Slot>? onSlotTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return verticalSlotStack(
      cells: cells,
      selectMode: selectMode,
      highlightItemName: highlightItemName,
      onSlotTap: onSlotTap,
      tilePadding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
      decorate: (cell, tile) => Stack(
        children: [
          Positioned.fill(child: tile),
          // Drawer bar pull (decorative; must not steal the tap).
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  width: 72,
                  height: 5,
                  decoration: BoxDecoration(
                    color: scheme.outline.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

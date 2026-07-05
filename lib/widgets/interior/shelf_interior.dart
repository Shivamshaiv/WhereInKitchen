import 'package:flutter/material.dart';
import 'package:wherein_kitchen/models/slot.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';
import 'package:wherein_kitchen/widgets/interior/slot_tile.dart';

/// Interior that reads like open shelving / a pantry: each shelf sits on a
/// visible wood ledge, no doors or carcass.
class ShelfStackInterior extends StatelessWidget {
  const ShelfStackInterior({
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
    return verticalSlotStack(
      cells: cells,
      selectMode: selectMode,
      highlightItemName: highlightItemName,
      onSlotTap: onSlotTap,
      decorate: (cell, tile) => Column(
        children: [
          Expanded(child: tile),
          // Wood ledge under each shelf so "top / bottom shelf" reads clearly.
          Container(
            height: 8,
            margin: const EdgeInsets.only(top: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFCBA47C), Color(0xFF9C6B43)],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

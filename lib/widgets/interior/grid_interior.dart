import 'package:flutter/material.dart';
import 'package:wherein_kitchen/models/slot.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';
import 'package:wherein_kitchen/widgets/interior/slot_tile.dart';

/// The default 2D grid interior (rows × columns) — used for generic units, and
/// for cabinets (with [framed] carcass chrome) and multi-column shelves.
/// Non-scrolling: fills the bounded height it is given (every call site wraps
/// it in an Expanded).
class GridInterior extends StatelessWidget {
  const GridInterior({
    super.key,
    required this.unit,
    required this.cells,
    required this.selectMode,
    required this.highlightItemName,
    required this.onSlotTap,
    this.framed = false,
  });

  final StorageUnit unit;
  final List<SlotCellData> cells;
  final bool selectMode;
  final String? highlightItemName;
  final ValueChanged<Slot>? onSlotTap;
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rowCount = effectiveRowCount(unit, cells.map((c) => c.slot).toList());

    final grid = Column(
      children: List.generate(rowCount, (i) {
        final row = i + 1;
        final rowCells = cells.where((c) => c.slot.row == row).toList()
          ..sort((a, b) => a.slot.column.compareTo(b.slot.column));
        return Expanded(
          child: Row(
            children: rowCells
                .map(
                  (c) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: SlotTile(
                        label: c.slot.label,
                        count: c.count,
                        items: c.items,
                        highlighted: c.highlighted,
                        selected: c.selected,
                        selectMode: selectMode,
                        highlightItemName: highlightItemName,
                        onTap: onSlotTap == null
                            ? null
                            : () => onSlotTap!(c.slot),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        );
      }),
    );

    if (!framed) return grid;
    // Cabinet carcass: a thick frame + subtle back panel so it reads as a
    // cabinet you've opened rather than open shelving.
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [scheme.surfaceContainerHigh, scheme.surfaceContainer],
        ),
        border: Border.all(color: scheme.outlineVariant, width: 6),
      ),
      padding: const EdgeInsets.all(6),
      child: grid,
    );
  }
}

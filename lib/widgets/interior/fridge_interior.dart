import 'package:flutter/material.dart';
import 'package:wherein_kitchen/models/slot.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';
import 'package:wherein_kitchen/widgets/interior/slot_tile.dart';

/// Interior that reads like an open fridge: a tall body of stacked main
/// shelves (column 1) with the crisper as the bottom drawer, and a narrow
/// door panel of bins (column 2) down the right side.
class FridgeInterior extends StatelessWidget {
  const FridgeInterior({
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
    final maxRow = cells.fold<int>(0, (m, c) => c.slot.row > m ? c.slot.row : m);
    // column 1 = main shelves (+ crisper); column >= 2 = door bins. Using <=/>=
    // (not ==) guarantees no cell is ever dropped, even for edited/legacy units.
    final shelfCells = cells.where((c) => c.slot.column <= 1).toList()
      ..sort((a, b) => a.slot.row.compareTo(b.slot.row));
    // Group door bins by their column so each door renders as its own panel.
    final binsByColumn = <int, List<SlotCellData>>{};
    for (final c in cells.where((c) => c.slot.column >= 2)) {
      (binsByColumn[c.slot.column] ??= []).add(c);
    }
    for (final list in binsByColumn.values) {
      list.sort((a, b) => a.slot.row.compareTo(b.slot.row));
    }
    final doorColumns = binsByColumn.keys.toList()..sort();

    SlotTile tileFor(SlotCellData c,
            {EdgeInsets padding = const EdgeInsets.all(12)}) =>
        SlotTile(
          label: c.slot.label,
          count: c.count,
          items: c.items,
          highlighted: c.highlighted,
          selected: c.selected,
          selectMode: selectMode,
          highlightItemName: highlightItemName,
          padding: padding,
          onTap: onSlotTap == null ? null : () => onSlotTap!(c.slot),
        );

    bool isCrisper(SlotCellData c) =>
        c.slot.label == 'Crisper' ||
        (c.slot.row == maxRow && c.slot.column == 1);

    final body = Column(
      children: [
        for (final c in shelfCells)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: isCrisper(c)
                  // The crisper reads as a pull-out drawer at the fridge bottom.
                  ? Stack(
                      children: [
                        Positioned.fill(
                          child: tileFor(c,
                              padding:
                                  const EdgeInsets.fromLTRB(12, 16, 12, 12)),
                        ),
                        Positioned(
                          top: 7,
                          left: 0,
                          right: 0,
                          child: IgnorePointer(
                            child: Center(
                              child: Container(
                                width: 48,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: scheme.outline.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : tileFor(c),
            ),
          ),
      ],
    );

    Widget doorPanel(List<SlotCellData> bins) => Column(
          children: [
            for (final c in bins)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: tileFor(c, padding: const EdgeInsets.all(8)),
                ),
              ),
          ],
        );

    Widget seam() => Container(
          width: 2,
          margin: const EdgeInsets.symmetric(vertical: 10),
          color: scheme.outlineVariant,
        );

    final rowChildren = <Widget>[];
    if (doorColumns.length >= 2) {
      // Two (or more) doors flank the shelves like an open French-door fridge.
      rowChildren
        ..add(Expanded(flex: 2, child: doorPanel(binsByColumn[doorColumns.first]!)))
        ..add(seam())
        ..add(Expanded(flex: 5, child: body));
      for (final col in doorColumns.skip(1)) {
        rowChildren
          ..add(seam())
          ..add(Expanded(flex: 2, child: doorPanel(binsByColumn[col]!)));
      }
    } else if (doorColumns.length == 1) {
      rowChildren
        ..add(Expanded(flex: 3, child: body))
        ..add(seam())
        ..add(Expanded(
            flex: 1, child: doorPanel(binsByColumn[doorColumns.first]!)));
    } else {
      rowChildren.add(Expanded(child: body));
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant, width: 2),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [scheme.surfaceContainer, scheme.surfaceContainerLow],
        ),
      ),
      padding: const EdgeInsets.all(8),
      child: Row(children: rowChildren),
    );
  }
}

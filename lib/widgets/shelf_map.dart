import 'package:flutter/material.dart';
import 'package:wherein_kitchen/models/slot.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';

class ShelfMap extends StatefulWidget {
  const ShelfMap({
    super.key,
    required this.unit,
    required this.slots,
    required this.itemCountBySlot,
    this.highlightSlotId,
    this.highlightItemName,
    this.onSlotTap,
    this.selectMode = false,
    this.selectedSlotId,
  });

  final StorageUnit unit;
  final List<Slot> slots;
  final Map<String, int> itemCountBySlot;
  final String? highlightSlotId;
  final String? highlightItemName;
  final ValueChanged<Slot>? onSlotTap;
  final bool selectMode;
  final String? selectedSlotId;

  @override
  State<ShelfMap> createState() => _ShelfMapState();
}

class _ShelfMapState extends State<ShelfMap> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.highlightSlotId != null) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant ShelfMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlightSlotId != null && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (widget.highlightSlotId == null && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Column(
          children: List.generate(widget.unit.rows, (rowIndex) {
            final row = rowIndex + 1;
            final rowSlots = widget.slots
                .where((s) => s.row == row)
                .toList()
              ..sort((a, b) => a.column.compareTo(b.column));

            return Expanded(
              child: Row(
                children: rowSlots.map((slot) {
                  final isHighlighted = slot.id == widget.highlightSlotId;
                  final isSelected = slot.id == widget.selectedSlotId;
                  final itemCount = widget.itemCountBySlot[slot.id] ?? 0;
                  final glow = isHighlighted ? _pulseController.value : 0.0;

                  Color background = colorScheme.surfaceContainerHighest;
                  Color border = colorScheme.outlineVariant;
                  if (isHighlighted) {
                    background = Color.lerp(
                      colorScheme.primaryContainer,
                      colorScheme.primary,
                      glow * 0.35,
                    )!;
                    border = colorScheme.primary;
                  } else if (isSelected) {
                    background = colorScheme.secondaryContainer;
                    border = colorScheme.secondary;
                  }

                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Material(
                        color: background,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: widget.onSlotTap == null
                              ? null
                              : () => widget.onSlotTap!(slot),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: border,
                                width: isHighlighted ? 2.5 + glow : 1,
                              ),
                              boxShadow: isHighlighted
                                  ? [
                                      BoxShadow(
                                        color: colorScheme.primary
                                            .withValues(alpha: 0.3 + glow * 0.4),
                                        blurRadius: 12 + glow * 8,
                                        spreadRadius: glow * 2,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    slot.label,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (isHighlighted &&
                                      widget.highlightItemName != null)
                                    Text(
                                      widget.highlightItemName!,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: colorScheme.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  else if (itemCount > 0)
                                    Text(
                                      '$itemCount item${itemCount == 1 ? '' : 's'}',
                                      style: theme.textTheme.bodySmall,
                                    )
                                  else
                                    Text(
                                      widget.selectMode ? 'Tap to place' : 'Empty',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.outline,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            );
          }),
        );
      },
    );
  }
}

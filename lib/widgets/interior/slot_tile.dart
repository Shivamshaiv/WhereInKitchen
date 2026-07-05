import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wherein_kitchen/models/item.dart';
import 'package:wherein_kitchen/models/slot.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';

/// A resolved per-compartment cell: its slot plus the item data/flags a layout
/// needs. Every interior layout receives a `List<SlotCellData>` and arranges
/// them type-appropriately.
class SlotCellData {
  const SlotCellData({
    required this.slot,
    required this.count,
    required this.items,
    required this.highlighted,
    required this.selected,
  });

  final Slot slot;
  final int count;
  final List<Item> items;
  final bool highlighted;
  final bool selected;
}

/// Number of rows a unit's interior should show: the max of its declared rows
/// and the highest actual slot row, so populated shelves never vanish when the
/// stored `rows` is out of sync with the real slots (imported/joined data).
int effectiveRowCount(StorageUnit unit, List<Slot> slots) {
  final maxSlotRow = slots.fold<int>(0, (m, s) => s.row > m ? s.row : m);
  return math.max(1, math.max(unit.rows, maxSlotRow));
}

/// A single compartment tile: label + count badge + item preview, with a
/// self-contained pulse/glow when [highlighted] (search target). Being a
/// StatefulWidget that owns its own controller lets any layout drop a tile
/// anywhere and have the highlighted one animate itself.
class SlotTile extends StatefulWidget {
  const SlotTile({
    super.key,
    required this.label,
    required this.count,
    required this.items,
    this.highlighted = false,
    this.selected = false,
    this.selectMode = false,
    this.highlightItemName,
    this.onTap,
    this.padding = const EdgeInsets.all(12),
    this.borderRadius = 12,
  });

  final String label;
  final int count;
  final List<Item> items;
  final bool highlighted;
  final bool selected;
  final bool selectMode;
  final String? highlightItemName;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final double borderRadius;

  @override
  State<SlotTile> createState() => _SlotTileState();
}

class _SlotTileState extends State<SlotTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.highlighted) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant SlotTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlighted && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.highlighted && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.reset();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Widget _contents(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final items = widget.items;
    final count = widget.count;

    if (items.isEmpty) {
      final label = count > 0
          ? '$count item${count == 1 ? '' : 's'}'
          : (widget.selectMode ? 'Tap to place' : 'Empty');
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: count > 0 ? scheme.onSurfaceVariant : scheme.outline,
          ),
        ),
      );
    }

    const maxChips = 12;
    final preview = items.take(maxChips).toList();
    final extra = items.length - preview.length;
    final highlightName = widget.highlightItemName?.toLowerCase();

    return ClipRect(
      child: Align(
        alignment: Alignment.topLeft,
        child: LayoutBuilder(
          builder: (context, c) {
            final maxChipWidth = c.maxWidth.isFinite ? c.maxWidth : 200.0;
            return Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final item in preview)
                  _ShelfItemChip(
                    item: item,
                    maxWidth: maxChipWidth,
                    highlighted: widget.highlighted &&
                        highlightName != null &&
                        item.name.toLowerCase() == highlightName,
                  ),
                if (extra > 0) _MoreChip(count: extra),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Animation-independent tile content. Passed to AnimatedBuilder as `child`
    // so the per-frame builder only recomputes the glow-driven decoration and
    // reuses this subtree instead of rebuilding the header + item chips (and
    // re-decoding thumbnails) on every pulse frame.
    final content = Padding(
      padding: widget.padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final header = Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (widget.count > 0) ...[
                const SizedBox(width: 6),
                _CountBadge(count: widget.count),
              ],
            ],
          );
          // Drop the preview area when the tile is too short to hold
          // it (dense stacks, bottom sheets, large text scale), so a
          // compartment never paints a RenderFlex overflow — it just
          // shows its label + count.
          final showContents = !constraints.hasBoundedHeight ||
              constraints.maxHeight >= 48;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              if (showContents) ...[
                const SizedBox(height: 8),
                Expanded(child: _contents(context)),
              ],
            ],
          );
        },
      ),
    );
    return AnimatedBuilder(
      animation: _pulse,
      child: content,
      builder: (context, child) {
        final glow = widget.highlighted ? _pulse.value : 0.0;
        Color background = scheme.surfaceContainerHighest;
        Color border = scheme.outlineVariant;
        if (widget.highlighted) {
          background = Color.lerp(
              scheme.primaryContainer, scheme.primary, glow * 0.35)!;
          border = scheme.primary;
        } else if (widget.selected) {
          background = scheme.secondaryContainer;
          border = scheme.secondary;
        }
        return Material(
          color: background,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: InkWell(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                border: Border.all(
                  color: border,
                  width: widget.highlighted ? 2.5 + glow : 1,
                ),
                boxShadow: widget.highlighted
                    ? [
                        BoxShadow(
                          color: scheme.primary
                              .withValues(alpha: 0.3 + glow * 0.4),
                          blurRadius: 12 + glow * 8,
                          spreadRadius: glow * 2,
                        ),
                      ]
                    : null,
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// A single-column top→bottom stack of slot tiles. Freezer/drawer/open-shelf
/// interiors share this and only supply their own [decorate] chrome (a drawer
/// handle, a wood ledge, …) around each tile.
Widget verticalSlotStack({
  required List<SlotCellData> cells,
  required bool selectMode,
  String? highlightItemName,
  ValueChanged<Slot>? onSlotTap,
  EdgeInsets tilePadding = const EdgeInsets.all(12),
  Widget Function(SlotCellData cell, Widget tile)? decorate,
}) {
  final sorted = [...cells]..sort((a, b) => a.slot.row.compareTo(b.slot.row));
  final children = <Widget>[];
  for (final c in sorted) {
    final Widget tile = SlotTile(
      label: c.slot.label,
      count: c.count,
      items: c.items,
      highlighted: c.highlighted,
      selected: c.selected,
      selectMode: selectMode,
      highlightItemName: highlightItemName,
      padding: tilePadding,
      onTap: onSlotTap == null ? null : () => onSlotTap(c.slot),
    );
    children.add(
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: decorate == null ? tile : decorate(c, tile),
        ),
      ),
    );
  }
  return Column(children: children);
}

/// Small rounded count badge shown next to a compartment label.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

/// "+N more" pill when a compartment has more items than the preview shows.
class _MoreChip extends StatelessWidget {
  const _MoreChip({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '+$count more',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// A single item preview: rounded thumbnail (or coloured initial) + name.
class _ShelfItemChip extends StatelessWidget {
  const _ShelfItemChip({
    required this.item,
    this.highlighted = false,
    this.maxWidth = double.infinity,
  });

  final Item item;
  final bool highlighted;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
        decoration: BoxDecoration(
          color: highlighted ? scheme.primaryContainer : scheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: highlighted
                ? scheme.primary
                : scheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _thumb(context),
            const SizedBox(width: 8),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 130),
                child: Text(
                  item.name,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight:
                            highlighted ? FontWeight.w700 : FontWeight.w500,
                        color: highlighted ? scheme.onPrimaryContainer : null,
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumb(BuildContext context) {
    final thumb = item.thumbB64;
    if (thumb != null && thumb.isNotEmpty) {
      try {
        return ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Image.memory(
            base64Decode(thumb),
            width: 26,
            height: 26,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        );
      } catch (_) {
        // Fall through to the initial avatar.
      }
    }
    final url = item.imageUrl;
    if (url != null && url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Image.network(
          url,
          width: 26,
          height: 26,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _initial(context),
        ),
      );
    }
    return _initial(context);
  }

  Widget _initial(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        item.name.isNotEmpty ? item.name[0].toUpperCase() : '?',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wherein_kitchen/models/item.dart';
import 'package:wherein_kitchen/models/slot.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';
import 'package:wherein_kitchen/providers/providers.dart';
import 'package:wherein_kitchen/screens/slot/slot_detail_screen.dart';
import 'package:wherein_kitchen/screens/unit/unit_view_screen.dart';

/// A "sneak peek" front-elevation of a unit: shelves stacked top-to-bottom,
/// each showing a preview of what's stored on it. Reached by tapping a unit in
/// the room with a zoom-in transition. Tapping a shelf drills into its detail.
class UnitPeekScreen extends ConsumerStatefulWidget {
  const UnitPeekScreen({super.key, required this.unit});

  final StorageUnit unit;

  @override
  ConsumerState<UnitPeekScreen> createState() => _UnitPeekScreenState();
}

class _UnitPeekScreenState extends ConsumerState<UnitPeekScreen> {
  @override
  void initState() {
    super.initState();
    // Make sure shelves exist even for freshly created units.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final householdId = ref.read(householdIdProvider);
      if (householdId == null) return;
      ref.read(slotRepositoryProvider).ensureSlotsForUnit(
            householdId: householdId,
            unit: widget.unit,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final unit = widget.unit;
    final scheme = Theme.of(context).colorScheme;
    final slotsAsync = ref.watch(slotsForUnitProvider(unit.id));
    final items = ref.watch(itemsProvider).value ?? [];

    final itemsBySlot = <String, List<Item>>{};
    for (final item in items) {
      (itemsBySlot[item.slotId] ??= []).add(item);
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              unit.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${unit.mount.label} · ${unit.type.label}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Full view',
            icon: const Icon(Icons.open_in_full),
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => UnitViewScreen(unit: unit),
                ),
              );
            },
          ),
        ],
      ),
      body: slotsAsync.when(
        data: (slots) {
          if (slots.isEmpty) {
            return const Center(child: Text('Setting up shelves…'));
          }

          final rows = <int, List<Slot>>{};
          for (final s in slots) {
            (rows[s.row] ??= []).add(s);
          }
          // Row 1 at the top, matching ShelfMap (used by the full unit view,
          // shelf pickers, and search) so a shelf never changes position
          // depending on how the unit was opened.
          final rowNumbers = rows.keys.toList()..sort((a, b) => a.compareTo(b));

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Peek inside — tap a shelf to see or add items',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          scheme.surfaceContainerHighest,
                          scheme.surfaceContainerHigh,
                        ],
                      ),
                      border: Border.all(
                        color: scheme.outlineVariant,
                        width: 6,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        for (final row in rowNumbers)
                          Expanded(
                            child: Row(
                              children: [
                                for (final slot in (rows[row]!
                                  ..sort((a, b) =>
                                      a.column.compareTo(b.column))))
                                  Expanded(
                                    child: _ShelfCell(
                                      slot: slot,
                                      items: itemsBySlot[slot.id] ?? const [],
                                      onTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => SlotDetailScreen(
                                              unit: unit,
                                              slot: slot,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _ShelfCell extends StatelessWidget {
  const _ShelfCell({
    required this.slot,
    required this.items,
    required this.onTap,
  });

  final Slot slot;
  final List<Item> items;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final preview = items.take(4).toList();
    final extra = items.length - preview.length;

    return Padding(
      padding: const EdgeInsets.all(5),
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant),
              // Wooden shelf ledge at the bottom.
              boxShadow: [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: 0.12),
                  blurRadius: 2,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        slot.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (items.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${items.length}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: items.isEmpty
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Empty · tap to add',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: scheme.outline),
                          ),
                        )
                      : Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final item in preview)
                              _ItemChip(item: item),
                            if (extra > 0)
                              Chip(
                                visualDensity: VisualDensity.compact,
                                label: Text('+$extra'),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ItemChip extends StatelessWidget {
  const _ItemChip({required this.item});

  final Item item;

  // Cache decoded thumbnails keyed by their base64 string so base64Decode is
  // not re-run on every rebuild (the peek screen rebuilds whenever itemsProvider
  // updates, redrawing every preview chip).
  static final Map<String, Uint8List> _thumbCache = {};

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget? avatar;
    final thumb = item.thumbB64;
    if (thumb != null && thumb.isNotEmpty) {
      try {
        final bytes = _thumbCache[thumb] ??= base64Decode(thumb);
        avatar = ClipOval(
          child: Image.memory(
            bytes,
            width: 22,
            height: 22,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        );
      } catch (_) {
        avatar = null;
      }
    }
    avatar ??= CircleAvatar(
      radius: 11,
      backgroundColor: scheme.secondaryContainer,
      child: Text(
        item.name.isNotEmpty ? item.name[0].toUpperCase() : '?',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: scheme.onSecondaryContainer,
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.only(left: 2, right: 8, top: 2, bottom: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          avatar,
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 90),
            child: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wherein_kitchen/models/item.dart';
import 'package:wherein_kitchen/models/slot.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';
import 'package:wherein_kitchen/providers/providers.dart';
import 'package:wherein_kitchen/screens/qr/qr_label_screen.dart';
import 'package:wherein_kitchen/screens/slot/slot_detail_screen.dart';
import 'package:wherein_kitchen/widgets/empty_state.dart';
import 'package:wherein_kitchen/widgets/interior/unit_interior.dart';

class UnitViewScreen extends ConsumerStatefulWidget {
  const UnitViewScreen({
    super.key,
    required this.unit,
    this.highlightSlotId,
    this.highlightItemName,
  });

  final StorageUnit unit;
  final String? highlightSlotId;
  final String? highlightItemName;

  @override
  ConsumerState<UnitViewScreen> createState() => _UnitViewScreenState();
}

class _UnitViewScreenState extends ConsumerState<UnitViewScreen> {
  @override
  void initState() {
    super.initState();
    _ensureSlots();
  }

  Future<void> _ensureSlots() async {
    final householdId = ref.read(householdIdProvider);
    if (householdId == null) return;
    // Reconcile (not just ensure) so the compartments always match the unit's
    // current config — e.g. a fridge switched to two doors gains its second
    // bank of door bins on open. Populated slots are never removed.
    await ref.read(slotRepositoryProvider).reconcileSlotsForUnit(
          householdId: householdId,
          unit: widget.unit,
        );
  }

  @override
  Widget build(BuildContext context) {
    final householdId = ref.watch(householdIdProvider);
    final slotsAsync = householdId == null
        ? const AsyncValue<List<Slot>>.loading()
        : ref.watch(slotsForUnitProvider(widget.unit.id));
    final items = ref.watch(itemsProvider).value ?? [];

    final itemCountBySlot = <String, int>{};
    final itemsBySlot = <String, List<Item>>{};
    for (final item in items) {
      itemCountBySlot[item.slotId] =
          (itemCountBySlot[item.slotId] ?? 0) + 1;
      (itemsBySlot[item.slotId] ??= []).add(item);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.unit.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'QR labels',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => QrLabelScreen(unit: widget.unit),
                ),
              );
            },
            icon: const Icon(Icons.qr_code),
          ),
        ],
      ),
      body: slotsAsync.when(
        data: (slots) {
          if (slots.isEmpty) {
            return const EmptyState(
              icon: Icons.shelves,
              title: 'Setting up shelves…',
            );
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Tap a shelf to view or add items',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: UnitInterior(
                    unit: widget.unit,
                    slots: slots,
                    itemCountBySlot: itemCountBySlot,
                    itemsBySlot: itemsBySlot,
                    highlightSlotId: widget.highlightSlotId,
                    highlightItemName: widget.highlightItemName,
                    onSlotTap: (slot) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => SlotDetailScreen(
                            unit: widget.unit,
                            slot: slot,
                          ),
                        ),
                      );
                    },
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

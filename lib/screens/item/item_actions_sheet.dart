import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wherein_kitchen/models/item.dart';
import 'package:wherein_kitchen/models/slot.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';
import 'package:wherein_kitchen/providers/providers.dart';
import 'package:wherein_kitchen/screens/search/search_result_screen.dart';
import 'package:wherein_kitchen/widgets/shelf_map.dart';

Future<void> showItemActionsSheet({
  required BuildContext context,
  required WidgetRef ref,
  required Item item,
  StorageUnit? currentUnit,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(item.name),
              subtitle: Text(item.quantity),
            ),
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: const Text('Show on shelf'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SearchResultScreen(item: item),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outline),
              title: const Text('Move to another shelf'),
              onTap: () async {
                Navigator.pop(context);
                await _moveItem(context, ref, item);
              },
            ),
            ListTile(
              leading: const Icon(Icons.remove_circle_outline),
              title: const Text('Mark as used up'),
              onTap: () async {
                Navigator.pop(context);
                await ref
                    .read(itemRepositoryProvider)
                    .deleteItem(item.householdId, item.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Removed ${item.name}')),
                  );
                }
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Delete',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () async {
                Navigator.pop(context);
                await ref
                    .read(itemRepositoryProvider)
                    .deleteItem(item.householdId, item.id);
              },
            ),
          ],
        ),
      );
    },
  );
}

Future<void> _moveItem(
  BuildContext context,
  WidgetRef ref,
  Item item,
) async {
  final units = ref.read(unitsProvider).value ?? [];
  if (units.isEmpty) return;

  final householdId = ref.read(householdIdProvider);
  if (householdId == null) return;

  StorageUnit? selectedUnit = units.first;
  String? selectedSlotId;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          final unit = selectedUnit ?? units.first;
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.8,
            builder: (context, scrollController) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Move ${item.name}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<StorageUnit>(
                      initialValue: unit,
                      decoration:
                          const InputDecoration(labelText: 'Storage unit'),
                      items: units
                          .map(
                            (u) => DropdownMenuItem(
                              value: u,
                              child: Text(u.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedUnit = value;
                          selectedSlotId = null;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: StreamBuilder<List<Slot>>(
                        stream: ref
                            .read(slotRepositoryProvider)
                            .watchSlotsForUnit(householdId, unit.id),
                        builder: (context, snapshot) {
                          final slots = snapshot.data ?? [];
                          return ShelfMap(
                            unit: unit,
                            slots: slots,
                            itemCountBySlot: const {},
                            selectMode: true,
                            selectedSlotId: selectedSlotId,
                            onSlotTap: (slot) {
                              setState(() => selectedSlotId = slot.id);
                            },
                          );
                        },
                      ),
                    ),
                    FilledButton(
                      onPressed: selectedSlotId == null
                          ? null
                          : () async {
                              await ref.read(itemRepositoryProvider).moveItem(
                                    item: item,
                                    newSlotId: selectedSlotId!,
                                  );
                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Item moved')),
                                );
                              }
                            },
                      child: const Text('Move here'),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    },
  );
}

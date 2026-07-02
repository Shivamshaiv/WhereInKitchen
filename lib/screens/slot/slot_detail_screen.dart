import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wherein_kitchen/models/item.dart';
import 'package:wherein_kitchen/models/slot.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';
import 'package:wherein_kitchen/providers/providers.dart';
import 'package:wherein_kitchen/screens/item/add_item_screen.dart';
import 'package:wherein_kitchen/screens/item/item_actions_sheet.dart';
import 'package:wherein_kitchen/screens/qr/qr_label_screen.dart';
import 'package:wherein_kitchen/widgets/item_list_tile.dart';

class SlotDetailScreen extends ConsumerStatefulWidget {
  const SlotDetailScreen({
    super.key,
    required this.unit,
    required this.slot,
  });

  final StorageUnit unit;
  final Slot slot;

  @override
  ConsumerState<SlotDetailScreen> createState() => _SlotDetailScreenState();
}

class _SlotDetailScreenState extends ConsumerState<SlotDetailScreen> {
  final _quickAddController = TextEditingController();
  final _quickAddFocus = FocusNode();
  bool _adding = false;

  @override
  void dispose() {
    _quickAddController.dispose();
    _quickAddFocus.dispose();
    super.dispose();
  }

  Future<void> _quickAdd() async {
    final name = _quickAddController.text.trim();
    if (name.isEmpty) return;
    final householdId = ref.read(householdIdProvider);
    if (householdId == null) return;

    setState(() => _adding = true);
    _quickAddController.clear();
    // Keep focus so the user can keep typing item after item.
    _quickAddFocus.requestFocus();

    try {
      await ref.read(itemRepositoryProvider).quickAdd(
            householdId: householdId,
            slotId: widget.slot.id,
            name: name,
          );
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _renameShelf() async {
    final householdId = ref.read(householdIdProvider);
    if (householdId == null) return;

    final controller = TextEditingController(text: widget.slot.label);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename shelf'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'e.g. Snacks shelf'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty) {
      await ref
          .read(slotRepositoryProvider)
          .renameSlot(householdId, widget.slot.id, newName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Renamed to $newName')),
        );
      }
    }
  }

  Future<void> _clearShelf(List<Item> items) async {
    if (items.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove all ${items.length} items?'),
        content: Text(
            'Everything on "${widget.slot.label}" will be deleted. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove all'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final householdId = ref.read(householdIdProvider);
    if (householdId == null) return;

    await ref
        .read(itemRepositoryProvider)
        .deleteItems(householdId, items.map((i) => i.id).toList());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shelf cleared')),
      );
    }
  }

  Future<void> _deleteWithUndo(Item item) async {
    final householdId = ref.read(householdIdProvider);
    if (householdId == null) return;
    final repo = ref.read(itemRepositoryProvider);
    await repo.deleteItem(householdId, item.id);

    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('Removed ${item.name}'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => repo.addItem(item),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(itemsForSlotProvider(widget.slot.id));
    final items = itemsAsync.value ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.unit.name} · ${widget.slot.label}'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'rename':
                  _renameShelf();
                case 'clear':
                  _clearShelf(items);
                case 'qr':
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          QrLabelScreen(unit: widget.unit, slot: widget.slot),
                    ),
                  );
                case 'full':
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AddItemScreen(
                        preselectedSlotId: widget.slot.id,
                        preselectedUnit: widget.unit,
                      ),
                    ),
                  );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'rename',
                child: ListTile(
                  leading: Icon(Icons.drive_file_rename_outline),
                  title: Text('Rename shelf'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'full',
                child: ListTile(
                  leading: Icon(Icons.tune),
                  title: Text('Add with details'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'qr',
                child: ListTile(
                  leading: Icon(Icons.qr_code),
                  title: Text('Shelf QR label'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: ListTile(
                  leading: Icon(Icons.delete_sweep_outlined),
                  title: Text('Remove all items'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Quick add bar: type, enter, repeat.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _quickAddController,
              focusNode: _quickAddFocus,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _quickAdd(),
              decoration: InputDecoration(
                hintText: 'Type item name, press ✓ to add…',
                prefixIcon: const Icon(Icons.add),
                suffixIcon: _adding
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.check_circle),
                        color: Theme.of(context).colorScheme.primary,
                        onPressed: _quickAdd,
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                filled: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(
              children: [
                Text(
                  items.isEmpty
                      ? 'No items yet'
                      : '${items.length} item${items.length == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const Spacer(),
                if (items.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => _clearShelf(items),
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    label: const Text('Clear all'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: itemsAsync.when(
              data: (itemList) {
                if (itemList.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 56,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Type above to add items fast',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: itemList.length,
                  itemBuilder: (context, index) {
                    final item = itemList[index];
                    return Dismissible(
                      key: ValueKey(item.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: Icon(
                          Icons.delete_outline,
                          color:
                              Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                      onDismissed: (_) => _deleteWithUndo(item),
                      child: ItemListTile(
                        item: item,
                        onTap: () => showItemActionsSheet(
                          context: context,
                          ref: ref,
                          item: item,
                          currentUnit: widget.unit,
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }
}

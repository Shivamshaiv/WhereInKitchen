import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wherein_kitchen/models/item.dart';
import 'package:wherein_kitchen/models/room.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';
import 'package:wherein_kitchen/providers/providers.dart';
import 'package:wherein_kitchen/screens/item/add_item_screen.dart';
import 'package:wherein_kitchen/screens/room/room_layout_screen.dart';
import 'package:wherein_kitchen/screens/scan/scan_screen.dart';
import 'package:wherein_kitchen/screens/search/search_result_screen.dart';
import 'package:wherein_kitchen/screens/unit/unit_view_screen.dart';
import 'package:wherein_kitchen/widgets/empty_state.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    ref.read(searchQueryProvider.notifier).state = value;
  }

  void _openSearchResult(Item item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchResultScreen(item: item),
      ),
    );
  }

  Future<void> _copyHouseholdId() async {
    final householdId = ref.read(householdIdProvider);
    if (householdId == null) return;
    await Clipboard.setData(ClipboardData(text: householdId));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Household ID copied')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final household = ref.watch(householdProvider);
    final rooms = ref.watch(roomsProvider);
    final units = ref.watch(unitsProvider);
    final searchResults = ref.watch(searchResultsProvider);
    final query = ref.watch(searchQueryProvider);

    return Scaffold(
      appBar: AppBar(
        title: household.when(
          data: (h) => Text(h?.name ?? 'WhereInKitchen'),
          loading: () => const Text('WhereInKitchen'),
          error: (_, __) => const Text('WhereInKitchen'),
        ),
        actions: [
          IconButton(
            tooltip: 'Copy household ID',
            onPressed: _copyHouseholdId,
            icon: const Icon(Icons.share_outlined),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () async {
              await ref.read(authServiceProvider).signOut();
              ref.read(householdIdProvider.notifier).state = null;
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchBar(
              controller: _searchController,
              hintText: 'Search for anything…',
              leading: const Icon(Icons.search),
              onChanged: _onSearchChanged,
              trailing: query.isNotEmpty
                  ? [
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      ),
                    ]
                  : null,
            ),
          ),
          Expanded(
            child: query.trim().isNotEmpty
                ? _buildSearchResults(searchResults)
                : _buildHomeContent(rooms, units),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'scan',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ScanScreen()),
              );
            },
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan'),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'add',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AddItemScreen()),
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('Add item'),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(AsyncValue<List<Item>> searchResults) {
    return searchResults.when(
      data: (items) {
        if (items.isEmpty) {
          return const EmptyState(
            icon: Icons.search_off,
            title: 'No items found',
            subtitle: 'Try a different name or alias',
          );
        }
        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return ListTile(
              leading: const Icon(Icons.place_outlined),
              title: Text(item.name),
              subtitle: Text(item.category),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openSearchResult(item),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Search error: $e')),
    );
  }

  Widget _buildHomeContent(
    AsyncValue<List<Room>> rooms,
    AsyncValue<List<StorageUnit>> units,
  ) {
    return rooms.when(
      data: (roomList) {
        return units.when(
          data: (unitList) {
            if (roomList.isEmpty) {
              return const EmptyState(
                icon: Icons.home_outlined,
                title: 'No rooms yet',
                subtitle: 'Add a room to start organizing',
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              children: [
                Row(
                  children: [
                    Text(
                      'Rooms',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _addRoom,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add room'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ...roomList.map((room) {
                  final roomUnits =
                      unitList.where((u) => u.roomId == room.id).toList();
                  final itemTotal = _itemCountForUnits(roomUnits);
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      leading: CircleAvatar(
                        child: Icon(
                          room.name.toLowerCase().contains('kitchen')
                              ? Icons.kitchen
                              : Icons.meeting_room_outlined,
                        ),
                      ),
                      title: Text(
                        room.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${roomUnits.length} storage units · $itemTotal items',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => RoomLayoutScreen(room: room),
                          ),
                        );
                      },
                    ),
                  );
                }),
                const SizedBox(height: 20),
                Text(
                  'Jump to storage',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: unitList.map((unit) {
                    return ActionChip(
                      avatar: Icon(_iconForUnitType(unit.type), size: 18),
                      label: Text(unit.name),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => UnitViewScreen(unit: unit),
                          ),
                        );
                      },
                    );
                  }).toList(),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  int _itemCountForUnits(List<StorageUnit> units) {
    final items = ref.watch(itemsProvider).value ?? [];
    final slots = ref.watch(slotsProvider).value ?? [];
    final unitIds = units.map((u) => u.id).toSet();
    final slotIds = slots
        .where((s) => unitIds.contains(s.unitId))
        .map((s) => s.id)
        .toSet();
    return items.where((i) => slotIds.contains(i.slotId)).length;
  }

  Future<void> _addRoom() async {
    final householdId = ref.read(householdIdProvider);
    if (householdId == null) return;

    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add room'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Garage, Laundry, Bathroom…',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      final rooms = ref.read(roomsProvider).value ?? [];
      await ref.read(roomRepositoryProvider).createRoom(
            householdId: householdId,
            name: name,
            sortOrder: rooms.length,
          );
    }
  }

  IconData _iconForUnitType(StorageUnitType type) {
    return switch (type) {
      StorageUnitType.shelf => Icons.shelves,
      StorageUnitType.drawer => Icons.inbox_outlined,
      StorageUnitType.cabinet => Icons.kitchen_outlined,
      StorageUnitType.fridge => Icons.kitchen,
      StorageUnitType.freezer => Icons.ac_unit,
      StorageUnitType.other => Icons.inventory_2_outlined,
    };
  }
}

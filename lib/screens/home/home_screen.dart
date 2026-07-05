import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:wherein_kitchen/models/household.dart';
import 'package:wherein_kitchen/models/item.dart';
import 'package:wherein_kitchen/models/room.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';
import 'package:wherein_kitchen/providers/providers.dart';
import 'package:wherein_kitchen/screens/item/add_item_screen.dart';
import 'package:wherein_kitchen/screens/room/room_top_view_screen.dart';
import 'package:wherein_kitchen/screens/scan/scan_screen.dart';
import 'package:wherein_kitchen/screens/search/search_result_screen.dart';
import 'package:wherein_kitchen/screens/settings/settings_screen.dart';
import 'package:wherein_kitchen/screens/unit/unit_view_screen.dart';
import 'package:wherein_kitchen/widgets/empty_state.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    // Debounce so the full-list filter runs at most a few times/sec instead of
    // once per keystroke. Clearing is applied immediately.
    _searchDebounce?.cancel();
    if (value.trim().isEmpty) {
      ref.read(searchQueryProvider.notifier).state = value;
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      ref.read(searchQueryProvider.notifier).state = value;
    });
  }

  void _openSearchResult(Item item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchResultScreen(item: item),
      ),
    );
  }

  Future<void> _roomActions(Room room) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Rename room'),
              onTap: () => Navigator.pop(sheetContext, 'rename'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(sheetContext).colorScheme.error),
              title: const Text('Delete room'),
              subtitle: const Text('Removes the room and everything in it'),
              onTap: () => Navigator.pop(sheetContext, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == 'rename') {
      await _renameRoom(room);
    } else if (action == 'delete') {
      await _deleteRoom(room);
    }
  }

  Future<void> _renameRoom(Room room) async {
    final hh = ref.read(householdIdProvider);
    if (hh == null) return;
    final controller = TextEditingController(text: room.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename room'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == room.name || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(roomRepositoryProvider).renameRoom(hh, room.id, name);
      messenger.showSnackBar(SnackBar(content: Text('Renamed to “$name”')));
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Couldn’t rename — try again.')));
    }
  }

  Future<void> _deleteRoom(Room room) async {
    final hh = ref.read(householdIdProvider);
    if (hh == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete “${room.name}”?'),
        content: const Text(
            'This permanently removes the room and every unit, shelf, and item '
            'inside it. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(roomRepositoryProvider).deleteRoom(hh, room.id);
      messenger.showSnackBar(SnackBar(content: Text('Deleted “${room.name}”')));
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Couldn’t delete — try again.')));
    }
  }

  Future<void> _createHome() async {
    final controller = TextEditingController(text: 'New Home');
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create new home'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'e.g. Beach House'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (uid == null) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final id = const Uuid().v4();
    try {
      await ref.read(householdRepositoryProvider).createHousehold(
            id: id,
            name: name,
            ownerUid: uid,
          );
      // Give the new home a Kitchen to start with.
      await ref.read(roomRepositoryProvider).createRoom(
            householdId: id,
            name: 'Kitchen',
            sortOrder: 0,
          );
      ref.read(householdIdProvider.notifier).state = id;
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('Created “$name”')));
    } catch (_) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(
            content: Text('Couldn’t create the home — try again.')));
    }
  }

  Future<void> _joinHome() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: const Text('Scan an invite QR'),
              subtitle: const Text('Point at the code on another phone'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ScanScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.keyboard),
              title: const Text('Enter a code'),
              subtitle: const Text('Paste a home code someone shared'),
              onTap: () {
                Navigator.pop(sheetContext);
                _enterHomeCode();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _enterHomeCode() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Join a home'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Home code',
            hintText: 'Paste the code from your invite',
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
            child: const Text('Join'),
          ),
        ],
      ),
    );
    if (code == null || code.isEmpty) return;

    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (uid == null) return;
    final id = parseHouseholdInvite(code);
    final household =
        await ref.read(householdRepositoryProvider).joinHousehold(uid, id);
    if (!mounted) return;
    if (household == null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('No home found for that code')),
        );
      return;
    }
    ref.read(householdIdProvider.notifier).state = household.id;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('Joined “${household.name}”')));
  }

  Future<void> _showInvite() async {
    final id = ref.read(householdIdProvider);
    if (id == null) return;
    final household = ref.read(householdProvider).valueOrNull;
    final payload = householdInvitePayload(id);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: Text(
            'Invite to ${household?.name ?? 'this home'}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'In WhereInKitchen, open the menu → Join a home → Scan, '
                'and point at this code.',
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: payload,
                  size: 220,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Text('Or share this code:',
                  style: Theme.of(dialogContext).textTheme.labelMedium),
              const SizedBox(height: 4),
              SelectableText(
                id,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: id));
                if (!mounted) return;
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(
                    const SnackBar(content: Text('Home code copied')),
                  );
              },
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy code'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _switchHome(String id) async {
    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (uid == null) return;
    await ref.read(householdRepositoryProvider).setActiveHousehold(uid, id);
    ref.read(householdIdProvider.notifier).state = id;
  }

  @override
  Widget build(BuildContext context) {
    final household = ref.watch(householdProvider);
    final rooms = ref.watch(roomsProvider);
    final units = ref.watch(unitsProvider);
    final searchResults = ref.watch(searchResultsProvider);
    final query = ref.watch(searchQueryProvider);

    // Switching/joining/creating a home must not carry the old home's search or
    // highlight into the new one (which would show stale results over unrelated
    // content). Reset on any change of the active household.
    ref.listen<String?>(householdIdProvider, (prev, next) {
      if (prev == next) return;
      _searchDebounce?.cancel();
      _searchController.clear();
      ref.read(searchQueryProvider.notifier).state = '';
      ref.read(highlightSlotIdProvider.notifier).state = null;
      ref.read(highlightItemNameProvider.notifier).state = null;
    });

    return Scaffold(
      drawer: _HouseSwitcherDrawer(
        onSwitch: _switchHome,
        onCreate: _createHome,
        onJoin: _joinHome,
        onInvite: _showInvite,
      ),
      appBar: AppBar(
        title: household.when(
          data: (h) => Text(h?.name ?? 'WhereInKitchen'),
          loading: () => const Text('WhereInKitchen'),
          error: (_, __) => const Text('WhereInKitchen'),
        ),
        actions: [
          IconButton(
            tooltip: 'Invite / share this home',
            onPressed: _showInvite,
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

            // Build a per-unit item-count index once per build instead of
            // re-scanning all slots and items for every room below.
            final itemCountByUnitId = _itemCountByUnitId();

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
                  final itemTotal = roomUnits.fold<int>(
                    0,
                    (sum, u) => sum + (itemCountByUnitId[u.id] ?? 0),
                  );
                  final scheme = Theme.of(context).colorScheme;
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          room.name.toLowerCase().contains('kitchen')
                              ? Icons.kitchen
                              : Icons.meeting_room_outlined,
                          color: scheme.onPrimaryContainer,
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
                            builder: (_) => RoomTopViewScreen(room: room),
                          ),
                        );
                      },
                      onLongPress: () => _roomActions(room),
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
                      label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 200),
                        child: Text(
                          unit.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
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

  /// Builds a map of storage-unit id -> number of items stored in that unit,
  /// scanning slots and items just once per build.
  Map<String, int> _itemCountByUnitId() {
    final items = ref.watch(itemsProvider).value ?? [];
    final slots = ref.watch(slotsProvider).value ?? [];
    final unitIdBySlotId = <String, String>{
      for (final s in slots) s.id: s.unitId,
    };
    final counts = <String, int>{};
    for (final i in items) {
      final unitId = unitIdBySlotId[i.slotId];
      if (unitId == null) continue;
      counts[unitId] = (counts[unitId] ?? 0) + 1;
    }
    return counts;
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
      StorageUnitType.range => Icons.local_fire_department_outlined,
      StorageUnitType.sink => Icons.water_drop_outlined,
      StorageUnitType.dishwasher => Icons.local_laundry_service_outlined,
      StorageUnitType.oven => Icons.microwave_outlined,
      StorageUnitType.gap => Icons.crop_free,
      StorageUnitType.other => Icons.inventory_2_outlined,
    };
  }
}

/// Side panel to switch between the user's homes, create a new one, join
/// another via QR/code, or share an invite to the current home.
class _HouseSwitcherDrawer extends ConsumerWidget {
  const _HouseSwitcherDrawer({
    required this.onSwitch,
    required this.onCreate,
    required this.onJoin,
    required this.onInvite,
  });

  final Future<void> Function(String householdId) onSwitch;
  final VoidCallback onCreate;
  final VoidCallback onJoin;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final activeId = ref.watch(householdIdProvider);
    final mine = ref.watch(myHouseholdsProvider);
    final activeName = ref.watch(householdProvider).valueOrNull?.name;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.home_rounded,
                        color: scheme.onPrimaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Current home',
                            style: Theme.of(context).textTheme.labelSmall),
                        Text(
                          activeName ?? 'No home',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                    child: Text('Your homes',
                        style: Theme.of(context).textTheme.labelLarge),
                  ),
                  ...mine.when(
                    data: (homes) {
                      if (homes.isEmpty) {
                        return [
                          const ListTile(
                            dense: true,
                            title: Text('No homes yet'),
                          ),
                        ];
                      }
                      return homes.map((h) {
                        final active = h.id == activeId;
                        return ListTile(
                          leading: Icon(
                            active ? Icons.home_rounded : Icons.home_outlined,
                            color: active ? scheme.primary : null,
                          ),
                          title: Text(h.name),
                          subtitle: Text(
                            '${h.members.length} '
                            'member${h.members.length == 1 ? '' : 's'}',
                          ),
                          trailing: active
                              ? Icon(Icons.check_circle, color: scheme.primary)
                              : null,
                          selected: active,
                          onTap: () {
                            Navigator.pop(context);
                            if (!active) onSwitch(h.id);
                          },
                        );
                      }).toList();
                    },
                    loading: () => [
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ],
                    error: (e, _) => [
                      ListTile(title: Text('Error: $e')),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.add_home_outlined),
              title: const Text('Create new home'),
              onTap: () {
                Navigator.pop(context);
                onCreate();
              },
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: const Text('Join a home'),
              onTap: () {
                Navigator.pop(context);
                onJoin();
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('Invite to this home'),
              onTap: () {
                Navigator.pop(context);
                onInvite();
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

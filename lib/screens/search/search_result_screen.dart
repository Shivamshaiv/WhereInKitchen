import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wherein_kitchen/models/item.dart';
import 'package:wherein_kitchen/models/room.dart';
import 'package:wherein_kitchen/models/slot.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';
import 'package:wherein_kitchen/providers/providers.dart';
import 'package:wherein_kitchen/screens/room/room_3d_screen.dart';
import 'package:wherein_kitchen/screens/slot/slot_detail_screen.dart';
import 'package:wherein_kitchen/widgets/interior/unit_interior.dart';

class SearchResultScreen extends ConsumerStatefulWidget {
  const SearchResultScreen({super.key, required this.item});

  final Item item;

  @override
  ConsumerState<SearchResultScreen> createState() => _SearchResultScreenState();
}

class _SearchResultScreenState extends ConsumerState<SearchResultScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _showMap = false;
  String? _locationPath;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _runAnimation());
  }

  Future<void> _runAnimation() async {
    await _resolveLocationPath();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() => _showMap = true);
    await _controller.forward();
  }

  Future<void> _resolveLocationPath() async {
    final householdId = ref.read(householdIdProvider);
    if (householdId == null) return;

    final slot = await ref
        .read(slotRepositoryProvider)
        .getSlot(householdId, widget.item.slotId);
    if (slot == null) return;

    final unit = await ref
        .read(unitRepositoryProvider)
        .getUnit(householdId, slot.unitId);
    if (unit == null) return;

    final rooms = ref.read(roomsProvider).value ?? [];
    final room = rooms.cast<Room?>().firstWhere(
          (r) => r?.id == unit.roomId,
          orElse: () => null,
        );

    setState(() {
      _locationPath = [
        room?.name ?? 'Home',
        unit.name,
        slot.label,
      ].join(' → ');
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final householdId = ref.watch(householdIdProvider);
    final slots = ref.watch(slotsProvider).value ?? [];
    final units = ref.watch(unitsProvider).value ?? [];
    final allItems = ref.watch(itemsProvider).value ?? [];

    // Re-derive the item from the live stream so a move/rename made after this
    // screen opened is reflected — otherwise we'd keep highlighting the shelf it
    // used to be on. Fall back to the passed snapshot until the stream loads.
    final item = allItems.firstWhere((i) => i.id == widget.item.id,
        orElse: () => widget.item);

    final slot = slots.cast<Slot?>().firstWhere(
          (s) => s?.id == item.slotId,
          orElse: () => null,
        );
    final unit = slot == null
        ? null
        : units.cast<StorageUnit?>().firstWhere(
              (u) => u?.id == slot.unitId,
              orElse: () => null,
            );

    final rooms = ref.watch(roomsProvider).value ?? [];
    final unitRoom = unit == null
        ? null
        : rooms.cast<Room?>().firstWhere(
              (r) => r?.id == unit.roomId,
              orElse: () => null,
            );

    final unitSlots = unit == null
        ? const <Slot>[]
        : (slots.where((s) => s.unitId == unit.id).toList()
          ..sort((a, b) {
            final r = a.row.compareTo(b.row);
            return r != 0 ? r : a.column.compareTo(b.column);
          }));
    final itemCountBySlot = <String, int>{};
    final itemsBySlot = <String, List<Item>>{};
    for (final it in allItems) {
      itemCountBySlot[it.slotId] = (itemCountBySlot[it.slotId] ?? 0) + 1;
      (itemsBySlot[it.slotId] ??= []).add(it);
    }

    return Scaffold(
      appBar: AppBar(title: Text(item.name)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    if (_locationPath != null)
                      Text(
                        _locationPath!,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                    if (item.aliases.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Also: ${item.aliases.join(', ')}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (unit != null && unitRoom != null) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.tonalIcon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => Room3DScreen(
                                room: unitRoom,
                                focusUnitId: unit.id,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.threed_rotation),
                          label: const Text('See it in 3D'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _showMap ? 'Found here:' : 'Locating…',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: AnimatedOpacity(
                opacity: _showMap ? 1 : 0.3,
                duration: const Duration(milliseconds: 500),
                child: unit != null && slot != null && householdId != null
                    ? FadeTransition(
                        opacity: _controller,
                        child: ScaleTransition(
                          scale: Tween<double>(begin: 0.92, end: 1).animate(
                            CurvedAnimation(
                              parent: _controller,
                              curve: Curves.easeOutBack,
                            ),
                          ),
                          child: UnitInterior(
                            unit: unit,
                            slots: unitSlots,
                            itemCountBySlot: itemCountBySlot,
                            itemsBySlot: itemsBySlot,
                            highlightSlotId: slot.id,
                            highlightItemName: item.name,
                            onSlotTap: (s) {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      SlotDetailScreen(unit: unit, slot: s),
                                ),
                              );
                            },
                          ),
                        ),
                      )
                    : const Center(child: CircularProgressIndicator()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

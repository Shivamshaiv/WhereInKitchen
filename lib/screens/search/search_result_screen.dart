import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wherein_kitchen/models/item.dart';
import 'package:wherein_kitchen/models/room.dart';
import 'package:wherein_kitchen/models/slot.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';
import 'package:wherein_kitchen/providers/providers.dart';
import 'package:wherein_kitchen/screens/unit/unit_view_screen.dart';

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

    final slot = slots.cast<Slot?>().firstWhere(
          (s) => s?.id == widget.item.slotId,
          orElse: () => null,
        );
    final unit = slot == null
        ? null
        : units.cast<StorageUnit?>().firstWhere(
              (u) => u?.id == slot.unitId,
              orElse: () => null,
            );

    return Scaffold(
      appBar: AppBar(title: Text(widget.item.name)),
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
                      widget.item.name,
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
                    if (widget.item.aliases.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Also: ${widget.item.aliases.join(', ')}',
                        style: Theme.of(context).textTheme.bodySmall,
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
                          child: UnitViewScreen(
                            unit: unit,
                            highlightSlotId: slot.id,
                            highlightItemName: widget.item.name,
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

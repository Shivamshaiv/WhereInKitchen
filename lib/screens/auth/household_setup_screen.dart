import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';
import 'package:wherein_kitchen/providers/providers.dart';

class HouseholdSetupScreen extends ConsumerStatefulWidget {
  const HouseholdSetupScreen({super.key});

  @override
  ConsumerState<HouseholdSetupScreen> createState() =>
      _HouseholdSetupScreenState();
}

class _HouseholdSetupScreenState extends ConsumerState<HouseholdSetupScreen> {
  final _homeNameController = TextEditingController(text: 'Our Home');
  final _joinIdController = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _joinMode = false;

  @override
  void initState() {
    super.initState();
    _loadExistingHousehold();
  }

  Future<void> _loadExistingHousehold() async {
    final user = ref.read(authServiceProvider).currentUser;
    if (user == null) return;

    final householdId = await ref
        .read(householdRepositoryProvider)
        .findHouseholdForUser(user.uid);
    if (householdId != null && mounted) {
      ref.read(householdIdProvider.notifier).state = householdId;
    }
  }

  @override
  void dispose() {
    _homeNameController.dispose();
    _joinIdController.dispose();
    super.dispose();
  }

  Future<void> _createHousehold() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = ref.read(authServiceProvider).currentUser;
      if (user == null) return;

      final householdId = const Uuid().v4();
      await ref.read(householdRepositoryProvider).createHousehold(
            id: householdId,
            name: _homeNameController.text.trim(),
            ownerUid: user.uid,
          );

      await _seedKitchen(householdId);
      ref.read(householdIdProvider.notifier).state = householdId;
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _joinHousehold() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = ref.read(authServiceProvider).currentUser;
      if (user == null) return;

      final householdId = _joinIdController.text.trim();
      final household = await ref
          .read(householdRepositoryProvider)
          .getHousehold(householdId);
      if (household == null) {
        throw Exception('Household not found. Check the ID.');
      }

      await ref
          .read(householdRepositoryProvider)
          .addMember(householdId, user.uid);
      ref.read(householdIdProvider.notifier).state = householdId;
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _seedKitchen(String householdId) async {
    final roomRepo = ref.read(roomRepositoryProvider);
    final unitRepo = ref.read(unitRepositoryProvider);
    final slotRepo = ref.read(slotRepositoryProvider);

    final kitchen = await roomRepo.createRoom(
      householdId: householdId,
      name: 'Kitchen',
      sortOrder: 0,
    );

    final units = <({String name, StorageUnitType type, int rows})>[
      (name: 'Main Pantry', type: StorageUnitType.shelf, rows: 4),
      (name: 'Spice Drawer', type: StorageUnitType.drawer, rows: 3),
      (name: 'Upper Cabinets', type: StorageUnitType.cabinet, rows: 3),
      (name: 'Island Drawers', type: StorageUnitType.drawer, rows: 2),
      (name: 'Fridge', type: StorageUnitType.fridge, rows: 4),
    ];

    for (var i = 0; i < units.length; i++) {
      final config = units[i];
      final unit = await unitRepo.createUnit(
        householdId: householdId,
        roomId: kitchen.id,
        name: config.name,
        type: config.type,
        rows: config.rows,
        columns: 1,
        sortOrder: i,
      );
      await slotRepo.ensureSlotsForUnit(householdId: householdId, unit: unit);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set up your home')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Create home')),
                ButtonSegment(value: true, label: Text('Join home')),
              ],
              selected: {_joinMode},
              onSelectionChanged: (value) {
                setState(() => _joinMode = value.first);
              },
            ),
            const SizedBox(height: 24),
            if (!_joinMode) ...[
              TextField(
                controller: _homeNameController,
                decoration: const InputDecoration(
                  labelText: 'Home name',
                  hintText: 'Newark Home',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loading ? null : _createHousehold,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create & seed kitchen'),
              ),
            ] else ...[
              TextField(
                controller: _joinIdController,
                decoration: const InputDecoration(
                  labelText: 'Household ID',
                  hintText: 'Paste ID from your partner',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loading ? null : _joinHousehold,
                child: const Text('Join household'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wherein_kitchen/models/slot.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';
import 'package:wherein_kitchen/providers/providers.dart';
import 'package:wherein_kitchen/widgets/empty_state.dart';

class QrLabelScreen extends ConsumerWidget {
  const QrLabelScreen({
    super.key,
    required this.unit,
    this.slot,
  });

  final StorageUnit unit;
  final Slot? slot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final householdId = ref.watch(householdIdProvider);

    if (slot != null) {
      return _buildSingleLabel(context, slot!);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${unit.name} QR labels',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: householdId == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<Slot>>(
              stream: ref
                  .read(slotRepositoryProvider)
                  .watchSlotsForUnit(householdId, unit.id),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final slots = snapshot.data ?? [];
                if (slots.isEmpty) {
                  return const EmptyState(
                    icon: Icons.shelves,
                    title: 'No shelves to label',
                    subtitle: 'This unit has no shelves to print QR codes for.',
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: slots.length,
                  itemBuilder: (context, index) {
                    final s = slots[index];
                    return Card(
                      child: ListTile(
                        title: Text(s.label),
                        subtitle: Text(_payloadForSlot(s.id)),
                        trailing: const Icon(Icons.qr_code),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => QrLabelScreen(unit: unit, slot: s),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  Widget _buildSingleLabel(BuildContext context, Slot slot) {
    final payload = _payloadForSlot(slot.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${unit.name} · ${slot.label}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(
                  data: payload,
                  version: QrVersions.auto,
                  size: 220,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                unit.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                slot.label,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Text(
                'Print and stick inside the shelf or drawer.\nScan to open this location instantly.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _payloadForSlot(String slotId) => 'whereinkitchen://slot/$slotId';
}

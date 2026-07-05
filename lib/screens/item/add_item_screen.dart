import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wherein_kitchen/models/item.dart';
import 'package:wherein_kitchen/models/slot.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';
import 'package:wherein_kitchen/providers/providers.dart';
import 'package:wherein_kitchen/services/auth_service.dart';
import 'package:wherein_kitchen/widgets/interior/unit_interior.dart';

class AddItemScreen extends ConsumerStatefulWidget {
  const AddItemScreen({
    super.key,
    this.preselectedSlotId,
    this.preselectedUnit,
    this.initialName,
    this.initialCategory,
    this.initialBarcode,
    this.initialImageUrl,
    this.selectSlotOnly = false,
  });

  final String? preselectedSlotId;
  final StorageUnit? preselectedUnit;
  final String? initialName;
  final String? initialCategory;
  final String? initialBarcode;
  final String? initialImageUrl;
  final bool selectSlotOnly;

  @override
  ConsumerState<AddItemScreen> createState() => _AddItemScreenState();
}

class _AddItemScreenState extends ConsumerState<AddItemScreen> {
  final _nameController = TextEditingController();
  final _aliasesController = TextEditingController();
  final _categoryController = TextEditingController(text: 'General');
  final _quantityController = TextEditingController(text: '1');
  final _notesController = TextEditingController();

  String? _selectedSlotId;
  StorageUnit? _selectedUnit;
  String? _thumbB64;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedSlotId = widget.preselectedSlotId;
    _selectedUnit = widget.preselectedUnit;
    if (widget.initialName != null) {
      _nameController.text = widget.initialName!;
    }
    if (widget.initialCategory != null) {
      _categoryController.text = widget.initialCategory!;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _aliasesController.dispose();
    _categoryController.dispose();
    _quantityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 200,
      maxHeight: 200,
      imageQuality: 60,
    );
    if (image == null) return;

    final bytes = await image.readAsBytes();
    final encoded = ImageService.encodeThumbnail(Uint8List.fromList(bytes));
    if (!mounted) return;
    if (encoded == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo too large — try a smaller image')),
      );
      return;
    }
    setState(() => _thumbB64 = encoded);
  }

  Future<void> _save() async {
    final householdId = ref.read(householdIdProvider);
    if (householdId == null || _selectedSlotId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a shelf first')),
      );
      return;
    }

    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _saving = true);

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final aliases = _aliasesController.text
          .split(',')
          .map((a) => a.trim())
          .where((a) => a.isNotEmpty)
          .toList();

      final item = Item(
        id: '',
        householdId: householdId,
        name: name,
        aliases: aliases,
        category: _categoryController.text.trim(),
        slotId: _selectedSlotId!,
        quantity: _quantityController.text.trim(),
        updatedAt: DateTime.now(),
        barcode: widget.initialBarcode,
        imageUrl: widget.initialImageUrl,
        thumbB64: _thumbB64,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      await ref.read(itemRepositoryProvider).addItem(item);

      navigator.popUntil((route) => route.isFirst);
      messenger.showSnackBar(
        SnackBar(content: Text('Added $name')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text("Couldn't save — check your connection and try again."),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickShelf() async {
    final units = ref.read(unitsProvider).value ?? [];
    if (units.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return _ShelfPickerSheet(
          units: units,
          onSelected: (unit, slot) {
            setState(() {
              _selectedUnit = unit;
              _selectedSlotId = slot.id;
            });
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedLabel = _selectedUnit == null
        ? 'Tap to choose shelf'
        : '${_selectedUnit!.name} · shelf selected';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.selectSlotOnly ? 'Choose shelf' : 'Add item'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!widget.selectSlotOnly) ...[
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Item name',
                hintText: 'Jeera, Basmati rice…',
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _aliasesController,
              decoration: const InputDecoration(
                labelText: 'Aliases (comma separated)',
                hintText: 'cumin, cumin seeds',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _categoryController,
              decoration: const InputDecoration(labelText: 'Category'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _quantityController,
              decoration: const InputDecoration(labelText: 'Quantity'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickPhoto,
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(_thumbB64 == null ? 'Add photo' : 'Photo added'),
            ),
            const SizedBox(height: 20),
          ],
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Theme.of(context).colorScheme.outline),
            ),
            leading: const Icon(Icons.place_outlined),
            title: Text(selectedLabel),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickShelf,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save item'),
          ),
        ],
      ),
    );
  }
}

class _ShelfPickerSheet extends ConsumerStatefulWidget {
  const _ShelfPickerSheet({
    required this.units,
    required this.onSelected,
  });

  final List<StorageUnit> units;
  final void Function(StorageUnit unit, Slot slot) onSelected;

  @override
  ConsumerState<_ShelfPickerSheet> createState() => _ShelfPickerSheetState();
}

class _ShelfPickerSheetState extends ConsumerState<_ShelfPickerSheet> {
  StorageUnit? _unit;
  Slot? _selectedSlot;

  @override
  Widget build(BuildContext context) {
    final householdId = ref.watch(householdIdProvider);
    final unit = _unit ?? widget.units.first;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Choose shelf',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<StorageUnit>(
                initialValue: unit,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Storage unit'),
                items: widget.units
                    .map(
                      (u) => DropdownMenuItem(
                        value: u,
                        child: Text(
                          u.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _unit = value),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: householdId == null
                    ? const Center(child: CircularProgressIndicator())
                    : ref.watch(slotsForUnitProvider(unit.id)).when(
                        data: (slots) {
                          if (slots.isEmpty) {
                            return const Center(
                              child: Text('Setting up shelves…'),
                            );
                          }
                          return UnitInterior(
                            unit: unit,
                            slots: slots,
                            itemCountBySlot: const {},
                            selectMode: true,
                            selectedSlotId: _selectedSlot?.id,
                            onSlotTap: (slot) {
                              setState(() => _selectedSlot = slot);
                            },
                          );
                        },
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (e, _) => Center(child: Text('Error: $e')),
                      ),
              ),
              FilledButton(
                onPressed: _selectedSlot == null
                    ? null
                    : () {
                        widget.onSelected(unit, _selectedSlot!);
                        Navigator.pop(context);
                      },
                child: const Text('Confirm shelf'),
              ),
            ],
          ),
        );
      },
    );
  }
}

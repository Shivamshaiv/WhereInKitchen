import 'package:flutter_test/flutter_test.dart';
import 'package:wherein_kitchen/models/item.dart';

void main() {
  group('Item search', () {
    test('matches by name', () {
      final item = _sampleItem(name: 'Jeera', aliases: ['cumin']);
      expect(item.matchesQuery('jeera'), isTrue);
      expect(item.matchesQuery('cumin'), isTrue);
      expect(item.matchesQuery('rice'), isFalse);
    });

    test('matches by category', () {
      final item = _sampleItem(name: 'Basmati', category: 'Rice');
      expect(item.matchesQuery('rice'), isTrue);
    });
  });
}

Item _sampleItem({
  required String name,
  List<String> aliases = const [],
  String category = 'General',
}) {
  return Item(
    id: '1',
    householdId: 'home',
    name: name,
    aliases: aliases,
    category: category,
    slotId: 'slot1',
    quantity: '1',
    updatedAt: DateTime(2026, 1, 1),
  );
}

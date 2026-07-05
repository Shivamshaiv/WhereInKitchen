import 'package:flutter_test/flutter_test.dart';
import 'package:wherein_kitchen/models/slot.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';
import 'package:wherein_kitchen/widgets/interior/slot_tile.dart';

StorageUnit _unit({int rows = 4}) {
  return StorageUnit(
    id: 'u1',
    householdId: 'h1',
    roomId: 'r1',
    name: 'Unit',
    type: StorageUnitType.cabinet,
    rows: rows,
    columns: 1,
    sortOrder: 0,
  );
}

Slot _slot({required int row, int column = 1}) {
  return Slot(
    id: 's$row$column',
    householdId: 'h1',
    unitId: 'u1',
    label: 'Slot',
    row: row,
    column: column,
  );
}

void main() {
  group('effectiveRowCount', () {
    test('uses unit.rows when it exceeds the max slot row', () {
      final rows = effectiveRowCount(
        _unit(rows: 5),
        [_slot(row: 1), _slot(row: 2)],
      );
      expect(rows, 5);
    });

    test('uses max slot row when slots exceed declared rows', () {
      final rows = effectiveRowCount(
        _unit(rows: 2),
        [_slot(row: 1), _slot(row: 7)],
      );
      expect(rows, 7);
    });

    test('never falls below 1 with no slots and zero declared rows', () {
      final rows = effectiveRowCount(_unit(rows: 0), const []);
      expect(rows, 1);
    });

    test('no slots falls back to declared rows', () {
      final rows = effectiveRowCount(_unit(rows: 3), const []);
      expect(rows, 3);
    });

    test('equal declared and max slot row', () {
      final rows = effectiveRowCount(
        _unit(rows: 4),
        [_slot(row: 4)],
      );
      expect(rows, 4);
    });

    test('slot rows unordered still yields the highest', () {
      final rows = effectiveRowCount(
        _unit(rows: 1),
        [_slot(row: 3), _slot(row: 9), _slot(row: 2)],
      );
      expect(rows, 9);
    });
  });
}

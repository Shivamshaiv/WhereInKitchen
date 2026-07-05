import 'package:flutter_test/flutter_test.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';

const double _eps = 1e-9;

StorageUnit _unit({
  StorageUnitType type = StorageUnitType.cabinet,
  int rows = 4,
  int columns = 1,
  UnitMount mount = UnitMount.base,
  int? heightCm,
}) {
  return StorageUnit(
    id: 'u1',
    householdId: 'h1',
    roomId: 'r1',
    name: 'Unit',
    type: type,
    rows: rows,
    columns: columns,
    sortOrder: 0,
    mount: mount,
    heightCm: heightCm,
  );
}

void main() {
  group('defaultCompartments - fridge', () {
    test('1 door: main shelves (+ crisper) and one bin column', () {
      final c = defaultCompartments(_unit(
        type: StorageUnitType.fridge,
        rows: 3,
        columns: 1,
      ));
      // 3 shelves (col 1) + 3 door bins (col 2) = 6.
      expect(c.length, 6);

      final col1 = c.where((e) => e.column == 1).toList();
      expect(col1.map((e) => e.label),
          ['Shelf 1', 'Shelf 2', 'Crisper']); // last row -> Crisper

      final col2 = c.where((e) => e.column == 2).toList();
      expect(col2.length, 3);
      expect(col2.map((e) => e.label),
          ['Door bin 1', 'Door bin 2', 'Door bin 3']);

      // No third column for a single-door fridge.
      expect(c.any((e) => e.column == 3), isFalse);
    });

    test('2 doors: column 2 Left bin, column 3 Right bin', () {
      final c = defaultCompartments(_unit(
        type: StorageUnitType.fridge,
        rows: 2,
        columns: 2,
      ));
      // 2 shelves + 2 left bins + 2 right bins = 6.
      expect(c.length, 6);

      final col2 = c.where((e) => e.column == 2).toList();
      expect(col2.map((e) => e.label), ['Left bin 1', 'Left bin 2']);

      final col3 = c.where((e) => e.column == 3).toList();
      expect(col3.map((e) => e.label), ['Right bin 1', 'Right bin 2']);

      final col1 = c.where((e) => e.column == 1).toList();
      // rows=2 -> Shelf 1 then Crisper (last row).
      expect(col1.map((e) => e.label), ['Shelf 1', 'Crisper']);
    });

    test('door count clamps to [1,2] so 4 columns still means 2 doors', () {
      final c = defaultCompartments(_unit(
        type: StorageUnitType.fridge,
        rows: 1,
        columns: 4,
      ));
      // rows=1: 1 shelf (which is also the crisper row) + left + right = 3.
      expect(c.length, 3);
      expect(c.where((e) => e.column == 1).single.label, 'Crisper');
      expect(c.where((e) => e.column == 2).single.label, 'Left bin 1');
      expect(c.where((e) => e.column == 3).single.label, 'Right bin 1');
      expect(c.any((e) => e.column == 4), isFalse);
    });
  });

  group('defaultCompartments - freezer', () {
    test('single-column stacked drawers, one per row', () {
      final c = defaultCompartments(_unit(
        type: StorageUnitType.freezer,
        rows: 4,
        columns: 3, // columns ignored for freezer
      ));
      expect(c.length, 4);
      expect(c.every((e) => e.column == 1), isTrue);
      expect(c.map((e) => e.label),
          ['Drawer 1', 'Drawer 2', 'Drawer 3', 'Drawer 4']);
      expect(c.map((e) => e.row), [1, 2, 3, 4]);
    });
  });

  group('defaultCompartments - generic grid', () {
    test('rows*cols cells with Row/Col labels', () {
      final c = defaultCompartments(_unit(
        type: StorageUnitType.cabinet,
        rows: 2,
        columns: 3,
      ));
      expect(c.length, 6);
      // Ordered row-major.
      expect(c.first, (row: 1, column: 1, label: 'Row 1 · Col 1'));
      expect(c.last, (row: 2, column: 3, label: 'Row 2 · Col 3'));
    });

    test('single column uses Shelf labels', () {
      final c = defaultCompartments(_unit(
        type: StorageUnitType.shelf,
        rows: 3,
        columns: 1,
      ));
      expect(c.length, 3);
      expect(c.map((e) => e.label), ['Shelf 1', 'Shelf 2', 'Shelf 3']);
    });

    test('rows clamp to kMaxShelfRows', () {
      final c = defaultCompartments(_unit(
        type: StorageUnitType.shelf,
        rows: 100,
        columns: 1,
      ));
      expect(c.length, kMaxShelfRows);
    });

    test('columns clamp to kMaxDoors', () {
      final c = defaultCompartments(_unit(
        type: StorageUnitType.cabinet,
        rows: 1,
        columns: 100,
      ));
      expect(c.length, kMaxDoors);
    });
  });

  group('unitZBand', () {
    test('base derives height from rows when no explicit heightCm', () {
      final band = unitZBand(_unit(mount: UnitMount.base, rows: 4));
      expect(band.bottom, 0);
      // 0.85 + 4 * 0.07 = 1.13
      expect(band.top, closeTo(1.13, _eps));
    });

    test('wall unit sits at fixed bottom and uses explicit height', () {
      final band = unitZBand(_unit(mount: UnitMount.wall, heightCm: 70));
      expect(band.bottom, closeTo(1.75, _eps));
      expect(band.top, closeTo(1.75 + 0.70, _eps)); // bottom + 70/100
    });

    test('explicit heightCm overrides row-derived height', () {
      final band = unitZBand(_unit(mount: UnitMount.tall, rows: 6, heightCm: 210));
      expect(band.bottom, 0);
      expect(band.top, closeTo(2.10, _eps));
    });

    test('rows clamp inside band derivation', () {
      // rows below 1 clamp to 1, base: 0.85 + 1*0.07 = 0.92.
      final band = unitZBand(_unit(mount: UnitMount.base, rows: 0));
      expect(band.top, closeTo(0.92, _eps));
    });
  });

  group('effectiveHeightCm', () {
    test('returns explicit heightCm untouched', () {
      expect(effectiveHeightCm(_unit(heightCm: 123)), 123);
    });

    test('derives from band and clamps to lower bound 20', () {
      // wall + no explicit height, rows=1: top-bottom = 0.5 + 1*0.12 = 0.62 -> 62cm.
      expect(effectiveHeightCm(_unit(mount: UnitMount.wall, rows: 1)), 62);
    });

    test('derived height clamps to upper bound 260', () {
      // tall + rows=6, no explicit: top = 2.9 + 6*0.02 = 3.02 -> 302 -> clamp 260.
      expect(effectiveHeightCm(_unit(mount: UnitMount.tall, rows: 6)), 260);
    });

    test('base rows=4 derives 113cm', () {
      expect(effectiveHeightCm(_unit(mount: UnitMount.base, rows: 4)), 113);
    });
  });

  group('hasElevationPlacement', () {
    StorageUnit withElev({
      String? surfaceId,
      double? xCm,
      double? widthCm,
      double? hCm,
    }) {
      return StorageUnit(
        id: 'u1',
        householdId: 'h1',
        roomId: 'r1',
        name: 'Unit',
        type: StorageUnitType.cabinet,
        rows: 2,
        columns: 1,
        sortOrder: 0,
        surfaceId: surfaceId,
        xCm: xCm,
        widthCm: widthCm,
        hCm: hCm,
      );
    }

    test('true only when surfaceId, xCm, widthCm and hCm are all set', () {
      expect(
        withElev(surfaceId: 'wall:N', xCm: 0, widthCm: 60, hCm: 70)
            .hasElevationPlacement,
        isTrue,
      );
    });

    test('false if any required field is missing', () {
      expect(withElev(xCm: 0, widthCm: 60, hCm: 70).hasElevationPlacement,
          isFalse); // no surfaceId
      expect(
          withElev(surfaceId: 'wall:N', widthCm: 60, hCm: 70)
              .hasElevationPlacement,
          isFalse); // no xCm
      expect(
          withElev(surfaceId: 'wall:N', xCm: 0, hCm: 70).hasElevationPlacement,
          isFalse); // no widthCm
      expect(
          withElev(surfaceId: 'wall:N', xCm: 0, widthCm: 60)
              .hasElevationPlacement,
          isFalse); // no hCm
    });
  });

  group('StorageUnit.fromMap / toMap', () {
    test('tolerates numeric fields stored as double (num casts)', () {
      final map = <String, dynamic>{
        'householdId': 'h1',
        'roomId': 'r1',
        'name': 'Doubled',
        'type': 'cabinet',
        'rows': 3.0, // double where an int is expected
        'columns': 2.0,
        'sortOrder': 5.0,
        'facing': 5.0, // 5 % 4 == 1
        'heightCm': 90.0,
        'gx': 2.0,
        'gy': 3.0,
        'gw': 2.0,
        'gh': 2.0,
        'surfaceId': 'wall:N',
        'xCm': 12.5, // fractional double preserved
        'zCm': 90.0,
        'widthCm': 60.0,
        'hCm': 70.0,
        'depthCm': 40.0,
      };
      final u = StorageUnit.fromMap('doc1', map);
      expect(u.id, 'doc1');
      expect(u.rows, 3);
      expect(u.columns, 2);
      expect(u.sortOrder, 5);
      expect(u.facing, 1); // 5 % 4
      expect(u.heightCm, 90);
      expect(u.gx, 2);
      expect(u.gy, 3);
      expect(u.type, StorageUnitType.cabinet);
      expect(u.surfaceId, 'wall:N');
      expect(u.xCm, closeTo(12.5, _eps));
      expect(u.widthCm, closeTo(60.0, _eps));
    });

    test('tolerates integer Firestore values too', () {
      final map = <String, dynamic>{
        'name': 'Inted',
        'type': 'drawer',
        'rows': 4, // int
        'columns': 1,
        'sortOrder': 0,
        'xCm': 10, // int where a double is expected
        'widthCm': 60,
        'hCm': 70,
        'surfaceId': 'wall:E',
      };
      final u = StorageUnit.fromMap('doc2', map);
      expect(u.rows, 4);
      expect(u.xCm, closeTo(10.0, _eps));
      expect(u.type, StorageUnitType.drawer);
    });

    test('applies defaults for missing fields', () {
      final u = StorageUnit.fromMap('doc3', <String, dynamic>{});
      expect(u.householdId, '');
      expect(u.roomId, '');
      expect(u.name, 'Storage');
      expect(u.type, StorageUnitType.shelf); // unknown/absent -> shelf
      expect(u.rows, 4);
      expect(u.columns, 1);
      expect(u.sortOrder, 0);
      expect(u.gx, -1);
      expect(u.gy, -1);
      expect(u.gw, 2);
      expect(u.gh, 2);
      expect(u.heightCm, isNull);
      expect(u.surfaceId, isNull);
      expect(u.xCm, isNull);
    });

    test('unknown mount falls back to default for the type', () {
      // fridge/freezer default to freestanding; others to base.
      final fridge = StorageUnit.fromMap('doc4', {
        'type': 'fridge',
        'rows': 4,
        'columns': 1,
        'sortOrder': 0,
      });
      expect(fridge.mount, UnitMount.freestanding);

      final cabinet = StorageUnit.fromMap('doc5', {
        'type': 'cabinet',
        'rows': 4,
        'columns': 1,
        'sortOrder': 0,
      });
      expect(cabinet.mount, UnitMount.base);
    });

    test('round-trip preserves fields (fromMap(toMap()) is stable)', () {
      const original = StorageUnit(
        id: 'doc6',
        householdId: 'h1',
        roomId: 'r1',
        name: 'RoundTrip',
        type: StorageUnitType.fridge,
        rows: 3,
        columns: 2,
        sortOrder: 7,
        mount: UnitMount.freestanding,
        facing: 2,
        heightCm: 180,
        gx: 1,
        gy: 2,
        gw: 2,
        gh: 2,
        surfaceId: 'island:i1:E',
        xCm: 12.5,
        zCm: 0,
        widthCm: 75,
        hCm: 180,
        depthCm: 70,
      );
      final restored = StorageUnit.fromMap('doc6', original.toMap());
      expect(restored.name, original.name);
      expect(restored.type, original.type);
      expect(restored.rows, original.rows);
      expect(restored.columns, original.columns);
      expect(restored.sortOrder, original.sortOrder);
      expect(restored.mount, original.mount);
      expect(restored.facing, original.facing);
      expect(restored.heightCm, original.heightCm);
      expect(restored.gx, original.gx);
      expect(restored.gy, original.gy);
      expect(restored.surfaceId, original.surfaceId);
      expect(restored.xCm, original.xCm);
      expect(restored.zCm, original.zCm);
      expect(restored.widthCm, original.widthCm);
      expect(restored.hCm, original.hCm);
      expect(restored.depthCm, original.depthCm);
    });

    test('toMap omits null optional fields', () {
      const u = StorageUnit(
        id: 'doc7',
        householdId: 'h1',
        roomId: 'r1',
        name: 'Bare',
        type: StorageUnitType.cabinet,
        rows: 2,
        columns: 1,
        sortOrder: 0,
      );
      final map = u.toMap();
      expect(map.containsKey('heightCm'), isFalse);
      expect(map.containsKey('surfaceId'), isFalse);
      expect(map.containsKey('xCm'), isFalse);
      expect(map.containsKey('zCm'), isFalse);
      expect(map.containsKey('widthCm'), isFalse);
      expect(map.containsKey('hCm'), isFalse);
      expect(map.containsKey('depthCm'), isFalse);
      // Required legacy grid fields are always present.
      expect(map['gx'], -1);
      expect(map['gy'], -1);
    });
  });

  group('type / mount helpers', () {
    test('appliances and gaps do not hold items', () {
      expect(StorageUnitType.range.holdsItems, isFalse);
      expect(StorageUnitType.sink.holdsItems, isFalse);
      expect(StorageUnitType.dishwasher.holdsItems, isFalse);
      expect(StorageUnitType.gap.holdsItems, isFalse);
      expect(StorageUnitType.cabinet.holdsItems, isTrue);
      expect(StorageUnitType.fridge.holdsItems, isTrue);
    });

    test('mount band occupancy', () {
      expect(UnitMount.wall.occupiesLower, isFalse);
      expect(UnitMount.base.occupiesLower, isTrue);
      expect(UnitMount.wall.occupiesUpper, isTrue);
      expect(UnitMount.base.occupiesUpper, isFalse);
      expect(UnitMount.tall.occupiesUpper, isTrue);
      expect(UnitMount.freestanding.occupiesUpper, isTrue);
    });

    test('hasLayoutPosition requires non-negative grid coords', () {
      expect(_unit().copyWith(gx: 0, gy: 0).hasLayoutPosition, isTrue);
      expect(_unit().copyWith(gx: -1, gy: 0).hasLayoutPosition, isFalse);
    });
  });
}

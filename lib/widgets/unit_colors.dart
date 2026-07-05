import 'package:flutter/material.dart';
import 'package:wherein_kitchen/models/storage_unit.dart';

/// Shared palette for storage units so the 2D plan, 2.5D iso, and 3D views
/// colour a given [StorageUnitType] identically (view parity). Previously each
/// painter carried its own copy of this table with slightly different tints.
Color unitSeedColor(StorageUnitType type) {
  return switch (type) {
    StorageUnitType.shelf => const Color(0xFF8D6E63),
    StorageUnitType.drawer => const Color(0xFF78909C),
    StorageUnitType.cabinet => const Color(0xFFA1887F),
    StorageUnitType.fridge => const Color(0xFF90A4AE),
    StorageUnitType.freezer => const Color(0xFF81D4FA),
    StorageUnitType.range => const Color(0xFF546E7A),
    StorageUnitType.sink => const Color(0xFFB0BEC5),
    StorageUnitType.dishwasher => const Color(0xFF9E9E9E),
    StorageUnitType.oven => const Color(0xFF607D8B),
    StorageUnitType.gap => const Color(0xFF6D6D6D),
    StorageUnitType.other => const Color(0xFF9E9E9E),
  };
}

/// The base fill for a unit: its seed colour blended toward the surface so it
/// sits calmly in the current theme. [tint] is how far to blend (0 = pure seed).
Color unitBaseColor(
  StorageUnitType type,
  ColorScheme scheme, {
  double tint = 0.2,
}) {
  return Color.lerp(
    unitSeedColor(type),
    scheme.surfaceContainerHighest,
    tint,
  )!;
}

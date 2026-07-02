# WhereInKitchen

A cross-platform (Android + iOS) home-inventory app that answers one question:
**"Where did we keep it?"**

Instead of a boring list, WhereInKitchen draws your kitchen as a visual 2.5D map of
rooms, cabinets, pantries and drawers. Add an item once, and later search for it to
see the exact shelf glow and highlight so you can walk right up to it.

## Features

- **Visual 2.5D layout** – build and edit rooms with cabinets/pantries/drawers in an
  isometric view; pan, zoom, and long-press-drag units into place.
- **Fast item management** – quick add, move, mark-used, and swipe-to-delete.
- **Alias-aware search** – type any name/alias and the matching shelf animates and
  highlights.
- **Barcode scanning** – scan a product barcode to auto-fill details via the
  [Open Food Facts](https://world.openfoodfacts.org/) database, or add manually.
- **Shelf QR labels** – print/scan QR labels that jump straight to a shelf.
- **Cloud sync** – households sync across devices in real time, with offline support.
- **Free stack** – runs entirely on Firebase's free Spark plan.

## Tech stack

- **Flutter** (Dart) – single codebase for Android & iOS
- **Riverpod** – state management
- **Firebase** – Auth (email/password + Google), Cloud Firestore (with offline
  persistence)
- **mobile_scanner** – barcode/QR scanning (CameraX + ML Kit on Android)
- **Open Food Facts API** – product barcode lookup

## Data model

```
Household
 └─ Room (e.g. Kitchen)
     └─ StorageUnit (cabinet / pantry / drawer, with grid position gx,gy,gw,gh)
         └─ Slot (a shelf/compartment)
             └─ Item (name, aliases, category, barcode, thumbnail)
```

A `users/{uid}` document maps each signed-in user to their `householdId` for fast,
rule-friendly lookups.

## Getting started

1. Install [Flutter](https://docs.flutter.dev/get-started/install) (3.x).
2. Fetch dependencies:
   ```bash
   flutter pub get
   ```
3. This project is wired to a Firebase project via `lib/firebase_options.dart` and
   `android/app/google-services.json`. To use your own Firebase project, replace those
   with your own config (e.g. via the FlutterFire CLI) and publish the Firestore rules
   in `firestore.rules`.
4. Run on a connected device:
   ```bash
   flutter run
   ```

## Building a release APK

```bash
flutter build apk --release
```

> **Note on the scanner:** R8 code-shrinking is intentionally disabled for the release
> build (`android/app/build.gradle.kts`), and ML Kit / mobile_scanner keep rules live in
> `android/app/proguard-rules.pro`. Without this, R8 strips ML Kit's barcode components
> and the camera fails to start in release builds ("Camera unavailable"). The scan screen
> also manages the camera lifecycle via `WidgetsBindingObserver` so it restarts correctly
> after the app is minimized/resumed.

## Notes / known behavior

- **"Barcode not found" is normal for non-food items.** Open Food Facts only covers
  food/grocery products, so household, cosmetic, or hardware barcodes usually won't
  resolve — the app falls back to a quick manual add. The scanner is still reading the
  barcode correctly; it just has no product database entry.

## Project layout

```
lib/
 ├─ models/          # Household, Room, StorageUnit, Slot, Item, Product
 ├─ data/            # Firestore repositories
 ├─ services/        # Auth, Open Food Facts
 ├─ providers/       # Riverpod providers + household bootstrap
 ├─ screens/         # auth, home, room layout, item, slot, scan, search
 └─ widgets/         # iso_room_view (2.5D renderer), etc.
```

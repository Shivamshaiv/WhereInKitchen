# WhereInKitchen

A visual home‑inventory app that helps you remember **where things are** in your kitchen (and any other room). Lay out your cabinets in 2D / 2.5D / 3D, tap a shelf to see or add what's on it, and scan barcodes to place items fast.

Built with **Flutter** + **Firebase** (Auth, Cloud Firestore). Cross‑platform: Android and iOS.

---

## Features

- **Multi‑view room layouts** of the same data, kept in sync:
  - **2D floor plan** – top‑down editor: drag to place, resize, rotate, set height, stack wall units over base units.
  - **2.5D isometric** – extruded cabinets with visible shelves, mount levels, and appliances.
  - **3D walk‑around** – orbit the camera around the kitchen, rotate individual units in place.
- **Cabinets that feel real** – mount levels (base / wall / tall / island / free‑standing), explicit height (cm), doors/bays (columns), shelf counts, plus appliance & "open space" types.
- **Quick templates** when adding storage (Big cabinet with 2 doors, Drawer stack, Wall cabinet, Tall pantry, Fridge, Sink base, Cooktop/range).
- **Tap‑to‑peek** – zoom into a unit to see a front‑elevation of its shelves and a preview of items on each.
- **Fast item entry** – type to quick‑add, or **scan a barcode** to look up a product and place it straight onto a shelf.
- **Barcode lookup across free databases** – Open Food/Beauty/Products/Pet Food Facts + UPCitemdb, tried in order.
- **Multiple homes** – switch between homes, create new ones, and **join a home via QR code or a share code** (cross‑platform).
- **Shelf QR labels** – print/scan a QR on a shelf to jump straight to it.
- **Settings → barcode API usage** – per‑source daily & all‑time call counts with free‑tier limit tracking (e.g. UPCitemdb's 100 lookups/day).

---

## Tech stack

- **Flutter** (Material 3), **Dart**
- **Riverpod** for state management
- **Firebase**: `firebase_auth`, `cloud_firestore`, `firebase_core`
- `mobile_scanner` (barcodes/QR), `qr_flutter` (QR generation)
- `shared_preferences` (local usage stats), `image_picker`, `http`, `google_sign_in`

---

## Getting started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart SDK `>=3.2.0 <4.0.0`)
- A Firebase project (the app expects a project id of `whereinkitchen`, or reconfigure — see below)

```bash
flutter pub get
flutter run
```

### Android (works from Windows / macOS / Linux)
`android/app/google-services.json` is included. Just:
```bash
flutter run                       # debug on a connected device/emulator
flutter build apk --release       # release APK
```

### iOS (requires a Mac with Xcode)

> iOS cannot be built on Windows — you need macOS + Xcode. Clone the repo on a Mac, then:

```bash
flutter pub get

# The included firebase_options.dart currently has a PLACEHOLDER iOS appId and
# there is no GoogleService-Info.plist yet, so configure Firebase for iOS:
dart pub global activate flutterfire_cli
flutterfire configure --project=whereinkitchen   # select iOS

cd ios && pod install && cd ..
open ios/Runner.xcworkspace   # set your Signing Team + bundle id in Xcode

flutter run                   # simulator, or -d <device> for a real iPhone
```

Notes for iOS:
- Add the `REVERSED_CLIENT_ID` from `GoogleService-Info.plist` as a URL scheme in `ios/Runner/Info.plist` for **Google Sign‑In** to work.
- The **camera/barcode scanner does not work in the iOS Simulator** — use a real device.
- Camera & photo‑library permission strings are already set in `Info.plist`.

---

## Firebase setup

This repo ships with client Firebase config for the `whereinkitchen` project:
- Android: `android/app/google-services.json`
- Options: `lib/firebase_options.dart` (Android/Web filled in; **iOS is a placeholder** — run `flutterfire configure`)

To point the app at **your own** Firebase project, run `flutterfire configure` and enable **Email/Password** (and Google) sign‑in plus **Cloud Firestore** in the Firebase console.

> Firebase client API keys are not secrets — access is controlled by your **Firestore security rules**. Make sure your rules restrict reads/writes to a household's members.

### Data model (Firestore)
```
users/{uid}                         -> { householdId }
households/{id}                     -> { name, members[], createdAt }
households/{id}/rooms/{roomId}
households/{id}/units/{unitId}      -> { name, type, mount, facing, heightCm, rows, columns, gx, gy, gw, gh }
households/{id}/slots/{slotId}      -> { unitId, label, row, column }
households/{id}/items/{itemId}      -> { name, slotId, barcode, imageUrl, ... }
households/{id}/products/{barcode}  -> cached barcode lookups
```

---

## Project structure

```
lib/
  models/            data models (StorageUnit, Household, Item, Slot, Product…)
  data/repositories/ Firestore repositories
  providers/         Riverpod providers + household bootstrap
  services/          auth, product lookup, API usage tracking
  screens/           home, room (2D/2.5D/3D), unit, slot, scan, settings, auth
  widgets/           iso room view, shelf map, reusable UI
```

---

## License

Private project. All rights reserved.

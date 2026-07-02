import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:wherein_kitchen/models/item.dart';
import 'package:wherein_kitchen/models/product.dart';
import 'package:wherein_kitchen/providers/providers.dart';
import 'package:wherein_kitchen/screens/item/add_item_screen.dart';
import 'package:wherein_kitchen/screens/item/item_actions_sheet.dart';
import 'package:wherein_kitchen/screens/search/search_result_screen.dart';
import 'package:wherein_kitchen/screens/slot/slot_detail_screen.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen>
    with WidgetsBindingObserver {
  // We own the controller, so we own its lifecycle. `autoStart: false` means the
  // MobileScanner widget will NOT start it for us; instead we start it in
  // initState and, crucially, restart it whenever the app is resumed. Without
  // this, Android releases the camera when the app is minimized (or the scanner
  // stops) and it never comes back, showing "camera unavailable" on the next
  // open. See the mobile_scanner lifecycle docs.
  final _controller = MobileScannerController(
    autoStart: false,
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.qrCode,
    ],
  );
  StreamSubscription<BarcodeCapture>? _subscription;
  bool _processing = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = _controller.barcodes.listen(_onDetect);
    unawaited(_controller.start());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Permission prompts can fire lifecycle changes before the camera is ready.
    if (!_controller.value.hasCameraPermission) return;

    switch (state) {
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        return;
      case AppLifecycleState.resumed:
        _subscription = _controller.barcodes.listen(_onDetect);
        unawaited(_controller.start());
      case AppLifecycleState.inactive:
        unawaited(_subscription?.cancel());
        _subscription = null;
        unawaited(_controller.stop());
    }
  }

  @override
  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    _subscription = null;
    super.dispose();
    await _controller.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final barcode = capture.barcodes.firstOrNull?.rawValue;
    if (barcode == null || barcode.isEmpty) return;

    setState(() {
      _processing = true;
      _status = 'Scanning $barcode…';
    });

    try {
      await _handleBarcode(barcode);
    } finally {
      if (mounted) {
        setState(() {
          _processing = false;
          _status = null;
        });
      }
    }
  }

  Future<void> _handleBarcode(String barcode) async {
    final householdId = ref.read(householdIdProvider);
    if (householdId == null) return;

    if (barcode.startsWith('whereinkitchen://slot/')) {
      await _handleShelfQr(barcode);
      return;
    }

    final existingItem = await ref
        .read(itemRepositoryProvider)
        .getItemByBarcode(householdId, barcode);

    if (existingItem != null && mounted) {
      await _showKnownItemSheet(existingItem);
      return;
    }

    Product? product = await ref
        .read(productRepositoryProvider)
        .getProduct(householdId, barcode);

    product ??= await ref.read(productLookupServiceProvider).lookupBarcode(
          barcode,
        );

    if (product != null) {
      await ref
          .read(productRepositoryProvider)
          .saveProduct(householdId, product);
    }

    if (!mounted) return;

    if (product != null) {
      await _showNewProductSheet(barcode, product);
    } else {
      await _showUnknownBarcodeSheet(barcode);
    }
  }

  Future<void> _handleShelfQr(String payload) async {
    final householdId = ref.read(householdIdProvider);
    if (householdId == null) return;

    final slotId = payload.replaceFirst('whereinkitchen://slot/', '');
    final slot = await ref.read(slotRepositoryProvider).getSlot(
          householdId,
          slotId,
        );
    if (slot == null || !mounted) return;

    final unit = await ref.read(unitRepositoryProvider).getUnit(
          householdId,
          slot.unitId,
        );
    if (unit == null || !mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SlotDetailScreen(unit: unit, slot: slot),
      ),
    );
  }

  Future<void> _showKnownItemSheet(Item item) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: Text('Found: ${item.name}'),
                subtitle: const Text('Already in your home'),
              ),
              ListTile(
                leading: const Icon(Icons.place_outlined),
                title: const Text('Show location'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SearchResultScreen(item: item),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Add another'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AddItemScreen(
                        initialName: item.name,
                        initialCategory: item.category,
                        initialBarcode: item.barcode,
                        initialImageUrl: item.imageUrl,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.more_horiz),
                title: const Text('Move or remove'),
                onTap: () {
                  Navigator.pop(context);
                  showItemActionsSheet(
                    context: context,
                    ref: ref,
                    item: item,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showNewProductSheet(String barcode, Product product) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: product.imageUrl != null
                    ? Image.network(product.imageUrl!, width: 48, height: 48)
                    : const Icon(Icons.inventory_2_outlined),
                title: Text(product.name),
                subtitle: Text(product.brand.isEmpty
                    ? product.category
                    : '${product.brand} · ${product.category}'),
              ),
              ListTile(
                leading: const Icon(Icons.add_location_alt_outlined),
                title: const Text('Place on shelf'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AddItemScreen(
                        initialName: product.name,
                        initialCategory: product.category,
                        initialBarcode: barcode,
                        initialImageUrl: product.imageUrl,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showUnknownBarcodeSheet(String barcode) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: const Text('Barcode not found'),
                subtitle: Text(barcode),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Add manually'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AddItemScreen(
                        initialBarcode: barcode,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, state, _) {
              final on = state.torchState == TorchState.on;
              return IconButton(
                tooltip: on ? 'Turn off flash' : 'Turn on flash',
                onPressed: () => _controller.toggleTorch(),
                icon: Icon(on ? Icons.flash_on : Icons.flash_off,
                    color: on ? Colors.amber : Colors.white),
              );
            },
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            fit: BoxFit.cover,
            errorBuilder: (context, error, _) => _CameraError(
              error: error,
              onRetry: () async {
                // Fully cycle the camera so a busy/interrupted device recovers,
                // and make sure we're listening to barcode events again.
                await _controller.stop();
                await _subscription?.cancel();
                _subscription = _controller.barcodes.listen(_onDetect);
                await _controller.start();
              },
            ),
            placeholderBuilder: (context, _) => const ColoredBox(
              color: Colors.black,
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          ),
          const _ScannerReticle(),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)],
                ),
              ),
              child: Text(
                _status ?? 'Point at a product barcode or shelf QR label',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          if (_processing)
            const ColoredBox(
              color: Colors.black38,
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

/// Decorative centered viewfinder with animated corner brackets.
class _ScannerReticle extends StatelessWidget {
  const _ScannerReticle();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: AspectRatio(
          aspectRatio: 1,
          child: FractionallySizedBox(
            widthFactor: 0.72,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.9),
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 40,
                    spreadRadius: 8,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Friendly camera error / permission screen with a retry action.
class _CameraError extends StatelessWidget {
  const _CameraError({required this.error, required this.onRetry});

  final MobileScannerException error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final permissionDenied =
        error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                permissionDenied
                    ? Icons.no_photography_outlined
                    : Icons.videocam_off_outlined,
                color: Colors.white70,
                size: 64,
              ),
              const SizedBox(height: 20),
              Text(
                permissionDenied
                    ? 'Camera permission is off'
                    : 'Camera unavailable',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                permissionDenied
                    ? 'Allow camera access for WhereInKitchen in your device settings, then tap retry.'
                    : 'Could not start the camera. Close any other app using it and retry.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

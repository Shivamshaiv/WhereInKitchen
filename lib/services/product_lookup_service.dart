import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:wherein_kitchen/models/product.dart';

/// Looks up a barcode across several completely-free, no-API-key product
/// databases and returns the first match.
///
/// Sources, tried in order (best coverage first):
///  1. Open Food Facts        – groceries / food
///  2. Open Beauty Facts       – cosmetics / personal care
///  3. Open Products Facts     – general non-food products
///  4. Open Pet Food Facts     – pet food
///  5. UPCitemdb (free trial)  – broad retail catalog (electronics, household…)
///
/// The four Open*Facts projects share the same v2 API shape, so they use one
/// parser; UPCitemdb has its own response format.
class ProductLookupService {
  ProductLookupService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 6);
  // Open Food Facts asks callers to identify themselves via User-Agent.
  static const Map<String, String> _headers = {
    'User-Agent': 'WhereInKitchen/1.0 (Flutter home inventory app)',
  };

  /// The Open*Facts endpoints, paired with the `source` label we store.
  static const List<({String host, String source, String fallbackCategory})>
      _openFactsSources = [
    (
      host: 'world.openfoodfacts.org',
      source: 'open_food_facts',
      fallbackCategory: 'Food',
    ),
    (
      host: 'world.openbeautyfacts.org',
      source: 'open_beauty_facts',
      fallbackCategory: 'Beauty',
    ),
    (
      host: 'world.openproductsfacts.org',
      source: 'open_products_facts',
      fallbackCategory: 'General',
    ),
    (
      host: 'world.openpetfoodfacts.org',
      source: 'open_pet_food_facts',
      fallbackCategory: 'Pet food',
    ),
  ];

  Future<Product?> lookupBarcode(String barcode) async {
    final code = barcode.trim();
    if (code.isEmpty) return null;

    for (final src in _openFactsSources) {
      final product = await _tryOpenFacts(code, src);
      if (product != null) return product;
    }

    return _tryUpcItemDb(code);
  }

  Future<Product?> _tryOpenFacts(
    String barcode,
    ({String host, String source, String fallbackCategory}) src,
  ) async {
    try {
      final uri = Uri.parse(
        'https://${src.host}/api/v2/product/$barcode.json',
      );
      final response = await _client.get(uri, headers: _headers).timeout(_timeout);
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['status'] != 1) return null;

      final product = data['product'] as Map<String, dynamic>?;
      if (product == null) return null;

      final name = _firstNonEmpty([
        product['product_name'] as String?,
        product['product_name_en'] as String?,
        product['generic_name'] as String?,
        product['abbreviated_product_name'] as String?,
      ]);
      if (name == null) return null;

      return Product(
        barcode: barcode,
        name: name,
        brand: (product['brands'] as String?)?.trim() ?? '',
        category: _extractOpenFactsCategory(product, src.fallbackCategory),
        imageUrl: _firstNonEmpty([
          product['image_front_small_url'] as String?,
          product['image_small_url'] as String?,
          product['image_front_url'] as String?,
          product['image_url'] as String?,
        ]),
        source: src.source,
        updatedAt: DateTime.now(),
      );
    } catch (_) {
      // Network error / timeout / bad JSON: just fall through to the next source.
      return null;
    }
  }

  Future<Product?> _tryUpcItemDb(String barcode) async {
    try {
      final uri = Uri.parse(
        'https://api.upcitemdb.com/prod/trial/lookup?upc=$barcode',
      );
      final response = await _client.get(uri, headers: _headers).timeout(_timeout);
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['code'] != 'OK') return null;

      final items = data['items'] as List?;
      if (items == null || items.isEmpty) return null;

      final item = items.first as Map<String, dynamic>;
      final name = _firstNonEmpty([item['title'] as String?]);
      if (name == null) return null;

      final images = item['images'] as List?;
      final imageUrl = (images != null && images.isNotEmpty)
          ? images.first.toString()
          : null;

      return Product(
        barcode: barcode,
        name: name,
        brand: (item['brand'] as String?)?.trim() ?? '',
        category: _firstNonEmpty([item['category'] as String?]) ?? 'General',
        imageUrl: imageUrl,
        source: 'upcitemdb',
        updatedAt: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  String _extractOpenFactsCategory(
    Map<String, dynamic> product,
    String fallback,
  ) {
    final categories = product['categories_tags'] as List?;
    if (categories != null && categories.isNotEmpty) {
      // Prefer the most specific (last) tag, and prettify it.
      final raw = categories.last.toString();
      final cleaned = raw
          .replaceAll(RegExp(r'^[a-z]{2}:'), '')
          .replaceAll('-', ' ')
          .trim();
      if (cleaned.isNotEmpty) {
        return cleaned[0].toUpperCase() + cleaned.substring(1);
      }
    }
    return fallback;
  }

  String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }
}

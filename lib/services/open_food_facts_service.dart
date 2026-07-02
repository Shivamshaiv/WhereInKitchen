import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:wherein_kitchen/models/product.dart';

class OpenFoodFactsService {
  OpenFoodFactsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<Product?> lookupBarcode(String barcode) async {
    final uri = Uri.parse(
      'https://world.openfoodfacts.org/api/v2/product/$barcode.json',
    );
    final response = await _client.get(uri);
    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['status'] != 1) return null;

    final product = data['product'] as Map<String, dynamic>?;
    if (product == null) return null;

    final name = (product['product_name'] as String?)?.trim();
    if (name == null || name.isEmpty) return null;

    return Product(
      barcode: barcode,
      name: name,
      brand: (product['brands'] as String?)?.trim() ?? '',
      category: _extractCategory(product),
      imageUrl: product['image_front_small_url'] as String?,
      source: 'open_food_facts',
      updatedAt: DateTime.now(),
    );
  }

  String _extractCategory(Map<String, dynamic> product) {
    final categories = product['categories_tags'] as List?;
    if (categories != null && categories.isNotEmpty) {
      final raw = categories.first.toString();
      return raw.replaceAll('en:', '').replaceAll('-', ' ');
    }
    return 'General';
  }
}

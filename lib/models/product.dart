class Product {
  const Product({
    required this.barcode,
    required this.name,
    required this.brand,
    required this.category,
    required this.imageUrl,
    required this.source,
    required this.updatedAt,
  });

  final String barcode;
  final String name;
  final String brand;
  final String category;
  final String? imageUrl;
  final String source;
  final DateTime updatedAt;

  factory Product.fromMap(String barcode, Map<String, dynamic> map) {
    return Product(
      barcode: barcode,
      name: map['name'] as String? ?? 'Unknown',
      brand: map['brand'] as String? ?? '',
      category: map['category'] as String? ?? 'General',
      imageUrl: map['imageUrl'] as String?,
      source: map['source'] as String? ?? 'manual',
      updatedAt: (map['updatedAt'] as dynamic)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'brand': brand,
        'category': category,
        if (imageUrl != null) 'imageUrl': imageUrl,
        'source': source,
        'updatedAt': updatedAt,
      };
}

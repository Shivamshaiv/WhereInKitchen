import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wherein_kitchen/data/firestore_paths.dart';
import 'package:wherein_kitchen/models/product.dart';

class ProductRepository {
  ProductRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _collection(String householdId) =>
      _firestore.collection(FirestorePaths.products(householdId));

  Future<Product?> getProduct(String householdId, String barcode) async {
    final doc = await _collection(householdId).doc(barcode).get();
    if (!doc.exists) return null;
    return Product.fromMap(barcode, doc.data()!);
  }

  Future<void> saveProduct(String householdId, Product product) async {
    await _collection(householdId)
        .doc(product.barcode)
        .set(product.toMap(), SetOptions(merge: true));
  }
}

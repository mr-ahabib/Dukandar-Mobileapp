import 'package:flutter/material.dart';
import '../core/database/app_database.dart';
import '../core/utils/perf.dart';
import '../models/product.dart';

/// Inventory. Exposed as a singleton so screens can attach it with
/// `ChangeNotifierProvider.value(value: ProductsProvider.instance)` even when
/// main.dart does not register it.
class ProductsProvider extends ChangeNotifier {
  static final ProductsProvider instance = ProductsProvider._();

  /// No I/O in the constructor: the singleton is created while the widget
  /// tree is first built, so loading waits for `AppBootstrap`.
  ProductsProvider._();

  final AppDatabase _db = AppDatabase.instance;
  List<Product> _products = [];
  bool _isLoading = false;
  bool _loadedOnce = false;
  String _query = '';
  List<Product>? _filtered;
  List<Product>? _lowStock;

  bool get isLoading => _isLoading;
  bool get loadedOnce => _loadedOnce;
  String get query => _query;
  List<Product> get allProducts => _products;

  List<Product> get products => _filtered ??= _query.isEmpty
      ? _products
      : [
          for (final p in _products)
            if (p.searchKey.contains(_query)) p,
        ];

  List<Product> get lowStock => _lowStock ??= [
        for (final p in _products)
          if (p.isLowStock) p,
      ];
  int get lowStockCount => lowStock.length;

  void setQuery(String q) {
    final norm = q.trim().toLowerCase();
    if (norm == _query) return;
    _query = norm;
    _filtered = null;
    notifyListeners();
  }

  void _setProducts(List<Product> list) {
    _products = list;
    _filtered = null;
    _lowStock = null;
  }

  Future<void> ensureLoaded() => _loadedOnce || _isLoading ? Future.value() : load();

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    final t = Perf.start('products.load');
    try {
      _setProducts(await _db.getProducts());
      t.stop('${_products.length} products');
    } catch (e) {
      debugPrint('Error loading products: $e');
    } finally {
      _isLoading = false;
      _loadedOnce = true;
      notifyListeners();
    }
  }

  Future<Product> addProduct({
    required String name,
    required String unit,
    required double salePrice,
    double buyPrice = 0,
    double stock = 0,
    double lowStockAlert = 0,
  }) async {
    final product = Product(
      id: 'prod_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim(),
      unit: unit.trim().isEmpty ? 'পিস' : unit.trim(),
      salePrice: salePrice,
      buyPrice: buyPrice,
      stock: stock,
      lowStockAlert: lowStockAlert,
      updatedAt: DateTime.now(),
    );
    await _db.insertProduct(product);
    _setProducts([..._products, product].._sortByName());
    notifyListeners();
    return product;
  }

  Future<void> updateProduct(Product product) async {
    final updated = product.copyWith(updatedAt: DateTime.now());
    await _db.updateProduct(updated);
    _setProducts([for (final p in _products) p.id == updated.id ? updated : p].._sortByName());
    notifyListeners();
  }

  Future<void> deleteProduct(String id) async {
    await _db.deleteProduct(id);
    _setProducts(_products.where((p) => p.id != id).toList());
    notifyListeners();
  }

  Future<void> addStock(String id, double qty) async {
    await _db.adjustStock(id, qty);
    _setProducts([
      for (final p in _products)
        p.id == id ? p.copyWith(stock: p.stock + qty, updatedAt: DateTime.now()) : p,
    ]);
    notifyListeners();
  }

  /// Applies stock deltas from a saved memo in memory (no DB round trip:
  /// the DB layer already decremented inside the memo transaction).
  void applyStockDeltas(Map<String, double> deltaByProductId) {
    if (deltaByProductId.isEmpty) return;
    _setProducts([
      for (final p in _products)
        deltaByProductId.containsKey(p.id)
            ? p.copyWith(stock: p.stock + deltaByProductId[p.id]!, updatedAt: DateTime.now())
            : p,
    ]);
    notifyListeners();
  }
}

extension on List<Product> {
  void _sortByName() => sort((a, b) => a.searchKey.compareTo(b.searchKey));
}

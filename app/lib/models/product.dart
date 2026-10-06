class Product {
  final String id;
  final String name;
  final String unit; // কেজি, পিস, লিটার ...
  final double salePrice;
  final double buyPrice;
  final double stock;
  final double lowStockAlert;
  final DateTime updatedAt;

  Product({
    required this.id,
    required this.name,
    this.unit = 'পিস',
    required this.salePrice,
    this.buyPrice = 0.0,
    this.stock = 0.0,
    this.lowStockAlert = 0.0,
    required this.updatedAt,
  });

  bool get isLowStock => lowStockAlert > 0 && stock <= lowStockAlert;

  /// Pre-lowercased name used by search (computed once).
  late final String searchKey = name.toLowerCase();
  bool get isOutOfStock => stock <= 0;
  double get margin => salePrice - buyPrice;

  Product copyWith({
    String? name,
    String? unit,
    double? salePrice,
    double? buyPrice,
    double? stock,
    double? lowStockAlert,
    DateTime? updatedAt,
  }) =>
      Product(
        id: id,
        name: name ?? this.name,
        unit: unit ?? this.unit,
        salePrice: salePrice ?? this.salePrice,
        buyPrice: buyPrice ?? this.buyPrice,
        stock: stock ?? this.stock,
        lowStockAlert: lowStockAlert ?? this.lowStockAlert,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'unit': unit,
        'sale_price': salePrice,
        'buy_price': buyPrice,
        'stock': stock,
        'low_stock_alert': lowStockAlert,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Product.fromMap(Map<String, dynamic> map) => Product(
        id: map['id']?.toString() ?? '',
        name: map['name'] as String? ?? '',
        unit: map['unit'] as String? ?? 'পিস',
        salePrice: (map['sale_price'] as num?)?.toDouble() ?? 0.0,
        buyPrice: (map['buy_price'] as num?)?.toDouble() ?? 0.0,
        stock: (map['stock'] as num?)?.toDouble() ?? 0.0,
        lowStockAlert: (map['low_stock_alert'] as num?)?.toDouble() ?? 0.0,
        updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ?? DateTime.now(),
      );
}

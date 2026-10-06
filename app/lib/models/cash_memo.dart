import 'dart:convert';

class MemoItem {
  final String name;
  final double quantity;
  final double unitPrice;
  final String? productId;

  MemoItem({required this.name, required this.quantity, required this.unitPrice, this.productId});

  double get total => quantity * unitPrice;

  Map<String, dynamic> toMap() => {
        'name': name,
        'quantity': quantity,
        'unit_price': unitPrice,
        if (productId != null) 'product_id': productId,
      };

  factory MemoItem.fromMap(Map<String, dynamic> map) => MemoItem(
        name: map['name'] as String? ?? '',
        quantity: (map['quantity'] as num?)?.toDouble() ?? 1.0,
        unitPrice: (map['unit_price'] as num?)?.toDouble() ?? 0.0,
        productId: map['product_id'] as String?,
      );
}

class CashMemo {
  final String id;
  final String memoNumber;
  final String customerName;
  final String customerPhone;
  final String? customerId;
  final double discount;
  final double paidAmount;
  final DateTime date;

  // Items are decoded lazily for rows read from the DB: a 200-memo list no
  // longer JSON-decodes every memo on load, only the ones actually shown.
  List<MemoItem>? _items;
  final String? _itemsJson;
  final double? _storedGrandTotal;

  CashMemo({
    required this.id,
    required this.memoNumber,
    required this.customerName,
    required this.customerPhone,
    this.customerId,
    required List<MemoItem> items,
    this.discount = 0.0,
    required this.paidAmount,
    required this.date,
  })  : _items = items, // ignore: prefer_initializing_formals
        _itemsJson = null,
        _storedGrandTotal = null;

  /// DB row constructor: keeps the raw `items_json` and the stored
  /// `grand_total` so list views never touch the JSON.
  CashMemo.lazy({
    required this.id,
    required this.memoNumber,
    required this.customerName,
    required this.customerPhone,
    this.customerId,
    required String itemsJson,
    required double grandTotal,
    this.discount = 0.0,
    required this.paidAmount,
    required this.date,
  })  : _items = null,
        _itemsJson = itemsJson, // ignore: prefer_initializing_formals
        _storedGrandTotal = grandTotal;

  List<MemoItem> get items => _items ??= decodeItems(_itemsJson);

  /// True when [items] has already been decoded (or was given directly).
  bool get itemsDecoded => _items != null;

  /// Pre-lowercased key for search. Built once per instance.
  late final String searchKey = '$customerName $memoNumber'.toLowerCase();

  /// Safe decoder: malformed / missing JSON yields an empty list instead of
  /// crashing the whole list load.
  static List<MemoItem> decodeItems(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      final raw = jsonDecode(json);
      if (raw is! List) return const [];
      return [
        for (final e in raw)
          if (e is Map) MemoItem.fromMap(Map<String, dynamic>.from(e)),
      ];
    } catch (_) {
      return const [];
    }
  }

  // Money rules (see lib/core/utils/money_rules.md):
  //   subtotal   = Σ qty × unit price
  //   grandTotal = max(0, subtotal − discount)
  //   cash kept  = min(paid, grandTotal)      ← "নগদ বিক্রি"
  //   due        = max(0, grandTotal − paid)  ← the only amount posted to the ledger
  //   change     = max(0, paid − grandTotal)  ← "ফেরত", never revenue
  double get subtotal => items.fold(0.0, (sum, item) => sum + item.total);
  double get grandTotal {
    final stored = _storedGrandTotal;
    if (_items == null && stored != null) return stored;
    return (subtotal - discount) > 0 ? (subtotal - discount) : 0.0;
  }

  double get cashReceived => paidAmount < grandTotal ? paidAmount : grandTotal;
  double get dueAmount => (grandTotal - paidAmount) > 0 ? (grandTotal - paidAmount) : 0.0;
  double get changeAmount => (paidAmount - grandTotal) > 0 ? (paidAmount - grandTotal) : 0.0;
  bool get isFullyPaid => dueAmount <= 0;

  /// Raw items JSON (encodes on demand when the memo was built in memory).
  String get itemsJson {
    final raw = _itemsJson;
    if (_items == null && raw != null) return raw;
    return jsonEncode(items.map((e) => e.toMap()).toList());
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'memo_number': memoNumber,
        'customer_name': customerName,
        'customer_phone': customerPhone,
        'customer_id': customerId,
        'items': items.map((e) => e.toMap()).toList(),
        'discount': discount,
        'paid_amount': paidAmount,
        'date': date.toIso8601String(),
      };

  factory CashMemo.fromMap(Map<String, dynamic> map) => CashMemo(
        id: map['id']?.toString() ?? '',
        memoNumber: map['memo_number']?.toString() ?? '',
        customerName: map['customer_name'] as String? ?? 'সাধারণ ক্রেতা',
        customerPhone: map['customer_phone'] as String? ?? '',
        customerId: map['customer_id'] as String?,
        items: (map['items'] as List<dynamic>?)
                ?.whereType<Map>()
                .map((e) => MemoItem.fromMap(Map<String, dynamic>.from(e)))
                .toList() ??
            [],
        discount: (map['discount'] as num?)?.toDouble() ?? 0.0,
        paidAmount: (map['paid_amount'] as num?)?.toDouble() ?? 0.0,
        date: DateTime.tryParse(map['date'] as String? ?? '') ?? DateTime.now(),
      );
}

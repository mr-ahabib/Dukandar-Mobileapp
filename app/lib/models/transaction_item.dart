enum TransactionType {
  gave, // দিলাম (Customer: বাকি দিলাম | Supplier: টাকা দিলাম)
  got, // পেলাম (Customer: টাকা পেলাম | Supplier: মালামাল পেলাম)
}

class TransactionItem {
  final String id;
  final String customerId;
  final TransactionType type;
  final double amount;
  final String note;
  final DateTime date;
  final String? memoId;
  final String? photoPath;

  TransactionItem({
    required this.id,
    required this.customerId,
    required this.type,
    required this.amount,
    this.note = '',
    required this.date,
    this.memoId,
    this.photoPath,
  });

  TransactionItem copyWith({
    TransactionType? type,
    double? amount,
    String? note,
    DateTime? date,
    String? memoId,
    String? photoPath,
    bool clearPhoto = false,
  }) =>
      TransactionItem(
        id: id,
        customerId: customerId,
        type: type ?? this.type,
        amount: amount ?? this.amount,
        note: note ?? this.note,
        date: date ?? this.date,
        memoId: memoId ?? this.memoId,
        photoPath: clearPhoto ? null : (photoPath ?? this.photoPath),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'customer_id': customerId,
        'type': type.name,
        'amount': amount,
        'note': note,
        'date': date.toIso8601String(),
        'memo_id': memoId,
        'photo_path': photoPath,
      };

  factory TransactionItem.fromMap(Map<String, dynamic> map) => TransactionItem(
        id: map['id']?.toString() ?? '',
        customerId: map['customer_id']?.toString() ?? '',
        type: map['type'] == 'got' ? TransactionType.got : TransactionType.gave,
        amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
        note: map['note'] as String? ?? '',
        date: DateTime.tryParse(map['date'] as String? ?? '') ?? DateTime.now(),
        memoId: map['memo_id'] as String?,
        photoPath: map['photo_path'] as String?,
      );
}

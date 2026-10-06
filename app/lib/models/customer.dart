enum ContactType {
  customer, // খরিদ্দার (বাকি রাখে / দেয়)
  supplier, // মহাজন / পাইকার (যাকে আমাদের দিতে হয়)
}

class Customer {
  final String id;
  final String name;
  final String phone;
  final String address;
  final ContactType type;
  final double currentBalance; // Positive: Customer owes shop / Shop owes supplier
  final DateTime updatedAt;
  final String? photoPath;
  final String note;

  Customer({
    required this.id,
    required this.name,
    required this.phone,
    this.address = '',
    required this.type,
    this.currentBalance = 0.0,
    required this.updatedAt,
    this.photoPath,
    this.note = '',
  });

  bool get isCustomer => type == ContactType.customer;

  /// Pre-lowercased "name phone" used by list search (computed once).
  late final String searchKey = '${name.toLowerCase()} $phone';

  Customer copyWith({
    String? id,
    String? name,
    String? phone,
    String? address,
    ContactType? type,
    double? currentBalance,
    DateTime? updatedAt,
    String? photoPath,
    bool clearPhoto = false,
    String? note,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      type: type ?? this.type,
      currentBalance: currentBalance ?? this.currentBalance,
      updatedAt: updatedAt ?? this.updatedAt,
      photoPath: clearPhoto ? null : (photoPath ?? this.photoPath),
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'address': address,
        'type': type.name,
        'current_balance': currentBalance,
        'updated_at': updatedAt.toIso8601String(),
        'photo_path': photoPath,
        'note': note,
      };

  factory Customer.fromMap(Map<String, dynamic> map) => Customer(
        id: map['id']?.toString() ?? '',
        name: map['name'] as String? ?? '',
        phone: map['phone'] as String? ?? '',
        address: map['address'] as String? ?? '',
        type: (map['type'] == 'supplier') ? ContactType.supplier : ContactType.customer,
        currentBalance: (map['current_balance'] as num?)?.toDouble() ?? 0.0,
        updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ?? DateTime.now(),
        photoPath: map['photo_path'] as String?,
        note: map['note'] as String? ?? '',
      );
}

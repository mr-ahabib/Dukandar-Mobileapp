class DailyExpense {
  final String id;
  final String title;
  final String category; // দোকান ভাড়া, কারেন্ট বিল, নাস্তা/চা, স্টাফ বেতন, অন্যান্য
  final double amount;
  final DateTime date;

  DailyExpense({
    required this.id,
    required this.title,
    required this.category,
    required this.amount,
    required this.date,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'category': category,
      'amount': amount,
      'date': date.toIso8601String(),
    };
  }

  factory DailyExpense.fromMap(Map<String, dynamic> map) {
    return DailyExpense(
      id: map['id']?.toString() ?? '',
      title: map['title'] as String? ?? 'খরচ',
      category: map['category'] as String? ?? 'অন্যান্য',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      date: DateTime.tryParse(map['date'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// Offline Bangla/English voice sentence analyser for Dukandar.
///
/// Everything here is pure string processing — no network.
library;

class VoiceItemResult {
  final String originalText;
  final String itemName;
  final double quantity;
  final double unitPrice;
  final String unit;

  VoiceItemResult({
    required this.originalText,
    required this.itemName,
    required this.quantity,
    required this.unitPrice,
    this.unit = '',
  });

  double get total => quantity * unitPrice;
}

enum VoiceIntent { gave, got, unknown }

class VoiceLedgerResult {
  final String originalText;
  final String? customerName;
  final VoiceIntent intent;
  final double? amount;
  final String note;
  const VoiceLedgerResult({
    required this.originalText,
    this.customerName,
    this.intent = VoiceIntent.unknown,
    this.amount,
    this.note = '',
  });
}

class VoiceExpenseResult {
  final String originalText;
  final String title;
  final String category;
  final double? amount;
  const VoiceExpenseResult({required this.originalText, required this.title, required this.category, this.amount});
}

class VoiceContactResult {
  final String originalText;
  final String name;
  final String phone;
  const VoiceContactResult({required this.originalText, required this.name, required this.phone});
}

class VoiceProductResult {
  final String originalText;
  final String name;
  final String unit;
  final double? price;
  final double? stock;
  const VoiceProductResult({required this.originalText, required this.name, required this.unit, this.price, this.stock});
}

class VoiceParser {
  VoiceParser._();

  static const Map<String, String> _bnToEnDigits = {
    '০': '0', '১': '1', '২': '2', '৩': '3', '৪': '4',
    '৫': '5', '৬': '6', '৭': '7', '৮': '8', '৯': '9',
  };

  /// Simple number words (Bangla + English).
  static const Map<String, double> _numberWords = {
    'শূন্য': 0, 'এক': 1, 'দুই': 2, 'তিন': 3, 'চার': 4, 'পাঁচ': 5, 'পাচ': 5, 'ছয়': 6, 'সাত': 7,
    'আট': 8, 'নয়': 9, 'দশ': 10, 'এগারো': 11, 'এগার': 11, 'বারো': 12, 'বার': 12, 'তেরো': 13, 'তের': 13,
    'চৌদ্দ': 14, 'পনেরো': 15, 'পনের': 15, 'ষোল': 16, 'ষোলো': 16, 'সতেরো': 17, 'সতের': 17, 'আঠারো': 18, 'আঠার': 18,
    'উনিশ': 19, 'বিশ': 20, 'কুড়ি': 20, 'একুশ': 21, 'বাইশ': 22, 'তেইশ': 23, 'চব্বিশ': 24, 'পঁচিশ': 25, 'পচিশ': 25,
    'ছাব্বিশ': 26, 'সাতাশ': 27, 'আঠাশ': 28, 'ঊনত্রিশ': 29, 'উনত্রিশ': 29, 'ত্রিশ': 30, 'তিরিশ': 30, 'পঁয়ত্রিশ': 35,
    'চল্লিশ': 40, 'পঁয়তাল্লিশ': 45, 'পঞ্চাশ': 50, 'পঞ্চান্ন': 55, 'ষাট': 60, 'পঁয়ষট্টি': 65, 'সত্তর': 70, 'পঁচাত্তর': 75,
    'আশি': 80, 'পঁচাশি': 85, 'নব্বই': 90, 'পঁচানব্বই': 95,
    'দেড়': 1.5, 'আড়াই': 2.5,
    'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
    'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50, 'sixty': 60, 'seventy': 70, 'eighty': 80, 'ninety': 90,
  };

  /// Multipliers. "শ"/"শো" are also handled as suffixes (তিনশ, পাঁচশো).
  static const Map<String, double> _multipliers = {
    'শত': 100, 'শো': 100, 'শ': 100, 'হাজার': 1000, 'লাখ': 100000, 'লক্ষ': 100000,
    'hundred': 100, 'thousand': 1000, 'lakh': 100000, 'lac': 100000,
  };

  /// Special compound words.
  static const Map<String, double> _specials = {
    'দেড়শ': 150, 'দেড়শো': 150, 'আড়াইশ': 250, 'আড়াইশো': 250, 'দেড়হাজার': 1500, 'আড়াইহাজার': 2500,
  };

  static const List<String> _units = [
    'কেজি', 'কিলো', 'kg', 'গ্রাম', 'লিটার', 'লি', 'liter', 'litre', 'পিস', 'টা', 'টি', 'খানা', 'ডজন', 'প্যাকেট', 'প্যাক',
    'কার্টুন', 'ব্যাগ', 'বস্তা', 'জোড়া', 'হালি', 'বোতল', 'কেস', 'pcs', 'pc', 'dozen',
  ];

  static const Map<String, String> _unitCanonical = {
    'কিলো': 'কেজি', 'kg': 'কেজি', 'লি': 'লিটার', 'liter': 'লিটার', 'litre': 'লিটার', 'টা': 'পিস', 'টি': 'পিস',
    'খানা': 'পিস', 'pcs': 'পিস', 'pc': 'পিস', 'dozen': 'ডজন', 'প্যাক': 'প্যাকেট',
  };

  static const List<String> _priceKeywords = [
    'টাকা করে', 'টাকা দরে', 'টাকা দর', 'টাকার', 'টাকায়', 'টাকা', 'দরে', 'দর', 'করে', 'tk', 'taka',
  ];

  static const List<String> _gaveWords = ['দিলাম', 'বাকি', 'বাকী', 'নিল', 'নিলো', 'নিয়েছে', 'নিয়েছেন', 'ধার', 'নিলেন', 'দিয়েছি', 'বাকিতে'];
  static const List<String> _gotWords = ['পেলাম', 'জমা', 'দিলো', 'দিল', 'দিয়েছে', 'দিয়েছেন', 'ফেরত', 'পরিশোধ', 'শোধ', 'পেয়েছি', 'আদায়'];

  static const List<String> _stopWords = [
    'আমি', 'আমার', 'আজ', 'আজকে', 'গতকাল', 'কাল', 'তাকে', 'তার', 'কে', 'থেকে', 'কাছ', 'কাছে', 'এর', 'ভাই', 'আপা', 'সাহেব',
    'ভাইকে', 'আপাকে', 'এবং', 'আর', 'ও', 'the', 'to', 'from', 'for', 'টাকা', 'নগদ', 'বিকাশে', 'বিকাশ', 'নগদে',
  ];

  static const Map<String, List<String>> _expenseCategories = {
    'কারেন্ট বিল': ['বিদ্যুৎ', 'কারেন্ট', 'ইলেকট্রিক', 'বিল', 'electric', 'current'],
    'দোকান ভাড়া': ['ভাড়া', 'rent'],
    'নাস্তা/চা': ['চা', 'নাস্তা', 'খাবার', 'দুপুর', 'বিস্কুট', 'সিঙ্গারা', 'পানি', 'tea', 'lunch'],
    'স্টাফ বেতন': ['বেতন', 'স্টাফ', 'কর্মচারী', 'salary', 'staff'],
    'মাল কেনা': ['মাল', 'কেনা', 'পাইকার', 'পাইকারি', 'stock', 'purchase'],
    'যাতায়াত': ['রিকশা', 'ভ্যান', 'যাতায়াত', 'গাড়ি', 'বাস', 'ভাড়ায়', 'সিএনজি', 'তেল', 'transport'],
    'মোবাইল/নেট': ['মোবাইল', 'নেট', 'রিচার্জ', 'ইন্টারনেট', 'ফ্লেক্সি', 'wifi', 'recharge', 'internet'],
  };

  // ---------------------------------------------------------------------------
  // Normalisation
  // ---------------------------------------------------------------------------

  /// Converts Bangla digits to ASCII and spelled-out numbers to digits.
  /// e.g. "দেড়শ টাকা" → "150 টাকা", "সাড়ে তিনশ" → "350", "দুই হাজার পাঁচশ" → "2500".
  static String normalizeNumbers(String text) {
    String s = text;
    _bnToEnDigits.forEach((bn, en) => s = s.replaceAll(bn, en));
    s = s.replaceAll(RegExp(r'[,،]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return _wordsToDigits(s);
  }

  static String _wordsToDigits(String s) {
    final tokens = s.split(' ');
    final out = <String>[];
    int i = 0;
    while (i < tokens.length) {
      final parsed = _consumeNumber(tokens, i);
      if (parsed != null) {
        out.add(_fmt(parsed.value));
        i = parsed.end;
      } else {
        out.add(tokens[i]);
        i++;
      }
    }
    return out.join(' ');
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  /// Tries to read a number phrase starting at [start]. Returns value + end index.
  static ({double value, int end})? _consumeNumber(List<String> tokens, int start) {
    double total = 0;
    double current = 0;
    bool any = false;
    bool half = false; // সাড়ে
    int i = start;
    while (i < tokens.length) {
      final t = tokens[i].toLowerCase();
      if (t == 'সাড়ে' || t == 'সারে') {
        half = true;
        i++;
        continue;
      }
      if (_specials.containsKey(t)) {
        current += _specials[t]!;
        any = true;
        i++;
        continue;
      }
      // Suffix forms: "তিনশ", "পাঁচশো", "দুইহাজার"
      final suffix = _splitSuffixMultiplier(t);
      if (suffix != null) {
        current = (current + suffix.$1) * suffix.$2;
        if (half) {
          current += suffix.$2 / 2;
          half = false;
        }
        total += current;
        current = 0;
        any = true;
        i++;
        continue;
      }
      final digit = double.tryParse(t);
      if (digit != null) {
        current += digit;
        any = true;
        i++;
        continue;
      }
      if (_numberWords.containsKey(t)) {
        current += _numberWords[t]!;
        any = true;
        i++;
        continue;
      }
      if (_multipliers.containsKey(t)) {
        final m = _multipliers[t]!;
        current = (current == 0 ? 1 : current) * m;
        if (half) {
          current += m / 2;
          half = false;
        }
        total += current;
        current = 0;
        any = true;
        i++;
        continue;
      }
      break;
    }
    if (!any) return null;
    if (half) current += 0.5;
    return (value: total + current, end: i);
  }

  static (double, double)? _splitSuffixMultiplier(String t) {
    for (final suf in ['হাজার', 'শো', 'শ']) {
      if (t.length > suf.length && t.endsWith(suf)) {
        final head = t.substring(0, t.length - suf.length);
        final n = _numberWords[head] ?? double.tryParse(head);
        if (n != null) return (n, suf == 'হাজার' ? 1000 : 100);
      }
    }
    return null;
  }

  static List<double> _numbers(String normalized) =>
      RegExp(r'\d+(\.\d+)?').allMatches(normalized).map((m) => double.parse(m.group(0)!)).toList();

  static String _cleanName(String s) {
    var out = s;
    for (final kw in _priceKeywords) {
      out = out.replaceAll(RegExp('(^|\\s)${RegExp.escape(kw)}(?=\\s|\$)'), ' ');
    }
    out = out.replaceAll(RegExp(r'\d+(\.\d+)?'), ' ');
    final words = out.split(RegExp(r'\s+')).where((w) => w.isNotEmpty && !_stopWords.contains(w)).toList();
    return words.join(' ').trim();
  }

  // ---------------------------------------------------------------------------
  // Memo item  ("১ কেজি চিনি ৮০ টাকা", "ডিম ১০ টা ১২ টাকা করে")
  // ---------------------------------------------------------------------------
  static VoiceItemResult parse(String spokenText) {
    final raw = spokenText.trim();
    if (raw.isEmpty) {
      return VoiceItemResult(originalText: spokenText, itemName: '', quantity: 1.0, unitPrice: 0.0);
    }
    final working = normalizeNumbers(raw);

    String foundUnit = '';
    String foundUnitRaw = '';
    for (final unit in _units) {
      final pattern = RegExp('(^|\\s|\\d)$unit(\$|\\s|\\.)', caseSensitive: false);
      if (pattern.hasMatch(working)) {
        foundUnitRaw = unit;
        foundUnit = _unitCanonical[unit] ?? unit;
        break;
      }
    }

    final nums = _numbers(working);
    double quantity = 1.0;
    double price = 0.0;
    if (nums.length >= 2) {
      // Number right before/after the unit is the quantity; the other is the price.
      double? qtyNearUnit;
      if (foundUnitRaw.isNotEmpty) {
        final m = RegExp('(\\d+(\\.\\d+)?)\\s*$foundUnitRaw').firstMatch(working) ??
            RegExp('$foundUnitRaw\\s*(\\d+(\\.\\d+)?)').firstMatch(working);
        if (m != null) qtyNearUnit = double.tryParse(m.group(1)!);
      }
      if (qtyNearUnit != null) {
        quantity = qtyNearUnit;
        final rest = [...nums]..remove(qtyNearUnit);
        price = rest.isEmpty ? 0 : rest.last;
      } else {
        quantity = nums.first;
        price = nums.last;
      }
    } else if (nums.length == 1) {
      final n = nums.first;
      final priceContext = _priceKeywords.any((k) => working.contains(k));
      if (priceContext || n > 20) {
        price = n;
      } else {
        quantity = n;
      }
    }

    var cleanName = working;
    if (foundUnitRaw.isNotEmpty) cleanName = cleanName.replaceAll(foundUnitRaw, ' ');
    cleanName = _cleanName(cleanName);
    if (cleanName.isEmpty) cleanName = 'পণ্য';
    final displayName = foundUnit.isNotEmpty ? '$cleanName ($foundUnit)' : cleanName;

    return VoiceItemResult(originalText: raw, itemName: displayName, quantity: quantity, unitPrice: price, unit: foundUnit);
  }

  // ---------------------------------------------------------------------------
  // Ledger  ("কামালকে ৫০০ টাকা বাকি দিলাম", "রহিম ২০০ টাকা জমা দিলো")
  // ---------------------------------------------------------------------------
  static VoiceLedgerResult parseLedger(String spokenText) {
    final raw = spokenText.trim();
    if (raw.isEmpty) return VoiceLedgerResult(originalText: raw);
    final working = normalizeNumbers(raw);
    final lower = working.toLowerCase();

    // Intent: look for the LAST matching verb (Bangla verbs come at the end).
    VoiceIntent intent = VoiceIntent.unknown;
    int bestPos = -1;
    for (final w in _gaveWords) {
      final p = lower.lastIndexOf(w);
      if (p > bestPos) {
        bestPos = p;
        intent = VoiceIntent.gave;
      }
    }
    for (final w in _gotWords) {
      final p = lower.lastIndexOf(w);
      if (p > bestPos) {
        bestPos = p;
        intent = VoiceIntent.got;
      }
    }
    // "বাকি ... দিলো/দিয়েছে" → customer paid their due.
    if (intent == VoiceIntent.gave && RegExp(r'(দিলো|দিল|দিয়েছে|পরিশোধ|শোধ|ফেরত)').hasMatch(lower) && !lower.contains('দিলাম')) {
      intent = VoiceIntent.got;
    }

    final nums = _numbers(working);
    final amount = nums.isEmpty ? null : nums.reduce((a, b) => a > b ? a : b);

    // Customer: word with কে / -কে suffix, or "X এর কাছ থেকে", or first capital-ish token.
    String? name;
    final keMatch = RegExp(r'([^\s\d]+?)(?:কে|-কে)(?=\s|$)').firstMatch(working);
    if (keMatch != null) {
      final candidate = keMatch.group(1)!;
      final whole = keMatch.group(0)!;
      if (!_stopWords.contains(candidate) && !_stopWords.contains(whole) && !_gaveWords.contains(candidate) && !_gotWords.contains(candidate)) {
        name = candidate;
      }
    }
    name ??= RegExp(r'([^\s\d]+?)(?:ের|র)\s+(?:কাছ|কাছে)').firstMatch(working)?.group(1);
    if (name == null) {
      for (final tok in working.split(' ')) {
        final t = tok.toLowerCase();
        if (t.isEmpty || double.tryParse(t) != null) continue;
        if (_stopWords.contains(t) || _gaveWords.contains(t) || _gotWords.contains(t) || _priceKeywords.contains(t)) continue;
        if (_units.contains(t) || _numberWords.containsKey(t) || _multipliers.containsKey(t)) continue;
        name = tok;
        break;
      }
    }
    if (name != null) {
      name = name.replaceAll(RegExp(r'(ভাই|আপা|সাহেব)$'), '').trim();
      if (name.isEmpty) name = null;
    }

    // Note: everything else that's descriptive (items mentioned).
    var note = working;
    if (name != null) note = note.replaceAll(RegExp('$name(কে|-কে|ের|র)?'), ' ');
    for (final w in [..._gaveWords, ..._gotWords]) {
      note = note.replaceAll(w, ' ');
    }
    note = _cleanName(note);

    return VoiceLedgerResult(originalText: raw, customerName: name, intent: intent, amount: amount, note: note);
  }

  // ---------------------------------------------------------------------------
  // Expense  ("বিদ্যুৎ বিল ৬৫০ টাকা", "চা নাস্তা ১২০")
  // ---------------------------------------------------------------------------
  static VoiceExpenseResult parseExpense(String spokenText) {
    final raw = spokenText.trim();
    final working = normalizeNumbers(raw);
    final lower = working.toLowerCase();
    final nums = _numbers(working);
    final amount = nums.isEmpty ? null : nums.reduce((a, b) => a > b ? a : b);

    String category = 'অন্যান্য';
    for (final e in _expenseCategories.entries) {
      if (e.value.any((k) => lower.contains(k))) {
        category = e.key;
        break;
      }
    }
    var title = _cleanName(working).replaceAll(RegExp(r'(^|\s)(খরচ|হলো|হয়েছে|দিলাম|গেল|গেছে)(?=\s|$)'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (title.isEmpty) title = category;
    return VoiceExpenseResult(originalText: raw, title: title, category: category, amount: amount);
  }

  // ---------------------------------------------------------------------------
  // Contact  ("কামাল হোসেন ০১৭১২৩৪৫৬৭৮")
  // ---------------------------------------------------------------------------
  static VoiceContactResult parseContact(String spokenText) {
    final raw = spokenText.trim();
    var s = raw;
    _bnToEnDigits.forEach((bn, en) => s = s.replaceAll(bn, en));
    // Phone: join digit groups separated by spaces, take a 10-11 digit run.
    final digitsOnly = s.replaceAll(RegExp(r'[^0-9]'), '');
    String phone = '';
    final m = RegExp(r'(01\d{9}|\d{11}|\d{10})').firstMatch(digitsOnly);
    if (m != null) phone = m.group(0)!;
    var name = s.replaceAll(RegExp(r'[0-9]'), ' ');
    name = name.replaceAll(RegExp(r'(^|\s)(নম্বর|নাম্বার|মোবাইল|ফোন|নাম|নতুন|খরিদ্দার|কাস্টমার|যোগ|করো|কর|করুন)(?=\s|$)'), ' ');
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    return VoiceContactResult(originalText: raw, name: name, phone: phone);
  }

  // ---------------------------------------------------------------------------
  // Product  ("মিনিকেট চাল কেজি ৭২ টাকা স্টক ৫০")
  // ---------------------------------------------------------------------------
  static VoiceProductResult parseProduct(String spokenText) {
    final raw = spokenText.trim();
    final working = normalizeNumbers(raw);
    String unit = 'পিস';
    String unitRaw = '';
    for (final u in _units) {
      if (RegExp('(^|\\s)$u(\$|\\s)').hasMatch(working)) {
        unitRaw = u;
        unit = _unitCanonical[u] ?? u;
        break;
      }
    }
    double? price;
    double? stock;
    final priceM = RegExp(r'(\d+(\.\d+)?)\s*(টাকা|tk|taka|দর)').firstMatch(working);
    if (priceM != null) price = double.tryParse(priceM.group(1)!);
    final stockM = RegExp(r'(?:স্টক|স্টকে|আছে|মজুদ)\s*(\d+(\.\d+)?)').firstMatch(working) ??
        RegExp(r'(\d+(\.\d+)?)\s*(?:টা|পিস|কেজি|লিটার)?\s*(?:স্টক|আছে|মজুদ)').firstMatch(working);
    if (stockM != null) stock = double.tryParse(stockM.group(1)!);
    final nums = _numbers(working);
    price ??= nums.isNotEmpty ? nums.first : null;
    var name = working;
    if (unitRaw.isNotEmpty) name = name.replaceAll(unitRaw, ' ');
    name = _cleanName(name).replaceAll(RegExp(r'(^|\s)(স্টক|স্টকে|আছে|মজুদ|পণ্য|নতুন|যোগ)(?=\s|$)'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return VoiceProductResult(originalText: raw, name: name, unit: unit, price: price, stock: stock);
  }
}

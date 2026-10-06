/// Pure-Dart helper: which server notifications are new since the last poll.
///
/// Kept free of Flutter / plugin imports so it is unit-testable.
class NewNotificationDetector {
  NewNotificationDetector(Iterable<String> seenIds) : _seen = {...seenIds};

  final Set<String> _seen;

  Set<String> get seenIds => Set.unmodifiable(_seen);

  /// Ids from [incoming] (`{id, read}` maps) that are unread and have never
  /// been seen. Marks them seen as a side effect so a second call with the
  /// same list returns nothing. Read notifications are also marked seen
  /// (silently) so an already-read item never fires later.
  ///
  /// [isFirstSync] (no persisted seen-set yet) suppresses alerts for the
  /// entire backlog: an existing account should not get 20 pings on the
  /// first launch after the update; everything is just marked seen.
  List<String> detect(Iterable<({String id, bool read})> incoming, {bool isFirstSync = false}) {
    final fresh = <String>[];
    for (final n in incoming) {
      if (n.id.isEmpty) continue;
      if (_seen.contains(n.id)) continue;
      _seen.add(n.id);
      if (!n.read && !isFirstSync) fresh.add(n.id);
    }
    return fresh;
  }

  /// Keep the persisted set bounded (oldest ids are dropped first since
  /// callers insert newest last).
  List<String> toPersist({int max = 500}) {
    final list = _seen.toList();
    if (list.length <= max) return list;
    return list.sublist(list.length - max);
  }

  /// Deterministic positive int for a platform notification id.
  static int platformId(String id) {
    var h = 0x811C9DC5;
    for (final c in id.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0x7FFFFFFF;
    }
    // Keep clear of the subscription reminder range (7000..7020).
    return 100000 + (h % 1000000000);
  }
}

class SearchQuery {
  final Map<String, String> qualified;
  final List<String> freeTokens;

  const SearchQuery({this.qualified = const {}, this.freeTokens = const []});

  bool get isEmpty => qualified.isEmpty && freeTokens.isEmpty;

  factory SearchQuery.parse(String text, {Set<String> knownFields = const {}}) {
    if (text.trim().isEmpty) {
      return const SearchQuery();
    }
    final qualified = <String, String>{};
    final freeParts = <String>[];
    final segments = _splitByComma(text);
    for (var seg in segments) {
      var remaining = seg.trim();
      if (remaining.isEmpty) continue;

      while (true) {
        bool matched = false;
        for (final field in knownFields) {
          final quotedRegex = RegExp('\\b$field:\\s*"([^"]*)"');
          final qm = quotedRegex.firstMatch(remaining);
          if (qm != null) {
            qualified[field] = qm.group(1)!;
            remaining = remaining.replaceRange(qm.start, qm.end, '');
            matched = true;
            break;
          }
          final wordRegex = RegExp('\\b$field:\\s*(\\S+)');
          final wm = wordRegex.firstMatch(remaining);
          if (wm != null) {
            qualified[field] = wm.group(1)!;
            remaining = remaining.replaceRange(wm.start, wm.end, '');
            matched = true;
            break;
          }
        }
        if (!matched) break;
        remaining = remaining.trim();
      }

      if (remaining.isNotEmpty) freeParts.add(remaining);
    }
    final tokens = <String>[];
    for (final part in freeParts) {
      tokens.addAll(part.split(RegExp(r'\s+')).where((t) => t.isNotEmpty));
    }
    return SearchQuery(qualified: qualified, freeTokens: tokens);
  }

  static List<String> _splitByComma(String text) {
    final result = <String>[];
    final buf = StringBuffer();
    bool inQuote = false;
    for (int i = 0; i < text.length; i++) {
      final ch = text[i];
      if (ch == '"') {
        inQuote = !inQuote;
        buf.write(ch);
      } else if (ch == ',' && !inQuote) {
        result.add(buf.toString());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    if (buf.isNotEmpty) result.add(buf.toString());
    return result;
  }
}

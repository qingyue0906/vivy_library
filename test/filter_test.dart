import 'package:flutter_test/flutter_test.dart';
import 'package:vivy_library/services/settings_service.dart';

void main() {
  group('ItemFilter 默认全选', () {
    final f = ItemFilter.all();

    test('默认全选时任意类型/分级都显示', () {
      for (final t in ['video', 'comic', 'ab', 'default']) {
        for (final r in ['G', 'PG-13', 'R-18', 'R-19', '']) {
          expect(f.matches(t, r), isTrue, reason: 'type=$t rating=$r');
        }
      }
    });

    test('isAll 为 true', () {
      expect(f.isAll, isTrue);
    });
  });

  group('ItemFilter 类型维度', () {
    test('预设类型精确匹配勾选项', () {
      final f = ItemFilter(
        types: {'video', ItemFilter.otherSentinel},
        ratings: ItemFilter.all().ratings,
      );
      expect(f.matchesType('video'), isTrue);
      expect(f.matchesType('comic'), isFalse);
    });

    test('非预设值（含 default 与自定义 ab）归「其他」', () {
      final withOther = ItemFilter(
        types: {'video', ItemFilter.otherSentinel},
        ratings: ItemFilter.all().ratings,
      );
      expect(withOther.matchesType('default'), isTrue);
      expect(withOther.matchesType('ab'), isTrue);

      final withoutOther = ItemFilter(
        types: {'video'},
        ratings: ItemFilter.all().ratings,
      );
      expect(withoutOther.matchesType('default'), isFalse);
      expect(withoutOther.matchesType('ab'), isFalse);
    });

    test('空集合 = 类型维度全部隐藏', () {
      final f = ItemFilter(
        types: const {},
        ratings: ItemFilter.all().ratings,
      );
      expect(f.matchesType('video'), isFalse);
      expect(f.matchesType('default'), isFalse);
      expect(f.matches('video', 'G'), isFalse);
    });

    test('空 type 防御性归「其他」', () {
      final f = ItemFilter(
        types: {ItemFilter.otherSentinel},
        ratings: ItemFilter.all().ratings,
      );
      expect(f.matchesType(''), isTrue);
    });
  });

  group('ItemFilter 分级维度', () {
    test('预设分级精确匹配勾选项', () {
      final f = ItemFilter(
        types: ItemFilter.all().types,
        ratings: {'G'},
      );
      expect(f.matchesRating('G'), isTrue);
      expect(f.matchesRating('PG-13'), isFalse);
      expect(f.matchesRating('R-18'), isFalse);
    });

    test('非预设值（如 R-19）归「其他」', () {
      final withOther = ItemFilter(
        types: ItemFilter.all().types,
        ratings: {'G', ItemFilter.otherSentinel},
      );
      expect(withOther.matchesRating('R-19'), isTrue);
      expect(withOther.matchesRating('XXX'), isTrue);

      final withoutOther = ItemFilter(
        types: ItemFilter.all().types,
        ratings: {'G'},
      );
      expect(withoutOther.matchesRating('R-19'), isFalse);
    });

    test('空集合 = 分级维度全部隐藏', () {
      final f = ItemFilter(
        types: ItemFilter.all().types,
        ratings: const {},
      );
      expect(f.matchesRating('G'), isFalse);
      expect(f.matches('video', 'G'), isFalse);
    });
  });

  group('ItemFilter 交集与持久化编码', () {
    test('两维度都命中才显示', () {
      final f = ItemFilter(
        types: {'video'},
        ratings: {'R-18'},
      );
      expect(f.matches('video', 'R-18'), isTrue);
      expect(f.matches('video', 'G'), isFalse);
      expect(f.matches('comic', 'R-18'), isFalse);
    });

    test('编码/解码往返一致', () {
      final f = ItemFilter(
        types: {'video', ItemFilter.otherSentinel},
        ratings: {'G', 'R-18', ItemFilter.otherSentinel},
      );
      final typesDecoded = ItemFilter.decode(f.encode(f.types));
      final ratingsDecoded = ItemFilter.decode(f.encode(f.ratings));
      expect(typesDecoded, f.types);
      expect(ratingsDecoded, f.ratings);
    });

    test('null/空串解码为空集合', () {
      expect(ItemFilter.decode(null), isEmpty);
      expect(ItemFilter.decode(''), isEmpty);
    });

    test('isAll 仅在全部勾选时为 true', () {
      final f = ItemFilter(
        types: {'video', ItemFilter.otherSentinel},
        ratings: {...ItemFilter.presetRatings, ItemFilter.otherSentinel},
      );
      expect(f.isAll, isFalse);
      expect(ItemFilter.all().isAll, isTrue);
    });
  });
}

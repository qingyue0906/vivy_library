import 'package:flutter_test/flutter_test.dart';
import 'package:vivy_library/utils/folder_collapse.dart';

/// 测试用最小树节点：与 4 种播放列表节点结构一致（children + files）。
class _N {
  final String name;
  final List<_N> children;
  final List<String> files;
  _N(this.name, {List<_N>? children, List<String>? files})
    : children = children ?? [],
      files = files ?? [];
}

void main() {
  group('collapsedPath', () {
    List<_N> childrenOf(_N n) => n.children;
    List<String> filesOf(_N n) => n.files;
    String nameOf(_N n) => n.name;
    String fileNameOf(String f) => f;

    test('单文件节点折叠为 文件夹/文件', () {
      final node = _N('ep1', files: ['a.mp4']);
      expect(
        collapsedPath(
          node,
          childrenOf: childrenOf,
          filesOf: filesOf,
          nameOf: nameOf,
          fileNameOf: fileNameOf,
        ),
        'ep1/a.mp4',
      );
    });

    test('多层单子项链整链折叠', () {
      final node = _N(
        'folder1',
        children: [
          _N(
            'folder2',
            children: [
              _N('folder3', files: ['file.mp4']),
            ],
          ),
        ],
      );
      expect(
        collapsedPath(
          node,
          childrenOf: childrenOf,
          filesOf: filesOf,
          nameOf: nameOf,
          fileNameOf: fileNameOf,
        ),
        'folder1/folder2/folder3/file.mp4',
      );
    });

    test('多文件节点不折叠', () {
      final node = _N('dir', files: ['a.mp4', 'b.mp4']);
      expect(
        collapsedPath(
          node,
          childrenOf: childrenOf,
          filesOf: filesOf,
          nameOf: nameOf,
          fileNameOf: fileNameOf,
        ),
        isNull,
      );
    });

    test('单子文件夹链末端多文件不折叠（链顶非单文件）', () {
      final node = _N(
        'folder1',
        children: [
          _N('folder2', files: ['a.mp4', 'b.mp4']),
        ],
      );
      expect(
        collapsedPath(
          node,
          childrenOf: childrenOf,
          filesOf: filesOf,
          nameOf: nameOf,
          fileNameOf: fileNameOf,
        ),
        isNull,
      );
    });

    test('分支节点不折叠', () {
      final node = _N(
        'dir',
        children: [
          _N('sub1', files: ['a.mp4']),
          _N('sub2', files: ['b.mp4']),
        ],
      );
      expect(
        collapsedPath(
          node,
          childrenOf: childrenOf,
          filesOf: filesOf,
          nameOf: nameOf,
          fileNameOf: fileNameOf,
        ),
        isNull,
      );
    });

    test('一文件一子文件夹（总数2）不折叠', () {
      final node = _N(
        'dir',
        children: [
          _N('sub', files: ['b.mp4']),
        ],
        files: ['a.mp4'],
      );
      expect(
        collapsedPath(
          node,
          childrenOf: childrenOf,
          filesOf: filesOf,
          nameOf: nameOf,
          fileNameOf: fileNameOf,
        ),
        isNull,
      );
    });
  });

  group('collapseLeafFile', () {
    List<_N> childrenOf(_N n) => n.children;
    List<String> filesOf(_N n) => n.files;

    test('返回折叠链末端的唯一文件', () {
      final leaf = _N('folder2', files: ['a.mp4']);
      final node = _N('folder1', children: [leaf]);
      expect(
        collapseLeafFile(node, childrenOf: childrenOf, filesOf: filesOf),
        'a.mp4',
      );
      expect(
        collapseLeafFile(leaf, childrenOf: childrenOf, filesOf: filesOf),
        'a.mp4',
      );
    });

    test('不可折叠时返回 null', () {
      final node = _N('dir', files: ['a.mp4', 'b.mp4']);
      expect(
        collapseLeafFile(node, childrenOf: childrenOf, filesOf: filesOf),
        isNull,
      );
    });
  });

  group('ellipsizePathMiddle', () {
    test('短名原样返回', () {
      expect(
        ellipsizePathMiddle('folder/file.mp4', maxLen: 60),
        'folder/file.mp4',
      );
    });

    test('超长名省略中间，保留首末段', () {
      final long = '${'a' * 40}/mid/${'b' * 30}.mp4';
      final out = ellipsizePathMiddle(long, maxLen: 60);
      expect(out.length, lessThanOrEqualTo(60));
      expect(out.contains('…'), isTrue);
      expect(out.endsWith('.mp4'), isTrue);
    });

    test('单段超长按比例截断且保留省略号', () {
      final out = ellipsizePathMiddle('${'x' * 100}.mp4', maxLen: 60);
      expect(out.length, lessThanOrEqualTo(60));
      expect(out.contains('…'), isTrue);
      expect(out.endsWith('.mp4'), isTrue);
    });
  });
}

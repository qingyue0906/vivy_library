enum AppLocale { system, zhHans, zhHant, en, ja }

extension AppLocaleX on AppLocale {
  String get displayName {
    switch (this) {
      case AppLocale.system: return Strings.t('followSystem');
      case AppLocale.zhHans: return '中文(简体)';
      case AppLocale.zhHant: return '中文(繁體)';
      case AppLocale.en: return 'English';
      case AppLocale.ja: return '日本語';
    }
  }
}

class Strings {
  static AppLocale _locale = AppLocale.zhHans;

  static void setLocale(AppLocale locale) { _locale = locale; }
  static AppLocale get currentLocale => _locale;

  static String _key(String k, [Map<String, String>? args]) {
    final entry = _all[k];
    if (entry == null) return k;
    var v = entry[_locale] ?? entry[AppLocale.zhHans] ?? k;
    if (args != null) {
      for (final e in args.entries) {
        v = v.replaceAll('{${e.key}}', e.value);
      }
    }
    return v;
  }

  static String t(String k) => _key(k);

  static String tn(String k, Map<String, String> args) => _key(k, args);

  static const _all = <String, Map<AppLocale, String>>{
    // ======== settings_page ========
    'tabGeneral': {
      AppLocale.zhHans: '常规',
      AppLocale.zhHant: '一般',
      AppLocale.en: 'General',
      AppLocale.ja: '一般',
    },
    'tabData': {
      AppLocale.zhHans: '数据',
      AppLocale.zhHant: '資料',
      AppLocale.en: 'Data',
      AppLocale.ja: 'データ',
    },
    'tabTheme': {
      AppLocale.zhHans: '主题',
      AppLocale.zhHant: '主題',
      AppLocale.en: 'Theme',
      AppLocale.ja: 'テーマ',
    },
    'tabUi': {
      AppLocale.zhHans: '界面',
      AppLocale.zhHant: '界面',
      AppLocale.en: 'UI',
      AppLocale.ja: 'UI',
    },
    'tabAbout': {
      AppLocale.zhHans: '关于',
      AppLocale.zhHant: '關於',
      AppLocale.en: 'About',
      AppLocale.ja: 'について',
    },
    'tabScripts': {
      AppLocale.zhHans: '脚本',
      AppLocale.zhHant: '腳本',
      AppLocale.en: 'Scripts',
      AppLocale.ja: 'スクリプト',
    },
    'pythonPath': {
      AppLocale.zhHans: 'Python 路径',
      AppLocale.zhHant: 'Python 路徑',
      AppLocale.en: 'Python Path',
      AppLocale.ja: 'Python パス',
    },
    'pythonPathDefault': {
      AppLocale.zhHans: '自动检测 (尝试 py -3 → python)',
      AppLocale.zhHant: '自動檢測 (嘗試 py -3 → python)',
      AppLocale.en: 'Auto detect (py -3 → python)',
      AppLocale.ja: '自動検出 (py -3 → python)',
    },
    'pythonBrowse': {
      AppLocale.zhHans: '浏览...',
      AppLocale.zhHant: '瀏覽...',
      AppLocale.en: 'Browse...',
      AppLocale.ja: '参照...',
    },
    'pythonReset': {
      AppLocale.zhHans: '重置',
      AppLocale.zhHant: '重置',
      AppLocale.en: 'Reset',
      AppLocale.ja: 'リセット',
    },
    'pythonPickTitle': {
      AppLocale.zhHans: '选择 Python 可执行文件',
      AppLocale.zhHant: '選擇 Python 可執行檔',
      AppLocale.en: 'Select Python Executable',
      AppLocale.ja: 'Python 実行可能ファイルを選択',
    },
    'scriptManage': {
      AppLocale.zhHans: '管理脚本',
      AppLocale.zhHant: '管理腳本',
      AppLocale.en: 'Manage Scripts',
      AppLocale.ja: 'スクリプト管理',
    },
    'scriptImport': {
      AppLocale.zhHans: '导入',
      AppLocale.zhHant: '導入',
      AppLocale.en: 'Import',
      AppLocale.ja: 'インポート',
    },
    'scriptImportTitle': {
      AppLocale.zhHans: '选择要导入的 Python 脚本',
      AppLocale.zhHant: '選擇要導入的 Python 腳本',
      AppLocale.en: 'Select Python Script to Import',
      AppLocale.ja: 'インポートする Python スクリプトを選択',
    },
    'noScripts': {
      AppLocale.zhHans: '暂无脚本，点击"导入"添加',
      AppLocale.zhHant: '暫無腳本，點擊"導入"添加',
      AppLocale.en: 'No scripts yet. Click Import to add',
      AppLocale.ja: 'スクリプトがありません。「インポート」をクリックして追加',
    },
    'scripts': {
      AppLocale.zhHans: '脚本',
      AppLocale.zhHant: '腳本',
      AppLocale.en: 'Scripts',
      AppLocale.ja: 'スクリプト',
    },
    'scriptEdit': {
      AppLocale.zhHans: '编辑',
      AppLocale.zhHant: '編輯',
      AppLocale.en: 'Edit',
      AppLocale.ja: '編集',
    },
    'scriptExport': {
      AppLocale.zhHans: '导出',
      AppLocale.zhHant: '導出',
      AppLocale.en: 'Export',
      AppLocale.ja: 'エクスポート',
    },
    'scriptExportTitle': {
      AppLocale.zhHans: '选择导出目录',
      AppLocale.zhHant: '選擇導出目錄',
      AppLocale.en: 'Select Export Directory',
      AppLocale.ja: 'エクスポート先を選択',
    },
    'scriptDelete': {
      AppLocale.zhHans: '删除',
      AppLocale.zhHant: '刪除',
      AppLocale.en: 'Delete',
      AppLocale.ja: '削除',
    },
    'scriptDeleteConfirm': {
      AppLocale.zhHans: '确认删除',
      AppLocale.zhHant: '確認刪除',
      AppLocale.en: 'Confirm Deletion',
      AppLocale.ja: '削除の確認',
    },
    'scriptDeleteMsg': {
      AppLocale.zhHans: '确定要删除脚本 "{name}" 吗？脚本文件也会被删除。',
      AppLocale.zhHant: '確定要刪除腳本 "{name}" 嗎？腳本檔案也會被刪除。',
      AppLocale.en: 'Are you sure you want to delete "{name}"? The script file will also be deleted.',
      AppLocale.ja: 'スクリプト "{name}" を削除してもよろしいですか？スクリプトファイルも削除されます。',
    },
    'scriptExported': {
      AppLocale.zhHans: '脚本已导出',
      AppLocale.zhHant: '腳本已導出',
      AppLocale.en: 'Script exported',
      AppLocale.ja: 'スクリプトをエクスポートしました',
    },
    'execModeResult': {
      AppLocale.zhHans: '结果',
      AppLocale.zhHant: '結果',
      AppLocale.en: 'Result',
      AppLocale.ja: '結果',
    },
    'execModeTerminal': {
      AppLocale.zhHans: '终端',
      AppLocale.zhHant: '終端',
      AppLocale.en: 'Terminal',
      AppLocale.ja: '端末',
    },
    'execModeSilent': {
      AppLocale.zhHans: '静默',
      AppLocale.zhHant: '靜默',
      AppLocale.en: 'Silent',
      AppLocale.ja: 'サイレント',
    },
    'appVersion': {
      AppLocale.zhHans: '版本 0.1.0 Build260706',
      AppLocale.zhHant: '版本 0.1.0 Build260706',
      AppLocale.en: 'Version 0.1.0 Build260706',
      AppLocale.ja: 'バージョン 0.1.0 Build260706',
    },
    'projectUrl': {
      AppLocale.zhHans: '项目地址',
      AppLocale.zhHant: '專案地址',
      AppLocale.en: 'Project URL',
      AppLocale.ja: 'プロジェクトURL',
    },
    'dataManage': {
      AppLocale.zhHans: '数据管理',
      AppLocale.zhHant: '資料管理',
      AppLocale.en: 'Data Management',
      AppLocale.ja: 'データ管理',
    },
    'exportData': {
      AppLocale.zhHans: '导出数据',
      AppLocale.zhHant: '匯出資料',
      AppLocale.en: 'Export Data',
      AppLocale.ja: 'データをエクスポート',
    },
    'importData': {
      AppLocale.zhHans: '导入数据（覆盖）',
      AppLocale.zhHant: '匯入資料（覆蓋）',
      AppLocale.en: 'Import Data (Overwrite)',
      AppLocale.ja: 'データをインポート（上書き）',
    },
    'clearData': {
      AppLocale.zhHans: '清空数据',
      AppLocale.zhHant: '清空資料',
      AppLocale.en: 'Clear Data',
      AppLocale.ja: 'データをクリア',
    },
    'themeSection': {
      AppLocale.zhHans: '主题',
      AppLocale.zhHant: '主題',
      AppLocale.en: 'Theme',
      AppLocale.ja: 'テーマ',
    },
    'followSystem': {
      AppLocale.zhHans: '跟随系统',
      AppLocale.zhHant: '跟隨系統',
      AppLocale.en: 'Follow System',
      AppLocale.ja: 'システムに従う',
    },
    'light': {
      AppLocale.zhHans: '亮色',
      AppLocale.zhHant: '亮色',
      AppLocale.en: 'Light',
      AppLocale.ja: 'ライト',
    },
    'dark': {
      AppLocale.zhHans: '暗色',
      AppLocale.zhHant: '暗色',
      AppLocale.en: 'Dark',
      AppLocale.ja: 'ダーク',
    },
    'customBg': {
      AppLocale.zhHans: '自定义背景',
      AppLocale.zhHant: '自訂背景',
      AppLocale.en: 'Custom Background',
      AppLocale.ja: 'カスタム背景',
    },
    'selectBg': {
      AppLocale.zhHans: '选择背景',
      AppLocale.zhHant: '選擇背景',
      AppLocale.en: 'Select Background',
      AppLocale.ja: '背景を選択',
    },
    'clearBg': {
      AppLocale.zhHans: '清除背景',
      AppLocale.zhHant: '清除背景',
      AppLocale.en: 'Clear Background',
      AppLocale.ja: '背景をクリア',
    },
    'panelOpacity': {
      AppLocale.zhHans: '面板不透明度',
      AppLocale.zhHant: '面板不透明度',
      AppLocale.en: 'Panel Opacity',
      AppLocale.ja: 'パネル不透明度',
    },
    'leftPanel': {
      AppLocale.zhHans: '左栏',
      AppLocale.zhHant: '左欄',
      AppLocale.en: 'Left Panel',
      AppLocale.ja: '左パネル',
    },
    'middlePanel': {
      AppLocale.zhHans: '中栏',
      AppLocale.zhHant: '中欄',
      AppLocale.en: 'Middle Panel',
      AppLocale.ja: '中央パネル',
    },
    'rightPanel': {
      AppLocale.zhHans: '右栏',
      AppLocale.zhHant: '右欄',
      AppLocale.en: 'Right Panel',
      AppLocale.ja: '右パネル',
    },
    'selectBgTitle': {
      AppLocale.zhHans: '选择背景图片',
      AppLocale.zhHant: '選擇背景圖片',
      AppLocale.en: 'Select Background Image',
      AppLocale.ja: '背景画像を選択',
    },
    'gridSettings': {
      AppLocale.zhHans: '网格设置',
      AppLocale.zhHant: '網格設定',
      AppLocale.en: 'Grid Settings',
      AppLocale.ja: 'グリッド設定',
    },
    'minCardWidth': {
      AppLocale.zhHans: '卡片最小宽度',
      AppLocale.zhHant: '卡片最小寬度',
      AppLocale.en: 'Min Card Width',
      AppLocale.ja: '最小カード幅',
    },
    'maxCardWidth': {
      AppLocale.zhHans: '卡片最大宽度',
      AppLocale.zhHant: '卡片最大寬度',
      AppLocale.en: 'Max Card Width',
      AppLocale.ja: '最大カード幅',
    },
    'aspectRatio': {
      AppLocale.zhHans: '卡片宽高比',
      AppLocale.zhHant: '卡片寬高比',
      AppLocale.en: 'Aspect Ratio',
      AppLocale.ja: 'アスペクト比',
    },
    'itemsPerRow': {
      AppLocale.zhHans: '每行固定数量（0=自动）',
      AppLocale.zhHant: '每行固定數量（0=自動）',
      AppLocale.en: 'Items Per Row (0=Auto)',
      AppLocale.ja: '行あたりのアイテム数（0=自動）',
    },
    'compactLevel': {
      AppLocale.zhHans: '紧凑度',
      AppLocale.zhHant: '緊湊度',
      AppLocale.en: 'Compact Level',
      AppLocale.ja: 'コンパクトレベル',
    },
    'gifDisplayMode': {
      AppLocale.zhHans: '动图展示方式',
      AppLocale.zhHant: '動圖展示方式',
      AppLocale.en: 'GIF Display Mode',
      AppLocale.ja: 'GIF表示モード',
    },
    'cardGifMode': {
      AppLocale.zhHans: '卡片动图',
      AppLocale.zhHant: '卡片動圖',
      AppLocale.en: 'Card GIF',
      AppLocale.ja: 'カードGIF',
    },
    'fileGifMode': {
      AppLocale.zhHans: '底部区域动图',
      AppLocale.zhHant: '底部區域動圖',
      AppLocale.en: 'File Panel GIF',
      AppLocale.ja: 'ファイルパネルGIF',
    },
    'gifUnlimited': {
      AppLocale.zhHans: '无限制',
      AppLocale.zhHant: '無限制',
      AppLocale.en: 'Unlimited',
      AppLocale.ja: '無制限',
    },
    'gifHover': {
      AppLocale.zhHans: 'hover时播放',
      AppLocale.zhHant: 'hover時播放',
      AppLocale.en: 'Play on Hover',
      AppLocale.ja: 'ホバーで再生',
    },
    'gifStatic': {
      AppLocale.zhHans: '展示为静态图',
      AppLocale.zhHant: '展示為靜態圖',
      AppLocale.en: 'Show as Static',
      AppLocale.ja: '静止画として表示',
    },
    'apply': {
      AppLocale.zhHans: '应用',
      AppLocale.zhHant: '應用',
      AppLocale.en: 'Apply',
      AppLocale.ja: '適用',
    },
    'gridSaved': {
      AppLocale.zhHans: '网格设置已保存',
      AppLocale.zhHant: '網格設定已儲存',
      AppLocale.en: 'Grid settings saved',
      AppLocale.ja: 'グリッド設定を保存しました',
    },
    'exportDirTitle': {
      AppLocale.zhHans: '选择导出目录',
      AppLocale.zhHant: '選擇匯出目錄',
      AppLocale.en: 'Select Export Directory',
      AppLocale.ja: 'エクスポート先を選択',
    },
    'exportedTo': {
      AppLocale.zhHans: '已导出到 {path}',
      AppLocale.zhHant: '已匯出到 {path}',
      AppLocale.en: 'Exported to {path}',
      AppLocale.ja: '{path} にエクスポートしました',
    },
    'exportFailed': {
      AppLocale.zhHans: '导出失败: {error}',
      AppLocale.zhHant: '匯出失敗: {error}',
      AppLocale.en: 'Export failed: {error}',
      AppLocale.ja: 'エクスポート失敗: {error}',
    },
    'export': {
      AppLocale.zhHans: '导出',
      AppLocale.zhHant: '導出',
      AppLocale.en: 'Export',
      AppLocale.ja: 'エクスポート',
    },
    'exportN': {
      AppLocale.zhHans: '导出 {n} 项',
      AppLocale.zhHant: '導出 {n} 項',
      AppLocale.en: 'Export {n} items',
      AppLocale.ja: '{n} 項をエクスポート',
    },
    'exportedToDir': {
      AppLocale.zhHans: '已导出 {n} 个项到 {dir}',
      AppLocale.zhHant: '已匯出 {n} 個項目到 {dir}',
      AppLocale.en: 'Exported {n} item(s) to {dir}',
      AppLocale.ja: '{n} 項を {dir} にエクスポートしました',
    },
    'exportedPartial': {
      AppLocale.zhHans: '已导出 {ok} 个项（{fail} 个失败）到 {dir}',
      AppLocale.zhHant: '已匯出 {ok} 個項目（{fail} 個失敗）到 {dir}',
      AppLocale.en: 'Exported {ok} item(s), {fail} failed, to {dir}',
      AppLocale.ja: '{ok} 項をエクスポート（{fail} 項失敗）{dir} へ',
    },
    'importFileTitle': {
      AppLocale.zhHans: '选择导入文件',
      AppLocale.zhHant: '選擇匯入檔案',
      AppLocale.en: 'Select Import File',
      AppLocale.ja: 'インポートするファイルを選択',
    },
    'fileNotExist': {
      AppLocale.zhHans: '文件不存在',
      AppLocale.zhHant: '檔案不存在',
      AppLocale.en: 'File does not exist',
      AppLocale.ja: 'ファイルが存在しません',
    },
    'dataImported': {
      AppLocale.zhHans: '数据已导入',
      AppLocale.zhHant: '資料已匯入',
      AppLocale.en: 'Data imported',
      AppLocale.ja: 'データをインポートしました',
    },
    'importFailed': {
      AppLocale.zhHans: '导入失败: {error}',
      AppLocale.zhHant: '匯入失敗: {error}',
      AppLocale.en: 'Import failed: {error}',
      AppLocale.ja: 'インポート失敗: {error}',
    },
    'confirmClear': {
      AppLocale.zhHans: '确认清空',
      AppLocale.zhHant: '確認清空',
      AppLocale.en: 'Confirm Clear',
      AppLocale.ja: 'クリア確認',
    },
    'confirmClearMsg': {
      AppLocale.zhHans: '确定要清空所有数据吗？此操作不可撤销。',
      AppLocale.zhHant: '確定要清空所有資料嗎？此操作不可撤銷。',
      AppLocale.en: 'Are you sure you want to clear all data? This cannot be undone.',
      AppLocale.ja: 'すべてのデータをクリアしますか？この操作は元に戻せません。',
    },
    'cancel': {
      AppLocale.zhHans: '取消',
      AppLocale.zhHant: '取消',
      AppLocale.en: 'Cancel',
      AppLocale.ja: 'キャンセル',
    },
    'confirm': {
      AppLocale.zhHans: '确认清空',
      AppLocale.zhHant: '確認清空',
      AppLocale.en: 'Clear',
      AppLocale.ja: 'クリア',
    },
    'dataCleared': {
      AppLocale.zhHans: '数据已清空',
      AppLocale.zhHant: '資料已清空',
      AppLocale.en: 'Data cleared',
      AppLocale.ja: 'データをクリアしました',
    },
    'clearFailed': {
      AppLocale.zhHans: '清空失败: {error}',
      AppLocale.zhHant: '清空失敗: {error}',
      AppLocale.en: 'Clear failed: {error}',
      AppLocale.ja: 'クリア失敗: {error}',
    },
    'language': {
      AppLocale.zhHans: '语言',
      AppLocale.zhHant: '語言',
      AppLocale.en: 'Language',
      AppLocale.ja: '言語',
    },
    'languageDesc': {
      AppLocale.zhHans: '选择应用界面语言，更改后立即生效',
      AppLocale.zhHant: '選擇應用程式界面語言，更改後立即生效',
      AppLocale.en: 'Select the application interface language. Changes take effect immediately.',
      AppLocale.ja: 'アプリケーションの言語を選択します。変更はすぐに反映されます。',
    },
    'systemDefault': {
      AppLocale.zhHans: '跟随系统',
      AppLocale.zhHant: '跟隨系統',
      AppLocale.en: 'System Default',
      AppLocale.ja: 'システムデフォルト',
    },
    'searchScope': {
      AppLocale.zhHans: '搜索范围',
      AppLocale.zhHant: '搜索範圍',
      AppLocale.en: 'Search Scope',
      AppLocale.ja: '検索範囲',
    },
    'searchScopeUuid': {
      AppLocale.zhHans: 'UUID',
      AppLocale.zhHant: 'UUID',
      AppLocale.en: 'UUID',
      AppLocale.ja: 'UUID',
    },
    'searchScopeDefine': {
      AppLocale.zhHans: 'Define',
      AppLocale.zhHant: 'Define',
      AppLocale.en: 'Define',
      AppLocale.ja: 'Define',
    },
    'searchScopeTitle': {
      AppLocale.zhHans: '标题',
      AppLocale.zhHant: '標題',
      AppLocale.en: 'Title',
      AppLocale.ja: 'タイトル',
    },
    'searchScopeDescription': {
      AppLocale.zhHans: '描述',
      AppLocale.zhHant: '描述',
      AppLocale.en: 'Description',
      AppLocale.ja: '説明',
    },
    'searchScopeCreator': {
      AppLocale.zhHans: '作者',
      AppLocale.zhHant: '作者',
      AppLocale.en: 'Creator',
      AppLocale.ja: '作者',
    },
    'searchScopeType': {
      AppLocale.zhHans: '类型',
      AppLocale.zhHant: '類型',
      AppLocale.en: 'Type',
      AppLocale.ja: 'タイプ',
    },
    'searchScopeContentrating': {
      AppLocale.zhHans: '评级',
      AppLocale.zhHant: '評級',
      AppLocale.en: 'Content Rating',
      AppLocale.ja: 'レーティング',
    },
    'searchScopeRating': {
      AppLocale.zhHans: '评分',
      AppLocale.zhHant: '評分',
      AppLocale.en: 'Rating',
      AppLocale.ja: '評価',
    },
    'searchScopeClass': {
      AppLocale.zhHans: '分类',
      AppLocale.zhHant: '分類',
      AppLocale.en: 'Class',
      AppLocale.ja: 'クラス',
    },
    'searchScopeTags': {
      AppLocale.zhHans: '标签',
      AppLocale.zhHant: '標籤',
      AppLocale.en: 'Tags',
      AppLocale.ja: 'タグ',
    },
    'searchScopeStar': {
      AppLocale.zhHans: '标星',
      AppLocale.zhHant: '標星',
      AppLocale.en: 'Star',
      AppLocale.ja: 'スター',
    },
    'classSourceCreator': {
      AppLocale.zhHans: '作者',
      AppLocale.zhHant: '作者',
      AppLocale.en: 'Creator',
      AppLocale.ja: '作者',
    },
    'classSourceType': {
      AppLocale.zhHans: '类型',
      AppLocale.zhHant: '類型',
      AppLocale.en: 'Type',
      AppLocale.ja: 'タイプ',
    },
    'classSourceContentrating': {
      AppLocale.zhHans: '评级',
      AppLocale.zhHant: '評級',
      AppLocale.en: 'Content Rating',
      AppLocale.ja: 'レーティング',
    },
    'classSourceRating': {
      AppLocale.zhHans: '评分',
      AppLocale.zhHant: '評分',
      AppLocale.en: 'Rating',
      AppLocale.ja: '評価',
    },
    'classSourceClass': {
      AppLocale.zhHans: '分类',
      AppLocale.zhHant: '分類',
      AppLocale.en: 'Class',
      AppLocale.ja: 'クラス',
    },
    'classSourceTags': {
      AppLocale.zhHans: '标签',
      AppLocale.zhHant: '標籤',
      AppLocale.en: 'Tags',
      AppLocale.ja: 'タグ',
    },
    'grouping': {
      AppLocale.zhHans: '分组',
      AppLocale.zhHant: '分組',
      AppLocale.en: 'Grouping',
      AppLocale.ja: 'グループ化',
    },
    'year': {
      AppLocale.zhHans: '年',
      AppLocale.zhHant: '年',
      AppLocale.en: '-',
      AppLocale.ja: '年',
    },
    'month': {
      AppLocale.zhHans: '月',
      AppLocale.zhHant: '月',
      AppLocale.en: '-',
      AppLocale.ja: '月',
    },
    'day': {
      AppLocale.zhHans: '日',
      AppLocale.zhHant: '日',
      AppLocale.en: '',
      AppLocale.ja: '日',
    },

    // ======== edit_dialog ========
    'batchEditFolder': {
      AppLocale.zhHans: '批量编辑文件夹 ({n} 项)',
      AppLocale.zhHant: '批量編輯資料夾 ({n} 項)',
      AppLocale.en: 'Batch Edit Folders ({n})',
      AppLocale.ja: 'フォルダを一括編集 ({n})',
    },
    'editFolder': {
      AppLocale.zhHans: '编辑文件夹：{name}',
      AppLocale.zhHant: '編輯資料夾：{name}',
      AppLocale.en: 'Edit Folder: {name}',
      AppLocale.ja: 'フォルダを編集：{name}',
    },
    'batchEdit': {
      AppLocale.zhHans: '批量编辑 ({n} 项)',
      AppLocale.zhHant: '批量編輯 ({n} 項)',
      AppLocale.en: 'Batch Edit ({n})',
      AppLocale.ja: '一括編集 ({n})',
    },
    'editItem': {
      AppLocale.zhHans: '编辑：{name}',
      AppLocale.zhHant: '編輯：{name}',
      AppLocale.en: 'Edit: {name}',
      AppLocale.ja: '編集：{name}',
    },
    'title': {
      AppLocale.zhHans: '标题',
      AppLocale.zhHant: '標題',
      AppLocale.en: 'Title',
      AppLocale.ja: 'タイトル',
    },
    'description': {
      AppLocale.zhHans: '描述',
      AppLocale.zhHant: '描述',
      AppLocale.en: 'Description',
      AppLocale.ja: '説明',
    },
    'creator': {
      AppLocale.zhHans: '创建者',
      AppLocale.zhHant: '創作者',
      AppLocale.en: 'Creator',
      AppLocale.ja: '作成者',
    },
    'type': {
      AppLocale.zhHans: '类型',
      AppLocale.zhHant: '類型',
      AppLocale.en: 'Type',
      AppLocale.ja: '種類',
    },
    'contentRating': {
      AppLocale.zhHans: '分级',
      AppLocale.zhHant: '分級',
      AppLocale.en: 'Content Rating',
      AppLocale.ja: 'レーティング',
    },
    'rating': {
      AppLocale.zhHans: '评分',
      AppLocale.zhHant: '評分',
      AppLocale.en: 'Rating',
      AppLocale.ja: '評価',
    },
    'classLabel': {
      AppLocale.zhHans: '分类',
      AppLocale.zhHant: '分類',
      AppLocale.en: 'Class',
      AppLocale.ja: 'クラス',
    },
    'tags': {
      AppLocale.zhHans: '标签',
      AppLocale.zhHant: '標籤',
      AppLocale.en: 'Tags',
      AppLocale.ja: 'タグ',
    },
    'save': {
      AppLocale.zhHans: '保存',
      AppLocale.zhHant: '儲存',
      AppLocale.en: 'Save',
      AppLocale.ja: '保存',
    },
    'add': {
      AppLocale.zhHans: '添加',
      AppLocale.zhHant: '新增',
      AppLocale.en: 'Add',
      AppLocale.ja: '追加',
    },
    'inputPlaceholder': {
      AppLocale.zhHans: '输入...',
      AppLocale.zhHant: '輸入...',
      AppLocale.en: 'Type...',
      AppLocale.ja: '入力...',
    },
    'ratingValue': {
      AppLocale.zhHans: '评分：{n} / 5',
      AppLocale.zhHant: '評分：{n} / 5',
      AppLocale.en: 'Rating: {n} / 5',
      AppLocale.ja: '評価：{n} / 5',
    },
    'advanced': {
      AppLocale.zhHans: '高级',
      AppLocale.zhHant: '進階',
      AppLocale.en: 'Advanced',
      AppLocale.ja: '詳細設定',
    },
    'defineItem': {
      AppLocale.zhHans: 'item（项目）',
      AppLocale.zhHant: 'item（專案）',
      AppLocale.en: 'Item',
      AppLocale.ja: 'item（項目）',
    },
    'defineDir': {
      AppLocale.zhHans: 'dir（文件夹）',
      AppLocale.zhHant: 'dir（資料夾）',
      AppLocale.en: 'Directory',
      AppLocale.ja: 'dir（フォルダ）',
    },
    'defineHide': {
      AppLocale.zhHans: 'hide（隐藏）',
      AppLocale.zhHant: 'hide（隱藏）',
      AppLocale.en: 'Hide',
      AppLocale.ja: 'hide（非表示）',
    },
    'define': {
      AppLocale.zhHans: '定义',
      AppLocale.zhHant: '定義',
      AppLocale.en: 'Define',
      AppLocale.ja: '定義',
    },
    'preview': {
      AppLocale.zhHans: '预览图',
      AppLocale.zhHant: '預覽圖',
      AppLocale.en: 'Preview',
      AppLocale.ja: 'プレビュー',
    },
    'previewHint': {
      AppLocale.zhHans: '预览图（相对路径，留空自动选择）',
      AppLocale.zhHant: '預覽圖（相對路徑，留空自動選擇）',
      AppLocale.en: 'Preview (relative path, leave empty for auto)',
      AppLocale.ja: 'プレビュー（相対パス、空欄で自動選択）',
    },
    'star': {
      AppLocale.zhHans: '标星',
      AppLocale.zhHant: '標星',
      AppLocale.en: 'Star',
      AppLocale.ja: 'スター',
    },
    'gotoSection': {
      AppLocale.zhHans: '关联项目 (goto)',
      AppLocale.zhHant: '關聯項目 (goto)',
      AppLocale.en: 'Related Items (goto)',
      AppLocale.ja: '関連項目 (goto)',
    },
    'overwrite': {
      AppLocale.zhHans: '覆盖',
      AppLocale.zhHant: '覆蓋',
      AppLocale.en: 'Overwrite',
      AppLocale.ja: '上書き',
    },
    'append': {
      AppLocale.zhHans: '追加',
      AppLocale.zhHant: '追加',
      AppLocale.en: 'Append',
      AppLocale.ja: '追加',
    },
    'remove': {
      AppLocale.zhHans: '删除',
      AppLocale.zhHant: '刪除',
      AppLocale.en: 'Remove',
      AppLocale.ja: '削除',
    },
    'saveFailed': {
      AppLocale.zhHans: '保存失败: {error}',
      AppLocale.zhHant: '儲存失敗: {error}',
      AppLocale.en: 'Save failed: {error}',
      AppLocale.ja: '保存失敗: {error}',
    },

    // ======== exe_picker_dialog ========
    'openWith': {
      AppLocale.zhHans: '打开方式',
      AppLocale.zhHant: '開啟方式',
      AppLocale.en: 'Open With',
      AppLocale.ja: 'プログラムから開く',
    },
    'browseOther': {
      AppLocale.zhHans: '浏览选择其他程序...',
      AppLocale.zhHant: '瀏覽選擇其他程式...',
      AppLocale.en: 'Browse for another program...',
      AppLocale.ja: '他のプログラムを参照...',
    },
    'noRecords': {
      AppLocale.zhHans: '还没有使用过的程序\n点击下方按钮浏览选择',
      AppLocale.zhHant: '還沒有使用過的程式\n點擊下方按鈕瀏覽選擇',
      AppLocale.en: 'No recent programs\nClick the button below to browse',
      AppLocale.ja: '最近使用したプログラムはありません\n下のボタンから参照',
    },
    'deleteRecord': {
      AppLocale.zhHans: '删除此记录',
      AppLocale.zhHant: '刪除此記錄',
      AppLocale.en: 'Delete this record',
      AppLocale.ja: 'この記録を削除',
    },
    'selectExe': {
      AppLocale.zhHans: '选择要使用的程序',
      AppLocale.zhHant: '選擇要使用的程式',
      AppLocale.en: 'Select the program to use',
      AppLocale.ja: '使用するプログラムを選択',
    },

    // ======== file_browser_panel ========
    'fileContent': {
      AppLocale.zhHans: '{title} 的内容',
      AppLocale.zhHant: '{title} 的內容',
      AppLocale.en: 'Contents of {title}',
      AppLocale.ja: '{title} の内容',
    },
    'hideInfo': {
      AppLocale.zhHans: '隐藏 Info/Preview',
      AppLocale.zhHant: '隱藏 Info/Preview',
      AppLocale.en: 'Hide Info/Preview',
      AppLocale.ja: 'Info/Preview を隠す',
    },
    'showInfo': {
      AppLocale.zhHans: '显示 Info/Preview',
      AppLocale.zhHant: '顯示 Info/Preview',
      AppLocale.en: 'Show Info/Preview',
      AppLocale.ja: 'Info/Preview を表示',
    },
    'closePanel': {
      AppLocale.zhHans: '✕ 关闭',
      AppLocale.zhHant: '✕ 關閉',
      AppLocale.en: '✕ Close',
      AppLocale.ja: '✕ 閉じる',
    },
    'folderNotExist': {
      AppLocale.zhHans: '文件夹不存在',
      AppLocale.zhHant: '資料夾不存在',
      AppLocale.en: 'Folder does not exist',
      AppLocale.ja: 'フォルダが存在しません',
    },
    'noFiles': {
      AppLocale.zhHans: '没有可显示的文件',
      AppLocale.zhHant: '沒有可顯示的檔案',
      AppLocale.en: 'No files to display',
      AppLocale.ja: '表示できるファイルがありません',
    },
    'defaultOpen': {
      AppLocale.zhHans: '以默认方式打开',
      AppLocale.zhHant: '以預設方式開啟',
      AppLocale.en: 'Open with default',
      AppLocale.ja: '既定のプログラムで開く',
    },
    'open': {
      AppLocale.zhHans: '打开',
      AppLocale.zhHant: '開啟',
      AppLocale.en: 'Open',
      AppLocale.ja: '開く',
    },
    'openWithDefault': {
      AppLocale.zhHans: '以默认方式打开',
      AppLocale.zhHant: '以預設方式開啟',
      AppLocale.en: 'Open with default',
      AppLocale.ja: '既定のプログラムで開く',
    },
    'openAs': {
      AppLocale.zhHans: '打开方式...',
      AppLocale.zhHant: '開啟方式...',
      AppLocale.en: 'Open with...',
      AppLocale.ja: 'プログラムから開く...',
    },
    'rename': {
      AppLocale.zhHans: '重命名',
      AppLocale.zhHant: '重新命名',
      AppLocale.en: 'Rename',
      AppLocale.ja: '名前の変更',
    },
    'showInExplorer': {
      AppLocale.zhHans: '在资源管理器中显示',
      AppLocale.zhHant: '在檔案總管中顯示',
      AppLocale.en: 'Show in Explorer',
      AppLocale.ja: 'エクスプローラで表示',
    },
    'properties': {
      AppLocale.zhHans: '属性',
      AppLocale.zhHant: '屬性',
      AppLocale.en: 'Properties',
      AppLocale.ja: 'プロパティ',
    },
    'newFileName': {
      AppLocale.zhHans: '新文件名',
      AppLocale.zhHant: '新檔案名稱',
      AppLocale.en: 'New file name',
      AppLocale.ja: '新しいファイル名',
    },
    'renameFailed': {
      AppLocale.zhHans: '重命名失败: {error}',
      AppLocale.zhHant: '重新命名失敗: {error}',
      AppLocale.en: 'Rename failed: {error}',
      AppLocale.ja: '名前の変更に失敗: {error}',
    },
    'openN': {
      AppLocale.zhHans: '打开 {n} 项',
      AppLocale.zhHant: '開啟 {n} 項',
      AppLocale.en: 'Open {n} item(s)',
      AppLocale.ja: '{n} 件を開く',
    },
    'locateNInExplorer': {
      AppLocale.zhHans: '在资源管理器中显示 {n} 项',
      AppLocale.zhHant: '在檔案總管中顯示 {n} 項',
      AppLocale.en: 'Show {n} item(s) in Explorer',
      AppLocale.ja: '{n} 件をエクスプローラで表示',
    },
    'deselectAll': {
      AppLocale.zhHans: '取消选中',
      AppLocale.zhHant: '取消選取',
      AppLocale.en: 'Deselect all',
      AppLocale.ja: '選択を解除',
    },
    'copyInHint': {
      AppLocale.zhHans: '拖入文件以复制到此处',
      AppLocale.zhHant: '拖入檔案以複製到此處',
      AppLocale.en: 'Drop files here to copy',
      AppLocale.ja: 'ファイルをドロップしてコピー',
    },

    // ======== file_properties_dialog ========
    'propTitle': {
      AppLocale.zhHans: '属性',
      AppLocale.zhHant: '屬性',
      AppLocale.en: 'Properties',
      AppLocale.ja: 'プロパティ',
    },
    'propFileName': {
      AppLocale.zhHans: '文件名',
      AppLocale.zhHant: '檔案名稱',
      AppLocale.en: 'File name',
      AppLocale.ja: 'ファイル名',
    },
    'propLocation': {
      AppLocale.zhHans: '位置',
      AppLocale.zhHant: '位置',
      AppLocale.en: 'Location',
      AppLocale.ja: '場所',
    },
    'propSize': {
      AppLocale.zhHans: '大小',
      AppLocale.zhHant: '大小',
      AppLocale.en: 'Size',
      AppLocale.ja: 'サイズ',
    },
    'propModified': {
      AppLocale.zhHans: '修改时间',
      AppLocale.zhHant: '修改時間',
      AppLocale.en: 'Modified',
      AppLocale.ja: '更新日時',
    },
    'propAccessed': {
      AppLocale.zhHans: '访问时间',
      AppLocale.zhHant: '訪問時間',
      AppLocale.en: 'Accessed',
      AppLocale.ja: 'アクセス日時',
    },
    'propChanged': {
      AppLocale.zhHans: '元数据变化时间',
      AppLocale.zhHant: '元資料變化時間',
      AppLocale.en: 'Metadata changed',
      AppLocale.ja: 'メタデータ変更日時',
    },
    'close': {
      AppLocale.zhHans: '关闭',
      AppLocale.zhHant: '關閉',
      AppLocale.en: 'Close',
      AppLocale.ja: '閉じる',
    },

    // ======== grid_area ========
    'noItems': {
      AppLocale.zhHans: '没有找到项目',
      AppLocale.zhHant: '沒有找到專案',
      AppLocale.en: 'No items found',
      AppLocale.ja: '項目が見つかりません',
    },
    'folderSection': {
      AppLocale.zhHans: '文件夹',
      AppLocale.zhHant: '資料夾',
      AppLocale.en: 'Folders',
      AppLocale.ja: 'フォルダ',
    },
    'itemSection': {
      AppLocale.zhHans: '项目',
      AppLocale.zhHant: '專案',
      AppLocale.en: 'Items',
      AppLocale.ja: '項目',
    },
    'fileSection': {
      AppLocale.zhHans: '文件',
      AppLocale.zhHant: '檔案',
      AppLocale.en: 'Files',
      AppLocale.ja: 'ファイル',
    },
    'edit': {
      AppLocale.zhHans: '编辑',
      AppLocale.zhHant: '編輯',
      AppLocale.en: 'Edit',
      AppLocale.ja: '編集',
    },
    'batchEditN': {
      AppLocale.zhHans: '批量编辑 ({n} 项)',
      AppLocale.zhHant: '批量編輯 ({n} 項)',
      AppLocale.en: 'Batch Edit ({n})',
      AppLocale.ja: '一括編集 ({n})',
    },
    'locateHere': {
      AppLocale.zhHans: '定位到此处',
      AppLocale.zhHant: '定位到此處',
      AppLocale.en: 'Locate Here',
      AppLocale.ja: 'ここに移動',
    },
    'enterFolder': {
      AppLocale.zhHans: '进入文件夹',
      AppLocale.zhHant: '進入資料夾',
      AppLocale.en: 'Enter Folder',
      AppLocale.ja: 'フォルダに入る',
    },
    'openInExplorer': {
      AppLocale.zhHans: '在资源管理器中显示',
      AppLocale.zhHant: '在檔案總管中顯示',
      AppLocale.en: 'Show in Explorer',
      AppLocale.ja: 'エクスプローラで表示',
    },

    // ======== detail_panel ========
    'selectHint': {
      AppLocale.zhHans: '选择一个项目\n查看详情',
      AppLocale.zhHant: '選擇一個專案\n查看詳情',
      AppLocale.en: 'Select an item\nto view details',
      AppLocale.ja: '項目を選択して\n詳細を表示',
    },
    'folderLabel': {
      AppLocale.zhHans: '文件夹',
      AppLocale.zhHant: '資料夾',
      AppLocale.en: 'Folder',
      AppLocale.ja: 'フォルダ',
    },
    'subfolderCount': {
      AppLocale.zhHans: '子文件夹数',
      AppLocale.zhHant: '子資料夾數',
      AppLocale.en: 'Subfolders',
      AppLocale.ja: 'サブフォルダ数',
    },
    'directItemCount': {
      AppLocale.zhHans: '直接项目数',
      AppLocale.zhHant: '直接專案數',
      AppLocale.en: 'Direct Items',
      AppLocale.ja: '直接項目数',
    },
    'path': {
      AppLocale.zhHans: '路径',
      AppLocale.zhHant: '路徑',
      AppLocale.en: 'Path',
      AppLocale.ja: 'パス',
    },
    'extension': {
      AppLocale.zhHans: '扩展名',
      AppLocale.zhHant: '副檔名',
      AppLocale.en: 'Extension',
      AppLocale.ja: '拡張子',
    },
    'noExt': {
      AppLocale.zhHans: '(无)',
      AppLocale.zhHant: '(無)',
      AppLocale.en: '(none)',
      AppLocale.ja: '(なし)',
    },
    'size': {
      AppLocale.zhHans: '大小',
      AppLocale.zhHant: '大小',
      AppLocale.en: 'Size',
      AppLocale.ja: 'サイズ',
    },
    'modifiedTime': {
      AppLocale.zhHans: '修改时间',
      AppLocale.zhHant: '修改時間',
      AppLocale.en: 'Modified',
      AppLocale.ja: '更新日時',
    },
    'relatedItems': {
      AppLocale.zhHans: '关联项目',
      AppLocale.zhHant: '關聯項目',
      AppLocale.en: 'Related Items',
      AppLocale.ja: '関連項目',
    },

    // ======== top_bar ========
    'settingsTooltip': {
      AppLocale.zhHans: '设置',
      AppLocale.zhHant: '設定',
      AppLocale.en: 'Settings',
      AppLocale.ja: '設定',
    },
    'searchHint': {
      AppLocale.zhHans: '搜索...',
      AppLocale.zhHant: '搜尋...',
      AppLocale.en: 'Search...',
      AppLocale.ja: '検索...',
    },
    'sortName': {
      AppLocale.zhHans: '名称',
      AppLocale.zhHant: '名稱',
      AppLocale.en: 'Name',
      AppLocale.ja: '名前',
    },
    'sortSize': {
      AppLocale.zhHans: '大小',
      AppLocale.zhHant: '大小',
      AppLocale.en: 'Size',
      AppLocale.ja: 'サイズ',
    },
    'sortDate': {
      AppLocale.zhHans: '日期',
      AppLocale.zhHant: '日期',
      AppLocale.en: 'Date',
      AppLocale.ja: '日付',
    },
    'sortMethod': {
      AppLocale.zhHans: '排序方式',
      AppLocale.zhHant: '排序方式',
      AppLocale.en: 'Sort Method',
      AppLocale.ja: 'ソート方法',
    },
    'sortAsc': {
      AppLocale.zhHans: '当前:升序',
      AppLocale.zhHant: '目前:升序',
      AppLocale.en: 'Ascending',
      AppLocale.ja: '昇順',
    },
    'sortDesc': {
      AppLocale.zhHans: '当前:降序',
      AppLocale.zhHant: '目前:降序',
      AppLocale.en: 'Descending',
      AppLocale.ja: '降順',
    },
    'refreshTooltip': {
      AppLocale.zhHans: '刷新',
      AppLocale.zhHant: '重新整理',
      AppLocale.en: 'Refresh',
      AppLocale.ja: '更新',
    },

    // ======== library_root_selector ========
    'selectLibrary': {
      AppLocale.zhHans: '选择资源库',
      AppLocale.zhHant: '選擇資源庫',
      AppLocale.en: 'Select Library',
      AppLocale.ja: 'ライブラリを選択',
    },
    'librarySelector': {
      AppLocale.zhHans: '资源库选择器',
      AppLocale.zhHant: '資源庫選擇器',
      AppLocale.en: 'Library Selector',
      AppLocale.ja: 'ライブラリセレクタ',
    },
    'searchLibrary': {
      AppLocale.zhHans: '搜索资源库名称或路径...',
      AppLocale.zhHant: '搜尋資源庫名稱或路徑...',
      AppLocale.en: 'Search library name or path...',
      AppLocale.ja: 'ライブラリ名またはパスを検索...',
    },
    'noLibraries': {
      AppLocale.zhHans: '还没有添加任何资源库',
      AppLocale.zhHant: '還沒有新增任何資源庫',
      AppLocale.en: 'No libraries added yet',
      AppLocale.ja: 'ライブラリが追加されていません',
    },
    'noMatch': {
      AppLocale.zhHans: '没有匹配的资源库',
      AppLocale.zhHant: '沒有匹配的資源庫',
      AppLocale.en: 'No matching libraries',
      AppLocale.ja: '一致するライブラリがありません',
    },
    'openOtherLibrary': {
      AppLocale.zhHans: '打开其他资源库...',
      AppLocale.zhHant: '開啟其他資源庫...',
      AppLocale.en: 'Open Other Library...',
      AppLocale.ja: '他のライブラリを開く...',
    },
    'libraryDisplayName': {
      AppLocale.zhHans: '资源库显示名称',
      AppLocale.zhHant: '資源庫顯示名稱',
      AppLocale.en: 'Library display name',
      AppLocale.ja: 'ライブラリ表示名',
    },
    'saveTooltip': {
      AppLocale.zhHans: '保存',
      AppLocale.zhHant: '儲存',
      AppLocale.en: 'Save',
      AppLocale.ja: '保存',
    },
    'cancelTooltip': {
      AppLocale.zhHans: '取消',
      AppLocale.zhHant: '取消',
      AppLocale.en: 'Cancel',
      AppLocale.ja: 'キャンセル',
    },
    'renameLibrary': {
      AppLocale.zhHans: '命名资源库',
      AppLocale.zhHant: '命名資源庫',
      AppLocale.en: 'Rename Library',
      AppLocale.ja: 'ライブラリ名を変更',
    },
    'openExplorer': {
      AppLocale.zhHans: '在资源管理器中打开',
      AppLocale.zhHant: '在檔案總管中開啟',
      AppLocale.en: 'Open in Explorer',
      AppLocale.ja: 'エクスプローラで開く',
    },
    'removeFromList': {
      AppLocale.zhHans: '从列表中删除',
      AppLocale.zhHant: '從列表中刪除',
      AppLocale.en: 'Remove from list',
      AppLocale.ja: 'リストから削除',
    },
    'selectLibraryDir': {
      AppLocale.zhHans: '选择资源库根目录',
      AppLocale.zhHant: '選擇資源庫根目錄',
      AppLocale.en: 'Select library root directory',
      AppLocale.ja: 'ライブラリのルートディレクトリを選択',
    },

    // ======== goto_editor ========
    'gotoName': {
      AppLocale.zhHans: '名称',
      AppLocale.zhHant: '名稱',
      AppLocale.en: 'Name',
      AppLocale.ja: '名前',
    },
    'gotoPath': {
      AppLocale.zhHans: '相对路径（可空）',
      AppLocale.zhHant: '相對路徑（可空）',
      AppLocale.en: 'Relative path (optional)',
      AppLocale.ja: '相対パス（省略可）',
    },
    'gotoUuid': {
      AppLocale.zhHans: 'uuid（可空）',
      AppLocale.zhHant: 'uuid（可空）',
      AppLocale.en: 'UUID (optional)',
      AppLocale.ja: 'UUID（省略可）',
    },
    'addRelation': {
      AppLocale.zhHans: '添加关联',
      AppLocale.zhHant: '新增關聯',
      AppLocale.en: 'Add Relation',
      AppLocale.ja: '関連を追加',
    },

    // ======== category_panel ========
    'allItems': {
      AppLocale.zhHans: '全部项目',
      AppLocale.zhHant: '全部專案',
      AppLocale.en: 'All Items',
      AppLocale.ja: 'すべての項目',
    },
    'rootDir': {
      AppLocale.zhHans: '根目录',
      AppLocale.zhHant: '根目錄',
      AppLocale.en: 'Root',
      AppLocale.ja: 'ルート',
    },

    // ======== library_state ========
    'allClass': {
      AppLocale.zhHans: '全部',
      AppLocale.zhHant: '全部',
      AppLocale.en: 'All',
      AppLocale.ja: 'すべて',
    },
    'unclassified': {
      AppLocale.zhHans: '未分类',
      AppLocale.zhHant: '未分類',
      AppLocale.en: 'Unclassified',
      AppLocale.ja: '未分類',
    },

    // ======== shell_page ========
    'scanFailed': {
      AppLocale.zhHans: '扫描失败: {error}',
      AppLocale.zhHant: '掃描失敗: {error}',
      AppLocale.en: 'Scan failed: {error}',
      AppLocale.ja: 'スキャン失敗: {error}',
    },
    'selectLibraryFirst': {
      AppLocale.zhHans: '请先选择一个资源库目录',
      AppLocale.zhHant: '請先選擇一個資源庫目錄',
      AppLocale.en: 'Please select a library directory first',
      AppLocale.ja: '最初にライブラリディレクトリを選択してください',
    },
    'targetNotFound': {
      AppLocale.zhHans: '找不到目标项目',
      AppLocale.zhHant: '找不到目標專案',
      AppLocale.en: 'Target item not found',
      AppLocale.ja: '対象の項目が見つかりません',
    },

    // ======== item_info ========
    'noDescription': {
      AppLocale.zhHans: '无描述',
      AppLocale.zhHant: '無描述',
      AppLocale.en: 'No description',
      AppLocale.ja: '説明なし',
    },


    // ======== create_item_dialog / image_cropper ========
    'create': {
      AppLocale.zhHans: '创建',
      AppLocale.zhHant: '創建',
      AppLocale.en: 'Create',
      AppLocale.ja: '作成',
    },
    'createItem': {
      AppLocale.zhHans: '创建项目',
      AppLocale.zhHant: '創建項目',
      AppLocale.en: 'Create Item',
      AppLocale.ja: '項目を作成',
    },
    'createFailed': {
      AppLocale.zhHans: '创建失败',
      AppLocale.zhHant: '創建失敗',
      AppLocale.en: 'Create failed',
      AppLocale.ja: '作成失敗',
    },
    'parentFolder': {
      AppLocale.zhHans: '父文件夹',
      AppLocale.zhHant: '父文件夾',
      AppLocale.en: 'Parent Folder',
      AppLocale.ja: '親フォルダ',
    },
    'tapToSelectFolder': {
      AppLocale.zhHans: '点击选择文件夹',
      AppLocale.zhHant: '點擊選擇文件夾',
      AppLocale.en: 'Tap to select folder',
      AppLocale.ja: 'タップしてフォルダを選択',
    },
    'selectParentFolder': {
      AppLocale.zhHans: '请选择父文件夹',
      AppLocale.zhHant: '請選擇父文件夾',
      AppLocale.en: 'Please select a parent folder',
      AppLocale.ja: '親フォルダを選択してください',
    },
    'titleRequired': {
      AppLocale.zhHans: '请输入项目名称',
      AppLocale.zhHant: '請輸入項目名稱',
      AppLocale.en: 'Please enter item name',
      AppLocale.ja: '項目名を入力してください',
    },
    'previewImage': {
      AppLocale.zhHans: '预览图',
      AppLocale.zhHant: '預覽圖',
      AppLocale.en: 'Preview Image',
      AppLocale.ja: 'プレビュー画像',
    },
    'tapToSelectImage': {
      AppLocale.zhHans: '点击或拖入图片',
      AppLocale.zhHant: '點擊或拖入圖片',
      AppLocale.en: 'Tap or drag an image here',
      AppLocale.ja: 'タップまたは画像をドロップ',
    },
    'imageLoadFailed': {
      AppLocale.zhHans: '图片加载失败',
      AppLocale.zhHant: '圖片加載失敗',
      AppLocale.en: 'Failed to load image',
      AppLocale.ja: '画像の読み込みに失敗しました',
    },

    'importFiles': {
      AppLocale.zhHans: '导入文件',
      AppLocale.zhHant: '導入文件',
      AppLocale.en: 'Import Files',
      AppLocale.ja: 'ファイルをインポート',
    },
    'selectFiles': {
      AppLocale.zhHans: '选择文件',
      AppLocale.zhHant: '選擇文件',
      AppLocale.en: 'Select Files',
      AppLocale.ja: 'ファイルを選択',
    },
    'selectFolder': {
      AppLocale.zhHans: '选择文件夹',
      AppLocale.zhHant: '選擇文件夾',
      AppLocale.en: 'Select Folder',
      AppLocale.ja: 'フォルダを選択',
    },
    'dragHint': {
      AppLocale.zhHans: '也可拖入文件或文件夹到此处',
      AppLocale.zhHant: '也可拖入文件或文件夾到此處',
      AppLocale.en: 'Or drag files/folders here',
      AppLocale.ja: 'ファイルやフォルダをここにドロップ',
    },

    // ======== 视频播放器 ========
    'videoPlayer': {
      AppLocale.zhHans: '视频播放器',
      AppLocale.zhHant: '視頻播放器',
      AppLocale.en: 'Video Player',
      AppLocale.ja: '動画プレーヤー',
    },
    'openProjectVideos': {
      AppLocale.zhHans: '播放项目内视频',
      AppLocale.zhHant: '播放項目內視頻',
      AppLocale.en: 'Play Project Videos',
      AppLocale.ja: 'プロジェクトの動画を再生',
    },
    'playVideo': {
      AppLocale.zhHans: '播放视频',
      AppLocale.zhHant: '播放視頻',
      AppLocale.en: 'Play Video',
      AppLocale.ja: '動画を再生',
    },
    'playlist': {
      AppLocale.zhHans: '播放列表',
      AppLocale.zhHant: '播放列表',
      AppLocale.en: 'Playlist',
      AppLocale.ja: 'プレイリスト',
    },
    'nowPlaying': {
      AppLocale.zhHans: '正在播放',
      AppLocale.zhHant: '正在播放',
      AppLocale.en: 'Now Playing',
      AppLocale.ja: '再生中',
    },
    'videoCodec': {
      AppLocale.zhHans: '编码',
      AppLocale.zhHant: '編碼',
      AppLocale.en: 'Codec',
      AppLocale.ja: 'コーデック',
    },
    'videoResolution': {
      AppLocale.zhHans: '分辨率',
      AppLocale.zhHant: '解像度',
      AppLocale.en: 'Resolution',
      AppLocale.ja: '解像度',
    },
    'videoFps': {
      AppLocale.zhHans: '帧率',
      AppLocale.zhHant: '幀率',
      AppLocale.en: 'FPS',
      AppLocale.ja: 'フレームレート',
    },
    'videoDuration': {
      AppLocale.zhHans: '时长',
      AppLocale.zhHant: '時長',
      AppLocale.en: 'Duration',
      AppLocale.ja: '長さ',
    },
    'videoSize': {
      AppLocale.zhHans: '大小',
      AppLocale.zhHant: '大小',
      AppLocale.en: 'Size',
      AppLocale.ja: 'サイズ',
    },
    'noVideoFiles': {
      AppLocale.zhHans: '该项目内没有找到视频文件',
      AppLocale.zhHant: '該項目內沒有找到視頻文件',
      AppLocale.en: 'No video files found in this project',
      AppLocale.ja: 'このプロジェクトに動画が見つかりません',
    },
    'loadingMeta': {
      AppLocale.zhHans: '加载元数据…',
      AppLocale.zhHant: '加載元數據…',
      AppLocale.en: 'Loading metadata…',
      AppLocale.ja: 'メタデータ読込中…',
    },
    'playListEmpty': {
      AppLocale.zhHans: '播放列表为空',
      AppLocale.zhHant: '播放列表為空',
      AppLocale.en: 'Playlist is empty',
      AppLocale.ja: 'プレイリストが空です',
    },
    'repeatOff': {
      AppLocale.zhHans: '顺序播放',
      AppLocale.zhHant: '順序播放',
      AppLocale.en: 'Sequential',
      AppLocale.ja: '順次再生',
    },
    'repeatAll': {
      AppLocale.zhHans: '列表循环',
      AppLocale.zhHant: '列表循環',
      AppLocale.en: 'Repeat All',
      AppLocale.ja: 'リスト再生',
    },
    'repeatOne': {
      AppLocale.zhHans: '单曲循环',
      AppLocale.zhHant: '單曲循環',
      AppLocale.en: 'Repeat One',
      AppLocale.ja: '一曲リピート',
    },
    'shuffle': {
      AppLocale.zhHans: '随机播放',
      AppLocale.zhHant: '隨機播放',
      AppLocale.en: 'Shuffle',
      AppLocale.ja: 'シャッフル',
    },
    'speed': {
      AppLocale.zhHans: '倍速',
      AppLocale.zhHant: '倍速',
      AppLocale.en: 'Speed',
      AppLocale.ja: '速度',
    },
    'volume': {
      AppLocale.zhHans: '音量',
      AppLocale.zhHant: '音量',
      AppLocale.en: 'Volume',
      AppLocale.ja: '音量',
    },
    'mute': {
      AppLocale.zhHans: '静音',
      AppLocale.zhHant: '靜音',
      AppLocale.en: 'Mute',
      AppLocale.ja: 'ミュート',
    },
    'fullscreen': {
      AppLocale.zhHans: '全屏',
      AppLocale.zhHant: '全屏',
      AppLocale.en: 'Fullscreen',
      AppLocale.ja: '全画面',
    },
    'exitFullscreen': {
      AppLocale.zhHans: '退出全屏',
      AppLocale.zhHant: '退出全屏',
      AppLocale.en: 'Exit Fullscreen',
      AppLocale.ja: '全画面終了',
    },
    'prevTrack': {
      AppLocale.zhHans: '上一个',
      AppLocale.zhHant: '上一個',
      AppLocale.en: 'Previous',
      AppLocale.ja: '前へ',
    },
    'nextTrack': {
      AppLocale.zhHans: '下一个',
      AppLocale.zhHant: '下一個',
      AppLocale.en: 'Next',
      AppLocale.ja: '次へ',
    },
    'audioTrack': {
      AppLocale.zhHans: '音轨',
      AppLocale.zhHant: '音軌',
      AppLocale.en: 'Audio Track',
      AppLocale.ja: '音声トラック',
    },
    'subtitle': {
      AppLocale.zhHans: '字幕',
      AppLocale.zhHant: '字幕',
      AppLocale.en: 'Subtitle',
      AppLocale.ja: '字幕',
    },
    'openFile': {
      AppLocale.zhHans: '打开文件',
      AppLocale.zhHant: '打開文件',
      AppLocale.en: 'Open File',
      AppLocale.ja: 'ファイルを開く',
    },
    'openFolder': {
      AppLocale.zhHans: '打开文件夹',
      AppLocale.zhHant: '打開文件夾',
      AppLocale.en: 'Open Folder',
      AppLocale.ja: 'フォルダを開く',
    },
    'closePlayer': {
      AppLocale.zhHans: '关闭播放器',
      AppLocale.zhHant: '關閉播放器',
      AppLocale.en: 'Close Player',
      AppLocale.ja: 'プレーヤーを閉じる',
    },
    'play': {
      AppLocale.zhHans: '播放',
      AppLocale.zhHant: '播放',
      AppLocale.en: 'Play',
      AppLocale.ja: '再生',
    },
    'pause': {
      AppLocale.zhHans: '暂停',
      AppLocale.zhHant: '暫停',
      AppLocale.en: 'Pause',
      AppLocale.ja: '一時停止',
    },
    'folderTree': {
      AppLocale.zhHans: '文件夹',
      AppLocale.zhHant: '文件夾',
      AppLocale.en: 'Folders',
      AppLocale.ja: 'フォルダ',
    },
    'allVideos': {
      AppLocale.zhHans: '全部视频',
      AppLocale.zhHant: '全部視頻',
      AppLocale.en: 'All Videos',
      AppLocale.ja: 'すべての動画',
    },
  };
}

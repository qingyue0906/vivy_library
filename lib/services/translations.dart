enum AppLocale { system, zhHans, zhHant, en, ja }

extension AppLocaleX on AppLocale {
  String get displayName {
    switch (this) {
      case AppLocale.system: return '跟随系统';
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
    'appVersion': {
      AppLocale.zhHans: '版本 0.1.0 Build260627',
      AppLocale.zhHant: '版本 0.1.0 Build260627',
      AppLocale.en: 'Version 0.1.0 Build260627',
      AppLocale.ja: 'バージョン 0.1.0 Build260627',
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
      AppLocale.zhHans: '分类标签 (class)',
      AppLocale.zhHant: '分類標籤 (class)',
      AppLocale.en: 'Class',
      AppLocale.ja: 'クラス',
    },
    'tags': {
      AppLocale.zhHans: '标签 (tags)',
      AppLocale.zhHant: '標籤 (tags)',
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
  };
}

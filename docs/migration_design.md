# Keynako migration design

## 方針

元のSwift版azooKeyは、設定用メインアプリ、iOS Keyboard Extension、共有コア／変換エンジンの3層で構成されています。Keynakoも同じ責務分割を保ちつつ、設定アプリと永続データモデルをFlutterへ移しました。

```text
Flutter application (Dart)
  |-- onboarding / tips / settings
  |-- themes / custom keys / custom tabs
  |-- user dictionary / backup / reports
  `-- MethodChannel: net.azookey/platform
          |
          +-- versioned JSON state
          +-- keyboard activation/settings
          +-- platform share sheet
          `-- contact import

Desktop input application (Flutter)
  `-- settings / input behavior preview

Desktop system IME
  |-- Windows TSF
  |-- macOS InputMethodKit
  |-- Linux IBus
  `-- native ime_core
          |-- Japanese / English / live candidates
          `-- persistent llama.cpp process / Zenzai v3.2

Android InputMethodService <---- shared JSON state ----> iOS Keyboard Extension
        |                                               |
        `-- llama.cpp JNI / Zenzai                      `-- AzooKeyKanaKanjiConverter / ZenzaiCPU
```

システムIMEは通常のFlutter Widgetとして登録できません。Androidの`InputMethodService`、iOSの`UIInputViewController`、WindowsのTSF、macOSのInputMethodKit、LinuxのIBusを薄いプラットフォーム層として残し、入力と変換の状態遷移は共通モジュールへ集約します。

## 共有状態

`AppData`はバージョン付きJSONです。Androidでは`SharedPreferences`、iOSではApp Group `group.com.azooKey.keyboard`に`azookey_flutter_state`として保存します。`live_conversion`、`keyboard_type`、`flick_sensitivity_setting`などSwift版由来のキーは互換性のため維持しています。

状態には以下を含みます。

- キーボード・変換・Zenzai設定
- ユーザー辞書、テンプレート、品詞情報
- ライト／ダークテーマと選択状態
- カスタムグリッド／フレーズタブ
- カスタムキーとタブバー割り当て
- クリップボード履歴とローカル学習スコア

## 機能対応

| Swift版の領域 | Keynakoの実装先 |
| --- | --- |
| 4つのメインタブ | Flutter Material 3 `NavigationBar` |
| オンボーディング／有効化案内 | Flutter + OS設定画面bridge |
| フリック／QWERTY | Android/iOSネイティブキーボードcontroller |
| 変換候補／ライブ変換 | ネイティブ候補バー + かな漢字変換engine |
| ユーザー辞書／テンプレート | Flutter CRUD + 共有JSON |
| キーボード背景画像 | Flutter画像選択 + Androidアプリ領域／iOS App Group + ネイティブ背景描画 |
| 学習／リセット | 共有learning map + iOS converter memory |
| テーマ／配色 | Flutter editor + ネイティブrenderer |
| Custard 1.0〜1.2（座標、複数アクション、長押し反復、variation） | URL importer + ネイティブrenderer |
| クリップボード | OS clipboard + 共有履歴 |
| 連絡先取り込み | platform contacts API + 共有辞書 |
| 音／触覚／片手設定 | ネイティブキーボードbehavior |
| import/export/share | JSON + OS share sheet |
| 変換報告／単語共有 | 変換報告は互換endpoint、単語共有はKeynako専用HTTPSゲートウェイ |
| 共有変換辞書 | `StupidGame/keynako_hotfix_dictionary_storage` Contents API + `data_v1.json`（5分キャッシュ） |

## Zenzai

中／高エフォートは`zenz-v3.2-small-gguf`、低エフォートは`zenz-v3.2-xsmall-gguf`を利用します。

- Android: モデルをAPK assetsからアプリ専用領域へ一度だけ展開し、azooKey forkのllama.cppをJNI経由で実行します。生成候補と既存候補をv3.2 scoringで再順位付けします。不正Unicode、制御文字、異常な長さの生成結果は候補に採用しません。
- iOS: azooKey本体と同じ`AzooKeyKanaKanjiConverter`の固定commit `93766c46e31fa6a18b7ced49dab31337780f6f45`と`ZenzaiCPU` traitを使い、モデルをKeyboard Extension resourceとして参照します。
- PC: `keynako_zenzai`をIMEプロセスから常駐起動し、Windows TSF、macOS InputMethodKit、Linux IBusの明示変換候補へ生成結果を挿入します。通常候補とライブ変換はモデルの起動を待たずに動作します。

モデルの正確なサイズとSHA-256は`assets/ZENZAI_MODELS.md`に記録しています。推論は端末内で完結します。

## ビルド上の制約

AndroidはWindowsを含むFlutter対応hostでビルドできます。iOSはXcode、Apple SDK、署名が必要なためmacOSでのみ最終ビルドできます。Runner、Keyboard Extension、App Groupのidentifierは選択したApple Developer Teamでプロビジョニングしてください。

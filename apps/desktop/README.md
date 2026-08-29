# Keynako Desktop

Windows、Linux、macOS向けKeynako IMEの設定・入力動作確認アプリです。OSの任意の入力欄へ文字を届ける処理は`../../platforms`以下のTSF、InputMethodKit、IBus adapterが担当します。

入力処理は`lib/input/desktop_input_controller.dart`、画面は
`lib/features/ime/ime_page.dart`、Zenzai実行ファイルとモデルの探索は
`lib/input/desktop_zenzai_locator.dart`に分けています。候補生成そのものは
`../../packages/keynako_conversion`を利用します。

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

Zenzaiを含む配布構成とC++実行ファイルの作り方は
[`../../docs/desktop_ime.md`](../../docs/desktop_ime.md)を参照してください。

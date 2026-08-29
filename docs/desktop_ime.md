# PC用Keynako IME

PC版は、Flutter製の設定・動作確認アプリと、OSへ入力ソースとして登録するIME adapterで構成します。変換状態は`packages/keynako_conversion/native/ime_core`へ分離し、Windows TSFとmacOS InputMethodKitから直接、Linux IBusからC ABI経由で共有します。

## 入力機能

- 日本語ローマ字入力、ひらがな／漢字／カタカナ／英字候補
- 英語直接入力、大文字／先頭大文字候補
- 入力ごとに未確定文字列と先頭候補を更新するライブ変換
- `Space`／上下キーによる候補選択、`Enter`による確定、`Esc`による取消
- `Ctrl+Space`による日本語／英語モード切替
- Zenzai v3.2 xsmall／smallと常駐`llama.cpp`プロセスによる端末内推論

Zenzaiは最初の明示変換時にモデルを読み込みます。モデルや実行ファイルが見つからない場合も、通常辞書、かな、カタカナ、英語候補は利用できます。任意のモデルへ切り替えるときは`KEYNAKO_ZENZAI_MODEL`を指定します。

## Windows

Actions成果物の`KeynakoSetup.exe`を実行します。セットアップは管理者権限で設定アプリ、64-bit TSF DLL、ZenzaiとモデルをProgram Filesへ配置し、Keynakoを日本語入力プロファイルとして登録します。Windowsの入力設定からKeynakoを選択できます。

Windowsの「インストールされているアプリ」またはスタートメニューの`Uninstall Keynako`を開くと、exe形式のアンインストーラーがTSF登録とファイルを削除します。

開発用ビルド:

```powershell
cmake -S platforms/windows -B build/windows-ime -A x64
cmake --build build/windows-ime --config Release
```

## macOS

`Keynako.inputmethod`を`~/Library/Input Methods`へコピーし、ログアウト後に「システム設定 > キーボード > 入力ソース」から追加します。同梱の`install-input-method.sh`と`uninstall-input-method.sh`でも導入・削除できます。配布成果物はad-hoc署名であり、一般配布ではDeveloper IDによる署名と公証が必要です。

開発用ビルド:

```sh
bash platforms/macos/build-input-method.sh build/macos-ime
```

## Linux

IBusとPyGObjectが必要です。Debian／Ubuntu系では`python3-gi`、`gir1.2-ibus-1.0`、`ibus`を導入し、展開した成果物の`install-ime.sh`を実行します。利用者領域へengineとcomponent定義を配置してIBusを再起動します。削除は`uninstall-ime.sh`です。

## Flutter設定・動作確認アプリ

```sh
cd apps/desktop
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

この画面はIMEと同じ日本語、英語、候補、ライブ変換、Zenzaiの状態遷移を試すためのものです。通常の利用時はOS側でKeynakoを入力ソースとして選び、任意のアプリへ直接入力します。

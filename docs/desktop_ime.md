# PC用Keynako IME

PC版は、Flutter製の設定・動作確認アプリと、OSへ入力ソースとして登録するIME adapterで構成します。変換状態は`packages/keynako_conversion/native/ime_core`へ分離し、Windows TSFとmacOS InputMethodKitから直接、Linux IBusからC ABI経由で共有します。

## 入力機能

- 日本語ローマ字入力、ひらがな／漢字／カタカナ／英字候補
- `A`表示時の英語直接入力
- 入力ごとに未確定文字列と先頭候補を更新するライブ変換
- `Space`／変換キーで変換開始と次候補、上下／Page Up／Page Downによる候補選択。未入力時の変換キーは日本語／英語モード切替
- 候補番号`1`〜`9`またはクリックによる確定、`Enter`による確定
- 変換中の`Esc`／`Backspace`で読みへ戻り、もう一度`Esc`で入力を取り消す二段階操作
- 未確定入力中に`Backspace`を約0.35秒以内で2回押す単語削除。長押しの連続削除は通常どおり一文字ずつ動作
- `Ctrl+Space`による日本語／英語モード切替
- サブモジュールのAzooKey標準辞書と、別リポジトリの`Dictionary/data_v1.json`共有辞書を併用
- 共有辞書をインストール時から利用し、アプリ版と同じ5分間隔で取得して三OSのシステムIMEへ反映
- Windowsでは第一候補以外の辞書候補を確定したあと、確認操作によって読みと選択語を共有変換辞書へ改善として送信
- Zenzai v3.2 xsmall／smallと常駐`llama.cpp`プロセスによる端末内推論

Zenzaiは最初の明示変換時にモデルを読み込みます。モデルや実行ファイルが見つからない場合も、通常辞書、かな、カタカナ、英語候補は利用できます。任意のモデルへ切り替えるときは`KEYNAKO_ZENZAI_MODEL`を指定します。

## Windows

Actions成果物の`KeynakoSetup.exe`を実行します。セットアップは管理者権限で設定アプリ、64-bit TSF DLL、ZenzaiとモデルをProgram Filesへ配置し、Keynakoを日本語入力プロファイルとして登録します。Windowsの入力設定からKeynakoを選択できます。

選択中はWindowsの入力インジケーターへ、Flutterアプリと同じブランドアイコンと、現在の入力モードを表す`あ`／`A`を個別に表示します。モード項目をクリックすると日本語と英語を切り替えられ、メニューからライブ変換、共有辞書の手動更新、設定アプリを操作できます。角丸の候補ウィンドウには選択行、候補番号、ページ数、キー操作、共有辞書／Zenzaiの出典を表示します。候補を右クリックすると、その単語と読みをアプリの辞書登録と同じ共有ストレージへ送信します。第一候補以外の辞書候補を確定すると8秒間だけ改善の送信確認を表示し、クリックした場合に限って選択語、読み、候補順位、アプリ版番号をHTTPSで送ります。入力の前後や入力先アプリの情報は送りません。IMEは起動時と利用中の5分間隔で更新を要求し、通信は設定アプリの非表示コマンドとして別プロセスで実行します。

Windowsの「インストールされているアプリ」またはスタートメニューの`Uninstall Keynako`を開くと、exe形式のアンインストーラーがTSF登録、本体、同梱辞書、更新済み共有辞書キャッシュを削除します。

新しい`KeynakoSetup.exe`は、そのままダブルクリックして既存環境へ上書き更新できます。更新前に常駐中のKeynako Zenzaiだけを終了して同名の実行ファイルを安全に置き換え、同じバージョンのモデルは再コピーしません。ビルドごとに別名となるTSF DLLは使用中の旧ファイルへ触れないため、Explorerや入力先アプリを強制終了しません。

開発用ビルド:

```powershell
cmake -S platforms/windows -B build/windows-ime -A x64 `
  -DKEYNAKO_DICTIONARY_SUBMISSION_URL="https://example.com/submissions"
cmake --build build/windows-ime --config Release
```

送信先を指定しない開発用ビルドでは、改善の送信確認を表示しません。

## macOS

`Keynako.inputmethod`を`~/Library/Input Methods`へコピーし、ログアウト後に「システム設定 > キーボード > 入力ソース」から追加します。同梱の`install-input-method.sh`と`uninstall-input-method.sh`でも導入・削除できます。配布成果物はad-hoc署名であり、一般配布ではDeveloper IDによる署名と公証が必要です。

メニューバーの入力メニューにはFlutterアプリと同じアイコンを表示し、`ひらがな (あ)`／`英数 (A)`とライブ変換を切り替えられます。かなキーと英数キーにも対応します。

開発用ビルド:

```sh
bash platforms/macos/build-input-method.sh build/macos-ime
```

## Linux

IBusとPyGObjectが必要です。Debian／Ubuntu系では`python3-gi`、`gir1.2-ibus-1.0`、`ibus`を導入し、展開した成果物の`install-ime.sh`を実行します。利用者領域へengineとcomponent定義を配置してIBusを再起動します。削除は`uninstall-ime.sh`です。

IBusパネルには現在の入力モードを`あ`／`A`で表示し、クリックで日本語と英語を切り替えられます。

## Flutter設定・動作確認アプリ

```sh
cd apps/desktop
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

この画面はIMEと同じ日本語、英語、候補、ライブ変換、Zenzaiの状態遷移を試すためのものです。ライト／ダークテーマへ追従する画面で、選択候補、候補番号、辞書やZenzaiの出典を見分けられます。候補の右クリックから単語と読みを共有ストレージへ送信できます。共有辞書は保存済みキャッシュを起動時に読み込み、最終取得から5分以上経過していれば更新し、その後もアプリ起動中は5分ごとに更新します。「共有辞書を今すぐ読み込む」から手動更新もできます。Windowsの入力メニュー、LinuxのIBus項目、macOSの入力メニューにも同じ手動更新を用意しています。通常の利用時はOS側でKeynakoを入力ソースとして選び、任意のアプリへ直接入力します。

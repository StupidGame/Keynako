# GitHub Actionsでアプリファイルを作る

`.github/workflows/build-app-files.yml` は、Pull Request、Actions画面の手動実行、または`v`で始まるタグのpushで次の成果物を作ります。Windows成果物はすべての実行でAuthenticode署名します。Pull Requestと手動実行では外部の署名ファイルを使わず、Actionsのキャッシュに保持するCI用証明書を使います。

| ジョブ | 成果物 | 用途 |
| --- | --- | --- |
| Android | `app-release.apk`、`signature-report.txt` | Actionsのキャッシュに保持するCI用keystoreによる署名済みAPKと署名検証結果 |
| iOS | `Keynako-unsigned.ipa` | Appleの証明書で後から署名するための実機用アーカイブ |
| iOS | `Keynako-simulator.app.zip` | iOS Simulatorへ展開・インストールできるアプリ |
| Windows | `KeynakoSetup.exe` | Keynako製DLL／exeとインストーラーを常にAuthenticode署名。通常はCI用証明書、登録済み証明書がある`v`タグでは正式証明書を使用 |
| Linux | `Keynako-linux-x64.tar.gz` | Flutter設定アプリ、IBus engine、導入／削除スクリプト、Zenzai |
| macOS | `Keynako-macos.zip` | Flutter設定アプリ、InputMethodKit bundle、導入／削除スクリプト、Zenzai |

## Android署名の制約

keystoreは初回実行時に作成され、Actionsのキャッシュへ保持されます。同じキャッシュが使われる限り、異なるActions実行のAPKを上書き更新できます。キャッシュが消えた場合は署名が変わるため、以前のAPKをアンインストールしてください。この方式は動作確認向けであり、Google Play配布では本番用キーを安全に保管して継続利用する必要があります。

## iOS署名の制約

物理iPhoneへインストールできるIPAには、Apple Developer Teamが発行した証明書と、次の2つのBundle ID用プロビジョニングプロファイルが必要です。

- `io.github.StupidGame.azookeyFlutter`
- `io.github.StupidGame.azookeyFlutter.AzooKeyKeyboard`

両プロファイルにはApp Group `group.com.azooKey.keyboard`を含める必要があります。これらはApple側でのみ発行できるため、Secretsも外部資格情報も使わないワークフローでは署名済み実機IPAを作れません。`Keynako-unsigned.ipa`は、証明書を用意した環境で再署名するための成果物です。

## Windows署名

WindowsはTSF DLLを入力先プロセス内へ読み込むため、すべてのActions成果物をAuthenticode署名します。Pull Request、手動実行、正式証明書が未登録の`v`タグでは、初回実行時に作成してActionsのキャッシュへ保持するCI用自己署名証明書を使います。CI署名は改ざん検出用であり、Windowsから信頼された発行元とは認識されません。公的に信頼された配布物を作る場合は、次のRepository secretsを登録します。

- `KEYNAKO_WINDOWS_SIGNING_PFX`: PFXファイル全体をBase64にした文字列
- `KEYNAKO_WINDOWS_SIGNING_PASSWORD`: PFXのパスワード

`v`タグで両Secretsが登録されている場合だけ正式証明書を使い、それ以外はCI用証明書へフォールバックします。片方だけ登録されている場合は設定不備としてジョブを失敗させます。署名対象は`Keynako.exe`、`KeynakoIME.dll`、`KeynakoDictionarySubmit.exe`、`keynako_zenzai.exe`、完成後の`KeynakoSetup.exe`です。各ファイルはRFC 3161タイムスタンプ付きSHA-256で署名し、同じジョブ内でWindowsのAuthenticodeポリシーによる検証を通します。正式な秘密鍵はPull Requestへ渡しません。

## 成果物の取得

Actionsの完了後、実行詳細のArtifactsから次をダウンロードします。

- `keynako-android-signed-apk-<run number>`
- `keynako-ios-files-<run number>`
- `keynako-windows-installer-ci-signed-<run number>`（通常実行、正式証明書未登録時）
- `keynako-windows-installer-trusted-signed-<run number>`（正式証明書を使った`v`タグ）
- `keynako-linux-x64-<run number>`
- `keynako-macos-<run number>`

成果物は14日間保存されます。AndroidのCI用keystoreとWindowsのCI用PFXはリポジトリや成果物には含めず、Actionsキャッシュだけに保存します。キャッシュが消えた場合はCI用の署名者が変わります。

PC版ジョブは共有変換モジュール、C++入力セッション、Flutter設定アプリを検査します。WindowsではTSF DLLとInno Setup製インストーラー、macOSではInputMethodKit bundle、LinuxではIBus engineも各OS向けに検証・梱包します。`keynako_zenzai`とsmall／xsmallモデルを同梱するため、追加モデル取得は不要です。

リポジトリ変数`KEYNAKO_DICTIONARY_SUBMISSION_URL`へHTTPSゲートウェイを設定すると、Android/iOSアプリとWindows TSF IMEの改善送信先へ同じURLを組み込みます。変数が空のWindowsビルドでは送信確認を表示しません。

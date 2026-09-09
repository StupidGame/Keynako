# GitHub Actionsでアプリファイルを作る

`.github/workflows/build-app-files.yml` は、Pull Request、Actions画面の手動実行、または`v`で始まるタグのpushで次の成果物を作ります。Pull Requestと手動実行は外部の署名ファイルを使いません。`v`タグのWindows成果物だけは、登録済みのAuthenticode証明書を必須にします。

| ジョブ | 成果物 | 用途 |
| --- | --- | --- |
| Android | `app-release.apk`、`signature-report.txt` | Actionsのキャッシュに保持するCI用keystoreによる署名済みAPKと署名検証結果 |
| iOS | `Keynako-unsigned.ipa` | Appleの証明書で後から署名するための実機用アーカイブ |
| iOS | `Keynako-simulator.app.zip` | iOS Simulatorへ展開・インストールできるアプリ |
| Windows | `KeynakoSetup.exe` | `v`タグではKeynako製DLL／exeとインストーラーをAuthenticode署名。Pull Requestと手動実行では署名なしの検査用セットアップ |
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

WindowsはTSF DLLを入力先プロセス内へ読み込むため、配布物には公的に信頼されたコード署名証明書を使います。自己署名証明書は開発用に限り、配布やゲーム互換性の判断には使いません。次のRepository secretsを登録します。

- `KEYNAKO_WINDOWS_SIGNING_PFX`: PFXファイル全体をBase64にした文字列
- `KEYNAKO_WINDOWS_SIGNING_PASSWORD`: PFXのパスワード

`v`タグではSecretsが空ならWindowsジョブを失敗させます。署名対象は`Keynako.exe`、`KeynakoIME.dll`、`KeynakoDictionarySubmit.exe`、`keynako_zenzai.exe`、完成後の`KeynakoSetup.exe`です。各ファイルはRFC 3161タイムスタンプ付きSHA-256で署名し、同じジョブ内でWindowsのAuthenticodeポリシーによる検証を通します。Pull Requestのコードへ秘密鍵を渡さないため、Pull Request成果物は署名しません。

## 成果物の取得

Actionsの完了後、実行詳細のArtifactsから次をダウンロードします。

- `keynako-android-signed-apk-<run number>`
- `keynako-ios-files-<run number>`
- `keynako-windows-installer-signed-<run number>`（`v`タグ）
- `keynako-windows-installer-unsigned-<run number>`（Pull Request／手動実行）
- `keynako-linux-x64-<run number>`
- `keynako-macos-<run number>`

成果物は14日間保存されます。CI用keystoreはリポジトリや成果物には含めず、Actionsキャッシュだけに保存します。

PC版ジョブは共有変換モジュール、C++入力セッション、Flutter設定アプリを検査します。WindowsではTSF DLLとInno Setup製インストーラー、macOSではInputMethodKit bundle、LinuxではIBus engineも各OS向けに検証・梱包します。`keynako_zenzai`とsmall／xsmallモデルを同梱するため、追加モデル取得は不要です。

リポジトリ変数`KEYNAKO_DICTIONARY_SUBMISSION_URL`へHTTPSゲートウェイを設定すると、Android/iOSアプリとWindows TSF IMEの改善送信先へ同じURLを組み込みます。変数が空のWindowsビルドでは送信確認を表示しません。

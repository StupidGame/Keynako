# GitHub Actionsでアプリファイルを作る

`.github/workflows/build-app-files.yml` は、GitHub Secretsや外部の署名ファイルを登録せずに次の成果物を作ります。Actions画面の「Build app files」から手動実行するか、`v`で始まるタグをpushすると実行されます。

| ジョブ | 成果物 | 用途 |
| --- | --- | --- |
| Android | `app-release.apk`、`signature-report.txt` | Actionsのキャッシュに保持するCI用keystoreによる署名済みAPKと署名検証結果 |
| iOS | `Keynako-unsigned.ipa` | Appleの証明書で後から署名するための実機用アーカイブ |
| iOS | `Keynako-simulator.app.zip` | iOS Simulatorへ展開・インストールできるアプリ |

## Android署名の制約

keystoreは初回実行時に作成され、Actionsのキャッシュへ保持されます。同じキャッシュが使われる限り、異なるActions実行のAPKを上書き更新できます。キャッシュが消えた場合は署名が変わるため、以前のAPKをアンインストールしてください。この方式は動作確認向けであり、Google Play配布では本番用キーを安全に保管して継続利用する必要があります。

## iOS署名の制約

物理iPhoneへインストールできるIPAには、Apple Developer Teamが発行した証明書と、次の2つのBundle ID用プロビジョニングプロファイルが必要です。

- `io.github.StupidGame.azookeyFlutter`
- `io.github.StupidGame.azookeyFlutter.AzooKeyKeyboard`

両プロファイルにはApp Group `group.com.azooKey.keyboard`を含める必要があります。これらはApple側でのみ発行できるため、Secretsも外部資格情報も使わないワークフローでは署名済み実機IPAを作れません。`Keynako-unsigned.ipa`は、証明書を用意した環境で再署名するための成果物です。

## 成果物の取得

Actionsの完了後、実行詳細のArtifactsから次をダウンロードします。

- `keynako-android-signed-apk-<run number>`
- `keynako-ios-files-<run number>`

成果物は14日間保存されます。CI用keystoreはリポジトリや成果物には含めず、Actionsキャッシュだけに保存します。

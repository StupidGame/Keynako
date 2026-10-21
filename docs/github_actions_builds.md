# GitHub Actionsでアプリファイルを作る

`.github/workflows/build-app-files.yml` は、Actions画面の手動実行、または`v`で始まるタグのpushで次の成果物を作ります。`android/**`、署名ファイル、Android署名処理のブランチpushでも、固定リリース鍵でAndroidだけをビルドします。Pull RequestはAndroidの解析・テスト・未署名リリースのビルド検証を行い、Android APKは配布しません。他のOSの成果物はPull Requestでも作成します。Windows成果物はすべての実行でAuthenticode署名します。WindowsのPull Requestと手動実行では、Actionsのキャッシュに保持するCI用証明書を使います。

| ジョブ | 成果物 | 用途 |
| --- | --- | --- |
| Android | `app-release.apk`、`signature-report.txt` | 固定の暗号化リリース鍵による署名済みAPKと署名検証結果。Pull Requestでは配布しない |
| iOS | `Keynako-unsigned.ipa` | Appleの証明書で後から署名するための実機用アーカイブ |
| iOS | `Keynako-simulator.app.zip` | iOS Simulatorへ展開・インストールできるアプリ |
| Windows | `KeynakoSetup.exe` | Keynako製DLL／exeとインストーラーを常にAuthenticode署名。通常はCI用証明書、登録済み証明書がある`v`タグでは正式証明書を使用 |
| Linux | `Keynako-linux-x64.tar.gz` | Flutter設定アプリ、IBus engine、導入／削除スクリプト、Zenzai |
| macOS | `Keynako-macos.zip` | Flutter設定アプリ、InputMethodKit bundle、導入／削除スクリプト、Zenzai |

## Android署名の制約

### Android Studio相当のリリース鍵

Android Studioの `Build → Generate Signed Bundle/APK → APK → Create new` と同じkeystore作成項目を、Java 17の `keytool` で指定して作成しています。Android Studio本体や、Android側による鍵の認証手続きは必要ありません。

| 作成項目 | 設定 |
| --- | --- |
| Key store path | リポジトリ外の `android-release.jks` |
| Keystore形式 | JKS |
| Alias | `keynako-release` |
| Key / Keystore Password | 同じ強いランダムパスフレーズ |
| Validity | 30年相当（10,950日） |
| Certificate | `CN=StupidGame`（自己署名） |
| 鍵・証明書署名 | RSA 2048 bit / SHA256withRSA |

作成時の指定は次のコマンドと同等です。パスワードは対話入力し、鍵のパスワードを聞かれたらEnterでkeystoreと同じ値にします。既存の配布鍵は再作成せず、そのまま保管します。

```sh
keytool -genkeypair -storetype JKS -keystore /secure/path/android-release.jks \
  -alias keynako-release -keyalg RSA -keysize 2048 -sigalg SHA256withRSA \
  -validity 10950 -dname "CN=StupidGame"
```

Gitへ保存するのは `signing/android-release.jks.gpg`（GPG AES-256暗号化済み）、`signing/android-release.cer`（公開証明書）、`signing/android-release.json`（公開メタデータ）です。平文のkeystoreとパスフレーズはコミットしません。復号には次のRepository secretを登録します。

- `KEYNAKO_ANDROID_SIGNING_PASSPHRASE`: 作成時に保管したパスフレーズ。GPGの復号とJKSの鍵・keystoreパスワードに使用します。

手動実行、タグ、Androidコードや署名関連ファイルのブランチpushでは、このSecretを必須にしています。未登録・復号失敗の場合は停止し、CI用など別の鍵へフォールバックしません。対象ファイルのブランチpushではAndroidジョブだけを実行します。復号ファイルは `RUNNER_TEMP` 内だけに作り、ジョブ終了時に削除します。完成したAPKの署名は `apksigner` で検証し、コミットした公開証明書のSHA-256とも照合します。

Pull Requestには復号用Secretを渡さず、`:app:assembleRelease` で未署名リリースをビルドして検証するだけにします。APKのアップロードやCI用鍵の復元は行いません。署名スクリプトもPull Requestからの呼び出しを拒否します。PRのActions概要に、同じブランチの配布ビルドへのリンクを表示します。

配布するAndroid成果物は `keynako-android-release-apk-<run number>` に統一します。#200・#202・#203・#204は同じ固定リリース鍵で署名されています。一方、従来の `keynako-android-signed-apk-*` は古いCI鍵による別署名です。#205はこのPR用APKだったため、固定リリース鍵でインストールしたアプリには上書き更新できません。実行番号の大きさだけで選ばず、`release-apk` の配布用成果物を使ってください。

固定リリース鍵の証明書SHA-256は `8469cff24bf4411fa9f48d3521389f673ccf56caf7c80b1136124c97194b4af0` です。この鍵の導入前にCI鍵の版をインストールしている場合は、そのまま上書き更新できません。鍵を変更する移行の前に、アプリ内の設定・辞書・学習データをバックアップする必要があります。復号用パスフレーズも、GitHub Secrets以外に安全なバックアップを保管してください。GitHub Secretsへ登録した値は後から表示できません。

### 既存のCI鍵と従来のSecrets

Androidは同じパッケージ名でも署名鍵が異なるAPKへ上書き更新できません。Actions #191と#192はソースツリーが同一ですが、#192ではキャッシュが見つからず別の鍵が生成されていました。署名証明書のSHA-256はそれぞれ次の値です。

- #191: `89064217d88f24f8ede388a2ec74a248ca7359a44d41094f51eb5d125417c014`
- #192: `837d05948a4c504cf61196bcc613ac382f1b3ebdfc9b6980c1905412f2982cad`

鍵がないときに自動生成する処理は廃止しました。さらに、古い`.ci/keynako-ci-release.jks`がキャッシュに残っていても署名には使いません。リリース鍵の設定がない場合は停止し、別の署名のAPKを配布しません。ActionsキャッシュはブランチやPull Requestごとにアクセス範囲が異なり、削除もされるため、配布用の鍵の保管先には使えません。

署名スクリプトには従来のBase64形式の復元処理も残しています。ただし現在のワークフローは暗号化リリース鍵を必須にしています。元のkeystoreを復旧して従来方式へ移行する場合は、ワークフローの `KEYNAKO_REQUIRE_ENCRYPTED` を明示的に変更した上で、次のRepository secretsをすべて登録します。暗号化方式のSecretと同時には設定せず、どちらか一方を選びます。Google Playのアカウントは不要です。

- `KEYNAKO_ANDROID_KEYSTORE_BASE64`: 元のkeystoreファイル全体をBase64にした文字列
- `KEYNAKO_ANDROID_STORE_PASSWORD`: keystoreのパスワード
- `KEYNAKO_ANDROID_KEY_ALIAS`: 署名鍵のalias
- `KEYNAKO_ANDROID_KEY_PASSWORD`: 署名鍵のパスワード

従来方式では、すべてのSecretsが設定されていればこの鍵を使います。一部だけ設定されていたり、Base64が不正だったりする場合はキャッシュへフォールバックせず停止します。秘密鍵はPull Requestへ渡さず、キャッシュや成果物にも保存しません。Secretsから復元したファイルはジョブの最後に削除します。

新しい鍵を作っても、すでに配布したAPKへの更新互換性は戻りません。APKに入っている公開証明書から元の秘密鍵を復元することもできません。署名が異なる場合は、アンインストールする前に元の鍵の復旧とアプリ内データの保存を確認してください。#191を利用中なら、同じソースの#192へ入れ替える必要はありません。

Playプロテクトのスキャン確認は署名検証とは別です。有効な固定署名があってもGoogle側の判定で表示されることがあり、この変更で非表示になる保証はありません。[Googleの説明](https://developers.google.com/android/play-protect/warning-dev-guidance?hl=ja)と[Androidの署名の説明](https://developer.android.com/studio/publish/app-signing)、[Actionsキャッシュのアクセス制約](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching#restrictions-for-accessing-a-cache)も参照してください。

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

- `keynako-android-release-apk-<run number>`（固定リリース鍵による署名。Pull Requestでは配布しない）
- `keynako-ios-files-<run number>`
- `keynako-windows-installer-ci-signed-<run number>`（通常実行、正式証明書未登録時）
- `keynako-windows-installer-trusted-signed-<run number>`（正式証明書を使った`v`タグ）
- `keynako-linux-x64-<run number>`
- `keynako-macos-<run number>`

成果物は14日間保存されます。Androidのリリース鍵は暗号化してGitに保存し、復号用パスフレーズだけをSecretsで管理します。AndroidのCI用keystoreとWindowsのCI用PFXはリポジトリや成果物には含めず、Actionsキャッシュだけに保存します。AndroidのPull RequestはCI用キャッシュが消えると停止します。リリース鍵はキャッシュに依存しません。WindowsのCI用証明書はキャッシュが消えると再作成されます。

PC版ジョブは共有変換モジュール、C++入力セッション、Flutter設定アプリを検査します。WindowsではTSF DLLとInno Setup製インストーラー、macOSではInputMethodKit bundle、LinuxではIBus engineも各OS向けに検証・梱包します。`keynako_zenzai`とsmall／xsmallモデルを同梱するため、追加モデル取得は不要です。

リポジトリ変数`KEYNAKO_DICTIONARY_SUBMISSION_URL`へHTTPSゲートウェイを設定すると、Android/iOSアプリとWindows TSF IMEの改善送信先へ同じURLを組み込みます。変数が空のWindowsビルドでは送信確認を表示しません。

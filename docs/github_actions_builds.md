# GitHub Actionsでアプリファイルを作る

`.github/workflows/build-app-files.yml` は、Pull Request、Actions画面の手動実行、または`v`で始まるタグのpushで次の成果物を作ります。Windows成果物はすべての実行でAuthenticode署名します。WindowsのPull Requestと手動実行では、Actionsのキャッシュに保持するCI用証明書を使います。Androidの固定鍵は以下のSecretsで設定できます。

| ジョブ | 成果物 | 用途 |
| --- | --- | --- |
| Android | `app-release.apk`、`signature-report.txt` | 固定鍵のSecretsまたは既存のCI用keystoreによる署名済みAPKと署名検証結果 |
| iOS | `Keynako-unsigned.ipa` | Appleの証明書で後から署名するための実機用アーカイブ |
| iOS | `Keynako-simulator.app.zip` | iOS Simulatorへ展開・インストールできるアプリ |
| Windows | `KeynakoSetup.exe` | Keynako製DLL／exeとインストーラーを常にAuthenticode署名。通常はCI用証明書、登録済み証明書がある`v`タグでは正式証明書を使用 |
| Linux | `Keynako-linux-x64.tar.gz` | Flutter設定アプリ、IBus engine、導入／削除スクリプト、Zenzai |
| macOS | `Keynako-macos.zip` | Flutter設定アプリ、InputMethodKit bundle、導入／削除スクリプト、Zenzai |

## Android署名の制約

Androidは同じパッケージ名でも署名鍵が異なるAPKへ上書き更新できません。Actions #191と#192はソースツリーが同一ですが、#192ではキャッシュが見つからず別の鍵が生成されていました。署名証明書のSHA-256はそれぞれ次の値です。

- #191: `89064217d88f24f8ede388a2ec74a248ca7359a44d41094f51eb5d125417c014`
- #192: `837d05948a4c504cf61196bcc613ac382f1b3ebdfc9b6980c1905412f2982cad`

鍵がないときに自動生成する処理は廃止しました。Secretsが未設定の場合は、既存の`.ci/keynako-ci-release.jks`をキャッシュから読み込むだけです。キャッシュが消えた場合はAndroidジョブをエラーで止め、別の署名のAPKを配布しません。ActionsキャッシュはブランチやPull Requestごとにアクセス範囲が異なり、削除もされるため、配布用の鍵の保管先には使えません。

継続して配布する場合は、使用中のAPKを署名した元のkeystoreを安全にバックアップし、次のRepository secretsをすべて登録します。Google Playのアカウントは不要です。

- `KEYNAKO_ANDROID_KEYSTORE_BASE64`: 元のkeystoreファイル全体をBase64にした文字列
- `KEYNAKO_ANDROID_STORE_PASSWORD`: keystoreのパスワード
- `KEYNAKO_ANDROID_KEY_ALIAS`: 署名鍵のalias
- `KEYNAKO_ANDROID_KEY_PASSWORD`: 署名鍵のパスワード

手動実行と`v`タグでは、すべてのSecretsが設定されていればこの鍵を優先します。一部だけ設定されていたり、Base64が不正だったりする場合はキャッシュへフォールバックせず停止します。秘密鍵はPull Requestへ渡さず、キャッシュや成果物にも保存しません。Secretsから復元したファイルはジョブの最後に削除します。

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

- `keynako-android-signed-apk-<run number>`
- `keynako-ios-files-<run number>`
- `keynako-windows-installer-ci-signed-<run number>`（通常実行、正式証明書未登録時）
- `keynako-windows-installer-trusted-signed-<run number>`（正式証明書を使った`v`タグ）
- `keynako-linux-x64-<run number>`
- `keynako-macos-<run number>`

成果物は14日間保存されます。AndroidのCI用keystoreとWindowsのCI用PFXはリポジトリや成果物には含めず、Actionsキャッシュだけに保存します。Androidはキャッシュが消えると固定鍵のSecretsが必要になり、自動で署名者を変えません。WindowsのCI用証明書はキャッシュが消えると再作成されます。

PC版ジョブは共有変換モジュール、C++入力セッション、Flutter設定アプリを検査します。WindowsではTSF DLLとInno Setup製インストーラー、macOSではInputMethodKit bundle、LinuxではIBus engineも各OS向けに検証・梱包します。`keynako_zenzai`とsmall／xsmallモデルを同梱するため、追加モデル取得は不要です。

リポジトリ変数`KEYNAKO_DICTIONARY_SUBMISSION_URL`へHTTPSゲートウェイを設定すると、Android/iOSアプリとWindows TSF IMEの改善送信先へ同じURLを組み込みます。変数が空のWindowsビルドでは送信確認を表示しません。

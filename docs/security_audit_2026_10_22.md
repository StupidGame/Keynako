# セキュリティ・安定性の確認（2026-10-22）

対象は `c20d0959c69d5f26168ad05d81eaa678069c1ada` を基点とした、Android IME、モバイルのバックアップ・背景画像、報告送信、JNI とデスクトップ補助プロセスの境界。この文書は確認範囲と修正の記録であり、製品全体の安全性を保証するものではない。

## 修正した問題

| 問題 | 修正前の影響・条件 | 対応と回帰テスト |
| --- | --- | --- |
| 入力先の学習禁止指定と数字パスワードの扱い | Android の `IME_FLAG_NO_PERSONALIZED_LEARNING` を無視して学習が保存される。数字パスワードも機密扱いにならず、配列や言語を切り替えると変換・候補表示に進む。文字パスワードでも日本語・カスタム入力経路に保護の抜けがある。 | エディター開始時に機密性を更新し、プライベート入力では個人履歴の読み書きと報告提案を停止。パスワードでは各入力経路を直接入力にし、句読点変換・括弧の自動補完も停止。`InputPrivacyTest` と `InputTypeKeyboardPolicyTest`。 |
| バックアップによる任意ファイル参照 | 攻撃者が作成したバックアップを利用者が読み込み、その後書き出すと、背景画像のパスで指定したアプリから読めるファイルが添付される可能性がある。OS の権限を越える読み取りや自動送信ではない。 | 読み込みでは生のパスを採用せず、埋め込まれた画像のみ復元。書き出しとキーボードの画像読み込みは、シンボリックリンク解決後も専用画像ディレクトリ内にある `.image` ファイルに限定。Flutter の不正パス回帰テストと Android のディレクトリ脱出・シンボリックリンクの回帰テスト。 |
| 画像のメモリ使用量が無制限 | 圧縮ファイルが 8 MB 以下でも、全画素展開するとキーボードのメモリを使い切る可能性がある。設定が残るため再度開いても同じ画像を読み込む。 | Android はメタデータで検証後にサンプリング、iOS は Image I/O のサムネイル生成で最大辺 2048 px に縮小。EXIF の向きを維持。元画像の上限は 2.5 億画素として 200 MP の写真にも対応。Android の実画像縮小・EXIF 回転・寸法オーバーフローの回帰テスト。 |
| 復元失敗時に使用中の画像が上書きされる | 複数の画像を含むバックアップで、先の画像を保存した後に後続画像が不正だと、設定の復元に失敗しても現在の背景ファイルだけが変わる。 | 復元画像は新しい名前で保存し、検証中の失敗ではその画像を削除。現在の画像を上書きしない。Flutter の途中失敗・既存ファイル保持・一時ファイル削除の回帰テスト。 |
| Android 7〜12L の報告送信の互換性 | 最小 API は 24 だが、応答処理で API 33 追加の `InputStream.readNBytes(int)` を使用。古い OS で処理が中断し、送信完了が返らない可能性がある。 | 古い API でも利用できる読み取りで応答を 64 KiB に制限。上限超過時も最後まで読み込まない。`BoundedInputTest` と API 28 の `ReportResponseCompatibilityTest`。 |
| Zenzai のモデル展開失敗から復旧できない | 既存ディレクトリに対する `mkdirs()` の戻り値を失敗と扱うため、展開が途中で止まった後にモデルを再配置できない。 | 既存のディレクトリを許可し、一時ファイルへのコピーとサイズ確認が完了してから置き換える。中断・途中までのデータ・再試行・既存モデル再利用を `ZenzaiModelFileTest` で検証。 |

パスだけを含む古いバックアップからは背景画像を引き継がない。画像データを埋め込んだ現在のバックアップ形式には対応する。

## 検証と確認範囲

- ローカルの JVM 回帰テスト: 139 件成功（変換・入力方針・上限付き読み取り・モデルの復旧）。
- 署名準備の Python テスト: 18 件成功。既存の署名鍵・証明書・暗号化ファイルは変更しない。
- Linux 補助プロセスの Python テスト: 7 件成功。
- Flutter のバックアップ回帰テスト、Robolectric の入力・画像・API 28 の回帰テスト、および Android/iOS のコンパイルは、この変更を対象に GitHub Actions で検証する。
- Android Lint を Actions の検証に追加し、最小 API で利用できない API の混入も検出する。
- 3 つの `pubspec.lock` の hosted パッケージ計 81 組（名前・バージョンの重複を除く）を OSV API で照合し、照合時点の登録済み脆弱性は 0 件。SDK・ネイティブ依存・未登録の問題を含めて安全と判断する検査ではない。
- Android IME は `BIND_INPUT_METHOD` で保護されている。報告ペイロードは周辺文脈や生のローマ字入力を送らず、共有辞書のリダイレクト先も制限されている。デスクトップ補助プロセスはシェルを介さず引数を渡している。今回確認した範囲で、これらの境界に新たな修正対象は見つからなかった。
- llama.cpp の上流には GGUF パーサーなどのセキュリティ報告がある。Android でのモデル供給は同梱アセットからアプリ専用領域への展開で、外部モデルを受信する経路やサーバーは提供していない。固定したフォーク全体の脆弱性監査や、任意の外部 GGUF の安全性検証は今回の検査に含まない。
- 実端末の長時間動作・OS ごとのメモリ使用量の測定は未実施。

## 仕様・照合元

- [Android: IME_FLAG_NO_PERSONALIZED_LEARNING](https://developer.android.com/reference/android/view/inputmethod/EditorInfo#IME_FLAG_NO_PERSONALIZED_LEARNING)
- [Android: TYPE_NUMBER_VARIATION_PASSWORD](https://developer.android.com/reference/android/text/InputType#TYPE_NUMBER_VARIATION_PASSWORD)
- [Android: InputStream.readNBytes(int)](https://developer.android.com/reference/java/io/InputStream#readNBytes(int))
- [Apple: Image and Graphics Best Practices（Image I/O による縮小）](https://devstreaming-cdn.apple.com/videos/wwdc/2018/219mybpx95zm9x/219/219_image_and_graphics_best_practices.pdf)
- [OSV: batch query API](https://google.github.io/osv.dev/post-v1-querybatch/)
- [llama.cpp: 上流のセキュリティ報告](https://github.com/ggml-org/llama.cpp/security/advisories/)

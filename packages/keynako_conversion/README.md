# keynako_conversion

Keynakoの入力・変換責務をUIと永続化から分離した、リポジトリ内の共通モジュールです。

- ローマ字からひらがな、カタカナ、半角カナへの変換
- 日本語候補、利用者辞書、テンプレート、学習スコア
- 英語直接入力と英単語の前方予測
- Unicode、全角英数字、絵文字、顔文字候補
- Keynako共有辞書の取得、検証、三OS共通キャッシュ形式
- Zenzai v3.2用の常駐プロセス境界とCPU推論実行ファイル
- PCシステムIMEが共有するC++入力セッションとLinux用C ABI

Flutterの画面状態やKeynako本体の`AppData`には依存しません。携帯アプリ側は
`lib/input/japanese_converter.dart`で保存設定をこのモジュールの入力へ変換し、PCアプリ側は
`DesktopInputController`から直接利用します。

## テスト

```sh
dart pub get
dart analyze
dart test
```

## Zenzai実行ファイル

`native`は既存の`llama.cpp`サブモジュールを使い、PC向けの`keynako_zenzai`を作ります。
同時に`keynako_ime_core`、`keynako_ime_bridge`とネイティブ状態遷移テストも作ります。

```sh
cmake -S native -B ../../build/zenzai -DCMAKE_BUILD_TYPE=Release
cmake --build ../../build/zenzai --config Release --parallel 2
```

標準入出力の内部プロトコルは16進化したUTF-8を使います。モデルは起動時に一度だけ読み込み、
各入力要求ではZenzai v3.2の文脈タグを付けたプロンプトだけを送ります。

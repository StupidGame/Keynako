# Third-party notices

Keynako includes or builds upon the following third-party works. Each work remains subject to its own license.

## azooKey

- Source: https://github.com/azooKey/azooKey
- Copyright (c) 2020-2023 Keita Miwa (ensan)
- License: MIT (see `third_party/licenses/azooKey-MIT.txt`)

The Flutter application and keyboard behavior are a clean migration and adaptation of the original Swift application.

## AzooKeyKanaKanjiConverter

- Source: https://github.com/azooKey/AzooKeyKanaKanjiConverter
- Pinned revision: `93766c46e31fa6a18b7ced49dab31337780f6f45`
- Copyright (c) 2023 Miwa / Ensan
- License: MIT (see `third_party/licenses/AzooKeyKanaKanjiConverter-MIT.txt`)

This dependency is resolved by the local iOS Swift package with the `ZenzaiCPU` trait.

## llama.cpp / ggml

- Source: https://github.com/azooKey/llama.cpp
- Pinned submodule revision: `88b97a47dc7f5892e2d5a6856fbe9cfe237f9e5c`
- Copyright (c) 2023-2024 The ggml authors
- License: MIT (see `android/app/src/main/cpp/llama.cpp/LICENSE`)

## JapaneseKeyboard Zenz JNI bridge

- Source: https://github.com/KazumaProject/JapaneseKeyboard
- Source revision: `94ec4fec9582392a25b7678415a986ca90a0ebe9`
- Copyright (c) 2024 Kazuma Naka
- License: MIT (see `third_party/licenses/JapaneseKeyboard-MIT.txt`)

`android/app/src/main/cpp/zenz_bridge.cpp` is adapted for Keynako's package, runtime lifecycle, and candidate validation.

## Zenzai v3.2 models

- Sources: https://huggingface.co/Miwa-Keita/zenz-v3.2-small-gguf and https://huggingface.co/Miwa-Keita/zenz-v3.2-xsmall-gguf
- License declared by the model repositories: Apache License 2.0

The bundled files, sizes, and SHA-256 digests are documented in `assets/ZENZAI_MODELS.md`.

## Flutter and Dart packages

Flutter, Dart, Cupertino Icons, and transitive SDK components retain the license notices distributed with their respective SDKs and packages.

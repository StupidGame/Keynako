// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AzooKeyConverterBridge",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "AzooKeyConverterBridge", targets: ["AzooKeyConverterBridge"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.20"),
        .package(
            url: "https://github.com/azooKey/AzooKeyKanaKanjiConverter",
            revision: "93766c46e31fa6a18b7ced49dab31337780f6f45",
            traits: ["ZenzaiCPU"]
        ),
    ],
    targets: [
        .target(
            name: "AzooKeyConverterBridge",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(
                    name: "KanaKanjiConverterModuleWithDefaultDictionary",
                    package: "AzooKeyKanaKanjiConverter"
                ),
            ],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
                .interoperabilityMode(.Cxx),
            ]
        ),
    ]
)

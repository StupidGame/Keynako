// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AzooKeyConverterBridge",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "AzooKeyConverterBridge", targets: ["AzooKeyConverterBridge"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/azooKey/AzooKeyKanaKanjiConverter",
            revision: "8e3a6eb89e088efd868aa28dadb74c697df4e6fb",
            traits: ["ZenzaiCPU"]
        ),
    ],
    targets: [
        .target(
            name: "AzooKeyConverterBridge",
            dependencies: [
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

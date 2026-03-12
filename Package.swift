// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "SpeedScan",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "SpeedScan", targets: ["SpeedScan"])
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0")
    ],
    targets: [
        .target(
            name: "SpeedScan",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            path: ".",
            exclude: ["Info.plist", "Resources", "Package.swift", "project.yml", "setup-xcode.sh", "README.md", "prototype"],
            sources: ["Views", "ViewModels", "Components", "Services", "Models", "SpeedScanApp.swift"]
        )
    ]
)

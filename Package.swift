// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "SpeedScan",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "SpeedScan", targets: ["SpeedScan"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SpeedScan",
            path: ".",
            exclude: ["Info.plist", "Resources", "Package.swift", "project.yml", "setup-xcode.sh", "README.md"],
            sources:["Views", "ViewModels", "Components", "SpeedScanApp.swift"]
        )
    ]
)

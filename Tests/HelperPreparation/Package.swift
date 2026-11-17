// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "HelperPreparation", platforms: [.macOS(.v13)], dependencies: [.package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")], targets: [
    .target(name: "HelperPreparation", dependencies: ["ZIPFoundation"]),
    .testTarget(name: "HelperPreparationTests", dependencies: ["HelperPreparation", "ZIPFoundation"])
])

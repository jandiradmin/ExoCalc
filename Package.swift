// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ExoCalc",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ExoCalc", targets: ["ExoCalc"]),
        .executable(name: "exocalc-cli", targets: ["exocalc-cli"]),
    ],
    targets: [
        .target(name: "ExoCalcCore"),
        .executableTarget(name: "ExoCalc", dependencies: ["ExoCalcCore"]),
        .executableTarget(name: "exocalc-cli", dependencies: ["ExoCalcCore"]),
    ]
)

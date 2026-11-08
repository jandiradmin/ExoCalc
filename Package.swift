// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ExoCalc",
    platforms: [.macOS(.v12), .iOS(.v16)],
    products: [
        .executable(name: "ExoCalc", targets: ["ExoCalc"]),
        .executable(name: "exocalc-cli", targets: ["exocalc-cli"]),
        .library(name: "ExoCalcCore", targets: ["ExoCalcCore"]),
    ],
    targets: [
        .target(name: "ExoCalcCore"),
        .executableTarget(name: "ExoCalc", dependencies: ["ExoCalcCore"]),
        .executableTarget(name: "exocalc-cli", dependencies: ["ExoCalcCore"]),
    ]
)

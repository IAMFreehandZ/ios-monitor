// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MonitorCore",
    platforms: [.macOS(.v12), .iOS(.v17)],
    products: [.library(name: "MonitorCore", targets: ["MonitorCore"])],
    targets: [
        .target(name: "MonitorCore"),
        .testTarget(name: "MonitorCoreTests", dependencies: ["MonitorCore"])
    ]
)

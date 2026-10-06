// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LocalPorts",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "LocalPorts", targets: ["LocalPorts"])],
    targets: [
        .target(name: "PortInspector", publicHeadersPath: "include"),
        .target(name: "LocalPortsCore", dependencies: ["PortInspector"]),
        .executableTarget(name: "LocalPorts", dependencies: ["LocalPortsCore"], resources: [.copy("Assets")]),
        .testTarget(name: "LocalPortsCoreTests", dependencies: ["LocalPortsCore"]),
        .testTarget(name: "LocalPortsAppTests", dependencies: ["LocalPorts"])
    ]
)

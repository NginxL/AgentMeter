// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AgentMeter",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AgentMeter", targets: ["AgentMeter"])],
    targets: [
        .target(name: "MeterCore"),
        .target(name: "MeterProviders", dependencies: ["MeterCore"]),
        .executableTarget(name: "AgentMeter", dependencies: ["MeterCore", "MeterProviders"]),
        .executableTarget(name: "MeterChecks", dependencies: ["MeterCore"], path: "Tests/MeterChecks"),
        .executableTarget(name: "MeterProviderChecks", dependencies: ["MeterCore", "MeterProviders"], path: "Tests/ProviderChecks")
    ]
)

// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "HarborFTP", platforms: [.macOS(.v13)], products: [.executable(name: "HarborFTP", targets: ["HarborFTP"])], targets: [.executableTarget(name: "HarborFTP", path: "Sources")])

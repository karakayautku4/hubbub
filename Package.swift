// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "Hubbub",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "Hubbub", path: "Sources/Hubbub")]
)

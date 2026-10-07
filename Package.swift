// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Pinwire",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Pinwire", path: "Sources/Pinwire")
    ]
)

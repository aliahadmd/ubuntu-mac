// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TryUbuntuVMHelper",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "tryubuntu-vm-helper", targets: ["TryUbuntuVMHelper"]),
    ],
    targets: [
        .executableTarget(name: "TryUbuntuVMHelper"),
        .testTarget(name: "TryUbuntuVMHelperTests", dependencies: ["TryUbuntuVMHelper"]),
    ],
    swiftLanguageModes: [.v5]
)

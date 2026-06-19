// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AppSwipe",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AppSwipe", targets: ["AppSwipe"]),
    ],
    targets: [
        .target(
            name: "AppSwipeCore"
        ),
        .executableTarget(
            name: "AppSwipe",
            dependencies: ["AppSwipeCore"]
        ),
        .testTarget(
            name: "AppSwipeCoreTests",
            dependencies: ["AppSwipeCore"]
        ),
    ]
)

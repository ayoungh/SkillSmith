// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SkillSmith",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SkillSmith", targets: ["SkillSmithApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2"),
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0")
    ],
    targets: [
        .executableTarget(
            name: "SkillSmithApp",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
                .product(name: "TOMLKit", package: "TOMLKit")
            ],
            path: ".",
            exclude: [
                ".build",
                ".codex",
                ".git",
                "Assets",
                "dist",
                "script",
                "Tests",
                "README.md",
                "LICENSE",
                ".gitignore"
            ],
            sources: [
                "App",
                "Models",
                "Services",
                "Stores",
                "Support",
                "Views"
            ]
        ),
        .testTarget(
            name: "SkillSmithTests",
            dependencies: ["SkillSmithApp"],
            path: "Tests/SkillSmithTests"
        )
    ]
)

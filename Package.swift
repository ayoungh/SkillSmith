// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SkillSmith",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SkillSmithApp", targets: ["SkillSmithApp"])
    ],
    targets: [
        .executableTarget(
            name: "SkillSmithApp",
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

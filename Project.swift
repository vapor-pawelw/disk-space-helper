import ProjectDescription

let project = Project(
    name: "DiskSpaceHelper",
    targets: [
        .target(
            name: "DiskSpaceHelper",
            destinations: [.mac],
            product: .app,
            bundleId: "com.pawelw.DiskSpaceHelper",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .extendingDefault(with: [
                "LSUIElement": .boolean(true),
            ]),
            sources: ["Sources/**"],
            resources: ["Resources/**"]
        ),
    ]
)

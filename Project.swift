import ProjectDescription

let project = Project(
    name: "DiskSpaceHelper",
    targets: [
        .target(
            name: "DiskSpaceHelper",
            destinations: [.mac],
            product: .app,
            bundleId: "com.vaporpw.DiskSpaceHelper",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .extendingDefault(with: [
                "LSUIElement": .boolean(true),
            ]),
            sources: ["Sources/**"],
            resources: ["Resources/**"],
            settings: .settings(base: [
                "STRING_CATALOG_GENERATE_SYMBOLS": "YES",
                "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
                "SWIFT_EMIT_LOC_STRINGS": "YES",
            ])
        ),
        .target(
            name: "DiskSpaceHelperTests",
            destinations: [.mac],
            product: .unitTests,
            bundleId: "com.vaporpw.DiskSpaceHelperTests",
            deploymentTargets: .macOS("14.0"),
            sources: ["Tests/**"],
            dependencies: [
                .target(name: "DiskSpaceHelper"),
            ]
        ),
    ]
)

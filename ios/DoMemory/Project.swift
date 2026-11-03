import ProjectDescription

let currentProjectVersion = Environment.CURRENT_PROJECT_VERSION.getString(default: "1")

let appTarget = Target.target(
    name: "DoMemory",
    destinations: [.iPhone, .iPad],
    product: .app,
    bundleId: "com.ezequielbrrt.domemory",
    deploymentTargets: .iOS("18.6"),
    infoPlist: .file(path: "DoMemory/Info.plist"),
    sources: [
        "DoMemory/**/*.swift",
    ],
    resources: [
        "DoMemory/**/*.strings",
        "DoMemory/GoogleService-Info.plist",
        "DoMemory/SupportingFiles/Assets.xcassets",
        "DoMemory/SupportingFiles/Fonts/*.ttf",
        "DoMemory/SupportingFiles/Lottie/*.json",
        "../../localization/leaderboard-names.json",
        "DoMemory/Preview Content/Preview Assets.xcassets",
    ],
    entitlements: .file(path: "DoMemory/DoMemory.entitlements"),
    dependencies: [
        .external(name: "FirebaseAnalytics"),
        .external(name: "FirebaseAnalyticsCore"),
        .external(name: "FirebaseAuth"),
        .external(name: "FirebaseCore"),
        .external(name: "FirebaseCrashlytics"),
        .external(name: "FirebaseDatabase"),
        .external(name: "FirebaseMessaging"),
        .external(name: "GoogleMobileAds"),
        .external(name: "Lottie"),
        .external(name: "NotificationPermissionKit"),
        .external(name: "ReviewFlow"),
        .external(name: "WaterfallGrid"),
        .external(name: "WhatsNewKit"),
    ],
    settings: .settings(
        base: [
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
            "CODE_SIGN_STYLE": "Automatic",
            "CURRENT_PROJECT_VERSION": "\(currentProjectVersion)",
            "DEVELOPMENT_ASSET_PATHS": "\"DoMemory/Preview Content\"",
            "DEVELOPMENT_TEAM": "H5V33368QJ",
            "ENABLE_PREVIEWS": "YES",
            "MARKETING_VERSION": "4.5.1",
            "OTHER_LDFLAGS": [
                "$(inherited)",
                "-ObjC",
            ],
            "PRODUCT_BUNDLE_IDENTIFIER": "com.ezequielbrrt.domemory",
            "SWIFT_VERSION": "5.0",
            "TARGETED_DEVICE_FAMILY": "1,2",
        ],
        release: [
            "ONLY_ACTIVE_ARCH": "YES",
        ],
        defaultSettings: .recommended
    ),
    coreDataModels: [
        .coreDataModel("DoMemory/Modules/SharedModules/Models/DoMemory.xcdatamodeld"),
    ]
)

let testsTarget = Target.target(
    name: "DoMemoryTests",
    destinations: [.iPhone, .iPad],
    product: .unitTests,
    bundleId: "com.ezequielbrrt.DoMemoryTests",
    deploymentTargets: .iOS("18.6"),
    infoPlist: .file(path: "DoMemoryTests/Info.plist"),
    sources: [
        "DoMemoryTests/**/*.swift",
    ],
    dependencies: [
        .target(name: "DoMemory"),
    ],
    settings: .settings(
        base: [
            "CODE_SIGN_STYLE": "Automatic",
            "SWIFT_VERSION": "5.0",
            "TARGETED_DEVICE_FAMILY": "1,2",
        ],
        defaultSettings: .recommended
    )
)

let project = Project(
    name: "DoMemory",
    organizationName: "DoMemory",
    options: .options(
        automaticSchemesOptions: .disabled,
        defaultKnownRegions: [
            "en",
            "Base",
            "es-419",
            "pt-BR",
            "de",
            "it",
            "zh-Hans",
            "ja",
            "ko",
            "hi",
            "fr",
        ],
        developmentRegion: "en",
        xcodeProjectName: "DoMemory"
    ),
    settings: .settings(
        base: [
            "IPHONEOS_DEPLOYMENT_TARGET": "15.0",
            "SDKROOT": "iphoneos",
        ],
        debug: [
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
        ],
        release: [
            "SWIFT_COMPILATION_MODE": "wholemodule",
            "VALIDATE_PRODUCT": "YES",
        ],
        defaultSettings: .recommended
    ),
    targets: [
        appTarget,
        testsTarget,
    ],
    schemes: [
        .scheme(
        name: "DoMemory",
        shared: true,
        buildAction: .buildAction(
            targets: ["DoMemory"]
        ),
            testAction: .targets(
                [
                    .testableTarget(target: "DoMemoryTests"),
                ],
                configuration: .debug,
                expandVariableFromTarget: "DoMemory"
            ),
            runAction: .runAction(
                configuration: .debug,
                executable: .executable("DoMemory"),
                options: .options(storeKitConfigurationPath: "DoMemory.storekit")
            ),
            archiveAction: .archiveAction(configuration: .release),
            profileAction: .profileAction(
                configuration: .release,
                executable: .executable("DoMemory")
            ),
            analyzeAction: .analyzeAction(configuration: .debug)
        ),
    ]
)

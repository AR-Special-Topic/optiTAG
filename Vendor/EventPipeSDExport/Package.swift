// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EventPipeSDExport",
    platforms: [.iOS(.v16)],
    products: [.library(name: "EventPipeSDExport", targets: ["EventPipeSDExport"])],
    targets: [
        .target(name: "EventPipeSDExport", path: ".", exclude: ["README.md", "Tests"],
                sources: ["BLEProtocol.swift", "SDExportBLELink.swift", "SDExportClient.swift", "EventDataTypes.swift", "SDExportProgressView.swift"]),
        .testTarget(name: "EventPipeSDExportTests", dependencies: ["EventPipeSDExport"], path: "Tests")
    ],
    swiftLanguageVersions: [.v5]
)

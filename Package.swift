// swift-tools-version:5.9
//
// LOKI – lokale KI-Arbeitsumgebung für macOS.
//
// Dieses Swift-Paket enthält den modellunabhängigen Kern (LokiCore): Modellkatalog, Aufgabenerkennung,
// AUTO-Router und Context Engine. Er hat keine Abhängigkeiten und ist mit `swift test` prüfbar.
// Die App selbst (Oberfläche, MLX-Inferenz, Downloads) entsteht aus project.yml mit XcodeGen,
// weil MLX seine Metal-Shader nur über xcodebuild übersetzen kann.
import PackageDescription

let package = Package(
    name: "LokiKern",
    defaultLocalization: "de",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LokiCore", targets: ["LokiCore"])
    ],
    targets: [
        .target(name: "LokiCore", path: "Sources/LokiCore"),
        .testTarget(name: "LokiCoreTests", dependencies: ["LokiCore"], path: "Tests/LokiCoreTests"),
    ]
)

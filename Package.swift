// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PDFChat",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PDFChat",
            path: "Sources/PDFChat"
        )
    ]
)
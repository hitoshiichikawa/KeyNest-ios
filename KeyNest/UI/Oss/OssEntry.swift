import Foundation

/// One row in the OSS license list. iOS port of Android `OssEntry`.
struct OssEntry: Identifiable {
    let id = UUID()
    let name: String
    let license: String
    let url: URL?
    let summary: String
}

enum OssLicenses {
    /// The bundled third-party dependencies KeyNest ships with on iOS. Keep
    /// this list in sync with the SPM / vendored asset graph; license parity
    /// is Req 8.2 (fonts) + Req 7.3 (OSS section).
    static let entries: [OssEntry] = [
        OssEntry(
            name: "Manrope",
            license: "SIL Open Font License 1.1",
            url: URL(string: "https://github.com/sharanda/manrope"),
            summary: """
            Manrope is a free typeface designed by Mikhail Sharanda.
            Distributed under the SIL Open Font License, Version 1.1.
            Bundled in this app as the primary UI typeface.
            """
        ),
        OssEntry(
            name: "JetBrains Mono",
            license: "SIL Open Font License 1.1",
            url: URL(string: "https://github.com/JetBrains/JetBrainsMono"),
            summary: """
            JetBrains Mono is a typeface made by JetBrains s.r.o.
            Distributed under the SIL Open Font License, Version 1.1.
            Bundled in this app as the monospace typeface for ciphertext / hash display.
            """
        ),
        OssEntry(
            name: "GRDB.swift",
            license: "MIT License",
            url: URL(string: "https://github.com/groue/GRDB.swift"),
            summary: """
            GRDB.swift is a toolkit for SQLite databases authored by Gwendal Roué.
            Copyright © Gwendal Roué.
            Distributed under the MIT License — see the project repository for the full license text.
            """
        ),
    ]
}

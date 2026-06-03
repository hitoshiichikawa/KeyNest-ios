import Foundation

/// Measures the on-disk byte size of the vault. Abstracted so the use case is
/// unit-testable without touching the real App Group container.
public protocol VaultStorageMeasuring {
    /// Total bytes occupied by the vault database files. Missing files count as 0.
    func measureBytes() async -> Int64
}

/// `FileManager`-based [VaultStorageMeasuring]. Port of KeyNest Android's
/// `VaultStorageMeasurer`, summing the SQLite database file plus its WAL / SHM
/// sidecars (which hold uncheckpointed pages) so the figure reflects real usage.
///
/// The raw byte count is returned; human-readable formatting (e.g. "123 kB") is
/// the UI layer's job, keeping the domain free of locale formatting.
public struct VaultStorageMeasurer: VaultStorageMeasuring {
    private let databaseURL: () -> URL?
    private let fileManager: FileManager

    /// - Parameters:
    ///   - databaseURL: locates the main DB file (default: the App Group vault).
    ///   - fileManager: injectable for tests.
    public init(
        databaseURL: @escaping () -> URL? = { AppGroup.databaseURL() },
        fileManager: FileManager = .default
    ) {
        self.databaseURL = databaseURL
        self.fileManager = fileManager
    }

    public func measureBytes() async -> Int64 {
        guard let base = databaseURL() else { return 0 }
        // SQLite in WAL mode keeps `<db>-wal` and `<db>-shm` sidecars (hyphen
        // suffix, NOT a path extension) next to the DB.
        let basePath = base.path
        let candidates = [
            base,
            URL(fileURLWithPath: basePath + "-wal"),
            URL(fileURLWithPath: basePath + "-shm"),
        ]
        return candidates.reduce(into: Int64(0)) { total, url in
            total += fileSize(at: url)
        }
    }

    private func fileSize(at url: URL) -> Int64 {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return 0
        }
        return size.int64Value
    }
}

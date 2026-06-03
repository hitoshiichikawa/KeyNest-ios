import Foundation

/// Returns the total on-disk byte size occupied by the vault. Port of KeyNest
/// Android's `GetVaultStorageUsageUseCase`; delegates to [VaultStorageMeasuring].
/// Human-readable formatting is left to the UI layer.
public struct GetVaultStorageUsageUseCase {
    private let measurer: VaultStorageMeasuring

    public init(measurer: VaultStorageMeasuring) {
        self.measurer = measurer
    }

    public func callAsFunction() async -> Int64 {
        await measurer.measureBytes()
    }
}

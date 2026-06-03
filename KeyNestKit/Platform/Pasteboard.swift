import Foundation
import UIKit

/// Abstraction over the system clipboard so consumers (`copy password` /
/// `copy custom field`) can be unit-tested without touching the real
/// `UIPasteboard`. iOS-only — extension target uses the same default.
public protocol Pasteboarding: Sendable {
    /// Copies `string` onto the clipboard. When `autoClearAfter` is non-nil,
    /// schedules a clear after that many seconds (best-effort: a later
    /// non-KeyNest write supersedes the deadline). Pass nil to disable
    /// auto-clear (non-sensitive values).
    func setString(_ string: String, autoClearAfter seconds: TimeInterval?)
}

/// Production implementation backed by `UIPasteboard.general`. Auto-clear
/// only fires when the clipboard still holds the value KeyNest wrote — a
/// later write (Safari copy, another app) silently wins (NFR 1.1: we do
/// not overwrite other apps' clipboard state).
public final class SystemPasteboard: Pasteboarding {
    private let pasteboard: UIPasteboard
    private let scheduler: @Sendable (TimeInterval, @Sendable @escaping () -> Void) -> Void

    public init(
        pasteboard: UIPasteboard = .general,
        scheduler: @Sendable @escaping (TimeInterval, @Sendable @escaping () -> Void) -> Void = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    ) {
        self.pasteboard = pasteboard
        self.scheduler = scheduler
    }

    public func setString(_ string: String, autoClearAfter seconds: TimeInterval?) {
        pasteboard.string = string
        guard let seconds else { return }
        let captured = string
        let board = pasteboard
        scheduler(seconds) {
            if board.string == captured {
                board.string = ""
            }
        }
    }
}

/// Convenience helpers so view models don't repeat the "sensitive vs
/// non-sensitive auto-clear" policy in every call site.
///
/// Default auto-clear for secrets is 60 s (1Password / Bitwarden parity).
public enum CredentialClipboard {
    /// Default auto-clear window for secret values (passwords, custom
    /// field values, TOTP seeds). Seconds.
    public static let defaultAutoClearSeconds: TimeInterval = 60

    /// Copies a sensitive value with the default auto-clear window.
    public static func copySecret(_ value: String, to pasteboard: Pasteboarding) {
        pasteboard.setString(value, autoClearAfter: defaultAutoClearSeconds)
    }

    /// Copies a non-sensitive value (label / username / service identifier)
    /// without an auto-clear deadline.
    public static func copyPlain(_ value: String, to pasteboard: Pasteboarding) {
        pasteboard.setString(value, autoClearAfter: nil)
    }
}

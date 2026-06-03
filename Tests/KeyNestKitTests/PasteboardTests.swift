import XCTest
import UIKit
@testable import KeyNestKit

/// Records every `setString` call so assertions can verify the helper
/// dispatched the expected value + auto-clear policy.
final class RecordingPasteboard: Pasteboarding, @unchecked Sendable {
    struct Call: Equatable {
        let value: String
        let autoClearAfter: TimeInterval?
    }
    private let lock = NSLock()
    private var _calls: [Call] = []
    var calls: [Call] {
        lock.lock(); defer { lock.unlock() }
        return _calls
    }

    func setString(_ string: String, autoClearAfter seconds: TimeInterval?) {
        lock.lock()
        _calls.append(Call(value: string, autoClearAfter: seconds))
        lock.unlock()
    }
}

final class CredentialClipboardTests: XCTestCase {

    func test_copySecret_usesDefaultAutoClearWindow() {
        let board = RecordingPasteboard()
        CredentialClipboard.copySecret("hunter2", to: board)
        XCTAssertEqual(
            board.calls,
            [.init(value: "hunter2", autoClearAfter: CredentialClipboard.defaultAutoClearSeconds)]
        )
    }

    func test_copyPlain_doesNotScheduleAutoClear() {
        let board = RecordingPasteboard()
        CredentialClipboard.copyPlain("alice@example.com", to: board)
        XCTAssertEqual(
            board.calls,
            [.init(value: "alice@example.com", autoClearAfter: nil)]
        )
    }

    func test_defaultAutoClearWindow_isOneMinute() {
        // 1Password / Bitwarden parity — guards against accidental tuning.
        XCTAssertEqual(CredentialClipboard.defaultAutoClearSeconds, 60)
    }
}

final class SystemPasteboardTests: XCTestCase {

    private final class FakeBoard {
        var string: String? = nil
    }

    func test_autoClear_clearsValueAfterDeadline_whenStillOurValue() {
        // SystemPasteboard's UIPasteboard dependency makes a true unit test
        // impossible without UIKit involvement; the auto-clear semantics
        // are exercised by mirroring the scheduler injection.
        let scheduledWork = SchedulerCapture()
        let board = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: board.name) }

        let pasteboard = SystemPasteboard(
            pasteboard: board,
            scheduler: { delay, work in
                scheduledWork.record(delay: delay, work: work)
            }
        )
        pasteboard.setString("secret", autoClearAfter: 60)
        XCTAssertEqual(board.string, "secret")
        XCTAssertEqual(scheduledWork.delays, [60])

        // The clipboard still holds our value — running the work clears it.
        scheduledWork.runAll()
        XCTAssertEqual(board.string, "")
    }

    func test_autoClear_doesNotOverwriteForeignValue() {
        let scheduledWork = SchedulerCapture()
        let board = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: board.name) }

        let pasteboard = SystemPasteboard(
            pasteboard: board,
            scheduler: { delay, work in
                scheduledWork.record(delay: delay, work: work)
            }
        )
        pasteboard.setString("secret", autoClearAfter: 60)
        board.string = "someone-else"

        scheduledWork.runAll()
        // Foreign value untouched — KeyNest must not blast another app's
        // clipboard state (NFR 1.1 / NFR 1.2 spirit).
        XCTAssertEqual(board.string, "someone-else")
    }

    func test_noAutoClear_whenSecondsIsNil() {
        let scheduledWork = SchedulerCapture()
        let board = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: board.name) }

        let pasteboard = SystemPasteboard(
            pasteboard: board,
            scheduler: { delay, work in
                scheduledWork.record(delay: delay, work: work)
            }
        )
        pasteboard.setString("alice@example.com", autoClearAfter: nil)
        XCTAssertEqual(board.string, "alice@example.com")
        XCTAssertEqual(scheduledWork.delays, [])
    }
}

/// Captures `scheduler` callbacks so a test can run them synchronously.
private final class SchedulerCapture: @unchecked Sendable {
    private(set) var delays: [TimeInterval] = []
    private var works: [() -> Void] = []
    func record(delay: TimeInterval, work: @escaping () -> Void) {
        delays.append(delay)
        works.append(work)
    }
    func runAll() {
        let pending = works
        works.removeAll()
        pending.forEach { $0() }
    }
}

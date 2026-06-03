# KeyNest (iOS)

Offline-first iOS password & passkey manager. iOS port of the Android app
[**KeyNest**](../KeyNest). All credentials and passkeys are stored only on-device and never
transmitted to any server. Secrets are encrypted with **AES-256-GCM** using a data key wrapped
by the **Secure Enclave**, and unlocked via **Face ID / Touch ID** (passcode fallback).

- Acts as a system **AutoFill** credential provider (passwords).
- Acts as a **passkey** provider (WebAuthn / FIDO2) on **iOS 17+**.
- English + Japanese, light/dark, Manrope + JetBrains Mono.

> **Targeting model differs from Android.** KeyNest matches a target app by Android package
> name + signing-certificate SHA-256. iOS has no equivalent — KeyNest matches by **web domain**
> (`ASCredentialServiceIdentifier`). See `docs/specs/1-ios-port-foundation/design.md`.

## Status

**Phases 0–2 complete (logic core) — generated on Linux, not yet compiled on a Mac.**
`KeyNestKit` carries the full platform-independent core: domain models + use cases (with
async-stream DB observers), the GRDB vault + repositories, AES-256-GCM crypto with a
Secure-Enclave envelope data key, `LAContext` biometrics, and the WebAuthn byte layer +
P-256 passkey create / assert.

**First step on macOS:** run `scripts/build-test.sh` to compile and run `KeyNestKitTests`,
then fix any toolchain-specific issues (see
`docs/specs/1-ios-port-foundation/impl-notes.md` → "Mac 検証項目").

Remaining: Phase 3 SwiftUI UI, Phases 4–5 AutoFill / PassKey extensions, Phase 6
localization & hardening. Progress is tracked per-task in
`docs/specs/1-ios-port-foundation/tasks.md`.

## Build (macOS + Xcode required)

This project is generated from `project.yml` with [XcodeGen]; the `.xcodeproj` is not committed.

```bash
brew install xcodegen
xcodegen generate
open KeyNest.xcodeproj
```

Requirements: macOS with Xcode 15+, iOS 17 SDK. iOS apps **cannot** be built on Linux.

### Run the unit tests

`KeyNestKitTests` runs on the iOS Simulator and needs **no** code signing /
`DEVELOPMENT_TEAM` (only device builds need a real Team ID):

```bash
scripts/build-test.sh                                # xcodegen generate + xcodebuild test
KEYNEST_DEVICE="iPhone 16" scripts/build-test.sh     # if "iPhone 15" isn't installed
```

Identifiers are set: bundle ID `io.github.hitoshiichikawa.ios.keynest`, App Group
`group.io.github.hitoshiichikawa.ios.keynest`, Keychain group `io.github.hitoshiichikawa.ios.keynest.shared`.
The only thing left before running on a device is your **`DEVELOPMENT_TEAM`** (Apple Team ID),
set in Xcode / a local xcconfig — never committed.

## Architecture

```
KeyNest.app ──┐
              ├── KeyNestKit.framework  (Domain / Data[GRDB] / Crypto / WebAuthn / AutoFill)
AutoFill.appex┘
        └── shared: App Group SQLite DB  +  shared Keychain (SE-wrapped data key)
```

See `docs/specs/1-ios-port-foundation/` for `requirements.md`, `design.md`, `tasks.md`.

## License

MIT (parity with KeyNest). Bundled fonts are OFL (Manrope, JetBrains Mono).

[XcodeGen]: https://github.com/yonaskolb/XcodeGen

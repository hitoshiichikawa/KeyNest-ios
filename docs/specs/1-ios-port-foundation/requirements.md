# Requirements — KeyNest iOS 移植（基盤フェーズ）

> 元アプリ: `../KeyNest`（Android / Kotlin / Room / Android Autofill Framework / Credential Manager）
> 本 spec: KeyNest の動作を iOS に忠実移植するための **プラットフォーム要件**。
> 元アプリの機能要件（保管・暗号化・自動入力・PassKey）は維持し、iOS 固有の差分のみを
> ここで明示する。EARS 記法・numeric 階層 ID。

## 確定済みの方針（人間決定 2026-06-03）

- 機能スコープ: **パスワード自動入力 ＋ PassKey 両対応**（最低 iOS 17）
- 自動入力ターゲティング: **ドメイン基盤に作り替え**（Android のパッケージ名＋署名照合は廃止）
- UI: **SwiftUI で iOS ネイティブ（HIG）最適化**（Material 3 の見た目模倣はしない）
- データ移行: 無し（新規インストール前提）

---

## Requirement 1: アプリ構成（App + AutoFill 拡張 + 共有コンテナ）

iOS の自動入力は App Extension 必須のため、単一 APK 構成を分割する。

### 1.1
The KeyNest app shall ship as a main app target plus an AutoFill Credential Provider
extension target that share one code framework.

### 1.2
While the extension and the app both need vault data, the KeyNest app shall store the
SQLite database in an App Group shared container so both targets read/write the same file.

### 1.3
While the extension and the app both need the data-encryption key, the KeyNest app shall
store key material in a shared Keychain access group reachable from both targets.

### 1.4
The KeyNest app shall declare the AutoFill Credential Provider entitlement
(`com.apple.developer.authentication-services.autofill-credential-provider`) on both the
app and the extension target.

### 1.5
Where the device runs iOS 17 or newer, the AutoFill extension shall advertise both password
and passkey provision capability; where the device runs iOS 16, the extension shall advertise
password capability only.

---

## Requirement 2: ローカル限定保管（オフラインファースト）

元アプリ NFR 1.5（INTERNET 権限を持たず通信を fail-fast）の iOS 等価。

### 2.1
The KeyNest app shall not include any networking code paths in the vault read/write,
encryption, or autofill flows.

### 2.2
The KeyNest app shall keep all credential and passkey data on-device only and shall not
transmit it to any external server.

### 2.3
While stored at rest, the credential password and passkey private key shall be encrypted
with AES-256-GCM before being written to the database.

---

## Requirement 3: 暗号化（CryptoKit + Secure Enclave）

元アプリの「鍵は TEE から出ない（NFR 1.2）」を iOS で等価実現する。

### 3.1
The KeyNest app shall encrypt the credential password with AES-256-GCM using a 12-byte IV
generated per encryption call, persisting ciphertext and IV as separate columns
(parity with `password_ciphertext` / `password_iv`).

### 3.2
The KeyNest app shall protect the data-encryption key with a non-exportable Secure Enclave
key so that the raw key bytes never leave secure hardware.

### 3.3
If the device has no Secure Enclave, the KeyNest app shall fall back to a Keychain-stored key
with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and shall not silently disable encryption.

### 3.4
The KeyNest app shall encrypt the custom-fields list as a JSON payload through the same
data-encryption key (parity with `EncryptedCustomFieldsCodec`), and shall treat an empty
ciphertext as an empty custom-fields list.

### 3.5
While decrypting, if the GCM auth tag does not validate, the KeyNest app shall surface an
opaque decryption error and shall not log any plaintext byte.

---

## Requirement 4: 生体認証 / デバイス認証アンロック

元アプリ Req 5.x（BiometricPrompt STRONG | DEVICE_CREDENTIAL）の iOS 等価。

### 4.1
When the user reveals a stored password, fills a credential, or runs a destructive vault
action, the KeyNest app shall require `LAContext` device-owner authentication
(biometrics with passcode fallback) before exposing plaintext.

### 4.2
If biometric/device authentication fails or is cancelled, the KeyNest app shall keep the
plaintext sealed and shall return the UI to its pre-authentication state.

### 4.3
The KeyNest app shall zero-fill the decrypted password buffer immediately after use
(parity with `PlaintextCredential.close()`).

---

## Requirement 5: パスワード自動入力（ドメイン基盤）

Android の AssistStructure ヒューリスティック照合を、iOS のドメイン基盤照合に置換する。

### 5.1
The credential record shall identify its target by a normalized web domain / service
identifier instead of an Android package name.

### 5.2
The AutoFill extension shall register each saved credential as an `ASPasswordCredentialIdentity`
keyed by its service identifier so iOS surfaces it on matching sites/apps.

### 5.3
When the user selects a KeyNest suggestion in the system AutoFill UI, the extension shall
require device-owner authentication, decrypt the password, and return an
`ASPasswordCredential` (username + password).

### 5.4
While no stored credential matches the requested service identifier, the extension shall
return control to the OS without surfacing an entry.

### 5.5
The KeyNest app shall keep its registered credential-identity store in sync with the vault
on create / update / delete.

---

## Requirement 6: PassKey プロバイダ（iOS 17+）

元アプリの WebAuthn セレモニー（CBOR/COSE/attestation/assertion バイト列）を iOS の
`ASCredentialProvider` passkey フローに載せる。バイトレイアウトは元実装と一致させる。

### 6.1
Where the device runs iOS 17+, when iOS requests passkey registration, the extension shall
generate an ES256 (P-256) key pair, build a `none`-format attestation object whose
authenticator data and COSE key match the KeyNest byte layout, and return an
`ASPasskeyRegistrationCredential`.

### 6.2
The KeyNest app shall use the same 16-byte AAGUID byte layout decided for the iOS build
(see design §PassKey) consistently across all registrations.

### 6.3
Where the device runs iOS 17+, when iOS requests a passkey assertion, the extension shall
build 37-byte authenticator data with flags `0x05` (UP|UV), sign
`authenticatorData ‖ clientDataHash` with SHA256withECDSA, and return an
`ASPasskeyAssertionResponse`.

### 6.4
The KeyNest app shall store the passkey ES256 private key encrypted with AES-256-GCM and shall
never expose it across the repository boundary in plaintext (parity with `PasskeyEntity` /
`Passkey`).

### 6.5
While signing an assertion, the KeyNest app shall increment the stored signature counter
atomically with the signature and shall roll the counter back if signing fails
(parity with `signWithIncrement`).

### 6.6
If a passkey registration would duplicate an existing `(rpId, userHandle)` pair, the KeyNest
app shall overwrite the prior passkey rather than create a duplicate.

---

## Requirement 7: 画面と機能パリティ（SwiftUI / HIG）

見た目は iOS ネイティブ化するが、情報設計・操作・状態遷移は元アプリと等価にする。

### 7.1
The KeyNest app shall provide a credential list screen with search, sort
(updated-desc / label-asc / domain-asc), a recently-used section, and empty states
(initial vs no-match) equivalent to KeyNest.

### 7.2
The KeyNest app shall provide a credential edit screen with label / username / password /
target-domain / custom fields (max 10) / advanced details, plus duplicate and delete actions
equivalent to KeyNest.

### 7.3
The KeyNest app shall provide a settings screen exposing autofill status, lock method, vault
metadata (count / last-updated / storage), passkey-provider status, OSS licenses, and a danger
zone, adapted to iOS settings idioms.

### 7.4
When the user runs "clear vault" in the danger zone, the KeyNest app shall require
device-owner authentication and an explicit confirmation before deleting all credentials,
passkeys, and key material.

### 7.5
The KeyNest app shall provide onboarding that guides the user to enable KeyNest as an AutoFill
provider in iOS Settings, adapted to the iOS enablement path (no direct deep-link to the toggle).

---

## Requirement 8: ローカライズ・デザイントークン

### 8.1
The KeyNest app shall ship English and Japanese localizations with parity to KeyNest's string
catalog.

### 8.2
The KeyNest app shall bundle the Manrope and JetBrains Mono fonts and apply them as the primary
and monospace typefaces (license parity, OFL).

### 8.3
The KeyNest app shall support light and dark appearance using the KeyNest semantic color tokens.

---

## Non-Functional Requirements

### NFR 1: セキュリティ
- 1.1 plaintext（パスワード/秘密鍵/カスタムフィールド値）はログ出力しない。
- 1.2 ロック画面・スクリーンショット時に平文を露出しない（センシティブ画面の保護）。
- 1.3 鍵束は `ThisDeviceOnly`、iCloud Keychain 同期対象にしない。

### NFR 2: 性能
- 2.1 AutoFill 候補提示は体感即時（重い同期復号を提示パスに置かない）。

### NFR 3: 堅牢性
- 3.1 拡張のフィル経路で例外が発生しても OS にエラーを返さず、候補無しとして安全に閉じる
  （parity: `onSuccess(null)`）。

### NFR 4: ビルド/配布
- 4.1 プロジェクトは XcodeGen の `project.yml` から再現生成でき、Mac/Xcode でビルドする。
- 4.2 本リポジトリには署名証明書・プロビジョニングprofile・実 Team ID を含めない。

---

## 確定事項（人間決定 2026-06-03）

1. アプリ名: **KeyNest**（Android 版と同一）。リポジトリフォルダ名は `KeyNest-ios`。
2. Bundle ID: **`io.github.hitoshiichikawa.ios.keynest`**（App Group `group.io.github.hitoshiichikawa.ios.keynest` /
   Keychain `io.github.hitoshiichikawa.ios.keynest.shared`）。
3. AAGUID: **新採番** `aae6363e-fdb4-4c71-aef4-43c79e5d59a3`。
4. passkey 鍵方式: 単一 DEK ＋ Secure Enclave エンベロープ（`keyAlias` 廃止）。

## 確認事項（残・人間判断待ち）

1. **Team ID** の実値（署名時に設定。VCS には含めない）。
2. App Store 配布前提か（AutoFill / PassKey はレビュー観点あり）。
3. PassKey の RP 紐付け: KeyNest 自身の associated-domains は不要（他 RP の passkey は
   associated-domains 無しで提供可能）。自社 RP を持つ予定があるかのみ確認。

# Tasks — KeyNest iOS 移植（基盤フェーズ）

> 規約: numeric 階層 ID / `_Requirements:_` 必須 / 並列可は `(P)` ＋ `_Boundary:_`。
> 各タスクは概ね 1 commit 単位。Phase は実装順（後段ほど前段に依存）。
> **ビルド/テストは Mac + Xcode（XcodeGen 生成）で実施**。本リポジトリ環境（Linux）は
> ソース生成のみ可能。

## Phase 0: プロジェクト雛形

- [x] 0.1 XcodeGen `project.yml`（App / AutoFillExtension / KeyNestKit / Tests の 4 ターゲット、GRDB SPM 依存）
  - _Requirements: 1.1, 1.5, NFR 4.1_
- [x] 0.2 Entitlements（autofill-credential-provider, App Group, Keychain access group）と 両 Info.plist
  - _Requirements: 1.2, 1.3, 1.4, 1.5_
- [x] 0.3 `AppGroup.swift`（共有コンテナ URL / Keychain グループ定数）と `ServiceLocator` 骨格
  - `AppGroup.swift` はシード済み。`KeyNestKit/Platform/ServiceLocator.swift` を追加し Phase 1 の暗号/データ層（DB / DataKey / cipher / codec / 各 Repository）を配線。後続フェーズで Biometric / UseCase / AutoFill 同期を拡張
  - _Requirements: 1.2, 1.3_
- [x] 0.4 README にビルド手順（`brew install xcodegen` → `xcodegen generate` → `open`）を追記、`.gitignore`
  - _Requirements: NFR 4.1, NFR 4.2_

> **シード済み（未コンパイル / Mac 検証前）**: 以下の「プラットフォーム非依存かつバイト一致が最重要」な
> アンカーを先行作成済み。Phase 1/2 着手時に Mac でコンパイル・テストして確定する:
> `KeyNestKit/WebAuthn/{CborWriter,CoseKeyEncoder,AuthenticatorDataBuilder,AttestationObjectBuilder,KeynestAaguid}.swift`、
> `KeyNestKit/Crypto/AesGcmCipher.swift`、`KeyNestKit/Domain/Model/{Credential,CustomField,PlaintextCredential}.swift`、
> `KeyNestKit/Platform/AppGroup.swift`、`Tests/KeyNestKitTests/WebAuthnByteLayoutTests.swift`（バイト一致回帰テスト）。

## Phase 1: 暗号・データ基盤

- [x] 1.1 `AesGcmCipher`（CryptoKit AES.GCM、12B nonce、tag 末尾連結で Android 互換レイアウト）
  - encrypt/decrypt 往復・IV 毎回相違・tag 改竄失敗の単体テスト（Red→Green）
  - 実装はシード済み。専用テスト `Tests/KeyNestKitTests/AesGcmCipherTests.swift` を追加（往復 / IV 相違 / tag 改竄 / 鍵相違 / 短い blob）。WebAuthn テストから AES ケースを移設
  - _Requirements: 2.3, 3.1, 3.5_
- [x] 1.2 `DataKeyProvider`（Secure Enclave エンベロープ DEK、SE 非搭載 fallback、`clearAll()`）
  - `KeyNestKit/Crypto/DataKeyProvider.swift`（`DataKeyStore` seam ＋ `KeychainDataKeyStore` 実バックエンド）。テストは in-memory fake で検証（実 Keychain/SE は Mac/実機検証）
  - _Requirements: 3.2, 3.3, NFR 1.3_
- [x] 1.3 `EncryptedCustomFieldsCodec`（JSON `k`/`v` 短縮キー、空 BLOB→空、破損→空 fail-open）
  - `KeyNestKit/Crypto/EncryptedCustomFieldsCodec.swift`、`KeyNestKit/Platform/SafeLog.swift`。GCM 失敗は非吞み込みを境界テストで固定
  - _Requirements: 3.4_
- [x] 1.4 GRDB `Database` セットアップ（App Group 配置）＋ v1 マイグレーション（credentials / passkeys）
  - `KeyNestKit/Data/Database/AppDatabase.swift`（`DatabasePool` ＋ busy timeout、単一 `v1` マイグレーションに履歴を畳む、破壊的 fallback 無効）。`Tests/.../AppDatabaseTests.swift` でテーブル/一意インデックス生成を検証
  - _Requirements: 1.2, 2.2_
- [x] 1.5 `CredentialRecord` / `PasskeyRecord`（GRDB 行）と `*RepositoryImpl`（CRUD・`findByServiceIdentifier`・`signWithIncrement` トランザクション）
  - `KeyNestKit/Data/Record/*`、`KeyNestKit/Data/Repository/*`、境界型 `EncryptedCredentialRecord` / `Passkey` / `SavePasskeyRequest`（`KeyNestKit/Domain/Model/*`）、protocol（`KeyNestKit/Domain/Repository/*`）。passkey は単一 DEK 方式で `keyAlias` 列なし。暗号処理は DB トランザクション外。reactive observe* は本フェーズ非対象（スナップショットのみ）
  - `signWithIncrement` ロールバック / Req 6.6 上書き / loadPrivateKey 往復を `Tests/.../{CredentialRepositoryTests,PasskeyRepositoryTests}.swift` で固定
  - _Requirements: 2.2, 6.4, 6.5_

## Phase 2: ドメイン ＋ WebAuthn バイト層

- [x] 2.1 Domain Model 移植（`Credential`(serviceIdentifier 化), `CustomField`, `PlaintextCredential`, `Passkey`, `VaultMetadata`, enums）(P)
  - シード/1.5 で先行作成済の型に加え、`VaultMetadata` / `DeviceLockStatus` / `PasskeyProviderStatus` を追加（`KeyNestKit/Domain/Model/*`）。`DeviceLockStatus` は iOS LAContext 準拠の 3 値（Android の `UpdateRequired` は iOS 等価が無く除外）
  - _Requirements: 5.1, 4.3_
  - _Boundary: KeyNestKit/Domain/Model_
- [x] 2.2 UseCase 移植（Save/Update/Delete/List/Unlock/Duplicate/MarkUsed/ObserveRecentlyUsed/ObserveVaultMetadata/GetVaultStorageUsage/GetDeviceLockStatus/ClearVault/ListPasskeys）
  - `KeyNestKit/Domain/UseCase/*`（13 UseCase）。署名解決は廃止、observe* は **async stream**（GRDB `ValueObservation`→`AsyncThrowingStream`、repo に `observeBySort`/`observeRecentlyUsed`/`observeMetadata`/`observeAll` を追加）。`ClearVault` は credentials＋passkeys＋DEK を削除。`GetVaultStorageUsage` は `VaultStorageMeasurer`（`-wal`/`-shm` 含む）。`ServiceLocator` に全配線
  - update 時パスワード未変更なら ciphertext 温存、の境界テストを `SaveUpdateCredentialUseCaseTests` で固定。Unlock の customFields fail-open / 鍵相違 decryptFailed も固定
  - 確認事項: Android は更新時 `lastUsedAt` を null リセットするが、iOS は recently-used 整合のため**温存**（要レビュー）
  - _Requirements: 7.1, 7.2, 7.4_
- [x] 2.3 `BiometricAuthenticator`（LAContext `.deviceOwnerAuthentication`、`AuthResult` 分岐）(P)
  - `KeyNestKit/Crypto/BiometricAuthenticator.swift`（protocol `BiometricAuthenticating` ＋ 実装）。`authenticate` / `availability` / `deviceLockStatus`。実 LAContext は Mac/実機検証、consumer はモックで単体テスト
  - _Requirements: 4.1, 4.2_
  - _Boundary: KeyNestKit/Crypto_
- [x] 2.4 WebAuthn バイト層: `CborWriter` / `CoseKeyEncoder` / `KeynestAaguid`（既知ベクタ単体テスト）(P)
  - シード済み実装を Android と突き合わせバイト一致を確認（AAGUID のみ iOS 新採番＝design 確定事項1で意図的差分）。`WebAuthnByteLayoutTests` に CBOR 長さエンコーディング境界（`0x18`/`0x58`/`0x59`）を追加。`Base64URL` ヘルパ＋テストも追加
  - _Requirements: 6.1, 6.2_
  - _Boundary: KeyNestKit/WebAuthn_
- [x] 2.5 `AuthenticatorDataBuilder`（登録 0x45 / 認証 0x05）/ `AttestationObjectBuilder`(none) / `PasskeyAssertion` / `PasskeyCreator`（P256 鍵生成・DEK 暗号化保存）
  - `KeyNestKit/WebAuthn/{PasskeyCreator,PasskeyAssertion}.swift`。iOS 差分: 鍵生成は CryptoKit `P256.Signing.PrivateKey`、COSE は `publicKey.rawRepresentation`(64B)、**per-key Keystore alias 廃止**（暗号化保存は単一 DEK の `PasskeyRepository.save`）、assertion は OS 提供 `clientDataHash` で署名し **DER** を返す。`ServiceLocator` に `passkeyCreator` 配線
  - `PasskeyCreatorTests`（登録バイト合成: AAGUID/flags 0x45/COSE 配置/attestation framing、DEK 保存往復）/ `PasskeyAssertionTests`（authData 37B flags 0x05、DER 署名の検証、create→assert の end-to-end 検証）でバイト/署名を固定
  - _Requirements: 6.1, 6.3, 6.4_

## Phase 3: メインアプリ UI（SwiftUI / HIG）

- [ ] 3.1 共通基盤: `KeyNestApp`(@main), `NavigationStack` ルート, カラーアセット / フォント登録, `StrengthBar` 等 Components
  - _Requirements: 8.2, 8.3_
- [ ] 3.2 Credential List（検索 `.searchable`・ソート `Menu`・最近使った・空状態 initial/no-match・複製/削除）
  - _Requirements: 7.1_
- [ ] 3.3 Credential Edit（label/username/password/target-domain/custom fields≤10/advanced・複製・削除・重複検出）＋ Domain Picker sheet
  - _Requirements: 7.2, 5.1_
- [ ] 3.4 Settings（autofill 状態・ロック方式・Vault メタデータ・passkey provider 状態・OSS・danger 入口）
  - _Requirements: 7.3_
- [ ] 3.5 Danger Zone（生体→確認ダイアログ→ClearVault、鍵削除）＋ OSS ライセンス画面
  - _Requirements: 7.4_
- [ ] 3.6 Onboarding（iOS の自動入力有効化導線、`PasskeyProviderStatus` 表示）
  - _Requirements: 7.5_

## Phase 4: AutoFill 拡張 — パスワード

- [ ] 4.1 `ServiceIdentifierMatcher`（URL/ドメイン正規化: scheme/path/大小/www 除去）＋ 境界値テスト (P)
  - _Requirements: 5.1_
  - _Boundary: KeyNestKit/AutoFill_
- [ ] 4.2 `CredentialIdentityStoreSync`（保存/更新/削除で `ASCredentialIdentityStore` 同期）
  - _Requirements: 5.2, 5.5_
- [ ] 4.3 `CredentialProviderViewController`（`prepareCredentialList` / `provideCredentialWithoutUserInteraction` / UI 選択→生体→復号→`ASPasswordCredential`）
  - 一致なし・例外時の安全終了（cancelRequest）
  - _Requirements: 5.3, 5.4, NFR 3.1_

## Phase 5: AutoFill 拡張 — PassKey（iOS 17+）

- [ ] 5.1 拡張 Info.plist の `ProvidesPasskeys` 能力宣言確認 ＋ passkey 登録 coordinator（`ASPasskeyRegistrationCredential` 返却）
  - _Requirements: 6.1, 6.2, 6.6_
- [ ] 5.2 passkey assertion coordinator（OS の `clientDataHash` で署名・`signWithIncrement`・`ASPasskeyAssertionResponse`・RP スプーフィング検証）
  - _Requirements: 6.3, 6.5_

## Phase 6: ローカライズ・仕上げ・ハードニング

- [ ] 6.1 Localizable（EN/JA）移植（KeyNest strings パリティ）(P)
  - _Requirements: 8.1_
  - _Boundary: KeyNestKit/Resources_
- [ ] 6.2 センシティブ画面保護（`.privacySensitive` / スクショ時マスク）・redact ログ・Keychain ThisDeviceOnly 監査 (P)
  - _Requirements: NFR 1.1, NFR 1.2, NFR 1.3_
  - _Boundary: KeyNest/UI_
- [ ]* 6.3 結合/E2E テスト拡充（GRDB 実 DB CRUD、IdentityStore 同期、Safari 自動入力手動確認手順）
  - _Requirements: 5.3, 6.3_

## 依存関係メモ
- Phase 1 → 2 → (3,4,5) は順序依存。Phase 6 は随時。
- `(P)` タスクは同 Phase 内で境界が分かれており並列実装可。
- Phase 5 は Phase 4（拡張の土台）と Phase 2.4/2.5（WebAuthn バイト層）完了後に着手。

## 未確定（design.md 確認事項に従う）
- AAGUID 流用可否 / passkey 鍵単純化可否 / 生体ゲート粒度 / Bundle ID 等の実値。

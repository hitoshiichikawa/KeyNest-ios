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

- [x] 3.1 共通基盤: `KeyNestApp`(@main), `NavigationStack` ルート, カラーアセット / フォント登録, `StrengthBar` 等 Components
  - `KeyNest/KeyNestApp.swift`（`ServiceLocator.makeShared()` を `.task` で起動 → `RootView` / 失敗時 `StartupErrorView`）、`KeyNest/UI/Root/RootView.swift`（`NavigationStack` ＋ Settings 遷移の placeholder）。テーマは `KeyNest/UI/Theme/{KNColor,KNFont}.swift`（Android `colors.xml` / `values-night` を `UIColor(dynamicProvider:)` で 1 ファイル化、Manrope/JetBrains Mono は `KeyNest/Resources/Fonts/*.ttf` ＋ `Info.plist` `UIAppFonts`）。`KeyNest/UI/Components/StrengthBar.swift`（3 セグメント 14×4 pt / gap 2 pt、weak/medium/strong で塗り分け）
  - _Requirements: 8.2, 8.3_
- [x] 3.2 Credential List（検索 `.searchable`・ソート `Menu`・最近使った・空状態 initial/no-match・複製/削除）
  - `KeyNest/UI/List/CredentialListViewModel.swift`（`@Observable` / `@MainActor`、`ListCredentialsUseCase` / `ObserveRecentlyUsedUseCase` を `for try await` で消費。sort 変更は View の `.task(id:)` で再購読＝Kotlin `flatMapLatest` 等価）/ `CredentialListView.swift`（`.searchable`、ソート `Menu`（updated/label/domain）、Recently used 水平カルーセル、空状態 initial/no-match、leading swipe で複製・trailing swipe で `confirmationDialog` 削除）。署名フィルタ／PassKey 行は v1 スコープ外
  - _Requirements: 7.1_
- [x] 3.3 Credential Edit（label/username/password/target-domain/custom fields≤10/advanced・複製・削除・重複検出）
  - `KeyNest/UI/Edit/CredentialEditViewModel.swift`（new / edit モード、edit ロード時に `BiometricAuthenticating.authenticate` → `UnlockVaultUseCase` で復号、`PlaintextCredential` 保持・deinit で wipe、`UpdateCredentialUseCase` は password 未変更時 ciphertext 温存）/ `CredentialEditView.swift`（生体プロンプト中ローダ、cancel/failed 時 Retry View、reveal toggle で `SecureField`/`TextField` 切替、custom fields≤10、Save/Delete/Duplicate、destructive は `confirmationDialog`、`.privacySensitive()`）/ `CredentialListView` から `+` 新規導線と row tap の編集遷移を配線。重複検出は serviceIdentifier+username の 250ms debounce 背景 lookup で **non-blocking 警告**（Android パリティ）
  - Domain Picker sheet は Phase 4 の `ServiceIdentifierMatcher` と一緒に追加（現状は URL TextField 直接入力）
  - _Requirements: 7.2, 5.1_
- [x] 3.4 Settings（autofill 状態・ロック方式・Vault メタデータ・passkey provider 状態・OSS・danger 入口）
  - `KeyNest/UI/Settings/SettingsViewModel.swift`（`@MainActor` + `@Observable`、`ObserveVaultMetadataUseCase` を `.task` で消費し metadata 変化時に `GetVaultStorageUsageUseCase` を再測。`GetDeviceLockStatusUseCase` + `ASCredentialIdentityStore.state()` は scenePhase=.active で再サンプル。PassKey 状態は `#available(iOS 17,*)` + autofill で導出）/ `SettingsView.swift`（AutoFill / Security / Vault / About / Danger Zone セクション、autofill 無効時は `openSettingsURLString` への deeplink ボタン、OSS / Danger Zone は Phase 3.5 placeholder）。CredentialListView の左 toolbar に Settings 入口
  - _Requirements: 7.3_
- [x] 3.5 Danger Zone（生体→確認ダイアログ→ClearVault、鍵削除）＋ OSS ライセンス画面
  - `KeyNest/UI/Danger/DangerZoneViewModel.swift`（strict state machine: idle→authenticating→confirming→clearing→cleared/failed、`clearing` は `confirming` からのみ到達可、`confirming` は `BiometricAuthenticating.authenticate` 成功からのみ到達可。`ClearVaultUseCase` は credentials＋passkeys＋DEK を削除）/ `DangerZoneView.swift`（Phase 別 statusLabel・footer、confirmationDialog 二段階）。`KeyNest/UI/Oss/OssEntry.swift`（Manrope/JetBrains Mono OFL、GRDB.swift MIT の static エントリ）/ `OssLicensesView.swift`（List + Link）。Settings の placeholder を本物 View に差し替え
  - _Requirements: 7.4_
- [x] 3.6 Onboarding（iOS の自動入力有効化導線、`PasskeyProviderStatus` 表示）
  - `KeyNest/UI/Onboarding/OnboardingViewModel.swift`（`@MainActor` + `@Observable`、`ASCredentialIdentityStore.state()` を `.task` ＋ `scenePhase=.active` で再サンプル＝Android `onResume` 等価。PassKey 状態は `#available(iOS 17, *)` 判定）/ `OnboardingView.swift`（welcome、AutoFill 状態カード、3 ステップガイド、PassKey 状態カード、`UIApplication.openSettingsURLString` への deeplink ボタン、有効化検知で CTA が "Continue" に切替、未有効時は "Skip for now"）。`KeyNestApp` に `@AppStorage("onboardingComplete")` で初回判定し OnboardingView / RootView を切替
  - _Requirements: 7.5_

## Phase 4: AutoFill 拡張 — パスワード

- [x] 4.1 `ServiceIdentifierMatcher`（URL/ドメイン正規化: scheme/path/大小/www 除去）＋ 境界値テスト (P)
  - `KeyNestKit/AutoFill/ServiceIdentifierMatcher.swift`（`normalize(_:)`: trim → lowercase → scheme/userInfo/port/path/query/fragment 除去 → 末尾 `.` / 先頭 `www.` 除去、idempotent。`matches(stored:requested:)`: 正規化後の完全一致 ＆ 非空）。サブドメインは**意図的に厳密**（`m.example.com` ≠ `example.com`、look-alike spoof 回避）。`Tests/.../ServiceIdentifierMatcherTests.swift` 14 件（scheme/path/port/userInfo/末尾ドット/www/lowercase/空白/idempotency/サブドメイン/typosquat）
  - _Requirements: 5.1_
  - _Boundary: KeyNestKit/AutoFill_
- [x] 4.2 `CredentialIdentityStoreSync`（保存/更新/削除で `ASCredentialIdentityStore` 同期）
  - `KeyNestKit/AutoFill/CredentialIdentityStoreSync.swift`（`actor`、protocol `CredentialIdentityStoreSyncing` ＋ `NoopCredentialIdentityStoreSync`）。`replaceAll` (snapshot reconcile)、`upsert`、`remove`、`removeAll`。`isEnabled` ガード（disabled なら IPC スキップ）、エラーは `SafeLog.warn` で握り潰す。`ServiceLocator` に配線、`makeShared()` 経路で本番 `ASCredentialIdentityStore.shared` を使用。`CredentialEditViewModel` / `CredentialListViewModel` / `DangerZoneViewModel` の各 CRUD 経路から同期、`KeyNestApp` 起動時に `replaceAll(with: listAll)` で reconcile
  - _Requirements: 5.2, 5.5_
- [x] 4.3 `CredentialProviderViewController`（`prepareCredentialList` / `provideCredentialWithoutUserInteraction` / UI 選択→生体→復号→`ASPasswordCredential`）
  - `AutoFillExtension/CredentialProviderViewController.swift`: `ServiceLocator.makeShared()` で App Group / Keychain 共有。`prepareCredentialList(for:)` → `listAll(.updatedDesc)` を `ServiceIdentifierMatcher.normalize` で絞り込み → `UIHostingController` で `AutoFillPickerView` を描画。silent path（`provideCredentialWithoutUserInteraction`）は常に `userInteractionRequired` で OS に UI 経路へ差し戻し（Req 4.1 を必須化）。`prepareInterfaceToProvideCredential` は同じ生体→`UnlockVaultUseCase`→`ASPasswordCredential` 経路。成功時は `markCredentialUsed` 副作用＋ `completeRequest`。失敗・例外・取消は `cancelRequest(withError:)`（NFR 3.1 安全終了）
  - `AutoFillExtension/AutoFillPickerView.swift`: SwiftUI Picker。Matched suggestions section ＋ all credentials section ＋ `.searchable`、空状態 footer
  - _Requirements: 5.3, 5.4, NFR 3.1_

## Phase 5: AutoFill 拡張 — PassKey（iOS 17+）

- [x] 5.1 拡張 Info.plist の `ProvidesPasskeys` 能力宣言確認 ＋ passkey 登録 coordinator（`ASPasskeyRegistrationCredential` 返却）
  - `AutoFillExtension/PasskeyRegistrationCoordinator.swift`（iOS 17+、`PasskeyCreator.create` → `PasskeyRepository.save`、`SavePasskeyRequest.privateKey` を `var` 化して `resetBytes` 可能に＝NFR 1.1）。`CredentialProviderViewController.prepareInterface(forPasskeyRegistration:)` で `PasskeyConfirmView`（SwiftUI）→ 生体認証 → `extensionContext.completeRegistrationRequest(using:)`
  - _Requirements: 6.1, 6.2, 6.6_
- [x] 5.2 passkey assertion coordinator（OS の `clientDataHash` で署名・`signWithIncrement`・`ASPasskeyAssertionCredential`・RP スプーフィング検証）
  - `AutoFillExtension/PasskeyAssertionCoordinator.swift`: `allowedCredentialIDs` 指定時はそれを優先、無指定時は `listDiscoverableByRpId` で選択。**RP スプーフィング検証**（stored.rpId == request.relyingPartyIdentifier、不一致は generic failure）。`loadPrivateKey` を `signWithIncrement` のクロージャ外で先行解決し、`var keyBuffer` を `defer resetBytes` でゼロ消去。クロージャは `@Sendable` 用に `let snapshot` capture。`CredentialProviderViewController.prepareCredentialList(for:requestParameters:)` 経路、silent path は `userInteractionRequired` で UI 強制（Req 4.1）
  - _Requirements: 6.3, 6.5_

## Phase 6: ローカライズ・仕上げ・ハードニング

- [x] 6.1 Localizable（EN/JA）移植（KeyNest strings パリティ）(P)
  - `KeyNest/Resources/Localizable.xcstrings`（Xcode 15+ JSON カタログ）。sourceLanguage=en、ja 翻訳を 80+ key 同梱（List / Edit / Settings / Onboarding / Danger / OSS / AutoFill picker / PassKey confirm）。`project.yml` に `developmentLanguage: en` ＋ `knownRegions: [en, ja]`。SwiftUI `Text("…")` リテラルは LocalizedStringKey として自動解決
  - _Requirements: 8.1_
  - _Boundary: KeyNestKit/Resources_
- [x] 6.2 センシティブ画面保護（`.privacySensitive` / スクショ時マスク）・redact ログ・Keychain ThisDeviceOnly 監査 (P)
  - **App switcher 保護**: `KeyNestApp.AppShell` で `@Environment(\.scenePhase) != .active` 時に `PrivacyShield`（KeyNest ロゴ + ブランドカラーのフル overlay）を被せる。OS が suspend 時に撮るスナップショットには vault が写らない（NFR 1.2）。
  - **`.privacySensitive()` 監査**: Edit 画面の `PasswordField` / `CustomFieldRow` に既適用、それ以外（label / username / serviceIdentifier）は redact 対象外と判断（Android `toString` redact と同じスタンス）。
  - **SafeLog 監査**: `SafeLog.warn/info/error` 4 callsite（`UnlockVaultUseCase` / `EncryptedCustomFieldsCodec` / `CredentialIdentityStoreSync` 4 経路）すべて静的メッセージ ＋ error type 名のみ。`Logger` interpolation は `privacy: .public` で固定し、動的データを混入させない契約。
  - **Keychain ThisDeviceOnly**: `KeychainDataKeyStore`（`DataKeyProvider.swift`）で `kSecAttrAccessible = kSecAttrAccessibleWhenUnlockedThisDeviceOnly` ＋ `kSecAttrSynchronizable = false`。Secure Enclave KEK 側も `.privateKeyUsage` のみ＝iCloud 同期対象外（NFR 1.3）。
  - _Requirements: NFR 1.1, NFR 1.2, NFR 1.3_
  - _Boundary: KeyNest/UI_
- [x]* 6.3 結合/E2E テスト拡充（GRDB 実 DB CRUD、IdentityStore 同期、Safari 自動入力手動確認手順）
  - `docs/specs/1-ios-port-foundation/impl-notes.md` の `### 6.3 (optional) E2E 検証手順` に Sim/実機での手動検証手順を文書化（拡張有効化 → password fill → passkey register/assert → Danger Zone → App Switcher 保護 → 言語切替）
  - _Requirements: 5.3, 6.3_

## 依存関係メモ
- Phase 1 → 2 → (3,4,5) は順序依存。Phase 6 は随時。
- `(P)` タスクは同 Phase 内で境界が分かれており並列実装可。
- Phase 5 は Phase 4（拡張の土台）と Phase 2.4/2.5（WebAuthn バイト層）完了後に着手。

## 未確定（design.md 確認事項に従う）
- AAGUID 流用可否 / passkey 鍵単純化可否 / 生体ゲート粒度 / Bundle ID 等の実値。

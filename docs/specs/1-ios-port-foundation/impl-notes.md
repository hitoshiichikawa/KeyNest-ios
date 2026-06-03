# Impl Notes — KeyNest iOS 移植（基盤フェーズ）

> 環境制約: 本リポジトリは Linux のため **ソース生成のみ**。コンパイル / テスト実行は
> Mac + Xcode（`xcodegen generate` 後）で行う。以下「Mac 検証項目」は実機/Sim での確認が必要。

## Phase 1 暗号層（1.1〜1.3）— 完了（Mac 検証前）

人間判断（2026-06-03）で、まず暗号層のみ確定し、GRDB データ層（1.4 / 1.5）と
`ServiceLocator`（0.3 の残り）は本レビュー後に進める方針。reactive な観測 API（observe* /
Flow 相当）は本フェーズでは入れない（スナップショットのみの方針）。

### 1.1 `AesGcmCipher`
- 実装はシード済み（`KeyNestKit/Crypto/AesGcmCipher.swift`）。本タスクで専用テスト
  `Tests/KeyNestKitTests/AesGcmCipherTests.swift` を追加し、WebAuthn テストに同居していた
  AES ケースをこちらへ移設（テストは対象コードの近傍に配置）。
- レイアウト: `iv = 12B nonce` / `ciphertext = sealedBox.ciphertext ‖ 16B tag`（Android
  `Cipher.doFinal` 出力と同一）。復号は末尾 16B を tag として分離。

### 1.2 `DataKeyProvider`（Secure Enclave エンベロープ DEK）
- Android `KeystoreKeyProvider`（鍵は TEE 内）の iOS 等価。iOS Secure Enclave は EC P-256
  のみ（AES 不可）のため **エンベロープ方式**:
  1. 256bit DEK を CSPRNG 生成
  2. SE に非エクスポータブル P-256 KEK を生成（`kSecAttrTokenIDSecureEnclave`、access control
     `[.privateKeyUsage]` のみ＝**生体フラグ無し**。確定事項 3 のアプリ層ゲート方針）
  3. KEK 公開鍵で DEK を ECIES 封緘（`eciesEncryptionStandardX963SHA256AESGCM`）、封緘 blob のみを
     共有 Keychain（`WhenUnlockedThisDeviceOnly` / `synchronizable=false`）へ保存
  4. 復号は SE 内で DEK を開封。生 DEK はプロセスメモリ上の短命（使用後 `resetBytes` でゼロ消去）
- **SE 非搭載 fallback**（Req 3.3）: DEK を直接 Keychain（`WhenUnlockedThisDeviceOnly`）へ保存。
  暗号化はサイレント無効化しない。
- **テスト容易性**: Keychain / SE 機構は `DataKeyStore` プロトコルへ分離（`KeychainDataKeyStore`
  が実バックエンド）。鍵ライフサイクル（生成 / 読込 / キャッシュ / clearAll / レース時の
  winner 採用 / 不正長検出）を in-memory fake で単体テスト（Android が `KeystoreKeyProvider` を
  `open` にしてテスト差し替えしていたのと同等の意図）。
- **初回起動レース**: app と extension が同時に DEK 生成→保存を試みた場合、`addSealedDataKey` は
  **add-only**（重複時 `duplicateItem` を throw）。先勝ち側の鍵を **再読込して採用**し、後勝ち側で
  上書きしない（既に暗号化済みデータの孤児化を防ぐ）。
- `clearAll()`（Req 7.4 / Danger Zone）: 封緘 DEK と SE 鍵を削除し、メモリキャッシュも破棄。

### 1.3 `EncryptedCustomFieldsCodec`
- Android `EncryptedCustomFieldsCodec.kt`（Issue #66）の動作等価。`Cipher`（DEK 共通鍵）を再利用。
- JSON 短縮キー `k` / `v`（`CustomFieldJson` は codec 内 private、`@SerialName` 相当の byte 形式パリティ）。
- 空 ciphertext → 空リスト / JSON 破損 → 空リスト（fail-open）＋ redact 警告（`SafeLog`、生 JSON は
  非ログ）。**GCM auth tag 失敗は非吞み込み**（`cipher.decrypt` は JSON の do/catch の外）で、
  境界テストで固定。
- 中間 UTF-8 / 復号バッファは `resetBytes` でゼロ消去（Android `Arrays.fill` 等価、NFR 1.1）。

### 追加生成物
- `KeyNestKit/Platform/SafeLog.swift`: `os.Logger` ベースの redact ロガー（Android `SafeLogger`
  等価）。静的メッセージ＋エラー型名のみ出力、`localizedDescription` は出さない。

## Phase 1 データ層（1.4 / 1.5）＋ 0.3 ServiceLocator — 完了（Mac 検証前）

### 1.4 `AppDatabase`（GRDB）
- `KeyNestKit/Data/Database/AppDatabase.swift`。App Group コンテナ上の `DatabasePool`（WAL、
  `busyMode = .timeout(10)` でプロセス間書込競合を吸収）。
- Room の v1〜v5 履歴は**単一 `v1` マイグレーションに畳む**（既存インストール無し）。`credentials` /
  `passkeys` テーブルと indices（`idx_credentials_service`、`idx_passkeys_rp`、UNIQUE
  `idx_passkeys_rp_user`）を作成。破壊的 fallback は無効（design 準拠）。
- `passkeys` は Android の `keyAlias` 列を**持たない**（単一 DEK 方式、確定事項 2）。
- 拡張がロック後に読めるよう DB ファイルへ `completeUntilFirstUserAuthentication` を best-effort 付与。
- テストは in-memory `DatabaseQueue` 経由（`AppDatabase(_:)`）。

### 1.5 Records ＋ Repositories
- `KeyNestKit/Data/Record/{CredentialRecord,PasskeyRecord}.swift`（GRDB Codable、snake_case カラムは
  `CodingKeys` で対応）。`PasskeyRecord` の `encrypted_private_key` / `private_key_iv` は `toDomain()` で
  落とし、`Passkey` には載せない（Req 6.4）。
- protocol（`KeyNestKit/Domain/Repository/{CredentialRepository,PasskeyRepository,RepositoryError}.swift`）と
  実装（`KeyNestKit/Data/Repository/*Impl.swift`）。境界型 `EncryptedCredentialRecord` / `Passkey` /
  `SavePasskeyRequest` は `Domain/Model/` に追加。
- iOS 適応: `findByPackage` → `findByServiceIdentifier`、Kotlin `Flow` の observe* は本フェーズ非対象
  （**スナップショットのみ**: `listAll(sort:)` / `findBy*`）、Kotlin `Result<>`/sealed failure → Swift
  `throws`（`RepositoryError.notFound`）、async/await。
- **暗号は DB トランザクション外**（save は encrypt 後に write、loadPrivateKey は fetch 後に decrypt）。
  DB ロック内で crypto を回さない。
- `signWithIncrement`（Req 6.5）: `writer.write { }` 内で `sign_count+1` →読み戻し→ `sign` クロージャ実行。
  `sign` が throw すると GRDB がトランザクションを巻き戻し、カウンタも戻る（テストで固定）。
- `save` の Req 6.6: 同一 `(rpId, userHandle)` の既存行を削除してから insert（上書き）。
- 並行性: GRDB の write/read クロージャは `@Sendable`。self を捕捉しないよう `let writer = database.writer`
  等を束縛し、Sendable な値型ローカルのみ捕捉。`Passkey` 等の境界型は struct（`Data` は値等価）で Sendable。

### 0.3 `ServiceLocator`
- `KeyNestKit/Platform/ServiceLocator.swift`。DB / DataKeyProvider / 単一 DEK cipher / CustomFields codec /
  両 Repository を配線。`makeShared()` で App Group DB ＋ Keychain/SE データ鍵を構築。後続で Biometric /
  UseCase / AutoFill 同期を追加。

## Phase 2 ドメイン＋UseCase＋Biometric（2.1〜2.3）— 完了（Mac 検証前）

人間判断: observe 系は **async stream**（GRDB `ValueObservation`→`AsyncThrowingStream`）、今回スコープは 2.1〜2.3
（WebAuthn passkey 2.4/2.5 は次回）。

### 2.1 ドメインモデル
- 追加: `VaultMetadata`（count + latestUpdatedAt）、`DeviceLockStatus`（iOS LAContext 準拠 3 値。Android の
  `UpdateRequired` は iOS 等価が無いため除外）、`PasskeyProviderStatus`（enabled/disabled/unsupported）。
- 既存（シード / 1.5 境界型）と合わせて 2.1 のモデルは出揃い。

### 2.2 UseCase（13 件）
- `KeyNestKit/Domain/UseCase/*`。Android 各 UseCase の動作等価。iOS 差分:
  - **署名解決（PackageSignatureResolver）を全廃**（iOS に署名照合が無い）。`packageName`→`serviceIdentifier`。
  - **observe 系を async stream 化**: repo に `observeBySort` / `observeRecentlyUsed` / `observeMetadata`
    （Credential）/ `observeAll`（Passkey）を追加し、`AppDatabase.observe(_:)` が `ValueObservation.values(in:)`
    を `AsyncThrowingStream` へブリッジ（GRDB 型を境界に漏らさない）。`ListCredentials` / `ObserveRecentlyUsed`
    / `ObserveVaultMetadata` / `ListPasskeys` がこれを forward。
  - **`ClearVault`**: credentials＋passkeys＋DEK（`DataKeyProviding.clearAll`）を DB-first 順で削除（Req 7.4）。
    Android の `detected_fields` は Non-Goal のため無し。passkey も削除する点が Android 版との差分。
  - **`GetVaultStorageUsage`**: `VaultStorageMeasurer`（`keynest.db` ＋ `-wal` / `-shm` の合算、`FileManager`）。
  - **`GetDeviceLockStatus`**: `BiometricAuthenticating.deviceLockStatus()`（LAContext）に委譲。
  - 失敗系は Kotlin `Result<>`/sealed → Swift `throws`＋enum（`SaveCredentialError` / `UpdateCredentialError`
    / `UnlockError` / `ClearVaultError`）。storage 系は GRDB エラーを伝播。
- パスワード入力は `[UInt8]`。iOS の値型 COW ＋ `String` 不変性のため**呼び出し側のワイプは限定的**（best-effort で
  作業バッファをゼロ消去）。確実にワイプできるのは出力の `PlaintextCredential`（class＋`[UInt8]`、`close()`）。
- **確認事項（要レビュー）**: Android `UpdateCredentialUseCase` は編集時 `lastUsedAt` を null リセットする
  （おそらく意図せず）。iOS は recently-used 整合のため `lastUsedAt` を**温存**。要否を人間判断。

### 2.3 BiometricAuthenticator
- `KeyNestKit/Crypto/BiometricAuthenticator.swift`。protocol `BiometricAuthenticating`（テスト/DI 用）＋
  LAContext 実装。`authenticate(reason:) async -> AuthResult` / `availability()` / `deviceLockStatus()`。
  `LAPolicy.deviceOwnerAuthentication`（生体＋パスコード fallback、Android `BIOMETRIC_STRONG|DEVICE_CREDENTIAL` 等価）。
  操作毎に新規 `LAContext`（context はキャッシュするため使い回すと再認証が抑止される）。

## Phase 2 WebAuthn バイト層＋passkey（2.4 / 2.5）— 完了（Mac 検証前）

### 2.4 バイト層（検証）
- シード済み `CborWriter` / `CoseKeyEncoder` / `AuthenticatorDataBuilder` / `AttestationObjectBuilder` /
  `KeynestAaguid` を Android 実装と突き合わせ、**バイト一致を確認**:
  - CBOR major type / 長さエンコーディング、COSE map 順（1,3,-1,-2,-3）、authData レイアウト、
    attestation `fmt="none"` の map 順（fmt→attStmt→authData）すべて一致。
  - **AAGUID のみ意図的に差分**: Android `2a56cf86-…` に対し iOS は新採番 `aae6363e-…`（design 確定事項1）。
- `WebAuthnByteLayoutTests` に CBOR 長さ境界（inline≤23 / `0x18` / `0x58` / `0x59`）を追加。`Base64URL`
  ヘルパ（url-safe / no-pad、Android `URL_SAFE|NO_PADDING` 相当）＋テストを追加。

### 2.5 PasskeyCreator / PasskeyAssertion
- iOS 差分（design §PassKey 表）:
  - **鍵生成 = CryptoKit `P256.Signing.PrivateKey`**（JCE 不使用）。COSE は `publicKey.rawRepresentation`
    （64B uncompressed x‖y）→ `CoseKeyEncoder.encodeEs256(rawXY:)`。
  - **per-key Keystore alias / wrapping key を全廃**（確定事項2）。`PasskeyCreator` は純粋なバイトビルダで、
    DB/Keychain に触れない。暗号化保存は単一 DEK の `PasskeyRepository.save`（Phase 1.5）が担当。
  - 私鍵表現は `rawRepresentation`（32B スカラ）を `SavePasskeyRequest.privateKey` に格納。assertion 側は
    `loadPrivateKey` で取得 → `P256.Signing.PrivateKey(rawRepresentation:)` で復元。
  - **assertion は OS 提供の `clientDataHash` で署名**（clientDataJSON を自作しない）。署名対象
    `authenticatorData ‖ clientDataHash` を CryptoKit `signature(for:)`（内部 SHA-256→ECDSA、ES256 等価）
    に渡し、`derRepresentation`（ASN.1 DER）を返す（iOS `ASPasskeyAssertionResponse` は DER 受領）。
  - 登録 JSON（`registrationResponseJson`）は不要（iOS は `ASPasskeyRegistrationCredential`＝attestationObject
    ＋OS clientDataHash。Phase 5 coordinator で組む）。
- 署名は ECDSA の乱数 nonce のため非決定的 → テストは**署名の検証可能性**を確認（exact bytes は固定しない）。
  登録バイト（AAGUID/flags 0x45/COSE 配置/attestation framing）と authData(37B, flags 0x05) は固定。
- `ServiceLocator.passkeyCreator` を配線（assertion は stateless enum `PasskeyAssertion` を直接利用）。

## Mac 検証項目（実機/Sim で確認）

1. `xcodegen generate` → KeyNestKit / KeyNestKitTests のコンパイル通過（GRDB 6.29 SPM 解決）。
2. テスト green:
   - Phase 1: `AesGcmCipherTests` / `EncryptedCustomFieldsCodecTests` / `DataKeyProviderTests` /
     `AppDatabaseTests` / `CredentialRepositoryTests` / `PasskeyRepositoryTests`。
   - Phase 2: `SaveUpdateCredentialUseCaseTests` / `UnlockVaultUseCaseTests` / `ClearVaultUseCaseTests` /
     `CredentialObservationUseCaseTests` / `GetDeviceLockStatusUseCaseTests` / `VaultStorageMeasurerTests`。
   - Phase 2.4/2.5: `WebAuthnByteLayoutTests`（CBOR/COSE/authData/attestation）/ `Base64URLTests` /
     `PasskeyCreatorTests` / `PasskeyAssertionTests`。
3. **実機**: `KeychainDataKeyStore` の SE 鍵生成・ECIES seal/open（Sim は
   `SecureEnclave.isAvailable == false` で fallback 経路を通る）。`BiometricAuthenticator` の LAContext 評価も実機。
4. Keychain access group 共有（app ↔ extension で同一封緘 DEK を読めること）— 両ターゲットの
   entitlements 配線後に確認。
5. CryptoKit / Security / os / GRDB / LocalAuthentication は `APPLICATION_EXTENSION_API_ONLY = YES` 下で利用可。
6. **GRDB API バージョン確認**（6.29 想定で記述。差異あれば調整）: `TableDefinition.primaryKey(_:_:)` /
   `Database.create(index:on:columns:options:)`（`IndexOptions.unique`）/ `any DatabaseWriter` 上の
   async `read`/`write` / `MutablePersistableRecord.didInsert(_:)`（`InsertionSuccess.rowID`）/
   `ValueObservation.tracking(_:)` ＋ `values(in:)`（async stream ブリッジ）。
7. WAL × App Group のプロセス間共有（アプリ suspend 中ロック保持時の `0xDEAD10CC` 回避は後続フェーズで
   必要なら GRDB の suspension 連携を配線）。
8. observe 系テストは ValueObservation の初回 emission をスケジューラ（既定 main queue）経由で受ける。Mac で
   ハングしないこと（`.values(in:)` の scheduling 既定で問題なければ可）。
9. CryptoKit P256: `P256.Signing.PrivateKey().rawRepresentation`(32B) / `publicKey.rawRepresentation`(64B) /
   `signature(for:)`→`derRepresentation` / `ECDSASignature(derRepresentation:)` / `isValidSignature(_:for:)`。
   実 RP（例 webauthn.io）での登録/認証は Phase 5 の拡張 coordinator 完成後に手動確認。

## Phase 3.1 SwiftUI 基盤 — 完了

### 3.1 共通基盤
- `KeyNest/KeyNestApp.swift`（`@main`）。`ServiceLocator.makeShared()` を `WindowGroup` 下の `.task`
  で起動し、成功時 `RootView`、失敗時 `StartupErrorView` を出す（Android `Application.onCreate` 等価。
  初期化エラーは画面で表面化し、サイレント degraded UI は出さない）。
- `KeyNest/UI/Root/RootView.swift`: `NavigationStack` ＋ 右上 Settings 遷移。Credential List /
  Settings は Phase 3.2 / 3.4 で差し替える `PhaseStubView` を仮配置（ナビゲーショングラフ＆テーマの
  end-to-end ビルド確認用）。
- **テーマ**: `KeyNest/UI/Theme/KNColor.swift`（Android `values{,-night}/colors.xml` の **semantic
  layer のみ**を `UIColor(dynamicProvider:)` で 1 ファイル化）/ `KNFont.swift`（Manrope ＋ JetBrains Mono、
  `Font.custom(PostScriptName, relativeTo:)` で Dynamic Type 連動）。Asset Catalog を持たない方針＝
  すべて Swift コードで text-reviewable。raw palette は移植しない（必要な時に追加）。
- **フォント**: `KeyNest/Resources/Fonts/{Manrope-Regular,Medium,SemiBold,Bold,JetBrainsMono-Regular}.ttf`
  を Android `res/font/` から流用。`Info.plist` `UIAppFonts` に登録済み。PostScript 名はファイル名
  と一致（`fontTools` 互換スクリプトで確認済み）。OFL ライセンス本文は Phase 6 OSS 画面で同梱。
- **StrengthBar**: `KeyNest/UI/Components/StrengthBar.swift`。Android `widget/StrengthBar.kt` の SwiftUI
  港。3 セグメント `14×4 pt` / gap `2 pt` / corner = height/2。`weak`→1/`medium`→2/`strong`→3 を塗り、
  残りは `KNColor.borderStrong` のトラック。Android の `null → GONE` 等価は **呼び出し側で `if let`
  ガード**して View を生成しない（SwiftUI 慣用）。
- **XcodeGen**: `KeyNest/Resources/Fonts/*.ttf` は `KeyNest` ターゲットの `sources` 配下にあるため
  自動で Copy Bundle Resources に入る。ビルド成果物 `KeyNest.app/*.ttf` で確認済み。

## Phase 3.2 Credential List — 完了

### 3.2 一覧画面
- `KeyNest/UI/List/CredentialListViewModel.swift`（`@MainActor` + `@Observable`）。Android の
  `CredentialListViewModel` から **署名フィルタ** と **PassKey 行のマージ** を落とした最小ポート:
  - 署名フィルタは iOS 設計から除外（design Non-Goals: パッケージ署名照合を作らない）。
  - PassKey 行は List に混ぜず、Settings / 専用画面で扱う方針。Req 7.1 はパスワード一覧の検索/ソート/
    最近使った/空状態/複製/削除を要求しており、本 commit でその範囲を満たす。
- **観測モデル**: 主リストは `ListCredentialsUseCase` を `.task(id: vm.sort)` で再購読し、sort 変更時に
  ストリームを再起動する（Kotlin `flatMapLatest` 等価）。Recently used は独立した `.task` で観測。
  ViewModel 側の `for try await` ループは `CancellationError` を catch して再起動を許可。
- **純粋ヘルパ**: `applySearch`（label/username/serviceIdentifier の case-insensitive contains。
  Android `applySearch` を踏襲し、`packageName` → `serviceIdentifier`）と `computeEmptyKind`
  （`.initial` = vault が空 ＆ query 空、`.noMatch` = query 非空で intersection が空）を `static` で
  公開。後の UI テスト target 整備時にここをそのまま検証する想定。
- `KeyNest/UI/List/CredentialListView.swift`: `.searchable` ＋ ソート `Menu`、Recently used 水平
  カルーセル、空状態 View、leading swipe で複製・trailing swipe で `confirmationDialog` 削除確認。
  リストの背景は `KNColor.bg`（`scrollContentBackground(.hidden)` + 自前 background）。
- 失敗フィードバックは `ActionMessage`（`Identifiable`）＋ `.alert(item:)`。例外型名のみ surface
  （NFR 1.1: plaintext を露出しない）。

### 確認したい論点
- Recently used を `query` 入力中は隠す挙動（Android は常時表示）。検索集中度を上げるため iOS では
  query 非空時に Section を畳む。要レビュー。
- 複製ボタンは leading swipe（青）／削除は trailing（赤）。iOS では trailing destructive がHIG。
  Android の long-press メニュー UI は採用せず、HIG 寄せ。

## Phase 3.3 Credential Edit — 完了

### 3.3 編集画面
- `KeyNest/UI/Edit/CredentialEditViewModel.swift`（`@MainActor` + `@Observable`）。`Mode` で
  new/edit を分岐:
  - **new**: `loadIfNeeded()` は no-op、空フォームで Save → `SaveCredentialUseCase`。
  - **edit**: `loadIfNeeded()` で `BiometricAuthenticating.authenticate` → 成功時のみ
    `UnlockVaultUseCase` で復号 → `PlaintextCredential` をフィールドへ写経。
    cancelled / failed / unavailable は `LoadPhase` 経由で View にリトライ CTA を出す（Req 4.2:
    平文を sealed のままで戻す）。
  - 保存は `UpdateCredentialUseCase`。**password 文字列が編集前と同一なら `newPassword: nil`**
    で渡して既存 ciphertext/IV を温存（"edit metadata only" 時に decrypt/re-encrypt を回避）。
- **`PlaintextCredential` の寿命**: `loadedPlaintext` を `@ObservationIgnored` で保持し、ViewModel
  破棄時 ARC で `deinit` → `close()` がバッファをゼロ消去。新しい平文ロード時は古い側を
  `close()` してから差し替え（NFR 1.1 / Req 4.3）。
- **重複検出**: `serviceIdentifier` / `username` 変更時に 250 ms debounce で背景 lookup
  （`repository.findByServiceIdentifier(...)` → username の case-insensitive 一致を `edit` 時は
  自身を除外）。検出は **保存をブロックせず** 警告バナーのみ（Android パリティ）。
- **カスタムフィールド**: `EditableCustomField`（`UUID` Identifiable）配列で 1〜10 を View 側で
  クランプ。`Add custom field` は `canAddCustomField` で `disabled`。Save 時 trim 空行を除去。
- **削除**: `BiometricAuthenticating.authenticate` ＋ `confirmationDialog` の二段階（Req 4.1 destructive
  vault action）。
- **複製**: edit モードでのみ実行、結果の新 id を `dismissTo` に書いて List に戻す。`Duplicate`
  use case は ciphertext 温存なので生体プロンプト不要。

### View / 統合
- `KeyNest/UI/Edit/CredentialEditView.swift`: `Form` ベース、Sections = Identity / 警告 / Custom
  fields / Actions / Error。パスワードは `SecureField` / `TextField` を `passwordVisible` で
  切替（reveal は **既に生体認証済の状態でのみ可能**＝Req 4.1 を画面遷移時にゲート）。
  `.privacySensitive()` を password / custom field 行に付け、スイッチャ / スクショ時のリダクション
  に乗せる（Req NFR 1.2 の先取り）。LoadPhase で `LoadingView` / `LoadRetryView` を出し分け。
- `CredentialListView` を更新: toolbar に `+` の `NavigationLink → CredentialEditView(mode: .new)`、
  行は `NavigationLink → CredentialEditView(mode: .edit(id))` でラップ。スワイプ複製/削除は維持。

### Domain Picker は Phase 4 へ持ち越し
- Android `PackagePickerBottomSheet` の iOS 等価は **「過去 serviceIdentifier 候補リスト」 sheet**
  を想定しているが、正規化 `ServiceIdentifierMatcher`（Phase 4.1）が無いと候補抽出仕様が定まらない
  ため意図的に持ち越し。3.3 では URL TextField 直接入力で運用可。

### 確認したい論点
- パスワード reveal はロード時の生体認証 1 回で permitted する設計。reveal 毎に再認証する方が
  安全という考え方もある（Android はアプリ層ゲートで初回のみ）。要レビュー。
- 重複検出を非ブロッキング警告にした点（Android パリティ）。Save 経路で hard block する選択肢もある。
- Custom fields の key/value 順を保つために `UUID` を Identifiable に使った。Save 時は順序維持。

## Phase 3.4 Settings — 完了

### 3.4 設定画面
- `KeyNest/UI/Settings/SettingsViewModel.swift`（`@MainActor` + `@Observable`）。情報源:
  - `ObserveVaultMetadataUseCase`: `count` + `latestUpdatedAt` を `.task` で常時購読。メタデータが
    変わるたびに `GetVaultStorageUsageUseCase` を await で再測（行追加/削除で WAL も変動するため
    snapshot 単体だと取りこぼす）。
  - `GetDeviceLockStatusUseCase`: LAContext snapshot。`scenePhase == .active` で再サンプル。
  - **AutoFill 状態**: `ASCredentialIdentityStore.shared.state()` を await。`scenePhase` で再サンプル
    （ユーザーは Settings.app からトグルしてアプリに戻る動線）。
  - **PassKey provider 状態**: `#available(iOS 17, *)` で `.unsupported` を弾き、それ以外は AutoFill
    有効値をミラー。design `PasskeyProviderStatus` の 3 値に正規化。
- `KeyNest/UI/Settings/SettingsView.swift`: `Form` の Sections = AutoFill / Security / Vault /
  About / Danger Zone。autofill 無効時は `UIApplication.openSettingsURLString` への deeplink
  ボタンを footer 説明文と一緒に出す（iOS は AutoFill トグルへの直接遷移は不可、Req 7.5 と同方針）。
  OSS と Danger Zone は `PlaceholderView`＋ `NavigationLink` で配線、中身は Phase 3.5 で実装。
- `CredentialListView` の `topBarLeading` に Settings 入口（歯車）を追加。

### 注意点
- **`Section("title") { ... }` の string-title overload が Form コンテキストで Swift 6 の overload
  解決にひっかかる**ことがある（Xcode 17 / iOS 17 SDK）。本ファイルでは `Section { content } header: { Text("…") }`
  の明示形に統一。string-title 形は短いが解決不能エラー時の診断が分かりにくいので明示形を採用。
- `ASCredentialIdentityStore.state()` は `state.isEnabled` のみ使用。`supportsIncrementalUpdates` 等は
  Phase 4 の IdentityStore sync 配線時に再評価。

### 確認したい論点
- AutoFill 状態の再サンプル頻度を `scenePhase` 1 拍のみにした点。タイマー化 / NotificationCenter 監視
  も選べるが Settings 画面でしか参照しないため最小化。
- PassKey 状態を AutoFill ミラーで導出した点（実際は `ASCredentialIdentityStore` の細粒度 API は
  iOS 17 でも passkey 個別 toggle を返さない）。

## Phase 3.5 Danger Zone + OSS — 完了

### 3.5 Danger Zone
- `KeyNest/UI/Danger/DangerZoneViewModel.swift`（`@MainActor` + `@Observable`）。Android
  `DangerZoneViewModel` の **strict 状態機械** を踏襲:

      idle ──tap──▶ authenticating ──succeeded──▶ confirming ──confirm──▶ clearing ──ok──▶ cleared
                          │                            │                      │
                     cancel/fail                    cancel                 failure
                          ▼                            ▼                      ▼
                     idle / failed                   idle                   failed

  `.clearing` は **`.confirming` からのみ** 到達でき、`.confirming` は **生体認証成功からのみ**
  到達できる。`startClearFlow()` で transition の起点をガード（idle/failed/cleared 以外は no-op）。
- `KeyNest/UI/Danger/DangerZoneView.swift`: Phase ごとに `statusLabel`（authenticating /
  clearing / cleared / 通常）と footer メッセージ（cleared / failed）を出し分け。
  `phase == .confirming` で `confirmationDialog` を表示し、ここでのみ
  `ClearVaultUseCase` を発射する経路を提供。

### 3.5 OSS Licenses
- `KeyNest/UI/Oss/OssEntry.swift`: `OssEntry`（name / license / url? / summary）。`OssLicenses.entries`
  に Manrope（OFL 1.1）、JetBrains Mono（OFL 1.1）、GRDB.swift（MIT）の最低 3 件。
  **ライセンス全文の bundle は Phase 6 にずらした**: 現状は短いサマリ + canonical URL への
  `Link` で代用。Phase 6 でローカライズと一緒に `.txt` 同梱を再評価。
- `OssLicensesView.swift`: `List` + `Link`。expandable accordion（Android 等価）は OS の
  reader-style overlay があるため SwiftUI ではコンパクト表示で十分と判断。
- `SettingsView` の OSS / Danger placeholder を本物 View へ差し替え、`PlaceholderView` を削除。

### 確認したい論点
- OSS 全文の bundle 遅延（現状 URL リンク）。App Store 配布前にライセンス全文の同梱が必要なら
  Phase 6 で `.txt` リソース化。
- Danger Zone の `.cleared` 後の遷移: 現状は同画面に「Vault cleared」表示のみ。List 画面へ
  pop する自動遷移にした方が UX 上明快かもしれない（要レビュー）。

## Phase 3.6 Onboarding — 完了 ／ Phase 3 完走

### 3.6 初回ガイダンス
- `KeyNest/UI/Onboarding/OnboardingViewModel.swift`（`@MainActor` + `@Observable`）。
  `ASCredentialIdentityStore.state()` を `.task` ＋ `scenePhase == .active` で再サンプル
  （Android `onResume` 等価）。Settings.app への往復後に "AutoFill is enabled" カードが即時
  反映される。
- `OnboardingView.swift`: welcome ＋ AutoFill 状態カード ＋ 3 ステップガイド ＋
  PassKey 状態カード ＋ footer の "Open Settings" deeplink。AutoFill 有効化を検知すると CTA が
  "Continue" に切り替わり、未有効時は "Skip for now" で先送り可能（Req 7.5 のガイド責務であり
  ブロックではない）。
- **完了状態の永続化**: `KeyNestApp` 側 `@AppStorage("onboardingComplete")` を 1 回 true に立てる
  だけ。`UserDefaults` (App Group ではない standard) を採用＝拡張からは見ず、本体アプリの初回
  UX のみを制御。Danger Zone で vault clear しても再表示しない（onboarding はガイドであって
  vault 状態と独立、Android 同方針）。

### 確認したい論点
- iOS 17 では PassKey provider 状態 = AutoFill ミラーで運用。Apple は passkey 個別 toggle API を
  公開していないため、これが妥当な近似。

## Phase 3 完了サマリ
- 3.1 共通基盤（@main、Theme、Fonts、StrengthBar）
- 3.2 Credential List（検索 / ソート / 最近使った / 空状態 / swipe）
- 3.3 Credential Edit（new / edit、biometric ゲート、custom fields ≤ 10、重複検出）
- 3.4 Settings（autofill / lock / vault metadata / passkey）
- 3.5 Danger Zone（生体 → 確認 → ClearVault）＋ OSS Licenses
- 3.6 Onboarding（AutoFill 有効化導線 + PassKey status）
- 既存 KeyNestKitTests 80 件は緑のまま維持。UI フローは Sim/実機での目視確認が次の検証ステップ。

## 次フェーズ
- Phase 4（AutoFill 拡張 — パスワード）。`ServiceIdentifierMatcher` の正規化規則確定 →
  Edit 画面の Domain Picker sheet を後追い装着 → `CredentialIdentityStoreSync` →
  `CredentialProviderViewController`。
- Phase 4（AutoFill 拡張 — パスワード: `ServiceIdentifierMatcher` / `CredentialIdentityStoreSync` /
  `CredentialProviderViewController`）。serviceIdentifier の正規化はここで実装（UseCase 側は現状 blank チェックのみ）。
- Phase 5（AutoFill 拡張 — PassKey: 登録 / assertion coordinator。`PasskeyCreator` / `PasskeyAssertion` を
  `ASCredentialProviderViewController` 経路に載せる）。

## Feature Flag
- 本リポジトリは Feature Flag Protocol = **opt-out**。active flag は無し。

# App Store Metadata — KeyNest

App Store Connect 用のテキスト素材。**英 (Primary) + 日 (Localization)** の
2 言語を用意。文字数制限は App Store Connect 仕様に合わせて切り詰め済み。

実際の登録時はそのままコピペで OK。

---

## App Name（30 文字以内）

| 言語 | 値 | 文字数 |
|---|---|---|
| EN | `KeyNest — Offline Vault` | 23 |
| JA | `KeyNest — オフライン保管庫` | 14 |

## Subtitle（30 文字以内）

| 言語 | 値 | 文字数 |
|---|---|---|
| EN | `Passwords & Passkeys, on device` | 30 |
| JA | `パスワードとパスキーを端末内で管理` | 17 |

## Promotional Text（170 文字以内）

> 後から審査なしで更新可能なテキスト。新機能告知などに使う。

| 言語 | 値 |
|---|---|
| EN | `Your passwords and passkeys live on this device. Nothing is uploaded, nothing is tracked, nothing is shared. Fill them anywhere with iOS AutoFill.` |
| JA | `パスワードとパスキーは、すべてこの端末の中だけ。送信もトラッキングも共有もありません。iOS の自動入力からどこでも呼び出せます。` |

## Description（4000 文字以内）

### EN

```
KeyNest is an offline-first password and passkey manager.

Your credentials live on this device, encrypted with AES-256-GCM. The
encryption key is wrapped by your iPhone or iPad's Secure Enclave, so it
never leaves secure hardware. KeyNest has no network code — there is no
server to breach, no analytics to leak, no third-party SDK to track you.

— What KeyNest does —

• Store passwords with custom fields (up to 10 per entry)
• Generate and store passkeys (iOS 17 or later) for sites that support them
• Fill credentials anywhere via iOS AutoFill — Safari, native apps, anywhere
  iOS shows the system AutoFill bar
• Unlock with Face ID / Touch ID / device passcode
• Search, sort and copy with a one-minute auto-clear clipboard
• On iPadOS, use a two-column layout with the list in the sidebar and the
  detail in the right pane

— What KeyNest doesn't do —

• No accounts, no sign-up, no cloud sync
• No advertising, no analytics, no telemetry
• No third-party SDKs, no embedded trackers
• No data collection of any kind

KeyNest is a single-device vault by design. If you replace the device or
factory reset, the vault is gone. That trade-off is the price of the
"nothing leaves the device" guarantee.

— Privacy —

Privacy policy: https://hitoshiichikawa.github.io/KeyNest-ios/privacy/
Open-source license inventory ships inside the app under Settings →
Open-Source Licenses.
```

### JA

```
KeyNest は、オフライン専用のパスワード／パスキー保管庫です。

資格情報はこの端末の中だけに保存され、AES-256-GCM で暗号化されます。
暗号化鍵は iPhone / iPad の Secure Enclave で封緘されるため、ハードウェアの
外には一切出ません。KeyNest は通信コードを持たず、サーバも分析基盤も
サードパーティ SDK も組み込まれていません。

— できること —

• パスワード保存（1 エントリにつきカスタムフィールド最大 10 個）
• パスキーの作成・保存（iOS 17 以降、対応サイト用）
• iOS の自動入力経由で、Safari やネイティブアプリのフォームへ入力
• Face ID / Touch ID / 端末パスコードでアンロック
• 検索・並び替え、コピー時は 60 秒で自動クリアされるクリップボード
• iPadOS では 2 カラム表示（サイドバーに一覧、右ペインに詳細）

— やらないこと —

• アカウント不要、登録不要、クラウド同期なし
• 広告・解析・テレメトリーなし
• サードパーティ SDK・埋め込みトラッカーなし
• いかなるデータも収集しません

KeyNest は単一端末で完結する設計です。端末を初期化・買い替えすると、保管庫の
データも失われます。これは「データが端末外に出ない」ことの引き換えです。

— プライバシー —

プライバシーポリシー: https://hitoshiichikawa.github.io/KeyNest-ios/privacy/
オープンソースライセンス一覧はアプリ内 設定 → オープンソースライセンス
からご覧いただけます。
```

## Keywords（100 文字以内、カンマ区切り）

| 言語 | 値 |
|---|---|
| EN | `password,passkey,vault,manager,autofill,offline,keychain,security,passwords,login` |
| JA | `パスワード,パスキー,保管庫,管理,自動入力,オフライン,キーチェーン,セキュリティ,ログイン` |

## What's New（4000 文字以内）

初回リリース用。

| 言語 | 値 |
|---|---|
| EN | `First release of KeyNest — an offline-only password and passkey manager that never sends your data anywhere.` |
| JA | `KeyNest の初回リリースです。完全オフラインでパスワードとパスキーを管理し、データを一切外に出さないシンプルな保管庫です。` |

## Support URL（必須）

> GitHub Issues を流用。

`https://github.com/hitoshiichikawa/KeyNest-ios/issues`

## Marketing URL（任意）

> 空でも審査は通る。GitHub Pages 公開時はそこを指す。

`https://hitoshiichikawa.github.io/KeyNest-ios/`

## Copyright

`© 2026 Hitoshi Ichikawa`

## Primary Category

`Productivity`

## Secondary Category

`Utilities`

## Age Rating（年齢制限）

`4+` — 暴力・成人向けコンテンツなし。

## Price

`Free` — 単価なし、In-App Purchase なし。

## App Store Review — Notes

> 審査員への補足説明欄に貼り付け（公開されない）。

### EN

```
KeyNest is an offline password / passkey vault.

Demo flow:
1. Launch the app. The Onboarding screen explains how to enable
   AutoFill in iOS Settings.
2. Tap "Skip for now" to reach the main vault screen.
3. Tap the + button (top-left in the sidebar on iPad, top-right on iPhone)
   to add a credential.
4. To test the AutoFill extension: Settings ▸ General ▸ AutoFill Passwords
   & Passkeys ▸ enable KeyNest. Then open Safari and trigger a login form.
5. To test the PassKey path (iOS 17+): use webauthn.io or any RP that
   offers passkey registration.

The app has no accounts, no sign-up, no network calls. Everything is
encrypted locally with AES-256-GCM. The data-encryption key is wrapped
by the Secure Enclave.

Contact: hitoshi.ichikawa@gmail.com
```

### JA

```
KeyNest はオフラインのパスワード／パスキー保管庫です。

デモ手順:
1. アプリ起動。オンボーディング画面で AutoFill の有効化方法を案内します。
2. 「あとで」をタップしてメイン画面へ。
3. + ボタン（iPad サイドバーの左上 / iPhone は右上）で資格情報を追加。
4. AutoFill 拡張の確認: 設定 ▸ 一般 ▸ パスワードとパスキーを自動入力
   ▸ KeyNest を有効化。その後 Safari でログインフォームを開く。
5. パスキーの確認 (iOS 17+): webauthn.io 等のサイトでパスキー登録。

アカウント不要、登録不要、ネットワーク通信なし。データは AES-256-GCM で
暗号化され、データ暗号化鍵は Secure Enclave で封緘されます。

連絡先: hitoshi.ichikawa@gmail.com
```

---

## チェックリスト（App Store Connect 登録時）

- [ ] アプリ名 / Subtitle（EN・JA）
- [ ] Promotional Text（EN・JA）
- [ ] Description（EN・JA）
- [ ] Keywords（EN・JA）
- [ ] What's New（EN・JA）
- [ ] Support URL
- [ ] Marketing URL（任意）
- [ ] Copyright
- [ ] Primary / Secondary Category
- [ ] Age Rating
- [ ] Price = Free / 配信地域 = 全世界
- [ ] **App Privacy** = "Data Not Collected"
- [ ] **Review Notes**（EN・JA）
- [ ] スクリーンショット（iPhone 6.7" + iPad 13"）
- [ ] App Icon は 1024×1024（asset catalog から自動）
- [ ] プライバシーポリシー URL（後述）

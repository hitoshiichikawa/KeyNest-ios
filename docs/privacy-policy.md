---
title: KeyNest — Privacy Policy
permalink: /privacy/
---

# Privacy Policy

_Last updated: 2026-06-04_

KeyNest ("the app") is an offline-first password and passkey manager
developed by Hitoshi Ichikawa ("the developer"). This page describes
exactly what the app does — and does not do — with your data.

## TL;DR

- The app does **not collect any personal data**.
- The app does **not send anything to the developer or to any third party**.
- The app does **not use analytics, tracking, advertising or third-party SDKs**.
- All data stays on **this device**.

If you would prefer a structured summary in the App Store privacy
"nutrition label" format, the answer is the **single category**
"**Data Not Collected**".

## What the app stores

The following data is created by you while using KeyNest, and is stored
on this device only:

- Saved login credentials (label, target domain / service identifier,
  username, password, custom fields).
- Saved passkeys (relying party id, user handle, user name, the
  private key, sign count metadata).
- A "vault metadata" snapshot (credential count, last-update
  timestamp, storage usage) derived from the items above.
- A single boolean flag noting whether you have finished the
  first-run onboarding screen.

The credentials, passkey private keys and custom field values are
encrypted at rest with **AES-256-GCM**. The encryption key is wrapped
by the device's **Secure Enclave** (or, on devices without one, stored
in the device-only Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`).

## Where the data lives

- The SQLite database file resides inside the app's **App Group
  container** on this device. It is accessible to KeyNest and its
  bundled AutoFill extension only.
- The encryption key material lives in the **iOS Keychain** with the
  `ThisDeviceOnly` attribute set, so it is **not synced through iCloud
  Keychain**.
- No copy of any of the above ever leaves the device.

## What the app does NOT do

- No accounts, no sign-up, no email collection.
- No cloud sync. Not even an opt-in toggle for it.
- No third-party SDKs (analytics, crash reporters, ads, attribution,
  social logins, etc.).
- No outbound network calls. The app does not contain HTTP / DNS /
  socket code paths in the vault read/write, encryption, AutoFill or
  passkey flows.

## AutoFill extension

When you tap a KeyNest entry from the iOS AutoFill bar in another app
(e.g. Safari, or a third-party app), the system invokes the KeyNest
AutoFill extension. The extension:

- Reads the local encrypted vault that the host app already wrote.
- Asks iOS to run a Face ID / Touch ID / passcode check.
- Decrypts the requested credential in memory only and hands the
  resulting username + password back to iOS, which fills the focused
  form.
- Wipes the decrypted bytes from memory after use.

iOS — not KeyNest — controls which app receives the credential. The
AutoFill extension does not log, transmit, or persist anything beyond
the local vault.

## Permissions

- **Face ID / Touch ID / passcode**: requested at the OS level when
  you reveal a stored password, fill a credential, or run the "clear
  vault" action.
- **AutoFill Credential Provider** entitlement: required for the app
  to appear in the system AutoFill bar. You enable / disable this in
  iOS Settings ▸ Passwords ▸ AutoFill Passwords & Passkeys.

No other entitlements (location, camera, contacts, etc.) are
requested.

## Children's privacy

KeyNest does not knowingly collect any data from any user — including
children — because it does not collect data from anyone.

## Changes to this policy

If the policy changes, this page will be updated with a new
"Last updated" date. The git history of
[the repository](https://github.com/hitoshiichikawa/KeyNest-ios)
shows every change.

## Contact

For questions about this policy or the app, contact
**hitoshi.ichikawa@gmail.com** or open an issue at
<https://github.com/hitoshiichikawa/KeyNest-ios/issues>.

---

## 日本語版

_最終更新: 2026-06-04_

KeyNest（以下「本アプリ」）は、市川仁（以下「開発者」）が開発する
オフライン専用のパスワード／パスキー保管庫です。本ページでは、本アプリが
あなたのデータをどのように扱うか — そして **扱わないか** — を明示します。

### 要点

- **個人データを一切収集しません。**
- 開発者やサードパーティに **何も送信しません**。
- 解析・トラッキング・広告・サードパーティ SDK を **一切利用しません**。
- すべてのデータは **この端末内のみ** に保存されます。

App Store のプライバシー「栄養ラベル」表記では、該当区分は **「Data Not
Collected（データ収集なし）」** の 1 カテゴリのみです。

### 本アプリが保存するもの

利用中にあなたが入力した以下のデータが、この端末内のみに保存されます:

- 保存された資格情報（ラベル、対象ドメイン／サービス識別子、ユーザー名、
  パスワード、カスタムフィールド）。
- 保存されたパスキー（Relying Party ID、ユーザーハンドル、ユーザー名、
  秘密鍵、署名カウンター等）。
- 上記から派生する「ボルトメタデータ」（資格情報の件数、最終更新日時、
  ストレージ使用量）。
- 初回オンボーディング画面を完了したかどうかを示すブール値 1 個。

資格情報・パスキー秘密鍵・カスタムフィールド値は、保管時に
**AES-256-GCM** で暗号化されます。暗号化鍵は端末の **Secure Enclave**
で封緘されます（非搭載端末では `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
属性付きで Keychain に保存）。

### データの保存場所

- SQLite データベースファイルは、端末内の **App Group コンテナ**に
  あります。KeyNest 本体アプリと同梱の AutoFill 拡張機能だけがアクセス
  可能です。
- 暗号化鍵は `ThisDeviceOnly` 属性付きで **iOS Keychain** に保存される
  ため、**iCloud Keychain には同期されません**。
- 上記のいずれも、端末外に出ることはありません。

### 本アプリが「やらない」こと

- アカウント・新規登録・メールアドレス収集 — 一切なし。
- クラウド同期 — オプトインのトグルも存在しません。
- サードパーティ SDK（解析・クラッシュレポート・広告・アトリビューション
  ・ソーシャルログイン等）— 一切なし。
- 外部ネットワーク通信 — 資格情報の読み書き、暗号化、自動入力、パスキー
  経路に HTTP/DNS/Socket のコードパスが存在しません。

### AutoFill 拡張機能について

他のアプリ（Safari やサードパーティアプリ等）で iOS の AutoFill バーから
KeyNest を選んだ場合、システムが KeyNest の AutoFill 拡張機能を起動します。
拡張機能の処理は以下の通り:

- 本体アプリが書き込んだローカルの暗号化ボルトを読みます。
- iOS に Face ID / Touch ID / パスコード認証を依頼します。
- 要求された資格情報をメモリ上のみで復号し、ユーザー名 + パスワードを
  iOS に渡します。iOS が対象フォームに入力します。
- 使用後、復号バイト列はメモリから直ちにゼロ消去されます。

どのアプリに資格情報を渡すかは **KeyNest ではなく iOS が制御** します。
拡張機能は、ローカルボルトに対する読み書き以外に、ログ・送信・永続化を
一切行いません。

### パーミッション

- **Face ID / Touch ID / パスコード**: パスワード表示、自動入力、ボルト
  消去などの操作時に OS レベルで要求されます。
- **AutoFill Credential Provider** エンタイトルメント: システム自動入力
  バーに KeyNest が表示されるために必要です。 設定 ▸ パスワード ▸
  パスワードとパスキーを自動入力 から有効／無効を切り替えられます。

その他のエンタイトルメント（位置情報、カメラ、連絡先など）は要求しません。

### 児童のプライバシー

本アプリは、子供を含むいかなる利用者からもデータを収集しません
（そもそも誰からも収集しないため）。

### ポリシーの変更

ポリシーが変更された場合、本ページの「最終更新」日付が更新されます。
すべての変更履歴は
[リポジトリの git 履歴](https://github.com/hitoshiichikawa/KeyNest-ios)
に記録されます。

### お問い合わせ

本ポリシーまたは本アプリに関するご質問は、
**hitoshi.ichikawa@gmail.com** または
<https://github.com/hitoshiichikawa/KeyNest-ios/issues>
までお寄せください。

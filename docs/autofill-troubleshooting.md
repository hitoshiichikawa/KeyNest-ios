# AutoFill — トラブルシューティング & FAQ

iOS の自動入力は **ドメイン** だけで判定されます。Android のように「Bundle ID
で個別のアプリにひも付ける」概念はありません。本ドキュメントは「何を入れれば
自動入力が動くか」「動かない場合に何を確認するか」をまとめたものです。

## Service identifier には何を入れる?

| 自動入力したい先 | 入れる値 | 例 |
|---|---|---|
| Web サイト（Safari など） | **そのサイトのドメイン** | `github.com`, `apple.com` |
| ネイティブアプリ | **そのアプリの公式 web サイトのドメイン** | `slack.com`, `x.com`, `amazon.co.jp` |

KeyNest は入力された URL を自動で正規化します
（`https://www.GitHub.com/login` → `github.com`）。

## なぜアプリの Bundle ID ではないのか?

iOS の AutoFill は OS 内部で **Associated Domains**（`webcredentials:`）という
仕組みでアプリと web ドメインを紐付けます。アプリ側が自分の公式 web サイトを
"これは自分です" と Apple に登録しているので、ユーザー / パスワードマネージャ
側はその **web ドメインを保存しておけば良い**、という設計です。

そのため：

- ユーザーが Bundle ID（`com.tinyspeck.slackmacgap` のような長い ID）を意識する
  必要はありません。
- 公式 web サイトのドメインを保存しておけば、Safari でもアプリでも同じエントリで
  自動入力が動きます。
- パスワードマネージャ間（KeyNest / 1Password / Bitwarden / Apple Keychain）でも
  この点は **同じ**です。みんな同じ iOS API を使っています。

## アプリのドメインを調べる方法

「このアプリってどの web サイトと紐付いているの?」を確認する手段：

### 1. 公式 web サイトを開く（一番楽）

App Store のアプリ詳細 ▸ "開発者の Web サイト" を開く。多くの場合、その
ドメインが Associated Domain です。

### 2. Smart App Banner を見る

Safari でその web サイトを開いて、画面上部に "アプリで開く" バーが出れば、
そのドメインとアプリが関連付けられている証拠です。

### 3. AASA ファイルを直接見る（確実）

ターミナルから：

```bash
curl -s https://slack.com/.well-known/apple-app-site-association | jq .webcredentials
# → { "apps": ["TEAMID.com.tinyspeck.SlackMacGap", ...] }
```

`webcredentials.apps` に Bundle ID が並んでいれば、そのドメインで自動入力が動きます。

### 4. 設定 ▸ パスワード で試す

仮の credential を KeyNest に入れて、対象アプリを開いてみる。Quick Type bar に
KeyNest の候補が出れば成功です。

## 自動入力候補が出てこない

1. **設定 ▸ パスワード ▸ パスワードを自動入力 で KeyNest がオンか確認**
2. **アプリ側が Associated Domains を宣言しているか確認**（前項）。
   宣言していないアプリには **OS 側から自動入力経路が一切提供されません**。
   これは iOS の仕様で、KeyNest を含むどのパスワードマネージャでも同じです。
3. **入力したドメインが正しいか確認**。`apple.com` に保存していて `icloud.com`
   のフォームを開いても自動入力は出ません（サブドメイン違いも別扱い）。
4. KeyNest を一度終了して再起動。`CredentialIdentityStoreSync` が起動時に
   reconcile します。

## サブドメインの扱い

`m.example.com` と `example.com` は KeyNest 上では **別エントリ** です。これは
look-alike 攻撃（`m.example.com.attacker.com` のような偽装）を防ぐための仕様で、
Apple Keychain 等も同じ判定です。

両方で使う場合は、片方を保存後 **複製** メニューで複製し、ドメインだけ書き換えて
ください。

## OS のバージョン要件

- パスワード自動入力: iOS 17+
- PassKey 登録 / 認証: iOS 17+

iOS 16 以下では PassKey 経路は表示されません（Settings の PassKey 行は
"Requires iOS 17" 表示になります）。

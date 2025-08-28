# Amazon Connect Bedrock Helpdesk PoC

Amazon Connect と Amazon Bedrock を活用した自動応答サポートヘルプデスクシステムのPoCです。

## 概要

このプロジェクトは、レジシステムのサポートを想定した電話自動応答システムを構築します。お客様からの電話による問い合わせに対して、ナレッジベースに基づいた自動回答を提供します。

## 主な機能

- 🎙️ 音声による問い合わせの自動応答
- 🧠 Amazon Bedrock を使用したAI回答生成
- 📚 ナレッジベースによる情報管理
- 📊 通話品質とパフォーマンスの監視
- 🔄 マルチ環境対応（debug/staging/production）

## アーキテクチャ

```
User → Amazon Connect → Lambda → Bedrock Knowledge Base
                     ↓
                Amazon Polly → 音声回答
```

## 必要な環境

- AWS アカウント
- AWS CLI 設定済み
- Python 3.9+
- 適切なIAM権限

## セットアップ

### 1. 開発環境の準備

```bash
# リポジトリのクローン
git clone https://github.com/k-tanaka-522/awsAmazonConnectBedrock.git
cd awsAmazonConnectBedrock

# 開発環境のセットアップ
./scripts/setup-dev.sh
```

### 2. デプロイ

```bash
# デバッグ環境へのデプロイ
./scripts/deploy.sh -e debug

# ステージング環境へのデプロイ
./scripts/deploy.sh -e staging

# 本番環境へのデプロイ
./scripts/deploy.sh -e production
```

### 3. ナレッジベースデータのアップロード

```bash
./scripts/upload-knowledge-data.sh -e debug
```

### 4. Amazon Connectの設定

1. AWSコンソールでAmazon Connectインスタンスにアクセス
2. 電話番号を取得
3. Contact Flowに電話番号を関連付け

## テスト

```bash
# Connect インスタンス情報の確認
./scripts/test-connect.sh -e debug -i

# ログの確認
./scripts/test-connect.sh -e debug -l

# メトリクスの確認
./scripts/test-connect.sh -e debug -m
```

## プロジェクト構成

```
.
├── infrastructure/           # CloudFormationテンプレート
│   ├── main.yaml            # メインスタック
│   └── templates/           # ネストされたテンプレート
├── src/lambda/              # Lambda関数のソースコード
├── data/                    # ナレッジベースデータ
├── scripts/                 # デプロイ・運用スクリプト
├── tests/                   # テストコード
└── docs/                    # ドキュメント
```

## ナレッジベースの内容

現在、以下のレジシステムサポートに関するQ&Aが含まれています：

- 電源トラブル
- バーコード読み取り問題
- レシート印刷問題
- 釣り銭機エラー
- 売上データ確認
- システム再起動
- 商品登録
- 割引設定

## スタックの削除

```bash
# 環境を指定してスタックを削除
./scripts/deploy.sh -e debug -d
```

## 開発ガイドライン

- Python コードは `black` でフォーマット
- `flake8` でLintチェック
- テストは `pytest` を使用

## ライセンス

このプロジェクトはPoCとして作成されています。

## 貢献

問題や提案がある場合は、GitHubのIssueを作成してください。

---

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>
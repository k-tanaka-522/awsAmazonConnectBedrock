# デプロイメントガイド

## デプロイ手順

### 1. 初回デプロイ（段階的アプローチ）

CloudFormationテンプレートはネスト化されており、段階的にデプロイすることを推奨します。

#### Step 1: IAMロールとS3バケット

```bash
# main.yamlでIAMStackとStorageStackのみ有効化されている状態で実行
./scripts/deploy.sh -e debug
```

#### Step 2: ナレッジベースデータのアップロード

```bash
# S3バケットが作成されたらQ&Aデータをアップロード
./scripts/upload-knowledge-data.sh -e debug
```

#### Step 3: Lambda関数の追加

main.yamlで`LambdaStack`のコメントを外して：

```bash
./scripts/deploy.sh -e debug
```

#### Step 4: Amazon Connectの追加

main.yamlで`ConnectStack`のコメントを外して：

```bash
./scripts/deploy.sh -e debug
```

#### Step 5: モニタリングの追加

main.yamlで`MonitoringStack`のコメントを外して：

```bash
./scripts/deploy.sh -e debug
```

### 2. デプロイ確認

```bash
# スタック情報の確認
aws cloudformation describe-stacks --stack-name helpdesk-debug

# リソースの確認
aws cloudformation list-stack-resources --stack-name helpdesk-debug
```

### 3. Amazon Connect設定

1. AWSコンソール → Amazon Connect
2. `helpdesk-debug` インスタンスを選択
3. 電話番号の取得：
   - 「電話番号の管理」→「電話番号の取得」
   - 国：日本、タイプ：DID（Direct Inward Dialing）
   - 050番号を選択

4. Contact Flowの設定：
   - 「問い合わせフロー」→ 作成したフローを選択
   - 電話番号をContact Flowに関連付け

### 4. テスト実行

```bash
# Connect情報の確認
./scripts/test-connect.sh -e debug -i

# 取得した電話番号に電話をかけてテスト

# ログの確認
./scripts/test-connect.sh -e debug -l
```

### 5. スタックの削除

```bash
# 全リソースの削除
./scripts/deploy.sh -e debug -d
```

## トラブルシューティング

### S3バケットが削除できない場合

```bash
# バケットの中身を確認
aws s3 ls s3://helpdesk-knowledge-debug/

# 手動で削除
aws s3 rm s3://helpdesk-knowledge-debug/ --recursive
```

### CloudFormationスタックが削除できない場合

```bash
# スタックイベントを確認
aws cloudformation describe-stack-events \
  --stack-name helpdesk-debug \
  --query 'StackEvents[?ResourceStatus==`DELETE_FAILED`]'
```

### Connect インスタンスが作成できない場合

- リージョンがAmazon Connectをサポートしているか確認
- サービスクォータを確認（デフォルトは2インスタンス）

## 環境別の注意事項

### Debug環境
- コスト最小限の設定
- ログレベル: DEBUG
- 保持期間: 7日

### Staging環境
- 本番同等の構成
- ログレベル: INFO
- 保持期間: 7日

### Production環境
- 高可用性設定
- ログレベル: INFO
- 保持期間: 30日
- コスト予算: $100/月
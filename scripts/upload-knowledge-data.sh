#!/bin/bash

# ナレッジベースデータアップロードスクリプト

set -e

# 色付き出力用の設定
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 使用方法を表示
usage() {
    echo "Usage: $0 -e ENVIRONMENT [-p PROFILE] [-r REGION]"
    echo ""
    echo "Options:"
    echo "  -e, --environment ENV    環境名 (debug/staging/production) [必須]"
    echo "  -r, --region REGION      AWSリージョン (デフォルト: ap-northeast-1)"
    echo "  -p, --profile PROFILE    AWS CLIプロファイル (デフォルト: default)"
    echo "  -h, --help              ヘルプを表示"
}

# デフォルト値
REGION="ap-northeast-1"
PROFILE="default"

# オプション解析
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -e|--environment)
            ENVIRONMENT="$2"
            shift
            shift
            ;;
        -r|--region)
            REGION="$2"
            shift
            shift
            ;;
        -p|--profile)
            PROFILE="$2"
            shift
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# 必須パラメータのチェック
if [ -z "$ENVIRONMENT" ]; then
    echo -e "${RED}Error: 環境名が指定されていません${NC}"
    usage
    exit 1
fi

# S3バケット名
S3_BUCKET="helpdesk-knowledge-${ENVIRONMENT}"
S3_PREFIX="qa-data"

# データファイルの確認
DATA_FILE="data/qa-knowledge.json"
if [ ! -f "$DATA_FILE" ]; then
    echo -e "${RED}Error: データファイルが見つかりません: $DATA_FILE${NC}"
    exit 1
fi

echo -e "${GREEN}ナレッジベースデータをアップロード中...${NC}"
echo "環境: $ENVIRONMENT"
echo "S3バケット: s3://$S3_BUCKET/$S3_PREFIX/"
echo ""

# JSONファイルの検証
echo -e "${GREEN}JSONファイルを検証中...${NC}"
if ! python3 -m json.tool "$DATA_FILE" > /dev/null 2>&1; then
    echo -e "${RED}Error: JSONファイルが無効です${NC}"
    exit 1
fi

# S3バケットの存在確認
echo -e "${GREEN}S3バケットを確認中...${NC}"
if ! aws s3 ls "s3://${S3_BUCKET}" --profile "$PROFILE" --region "$REGION" &> /dev/null; then
    echo -e "${RED}Error: S3バケット '$S3_BUCKET' が存在しません${NC}"
    echo "先にCloudFormationスタックをデプロイしてください"
    exit 1
fi

# 既存ファイルのバックアップ
echo -e "${GREEN}既存データをバックアップ中...${NC}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PREFIX="${S3_PREFIX}/backup/${TIMESTAMP}"

# 既存ファイルがあればバックアップ
if aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/qa-knowledge.json" --profile "$PROFILE" --region "$REGION" &> /dev/null; then
    aws s3 cp "s3://${S3_BUCKET}/${S3_PREFIX}/qa-knowledge.json" \
              "s3://${S3_BUCKET}/${BACKUP_PREFIX}/qa-knowledge.json" \
              --profile "$PROFILE" \
              --region "$REGION"
    echo -e "${GREEN}バックアップ完了: s3://${S3_BUCKET}/${BACKUP_PREFIX}/qa-knowledge.json${NC}"
fi

# 新しいデータのアップロード
echo -e "${GREEN}新しいデータをアップロード中...${NC}"
aws s3 cp "$DATA_FILE" "s3://${S3_BUCKET}/${S3_PREFIX}/qa-knowledge.json" \
    --profile "$PROFILE" \
    --region "$REGION" \
    --content-type "application/json"

# メタデータファイルの作成とアップロード
echo -e "${GREEN}メタデータファイルを作成中...${NC}"
METADATA_FILE="/tmp/kb-metadata-${TIMESTAMP}.json"
cat > "$METADATA_FILE" << EOF
{
  "version": "1.0",
  "uploadedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "environment": "$ENVIRONMENT",
  "itemCount": $(jq '. | length' "$DATA_FILE"),
  "categories": $(jq '[.[].category] | unique' "$DATA_FILE"),
  "checksum": "$(sha256sum "$DATA_FILE" | cut -d' ' -f1)"
}
EOF

aws s3 cp "$METADATA_FILE" "s3://${S3_BUCKET}/${S3_PREFIX}/metadata.json" \
    --profile "$PROFILE" \
    --region "$REGION" \
    --content-type "application/json"

rm -f "$METADATA_FILE"

# アップロード確認
echo -e "${GREEN}アップロードを確認中...${NC}"
aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/" \
    --profile "$PROFILE" \
    --region "$REGION"

echo ""
echo -e "${GREEN}=== アップロード完了 ===${NC}"
echo ""
echo "アップロードされたファイル:"
echo "- s3://${S3_BUCKET}/${S3_PREFIX}/qa-knowledge.json"
echo "- s3://${S3_BUCKET}/${S3_PREFIX}/metadata.json"
echo ""

# Bedrock Knowledge Base同期の案内
echo -e "${YELLOW}次のステップ:${NC}"
echo "1. Bedrock Knowledge Baseが設定されている場合は、同期を実行してください"
echo "2. Lambda関数が新しいデータを使用することを確認してください"
echo ""
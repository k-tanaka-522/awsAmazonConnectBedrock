#!/bin/bash

# Amazon Connect Bedrock Helpdesk - デプロイスクリプト
# CloudFormation のパッケージングとデプロイを行うスクリプト

set -e

# 色付き出力用の設定
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 使用方法を表示
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -e, --environment ENV    環境名 (debug/staging/production) [必須]"
    echo "  -r, --region REGION      AWSリージョン (デフォルト: ap-northeast-1)"
    echo "  -p, --profile PROFILE    AWS CLIプロファイル (デフォルト: default)"
    echo "  -d, --delete            スタックを削除"
    echo "  -h, --help              ヘルプを表示"
    echo ""
    echo "Examples:"
    echo "  # ステージング環境にデプロイ"
    echo "  ./scripts/deploy.sh -e staging"
    echo ""
    echo "  # プロダクション環境にデプロイ (特定のプロファイルを使用)"
    echo "  ./scripts/deploy.sh -e production -p prod-account"
    echo ""
    echo "  # デバッグ環境のスタックを削除"
    echo "  ./scripts/deploy.sh -e debug -d"
}

# デフォルト値
REGION="ap-northeast-1"
PROFILE="default"
DELETE_MODE=false

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
        -d|--delete)
            DELETE_MODE=true
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

# 環境の妥当性チェック
if [[ ! "$ENVIRONMENT" =~ ^(debug|staging|production)$ ]]; then
    echo -e "${RED}Error: 無効な環境名: $ENVIRONMENT${NC}"
    echo "有効な環境名: debug, staging, production"
    exit 1
fi

# 変数設定
STACK_NAME="helpdesk-${ENVIRONMENT}"
TEMPLATE_FILE="infrastructure/main.yaml"
PACKAGED_TEMPLATE="infrastructure/packaged-${ENVIRONMENT}.yaml"
PARAMETERS_FILE="infrastructure/parameters/${ENVIRONMENT}.json"
S3_BUCKET="helpdesk-cfn-artifacts-${ENVIRONMENT}-${REGION}"

# AWS CLIの存在確認
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI がインストールされていません${NC}"
    echo "インストール方法: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
fi

# プロファイルの確認
echo -e "${GREEN}AWS プロファイルを確認中...${NC}"
if ! aws sts get-caller-identity --profile "$PROFILE" &> /dev/null; then
    echo -e "${RED}Error: AWS プロファイル '$PROFILE' が無効です${NC}"
    echo "aws configure --profile $PROFILE を実行してください"
    exit 1
fi

# アカウント情報の表示
ACCOUNT_INFO=$(aws sts get-caller-identity --profile "$PROFILE" --query 'Account' --output text)
echo -e "${GREEN}AWSアカウント: ${ACCOUNT_INFO}${NC}"
echo -e "${GREEN}リージョン: ${REGION}${NC}"
echo -e "${GREEN}環境: ${ENVIRONMENT}${NC}"

# 削除モードの場合
if [ "$DELETE_MODE" = true ]; then
    echo -e "${YELLOW}警告: スタック '${STACK_NAME}' を削除しようとしています${NC}"
    read -p "本当に削除しますか？ (yes/no): " -r
    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo -e "${GREEN}スタックを削除中...${NC}"
        
        # S3バケットの中身を空にする（バケットがある場合）
        KNOWLEDGE_BUCKET="helpdesk-knowledge-${ENVIRONMENT}"
        if aws s3 ls "s3://${KNOWLEDGE_BUCKET}" --profile "$PROFILE" --region "$REGION" 2>&1 | grep -q 'NoSuchBucket'; then
            echo "ナレッジベースバケットは存在しません"
        else
            echo -e "${YELLOW}ナレッジベースバケットを空にしています...${NC}"
            aws s3 rm "s3://${KNOWLEDGE_BUCKET}" --recursive --profile "$PROFILE" --region "$REGION"
        fi
        
        # CloudFormationスタックの削除
        aws cloudformation delete-stack \
            --stack-name "$STACK_NAME" \
            --profile "$PROFILE" \
            --region "$REGION"
        
        echo -e "${GREEN}削除を開始しました。進行状況を確認中...${NC}"
        aws cloudformation wait stack-delete-complete \
            --stack-name "$STACK_NAME" \
            --profile "$PROFILE" \
            --region "$REGION"
        
        echo -e "${GREEN}スタック '${STACK_NAME}' が正常に削除されました${NC}"
    else
        echo "削除をキャンセルしました"
    fi
    exit 0
fi

# デプロイモード
echo -e "${GREEN}=== CloudFormation デプロイを開始します ===${NC}"

# テンプレートファイルの存在確認
if [ ! -f "$TEMPLATE_FILE" ]; then
    echo -e "${RED}Error: CloudFormationテンプレートが見つかりません: $TEMPLATE_FILE${NC}"
    exit 1
fi

# パラメータファイルの存在確認
if [ ! -f "$PARAMETERS_FILE" ]; then
    echo -e "${YELLOW}警告: パラメータファイルが見つかりません: $PARAMETERS_FILE${NC}"
    echo "デフォルトパラメータを使用します"
    PARAMETERS_OPTION=""
else
    PARAMETERS_OPTION="--parameter-overrides file://${PARAMETERS_FILE}"
fi

# S3バケットの作成（存在しない場合）
echo -e "${GREEN}アーティファクト用S3バケットを確認中...${NC}"
if aws s3 ls "s3://${S3_BUCKET}" --profile "$PROFILE" --region "$REGION" 2>&1 | grep -q 'NoSuchBucket'; then
    echo -e "${YELLOW}S3バケットを作成中: ${S3_BUCKET}${NC}"
    
    # バケット作成（東京リージョン以外の場合は LocationConstraint を指定）
    if [ "$REGION" = "us-east-1" ]; then
        aws s3 mb "s3://${S3_BUCKET}" --profile "$PROFILE" --region "$REGION"
    else
        aws s3api create-bucket \
            --bucket "${S3_BUCKET}" \
            --profile "$PROFILE" \
            --region "$REGION" \
            --create-bucket-configuration LocationConstraint="${REGION}"
    fi
    
    # バージョニングの有効化
    aws s3api put-bucket-versioning \
        --bucket "${S3_BUCKET}" \
        --versioning-configuration Status=Enabled \
        --profile "$PROFILE" \
        --region "$REGION"
    
    # 暗号化の有効化
    aws s3api put-bucket-encryption \
        --bucket "${S3_BUCKET}" \
        --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' \
        --profile "$PROFILE" \
        --region "$REGION"
fi

# Lambda関数のソースコードをパッケージング
echo -e "${GREEN}Lambda関数をパッケージング中...${NC}"
if [ -d "src/lambda" ]; then
    # 一時ディレクトリの作成
    TEMP_DIR=$(mktemp -d)
    
    # Lambda関数をzipファイルにパッケージ
    for lambda_file in src/lambda/*.py; do
        if [ -f "$lambda_file" ]; then
            filename=$(basename "$lambda_file" .py)
            echo "パッケージング: $filename"
            
            # Pythonファイルをzipに追加
            cp "$lambda_file" "$TEMP_DIR/"
            (cd "$TEMP_DIR" && zip -q "${filename}.zip" "$(basename "$lambda_file")")
            
            # S3にアップロード
            aws s3 cp "$TEMP_DIR/${filename}.zip" "s3://${S3_BUCKET}/lambda/${filename}.zip" \
                --profile "$PROFILE" \
                --region "$REGION"
        fi
    done
    
    # 一時ディレクトリの削除
    rm -rf "$TEMP_DIR"
fi

# ネストされたテンプレートをS3にアップロード
echo -e "${GREEN}ネストされたテンプレートをS3にアップロード中...${NC}"
if [ -d "infrastructure/templates" ]; then
    for template in infrastructure/templates/*.yaml; do
        if [ -f "$template" ]; then
            template_name=$(basename "$template")
            echo "アップロード: $template_name"
            aws s3 cp "$template" "s3://${S3_BUCKET}/templates/${template_name}" \
                --profile "$PROFILE" \
                --region "$REGION"
        fi
    done
fi

# CloudFormationテンプレートのパッケージング
echo -e "${GREEN}CloudFormationテンプレートをパッケージング中...${NC}"
aws cloudformation package \
    --template-file "$TEMPLATE_FILE" \
    --s3-bucket "$S3_BUCKET" \
    --s3-prefix "templates" \
    --output-template-file "$PACKAGED_TEMPLATE" \
    --profile "$PROFILE" \
    --region "$REGION"

# CloudFormationスタックのデプロイ
echo -e "${GREEN}CloudFormationスタックをデプロイ中...${NC}"
aws cloudformation deploy \
    --template-file "$PACKAGED_TEMPLATE" \
    --stack-name "$STACK_NAME" \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --profile "$PROFILE" \
    --region "$REGION" \
    $PARAMETERS_OPTION \
    --tags Environment="${ENVIRONMENT}" Project="AmazonConnectBedrock"

# デプロイ結果の確認
if [ $? -eq 0 ]; then
    echo -e "${GREEN}=== デプロイが正常に完了しました ===${NC}"
    
    # スタックの出力を表示
    echo -e "${GREEN}スタック出力:${NC}"
    aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --profile "$PROFILE" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
        --output table
    
    # 重要なリソース情報の表示
    echo -e "${GREEN}重要なリソース:${NC}"
    aws cloudformation describe-stack-resources \
        --stack-name "$STACK_NAME" \
        --profile "$PROFILE" \
        --region "$REGION" \
        --query 'StackResources[?ResourceType==`AWS::Connect::Instance`].[LogicalResourceId,PhysicalResourceId]' \
        --output table
else
    echo -e "${RED}Error: デプロイに失敗しました${NC}"
    
    # エラーの詳細を表示
    echo -e "${YELLOW}スタックイベントを確認中...${NC}"
    aws cloudformation describe-stack-events \
        --stack-name "$STACK_NAME" \
        --profile "$PROFILE" \
        --region "$REGION" \
        --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`||ResourceStatus==`UPDATE_FAILED`].[Timestamp,ResourceType,LogicalResourceId,ResourceStatusReason]' \
        --output table
    
    exit 1
fi

# ナレッジベースへのデータアップロード確認
if [ -f "data/qa-knowledge.json" ] && [ "$ENVIRONMENT" != "debug" ]; then
    echo -e "${YELLOW}ナレッジベースにQ&Aデータをアップロードしますか？ (yes/no)${NC}"
    read -r UPLOAD_KB
    if [[ $UPLOAD_KB =~ ^[Yy][Ee][Ss]$ ]]; then
        KNOWLEDGE_BUCKET="helpdesk-knowledge-${ENVIRONMENT}"
        echo -e "${GREEN}Q&Aデータをアップロード中...${NC}"
        aws s3 cp "data/qa-knowledge.json" "s3://${KNOWLEDGE_BUCKET}/qa-data/qa-knowledge.json" \
            --profile "$PROFILE" \
            --region "$REGION"
        echo -e "${GREEN}アップロードが完了しました${NC}"
    fi
fi

echo -e "${GREEN}=== すべての処理が完了しました ===${NC}"
echo ""
echo "次のステップ:"
echo "1. Amazon Connect インスタンスにログインして電話番号を設定"
echo "2. Contact Flow の設定を確認"
echo "3. テスト通話を実施"
echo ""
echo "スタックの状態確認:"
echo "aws cloudformation describe-stacks --stack-name $STACK_NAME --profile $PROFILE --region $REGION"
#!/bin/bash

# Amazon Connect テストヘルパースクリプト

set -e

# 色付き出力用の設定
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 使用方法
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -e, --environment ENV    環境名 (debug/staging/production)"
    echo "  -l, --logs              CloudWatch Logsを表示"
    echo "  -m, --metrics           CloudWatchメトリクスを表示"
    echo "  -i, --info              Connect インスタンス情報を表示"
    echo "  -h, --help              ヘルプを表示"
}

# デフォルト値
ENVIRONMENT="debug"
SHOW_LOGS=false
SHOW_METRICS=false
SHOW_INFO=false

# オプション解析
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -e|--environment)
            ENVIRONMENT="$2"
            shift
            shift
            ;;
        -l|--logs)
            SHOW_LOGS=true
            shift
            ;;
        -m|--metrics)
            SHOW_METRICS=true
            shift
            ;;
        -i|--info)
            SHOW_INFO=true
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

# 環境変数読み込み
if [ -f ".env.local" ]; then
    source .env.local
fi

STACK_NAME="helpdesk-${ENVIRONMENT}"

# スタック情報取得
echo -e "${GREEN}スタック情報を取得中...${NC}"
STACK_INFO=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" 2>/dev/null || echo "")

if [ -z "$STACK_INFO" ]; then
    echo -e "${RED}Error: スタック '$STACK_NAME' が見つかりません${NC}"
    echo "先に './scripts/deploy.sh -e $ENVIRONMENT' でデプロイしてください"
    exit 1
fi

# Connect Instance ID取得
CONNECT_INSTANCE_ID=$(echo "$STACK_INFO" | jq -r '.Stacks[0].Outputs[] | select(.OutputKey == "ConnectInstanceId") | .OutputValue')
LAMBDA_ARN=$(echo "$STACK_INFO" | jq -r '.Stacks[0].Outputs[] | select(.OutputKey == "LambdaFunctionArn") | .OutputValue')

if [ "$SHOW_INFO" = true ]; then
    echo -e "${BLUE}=== Amazon Connect インスタンス情報 ===${NC}"
    echo "Instance ID: $CONNECT_INSTANCE_ID"
    echo "Lambda ARN: $LAMBDA_ARN"
    echo ""
    
    # Contact Flow情報
    echo -e "${BLUE}Contact Flows:${NC}"
    aws connect list-contact-flows \
        --instance-id "$CONNECT_INSTANCE_ID" \
        --query 'ContactFlowSummaryList[?contains(Name, `helpdesk`)].[Name,Id,Arn]' \
        --output table
    
    # 電話番号情報
    echo -e "${BLUE}電話番号:${NC}"
    aws connect list-phone-numbers \
        --instance-id "$CONNECT_INSTANCE_ID" \
        --query 'PhoneNumberSummaryList[].[PhoneNumber,PhoneNumberType,PhoneNumberCountryCode]' \
        --output table 2>/dev/null || echo "電話番号が設定されていません"
fi

if [ "$SHOW_LOGS" = true ]; then
    echo -e "${BLUE}=== CloudWatch Logs (最新20件) ===${NC}"
    
    # Lambda関数のログ
    echo -e "${GREEN}Lambda関数ログ:${NC}"
    LOG_GROUP="/aws/lambda/automated-helpdesk-processor-${ENVIRONMENT}"
    
    # 最新のログストリームを取得
    LATEST_STREAM=$(aws logs describe-log-streams \
        --log-group-name "$LOG_GROUP" \
        --order-by LastEventTime \
        --descending \
        --limit 1 \
        --query 'logStreams[0].logStreamName' \
        --output text 2>/dev/null)
    
    if [ "$LATEST_STREAM" != "None" ] && [ -n "$LATEST_STREAM" ]; then
        aws logs filter-log-events \
            --log-group-name "$LOG_GROUP" \
            --log-stream-names "$LATEST_STREAM" \
            --limit 20 \
            --query 'events[*].message' \
            --output text
    else
        echo "ログが見つかりません"
    fi
    
    echo ""
    
    # Connect のログ
    echo -e "${GREEN}Connect フローログ:${NC}"
    CONNECT_LOG_GROUP="/aws/connect/helpdesk-${ENVIRONMENT}"
    
    aws logs filter-log-events \
        --log-group-name "$CONNECT_LOG_GROUP" \
        --limit 20 \
        --query 'events[*].message' \
        --output text 2>/dev/null || echo "Connectログが見つかりません"
fi

if [ "$SHOW_METRICS" = true ]; then
    echo -e "${BLUE}=== CloudWatch メトリクス (過去1時間) ===${NC}"
    
    END_TIME=$(date -u +%Y-%m-%dT%H:%M:%S)
    START_TIME=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -v-1H +%Y-%m-%dT%H:%M:%S)
    
    # Lambda関数のメトリクス
    echo -e "${GREEN}Lambda関数メトリクス:${NC}"
    echo "呼び出し回数:"
    aws cloudwatch get-metric-statistics \
        --namespace AWS/Lambda \
        --metric-name Invocations \
        --dimensions Name=FunctionName,Value="automated-helpdesk-processor-${ENVIRONMENT}" \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --period 3600 \
        --statistics Sum \
        --query 'Datapoints[0].Sum' \
        --output text
    
    echo "エラー数:"
    aws cloudwatch get-metric-statistics \
        --namespace AWS/Lambda \
        --metric-name Errors \
        --dimensions Name=FunctionName,Value="automated-helpdesk-processor-${ENVIRONMENT}" \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --period 3600 \
        --statistics Sum \
        --query 'Datapoints[0].Sum' \
        --output text
    
    echo "平均実行時間(ms):"
    aws cloudwatch get-metric-statistics \
        --namespace AWS/Lambda \
        --metric-name Duration \
        --dimensions Name=FunctionName,Value="automated-helpdesk-processor-${ENVIRONMENT}" \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --period 3600 \
        --statistics Average \
        --query 'Datapoints[0].Average' \
        --output text
fi

# テスト手順の表示
echo ""
echo -e "${BLUE}=== テスト手順 ===${NC}"
echo "1. AWSコンソールにログイン"
echo "2. Amazon Connect > インスタンス > helpdesk-${ENVIRONMENT} を選択"
echo "3. 左メニューから「電話番号」を選択し、番号を取得（まだの場合）"
echo "4. 「Contact flows」から作成したフローを選択"
echo "5. 電話番号をContact Flowに関連付け"
echo "6. 取得した電話番号に電話をかけてテスト"
echo ""
echo -e "${YELLOW}ヒント:${NC}"
echo "- ログを確認: $0 -e $ENVIRONMENT -l"
echo "- メトリクスを確認: $0 -e $ENVIRONMENT -m"
echo "- インスタンス情報: $0 -e $ENVIRONMENT -i"
echo ""
#!/bin/bash

# Amazon Connect Bedrock Helpdesk - 開発環境セットアップスクリプト

set -e

# 色付き出力用の設定
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Amazon Connect Bedrock Helpdesk 開発環境セットアップ ===${NC}"
echo ""

# Python バージョンチェック
echo -e "${GREEN}Pythonバージョンを確認中...${NC}"
if ! python3 --version | grep -E "3\.(9|1[0-1])" > /dev/null 2>&1; then
    echo -e "${RED}Error: Python 3.9以上が必要です${NC}"
    exit 1
fi
python3 --version

# venv作成
if [ ! -d "venv" ]; then
    echo -e "${GREEN}仮想環境を作成中...${NC}"
    python3 -m venv venv
fi

# venvアクティベート
echo -e "${GREEN}仮想環境をアクティベート中...${NC}"
source venv/bin/activate

# 依存関係インストール
echo -e "${GREEN}依存パッケージをインストール中...${NC}"
pip install --upgrade pip
pip install -r requirements.txt
pip install -r requirements-dev.txt

# AWS CLI設定確認
echo -e "${GREEN}AWS CLI設定を確認中...${NC}"
if ! command -v aws &> /dev/null; then
    echo -e "${YELLOW}警告: AWS CLIがインストールされていません${NC}"
    echo "インストール方法: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
else
    aws --version
    echo -e "${GREEN}現在のAWSプロファイル:${NC}"
    aws configure list
fi

# 環境変数設定ファイルの作成
if [ ! -f ".env.local" ]; then
    echo -e "${GREEN}.env.localファイルを作成中...${NC}"
    cat > .env.local << EOF
# 開発環境用設定
export AWS_REGION=ap-northeast-1
export AWS_PROFILE=default
export ENVIRONMENT=debug

# デバッグ設定
export LOG_LEVEL=DEBUG
export PYTHONPATH=\${PYTHONPATH}:\$(pwd)/src

# Connect設定（デプロイ後に設定）
# export CONNECT_INSTANCE_ID=
# export CONNECT_CONTACT_FLOW_ID=
# export CONNECT_PHONE_NUMBER=
EOF
    echo -e "${YELLOW}注意: .env.localファイルを編集して適切な値を設定してください${NC}"
fi

# ディレクトリ権限設定
echo -e "${GREEN}ディレクトリ権限を設定中...${NC}"
chmod +x scripts/*.sh

# pre-commitフックの設定（オプション）
if command -v pre-commit &> /dev/null; then
    echo -e "${GREEN}pre-commitフックを設定中...${NC}"
    cat > .pre-commit-config.yaml << EOF
repos:
  - repo: https://github.com/psf/black
    rev: 23.7.0
    hooks:
      - id: black
        language_version: python3
  - repo: https://github.com/pycqa/flake8
    rev: 6.1.0
    hooks:
      - id: flake8
        args: ['--max-line-length=100', '--extend-ignore=E203']
EOF
    pre-commit install
fi

# テスト実行
echo -e "${GREEN}開発環境の動作確認中...${NC}"
python -c "import boto3; print('boto3 import: OK')"
python -c "import pytest; print('pytest import: OK')"

# CloudFormationテンプレートの検証
echo -e "${GREEN}CloudFormationテンプレートを検証中...${NC}"
if command -v cfn-lint &> /dev/null; then
    cfn-lint infrastructure/main.yaml || true
    cfn-lint infrastructure/templates/*.yaml || true
else
    echo -e "${YELLOW}cfn-lintがインストールされていません。pip install cfn-lintでインストールできます${NC}"
fi

echo ""
echo -e "${GREEN}=== セットアップ完了 ===${NC}"
echo ""
echo "次のステップ:"
echo "1. source venv/bin/activate で仮想環境をアクティベート"
echo "2. source .env.local で環境変数を設定"
echo "3. ./scripts/deploy.sh -e debug でデバッグ環境にデプロイ"
echo "4. Amazon Connectコンソールで電話番号を設定"
echo ""
echo -e "${BLUE}開発用コマンド:${NC}"
echo "  pytest tests/                    # テスト実行"
echo "  black src/ tests/                # コードフォーマット"
echo "  flake8 src/ tests/               # Lintチェック"
echo "  python -m src.lambda.helpdesk_processor  # Lambda関数のローカル実行"
echo ""

# Connect Studio テスト用の説明
echo -e "${BLUE}Amazon Connect テスト方法:${NC}"
echo "1. AWSコンソール > Amazon Connect > インスタンスを選択"
echo "2. 'Contact flows' > 作成したフローを選択"
echo "3. 'Test chat' または 'Test voice' でテスト"
echo "4. CloudWatch Logsでログを確認"
echo ""
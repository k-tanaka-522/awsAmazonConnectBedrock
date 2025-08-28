import boto3
import json
import logging
import os
from datetime import datetime
from typing import Dict, Any, List

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# AWSクライアント
s3 = boto3.client('s3')
bedrock_agent = boto3.client('bedrock-agent')

# 環境変数
KNOWLEDGE_BASE_ID = os.environ.get('KNOWLEDGE_BASE_ID')
S3_BUCKET = os.environ.get('S3_BUCKET')
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'unknown')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    ナレッジベースの更新処理
    EventBridgeまたは手動トリガーで実行される
    
    Args:
        event: トリガーイベント
        context: Lambda実行コンテキスト
    
    Returns:
        処理結果
    """
    try:
        logger.info(f"Knowledge base update started for environment: {ENVIRONMENT}")
        logger.info(f"Event: {json.dumps(event)}")
        
        # S3からの更新
        if event.get('source') == 'aws.s3':
            # S3イベントからの自動更新
            bucket = event['detail']['bucket']['name']
            key = event['detail']['object']['key']
            return handle_s3_update(bucket, key)
        
        # 定期更新またはマニュアル実行
        return handle_scheduled_update()
        
    except Exception as e:
        logger.error(f"Error in knowledge base update: {str(e)}")
        raise

def handle_scheduled_update() -> Dict[str, Any]:
    """
    定期更新処理
    """
    try:
        # バックアップの作成
        backup_current_data()
        
        # 新しいデータの検証
        validation_result = validate_knowledge_data()
        if not validation_result['valid']:
            logger.error(f"Data validation failed: {validation_result['errors']}")
            return {
                'statusCode': 400,
                'body': {
                    'message': 'Data validation failed',
                    'errors': validation_result['errors']
                }
            }
        
        # ナレッジベースの同期
        if KNOWLEDGE_BASE_ID and KNOWLEDGE_BASE_ID != 'debug-placeholder':
            sync_result = sync_knowledge_base()
            
            # 同期結果の記録
            record_update_history(sync_result)
            
            return {
                'statusCode': 200,
                'body': {
                    'message': 'Knowledge base updated successfully',
                    'details': sync_result
                }
            }
        else:
            logger.info("Knowledge base ID not configured, skipping sync")
            return {
                'statusCode': 200,
                'body': {
                    'message': 'Data validated successfully (sync skipped)',
                    'details': validation_result
                }
            }
        
    except Exception as e:
        logger.error(f"Error in scheduled update: {str(e)}")
        raise

def handle_s3_update(bucket: str, key: str) -> Dict[str, Any]:
    """
    S3イベントによる更新処理
    """
    try:
        logger.info(f"Processing S3 update: {bucket}/{key}")
        
        # ファイルタイプの確認
        if not key.endswith('.json'):
            logger.warning(f"Skipping non-JSON file: {key}")
            return {
                'statusCode': 200,
                'body': {'message': 'Skipped non-JSON file'}
            }
        
        # データの検証
        validation_result = validate_specific_file(bucket, key)
        if not validation_result['valid']:
            return {
                'statusCode': 400,
                'body': {
                    'message': 'Invalid data format',
                    'errors': validation_result['errors']
                }
            }
        
        # 即座に同期を実行
        if KNOWLEDGE_BASE_ID and KNOWLEDGE_BASE_ID != 'debug-placeholder':
            sync_result = trigger_ingestion_job()
            return {
                'statusCode': 200,
                'body': {
                    'message': 'Ingestion job started',
                    'jobId': sync_result.get('ingestionJobId')
                }
            }
        
        return {
            'statusCode': 200,
            'body': {'message': 'File validated successfully'}
        }
        
    except Exception as e:
        logger.error(f"Error handling S3 update: {str(e)}")
        raise

def backup_current_data():
    """
    現在のデータをバックアップ
    """
    try:
        timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
        
        # メインのQ&Aデータをバックアップ
        copy_source = {'Bucket': S3_BUCKET, 'Key': 'qa-data/qa-knowledge.json'}
        backup_key = f'qa-data/backup/{timestamp}/qa-knowledge.json'
        
        s3.copy_object(
            CopySource=copy_source,
            Bucket=S3_BUCKET,
            Key=backup_key
        )
        
        logger.info(f"Backup created: {backup_key}")
        
    except Exception as e:
        logger.error(f"Backup failed: {str(e)}")
        raise

def validate_knowledge_data() -> Dict[str, Any]:
    """
    ナレッジデータの検証
    """
    errors = []
    warnings = []
    
    try:
        # Q&Aデータの読み込み
        response = s3.get_object(Bucket=S3_BUCKET, Key='qa-data/qa-knowledge.json')
        qa_data = json.loads(response['Body'].read().decode('utf-8'))
        
        # データ構造の検証
        required_fields = ['id', 'question', 'answer', 'category', 'keywords']
        
        for idx, item in enumerate(qa_data):
            # 必須フィールドチェック
            for field in required_fields:
                if field not in item:
                    errors.append(f"Item {idx}: Missing required field '{field}'")
            
            # データ型チェック
            if 'keywords' in item and not isinstance(item['keywords'], list):
                errors.append(f"Item {idx}: 'keywords' must be a list")
            
            # 文字数チェック
            if 'answer' in item and len(item['answer']) > 2000:
                warnings.append(f"Item {idx}: Answer exceeds 2000 characters")
        
        # IDの重複チェック
        ids = [item.get('id') for item in qa_data if 'id' in item]
        duplicate_ids = set([id for id in ids if ids.count(id) > 1])
        if duplicate_ids:
            errors.append(f"Duplicate IDs found: {duplicate_ids}")
        
        # カテゴリの一貫性チェック
        categories = set([item.get('category') for item in qa_data if 'category' in item])
        logger.info(f"Found {len(categories)} categories: {categories}")
        
        return {
            'valid': len(errors) == 0,
            'errors': errors,
            'warnings': warnings,
            'stats': {
                'total_items': len(qa_data),
                'categories': list(categories),
                'total_keywords': sum(len(item.get('keywords', [])) for item in qa_data)
            }
        }
        
    except Exception as e:
        errors.append(f"Failed to read or parse data: {str(e)}")
        return {
            'valid': False,
            'errors': errors,
            'warnings': warnings
        }

def validate_specific_file(bucket: str, key: str) -> Dict[str, Any]:
    """
    特定ファイルの検証
    """
    try:
        response = s3.get_object(Bucket=bucket, Key=key)
        data = json.loads(response['Body'].read().decode('utf-8'))
        
        # 簡易検証
        if not isinstance(data, list):
            return {
                'valid': False,
                'errors': ['Data must be a JSON array']
            }
        
        return {'valid': True, 'errors': []}
        
    except json.JSONDecodeError as e:
        return {
            'valid': False,
            'errors': [f'Invalid JSON: {str(e)}']
        }
    except Exception as e:
        return {
            'valid': False,
            'errors': [f'Error reading file: {str(e)}']
        }

def sync_knowledge_base() -> Dict[str, Any]:
    """
    Bedrock Knowledge Baseとの同期
    """
    try:
        # データソースのIDを取得
        data_sources = bedrock_agent.list_data_sources(
            knowledgeBaseId=KNOWLEDGE_BASE_ID
        )
        
        if not data_sources['dataSourceSummaries']:
            raise Exception("No data sources found for knowledge base")
        
        data_source_id = data_sources['dataSourceSummaries'][0]['dataSourceId']
        
        # Ingestionジョブを開始
        response = bedrock_agent.start_ingestion_job(
            knowledgeBaseId=KNOWLEDGE_BASE_ID,
            dataSourceId=data_source_id,
            description=f"Scheduled update - {datetime.utcnow().isoformat()}"
        )
        
        job_id = response['ingestionJob']['ingestionJobId']
        logger.info(f"Started ingestion job: {job_id}")
        
        return {
            'jobId': job_id,
            'status': 'started',
            'timestamp': datetime.utcnow().isoformat()
        }
        
    except Exception as e:
        logger.error(f"Sync failed: {str(e)}")
        raise

def trigger_ingestion_job() -> Dict[str, Any]:
    """
    即座にIngestionジョブを実行
    """
    try:
        # sync_knowledge_baseと同じ処理だが、即座に実行
        return sync_knowledge_base()
        
    except Exception as e:
        logger.error(f"Failed to trigger ingestion: {str(e)}")
        raise

def record_update_history(sync_result: Dict[str, Any]):
    """
    更新履歴を記録
    """
    try:
        history_entry = {
            'timestamp': datetime.utcnow().isoformat(),
            'environment': ENVIRONMENT,
            'sync_result': sync_result,
            'type': 'scheduled_update'
        }
        
        # 履歴をS3に保存
        history_key = f'qa-data/update-history/{datetime.utcnow().strftime("%Y/%m/%d")}/update-{sync_result["jobId"]}.json'
        
        s3.put_object(
            Bucket=S3_BUCKET,
            Key=history_key,
            Body=json.dumps(history_entry),
            ContentType='application/json'
        )
        
        logger.info(f"Update history recorded: {history_key}")
        
    except Exception as e:
        logger.error(f"Failed to record history: {str(e)}")
        # 履歴記録の失敗は致命的ではないため、例外は投げない
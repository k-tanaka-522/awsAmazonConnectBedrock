import boto3
import logging
from datetime import datetime
from typing import Dict, Any, Optional
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

cloudwatch = boto3.client('cloudwatch')

class QualityMetrics:
    def __init__(self):
        self.cloudwatch = cloudwatch
        self.environment = os.environ.get('ENVIRONMENT', 'unknown')
        self.namespace = 'Helpdesk/Quality'
    
    def record_call_metrics(self, call_data: Dict[str, Any]):
        """通話品質メトリクスを記録"""
        try:
            metrics = []
            timestamp = datetime.utcnow()
            
            # 応答時間の記録
            response_time = call_data.get('response_time', 0)
            if response_time > 0:
                metrics.append({
                    'MetricName': 'ResponseTime',
                    'Value': response_time,
                    'Unit': 'Seconds',
                    'Timestamp': timestamp,
                    'Dimensions': [
                        {'Name': 'Environment', 'Value': self.environment},
                        {'Name': 'Category', 'Value': call_data.get('category', 'unknown')}
                    ]
                })
            
            # 解決率の記録（回答が見つかったかどうか）
            resolution_status = 1 if call_data.get('answer_found', False) else 0
            metrics.append({
                'MetricName': 'ResolutionRate',
                'Value': resolution_status,
                'Unit': 'Count',
                'Timestamp': timestamp,
                'Dimensions': [
                    {'Name': 'Environment', 'Value': self.environment}
                ]
            })
            
            # 信頼度スコアの記録
            confidence = call_data.get('confidence', 0)
            if confidence >= 0:
                metrics.append({
                    'MetricName': 'ConfidenceScore',
                    'Value': confidence,
                    'Unit': 'None',
                    'Timestamp': timestamp,
                    'Dimensions': [
                        {'Name': 'Environment', 'Value': self.environment},
                        {'Name': 'Category', 'Value': call_data.get('category', 'unknown')}
                    ]
                })
            
            # 通話時間の記録
            call_duration = call_data.get('call_duration', 0)
            if call_duration > 0:
                metrics.append({
                    'MetricName': 'CallDuration',
                    'Value': call_duration,
                    'Unit': 'Seconds',
                    'Timestamp': timestamp,
                    'Dimensions': [
                        {'Name': 'Environment', 'Value': self.environment}
                    ]
                })
            
            # エラー率の記録
            if call_data.get('error', False):
                metrics.append({
                    'MetricName': 'ErrorCount',
                    'Value': 1,
                    'Unit': 'Count',
                    'Timestamp': timestamp,
                    'Dimensions': [
                        {'Name': 'Environment', 'Value': self.environment},
                        {'Name': 'ErrorType', 'Value': call_data.get('error_type', 'unknown')}
                    ]
                })
            
            # メトリクスをCloudWatchに送信
            if metrics:
                self.cloudwatch.put_metric_data(
                    Namespace=self.namespace,
                    MetricData=metrics
                )
                logger.info(f"Recorded {len(metrics)} metrics to CloudWatch")
            
        except Exception as e:
            logger.error(f"Failed to record metrics: {str(e)}")
    
    def record_knowledge_base_metrics(self, kb_data: Dict[str, Any]):
        """ナレッジベース利用メトリクスを記録"""
        try:
            metrics = []
            timestamp = datetime.utcnow()
            
            # 検索時間
            search_time = kb_data.get('search_time', 0)
            if search_time > 0:
                metrics.append({
                    'MetricName': 'KnowledgeBaseSearchTime',
                    'Value': search_time,
                    'Unit': 'Seconds',
                    'Timestamp': timestamp,
                    'Dimensions': [
                        {'Name': 'Environment', 'Value': self.environment}
                    ]
                })
            
            # 検索結果数
            result_count = kb_data.get('result_count', 0)
            metrics.append({
                'MetricName': 'KnowledgeBaseResultCount',
                'Value': result_count,
                'Unit': 'Count',
                'Timestamp': timestamp,
                'Dimensions': [
                    {'Name': 'Environment', 'Value': self.environment}
                ]
            })
            
            # トップ結果の信頼度
            top_score = kb_data.get('top_score', 0)
            if top_score > 0:
                metrics.append({
                    'MetricName': 'KnowledgeBaseTopScore',
                    'Value': top_score,
                    'Unit': 'None',
                    'Timestamp': timestamp,
                    'Dimensions': [
                        {'Name': 'Environment', 'Value': self.environment}
                    ]
                })
            
            if metrics:
                self.cloudwatch.put_metric_data(
                    Namespace=self.namespace,
                    MetricData=metrics
                )
                
        except Exception as e:
            logger.error(f"Failed to record KB metrics: {str(e)}")
    
    def record_bedrock_metrics(self, bedrock_data: Dict[str, Any]):
        """Bedrock利用メトリクスを記録"""
        try:
            metrics = []
            timestamp = datetime.utcnow()
            
            # 生成時間
            generation_time = bedrock_data.get('generation_time', 0)
            if generation_time > 0:
                metrics.append({
                    'MetricName': 'BedrockGenerationTime',
                    'Value': generation_time,
                    'Unit': 'Seconds',
                    'Timestamp': timestamp,
                    'Dimensions': [
                        {'Name': 'Environment', 'Value': self.environment},
                        {'Name': 'ModelId', 'Value': bedrock_data.get('model_id', 'unknown')}
                    ]
                })
            
            # トークン数（概算）
            token_count = bedrock_data.get('token_count', 0)
            if token_count > 0:
                metrics.append({
                    'MetricName': 'BedrockTokenCount',
                    'Value': token_count,
                    'Unit': 'Count',
                    'Timestamp': timestamp,
                    'Dimensions': [
                        {'Name': 'Environment', 'Value': self.environment},
                        {'Name': 'ModelId', 'Value': bedrock_data.get('model_id', 'unknown')}
                    ]
                })
            
            # コスト概算（トークンベース）
            estimated_cost = bedrock_data.get('estimated_cost', 0)
            if estimated_cost > 0:
                metrics.append({
                    'MetricName': 'BedrockEstimatedCost',
                    'Value': estimated_cost,
                    'Unit': 'None',  # USD
                    'Timestamp': timestamp,
                    'Dimensions': [
                        {'Name': 'Environment', 'Value': self.environment}
                    ]
                })
            
            if metrics:
                self.cloudwatch.put_metric_data(
                    Namespace=self.namespace,
                    MetricData=metrics
                )
                
        except Exception as e:
            logger.error(f"Failed to record Bedrock metrics: {str(e)}")

# Lambda関数として使用する場合のハンドラ
def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    メトリクス記録用Lambda関数
    Connect Contact Flowから直接呼び出されることもある
    """
    metrics = QualityMetrics()
    
    try:
        # イベントタイプに応じて処理
        event_type = event.get('type', 'call_metrics')
        
        if event_type == 'call_metrics':
            metrics.record_call_metrics(event.get('data', {}))
        elif event_type == 'kb_metrics':
            metrics.record_knowledge_base_metrics(event.get('data', {}))
        elif event_type == 'bedrock_metrics':
            metrics.record_bedrock_metrics(event.get('data', {}))
        else:
            logger.warning(f"Unknown event type: {event_type}")
        
        return {
            'statusCode': 200,
            'body': {'message': 'Metrics recorded successfully'}
        }
        
    except Exception as e:
        logger.error(f"Error in metrics handler: {str(e)}")
        return {
            'statusCode': 500,
            'body': {'error': str(e)}
        }
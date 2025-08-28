import json
import logging
import os
import time
from typing import Dict, Any, Optional
import boto3
from botocore.exceptions import ClientError

# ログ設定
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# AWSクライアント
bedrock_runtime = boto3.client('bedrock-runtime')
bedrock_agent_runtime = boto3.client('bedrock-agent-runtime')
s3 = boto3.client('s3')

# 環境変数
KNOWLEDGE_BASE_ID = os.environ.get('KNOWLEDGE_BASE_ID')
BEDROCK_MODEL_ID = os.environ.get('BEDROCK_MODEL_ID', 'claude-3-5-sonnet-20241022')
KNOWLEDGE_BUCKET = os.environ.get('KNOWLEDGE_BUCKET')
COST_LIMIT_DAILY = float(os.environ.get('COST_LIMIT_DAILY', '10'))

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Amazon Connectからの音声認識結果を処理し、
    Bedrockを使用して回答を生成する
    
    Args:
        event: Connect Contact Flowからの入力データ
        context: Lambda実行コンテキスト
    
    Returns:
        Connect Contact Flowに返す回答データ
    """
    start_time = time.time()
    
    try:
        logger.info(f"Received event: {json.dumps(event)}")
        
        # 入力データの取得
        contact_data = event.get('Details', {})
        parameters = contact_data.get('Parameters', {})
        transcribed_text = parameters.get('transcribedText', '')
        contact_id = parameters.get('contactId', 'unknown')
        customer_phone = parameters.get('customerPhoneNumber', 'unknown')
        
        logger.info(f"Contact ID: {contact_id}, Customer: {customer_phone}")
        logger.info(f"Transcribed text: {transcribed_text}")
        
        # 入力検証
        if not transcribed_text or len(transcribed_text.strip()) == 0:
            return create_response(
                "申し訳ございません。音声が聞き取れませんでした。もう一度お話しいただけますでしょうか。",
                confidence=0.0,
                category="no_input",
                processing_time=time.time() - start_time
            )
        
        # ナレッジベースから回答を取得
        answer, confidence, category = get_answer_from_knowledge_base(transcribed_text)
        
        # 回答が見つからない場合は、Bedrockで生成
        if confidence < 0.5:
            answer, confidence, category = generate_answer_with_bedrock(transcribed_text)
        
        processing_time = time.time() - start_time
        logger.info(f"Processing completed in {processing_time:.2f} seconds")
        
        # メトリクスの記録（フェーズ3で実装）
        # record_metrics(contact_id, processing_time, confidence, category)
        
        return create_response(answer, confidence, category, processing_time)
        
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        return create_response(
            "申し訳ございません。現在システムが混雑しております。しばらくしてからおかけ直しください。",
            confidence=0.0,
            category="error",
            processing_time=time.time() - start_time
        )

def get_answer_from_knowledge_base(question: str) -> tuple[str, float, str]:
    """
    ナレッジベースから関連する回答を検索
    
    Args:
        question: ユーザーの質問
    
    Returns:
        回答、信頼度、カテゴリのタプル
    """
    try:
        # Knowledge Base IDが設定されていない場合（フェーズ1）
        if not KNOWLEDGE_BASE_ID or KNOWLEDGE_BASE_ID == 'debug-placeholder':
            logger.info("Knowledge Base not configured, using fallback")
            return get_answer_from_s3(question)
        
        # Bedrock Knowledge Baseからの検索（フェーズ2で完全実装）
        response = bedrock_agent_runtime.retrieve(
            knowledgeBaseId=KNOWLEDGE_BASE_ID,
            retrievalQuery={
                'text': question
            },
            retrievalConfiguration={
                'vectorSearchConfiguration': {
                    'numberOfResults': 3
                }
            }
        )
        
        # 最も関連性の高い結果を取得
        if response['retrievalResults']:
            result = response['retrievalResults'][0]
            answer = result['content']['text']
            confidence = result['score']
            category = 'knowledge_base'
            
            logger.info(f"Found answer in knowledge base with confidence: {confidence}")
            return answer, confidence, category
            
    except ClientError as e:
        logger.error(f"Error accessing knowledge base: {e}")
    except Exception as e:
        logger.error(f"Unexpected error in knowledge base search: {e}")
    
    return "", 0.0, "not_found"

def get_answer_from_s3(question: str) -> tuple[str, float, str]:
    """
    S3から直接Q&Aデータを読み込んで回答を検索（フォールバック）
    
    Args:
        question: ユーザーの質問
    
    Returns:
        回答、信頼度、カテゴリのタプル
    """
    try:
        if not KNOWLEDGE_BUCKET:
            return "", 0.0, "not_configured"
        
        # S3からQ&Aデータを読み込み
        response = s3.get_object(
            Bucket=KNOWLEDGE_BUCKET,
            Key='qa-data/qa-knowledge.json'
        )
        qa_data = json.loads(response['Body'].read().decode('utf-8'))
        
        # 簡易的なキーワードマッチング
        question_lower = question.lower()
        best_match = None
        best_score = 0.0
        
        for qa in qa_data:
            score = 0.0
            
            # キーワードマッチング
            for keyword in qa.get('keywords', []):
                if keyword.lower() in question_lower:
                    score += 1.0
            
            # 質問文の類似度（簡易版）
            if qa['question'].lower() in question_lower:
                score += 2.0
            
            if score > best_score:
                best_score = score
                best_match = qa
        
        if best_match and best_score > 0:
            confidence = min(best_score / 3.0, 1.0)  # 正規化
            return best_match['answer'], confidence, best_match['category']
        
    except Exception as e:
        logger.error(f"Error reading from S3: {e}")
    
    return "", 0.0, "not_found"

def generate_answer_with_bedrock(question: str) -> tuple[str, float, str]:
    """
    Bedrock LLMを使用して回答を生成
    
    Args:
        question: ユーザーの質問
    
    Returns:
        回答、信頼度、カテゴリのタプル
    """
    try:
        prompt = f"""あなたはレジシステムのサポート担当者です。
以下の質問に対して、丁寧で簡潔な回答を提供してください。
技術的な詳細は避け、実際の操作手順を中心に説明してください。

質問: {question}

回答:"""
        
        # Bedrockモデルの呼び出し
        if BEDROCK_MODEL_ID.startswith('claude'):
            response = bedrock_runtime.invoke_model(
                modelId=BEDROCK_MODEL_ID,
                body=json.dumps({
                    "anthropic_version": "bedrock-2023-05-31",
                    "max_tokens": 500,
                    "temperature": 0.7,
                    "messages": [
                        {
                            "role": "user",
                            "content": prompt
                        }
                    ]
                })
            )
        else:
            # Amazon Nova等の他のモデル用
            response = bedrock_runtime.invoke_model(
                modelId=BEDROCK_MODEL_ID,
                body=json.dumps({
                    "prompt": prompt,
                    "max_tokens": 500,
                    "temperature": 0.7
                })
            )
        
        response_body = json.loads(response['body'].read())
        
        if BEDROCK_MODEL_ID.startswith('claude'):
            answer = response_body['content'][0]['text']
        else:
            answer = response_body['completion']
        
        logger.info(f"Generated answer using {BEDROCK_MODEL_ID}")
        return answer, 0.7, "bedrock_generated"
        
    except Exception as e:
        logger.error(f"Error generating answer with Bedrock: {e}")
        return (
            "申し訳ございませんが、該当する情報が見つかりませんでした。技術サポートまでお問い合わせください。",
            0.3,
            "generation_error"
        )

def create_response(response: str, confidence: float, category: str, processing_time: float) -> Dict[str, Any]:
    """
    Connect Contact Flow用のレスポンスを作成
    
    Args:
        response: 回答テキスト
        confidence: 信頼度スコア
        category: 回答カテゴリ
        processing_time: 処理時間
    
    Returns:
        フォーマットされたレスポンス
    """
    return {
        'response': response,
        'confidence': confidence,
        'category': category,
        'processingTime': processing_time
    }
import logging
from typing import Dict, Any, Optional
from enum import Enum

logger = logging.getLogger()

class ErrorType(Enum):
    """エラータイプの定義"""
    NO_INPUT = "no_input"
    TRANSCRIPTION_FAILED = "transcription_failed"
    KNOWLEDGE_BASE_ERROR = "knowledge_base_error"
    BEDROCK_ERROR = "bedrock_error"
    LAMBDA_TIMEOUT = "lambda_timeout"
    UNKNOWN = "unknown"

class HelpdeskError(Exception):
    """ヘルプデスク固有のエラー"""
    def __init__(self, message: str, error_type: ErrorType = ErrorType.UNKNOWN):
        super().__init__(message)
        self.error_type = error_type
        self.message = message

def handle_error(error: Exception, context: str) -> Dict[str, Any]:
    """
    エラーを適切に処理し、ユーザー向けメッセージを生成
    
    Args:
        error: 発生したエラー
        context: エラーが発生したコンテキスト
    
    Returns:
        エラー応答データ
    """
    logger.error(f"Error in {context}: {type(error).__name__}: {str(error)}")
    
    # エラータイプ別の処理
    error_responses = {
        ErrorType.NO_INPUT: {
            "message": "申し訳ございません。音声が聞き取れませんでした。もう一度はっきりとお話しください。",
            "retry": True,
            "log_level": "WARNING"
        },
        ErrorType.TRANSCRIPTION_FAILED: {
            "message": "申し訳ございません。音声の処理に失敗しました。もう一度お試しください。",
            "retry": True,
            "log_level": "WARNING"
        },
        ErrorType.KNOWLEDGE_BASE_ERROR: {
            "message": "申し訳ございません。情報の検索に失敗しました。技術サポートまでお問い合わせください。",
            "retry": False,
            "log_level": "ERROR"
        },
        ErrorType.BEDROCK_ERROR: {
            "message": "現在システムが混雑しております。しばらくしてからおかけ直しください。",
            "retry": False,
            "log_level": "ERROR"
        },
        ErrorType.LAMBDA_TIMEOUT: {
            "message": "処理に時間がかかっています。もう少々お待ちください。",
            "retry": False,
            "log_level": "ERROR"
        },
        ErrorType.UNKNOWN: {
            "message": "システムエラーが発生しました。技術サポートまでお問い合わせください。",
            "retry": False,
            "log_level": "ERROR"
        }
    }
    
    # エラータイプの判定
    if isinstance(error, HelpdeskError):
        error_type = error.error_type
    else:
        error_type = ErrorType.UNKNOWN
    
    error_info = error_responses.get(error_type, error_responses[ErrorType.UNKNOWN])
    
    # ログ出力
    if error_info["log_level"] == "WARNING":
        logger.warning(f"{context}: {error_type.value} - {str(error)}")
    else:
        logger.error(f"{context}: {error_type.value} - {str(error)}", exc_info=True)
    
    return {
        "response": error_info["message"],
        "confidence": 0.0,
        "category": f"error_{error_type.value}",
        "retry": error_info["retry"],
        "error": True
    }

def validate_input(event: Dict[str, Any]) -> Optional[str]:
    """
    入力データの検証
    
    Args:
        event: Lambdaイベントデータ
    
    Returns:
        エラーメッセージ（正常な場合はNone）
    """
    # 必須フィールドの確認
    if not event:
        return "イベントデータが空です"
    
    details = event.get('Details', {})
    if not details:
        return "Detailsフィールドが見つかりません"
    
    parameters = details.get('Parameters', {})
    if not parameters:
        return "Parametersフィールドが見つかりません"
    
    transcribed_text = parameters.get('transcribedText', '')
    if not transcribed_text or len(transcribed_text.strip()) == 0:
        return "音声認識結果が空です"
    
    # 文字数制限（悪意のある長文を防ぐ）
    if len(transcribed_text) > 1000:
        return "入力テキストが長すぎます"
    
    return None

def format_error_for_connect(error_response: Dict[str, Any]) -> Dict[str, Any]:
    """
    Amazon Connect用にエラーレスポンスをフォーマット
    
    Args:
        error_response: エラーレスポンスデータ
    
    Returns:
        Connect用にフォーマットされたレスポンス
    """
    # Connectは特定のフィールドを期待するため、適切にフォーマット
    return {
        "statusCode": 200,  # Connectへは常に200を返す
        "body": {
            "response": error_response.get("response", "エラーが発生しました"),
            "confidence": error_response.get("confidence", 0.0),
            "category": error_response.get("category", "error"),
            "processingTime": 0.0,
            "error": True,
            "retry": error_response.get("retry", False)
        }
    }
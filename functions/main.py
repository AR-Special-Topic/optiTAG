"""Authenticated Firebase callable -> Google Cloud Speech-to-Text V2."""
import os
from functools import lru_cache

from firebase_admin import initialize_app
from firebase_functions import https_fn, options
from google.api_core import exceptions
from google.api_core.client_options import ClientOptions
from google.cloud import speech_v2
from google.cloud.speech_v2.types import cloud_speech
from speech_contract import decode_pcm, extract_segments, SAMPLE_RATE

initialize_app()

REGION = "asia-southeast1"


@lru_cache(maxsize=1)
def speech_client():
    # Application Default Credentials: Cloud Functions' runtime service account.
    return speech_v2.SpeechClient(client_options=ClientOptions(api_endpoint=f"{REGION}-speech.googleapis.com"))


@https_fn.on_call(region=REGION, enforce_app_check=True, timeout_sec=120,
                 memory=options.MemoryOption.MB_512, max_instances=2, concurrency=4)
def transcribeSpeech(request: https_fn.CallableRequest) -> dict:
    if request.auth is None:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.UNAUTHENTICATED, "請先登入 Firebase")
    try:
        pcm = decode_pcm(request.data)
    except ValueError as error:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.INVALID_ARGUMENT, str(error)) from None
    project = os.environ.get("GOOGLE_CLOUD_PROJECT") or os.environ.get("GCLOUD_PROJECT")
    if not project:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.FAILED_PRECONDITION, "後端未設定 Google Cloud 專案")
    config = cloud_speech.RecognitionConfig(
        explicit_decoding_config=cloud_speech.ExplicitDecodingConfig(
            encoding=cloud_speech.ExplicitDecodingConfig.AudioEncoding.LINEAR16,
            sample_rate_hertz=SAMPLE_RATE, audio_channel_count=1),
        language_codes=["cmn-Hant-TW"], model="chirp_2",
        features=cloud_speech.RecognitionFeatures(enable_word_time_offsets=True,
                                                  enable_automatic_punctuation=True))
    try:
        response = speech_client().recognize(
            request=cloud_speech.RecognizeRequest(
                recognizer=f"projects/{project}/locations/{REGION}/recognizers/_",
                config=config, content=pcm), timeout=105, retry=None)
        return {"segments": extract_segments(response, len(pcm) / (SAMPLE_RATE * 2))}
    except exceptions.ResourceExhausted:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.RESOURCE_EXHAUSTED, "STT 配額已用完，請稍後重試") from None
    except (exceptions.DeadlineExceeded, exceptions.ServiceUnavailable):
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.UNAVAILABLE, "STT 暫時無法使用，錄音可稍後重試") from None
    except (exceptions.PermissionDenied, exceptions.Unauthenticated):
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.FAILED_PRECONDITION, "請檢查後端服務帳戶的 Speech-to-Text 權限、API 與計費") from None
    except exceptions.InvalidArgument:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.FAILED_PRECONDITION, "請檢查 STT V2 模型、語言與音訊設定") from None
    except ValueError as error:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.INTERNAL, str(error)) from None
    except Exception:
        # Never return/log audio, credentials, transcripts, or raw upstream errors.
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.INTERNAL, "STT 後端處理失敗，錄音可稍後重試") from None

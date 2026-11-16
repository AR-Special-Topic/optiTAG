"""SDK-level callable tests; install requirements.txt before running."""
import base64
import inspect
import json
import os
from types import SimpleNamespace as Obj
import unittest
from unittest.mock import patch

try:
    import main
    from firebase_functions import https_fn
    from google.api_core import exceptions
    from google.cloud.speech_v2.types import cloud_speech
except ImportError:
    main = None


@unittest.skipIf(main is None, "Install functions/requirements.txt for callable SDK tests")
class CallableTests(unittest.TestCase):
    def call(self, auth=True, data=None):
        request = Obj(auth=Obj(uid="test-user") if auth else None,
                      data=data if data is not None else {"pcm": base64.b64encode(b"\0\0" * 16000).decode()})
        return inspect.unwrap(main.transcribeSpeech)(request)

    def test_callable_transport_requires_app_check(self):
        from flask import Flask
        app = Flask(__name__)
        with app.test_request_context("/", method="POST", json={"data": {"pcm": "AAA="}}):
            from flask import request
            with patch.object(main, "speech_client") as client:
                response = main.transcribeSpeech(request)
                self.assertEqual(response.status_code, 401)
                self.assertEqual(response.get_json()["error"]["status"], "UNAUTHENTICATED")
                client.assert_not_called()

    def test_rejects_unauthenticated_before_speech(self):
        with patch.object(main, "speech_client") as client:
            with self.assertRaises(https_fn.HttpsError) as failure:
                self.call(auth=False)
            self.assertEqual(failure.exception.code, https_fn.FunctionsErrorCode.UNAUTHENTICATED)
            client.assert_not_called()

    def test_v2_request_and_timestamps(self):
        response = cloud_speech.RecognizeResponse(results=[cloud_speech.SpeechRecognitionResult(
            alternatives=[cloud_speech.SpeechRecognitionAlternative(transcript="測試", words=[
                cloud_speech.WordInfo(start_offset="0s", end_offset="0.5s", word="測試")])])])
        with patch.dict(os.environ, {"GOOGLE_CLOUD_PROJECT": "test-project"}), patch.object(main, "speech_client") as client:
            client.return_value.recognize.return_value = response
            self.assertEqual(self.call(), {"segments": [{"start": 0.0, "end": 0.5, "text": "測試"}]})
            request = client.return_value.recognize.call_args.kwargs["request"]
            self.assertEqual(request.recognizer, "projects/test-project/locations/asia-southeast1/recognizers/_")
            self.assertEqual(request.config.model, "chirp_2")
            self.assertTrue(request.config.features.enable_word_time_offsets)

    def test_silence_is_success_but_upstream_errors_are_not(self):
        with patch.dict(os.environ, {"GOOGLE_CLOUD_PROJECT": "test-project"}), patch.object(main, "speech_client") as client:
            client.return_value.recognize.return_value = cloud_speech.RecognizeResponse()
            self.assertEqual(self.call(), {"segments": []})
            for error, code in [(exceptions.PermissionDenied("private detail"), https_fn.FunctionsErrorCode.FAILED_PRECONDITION),
                                (exceptions.ResourceExhausted("private detail"), https_fn.FunctionsErrorCode.RESOURCE_EXHAUSTED),
                                (exceptions.ServiceUnavailable("private detail"), https_fn.FunctionsErrorCode.UNAVAILABLE)]:
                client.return_value.recognize.side_effect = error
                with self.assertRaises(https_fn.HttpsError) as failure:
                    self.call()
                self.assertEqual(failure.exception.code, code)
                self.assertNotIn("private detail", failure.exception.message)

    def test_internal_failure_diagnostics_cover_each_stage_without_private_data(self):
        for stage in ("config", "client", "recognize", "segments"):
            with self.subTest(stage=stage), patch.dict(os.environ, {"GOOGLE_CLOUD_PROJECT": "test-project"}), \
                    patch.object(main, "speech_client") as client, \
                    patch.object(main.cloud_speech, "RecognitionConfig") as config, \
                    patch.object(main, "extract_segments") as extract, \
                    patch("builtins.print") as log:
                config.return_value = cloud_speech.RecognizeRequest().config
                target = {"config": config, "client": client,
                          "recognize": client.return_value.recognize, "segments": extract}[stage]
                target.side_effect = RuntimeError("private transcript or credential")
                with self.assertRaises(https_fn.HttpsError) as failure:
                    self.call()
                self.assertEqual(failure.exception.code, https_fn.FunctionsErrorCode.INTERNAL)
                diagnostic = json.loads(log.call_args.args[0])
                self.assertEqual(diagnostic["stage"], stage)
                self.assertEqual(diagnostic["exception_type"], "RuntimeError")
                self.assertIn(diagnostic["diagnostic_id"], failure.exception.message)
                self.assertNotIn("private transcript", failure.exception.message)
                self.assertNotIn("private transcript", log.call_args.args[0])

    def test_invalid_payload_never_calls_google(self):
        with patch.object(main, "speech_client") as client:
            with self.assertRaises(https_fn.HttpsError) as failure:
                self.call(data={"pcm": "@@@"})
            self.assertEqual(failure.exception.code, https_fn.FunctionsErrorCode.INVALID_ARGUMENT)
            client.assert_not_called()


if __name__ == "__main__":
    unittest.main()

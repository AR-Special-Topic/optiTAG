import base64
from datetime import timedelta
from types import SimpleNamespace as Obj
import unittest
from speech_contract import decode_pcm, extract_segments, MAX_BYTES


def reply(words, transcript="測試"):
    return Obj(results=[Obj(alternatives=[Obj(transcript=transcript, words=words)])])


def word(start, end, text="測試"):
    return Obj(start_offset=timedelta(seconds=start), end_offset=timedelta(seconds=end), word=text)


class SpeechContractTests(unittest.TestCase):
    def test_maximum_and_malformed_audio(self):
        pcm = b"\x00\x00" * (MAX_BYTES // 2)
        self.assertEqual(decode_pcm({"pcm": base64.b64encode(pcm).decode()}), pcm)
        for data in [None, {}, {"pcm": ""}, {"pcm": "@@@="}, {"pcm": "YQ=="},
                     {"pcm": 123}, {"pcm": "AA==", "model": "anything"},
                     {"pcm": base64.b64encode(pcm + b"\x00\x00").decode()}]:
            with self.subTest(data_type=type(data)), self.assertRaises(ValueError):
                decode_pcm(data)

    def test_word_offsets_and_silence(self):
        self.assertEqual(extract_segments(reply([word(0, 0.5), word(0.5, 1)]), 1), [
            {"start": 0, "end": 0.5, "text": "測試"}, {"start": 0.5, "end": 1, "text": "測試"}])
        self.assertEqual(extract_segments(reply([], transcript=""), 1), [])

    def test_missing_or_invalid_timestamps_are_errors_not_silence(self):
        for response in [reply([]), reply([word(-1, 0)]), reply([word(0.5, 0.1)]),
                         reply([word(0, 2)]), reply([word(0, 1, " ")])]:
            with self.assertRaises(ValueError):
                extract_segments(response, 1)


if __name__ == "__main__":
    unittest.main()

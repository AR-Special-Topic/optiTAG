import base64
from datetime import timedelta
from types import SimpleNamespace as Obj
import unittest
from speech_contract import decode_pcm, extract_segments, MAX_BYTES, SpeechTimestampError


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

    def test_out_of_bounds_words_use_complete_chunk_without_duplicates(self):
        duration = 2.558625
        response = reply([word(0, 0.5, "前"), word(2.56, 2.64, "尾"),
                          word(2.64, 2.72, "字"), word(2.76, 2.84, "詞")], transcript="前尾字詞。")
        self.assertEqual(extract_segments(response, duration), [
            {"start": 0, "end": duration, "text": "前尾字詞。"}])
        response.results += reply([word(0.1, 0.4)], transcript="下一句。").results
        self.assertEqual(extract_segments(response, duration), [
            {"start": 0, "end": duration, "text": "前尾字詞。 下一句。"}])

    def test_invalid_later_words_still_fail_after_out_of_bounds_word(self):
        with self.assertRaises(SpeechTimestampError):
            extract_segments(reply([word(1, 2), word(-1, 0)]), 1)

    def test_invalid_timestamps_are_rejected(self):
        for start, end in [(-0.001, 0.1), (1.05, 1.01)]:
            with self.subTest(start=start, end=end), self.assertRaises(SpeechTimestampError):
                extract_segments(reply([word(start, end)]), 1)
        for value in [float("nan"), float("inf")]:
            timestamp = Obj(total_seconds=lambda: value)
            for invalid in [Obj(start_offset=timestamp, end_offset=timedelta(seconds=1), word="測試"),
                            Obj(start_offset=timedelta(), end_offset=timestamp, word="測試")]:
                with self.assertRaises(SpeechTimestampError):
                    extract_segments(reply([invalid]), 1)

    def test_invalid_timing_exposes_numbers_without_transcript(self):
        with self.assertRaises(SpeechTimestampError) as failure:
            extract_segments(reply([word(3, 0, "private transcript")]), 2.56)
        self.assertEqual(failure.exception.timing, {"start": 3, "end": 0, "duration": 2.56})
        self.assertNotIn("private transcript", str(failure.exception))
        self.assertIn("2.560000", str(failure.exception))

    def test_missing_or_invalid_timestamps_are_errors_not_silence(self):
        for response in [reply([]), reply([word(-1, 0)]), reply([word(0.5, 0.1)]),
                         reply([word(0, 1, " ")])]:
            with self.assertRaises(ValueError):
                extract_segments(response, 1)


if __name__ == "__main__":
    unittest.main()

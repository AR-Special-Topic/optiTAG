"""Pure validation shared by the callable and offline tests."""
import base64
import binascii
import math

SAMPLE_RATE = 16000
MAX_BYTES = SAMPLE_RATE * 2 * 50


def decode_pcm(data):
    if not isinstance(data, dict) or set(data) != {"pcm"}:
        raise ValueError("請提供 pcm 音訊欄位")
    encoded = data["pcm"]
    if not isinstance(encoded, str) or not encoded or len(encoded) > 4 * ((MAX_BYTES + 2) // 3):
        raise ValueError("音訊必須為最多 50 秒的 16kHz 單聲道 PCM16")
    try:
        pcm = base64.b64decode(encoded, validate=True)
    except (ValueError, binascii.Error) as error:
        raise ValueError("音訊不是有效的 Base64") from error
    if not pcm or len(pcm) > MAX_BYTES or len(pcm) % 2:
        raise ValueError("PCM16 音訊長度無效")
    return pcm


class SpeechTimestampError(ValueError):
    """Numeric timing diagnostics only; never retain recognized text."""
    def __init__(self, start, end, duration):
        self.timing = {"start": start, "end": end, "duration": duration}
        super().__init__(f"Google STT 時間戳超出音訊範圍（start={start:.6f}, end={end:.6f}, duration={duration:.6f} 秒）")


def extract_segments(response, duration):
    if not math.isfinite(duration) or duration <= 0:
        raise ValueError("音訊長度無效")
    segments = []
    transcripts = []
    use_chunk_timing = False
    for result in response.results:
        if not result.alternatives:
            continue
        alternative = result.alternatives[0]
        if alternative.transcript.strip() and not alternative.words:
            raise ValueError("Google STT 未回傳要求的逐字時間戳")
        text = alternative.transcript.strip() or " ".join(word.word for word in alternative.words).strip()
        if text:
            transcripts.append(text)
        for word in alternative.words:
            start = word.start_offset.total_seconds()
            end = word.end_offset.total_seconds()
            if not (math.isfinite(start) and math.isfinite(end) and 0 <= start <= end):
                raise SpeechTimestampError(start, end, duration)
            if not word.word.strip():
                raise ValueError("Google STT 回傳空白字詞")
            if end > duration:
                use_chunk_timing = True
            segments.append({"start": start, "end": end, "text": word.word})
    if use_chunk_timing:
        # Text belongs to this request's PCM, but word alignment is unusable.
        # Replace the whole chunk to avoid duplicate text or fabricated word timing.
        return [{"start": 0.0, "end": duration, "text": " ".join(transcripts)}]
    return segments

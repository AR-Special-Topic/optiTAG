import Foundation

@main struct GoogleSpeechFailureChecks {
    static func main() throws {
        let key = "AIzaFakeKeyOnlyForTests12345678901234567"
        let invalid = try JSONSerialization.data(withJSONObject: ["error": ["code": 400, "status": "INVALID_ARGUMENT", "message": "API key not valid. Provided: " + key, "details": [["reason": "API_KEY_INVALID", "domain": "googleapis.com"]]]])
        let diagnostic = GoogleSpeechFailure(statusCode: 400, data: invalid, apiKey: key, offset: 50, duration: 12).localizedDescription
        precondition(diagnostic.contains("INVALID_ARGUMENT") && diagnostic.contains("API_KEY_INVALID"))
        precondition(diagnostic.contains("重新貼上") && diagnostic.contains("50.00–62.00"))
        precondition(!diagnostic.contains(key) && diagnostic.contains("已隱藏金鑰"))
        let badAudio = Data(#"{"error":{"message":"Invalid recognition config","status":"INVALID_ARGUMENT","details":[{"fieldViolations":[{"field":"config.sampleRateHertz","description":"invalid sample rate"}]}]}}"#.utf8)
        let audio = GoogleSpeechFailure(statusCode: 400, data: badAudio, apiKey: key, offset: 0, duration: 1).localizedDescription
        precondition(audio.contains("config.sampleRateHertz") && audio.contains("invalid sample rate") && audio.contains("錄音已保留"))
        let disabled = Data(#"{"error":{"message":"API disabled","status":"PERMISSION_DENIED","details":[{"reason":"SERVICE_DISABLED"}]}}"#.utf8)
        let permission = GoogleSpeechFailure(statusCode: 403, data: disabled, apiKey: key, offset: 0, duration: 1).localizedDescription
        precondition(permission.contains("啟用 Speech-to-Text API"))
        let malformed = GoogleSpeechFailure(statusCode: 400, data: Data("<html>".utf8), apiKey: key, offset: 0, duration: 1).localizedDescription
        precondition(malformed.contains("HTTP 400") && malformed.contains("錄音已保留"))
        print("Google STT error checks passed: API reason, field violations, key redaction, chunk context, service setup and non-JSON response")
    }
}

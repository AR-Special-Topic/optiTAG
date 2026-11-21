import Foundation

/// Retain only a redacted diagnostic, never the response body or request credential.
struct GoogleSpeechFailure: LocalizedError {
    let errorDescription: String?

    init(statusCode: Int, data: Data, apiKey: String, offset: Double, duration: Double) {
        struct Envelope: Decodable {
            struct APIError: Decodable {
                struct Detail: Decodable {
                    struct Violation: Decodable { let field: String?; let description: String? }
                    let reason: String?
                    let fieldViolations: [Violation]?
                }
                let message: String?
                let status: String?
                let details: [Detail]?
            }
            let error: APIError?
        }
        let apiError = (try? JSONDecoder().decode(Envelope.self, from: data))?.error
        let reasons = apiError?.details?.compactMap(\.reason) ?? []
        let fields = apiError?.details?.flatMap { $0.fieldViolations ?? [] }.map {
            [$0.field, $0.description].compactMap { $0 }.joined(separator: ": ")
        } ?? []
        var lines = [String(format: "Google STT HTTP %d（錄音 %.2f–%.2f 秒）", statusCode, offset, offset + duration)]
        if let status = apiError?.status { lines.append(status) }
        if let message = apiError?.message, !message.isEmpty { lines.append(message) }
        if !reasons.isEmpty { lines.append("原因：" + reasons.joined(separator: ", ")) }
        lines.append(contentsOf: fields)
        if reasons.contains("API_KEY_INVALID") || apiError?.message?.lowercased().contains("api key not valid") == true {
            lines.append("API 金鑰無效：請在設定重新貼上 Google Cloud API 金鑰，不要使用 OAuth token、專案 ID 或金鑰 ID。")
        } else if reasons.contains("SERVICE_DISABLED") {
            lines.append("請在這把金鑰所屬的 Google Cloud 專案啟用 Speech-to-Text API。")
        } else if reasons.contains("BILLING_DISABLED") {
            lines.append("請啟用金鑰所屬 Google Cloud 專案的計費。")
        } else if reasons.contains(where: { $0.hasPrefix("API_KEY_") && $0.hasSuffix("BLOCKED") }) {
            lines.append("請檢查這把金鑰的 API 與應用程式限制是否允許此 App 呼叫 Speech-to-Text API。")
        } else if statusCode == 400 {
            lines.append("請依上述 Google 錯誤確認金鑰或音訊參數；HTTP 400 不代表沒有語音。")
        } else if apiError == nil {
            lines.append("伺服器未提供可解析的 Google 錯誤訊息。")
        }
        lines.append("錄音已保留，修正後可按「重試轉寫」。")
        var diagnostic = lines.joined(separator: "\n")
        if !apiKey.isEmpty { diagnostic = diagnostic.replacingOccurrences(of: apiKey, with: "[已隱藏金鑰]") }
        // Also redact key-shaped strings if the server returns a different credential.
        diagnostic = diagnostic.replacingOccurrences(of: "AIza[0-9A-Za-z_-]+", with: "[已隱藏金鑰]", options: .regularExpression)
        errorDescription = String(diagnostic.prefix(2400))
    }
}

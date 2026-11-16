import SwiftUI
import EventPipeSDExport

struct ConversationsView: View {
    @ObservedObject var store: ConversationStore
    @ObservedObject var ble: BLEManager
    @State private var query = ""
    @State private var limit = 100
    @State private var deleting: ConversationSummary?
    var body: some View {
        List {
            Section {
                Text(store.status).font(.subheadline).textSelection(.enabled)
                ForEach(store.importWarnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                Button("下載並轉寫") { store.run(ble: ble) }.disabled(store.busy || ble.isChangingVAD)
                Button("清理裝置錄音（連線後自動補做）") { store.requestAudioCleanup(ble: ble) }
                    .disabled(store.busy || ble.isExporting || ble.isChangingVAD)
                if store.cleanupDeviceID != nil {
                    Text("等待原裝置連線後自動清理；只會刪除已處理的 WAV。").font(.caption)
                    Button("取消等待清理") { store.cancel() }
                }
                Button("重試轉寫") { store.retry() }.disabled(store.busy)
                Button("彙整對話") { store.retry(summarizing: true) }.disabled(store.busy)
                if store.cleanupTotal > 0 {
                    VStack(alignment: .leading) {
                        Text("剩餘待刪除：\(store.cleanupRemaining)／\(store.cleanupTotal) 筆")
                            .monospacedDigit()
                        ProgressView(value: Double(store.cleanupTotal - store.cleanupRemaining), total: Double(store.cleanupTotal))
                        if store.cleanupActive && store.cleanupRemaining == 0 {
                            Text("錄音已清理，正在等待裝置恢復…").font(.caption)
                        }
                    }
                }
                if let progress = ble.exportProgress { SDExportProgressView(progress: progress) }
                if store.busy { ProgressView(); Button("取消") { store.cancel() } }
            }
            if let prompt = ble.wiFiJoinPrompt {
                Section("手動加入裝置 Wi-Fi") {
                    Text("請在 90 秒內前往 iPhone「設定 → Wi-Fi」加入以下網路，然後返回此頁按繼續。刪除裝置錄音時會再次要求加入當次的新網路。")
                    LabeledContent("網路名稱", value: prompt.ssid).textSelection(.enabled)
                    LabeledContent("密碼", value: prompt.password).textSelection(.enabled)
                    Button("已加入 Wi-Fi，繼續") { ble.confirmWiFiJoined() }
                    Text("返回後會驗證裝置連線；若逾時請重新下載。密碼只用於本次連線。").font(.caption)
                }
            }
            Section("對話重點") {
                if store.summaries.isEmpty { Text("尚無彙整紀錄").foregroundStyle(.secondary) }
                ForEach(store.summaries.filter { query.isEmpty || ([$0.title, $0.overview] + $0.tasks + $0.decisions + $0.questions).joined().localizedCaseInsensitiveContains(query) }) { summary in
                    NavigationLink {
                        List {
                            Section("重點") { Text(displayText(summary.overview)) }
                            if !summary.decisions.isEmpty { Section("決定") { ForEach(summary.decisions, id: \.self) { Text(displayText($0)) } } }
                            if !summary.tasks.isEmpty { Section("待辦與約定") { ForEach(summary.tasks, id: \.self) { Text(displayText($0)) } } }
                            if !summary.questions.isEmpty { Section("待確認") { ForEach(summary.questions, id: \.self) { Text(displayText($0)) } } }
                            Section("出現人物（不代表說話者）") {
                                let records = store.sources(for: summary).flatMap(\.faceAssociations)
                                let names = Array(Set(records.filter { $0["image_id"] != "0" }.map(personKey))).sorted()
                                if names.isEmpty { Text("沒有可用的人臉辨識紀錄").foregroundStyle(.secondary) }
                                ForEach(names, id: \.self) { name in
                                    DisclosureGroup(records.first(where: { personKey($0) == name })?["name"] ?? "未知人物") {
                                        ForEach(Array(records.filter { personKey($0) == name }.enumerated()), id: \.offset) { _, record in
                                            Text([record["tag"], record["status"], record["similarity"]].compactMap { $0 }.joined(separator: " · "))
                                                .font(.caption)
                                        }
                                    }
                                }
                            }
                            Section("來源逐字稿") {
                                Text(store.sources(for: summary).flatMap(\.segments).map(\.text).joined(separator: "\n"))
                                    .textSelection(.enabled)
                            }
                            Section {
                                Button("刪除對話重點與來源", role: .destructive) { deleting = summary }.disabled(store.busy)
                            }
                        }.navigationTitle(summary.title)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(summary.title).font(.headline)
                            Text(displayText(summary.overview)).font(.subheadline).lineLimit(3)
                            Text("\(summary.tasks.count) 項待辦 · \(summary.sourceIDs.count) 段語音").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions { Button("刪除", role: .destructive) { deleting = summary }.disabled(store.busy) }
                }
            }
            if store.summaries.count >= limit {
                Button("載入更多對話") { limit += 100; store.search(query, limit: limit) }
            }
            Section("處理狀態（最近 100 筆）") {
                ForEach(store.events.filter { !$0.localAudioDeleted && $0.contentDeleted != true }.sorted { $0.id > $1.id }) { event in
                    VStack(alignment: .leading) {
                        Text(event.eventID).font(.caption.monospaced())
                        Text(event.state)
                        if let error = event.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                    }
                }
            }
        }.onChange(of: query) { _, value in limit = 100; store.search(value) }
        .alert("刪除對話重點與來源？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("取消", role: .cancel) { deleting = nil }
            Button("刪除", role: .destructive) { if let deleting { store.deleteSummary(deleting) }; deleting = nil }
        } message: { Text("將刪除重點及專屬的逐字稿、人臉紀錄；其他重點引用的來源會保留。") }
        .navigationTitle("對話紀錄").searchable(text: $query, prompt: "搜尋重點、待辦或約定")
    }
}

private func personKey(_ row: [String: String]) -> String {
    if row["status"] == "RECOGNIZED", let id = row["person_id"], !id.isEmpty { return "person:" + id }
    return "unknown:" + (row["status"] ?? "UNKNOWN")
}

private func displayText(_ text: String) -> String {
    text.replacingOccurrences(of: #"(?:\s*\[[0-9A-F]{16} \d+\.\d{2}–\d+\.\d{2} 秒\])+$"#, with: "", options: .regularExpression)
}

struct ConversationSettingsView: View {
    @ObservedObject var store: ConversationStore
    var body: some View {
        Form {
            Section("Google Speech-to-Text V2") {
                Text("Google 備援透過 Firebase Cloud Function 轉寫，無需輸入 API 金鑰。App 會自動匿名登入 Firebase；後端須完成部署並啟用匿名登入與 App Check。").font(.caption)
            }
            Section("Firebase AI") {
                TextField("模型名稱", text: $store.modelName).textInputAutocapitalization(.never).autocorrectionDisabled()
                Text("需在 Firebase Console 啟用 AI Logic；錄音優先於支援裝置上轉寫，Google 備援會上傳音訊，摘要會傳送轉寫文字至 Firebase AI。").font(.caption)
            }
        }.navigationTitle("設定").scrollDismissesKeyboard(.interactively)
    }
}

import SwiftUI

struct ConversationsView: View {
    @ObservedObject var store: ConversationStore
    @ObservedObject var ble: BLEManager
    @State private var query = ""
    @State private var limit = 100
    var body: some View {
        List {
            Section {
                Text(store.status).font(.subheadline).textSelection(.enabled)
                ForEach(store.importWarnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                Button("從裝置下載並彙整") { store.run(ble: ble) }.disabled(store.busy)
                Button("重試未完成的彙整") { store.retry() }.disabled(store.busy)
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
                            Section("重點") { Text(summary.overview) }
                            if !summary.decisions.isEmpty { Section("決定") { ForEach(summary.decisions, id: \.self) { Text($0) } } }
                            if !summary.tasks.isEmpty { Section("待辦與約定") { ForEach(summary.tasks, id: \.self) { Text($0) } } }
                            if !summary.questions.isEmpty { Section("待確認") { ForEach(summary.questions, id: \.self) { Text($0) } } }
                            Section("來源逐字稿（開機秒；摘要引用為 WAV 秒）") {
                                ForEach(store.sources(for: summary)) { event in
                                    DisclosureGroup(event.eventID) {
                                        ForEach(Array(event.segments.enumerated()), id: \.offset) { _, segment in
                                            Text(String(format: "[%.2f–%.2f 秒] %@", event.bootSeconds(segment.start), event.bootSeconds(segment.end), segment.text))
                                        }
                                    }
                                }
                            }
                        }.navigationTitle(summary.title)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(summary.title).font(.headline)
                            Text(summary.overview).font(.subheadline).lineLimit(3)
                            Text("\(summary.tasks.count) 項待辦 · \(summary.sourceIDs.count) 段語音").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if store.summaries.count >= limit {
                Button("載入更多對話") { limit += 100; store.search(query, limit: limit) }
            }
            Section("處理狀態（最近 100 筆）") {
                ForEach(store.events.sorted { $0.id > $1.id }) { event in
                    VStack(alignment: .leading) {
                        Text(event.eventID).font(.caption.monospaced())
                        Text(event.state)
                        if let error = event.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                        if event.localAudioDeleted { Text(event.deviceAudioDeleted ? "手機與裝置錄音已刪除" : "手機錄音已刪除；裝置待確認刪除").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }.onChange(of: query) { _, value in limit = 100; store.search(value) }
        .navigationTitle("對話紀錄").searchable(text: $query, prompt: "搜尋重點、待辦或約定")
    }
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

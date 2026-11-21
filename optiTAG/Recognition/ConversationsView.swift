import SwiftUI
import UIKit
import EventPipeSDExport

struct ConversationsView: View {
    @ObservedObject var store: ConversationStore
    @ObservedObject var ble: BLEManager
    @State private var showsSearch = false
    @State private var limit = 100
    @State private var copiedField: String?
    @State private var deleting: ConversationSummary?
    var body: some View {
        List {
            Section {
                ForEach(store.importWarnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                Button("下載錄音與事件資料") { store.run(ble: ble) }
                    .disabled(!ble.isConnected || store.busy || ble.isExporting || ble.isChangingVAD)
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
                if store.busy { Button("取消") { store.cancel() } }
            }
            if let prompt = ble.wiFiJoinPrompt {
                Section("手動加入裝置 Wi-Fi") {
                    Text("請在 90 秒內前往 iPhone「設定 → Wi-Fi」加入以下網路，然後返回此頁按繼續。刪除裝置錄音時會再次要求加入當次的新網路。")
                    copyableValue("網路名稱", value: prompt.ssid)
                    copyableValue("密碼", value: prompt.password)
                    Button("已加入 Wi-Fi，繼續") { ble.confirmWiFiJoined() }
                    Text("返回後會驗證裝置連線；若逾時請重新下載。密碼只用於本次連線。").font(.caption)
                }
            }
            Section("對話重點") {
                if store.summaries.isEmpty { Text("尚無彙整紀錄").foregroundStyle(.secondary) }
                ForEach(store.summaries) { summary in
                    summaryLink(summary, allowsDeletion: true)
                        .contextMenu { Button("刪除", systemImage: "trash", role: .destructive) { deleting = summary }.disabled(store.busy) }
                }
            }
            if store.summaries.count >= limit {
                Button("載入更多對話") { limit += 100; store.search("", limit: limit) }
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
        }
        .alert("刪除對話重點與來源？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("取消", role: .cancel) { deleting = nil }
            Button("刪除", role: .destructive) { if let deleting { store.deleteSummary(deleting) }; deleting = nil }
        } message: { Text("將刪除重點及專屬的逐字稿、人臉紀錄；其他重點引用的來源會保留。") }
        .safeAreaInset(edge: .bottom, alignment: .leading, spacing: 0) {
            Button {
                showsSearch = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.headline)
                    .frame(width: 46, height: 46)
                    .background(.regularMaterial, in: Circle())
                    .overlay { Circle().strokeBorder(OptiTagColors.border).allowsHitTesting(false) }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(OptiTagColors.accent)
            .accessibilityLabel("搜尋對話")
            .padding(.leading, 16)
            .padding(.vertical, 6)
        }
        .sheet(isPresented: $showsSearch) {
            ConversationSearchView(store: store) { summary in
                summaryLink(summary, allowsDeletion: false)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Label("處理進度", systemImage: "waveform")
                    .font(.caption.bold())
                Text(ble.wiFiJoinPrompt != nil ? "等待加入裝置 Wi-Fi" : store.status)
                    .font(.subheadline)
                    .textSelection(.enabled)
                if let progress = ble.exportProgress {
                    SDExportProgressView(progress: progress)
                } else if store.busy && ble.wiFiJoinPrompt == nil {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial)
        }
    }

    private func summaryLink(_ summary: ConversationSummary, allowsDeletion: Bool) -> some View {
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
                    let transcript = store.sources(for: summary).flatMap(\.segments).map(\.text).joined(separator: "\n")
                    Text(transcript).textSelection(.enabled)
                    Button {
                        UIPasteboard.general.string = transcript
                        copiedField = "逐字稿"
                    } label: {
                        Label(copiedField == "逐字稿" ? "已複製逐字稿" : "複製逐字稿", systemImage: "doc.on.doc")
                            .frame(minHeight: 44)
                    }
                    .disabled(transcript.isEmpty)
                }
                if allowsDeletion {
                    Section {
                        Button("刪除對話重點與來源", role: .destructive) { deleting = summary }.disabled(store.busy)
                    }
                }
            }.navigationTitle(summary.title)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(summary.title).font(.headline)
                Text(displayText(summary.overview)).font(.subheadline).lineLimit(3)
                Text("\(summary.tasks.count) 項待辦 · \(summary.sourceIDs.count) 段語音").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func copyableValue(_ title: String, value: String) -> some View {
        LabeledContent {
            HStack(spacing: 8) {
                Text(value).textSelection(.enabled)
                Button {
                    UIPasteboard.general.setItems(
                        [["public.utf8-plain-text": value]],
                        options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)]
                    )
                    copiedField = title
                } label: {
                    Image(systemName: copiedField == title ? "checkmark" : "doc.on.doc")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(copiedField == title ? "已複製\(title)" : "複製\(title)")
            }
        } label: {
            Text(title)
        }
    }

}

private struct ConversationSearchView<Row: View>: View {
    @ObservedObject var store: ConversationStore
    @ViewBuilder var row: (ConversationSummary) -> Row
    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFocused: Bool
    @State private var query = ""
    @State private var limit = 100
    @State private var results: [ConversationSummary] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Text(error).foregroundStyle(.red)
                } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("輸入關鍵字搜尋對話").foregroundStyle(.secondary)
                } else if results.isEmpty {
                    Text("找不到相符的對話").foregroundStyle(.secondary)
                } else {
                    ForEach(results) { summary in row(summary) }
                    if results.count == limit {
                        Button("載入更多") { limit += 100; search() }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .top, spacing: 0) {
                TextField("搜尋重點、待辦或約定", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .onSubmit { searchFocused = false }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.regularMaterial)
            }
            .navigationTitle("搜尋對話")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("關閉") { dismiss() } } }
            .onChange(of: query) { _, _ in limit = 100; search() }
        }
    }

    private func search() {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            results = keyword.isEmpty ? [] : try store.searchResults(for: keyword, limit: limit)
            error = nil
        } catch {
            results = []
            self.error = error.localizedDescription
        }
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
    @AppStorage("optiTAG.appearance") private var appearance = AppAppearance.system
    @ObservedObject var store: ConversationStore
    var body: some View {
        Form {
            Section("外觀") {
                Picker("主題", selection: $appearance) {
                    ForEach(AppAppearance.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
            }
            NavigationLink("App 資訊") { AppInformationView(store: store) }
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct AppInformationView: View {
    @ObservedObject var store: ConversationStore

    var body: some View {
        List {
            Section("optiTAG") {
                LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                LabeledContent("建置版本", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
                Text("搭配 ESP32-S3 穿戴裝置，提供人物辨識與對話紀錄的社交輔助 App。")
            }
            Section("Google Speech-to-Text V2") {
                Text("Google 備援透過 Firebase Cloud Function 轉寫，無需輸入 API 金鑰。App 會自動匿名登入 Firebase；後端須完成部署並啟用匿名登入與 App Check。")
            }
            Section("Firebase AI") {
                TextField("模型名稱", text: $store.modelName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("需在 Firebase Console 啟用 AI Logic。支援的裝置會優先在本機轉寫，Google 備援會上傳音訊。摘要會傳送轉寫文字至 Firebase AI。")
            }
        }
        .navigationTitle("App 資訊")
    }
}

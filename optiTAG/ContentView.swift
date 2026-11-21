import SwiftUI
import UIKit

struct ContentView: View {
    @AppStorage("optiTAG.appearance") private var appearance = AppAppearance.system
    @State private var selectedTab = "home"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let tabs = [
        (id: "home", title: "首頁", icon: "house", selectedIcon: "house.fill"),
        (id: "database", title: "人物", icon: "person.crop.circle", selectedIcon: "person.crop.circle.fill"),
        (id: "log", title: "對話", icon: "bubble.left.and.bubble.right", selectedIcon: "bubble.left.and.bubble.right.fill"),
        (id: "settings", title: "設定", icon: "gearshape", selectedIcon: "gearshape.fill"),
        (id: "notifications", title: "通知", icon: "bell", selectedIcon: "bell.fill")
    ]

    @StateObject private var model = MainViewModel()
    @StateObject private var conversations = ConversationStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $selectedTab) {
                    MainView(viewModel: model).tag("home")
                    PeopleView(viewModel: model).tag("database")
                    ConversationsView(store: conversations, ble: model.ble).tag("log")
                    ConversationSettingsView(store: conversations).tag("settings")
                    NotificationsView(model: model, conversations: conversations).tag("notifications")
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 2) {
                    ForEach(tabs.indices, id: \.self) { index in
                        let tab = tabs[index]
                        navigationButton(tab.title, icon: selectedTab == tab.id ? tab.selectedIcon : tab.icon, tab: tab.id)
                    }
                }
                .padding(5)
                .background(OptiTagColors.navigation, in: RoundedRectangle(cornerRadius: 24))
                .overlay {
                    RoundedRectangle(cornerRadius: 24).strokeBorder(OptiTagColors.border)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 25).onEnded { value in
                        let offset = value.translation
                        guard abs(offset.width) > abs(offset.height) * 1.4,
                              let current = tabs.firstIndex(where: { $0.id == selectedTab }) else { return }
                        let next = current + (offset.width < 0 ? 1 : -1)
                        if tabs.indices.contains(next) { selectTab(tabs[next].id) }
                    }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
                .background {
                    OptiTagColors.navigation.ignoresSafeArea(.container, edges: .bottom)
                }
            }
            .navigationTitle(pageTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    (Text("opti").foregroundStyle(Color.primary) + Text("TAG").foregroundStyle(OptiTagColors.accent))
                        .font(.headline.bold())
                        .accessibilityLabel("optiTAG")
                }
            }
        }
        .tint(OptiTagColors.accent)
        .preferredColorScheme(appearance.colorScheme)
        .onAppear {
            model.ble.onEventFace = { device, event, row in conversations.recordFace(deviceID: device, eventID: event, row: row) }
        }
        .onReceive(model.ble.$isConnected) { connected in
            if connected && conversations.cleanupDeviceID != nil {
                selectedTab = "log"
                Task { @MainActor in conversations.resumeAudioCleanupIfReady(ble: model.ble) }
            }
        }
        .onChange(of: conversations.busy) { _, busy in
            if !busy { conversations.resumeAudioCleanupIfReady(ble: model.ble) }
        }
        .onChange(of: model.ble.isChangingVAD) { _, changing in
            if !changing { conversations.resumeAudioCleanupIfReady(ble: model.ble) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { conversations.resumeAudioCleanupIfReady(ble: model.ble) }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .background && model.ble.wiFiJoinPrompt == nil { conversations.suspendForBackground() } }

    }
    private var pageTitle: String {
        switch selectedTab {
        case "database": "人物資料庫"
        case "log": "對話紀錄"
        case "settings": "設定"
        case "notifications": "通知"
        default: "optiTAG"
        }
    }

    private func selectTab(_ tab: String) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            selectedTab = tab
        }
    }

    private func navigationButton(_ title: String, icon: String, tab: String) -> some View {
        let isSelected = selectedTab == tab
        return Button { selectTab(tab) } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 19))
                Text(title).font(.caption2.weight(isSelected ? .semibold : .regular))
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(isSelected ? OptiTagColors.accent : Color.secondary)
            .background(isSelected ? OptiTagColors.card : Color.clear, in: Capsule())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct NotificationsView: View {
    @ObservedObject var model: MainViewModel
    @ObservedObject var conversations: ConversationStore
    var body: some View {
        List {
            Section("裝置") {
                Text(model.ble.statusText)
                if let error = model.ble.errorText { Text(error).foregroundStyle(.red) }
                if let error = model.ble.vadError { Text(error).foregroundStyle(.red) }
            }
            Section("對話紀錄") {
                Text(conversations.status)
                ForEach(conversations.importWarnings, id: \.self) { Text($0) }
            }
            if let error = model.databaseErrorMessage {
                Section("資料庫") { Text(error).foregroundStyle(.red) }
            }
        }
        .textSelection(.enabled)
    }
}

enum AppAppearance: String, CaseIterable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: "跟隨系統"
        case .light: "淺色"
        case .dark: "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum OptiTagColors {
    static let accent = adaptive(light: 0x7c3aed, dark: 0xc4a5ff)
    static let navigation = adaptive(light: 0xede9fe, dark: 0x302445)
    static let background = adaptive(light: 0xf8f7ff, dark: 0x15111d)
    static let card = adaptive(light: 0xffffff, dark: 0x221b2f)
    static let border = adaptive(light: 0xe5e7eb, dark: 0x48395e)

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((value >> 16) & 255) / 255,
                green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255,
                alpha: 1
            )
        })
    }
}

import SwiftUI

struct ContentView: View {
    @State private var isMenuOpen = false
    @State private var selectedTab = "home"

    @StateObject private var model = MainViewModel()
    @StateObject private var conversations = ConversationStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack(alignment: .leading) {
            NavigationStack {
                Group {
                    switch selectedTab {
                    case "database": PeopleView(viewModel: model)
                    case "log": ConversationsView(store: conversations, ble: model.ble)
                    case "settings": ConversationSettingsView(store: conversations)
                    default: MainView(isMenuOpen: $isMenuOpen, viewModel: model)
                    }
                }
                .toolbar {
                    if selectedTab != "home" {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { withAnimation { isMenuOpen.toggle() } } label: { Image(systemName: "line.3.horizontal") }
                        }
                    }
                }
            }

            if isMenuOpen {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut) { isMenuOpen = false }
                    }

                SideMenuView(selectedTab: $selectedTab, isMenuOpen: $isMenuOpen)
                    .frame(width: 260)
                    .transition(.move(edge: .leading))
            }
        }
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
        .animation(.easeInOut(duration: 0.25), value: isMenuOpen)
    }
}

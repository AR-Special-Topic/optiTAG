import SwiftUI

struct SideMenuView: View {
    @Binding var selectedTab: String
    @Binding var isMenuOpen: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 0) {
                    Text("opti")
                        .font(.title2).bold()
                        .foregroundStyle(.primary)
                    Text("TAG")
                        .font(.title2).bold()
                        .foregroundStyle(Color(hex: "#7c3aed"))
                }
                Text("v1.0.0")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            VStack(spacing: 0) {
                MenuRow(icon: "house", title: "首頁", isActive: selectedTab == "home")
                    .onTapGesture { select("home") }
                MenuRow(icon: "cylinder", title: "資料庫", isActive: selectedTab == "database")
                    .onTapGesture { select("database") }
                MenuRow(icon: "clock", title: "對話紀錄", isActive: selectedTab == "log")
                    .onTapGesture { select("log") }
            }

            Divider().padding(.vertical, 4)

            MenuRow(icon: "gearshape", title: "設定", isActive: selectedTab == "settings")
                .onTapGesture { select("settings") }

            Spacer()
        }
        .frame(maxHeight: .infinity)
        .background(Color.white)
    }

    private func select(_ tab: String) {
        selectedTab = tab
        withAnimation(.easeInOut) { isMenuOpen = false }
    }
}

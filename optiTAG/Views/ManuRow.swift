import SwiftUI

struct MenuRow: View {
    let icon: String
    let title: String
    var isActive: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(isActive ? Color(hex: "#7c3aed") : .secondary)
            Text(title)
                .foregroundStyle(isActive ? Color(hex: "#7c3aed") : .primary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(isActive ? Color(hex: "#ede9fe") : Color.clear)
    }
}

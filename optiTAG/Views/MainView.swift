import SwiftUI

struct MainView: View {
    @Binding var isMenuOpen: Bool
    @StateObject private var viewModel = MainViewModel()

    var body: some View {
        VStack(spacing: 0) {

            // 頂部導覽列
            HStack {
                Button {
                    withAnimation(.easeInOut) { isMenuOpen.toggle() }
                } label: {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(hex: "#e5e7eb"), lineWidth: 0.5)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 14))
                                .foregroundStyle(.primary)
                        )
                }

                Spacer()

                HStack(spacing: 0) {
                    Text("opti").font(.headline).foregroundStyle(.primary)
                    Text("TAG").font(.headline).foregroundStyle(Color(hex: "#7c3aed"))
                }

                Spacer()

                Circle()
                    .stroke(Color(hex: "#e5e7eb"), lineWidth: 0.5)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "bell")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(spacing: 16) {

                    // ESP32 連線狀態卡片
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(hex: "#ede9fe"))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: "cpu")
                                    .foregroundStyle(Color(hex: "#7c3aed"))
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ESP32")
                                .font(.subheadline).bold()
                            Text(viewModel.ble.statusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(viewModel.ble.isConnected ? "在線" : "離線")
                                .font(.caption).bold()
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color(hex: "#ede9fe"))
                                .foregroundStyle(Color(hex: "#7c3aed"))
                                .clipShape(Capsule())
                            Text(viewModel.ble.imageInfo ?? "BLE")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color(hex: "#e5e7eb"), lineWidth: 0.5)
                    )

                    // 辨識紀錄
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("辨識紀錄")
                                .font(.subheadline).bold()
                            Spacer()
                            Text("查看全部")
                                .font(.caption)
                                .foregroundStyle(Color(hex: "#2563eb"))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)

                        Divider()

                        if let databaseErrorMessage = viewModel.databaseErrorMessage {
                            Text(databaseErrorMessage)
                                .font(.caption)
                                .foregroundStyle(Color(hex: "#dc2626"))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                        } else if viewModel.logs.isEmpty {
                            Text("目前沒有辨識紀錄")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                        } else {
                            ForEach(viewModel.logs) { log in
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(backgroundColor(for: log))
                                        .frame(width: 36, height: 36)
                                        .overlay(
                                            Text(log.initial)
                                                .font(.subheadline).bold()
                                                .foregroundStyle(foregroundColor(for: log))
                                        )
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(log.name)
                                            .font(.subheadline)
                                            .foregroundStyle(log.isUnknown ? .secondary : .primary)
                                        Text(relativeTimeString(for: log.recognizedAt))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(log.tag)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(tagBackgroundColor(for: log))
                                        .foregroundStyle(foregroundColor(for: log))
                                        .clipShape(Capsule())
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)

                                if log.id != viewModel.logs.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color(hex: "#e5e7eb"), lineWidth: 0.5)
                    )
                }
                .padding(16)
            }

            // 掃描按鈕
            Button {
                viewModel.startBLEScanOrCapture()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "viewfinder")
                    Text("開始掃描")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(hex: "#7c3aed"))
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .background(Color(hex: "#f8f7ff"))
    }

    private func relativeTimeString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func foregroundColor(for log: RecognitionLog) -> Color {
        if log.isUnknown {
            return Color(hex: "#9ca3af")
        }

        switch log.tag {
        case "朋友":
            return Color(hex: "#2563eb")
        default:
            return Color(hex: "#7c3aed")
        }
    }

    private func backgroundColor(for log: RecognitionLog) -> Color {
        if log.isUnknown {
            return Color(hex: "#f3f4f6")
        }

        switch log.tag {
        case "朋友":
            return Color(hex: "#dbeafe")
        default:
            return Color(hex: "#ede9fe")
        }
    }

    private func tagBackgroundColor(for log: RecognitionLog) -> Color {
        if log.isUnknown {
            return Color(hex: "#fee2e2")
        }

        switch log.tag {
        case "同學", "朋友":
            return Color(hex: "#dbeafe")
        default:
            return Color(hex: "#ede9fe")
        }
    }
}

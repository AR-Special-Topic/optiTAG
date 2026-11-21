import SwiftUI

struct MainView: View {
    @ObservedObject var viewModel: MainViewModel


    @State private var scanRequested = false

    private var scanInProgress: Bool {
        let ble = viewModel.ble
        return !ble.isConnected && ble.errorText == nil &&
            (scanRequested || ble.statusText.hasPrefix("連線中"))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {

                    // ESP32 連線狀態卡片
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(OptiTagColors.navigation)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: "cpu")
                                    .foregroundStyle(OptiTagColors.accent)
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
                                .background(OptiTagColors.navigation)
                                .foregroundStyle(OptiTagColors.accent)
                                .clipShape(Capsule())
                            Text(viewModel.ble.imageInfo ?? "BLE")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .background(OptiTagColors.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(OptiTagColors.border, lineWidth: 0.5)
                    )

                    AutoRecordingCard(ble: viewModel.ble)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("人臉辨識").font(.headline)
                        Text(viewModel.recognitionStatus).font(.subheadline)
                        Text("已登錄 \(viewModel.enrolledCount) 位人物").font(.caption).foregroundStyle(.secondary)
                        if let image = viewModel.ble.receivedImage {
                            Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 180)
                        }
                        if viewModel.ble.isConnected {
                            Button("手動拍攝辨識", systemImage: "camera.viewfinder") {
                                viewModel.ble.startCapture()
                            }
                            .disabled(!viewModel.ble.canCapture || viewModel.ble.isExporting || viewModel.ble.isChangingVAD)
                        }
                        if let error = viewModel.ble.errorText {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }

                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(OptiTagColors.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    // 辨識紀錄
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("辨識紀錄")
                                .font(.subheadline).bold()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)

                        Divider()

                        if let databaseErrorMessage = viewModel.databaseErrorMessage {
                            Text(databaseErrorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
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
                    .background(OptiTagColors.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(OptiTagColors.border, lineWidth: 0.5)
                    )
                }
                .padding(16)
            }

            // 掃描按鈕
            Button {
                guard !viewModel.ble.isConnected, !scanInProgress else { return }
                scanRequested = true
                viewModel.ble.connectFirstDiscoveredDevice()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.ble.isConnected ? "checkmark.circle" : "dot.radiowaves.left.and.right")
                    Text(viewModel.ble.isConnected ? "裝置已連線" : scanInProgress ? "正在搜尋" : "開始掃描")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(hex: "#7c3aed").opacity(viewModel.ble.isConnected || scanInProgress ? 0.65 : 1))
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .contentShape(Capsule())
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.ble.isConnected || scanInProgress)
        }
        .background(OptiTagColors.background)
        .onAppear { viewModel.refreshEnrollmentCount(); viewModel.loadRecentLogs() }
        .onChange(of: viewModel.ble.devices.count) { _, count in
            guard scanRequested, count > 0, !viewModel.ble.isConnected,
                  !viewModel.ble.statusText.hasPrefix("連線中") else { return }
            viewModel.ble.connectFirstDiscoveredDevice()
        }
        .onChange(of: viewModel.ble.isConnected) { _, connected in
            if connected { scanRequested = false }
        }
        .onChange(of: viewModel.ble.errorText) { _, error in
            if error != nil { scanRequested = false }
        }
        .task(id: scanRequested) {
            guard scanRequested else { return }
            do { try await Task.sleep(for: .seconds(12)) }
            catch { return }
            scanRequested = false
        }

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
            return OptiTagColors.adaptive(light: 0x2563eb, dark: 0xa7c5ff)
        default:
            return OptiTagColors.accent
        }
    }

    private func backgroundColor(for log: RecognitionLog) -> Color {
        if log.isUnknown {
            return OptiTagColors.card
        }

        switch log.tag {
        case "朋友":
            return OptiTagColors.adaptive(light: 0xdbeafe, dark: 0x243655)
        default:
            return OptiTagColors.navigation
        }
    }

    private func tagBackgroundColor(for log: RecognitionLog) -> Color {
        if log.isUnknown {
            return OptiTagColors.adaptive(light: 0xfee2e2, dark: 0x492732)
        }

        switch log.tag {
        case "同學", "朋友":
            return OptiTagColors.adaptive(light: 0xdbeafe, dark: 0x243655)
        default:
            return OptiTagColors.navigation
        }
    }
}


private struct AutoRecordingCard: View {
    @ObservedObject var ble: BLEManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { ble.vadEnabled ?? false },
                set: { enabled in Task { await ble.setVAD(enabled: enabled) } }
            )) {
                Label("自動錄音", systemImage: "mic.fill")
                    .font(.subheadline.bold())
            }
            .toggleStyle(.switch)
            .tint(OptiTagColors.accent)
            .disabled(!ble.canCapture || ble.isExporting || ble.isChangingVAD)
            .accessibilityValue(ble.vadEnabled.map { $0 ? "已開啟" : "已關閉" } ?? "尚未確認")

            if ble.isChangingVAD {
                ProgressView("等待裝置確認…").font(.caption)
            } else {
                Text(ble.isConnected
                     ? (ble.vadEnabled.map { $0 ? "已開啟，偵測到語音時自動錄音" : "已關閉自動錄音" } ?? "尚未確認裝置狀態，開啟開關以啟用自動錄音")
                     : "請先連線裝置")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = ble.vadError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(14)
        .background(OptiTagColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(OptiTagColors.border, lineWidth: 0.5)
        )
    }
}

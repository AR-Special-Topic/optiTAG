import Foundation
import SwiftUI

/// Feed this view with updates from exportAll(to:progress:).
public struct SDExportProgressView: View {
    public let progress: SDExportProgress
    public init(progress: SDExportProgress) { self.progress = progress }

    private func size(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if progress.phase == .scanning {
                ProgressView("正在掃描 SD 卡…")
            } else {
                ProgressView(value: progress.fractionCompleted) {
                    Text("整體傳輸 \(Int(progress.fractionCompleted * 100))%")
                }
                Text("Event \(progress.completedEvents)/\(progress.totalEvents) · 檔案 \(progress.completedFiles)/\(progress.totalFiles)")
                Text("WAV \(size(progress.completedWAVBytes)) / \(size(progress.totalWAVBytes))")
                Text("總計 \(size(progress.completedBytes)) / \(size(progress.totalBytes))")
                if !progress.path.isEmpty {
                    Text(progress.path).font(.caption).lineLimit(1)
                    ProgressView(value: progress.fileFractionCompleted)
                    Text("\(size(progress.bytes)) / \(size(progress.total))").font(.caption)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

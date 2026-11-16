# optiTAG

optiTAG 是一套以 iOS App 搭配 ESP32-S3 裝置運作的輕量化穿戴式社交輔助系統原型。

App 透過 BLE 與 ESP32-S3 連線，展示從 ESP32-S3 擷取影像、透過 BLE 傳送到手機，並在 App 中呈現影像接收資訊與辨識紀錄的流程。

## 專案目標

- 協助臉盲症或社交辨識困難使用者，在社交情境中快速取得人物提示。
- 使用 ESP32-S3 等低功耗裝置作為前端感測與影像擷取端。
- 使用 iPhone 作為主要操作介面，負責顯示狀態與紀錄辨識結果。

## 目前功能

- 透過 BLE 掃描並連線 ESP32-S3 裝置。
- 接收 ESP32-S3 傳送的人臉影像資料。
- 顯示 ESP32-S3 連線狀態與影像接收資訊。
- 儲存並顯示近期辨識紀錄。
- 在主頁透過 Toggle 開啟／關閉裝置 VAD（自動錄音），等待裝置確認設定。
- 下載錄音時顯示整體與單檔進度、WAV 傳輸量與已完成 Event／檔案數。

## 技術架構

- 開發平台：iOS
- UI 框架：SwiftUI
- BLE 通訊：CoreBluetooth
- 資料庫：SQLite3
- 專案工具：Xcode
- 目標裝置：iPhone 與 ESP32-S3

## 執行方式

先完成以下本機設定（實際設定與模型不提交至 Git）：

- 將 InsightFace `buffalo_s` 的兩個必要模型放入 `buffalo_s/`，依 [模型說明](buffalo_s/README.md) 驗證。
- 從自己的 Firebase 專案下載 iOS 設定為 `optiTAG/GoogleService-Info.plist`；欄位結構可參考 `optiTAG/GoogleService-Info.example.plist`，範本不可直接用於連線。
- 在 Xcode Signing & Capabilities 選擇自己的 Team，並讓 Bundle Identifier 與 Firebase iOS app 一致。部署後端前同步確認 `.firebaserc`，詳見 [Firebase 設定](docs/FIREBASE_STT.md)。

1. 使用 Xcode 開啟 `optiTAG.xcodeproj`。
2. 選擇實體 iPhone 作為執行目標。
3. 確認 iPhone 已開啟藍牙。
4. 確認 ESP32-S3 裝置已開機。
5. 在 Xcode 中執行 App。
6. 進入 App 後點擊「開始掃描」進行連線測試。
## 人臉辨識

辨識流程參考 [DetectPipeDemo](https://github.com/CrocoFishing/DetectPipeDemo/) 的 PC client，不包含 phase01–06 測試介面：

- 使用 BLE protocol v2 接收並驗證 JPEG（封包與整張影像 CRC32、分塊序號、人臉批次資訊）。ESP32 韌體也必須使用 v2。
- 在手機背景佇列執行 buffalo_s 的 `det_500m.onnx`（SCRFD 偵測與五點 landmarks），對齊到 ArcFace 的 112×112 標準人臉，再執行 `w600k_mbf.onnx`（512 維、L2 正規化特徵）。
- 比較本機 SQLite 中已登錄人物的特徵，採 cosine similarity，預設門檻 0.45。相似度不是正確率；實際使用時需以自己的照片與 ESP32 影像校準門檻。
- 儲存辨識紀錄，並把人物 ID、姓名、相似度與處理時間回傳 ESP32。沒有匹配、沒有臉、或模型錯誤分別回傳 UNKNOWN、NO_FACE、FAILED。

先在「資料庫」頁輸入姓名／標籤，選取**只有一張清楚正面人臉**的照片，按「新增人物」。照片僅用於建立特徵，App 不保存原始登錄照片；特徵與紀錄保存在裝置上的 SQLite。接著掃描並連線 ESP32，再按「開始掃描」拍照辨識。ESP32 傳來的每張人臉影像也需要恰好偵測到一張臉。

Xcode 會透過 Swift Package Manager 安裝 Microsoft ONNX Runtime 1.24.2。初次建置需要網路；App 執行辨識時不需網路。App bundle 只包含偵測與辨識兩個模型，模型權重需另行放入本機專案目錄。新安裝不再建立假的人物或辨識紀錄；既有資料會保留，但沒有登錄特徵的人物不參與比對。

主要實作位於 `optiTAG/Recognition/`、`MainViewModel.swift`、`BLEManager.swift` 與 `OptiTagDatabase.swift`。BLE v2 事件通知顯示即時狀態；音訊透過 BLE 啟動的 Wi-Fi SD 匯出取得，對話紀錄另存 SQLite。詳見 [對話彙整設計與設定](docs/CONVERSATIONS.md)。

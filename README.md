# optiTAG

optiTAG 是一套以 iOS App 搭配 ESP32-S3 裝置運作的輕量化穿戴式社交輔助系統原型。App 透過 BLE 與 ESP32-S3 連線，接收裝置端擷取或裁切後的人臉影像，並在手機端顯示連線狀態、影像接收資訊與辨識紀錄。

本專案目前重點放在 iOS 端的操作介面、BLE 通訊流程、影像封包接收，以及本機辨識紀錄儲存。辨識結果目前仍以測試資料與未知人物流程為主，可作為後續串接人臉辨識模型與人物資料庫的基礎。

## 專案目標

- 協助臉盲症或社交辨識困難使用者，在社交情境中快速取得人物提示。
- 使用 ESP32-S3 等低功耗裝置作為前端感測與影像擷取端。
- 使用 iPhone 作為主要操作介面，負責顯示狀態、紀錄辨識結果與後續擴充辨識邏輯。
- 建立可被專題展示、測試與延伸的 BLE 通訊架構。

## 目前功能

- 掃描並連線指定 BLE 裝置：`ESP32S3-FACE-DEMO`
- 與 ESP32-S3 的自訂 BLE service 溝通
- 送出拍照命令 `START_CAPTURE`
- 接收 ESP32-S3 回傳的事件通知
- 接收並組合 `IMAGE_BEGIN`、`IMAGE_CHUNK`、`IMAGE_END` 影像封包
- 將完整影像資料解碼為 iOS 可顯示圖片
- 回傳暫定的 `UNKNOWN` 辨識結果給 ESP32-S3
- 使用 SQLite 儲存人物與辨識紀錄
- 在首頁顯示 ESP32 連線狀態與近期辨識紀錄

## 技術架構

- 開發平台：iOS
- UI 框架：SwiftUI
- BLE 通訊：CoreBluetooth
- 本機資料庫：SQLite3
- 專案工具：Xcode
- 目標裝置：實體 iPhone 與 ESP32-S3

> BLE 功能需要實體 iPhone 測試，iOS Simulator 無法完整測試藍牙連線流程。

## 專案結構

```text
optiTAG/
├── optiTAG.xcodeproj
└── optiTAG/
    ├── BLE/
    │   ├── BLEManager.swift        # BLE 掃描、連線、收發資料
    │   └── BLEProtocol.swift       # 封包格式、UUID、CRC32、影像組包
    ├── Database/
    │   └── OptiTagDatabase.swift   # SQLite 資料表與辨識紀錄存取
    ├── Models/
    │   ├── Person.swift
    │   └── RecognitionLog.swift
    ├── ViewModels/
    │   └── MainViewModel.swift
    ├── Views/
    │   ├── MainView.swift
    │   ├── SIdeManuView.swift      # 側邊選單 SideMenuView
    │   ├── ManuRow.swift           # 選單列 MenuRow
    │   └── ColorHex.swift
    ├── ContentView.swift
    └── optiTAGApp.swift
```

## BLE 通訊設定

App 目前會尋找名稱為：

```text
ESP32S3-FACE-DEMO
```

的 BLE 裝置，並使用以下自訂 service 與 characteristic：

| 類型 | UUID | 用途 |
| --- | --- | --- |
| Service | `7f510000-b7b2-4f6a-9f3a-6c8a2d7e1000` | optiTAG BLE service |
| Control | `7f510001-b7b2-4f6a-9f3a-6c8a2d7e1000` | App 傳送拍照命令 |
| Event | `7f510002-b7b2-4f6a-9f3a-6c8a2d7e1000` | ESP32-S3 回傳狀態事件 |
| Image Data | `7f510003-b7b2-4f6a-9f3a-6c8a2d7e1000` | ESP32-S3 分段傳送影像 |
| Recognition Result | `7f510004-b7b2-4f6a-9f3a-6c8a2d7e1000` | App 回傳辨識結果 |
| Device Information | `7f510005-b7b2-4f6a-9f3a-6c8a2d7e1000` | 讀取裝置資訊 |

封包格式包含 magic number、版本、訊息型別、request ID、image ID、payload 長度、chunk index、總 chunk 數與 CRC32。App 端會檢查封包長度、版本、CRC32 與影像 chunk 順序，避免接收到不完整或錯誤的影像資料。

## 資料庫

App 啟動時會在 iOS Documents 目錄建立：

```text
optiTAG.sqlite
```

目前包含兩張資料表：

- `persons`：儲存人物名稱、標籤與備註
- `recognition_logs`：儲存辨識紀錄、標籤、信心值與時間

第一次啟動時會建立幾筆示範資料，方便在沒有完整辨識模型時展示首頁紀錄。

## 開發環境

建議環境：

- macOS
- Xcode
- 實體 iPhone
- 已燒錄對應 BLE 韌體的 ESP32-S3

目前 Xcode project 設定：

- Bundle Identifier：`com.paulweng.optiTAG`
- Version：`1.0`
- Deployment Target：`iOS 26.1`

若要在較低版本 iOS 裝置測試，可以在 Xcode 的 project settings 中調整 Deployment Target。

## 執行方式

1. 開啟 Xcode。
2. 開啟 `optiTAG/optiTAG.xcodeproj`。
3. 選擇實體 iPhone 作為執行目標。
4. 確認 iPhone 已開啟藍牙。
5. 確認 ESP32-S3 已開機並廣播 `ESP32S3-FACE-DEMO`。
6. 在 Xcode 中按下 Run。
7. App 開啟後，點擊「開始掃描」進行連線或拍照測試。

## 權限需求

App 目前需要以下 iOS 權限：

- Bluetooth：用於連線 ESP32-S3 並接收影像資料
- Camera：保留給人物掃描與辨識相關功能

## 目前限制

- 人臉辨識模型尚未正式整合到 iOS App 流程。
- App 接收到影像後，目前會先寫入「未知人物」辨識紀錄。
- `Recognition Result` 回傳目前使用暫定的 `UNKNOWN` 結果。
- BLE 影像傳輸速度與穩定性會受到 MTU、封包大小、ESP32-S3 韌體與環境干擾影響。
- iOS Simulator 無法測試 BLE 實機連線。

## 後續可擴充方向

- 串接 FaceNet、Core ML 或其他人臉辨識模型。
- 建立人物管理頁面，支援新增、編輯與刪除人物資料。
- 將辨識信心值、人物標籤與備註整合到提醒介面。
- 優化 BLE 傳輸協定，例如加入重傳、壓縮或進度顯示。
- 加入通知、語音提示或 Apple Watch/穿戴式裝置延伸功能。
- 將 ESP32-S3 韌體與 App BLE 協定文件整理成完整開發規格。

## 專題定位

optiTAG 目前可作為「輕量化穿戴式社交輔助系統」的 iOS 端原型，展示從 ESP32-S3 擷取影像、透過 BLE 傳送到手機、在 App 中呈現狀態與紀錄的完整流程。後續只要補上穩定的人臉辨識模型與人物資料管理，就能逐步擴展成更完整的社交輔助工具。

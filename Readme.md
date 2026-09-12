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

## 技術架構

- 開發平台：iOS
- UI 框架：SwiftUI
- BLE 通訊：CoreBluetooth
- 資料庫：SQLite3
- 專案工具：Xcode
- 目標裝置：iPhone 與 ESP32-S3

## 執行方式

1. 使用 Xcode 開啟 `optiTAG.xcodeproj`。
2. 選擇實體 iPhone 作為執行目標。
3. 確認 iPhone 已開啟藍牙。
4. 確認 ESP32-S3 裝置已開機。
5. 在 Xcode 中執行 App。
6. 進入 App 後點擊「開始掃描」進行連線測試。
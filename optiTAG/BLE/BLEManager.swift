import EventPipeSDExport
import Combine
import CoreBluetooth
import SwiftUI
import UIKit

struct DiscoveredDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let identifier: String
    let rssi: Int?
    let peripheral: CBPeripheral
}

@MainActor final class BLEManager: NSObject, ObservableObject {
    @Published private(set) var statusText = "尚未掃描"
    @Published private(set) var errorText: String?
    @Published private(set) var devices: [DiscoveredDevice] = []
    @Published private(set) var isConnected = false
    @Published private(set) var canCapture = false
    @Published private(set) var receivedImage: UIImage?
    @Published private(set) var imageInfo: String?
    var onImageReceived: ((UInt32, UInt32, Data) -> Void)?

    struct WiFiJoinPrompt {
        let ssid: String
        let password: String
    }
    @Published private(set) var wiFiJoinPrompt: WiFiJoinPrompt?
    private var manualWiFiConfirmed = false

    func confirmWiFiJoined() { manualWiFiConfirmed = true }

    private func waitForManualWiFi(_ info: SDExportConnectionInfo) async throws {
        manualWiFiConfirmed = false
        wiFiJoinPrompt = WiFiJoinPrompt(ssid: info.ssid, password: info.passphrase)
        defer { wiFiJoinPrompt = nil; manualWiFiConfirmed = false }
        let deadline = Date().addingTimeInterval(90)
        while !manualWiFiConfirmed {
            try Task.checkCancellation()
            guard Date() < deadline else { throw PersonError.message("手動加入 Wi-Fi 已逾時，請重新開始下載取得新的連線資訊") }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        guard UIApplication.shared.applicationState == .active else { throw PersonError.message("請返回 optiTAG 後再繼續") }
        // The SDK validates the authenticated device endpoint after this step.
    }

    private var exportLink: SDExportBLELink?
    private var exportCoordinator: SDExportCoordinator?
    @Published private(set) var isExporting = false
    var exportDeviceID: String { peripheral?.identifier.uuidString ?? "unknown" }

    @MainActor func downloadEvents() async throws -> SDExportResult {
        guard !isExporting, let peripheral else { throw PersonError.message("請先連線裝置") }
        isExporting = true
        defer { isExporting = false }
        if exportLink == nil {
            let link = SDExportBLELink(peripheral: peripheral)
            exportLink = link; exportCoordinator = SDExportCoordinator(link: link) { [weak self] info in
                guard let self else { throw CancellationError() }
                try await self.waitForManualWiFi(info)
            }
        }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SDExport").appendingPathComponent(peripheral.identifier.uuidString)
        return try await exportCoordinator!.exportAll(to: directory)
    }

    @MainActor func deleteEventAudio(paths: [String]) async throws -> SDFileDeletionResult {
        guard !isExporting, let coordinator = exportCoordinator else { throw PersonError.message("匯出工作尚未就緒") }
        isExporting = true
        defer { isExporting = false }
        return try await coordinator.deleteFiles(paths: paths)
    }

    private lazy var central = CBCentralManager(delegate: self, queue: nil)
    private var peripheral: CBPeripheral?
    private var controlCharacteristic: CBCharacteristic?
    private var resultCharacteristic: CBCharacteristic?
    private var assembler = ImageChunkAssembler()
    private(set) var connectionGeneration = UUID()
    private var activeImage: (request: UInt32, image: UInt32)?
    private var subscribed: Set<CBUUID> = []
    private var requestID: UInt32 = 1
    private var chunkCount = 0
    private var transferStartedAt: Date?

    func scan() {
        errorText = nil
        devices.removeAll()
        _ = central
        guard central.state == .poweredOn else {
            statusText = bluetoothStateText(central.state)
            return
        }
        statusText = "掃描中"
        central.scanForPeripherals(withServices: [BLEProtocol.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func connect(to device: DiscoveredDevice) {
        statusText = "連線中：\(device.name)"
        errorText = nil
        central.stopScan()
        peripheral = device.peripheral
        peripheral?.delegate = self
        central.connect(device.peripheral)
    }

    func connectFirstDiscoveredDevice() {
        guard let device = devices.first else {
            scan()
            return
        }
        connect(to: device)
    }

    func scanOrCapture() {
        if canCapture {
            startCapture()
        } else if isConnected {
            statusText = "等待 BLE characteristic"
        } else {
            connectFirstDiscoveredDevice()
        }
    }

    func disconnect() {
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
    }

    func startCapture() {
        guard !isExporting else { return }
        guard canCapture, let peripheral, let controlCharacteristic else { return }
        let id = requestID
        requestID = requestID == 0x3fffffff ? 1 : requestID + 1
        chunkCount = 0
        receivedImage = nil
        imageInfo = "request \(id) 已送出"
        let packet = PacketFactory.startCapture(requestID: id)
        peripheral.writeValue(packet, for: controlCharacteristic, type: .withResponse)
    }

    private func handleNotification(_ data: Data) {
        do {
            let packet = try Packet.decode(data)
            switch packet.header.messageType {
            case .captureAccepted:
                statusText = "ESP32-S3 已接受拍照"
            case .busy:
                statusText = "ESP32-S3 忙碌中"
            case .noFace:
                statusText = "未偵測到人臉"
                imageInfo = "request \(packet.header.requestID), image \(packet.header.imageID)"
            case .error:
                errorText = "ESP32-S3 回報錯誤"
            case .imageBegin:
                try assembler.begin(packet)
                activeImage = (packet.header.requestID, packet.header.imageID)
                transferStartedAt = Date()
                chunkCount = 0
                statusText = "接收影像中"
                imageInfo = "image \(packet.header.imageID) 開始接收"
            case .imageChunk:
                try assembler.add(packet)
                chunkCount += 1
            case .imageEnd:
                let imageData = try assembler.finish(packet)
                receivedImage = UIImage(data: imageData)
                let elapsed = Date().timeIntervalSince(transferStartedAt ?? Date()) * 1000
                imageInfo = "request \(packet.header.requestID), image \(packet.header.imageID), \(imageData.count) bytes, \(chunkCount) chunks, \(Int(elapsed)) ms"
                statusText = receivedImage == nil ? "收到影像但無法解碼" : "影像接收完成"
                onImageReceived?(packet.header.requestID, packet.header.imageID, imageData)

            case .eventOpen, .eventAudioReady, .faceBatchEnd, .eventComplete:
                let event = try EventPayload.decode(packet)
                imageInfo = String(describing: event)
            default:
                statusText = "收到 \(packet.header.messageType)"
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    func sendRecognitionResult(_ result: RecognitionResult, generation: UUID) {
        guard generation == connectionGeneration,
              activeImage?.request == result.requestID, activeImage?.image == result.imageID,
              let peripheral, let resultCharacteristic else { return }
        let packet = result.encodedPacket()
        guard packet.count <= peripheral.maximumWriteValueLength(for: .withResponse) else {
            errorText = "BLE 寫入容量不足，無法傳送辨識結果"
            return
        }
        peripheral.writeValue(packet, for: resultCharacteristic, type: .withResponse)
        activeImage = nil
    }

    private func bluetoothStateText(_ state: CBManagerState) -> String {
        switch state {
        case .poweredOn: return "藍牙已開啟"
        case .poweredOff: return "藍牙未開啟"
        case .unauthorized: return "App 沒有藍牙權限"
        case .unsupported: return "此裝置不支援 BLE"
        case .resetting: return "藍牙重設中"
        case .unknown: fallthrough
        @unknown default: return "藍牙狀態未知"
        }
    }
}

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        statusText = bluetoothStateText(central.state)
        if central.state == .poweredOn {
            scan()
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = peripheral.name ?? localName ?? "未命名裝置"


        let device = DiscoveredDevice(
            id: peripheral.identifier,
            name: name,
            identifier: peripheral.identifier.uuidString,
            rssi: RSSI.intValue,
            peripheral: peripheral
        )

        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = device
        } else {
            devices.append(device)
        }
        statusText = "找到 \(devices.count) 個裝置"
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        exportLink = nil; exportCoordinator = nil
        connectionGeneration = UUID()
        subscribed.removeAll()
        isConnected = true
        statusText = "已連線，探索服務中"
        peripheral.discoverServices([BLEProtocol.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        canCapture = false
        errorText = error?.localizedDescription ?? "連線失敗"
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        exportLink?.disconnected()
        isConnected = false
        canCapture = false
        connectionGeneration = UUID()
        activeImage = nil
        assembler = ImageChunkAssembler()
        subscribed.removeAll()
        controlCharacteristic = nil
        resultCharacteristic = nil
        statusText = "已斷線"
        errorText = error?.localizedDescription
    }
}

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        exportLink?.didModifyServices(invalidatedServices)
        controlCharacteristic = nil; resultCharacteristic = nil; subscribed.removeAll(); canCapture = false
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        exportLink?.didDiscoverServices(error: error)
        if isExporting { return }
        if let error {
            errorText = error.localizedDescription
            return
        }
        peripheral.services?.forEach { service in
            peripheral.discoverCharacteristics([
                BLEProtocol.controlUUID,
                BLEProtocol.eventUUID,
                BLEProtocol.imageDataUUID,
                BLEProtocol.recognitionResultUUID,
                BLEProtocol.deviceInformationUUID
            ], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        exportLink?.didDiscoverCharacteristics(for: service, error: error)
        if isExporting { return }
        if let error {
            errorText = error.localizedDescription
            return
        }

        service.characteristics?.forEach { characteristic in
            switch characteristic.uuid {
            case BLEProtocol.controlUUID:
                controlCharacteristic = characteristic
            case BLEProtocol.eventUUID, BLEProtocol.imageDataUUID:
                peripheral.setNotifyValue(true, for: characteristic)
            case BLEProtocol.recognitionResultUUID:
                resultCharacteristic = characteristic
            case BLEProtocol.deviceInformationUUID:
                peripheral.readValue(for: characteristic)
            default:
                break
            }
        }

        updateCaptureReadiness()
        statusText = canCapture ? "可拍照" : "等待 BLE characteristic"
    }

    private func updateCaptureReadiness() {
        canCapture = controlCharacteristic != nil && resultCharacteristic != nil &&
            subscribed.contains(BLEProtocol.eventUUID) && subscribed.contains(BLEProtocol.imageDataUUID)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        exportLink?.didUpdateNotificationState(for: characteristic, error: error)
        if let error { errorText = error.localizedDescription; return }
        if characteristic.isNotifying { subscribed.insert(characteristic.uuid) }
        else { subscribed.remove(characteristic.uuid) }
        updateCaptureReadiness()
        statusText = canCapture ? "可拍照" : "等待 BLE 訂閱"
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        exportLink?.didWriteValue(for: characteristic, error: error)
        if let error { errorText = "BLE 傳送失敗：\(error.localizedDescription)" }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        exportLink?.didUpdateValue(for: characteristic, error: error)
        if let error {
            errorText = error.localizedDescription
            return
        }
        guard let data = characteristic.value else { return }

        if characteristic.uuid == BLEProtocol.deviceInformationUUID,
           let text = String(data: data, encoding: .utf8) {
            imageInfo = text
            return
        }

        if characteristic.uuid == EventPipeSDExport.BLEProtocol.sdExportInfoUUID { return }
        // Export responses belong to the SDK, whose message enum extends v2.
        if characteristic.uuid == BLEProtocol.eventUUID,
           let packet = try? EventPipeSDExport.Packet.decode(data), packet.header.messageType.rawValue > 18 { return }
        handleNotification(data)
    }
}

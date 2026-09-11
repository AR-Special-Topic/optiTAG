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

final class BLEManager: NSObject, ObservableObject {
    @Published private(set) var statusText = "尚未掃描"
    @Published private(set) var errorText: String?
    @Published private(set) var devices: [DiscoveredDevice] = []
    @Published private(set) var isConnected = false
    @Published private(set) var canCapture = false
    @Published private(set) var receivedImage: UIImage?
    @Published private(set) var imageInfo: String?
    var onImageReceived: ((UInt32, UInt32, Data) -> Void)?

    private lazy var central = CBCentralManager(delegate: self, queue: nil)
    private var peripheral: CBPeripheral?
    private var controlCharacteristic: CBCharacteristic?
    private var resultCharacteristic: CBCharacteristic?
    private let assembler = ImageChunkAssembler()
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
        guard let peripheral, let controlCharacteristic else { return }
        let id = requestID
        requestID = requestID == UInt32.max ? 1 : requestID + 1
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
                sendUnknownResult(requestID: packet.header.requestID, imageID: packet.header.imageID)
            default:
                statusText = "收到 \(packet.header.messageType)"
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func sendUnknownResult(requestID: UInt32, imageID: UInt32) {
        guard let peripheral, let resultCharacteristic else { return }
        let packet = PacketFactory.recognitionResult(
            requestID: requestID,
            imageID: imageID,
            status: .unknown,
            personID: "",
            personName: "UNKNOWN",
            similarity: 0,
            processingTimeMs: 0
        )
        peripheral.writeValue(packet, for: resultCharacteristic, type: .withResponse)
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
        guard name == BLEProtocol.deviceName || localName == BLEProtocol.deviceName else { return }

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
        isConnected = false
        canCapture = false
        controlCharacteristic = nil
        resultCharacteristic = nil
        statusText = "已斷線"
        errorText = error?.localizedDescription
    }
}

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
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

        canCapture = controlCharacteristic != nil
        statusText = canCapture ? "可拍照" : "等待 BLE characteristic"
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
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

        handleNotification(data)
    }
}

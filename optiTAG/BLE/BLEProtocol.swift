import CoreBluetooth
import Foundation

enum BLEProtocol {
    static let version: UInt8 = 1
    static let magic: UInt32 = 0x45434146
    static let headerLength = 32
    static let deviceName = "ESP32S3-FACE-DEMO"
    static let serviceUUID = CBUUID(string: "7f510000-b7b2-4f6a-9f3a-6c8a2d7e1000")
    static let controlUUID = CBUUID(string: "7f510001-b7b2-4f6a-9f3a-6c8a2d7e1000")
    static let eventUUID = CBUUID(string: "7f510002-b7b2-4f6a-9f3a-6c8a2d7e1000")
    static let imageDataUUID = CBUUID(string: "7f510003-b7b2-4f6a-9f3a-6c8a2d7e1000")
    static let recognitionResultUUID = CBUUID(string: "7f510004-b7b2-4f6a-9f3a-6c8a2d7e1000")
    static let deviceInformationUUID = CBUUID(string: "7f510005-b7b2-4f6a-9f3a-6c8a2d7e1000")
}

enum MessageType: UInt8 {
    case hello = 1
    case helloAck = 2
    case startCapture = 3
    case captureAccepted = 4
    case busy = 5
    case status = 6
    case imageBegin = 7
    case imageChunk = 8
    case imageEnd = 9
    case recognitionResult = 10
    case noFace = 11
    case error = 12
    case ping = 13
    case pong = 14
}

enum Command: UInt16 {
    case startCapture = 1
}

enum StatusCode: UInt8 {
    case ok = 0
    case unknown = 1
    case noFace = 2
    case failed = 3
}

enum ProtocolValidationError: Error, LocalizedError {
    case partialPacket
    case invalidMagic
    case unsupportedVersion(UInt8)
    case unknownMessage(UInt8)
    case invalidLength
    case crcMismatch
    case wrongIdentifiers
    case invalidSequence
    case missingChunks([UInt16])

    var errorDescription: String? {
        switch self {
        case .partialPacket: return "封包長度不足"
        case .invalidMagic: return "封包 magic 不正確"
        case .unsupportedVersion(let version): return "不支援的協定版本 \(version)"
        case .unknownMessage(let value): return "未知訊息型別 \(value)"
        case .invalidLength: return "封包長度不正確"
        case .crcMismatch: return "CRC32 檢查失敗"
        case .wrongIdentifiers: return "request id 或 image id 不一致"
        case .invalidSequence: return "圖片 chunk 順序不正確"
        case .missingChunks(let chunks): return "缺少圖片 chunk: \(chunks)"
        }
    }
}

struct PacketHeader {
    var messageType: MessageType
    var flags: UInt16 = 0
    var requestID: UInt32 = 0
    var imageID: UInt32 = 0
    var payloadLength: UInt32 = 0
    var chunkIndex: UInt16 = 0
    var totalChunks: UInt16 = 0
    var crc32: UInt32 = 0
    var reserved: UInt32 = 0

    func encoded() -> Data {
        var data = Data()
        data.appendLE(BLEProtocol.magic)
        data.append(BLEProtocol.version)
        data.append(messageType.rawValue)
        data.appendLE(flags)
        data.appendLE(requestID)
        data.appendLE(imageID)
        data.appendLE(payloadLength)
        data.appendLE(chunkIndex)
        data.appendLE(totalChunks)
        data.appendLE(crc32)
        data.appendLE(reserved)
        return data
    }

    static func decode(_ data: Data) throws -> PacketHeader {
        guard data.count >= BLEProtocol.headerLength else { throw ProtocolValidationError.partialPacket }
        guard data.uint32LE(at: 0) == BLEProtocol.magic else { throw ProtocolValidationError.invalidMagic }
        let version = data[4]
        guard version == BLEProtocol.version else { throw ProtocolValidationError.unsupportedVersion(version) }
        guard let type = MessageType(rawValue: data[5]) else { throw ProtocolValidationError.unknownMessage(data[5]) }

        return PacketHeader(
            messageType: type,
            flags: data.uint16LE(at: 6),
            requestID: data.uint32LE(at: 8),
            imageID: data.uint32LE(at: 12),
            payloadLength: data.uint32LE(at: 16),
            chunkIndex: data.uint16LE(at: 20),
            totalChunks: data.uint16LE(at: 22),
            crc32: data.uint32LE(at: 24),
            reserved: data.uint32LE(at: 28)
        )
    }
}

struct Packet {
    let header: PacketHeader
    let payload: Data

    func encoded() -> Data {
        var header = header
        header.payloadLength = UInt32(payload.count)
        header.crc32 = CRC32.checksum(payload)
        return header.encoded() + payload
    }

    static func decode(_ data: Data) throws -> Packet {
        let header = try PacketHeader.decode(data)
        guard data.count == BLEProtocol.headerLength + Int(header.payloadLength) else {
            throw ProtocolValidationError.invalidLength
        }
        let payload = data.subdata(in: BLEProtocol.headerLength..<data.count)
        guard CRC32.checksum(payload) == header.crc32 else { throw ProtocolValidationError.crcMismatch }
        return Packet(header: header, payload: payload)
    }
}

enum PacketFactory {
    static func startCapture(requestID: UInt32) -> Data {
        let timestamp = UInt32(Date().timeIntervalSince1970)
        var payload = Data()
        payload.appendLE(Command.startCapture.rawValue)
        payload.appendLE(UInt16(0))
        payload.appendLE(timestamp)
        return Packet(header: PacketHeader(messageType: .startCapture, requestID: requestID), payload: payload).encoded()
    }

    static func recognitionResult(
        requestID: UInt32,
        imageID: UInt32,
        status: StatusCode,
        personID: String,
        personName: String,
        similarity: Float,
        processingTimeMs: UInt32
    ) -> Data {
        let id = Data(personID.utf8.prefix(32))
        let name = Data(personName.utf8.prefix(64))
        var payload = Data([status.rawValue, UInt8(id.count), UInt8(name.count), 0])
        payload.appendLE(similarity.bitPattern)
        payload.appendLE(processingTimeMs)
        payload.append(id)
        payload.append(name)
        return Packet(header: PacketHeader(messageType: .recognitionResult, requestID: requestID, imageID: imageID), payload: payload).encoded()
    }
}

enum CRC32 {
    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xEDB88320 : 0)
            }
        }
        return crc ^ 0xFFFFFFFF
    }
}

final class ImageChunkAssembler {
    private var requestID: UInt32 = 0
    private var imageID: UInt32 = 0
    private var expectedBytes: UInt32 = 0
    private var expectedCRC: UInt32 = 0
    private var totalChunks: UInt16 = 0
    private var chunks: [UInt16: Data] = [:]

    private(set) var duplicatedSequenceCount = 0

    func begin(_ packet: Packet) throws {
        guard packet.header.messageType == .imageBegin, packet.payload.count == 8 else {
            throw ProtocolValidationError.invalidLength
        }
        requestID = packet.header.requestID
        imageID = packet.header.imageID
        expectedBytes = packet.payload.uint32LE(at: 0)
        expectedCRC = packet.payload.uint32LE(at: 4)
        totalChunks = 0
        chunks.removeAll(keepingCapacity: true)
        duplicatedSequenceCount = 0
    }

    func add(_ packet: Packet) throws {
        guard packet.header.messageType == .imageChunk,
              packet.header.requestID == requestID,
              packet.header.imageID == imageID else {
            throw ProtocolValidationError.wrongIdentifiers
        }
        guard packet.header.totalChunks > 0, packet.header.chunkIndex < packet.header.totalChunks else {
            throw ProtocolValidationError.invalidSequence
        }
        if totalChunks != 0, totalChunks != packet.header.totalChunks {
            throw ProtocolValidationError.invalidSequence
        }
        totalChunks = packet.header.totalChunks

        if let old = chunks[packet.header.chunkIndex] {
            duplicatedSequenceCount += 1
            guard old == packet.payload else { throw ProtocolValidationError.invalidSequence }
        } else {
            chunks[packet.header.chunkIndex] = packet.payload
        }
    }

    func finish(_ packet: Packet) throws -> Data {
        guard packet.header.messageType == .imageEnd,
              packet.header.requestID == requestID,
              packet.header.imageID == imageID else {
            throw ProtocolValidationError.wrongIdentifiers
        }
        let missing = (0..<totalChunks).filter { chunks[$0] == nil }
        guard missing.isEmpty else { throw ProtocolValidationError.missingChunks(Array(missing)) }

        var image = Data()
        for index in 0..<totalChunks {
            if let chunk = chunks[index] {
                image.append(chunk)
            }
        }

        guard image.count == Int(expectedBytes) else { throw ProtocolValidationError.invalidLength }
        guard CRC32.checksum(image) == expectedCRC else { throw ProtocolValidationError.crcMismatch }
        return image
    }
}

extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    func uint16LE(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func uint32LE(at offset: Int) -> UInt32 {
        UInt32(self[offset]) |
            UInt32(self[offset + 1]) << 8 |
            UInt32(self[offset + 2]) << 16 |
            UInt32(self[offset + 3]) << 24
    }
}


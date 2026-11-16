import Foundation

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
        RecognitionResult(requestID: requestID, imageID: imageID, status: status, personID: personID,
            personName: personName, similarity: similarity, processingTimeMs: processingTimeMs).encodedPacket()
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}

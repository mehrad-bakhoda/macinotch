import Foundation
import IOKit

public final class SMC: @unchecked Sendable {
    public static let shared = SMC()

    private let lock = NSLock()
    private var connection: io_connect_t = 0
    private var opened = false

    private static let size = 80
    private static let offKey = 0
    private static let offKeyInfoSize = 28
    private static let offKeyInfoType = 32
    private static let offResult = 40
    private static let offData8 = 42
    private static let offBytes = 48

    private static let cmdReadBytes: UInt8 = 5
    private static let cmdWriteBytes: UInt8 = 6
    private static let cmdReadKeyInfo: UInt8 = 9

    private init() {}

    @discardableResult
    public func open() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if opened { return true }
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSMC"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess
        else { return false }
        opened = true
        return true
    }

    public func close() {
        lock.lock(); defer { lock.unlock() }
        guard opened else { return }
        IOServiceClose(connection)
        opened = false
    }

    public enum Value {
        case number(Double)
        case raw([UInt8])
    }

    public func read(_ key: String) -> Double? {
        guard let (type, bytes) = readRaw(key) else { return nil }
        return Self.decode(type: type, bytes: bytes)
    }

    public func readRaw(_ key: String) -> (type: String, bytes: [UInt8])? {
        guard open(), let info = keyInfo(key), info.size > 0, info.size <= 32 else { return nil }
        var request = [UInt8](repeating: 0, count: Self.size)
        Self.put32(&request, Self.offKey, Self.fourCC(key))
        Self.put32(&request, Self.offKeyInfoSize, info.size)
        Self.put32(&request, Self.offKeyInfoType, info.type)
        request[Self.offData8] = Self.cmdReadBytes

        guard let out = call(request), out[Self.offResult] == 0 else { return nil }
        let bytes = Array(out[Self.offBytes..<(Self.offBytes + Int(info.size))])
        return (Self.string(info.type), bytes)
    }

    @discardableResult
    public func write(_ key: String, bytes: [UInt8]) -> Bool {
        guard open(), let info = keyInfo(key),
              Int(info.size) == bytes.count, bytes.count <= 32 else { return false }
        var request = [UInt8](repeating: 0, count: Self.size)
        Self.put32(&request, Self.offKey, Self.fourCC(key))
        Self.put32(&request, Self.offKeyInfoSize, info.size)
        Self.put32(&request, Self.offKeyInfoType, info.type)
        request[Self.offData8] = Self.cmdWriteBytes
        for (i, b) in bytes.enumerated() { request[Self.offBytes + i] = b }

        guard let out = call(request) else { return false }
        return out[Self.offResult] == 0
    }

    public func writeFloat(_ key: String, _ value: Float) -> Bool {
        let bits = value.bitPattern
        return write(key, bytes: [UInt8(bits & 0xFF), UInt8((bits >> 8) & 0xFF),
                                  UInt8((bits >> 16) & 0xFF), UInt8((bits >> 24) & 0xFF)])
    }

    public func writeUInt8(_ key: String, _ value: UInt8) -> Bool { write(key, bytes: [value]) }

    private func keyInfo(_ key: String) -> (size: UInt32, type: UInt32)? {
        var request = [UInt8](repeating: 0, count: Self.size)
        Self.put32(&request, Self.offKey, Self.fourCC(key))
        request[Self.offData8] = Self.cmdReadKeyInfo
        guard let out = call(request), out[Self.offResult] == 0 else { return nil }
        return (Self.get32(out, Self.offKeyInfoSize), Self.get32(out, Self.offKeyInfoType))
    }

    private func call(_ request: [UInt8]) -> [UInt8]? {
        lock.lock(); defer { lock.unlock() }
        guard opened else { return nil }
        var response = [UInt8](repeating: 0, count: Self.size)
        var outSize = Self.size
        let result = request.withUnsafeBytes { inPtr -> kern_return_t in
            response.withUnsafeMutableBytes { outPtr in
                IOConnectCallStructMethod(connection, 2, inPtr.baseAddress!, Self.size,
                                          outPtr.baseAddress!, &outSize)
            }
        }
        return result == kIOReturnSuccess ? response : nil
    }

    private static func fourCC(_ s: String) -> UInt32 {
        var v: UInt32 = 0
        for ch in s.utf8.prefix(4) { v = (v << 8) | UInt32(ch) }
        return v
    }

    private static func string(_ v: UInt32) -> String {
        String(bytes: [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF),
                       UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)],
               encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    private static func put32(_ buf: inout [UInt8], _ off: Int, _ v: UInt32) {
        buf[off] = UInt8(v & 0xFF)
        buf[off + 1] = UInt8((v >> 8) & 0xFF)
        buf[off + 2] = UInt8((v >> 16) & 0xFF)
        buf[off + 3] = UInt8((v >> 24) & 0xFF)
    }

    private static func get32(_ buf: [UInt8], _ off: Int) -> UInt32 {
        UInt32(buf[off]) | UInt32(buf[off + 1]) << 8
            | UInt32(buf[off + 2]) << 16 | UInt32(buf[off + 3]) << 24
    }

    private static func decode(type: String, bytes b: [UInt8]) -> Double? {
        switch type {
        case "flt":
            guard b.count >= 4 else { return nil }
            let bits = UInt32(b[0]) | UInt32(b[1]) << 8
                     | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
            return Double(Float(bitPattern: bits))
        case "ui8":  return b.first.map(Double.init)
        case "ui16": return b.count >= 2 ? Double(UInt16(b[0]) << 8 | UInt16(b[1])) : nil
        case "ui32": return b.count >= 4 ? Double(UInt32(b[0]) << 24 | UInt32(b[1]) << 16
                                                  | UInt32(b[2]) << 8 | UInt32(b[3])) : nil
        case "fpe2": return b.count >= 2 ? Double(UInt16(b[0]) << 8 | UInt16(b[1])) / 4 : nil
        default:     return nil
        }
    }
}

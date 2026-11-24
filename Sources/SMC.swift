import Foundation
import IOKit

/// 读取 SMC 里的风扇转速。无风扇机型（如 MacBook Air / 本机）返回 nil。
/// 用固定 80 字节缓冲区 + 偏移量访问，避免 C 结构体对齐差异带来的问题。
final class SMCReader {

    private var conn: io_connect_t = 0
    private var attempted = false
    private var fanCount: Int = 0
    private var cached: Int?
    private var lastRead = Date.distantPast

    private let structSize = 80
    private let kernelIndexSMC: UInt32 = 2
    private let cmdReadBytes: UInt8 = 5
    private let cmdReadKeyInfo: UInt8 = 9

    // 偏移量（对应 C 版 SMCKeyData_t 的内存布局）
    private let offKey = 0
    private let offKeyInfo = 28        // dataSize(4) + dataType(4) + attributes(1)
    private let offResult = 40
    private let offData8 = 42
    private let offBytes = 48

    private func open() -> Bool {
        if conn != 0 { return true }
        guard !attempted else { return false }
        attempted = true
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        return IOServiceOpen(service, mach_task_self_, 0, &conn) == KERN_SUCCESS
    }

    private func fourCC(_ s: String) -> UInt32 {
        var result: UInt32 = 0
        for ch in s.utf8.prefix(4) { result = (result << 8) | UInt32(ch) }
        return result
    }

    private func putU32(_ buf: inout [UInt8], _ off: Int, _ v: UInt32) {
        buf[off] = UInt8((v >> 24) & 0xff)
        buf[off + 1] = UInt8((v >> 16) & 0xff)
        buf[off + 2] = UInt8((v >> 8) & 0xff)
        buf[off + 3] = UInt8(v & 0xff)
    }

    private func getU32(_ buf: [UInt8], _ off: Int) -> UInt32 {
        (UInt32(buf[off]) << 24) | (UInt32(buf[off + 1]) << 16) |
        (UInt32(buf[off + 2]) << 8) | UInt32(buf[off + 3])
    }

    /// 读一个 key，返回 (数据类型, 数据字节)
    private func read(_ key: String) -> (type: String, bytes: [UInt8])? {
        guard open() else { return nil }
        var output = [UInt8](repeating: 0, count: structSize)
        var outputSize = structSize

        // 第一步：取 key 信息
        var input = [UInt8](repeating: 0, count: structSize)
        putU32(&input, offKey, fourCC(key))
        input[offData8] = cmdReadKeyInfo
        var kr = input.withUnsafeBytes { inp in
            output.withUnsafeMutableBytes { out in
                IOConnectCallStructMethod(conn, kernelIndexSMC, inp.baseAddress, structSize,
                                          out.baseAddress, &outputSize)
            }
        }
        guard kr == KERN_SUCCESS, output[offResult] == 0 else { return nil }

        let dataSize = Int(getU32(output, offKeyInfo))
        let dataType = getU32(output, offKeyInfo + 4)
        guard dataSize > 0, dataSize <= 32 else { return nil }

        // 第二步：读数据
        outputSize = structSize
        input = [UInt8](repeating: 0, count: structSize)
        putU32(&input, offKey, fourCC(key))
        input[offData8] = cmdReadBytes
        putU32(&input, offKeyInfo, UInt32(dataSize))
        putU32(&input, offKeyInfo + 4, dataType)
        kr = input.withUnsafeBytes { inp in
            output.withUnsafeMutableBytes { out in
                IOConnectCallStructMethod(conn, kernelIndexSMC, inp.baseAddress, structSize,
                                          out.baseAddress, &outputSize)
            }
        }
        guard kr == KERN_SUCCESS, output[offResult] == 0 else { return nil }

        let typeStr = String(bytes: [
            UInt8((dataType >> 24) & 0xff), UInt8((dataType >> 16) & 0xff),
            UInt8((dataType >> 8) & 0xff), UInt8(dataType & 0xff)
        ], encoding: .ascii) ?? "?"
        return (typeStr, Array(output[offBytes..<(offBytes + dataSize)]))
    }

    private func u8(_ key: String) -> Int? {
        guard let r = read(key), let first = r.bytes.first else { return nil }
        return Int(first)
    }

    private func float(_ key: String) -> Double? {
        guard let r = read(key), r.bytes.count >= 4 else { return nil }
        if r.type == "flt" {
            let bits = getU32(r.bytes, 0)
            let f = Float(bitPattern: bits)
            return Double(f)
        }
        return nil
    }

    func fanRPM() -> Int? {
        if Date().timeIntervalSince(lastRead) < 2 { return cached }
        lastRead = Date()
        cached = nil

        guard open() else { return nil }
        if fanCount == 0 { fanCount = u8("FNum") ?? 0 }
        guard fanCount > 0 else { return nil }
        guard let rpm = float("F0Ac"), rpm >= 0, rpm < 20000 else { return nil }
        cached = Int(rpm.rounded())
        return cached
    }
}

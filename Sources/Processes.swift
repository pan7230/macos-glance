import Foundation
import Cocoa

// MARK: - 进程级采样（C 模块桥接）

/// 与 C 侧 GlanceProc 内存布局一致：int(4)+pad(4)+double(8)+uint64(8)+ptr(8)+ptr(8)
private struct CGlanceProc {
    var pid: Int32
    var cpu: Double
    var mem: UInt64
    var name: UnsafePointer<CChar>?
    var path: UnsafePointer<CChar>?
}

@_silgen_name("glance_procs_sample")
private func glance_procs_sample(_ out: UnsafeMutablePointer<CGlanceProc>, _ cap: Int32) -> Int32

struct ProcInfo {
    let pid: Int32
    let name: String
    let path: String
    let cpu: Double
    let memory: UInt64
}

final class ProcessSampler {
    private let capacity = 512

    /// 采样进程。首次调用返回空数组（建立 CPU 基线）。
    func sample() -> [ProcInfo] {
        var buffer = [CGlanceProc](repeating: CGlanceProc(pid: 0, cpu: 0, mem: 0, name: nil, path: nil),
                                   count: capacity)
        let count = buffer.withUnsafeMutableBufferPointer { buf in
            Int(glance_procs_sample(buf.baseAddress!, Int32(buf.count)))
        }
        guard count > 0 else { return [] }
        return buffer.prefix(count).map { c in
            ProcInfo(pid: c.pid,
                     name: c.name.map { String(cString: $0) } ?? "",
                     path: c.path.map { String(cString: $0) } ?? "",
                     cpu: c.cpu,
                     memory: c.mem)
        }
    }
}

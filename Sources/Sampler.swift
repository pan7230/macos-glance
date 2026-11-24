import Foundation
import Darwin
import IOKit

// MARK: - 一次采样的结果

struct Snapshot {
    var cpu: Double = 0              // 0...1 总体占用
    var cpuCores: Int = 0
    var memUsed: UInt64 = 0          // 活动监视器口径：App 内存 + 有线 + 压缩
    var memTotal: UInt64 = 0
    var netDown: Double = 0          // bytes/s
    var netUp: Double = 0
    var diskFree: Int64 = 0
    var diskTotal: Int64 = 0
    var diskRead: Double = 0         // bytes/s
    var diskWrite: Double = 0
    var cpuTemp: Double? = nil       // 摄氏度
    var fanRPM: Int? = nil           // 无风扇机型为 nil
    var diskTemp: Double? = nil      // 磁盘温度（NAND 传感器）
    var gpuTemp: Double? = nil       // GPU 温度（tdev 传感器近似）
    var gpuUtil: Double? = nil       // GPU 占用 0...1（IOReport）
    var power: Double? = nil         // 系统功耗 W（IOReport）
    var uptime: TimeInterval = 0
    var time: Date = Date()
}

// MARK: - 采集器

final class Sampler {

    private var prevCPU: [UInt64] = []
    private var prevNet: (down: UInt64, up: UInt64) = (0, 0)
    private var prevDisk: (read: UInt64, write: UInt64) = (0, 0)
    private var prevTime: Date?
    private var primed = false

    private let pageSize: UInt64 = {
        var s: vm_size_t = 0
        host_page_size(mach_host_self(), &s)
        return UInt64(s)
    }()

    private let tempReader = HIDTemperatureReader()
    private let smcReader = SMCReader()
    private let ioReader = IOReportReader()

    init() {
        // 预热一次，避免第一次采样没有基线而显示 0
        _ = sample()
        primed = true
    }

    /// 采样一次。第一次调用时只建立基线，数值为 0。
    func sample() -> Snapshot {
        var snap = Snapshot()
        let now = Date()
        let elapsed = max(0.2, now.timeIntervalSince(prevTime ?? now.addingTimeInterval(-1)))
        prevTime = now

        snap.time = now
        snap.cpuCores = ProcessInfo.processInfo.activeProcessorCount
        snap.uptime = ProcessInfo.processInfo.systemUptime

        snap.cpu = readCPU()
        (snap.memUsed, snap.memTotal) = readMemory()

        // 网络
        let net = readNetworkTotals()
        if primed {
            let dDown = net.down >= prevNet.down ? net.down - prevNet.down : 0
            let dUp = net.up >= prevNet.up ? net.up - prevNet.up : 0
            snap.netDown = Double(dDown) / elapsed
            snap.netUp = Double(dUp) / elapsed
        }
        prevNet = net

        // 磁盘容量
        (snap.diskFree, snap.diskTotal) = readDiskCapacity()

        // 磁盘读写
        let io = readDiskIOTotals()
        if primed {
            let dR = io.read >= prevDisk.read ? io.read - prevDisk.read : 0
            let dW = io.write >= prevDisk.write ? io.write - prevDisk.write : 0
            snap.diskRead = Double(dR) / elapsed
            snap.diskWrite = Double(dW) / elapsed
        }
        prevDisk = io

        snap.cpuTemp = tempReader.maxDieTemperature()
        snap.diskTemp = tempReader.temperature(containing: "nand")
        snap.gpuTemp = tempReader.averageTemperature(containing: "tdev")
        snap.fanRPM = smcReader.fanRPM()
        let ioreport = ioReader.sample()
        snap.gpuUtil = ioreport.gpu
        snap.power = ioreport.power
        return snap
    }

    // MARK: CPU

    private func readCPU() -> Double {
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCpus: natural_t = 0

        let kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                     &numCpus, &cpuInfo, &numCpuInfo)
        guard kr == KERN_SUCCESS, let info = cpuInfo else { return 0 }

        let count = Int(numCpuInfo)
        var ticks = [UInt64](repeating: 0, count: count)
        for i in 0..<count { ticks[i] = UInt64(UInt32(bitPattern: info[i])) }

        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                      vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.size))

        defer { prevCPU = ticks }
        guard prevCPU.count == ticks.count, !prevCPU.isEmpty else { return 0 }

        var busy: UInt64 = 0
        var total: UInt64 = 0
        let stateCount = Int(CPU_STATE_MAX)
        var core = 0
        while core * stateCount + stateCount <= count {
            let base = core * stateCount
            var coreTotal: UInt64 = 0
            var coreBusy: UInt64 = 0
            for s in 0..<stateCount {
                let idx = base + s
                let delta = ticks[idx] >= prevCPU[idx] ? ticks[idx] - prevCPU[idx] : 0
                coreTotal += delta
                if s != Int(CPU_STATE_IDLE) { coreBusy += delta }
            }
            busy += coreBusy
            total += coreTotal
            core += 1
        }
        guard total > 0 else { return 0 }
        return min(1, Double(busy) / Double(total))
    }

    // MARK: 内存

    private func readMemory() -> (used: UInt64, total: UInt64) {
        var total: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        var mib: [Int32] = [CTL_HW, HW_MEMSIZE]
        sysctl(&mib, 2, &total, &size, nil, 0)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<Int32>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return (0, total) }

        let appPages = max(0, Int64(stats.internal_page_count) - min(Int64(stats.internal_page_count),
                                                              Int64(stats.purgeable_count)))
        let usedPages = appPages + Int64(stats.wire_count) + Int64(stats.compressor_page_count)
        let used = UInt64(max(0, usedPages)) * pageSize
        return (min(used, total), total)
    }

    // MARK: 网络

    private func readNetworkTotals() -> (down: UInt64, up: UInt64) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, 6 /* NET_RT_IFLIST2 */, 0]
        var len = 0
        guard sysctl(&mib, 6, nil, &len, nil, 0) == 0, len > 0 else { return (0, 0) }
        var buf = [UInt8](repeating: 0, count: len)
        let ok = buf.withUnsafeMutableBytes { sysctl(&mib, 6, $0.baseAddress, &len, nil, 0) }
        guard ok == 0 else { return (0, 0) }

        var down: UInt64 = 0
        var up: UInt64 = 0
        buf.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= len {
                let hdr = base.advanced(by: offset).assumingMemoryBound(to: if_msghdr.self).pointee
                let msglen = Int(hdr.ifm_msglen)
                if msglen <= 0 { break }
                if Int32(hdr.ifm_type) == 0x12 /* RTM_IFINFO2 */, msglen >= MemoryLayout<if_msghdr2>.size {
                    let m2 = base.advanced(by: offset).assumingMemoryBound(to: if_msghdr2.self).pointee
                    var nameBuf = [CChar](repeating: 0, count: Int(IFNAMSIZ) + 1)
                    if if_indextoname(UInt32(m2.ifm_index), &nameBuf) != nil {
                        let name = String(cString: nameBuf)
                        // 只统计物理网卡，避免 VPN / 虚拟网卡重复计数
                        if name.hasPrefix("en") {
                            down &+= m2.ifm_data.ifi_ibytes
                            up &+= m2.ifm_data.ifi_obytes
                        }
                    }
                }
                offset += msglen
            }
        }
        return (down, up)
    }

    // MARK: 磁盘容量

    private func readDiskCapacity() -> (free: Int64, total: Int64) {
        let url = URL(fileURLWithPath: "/")
        if let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
            let total = Int64(v.volumeTotalCapacity ?? 0)
            let free = v.volumeAvailableCapacityForImportantUsage ?? 0
            return (free, total)
        }
        return (0, 0)
    }

    // MARK: 磁盘读写

    private func readDiskIOTotals() -> (read: UInt64, write: UInt64) {
        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOBlockStorageDriver"),
                                           &iter) == KERN_SUCCESS else { return (0, 0) }
        var drive = IOIteratorNext(iter)
        while drive != 0 {
            if let props = IORegistryEntryCreateCFProperty(drive, "Statistics" as CFString,
                                                          kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] {
                if let r = (props["Bytes (Read)"] as? NSNumber)?.uint64Value { totalRead &+= r }
                if let w = (props["Bytes (Write)"] as? NSNumber)?.uint64Value { totalWrite &+= w }
            }
            IOObjectRelease(drive)
            drive = IOIteratorNext(iter)
        }
        IOObjectRelease(iter)
        return (totalRead, totalWrite)
    }
}

// MARK: - 温度（IOHID 私有接口，只读，无需授权）

private let kHIDEventTypeTemperature: Int64 = 15
private let kHIDEventFieldTemperatureLevel: Int32 = 15 << 16

@_silgen_name("IOHIDEventSystemClientCreateWithType")
private func IOHIDEventSystemClientCreateWithType(_ alloc: CFAllocator?, _ type: Int32,
                                                  _ options: CFDictionary?) -> Unmanaged<CFTypeRef>?
@_silgen_name("IOHIDEventSystemClientSetMatching")
private func IOHIDEventSystemClientSetMatching(_ client: CFTypeRef, _ matching: CFDictionary?) -> Int32
@_silgen_name("IOHIDEventSystemClientCopyServices")
private func IOHIDEventSystemClientCopyServices(_ client: CFTypeRef) -> Unmanaged<CFArray>?
@_silgen_name("IOHIDServiceClientCopyProperty")
private func IOHIDServiceClientCopyProperty(_ service: CFTypeRef, _ key: CFString) -> Unmanaged<CFTypeRef>?
@_silgen_name("IOHIDServiceClientCopyEvent")
private func IOHIDServiceClientCopyEvent(_ service: CFTypeRef, _ type: Int64,
                                         _ options: Int32, _ timestamp: Int64) -> Unmanaged<CFTypeRef>?
@_silgen_name("IOHIDEventGetFloatValue")
private func IOHIDEventGetFloatValue(_ event: CFTypeRef, _ field: Int32) -> Double

final class HIDTemperatureReader {
    private var client: CFTypeRef?
    private var serviceList: [CFTypeRef] = []
    private var lastRefresh = Date.distantPast

    private func ensureClient() {
        if client == nil {
            let typeMonitor: Int32 = 1
            client = IOHIDEventSystemClientCreateWithType(kCFAllocatorDefault, typeMonitor, nil)?
                .takeRetainedValue()
        }
        guard let client else { return }
        let matching: [String: Any] = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5]
        _ = IOHIDEventSystemClientSetMatching(client, matching as CFDictionary)
        if let arr = IOHIDEventSystemClientCopyServices(client)?.takeRetainedValue() as? [CFTypeRef] {
            serviceList = arr
        }
    }

    /// 取所有 CPU 核心（tdie）传感器里的最高值
    func maxDieTemperature() -> Double? {
        if Date().timeIntervalSince(lastRefresh) > 60 || serviceList.isEmpty {
            ensureClient()
            lastRefresh = Date()
        }
        var best: Double?
        for service in serviceList {
            guard let name = IOHIDServiceClientCopyProperty(service, "Product" as CFString)?
                .takeRetainedValue() as? String else { continue }
            let lower = name.lowercased()
            guard lower.contains("tdie") || lower.contains("cpu") else { continue }
            guard let ev = IOHIDServiceClientCopyEvent(service, kHIDEventTypeTemperature, 0, 0)?
                .takeRetainedValue() else { continue }
            let t = IOHIDEventGetFloatValue(ev, kHIDEventFieldTemperatureLevel)
            if t > 1, t < 130 {
                best = max(best ?? 0, t)
            }
        }
        return best
    }

    /// 按名称关键字求一组温度传感器的平均值（如 "tdev" = GPU/协处理器 die 近似）。
    func averageTemperature(containing keyword: String) -> Double? {
        if Date().timeIntervalSince(nameCacheTime) > 60 || serviceList.isEmpty {
            ensureClient()
            let arr = IOHIDEventSystemClientCopyServices(client!)?.takeRetainedValue() as? [CFTypeRef] ?? []
            nameCache = [:]
            for sv in arr {
                if let name = IOHIDServiceClientCopyProperty(sv, "Product" as CFString)?
                    .takeRetainedValue() as? String {
                    nameCache[name] = sv
                }
            }
            nameCacheTime = Date()
        }
        var sum = 0.0; var cnt = 0
        for (name, service) in nameCache {
            guard name.lowercased().contains(keyword.lowercased()) else { continue }
            guard let ev = IOHIDServiceClientCopyEvent(service, kHIDEventTypeTemperature, 0, 0)?
                .takeRetainedValue() else { continue }
            let t = IOHIDEventGetFloatValue(ev, kHIDEventFieldTemperatureLevel)
            if t > 1, t < 130 { sum += t; cnt += 1 }
        }
        return cnt > 0 ? sum / Double(cnt) : nil
    }

    /// 按名称关键字找温度传感器（如 "nand" = 磁盘）。结果缓存，避免每秒全量枚举。
    private var nameCache: [String: CFTypeRef] = [:]
    private var nameCacheTime = Date.distantPast
    func temperature(containing keyword: String) -> Double? {
        if Date().timeIntervalSince(nameCacheTime) > 60 || serviceList.isEmpty {
            ensureClient()
            let arr = IOHIDEventSystemClientCopyServices(client!)?.takeRetainedValue() as? [CFTypeRef] ?? []
            nameCache = [:]
            for s in arr {
                if let name = IOHIDServiceClientCopyProperty(s, "Product" as CFString)?
                    .takeRetainedValue() as? String {
                    nameCache[name] = s
                }
            }
            nameCacheTime = Date()
        }
        for (name, service) in nameCache {
            guard name.lowercased().contains(keyword.lowercased()) else { continue }
            guard let ev = IOHIDServiceClientCopyEvent(service, kHIDEventTypeTemperature, 0, 0)?
                .takeRetainedValue() else { continue }
            let t = IOHIDEventGetFloatValue(ev, kHIDEventFieldTemperatureLevel)
            if t > 1, t < 130 { return t }
        }
        return nil
    }
}

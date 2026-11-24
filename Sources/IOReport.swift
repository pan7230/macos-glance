import Foundation

/// C 模块返回的采样结果（字段顺序须与 ioreport.c 的 GlanceIOResult 一致）
struct GlanceIOResult {
    var gpu_util: Double
    var power_w: Double
    var disk_temp: Double
}

@_silgen_name("glance_io_init")
func glance_io_init()

@_silgen_name("glance_io_sample")
func glance_io_sample() -> GlanceIOResult

/// 封装 C 侧 IOReport 读取。私有 API 全部在 C 模块里调用（Swift 直接调会 ABI 崩溃）。
/// 能量通道在 macOS 27 常于采样窗口内读到 0，缓存上一次有效值避免闪烁。
final class IOReportReader {
    private var lastPower: Double? = nil

    init() {
        glance_io_init()
    }

    func sample() -> (gpu: Double?, power: Double?) {
        let r = glance_io_sample()
        let gpu = r.gpu_util >= 0 ? r.gpu_util : nil
        if r.power_w > 0 { lastPower = r.power_w }
        return (gpu, lastPower)
    }
}

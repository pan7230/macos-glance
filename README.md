# Glance — 极简菜单栏系统状态

一个只用系统 API、零第三方依赖的原生 macOS 菜单栏应用，功能只做一件事：实时显示系统状态。
（动机：MangoDisk 的菜单栏状态好用，但它是 Tauri 单体二进制，无法剥离，于是用 Swift 重写了一个高度还原的极简版。）

## 功能

- **菜单栏常驻**：严格仿 MangoDisk——8 个独立小项，上英文标签下数值、青绿色；网络项单独渲染为红色 ↑上传 / 蓝色 ↓下载 双行、无 NET 标签
- **点击弹出详情面板**：米白背景 + 白卡片 + 橙色标签下划线，标签页（概览 / CPU / GPU / 内存 / 磁盘 / 网络）布局与 MangoDisk 一致
  - **CPU / 内存页含应用进程列表**：真实进程名 + 图标 + CPU%/内存占用，按占用排序（`libproc` 的 `rusage_info_v4.ri_phys_footprint`，活动监视器口径）
  - CPU 页三列核心频率、GPU 页引擎活动、磁盘页容量/活动/健康、网络页流量与网卡信息
- **开机自启**：LaunchAgent（`~/Library/LaunchAgents/com.pangu.glance.autostart.plist`）
- **右键菜单**：刷新一次 / 退出

## 数据来源（全部系统接口，无授权弹窗、无需 root）

| 指标 | 接口 |
|---|---|
| CPU | `host_processor_info` |
| 内存 | `host_statistics64`（活动监视器口径：App 内存 + 有线 + 压缩） |
| 网络 | `sysctl(NET_RT_IFLIST2)`，只统计物理网卡（en*），VPN 虚拟网卡不计重复 |
| 磁盘容量 / 读写 | `NSURL volumeAvailableCapacity` / IOKit `IOBlockStorageDriver` |
| CPU 温度 | IOHID 私有接口，取全部 tdie 核心传感器最高值 |
| 磁盘温度 | IOHID `NAND CH0 temp` 传感器 |
| GPU 温度 | IOHID tdev 传感器平均值（Apple Silicon GPU 与 CPU 共享 die，为近似值） |
| GPU 占用 | IOReport `GPU Stats` 的 `GPUPH` 状态 residency（非 OFF 占比） |
| 系统功耗 | IOReport `Energy Model` 聚合通道；部分机型该组无 CPU 通道会显示"—" |
| 风扇 | SMC `F0Ac`，无风扇机型自动隐藏 |
| 进程 CPU / 内存 | `libproc`：`proc_pid_rusage(RUSAGE_INFO_V4)` 的 CPU 时间差与 `ri_phys_footprint`，采样逻辑在 `Sources/c/procs.c` |

> GPU 占用 / 功耗走 `libIOReport.dylib`（私有框架，dlopen 动态加载，失败自动降级）。采样逻辑封装在 `Sources/c/ioreport.c`，避免 Swift 调私有 C API 的 ABI 问题。已实测：GPU 空闲 0%、负载 100%。

### 已知限制
- 系统功耗（SYS）在部分机型（含 Apple Silicon）IOReport `Energy Model` 无 CPU 聚合通道，显示"—"；`powermetrics` 需 root，不采用。
- CPU 实时频率无公开 API，核心频率按机型标称值展示；GPU/磁盘健康的部分 SMART 字段无系统接口，显示"—"。
- 菜单栏项多（MangoDisk 与 Glance 同时开着共 16 项）时，macOS 可能折叠隐藏部分状态项，属系统状态栏空间限制。

## 下载安装

- **现成安装包**：[Releases 页面](https://github.com/pan7230/macos-glance/releases) 下载 `Glance.zip`，解压后把 `Glance.app` 拖到「应用程序」文件夹即可。
- ad-hoc 签名，首次打开若被 Gatekeeper 拦截：右键 → 打开。
- 源码自行构建：`./build.sh` 产出通用二进制（arm64 + x86_64，约 900KB）。

## 构建 / 运行

```bash
./build.sh                    # 编译打包，产物 build/Glance.app（通用二进制）
open build/Glance.app         # 启动
./build/Glance.app/Contents/MacOS/Glance --dump   # 命令行诊断：输出一次完整采样
```

## 安装与自启

1. 把 `build/Glance.app` 拖到「应用程序」文件夹；
2. 启动后点开面板，勾选「开机自启」（走系统 SMAppService）。

若当前会话无法向 launchd 注册（例如远程/受限会话里点开关没生效），可改用 LaunchAgent：
在 `~/Library/LaunchAgents/com.pangu.glance.autostart.plist` 放入 `RunAtLoad=true`、
`ProgramArguments` 指向 `/Applications/Glance.app/Contents/MacOS/Glance` 的配置，下次登录自动生效。
注意这两种机制是独立的：用了 LaunchAgent 就不要再勾面板里的开关，否则会启动两个实例。

CI：推送 `v*` 标签会自动构建并把 `Glance.zip` 发布到 Releases（见 `.github/workflows/build.yml`）。

## 建议

- 日常使用建议只保留默认三项（CPU / 内存 / 网络），菜单栏最清爽。
- 想改菜单栏字号、采样间隔，改 `Sources/main.swift` / `Views.swift` 后重新 `./build.sh` 即可。

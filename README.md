# Glance — 极简菜单栏系统状态

一个只用系统 API、零第三方依赖的原生 macOS 菜单栏应用，功能只做一件事：实时显示系统状态。
（动机：MangoDisk 的菜单栏状态好用，但它是 Tauri 单体二进制，无法剥离，于是用 Swift 重写了一个极简版。）

## 功能

- **菜单栏常驻**：纯文字实时显示 CPU、内存、网络上下行（可在面板里勾选显示项）
- **点击弹出详情面板**：CPU / 内存 / 网络（带 60 秒走势图）/ 磁盘容量与读写 / CPU 温度 / 风扇
- **开机自启**：面板内一键开关（基于 SMAppService）
- **右键菜单**：刷新一次 / 退出

## 数据来源（全部系统接口，无授权弹窗）

| 指标 | 接口 |
|---|---|
| CPU | `host_processor_info` |
| 内存 | `host_statistics64`（活动监视器口径：App 内存 + 有线 + 压缩） |
| 网络 | `sysctl(NET_RT_IFLIST2)`，只统计物理网卡（en*），VPN 虚拟网卡不计重复 |
| 磁盘容量 | `NSURL volumeAvailableCapacity` |
| 磁盘读写 | IOKit `IOBlockStorageDriver` Statistics |
| CPU 温度 | IOHID 私有接口（只读，无需授权），取全部 tdie 核心传感器最高值 |
| 风扇 | SMC `F0Ac`，无风扇机型自动隐藏为"无风扇机型" |

## 下载安装

- **现成安装包**：[Releases 页面](https://github.com/pan7230/macos-glance/releases) 下载 `Glance.zip`，解压后把 `Glance.app` 拖到「应用程序」文件夹即可。
- ad-hoc 签名，首次打开若被 Gatekeeper 拦截：右键 → 打开。
- 源码自行构建：`./build.sh` 产出通用二进制（arm64 + x86_64，约 456KB）。

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

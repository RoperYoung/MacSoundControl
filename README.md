<p align="center">
  <img src="Assets/AppIcon.png" width="128" height="128" alt="MacSoundControl logo">
</p>

# MacSoundControl

原生 macOS 菜单栏音频控制工具：切换系统输入/输出、调节系统音量、分别控制每个应用的音量，并让麦克风保持在线。

Native macOS menu bar audio control — switch input/output devices, adjust system volume, control each app's volume independently, and keep your microphone alive.

## 功能

- 在菜单栏直接切换系统输入与系统输出。
- 调节当前系统输出音量并切换静音。
- 在 macOS 15 及以上列出已注册的音频应用，分别保存和控制 `0...100%` 音量。
- 统一控制 / 分开控制两种应用音量模式。
- 可选显示虚拟音频设备。
- 麦克风常驻、开机自动启动和当前输入通道重连。
- 实时声音输入测试，显示 36 段电平、百分比与相对数字满刻度 `dBFS`。
- 原生 AppKit 菜单和主窗口，不使用 WebView。

## 系统要求

- macOS 14 或更高版本：设备切换、系统音量、麦克风常驻和声音测试。
- macOS 15 或更高版本：分应用音量。
- 分应用音量需要在“系统设置 → 隐私与安全性 → 屏幕与系统音频录制”中授权。
- 麦克风常驻和声音测试需要麦克风权限。

## 从源码构建

需要 Xcode Command Line Tools。项目不依赖第三方包管理器。

```bash
git clone https://github.com/RoperYoung/MacSoundControl.git
cd MacSoundControl
./build.sh
open "Build/Release/MacSoundControl.app"
```

`build.sh` 默认构建 arm64 + x86_64 Universal App，并使用 ad-hoc 签名。发布维护者可通过 `APP_OUTPUT_PATH` 和 `SIGN_IDENTITY` 显式指定输出位置与 Developer ID。

## 隐私

- 麦克风和应用音频只在当前 Mac 的内存中实时处理。
- 音频不会录制、保存、上传，也不依赖服务端。
- 应用没有遥测、HTTP API 或数据库。

## 项目结构

```text
Sources/                 AppKit、CoreAudio、AVFoundation 与应用逻辑
Tests/                   无 XCTest 依赖的回归与界面探针
Assets/                  应用图标与菜单栏模板图标
Info.plist               App 元数据与隐私用途说明
Entitlements.plist       音频输入 entitlement
build.sh                 Universal App 本地构建脚本
THIRD_PARTY_NOTICES.md   第三方来源与许可
```

## 开源与许可

项目地址：[RoperYoung/MacSoundControl](https://github.com/RoperYoung/MacSoundControl)

项目级许可证尚待维护者确认。`ApplicationAudioMixer.swift` 中源自 MacMix 的部分继续遵循其 MIT 许可，详情见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

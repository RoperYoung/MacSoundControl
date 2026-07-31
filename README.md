<a id="readme-top"></a>

<p align="center">
  <img src="Assets/AppIcon.png" width="116" height="116" alt="Mac Sound Control app icon">
</p>

<h1 align="center">Mac Sound Control</h1>

<p align="center">
  <strong>One native panel for every layer of Mac audio.</strong><br>
  一个原生面板，集中控制 Mac 的系统声音、应用音量与麦克风。
</p>

<p align="center">
  <a href="https://github.com/RoperYoung/MacSoundControl/releases/download/v1.0.0/Mac%20Sound%20Control-1.0.0.dmg">
    <img src="https://img.shields.io/badge/Download-v1.0.0-7C3AED?style=for-the-badge&logo=github&logoColor=white" alt="Download Mac Sound Control 1.0.0">
  </a>
  <img src="https://img.shields.io/badge/macOS-14%2B-111827?style=for-the-badge&logo=apple&logoColor=white" alt="Requires macOS 14 or later">
  <img src="https://img.shields.io/badge/Universal-Apple%20Silicon%20%2B%20Intel-DB2777?style=for-the-badge" alt="Universal app for Apple Silicon and Intel">
</p>

<p align="center">
  <a href="#简体中文">简体中文</a>
  &nbsp;·&nbsp;
  <a href="#english">English</a>
  &nbsp;·&nbsp;
  <a href="https://github.com/RoperYoung/MacSoundControl/releases">Releases</a>
  &nbsp;·&nbsp;
  <a href="#隐私--privacy">Privacy</a>
</p>

---

## Built for everyday audio work

| System & apps | Devices |
| --- | --- |
| Control the main output and each application's volume from one place. | Switch built-in, Bluetooth, USB, display, AirPlay, Continuity, and virtual devices. |
| **Microphone** | **Native & private** |
| Keep the current input awake and inspect its live level when needed. | AppKit + CoreAudio, no WebView, no account, no telemetry, and no audio upload. |

## Product preview / 软件预览

### Main window / 主界面

<p align="center">
  <img src="docs/images/macsoundcontrol-main.png" width="920" alt="Mac Sound Control native main window with audio controls">
</p>

### Menu bar panel / 菜单栏控制面板

<p align="center">
  <img src="docs/images/macsoundcontrol-menu.png" width="440" alt="Mac Sound Control complete menu bar panel">
</p>

---

<a id="简体中文"></a>

## 简体中文

[English](#english) · [返回顶部](#readme-top)

### 把日常声音控制收进一个原生面板

Mac Sound Control 是一款原生 macOS 菜单栏工具。你可以在同一个地方切换系统输入与输出、调整系统总音量、分别控制应用音量，并让当前麦克风保持在线。它使用 AppKit 与 CoreAudio 构建，不使用 WebView，也不会在 Dock 中留下多余图标。

当前正式版本为 **1.0.0（Build 100）**，同时支持 Apple Silicon 与 Intel Mac。

### 核心能力

- **系统声音**：调节当前系统输出音量，一键静音或恢复。
- **应用音量**：在 macOS 15 及以上分别保存和控制每个音频应用的 `0...100%` 音量，并随时切换“统一控制 / 分开控制”。
- **设备切换**：识别并切换内建、蓝牙、USB、显示器、AirPlay、连续互通与虚拟音频设备。
- **麦克风常驻**：减少部分蓝牙或无线麦克风重新唤醒的等待。
- **声音测试**：以 36 段电平、百分比和相对数字满刻度 `dBFS` 实时显示输入强度。
- **原生更新**：通过 Sparkle 检查、验证、下载、替换并重启应用。

### 系统要求与权限

| 能力 | 要求 |
| --- | --- |
| 设备切换、系统音量、麦克风常驻、声音测试 | macOS 14 或更高版本 |
| 分应用音量 | macOS 15 或更高版本 |
| 麦克风常驻与声音测试 | 麦克风权限 |
| 分应用音量 | “系统设置 → 隐私与安全性 → 屏幕与系统音频录制”权限 |

> HDMI、DisplayPort 或部分外置设备可能不提供可写的系统主音量。此时仍可切换设备，但需要通过显示器、扩音器或设备本身调整音量。

### 安装

1. 下载 [`Mac Sound Control-1.0.0.dmg`](https://github.com/RoperYoung/MacSoundControl/releases/download/v1.0.0/Mac%20Sound%20Control-1.0.0.dmg)。
2. 打开 DMG，将应用拖入“应用程序”文件夹。
3. 启动应用，并按实际使用的功能授予麦克风或系统音频权限。
4. 点击菜单栏中的扬声器图标开始使用。

正式 DMG 与应用均使用 Apple Developer ID 签名、通过 Apple 公证，并装订公证票据。

### 安全更新

应用使用 Sparkle 2.9.4 定期读取 GitHub Pages 上的静态更新清单；你也可以在主窗口“关于”区段手动检查更新。每个更新包都同时经过：

- Apple Developer ID 签名；
- Apple 公证；
- Sparkle EdDSA 更新签名。

发现新版本后，Sparkle 会先征得你的同意；应用默认不会静默安装更新。

<a id="隐私--privacy"></a>

### 隐私

- 麦克风与应用音频只在当前 Mac 的内存中实时处理。
- 音频不会录制、写入磁盘、播放、上传或用于语音识别。
- 应用没有账号、遥测、自建服务端、写入型 HTTP API 或数据库。
- 网络访问仅用于读取静态更新清单，并在你确认后下载 GitHub Release 更新包。

### 仓库与源码

这里是 Mac Sound Control 的官方产品与发布仓库，保留产品说明、真实运行截图、更新清单、发布说明和第三方声明。应用源码、测试、构建配置、签名和公证工具不在此仓库中，因此无法从当前仓库二次构建应用。

Mac Sound Control 当前不作为开源软件发布。请只从本项目的 [GitHub Releases](https://github.com/RoperYoung/MacSoundControl/releases) 下载由维护者签名并经 Apple 公证的正式版本。

### 第三方声明

正式应用包含遵循各自许可的 MacMix 衍生部分与 Sparkle。完整信息见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

---

<a id="english"></a>

## English

[简体中文](#简体中文) · [Back to top](#readme-top)

### Everyday Mac audio, in one native panel

Mac Sound Control is a native macOS menu bar utility for switching system inputs and outputs, adjusting the main output, controlling application volumes independently, and keeping the current microphone awake. It is built with AppKit and CoreAudio, uses no WebView, and stays out of the Dock.

The current production release is **1.0.0 (Build 100)**, delivered as a Universal app for Apple Silicon and Intel Macs.

### Highlights

- **System audio** — adjust the current output and toggle mute.
- **Per-app volume** — save and control each audio application's `0...100%` level on macOS 15 or later.
- **Device switching** — recognize built-in, Bluetooth, USB, display, AirPlay, Continuity, and virtual audio devices.
- **Mic keep-alive** — reduce wake-up delays on some Bluetooth and wireless microphones.
- **Input test** — inspect live input with a 36-segment meter, percentage, and relative `dBFS` value.
- **Native updates** — let Sparkle verify, download, replace, and relaunch the app.

### Requirements and permissions

| Capability | Requirement |
| --- | --- |
| Device switching, system volume, mic keep-alive, and input test | macOS 14 or later |
| Per-application volume | macOS 15 or later |
| Mic keep-alive and input test | Microphone permission |
| Per-application volume | Screen & System Audio Recording permission in System Settings |

> HDMI, DisplayPort, and some external devices do not expose a writable main-volume property. The app can still switch to them, but volume must be adjusted on the display, amplifier, or device itself.

### Install

1. Download [`Mac Sound Control-1.0.0.dmg`](https://github.com/RoperYoung/MacSoundControl/releases/download/v1.0.0/Mac%20Sound%20Control-1.0.0.dmg).
2. Open the DMG and drag the app into Applications.
3. Launch the app and grant microphone or system-audio access only for the features you use.
4. Click the speaker icon in the menu bar.

The production app and DMG are signed with Apple Developer ID, notarized by Apple, and stapled with their notarization tickets.

### Secure updates

Sparkle 2.9.4 reads a static update feed hosted on GitHub Pages. You can also check manually from the About section. Every update is protected by:

- Apple Developer ID signing;
- Apple notarization;
- Sparkle EdDSA update signing.

Sparkle asks before installing an available update; silent installation is disabled by default.

### Privacy

- Microphone and application audio are processed only in memory on the current Mac.
- Audio is never recorded, written to disk, played back, uploaded, or used for speech recognition.
- The app has no account system, telemetry, custom backend, write API, or database.
- Network access is limited to reading the static update feed and downloading a GitHub Release after you approve it.

### Repository and source code

This is the official product and release repository for Mac Sound Control. It contains product information, real runtime screenshots, the update feed, release notes, and third-party notices. Application source code, tests, build configuration, signing material, and notarization tooling are not included, so the app cannot be rebuilt from this repository.

Mac Sound Control is not currently distributed as open-source software. Download only maintainer-signed and Apple-notarized builds from this project's [GitHub Releases](https://github.com/RoperYoung/MacSoundControl/releases).

### Third-party notices

Official builds include MacMix-derived portions and Sparkle under their respective licenses. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for details.

<p align="right"><a href="#readme-top">Back to top / 返回顶部</a></p>

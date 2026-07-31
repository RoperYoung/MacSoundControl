<a id="readme-top"></a>

<p align="center">
  <img src="Assets/AppIcon.png" width="116" height="116" alt="Mac Sound Control 应用图标">
</p>

<h1 align="center">Mac Sound Control</h1>

<p align="center">
  <strong>一个原生面板，集中控制 Mac 的系统声音、应用音量与麦克风。</strong>
</p>

<p align="center">
  <strong>简体中文</strong>
  &nbsp;·&nbsp;
  <a href="README_EN.md">English</a>
</p>

---

<h2 align="center">⬇️ 下载 Mac Sound Control</h2>

<p align="center">
  <strong>当前正式版本：1.0.0（Build 100）</strong>
</p>

<p align="center">
  <a href="https://github.com/RoperYoung/MacSoundControl/releases">
    <img src="https://img.shields.io/badge/%E5%89%8D%E5%BE%80_Releases_%E4%B8%8B%E8%BD%BD-7C3AED?style=for-the-badge&logo=github&logoColor=white" width="320" alt="前往 Releases 下载 Mac Sound Control">
  </a>
</p>

<p align="center">
  <a href="https://github.com/RoperYoung/MacSoundControl/releases"><strong>打开 Releases 页面，选择最新版本下载</strong></a><br>
  <sub>支持 macOS 14 或更高版本 · Apple Silicon 与 Intel Mac</sub>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-111827?style=flat-square&logo=apple&logoColor=white" alt="需要 macOS 14 或更高版本">
  <img src="https://img.shields.io/badge/Universal-Apple%20Silicon%20%2B%20Intel-DB2777?style=flat-square" alt="同时支持 Apple Silicon 与 Intel">
</p>

---

## 为日常音频工作而生

| 系统与应用 | 设备 |
| --- | --- |
| 在一个地方调节系统主输出，并分别控制每个应用的音量。 | 切换内建、蓝牙、USB、显示器、AirPlay、连续互通与虚拟音频设备。 |
| **麦克风** | **原生与私密** |
| 让当前输入保持在线，并在需要时查看实时输入电平。 | AppKit + CoreAudio，无 WebView、无账号、无遥测，也不会上传音频。 |

## 软件预览

### 分开控制

<p align="center">
  <img src="docs/images/macsoundcontrol-menu.png" width="520" alt="Mac Sound Control 分开控制模式下的完整菜单栏面板">
</p>

### 统一控制

<p align="center">
  <img src="docs/images/macsoundcontrol-main.png" width="520" alt="Mac Sound Control 统一控制模式下的紧凑菜单栏面板">
</p>

---

## 产品介绍

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

1. 打开 [GitHub Releases](https://github.com/RoperYoung/MacSoundControl/releases)，下载最新的 DMG。
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

<p align="center">
  <a href="README_EN.md">English version</a>
  &nbsp;·&nbsp;
  <a href="#readme-top">返回顶部</a>
</p>

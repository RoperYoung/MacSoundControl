<a id="readme-top"></a>

<p align="center">
  <img src="Assets/AppIcon.png" width="116" height="116" alt="Mac Sound Control app icon">
</p>

<h1 align="center">Mac Sound Control</h1>

<p align="center">
  <strong>One native panel for system audio, per-app volume, and microphones on your Mac.</strong>
</p>

<p align="center">
  <a href="README.md">简体中文</a>
  &nbsp;·&nbsp;
  <strong>English</strong>
</p>

<p align="center">
  <a href="https://github.com/RoperYoung/MacSoundControl/releases">
    <img src="Assets/download-macos-en.svg" width="280" alt="Download Mac Sound Control 1.0.0 (Build 100)">
  </a>
</p>

<p align="center">
  <sub>macOS 14+ · Apple Silicon + Intel · <a href="https://github.com/RoperYoung/MacSoundControl/releases">View all releases</a></sub>
</p>

---

## Built for everyday audio work

| System & apps | Devices |
| --- | --- |
| Control the main output and each application's volume from one place. | Switch built-in, Bluetooth, USB, display, AirPlay, Continuity, and virtual devices. |
| **Microphone** | **Native & private** |
| Keep the current input awake and inspect its live level when needed. | AppKit + CoreAudio, no WebView, no account, no telemetry, and no audio upload. |

## Product preview

<table width="100%">
  <thead>
    <tr>
      <th width="50%" align="center">Per-app control</th>
      <th width="50%" align="center">Unified control</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td align="center" valign="top">
        <a href="docs/images/macsoundcontrol-menu.png">
          <img src="docs/images/macsoundcontrol-menu.png" width="400" alt="Mac Sound Control menu bar panel in per-app volume control mode">
        </a>
      </td>
      <td align="center" valign="top">
        <a href="docs/images/macsoundcontrol-main.png">
          <img src="docs/images/macsoundcontrol-main.png" width="400" alt="Mac Sound Control menu bar panel in unified volume control mode">
        </a>
      </td>
    </tr>
  </tbody>
</table>

---

## Product overview

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

1. Open [GitHub Releases](https://github.com/RoperYoung/MacSoundControl/releases) and download the latest DMG.
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

---

<p align="center">
  <a href="README.md">简体中文</a>
  &nbsp;·&nbsp;
  <a href="#readme-top">Back to top</a>
</p>

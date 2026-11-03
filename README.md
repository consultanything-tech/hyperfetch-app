# ⚡ HyperFetch

<p align="center">
  <img src="assets/icon.png" alt="HyperFetch Icon" width="110" height="110" />
</p>

<p align="center">
  <strong>Native High-Speed Multi-Chunk Download Manager for macOS</strong><br>
  <em>The best lightweight, high-speed native download manager for macOS.</em>
</p>

<p align="center">
  <a href="https://github.com/consultanything-tech/hyperfetch-app/releases/tag/v1.0.3"><img src="https://img.shields.io/badge/Release-v1.0.3-0071E3?style=flat-square&logo=apple" alt="Release v1.0.3" /></a>
  <a href="https://www.apple.com/macos/"><img src="https://img.shields.io/badge/macOS-14%2B%20Sonoma%20%7C%20Sequoia-00D2FF?style=flat-square&logo=apple" alt="macOS 14+ Sonoma / Sequoia" /></a>
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-6.0-F05138?style=flat-square&logo=swift" alt="Swift 6.0" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-30D158?style=flat-square" alt="License MIT" /></a>
</p>

---

### 🌐 Live Interactive Demo
Try the interactive web showcase and simulator in your browser:  
👉 **[https://consultanything-tech.github.io/hyperfetch-app/](https://consultanything-tech.github.io/hyperfetch-app/)**

---

## ⚡ 1-Line Terminal Quick Install

Run this single command in Terminal to download, verify, and launch HyperFetch in `/Applications`:

```bash
curl -sSL https://raw.githubusercontent.com/consultanything-tech/hyperfetch-app/main/install.sh | bash
```

---

## 📦 Direct Downloads

| Package | Format | Compatibility | Link |
| :--- | :--- | :--- | :--- |
| **HyperFetch Disk Image** | `.dmg` | macOS 14.0+ (Apple Silicon & Intel) | [**Download HyperFetch.dmg**](https://github.com/consultanything-tech/hyperfetch-app/releases/download/v1.0.3/HyperFetch.dmg) |
| **HyperFetch Portable Archive** | `.zip` | macOS 14.0+ (Apple Silicon & Intel) | [**Download HyperFetch.zip**](https://github.com/consultanything-tech/hyperfetch-app/releases/download/v1.0.3/HyperFetch.zip) |

All official releases and checksums are available on the [**GitHub Releases Page**](https://github.com/consultanything-tech/hyperfetch-app/releases).

---

## 📸 Preview

<p align="center">
  <img src="assets/app_screenshot.png" alt="HyperFetch macOS Screenshot" width="840" style="border-radius: 12px; box-shadow: 0 16px 36px rgba(0,0,0,0.4);" />
</p>

---

## ✨ Key Features

- **🚀 Accelerated Multi-Chunk Range Streaming**: Splits files into 1 to 16 concurrent HTTP range streams, bypassing ISP/server per-connection bandwidth throttling.
- **⚡ Direct POSIX Zero-Copy I/O**: Pre-allocates disk files instantly using low-level POSIX `ftruncate` and parallel concurrent `pwrite` calls without temporary `.part` concatenation delays.
- **🎨 Real-Time Chunk Visualizer**: Watch chunks download in parallel through animated, color-coded segmented progress strips inspired by retro download managers and modernized for Apple glassmorphism.
- **🛡️ Bulletproof Browser Interception**: Local DNS-rebinding-protected HTTP bridge (`http://127.0.0.1:31415`) validates Origin, Host, and `Sec-Fetch-Site` to guard against web-based exploit attempts.
- **🎛️ Dual Token-Bucket Rate Limiter**: Effortlessly set custom speed limits (or toggle Unlimited mode) with sub-millisecond precision.
- **📁 Smart Category Routing**: Automatically files completed downloads into `Applications`, `Archives`, `Documents`, `Video`, or `Music` based on MIME type and file extension.
- **🔄 In-App Auto-Updates**: Seamless version checks against GitHub Releases with background downloading and instant in-place self-update.
- **🪶 Featherweight Native Footprint**: ~6 MB binary, idles under 40 MB RAM. Zero Electron, zero Qt, zero trackers, zero promotional ads.

---

## 🧩 Chrome & Chromium Extension Setup

The companion extension intercepts browser downloads and seamlessly passes them to HyperFetch with full cookie, user-agent, and referer preservation.

### Supported Browsers
Works on **Google Chrome**, **Brave**, **Arc**, **Microsoft Edge**, and **Vivaldi**.

### Setup Instructions
1. Clone or download this repository.
2. In your browser, open the Extensions page by visiting:
   ```text
   chrome://extensions
   ```
3. Enable **Developer mode** via the toggle switch in the upper-right corner.
4. Click **Load unpacked** in the top-left toolbar.
5. Select the [`extensions/chrome`](extensions/chrome) directory in this repo.
6. Done! Any initiated download will be routed into HyperFetch automatically.
   > **Pro Tip**: Hold the `Alt` (or `Option ⌥`) key while clicking a download link to temporarily bypass HyperFetch and use the browser's default download mechanism.

---

## 🧭 Safari & System-Wide Integration

- **Custom Protocol**: Supports `hyperfetch://<url>` links.
- **macOS Services**: Right-click any link or selected URL in Safari and select **Services → Download with HyperFetch**.
- **Clipboard Auto-Detection**: Simply copy any download URL (`Cmd + C`), and HyperFetch can detect and present the Add Download sheet automatically.

---

## 📊 Technical Comparison

| Feature / Metric | HyperFetch | Free Download Manager | Folx | Browser Default |
| :--- | :--- | :--- | :--- | :--- |
| **Binary Size** | **~6 MB** | ~120 MB | ~45 MB | Built-in |
| **Tech Stack** | **Pure Swift 6 & SwiftUI** | Qt / C++ Cross-platform | Obj-C / Swift | C++ Chromium/WebKit |
| **Idle Memory** | **< 40 MB** | ~250 MB | ~150 MB | Shared process |
| **POSIX Pre-allocation** | **Yes (`ftruncate` + `pwrite`)** | Temp part files | File merge | Sequential append |
| **Range Visualizer** | **Real-Time (1–16 Chunks)** | Basic progress | Pro only | Single stream |
| **Telemetry / Ads** | **Zero / 100% Clean** | Banner ads / tracking | Pro upsell popups | Telemetry |
| **In-App Auto-Update**| **Instant In-Place** | Yes | Paid upgrade | Browser updates |

---

## 📄 License

HyperFetch is distributed under the [MIT License](LICENSE).

<div align="center">

  <img src="assets/icon.svg" width="100" height="100" alt="Lockin Logo" />

  # Lockin
  
  **A brutal, tamper-proof, zero-bloat distraction blocker for macOS.**

  [![macOS](https://img.shields.io/badge/macOS-13.0%2B-black?style=flat&logo=apple)](https://apple.com)
  [![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange?style=flat&logo=swift)](https://swift.org)
  [![Release](https://img.shields.io/badge/Release-v1.0.0-green.svg)](https://github.com/sigma-prog/lockin/releases)
  [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

</div>

---
## ⚡ How Lockin Compares

| Feature | **Lockin** | **Cold Turkey** | **Freedom** | **Opal** |
| :--- | :---: | :---: | :---: | :---: |
| **Price** | **Free (Open Source)** | $39 (One-time) | $39.99 / year | $99.99 / year |
| **VPN & DoH Immunity** | ✅ **100% Immune**<br>*(Direct Apple Events)* | ⚠️ Can conflict<br>*(Local proxy)* | ❌ Incompatible<br>*(VPN profile breaks)* | ✅ Immune<br>*(Screen Time API)* |
| **App Termination** | ⚡ **Instant `SIGKILL`**<br>*(Kernel forces close)* | ⚠️ Process Watchdog<br>*(Scans & closes)* | ❌ Soft Overlay<br>*(Asks you to pause)* | ❌ System Shield<br>*(Draws screen cover)* |
| **Clock Anti-Tamper** | ⏱️ **CPU Hardware Clock**<br>*(mach_continuous_time)* | ✅ Encrypted Database<br>*(Internal verification)* | ⚠️ Cloud-synced<br>*(Requires internet)* | ✅ System Managed<br>*(DeviceActivity API)* |
| **Force-Quit Resilience** | 🔄 **Resurrects in <1s**<br>*(Native launchd supervisor)* | ✅ Root Protected<br>*(Owned by UID 0)* | ⚠️ Moderate<br>*(Session lock)* | ⚠️ Moderate<br>*(App sandbox)* |
| **Root (`sudo`) Required** | 🛡️ **None (User Space)**<br>*(Zero system risk)* | ❌ Required<br>*(Installs root daemon)* | ❌ Required<br>*(Installs network profile)* | 🛡️ None<br>*(Apple Sandbox)* |
| **Idle Memory (RAM)** | 🪶 **~22 MB** | ~140 MB | ~180 MB | ~210 MB |
| **Tech Stack** | **Native Swift / ARM64** | C++ / Qt | Electron / Web wrapper | SwiftUI / Catalyst |

## 📥 Installation

1. Download **`Lockin.app.zip`** from the [Latest Release](https://github.com/sigma-prog/lockin/releases).
2. Follow the instructions

## 🔨 Building from Source

If you prefer compiling directly from the source code:

```bash
git clone https://github.com/sigma-prog/lockin.git
cd lockin

swiftc -O -parse-as-library code/AppBlocker.swift code/WebsiteBlocker.swift code/ui.swift -o lockin

# Run
./lockin
```

---

## Permissions Notice

On first launch, macOS will ask for permission to control **System Events**, **Safari**, or **Google Chrome** etc.

Click **Allow**. This enables Lockin to inspect tab URLs and close blacklisted domains without requiring any third-party browser extensions.

---

## 📄 License

This project is open-source under the [MIT License](LICENSE).

Created by **Lucas H**.

# Clashify

**Clashify** is an all-in-one rootful iOS 14 jailbreak package and native application wrapper that runs **Mihomo (Clash.Meta)** userspace TUN routing directly as a root daemon, paired with a lightweight, zero-battery-drain native WebKit GUI (YACD).

Specifically designed for **iOS 14.x (arm64)** devices restored via `futurerestore` with **broken or incompatible SEP (Secure Enclave Processor)**.

---

## ⚡ The Broken SEP Problem & Architectural Solution

### 1. Why Standard iOS VPNs Fail
- Devices restored via `futurerestore` across incompatible SEP boundaries lose Secure Enclave and Keychain functionality (`errSecAuthFailed` / `errSecItemNotFound`).
- Standard iOS VPN frameworks (`NetworkExtension.framework`, `NEConfigurationManager`, `NETunnelProviderManager`) require storing VPN credentials and network configuration profiles in the Keychain.
- As a consequence, App Store VPN clients (Shadowrocket, Loon, Quantumult X, Sing-box) fail immediately or crash when attempting to start a VPN tunnel.

### 2. Root Daemon + Userspace TUN (gVisor)
- Clashify bypasses `NetworkExtension` entirely by running the `mihomo` binary directly as **`root` (UID 0)**.
- It attaches to a virtual `utun` network interface using its built-in userspace networking stack:
  - `stack: gvisor` (handles TCP/IP entirely in userspace without iOS NetworkExtension extensions);
  - `auto-route: true` & `auto-detect-interface: true` (configures Darwin kernel routing tables directly);
  - `mtu: 1400` (optimized for iOS LTE/Cellular `pdp_ip0` interfaces to prevent packet fragmentation);
  - `dns`: Fake-IP stack (`198.18.0.1/16`) with `dns-hijack: [any:53]`.

### 3. Mach-O Platform Conversion (`macOS -> iOS 14`)
- Upstream Go `darwin-arm64` releases default to `LC_BUILD_VERSION` platform `1` (`PLATFORM_MACOS`).
- On iOS, Apple's dynamic linker `dyld` strictly enforces platform matching: when an executable declares itself as macOS, `dyld` rejects all iOS system dylibs (`/usr/lib/libSystem.B.dylib`, Substrate/Substitute injects) with:
  `Reason: mach-o, but not built for platform macOS`.
- Clashify includes an automated converter (`patch_macho.py`) that patches `LC_BUILD_VERSION` to **`platform = 2` (`PLATFORM_IOS`)**, sets `minos: 14.0`, normalizes framework paths, and recomputes the CodeDirectory Page 0 SHA256 hash while preserving the exact `execSegLimit` matching the `__TEXT` segment.

### 4. Overcoming the iOS `sendfile()` Syscall Restriction (`SIGSYS`)
- In standard Go `net/http`, static file serving invokes the `sendfile()` system call.
- On iOS, Apple's XNU kernel blocks `sendfile()` and terminates the process with **`SIGSYS: bad system call`**.
- Clashify resolves this cleanly:
  1. Internal `external-ui` in the Go core is disabled.
  2. A native, in-process C/Objective-C HTTP server (`HTTPServer.m`) is embedded directly into the native iOS app.
  3. It serves the lightweight YACD web interface on `127.0.0.1:9091` using pure POSIX `read()`/`write()` chunks without ever touching `sendfile()`.

### 5. Zero-Battery-Drain Background Lifecycle
- The native app **never runs in the background**.
- When minimized, `AppDelegate.m` starts a strict **10-second timer**:
  ```objc
  self.terminationTimer = [NSTimer scheduledTimerWithTimeInterval:10.0 repeats:NO block:^(NSTimer *timer) {
      [self.httpServer stop];
      exit(0); // Clean termination, freeing all RAM and CPU
  }];
  ```
- If the user switches away for longer than 10 seconds, the app and its embedded web server exit completely. Background battery drain = **0%**.
- Tapping the icon on SpringBoard relaunches it instantly in ~0.2 seconds.

### 6. Bottom Floating Core Control Menu
- Placed conveniently at the bottom center of the screen within easy reach of the thumb.
- Displays a real-time status pill (`🟢 Core: ON` / `🔴 Core: OFF`).
- Tapping it opens an ActionSheet:
  - 🚀 **Start Core**
  - 🛑 **Force Stop (killall)**
  - 🔄 **Restart Core**
  - 🔑 **Change Root Password**
- Prompts for root SSH password on first use and elevates via local SSH / SUID root permissions.

---

## 📁 Repository Structure

```
mihomo-ios14-deb/
├── .gitignore
├── Makefile                          # Top-level build targets (make fetch, make deb)
├── fetch_assets.sh                   # Automates downloading mihomo v1.18.10 & UI
├── build_deb.sh                      # Builds .deb package with -Zgzip compression
├── patch_macho.py                    # Mach-O platform patcher & CodeDirectory hash fixer
├── entitlements.xml                  # Private iOS entitlements (no-sandbox, socket-delegate)
├── com.hrdcoreee.clashify_1.0.0_iphoneos-arm.deb  # Output Debian package
├── pkg_root/                         # Dpkg staging root
│   ├── Applications/
│   │   └── Mihomo.app/               # Native iOS application bundle
│   │       ├── Info.plist            # CFBundleIdentifier: com.hrdcoreee.clashify
│   │       ├── icon.png              # 192x192 retina app icon
│   │       └── yacd/                 # Ultra-lightweight YACD dashboard (500 KB)
│   ├── DEBIAN/
│   │   ├── control                   # Package metadata (Package: com.hrdcoreee.clashify)
│   │   ├── postinst                  # Setup script (permissions, app build, service start)
│   │   └── prerm                     # Cleanup script (killall, unregister)
│   ├── usr/
│   │   └── local/
│   │       └── bin/
│   │           ├── mihomo            # Patched & signed Mihomo arm64 binary
│   │           ├── mihomo-ctl        # Direct CLI controller (start/stop/restart/set-sub)
│   │           └── mihomo-patch-macho# On-device Mach-O patcher utility
│   └── var/
│       └── mobile/
│           └── Library/
│               └── Mihomo/
│                   ├── config.yaml   # Tuned config (gVisor TUN, Fake-IP DNS, 127.0.0.1:9090)
│                   ├── src_app/      # Objective-C source files for in-app compilation
│                   └── src_ctl/      # SUID C wrapper source
└── src/
    ├── MihomoApp/                    # Native iOS App sources (WKWebView + HTTPServer)
    │   ├── main.m                    # Entry point with setuid(0) elevation
    │   ├── AppDelegate.h / .m        # App lifecycle & 10s background auto-kill
    │   ├── RootViewController.h / .m # Fullscreen WKWebView & bottom root control menu
    │   ├── HTTPServer.h / .m         # Pure POSIX socket static server (no sendfile)
    │   └── Info.plist
    ├── MihomoCC/                     # CCSupport Control Center toggle module
    └── mihomo-ctl.c                  # SUID C wrapper source (chmod 4755)
```

---

## 🛠 Building the Package

### 1. Download Upstream Assets
```bash
make fetch
# or
./fetch_assets.sh
```

### 2. Build the `.deb` Package
```bash
make deb
# or
./build_deb.sh
```
The output file `com.hrdcoreee.clashify_1.0.0_iphoneos-arm.deb` (19 MB) will be generated.

---

## 📲 Installation on iPhone

### Step 1: Copy `.deb` to iPhone
From your computer:
```bash
scp com.hrdcoreee.clashify_1.0.0_iphoneos-arm.deb root@<IP_IPHONE>:/var/mobile/
```

### Step 2: Install via dpkg
On your iPhone via SSH (as `root`):
```bash
dpkg -i /var/mobile/com.hrdcoreee.clashify_1.0.0_iphoneos-arm.deb
```

### Step 3: Compile the Native App
Run the build command on the iPhone (automatically installs `clang` if not present):
```bash
mihomo-ctl build-app
```
The native **Clashify** icon will appear on your Home Screen.

---

## ⚙️ CLI Management (`mihomo-ctl`)

Control the core directly from terminal:

```bash
# Start core in background:
mihomo-ctl start

# Stop core immediately (killall -9):
mihomo-ctl stop

# Restart core:
mihomo-ctl restart

# Check daemon and controller status:
mihomo-ctl status

# Add a subscription link and auto-reload nodes:
mihomo-ctl set-sub "https://your-subscription-url-here"

# Refresh subscription nodes via REST API:
mihomo-ctl update-sub
```

---

## 🌐 Web Dashboards

- **Native App:** Tap the **Clashify** icon on your Home Screen. It launches YACD locally via embedded server and automatically connects to `127.0.0.1:9090`.
- **Browser Alternative:** Open Safari on your iPhone and visit:
  - **Zashboard:** [http://zashboard.pages.dev](http://zashboard.pages.dev)
  - **Metacubexd:** [https://metacubex.github.io/metacubexd/](https://metacubex.github.io/metacubexd/)
  - Host: `127.0.0.1`, Port: `9090`, Secret: (empty).

---

## 📄 License
GPLv3 / MIT - based on MetaCubeX/mihomo and haishanh/yacd.

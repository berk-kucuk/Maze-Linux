# Maze Connect

Maze Connect is a pair of companion apps — a Linux desktop daemon (Qt6/QML/C++) and an Android app (Kotlin/Jetpack Compose) — that let your phone remotely monitor and control a Maze Linux desktop over the local network.

---

## Overview

| Component | Platform | Stack |
|-----------|----------|-------|
| Maze Connect Desktop | Linux (Maze Linux) | Qt6, QML, C++ |
| Maze Connect Mobile | Android | Kotlin, Jetpack Compose |

Both apps must be installed and paired before use. All communication happens directly between the phone and the desktop on the same network — nothing is routed through a third-party server.

[SCREENSHOT: dashboard — place at /public/screenshots/maze-connect-dashboard.png]

---

## Pairing & Security

Pairing uses **mutual TLS 1.3**. Each side authenticates the other with a certificate; the connection is confirmed with a verification code shown on both devices, and the desktop's public key is **pinned** on the phone after the first successful pair — later connections are rejected if the key ever changes.

**Pairing steps:**

1. Open Maze Connect Desktop and select **Pair new device**.
2. Open Maze Connect on your Android phone and choose **Add computer**.
3. Confirm that the verification code shown on both screens matches.
4. Accept the pairing request on the desktop.

Once paired, the phone stores the desktop's pinned key and will reconnect automatically whenever both devices are on the same network.

**Connection resilience:** a heartbeat keeps the session alive, and if the connection drops (network change, desktop sleep, etc.) the phone reconnects automatically in the background — no need to reopen the app or re-pair.

---

## Features

### Dashboard

Live system metrics (CPU, RAM, GPU) alongside summary counts for hardening status, running services, and network state.

[SCREENSHOT: dashboard detail — /public/screenshots/maze-connect-dashboard-detail.png]

### maze-guard Killswitches

Direct integration with maze-guard: toggle the camera, microphone, Wi-Fi, and Bluetooth killswitches from the phone. Each toggle requires confirmation before it takes effect.

[SCREENSHOT: guard killswitches — /public/screenshots/maze-connect-guard-killswitches.png]

### Commands

Trigger commands defined on the desktop directly from the phone. Commands themselves can only be added or edited from the desktop side — the phone can only trigger existing ones. Commands marked sensitive require an extra confirmation step on the phone before running.

### Maze AI

Chat with the local Ollama model running on the desktop, from your phone. Inference stays on the desktop — nothing is sent to a third party.

### File Transfer

Two-way file transfer between phone and desktop.

### Android Share Menu Integration

Share to your desktop directly from any Android app's native **Share** menu.

### Open on Phone

Send a link or piece of text from the desktop to the phone; it opens via a notification on the phone.

### Home Screen Widgets

Three Android home-screen widgets, usable without opening the app:

- **Dashboard** — available in three sizes.
- **Commands**
- **Controls** — the maze-guard killswitches.

[SCREENSHOT: widgets — /public/screenshots/maze-connect-widgets.png]

### Multi-Computer Support

The phone can be paired with and connected to multiple desktops at once, with instant switching between them. Each home-screen widget independently chooses which paired computer it displays.

---

## Installation

**Desktop:** install the `maze-connect` package on Maze Linux (available from the application menu or via the package manager).

**Android:** install the Maze Connect APK. [Download the APK](/maze-connect-apk/latest.apk).

---

## Permissions (Android)

Maze Connect requests the following permissions depending on which features you use:

| Permission | Used for |
|------------|----------|
| Network access | Communicating with the paired desktop |
| Notifications | "Open on phone" and connection status |
| Storage / media access | File transfer |
| Share target | Android share-menu integration |

No permission is required unless the corresponding feature is used.

---

## See also

- [Security Reference](Security)
- [Privacy Reference](Privacy)
- [Tools & Apps](Tools)
</content>

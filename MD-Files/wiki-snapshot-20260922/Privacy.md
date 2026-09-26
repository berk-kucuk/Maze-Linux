# Privacy Reference

Maze Linux ships a layered anonymity and privacy stack that is active by default. This page explains each component, why it matters, and how to use it.

---

## Privacy at a Glance

| Layer | Tool | Default State |
|-------|------|--------------|
| MAC address randomization | macchanger + NetworkManager | Active on every boot |
| Encrypted DNS | DNSCrypt-proxy | Active on every boot |
| One-click anonymity stack | Entropy Shield (Tor + DNSCrypt + I2P) | Installed |
| Anonymous browsing | Tor Browser | Installed & configured |
| Anonymous file sharing | OnionShare | Installed |
| Hardened browser | Firefox (hardened profile) | Default browser |
| Zero-fingerprint browser | Mullvad Browser | Installed & configured |
| VPN | Mullvad VPN, ProtonVPN, WireGuard, OpenVPN | Installed & configured |
| Private messenger | Session | Installed & configured |
| KDE telemetry | All KDE / Plasma usage reporting | Disabled |
| Network monitoring | Wireshark, nmap | Installed |
| Tor daemon | tor (0.4.8.12) | Installed (manual start) |

---

## MAC Address Randomization

Every network card has a hardware MAC address that uniquely identifies your device on local networks. Maze randomizes MAC addresses automatically.

### How it works

Two layers:

1. **NetworkManager random MAC (per-connection):** NetworkManager uses a stable random MAC per network connection — different for each SSID, but not your hardware MAC.
2. **mac-changer systemd service:** A service runs at every boot using `macchanger` to randomize the MAC of every physical interface before NetworkManager connects.

### Manual MAC change

Change all MACs immediately without rebooting:

```bash
change-mac-now
```

### Check current MACs

```bash
ip link show
```

The displayed `link/ether` address is the current (randomized) value, not your hardware MAC.

### View MAC change log

```bash
cat /var/log/mac-changer.log
```

---

## DNSCrypt-proxy

Every DNS query you make is a potential privacy leak — your ISP can see every domain name you resolve. DNSCrypt-proxy solves this by encrypting all DNS queries before they leave your machine.

Maze ships DNSCrypt-proxy **preconfigured with a no-logs resolver** that starts automatically at boot.

**Check it's running:**
```bash
systemctl status dnscrypt-proxy
```

**Config:** `/etc/dnscrypt-proxy/dnscrypt-proxy.toml` — change the resolver or add custom DNS stamp entries here.

---

## Entropy Shield

Entropy Shield is a Maze-native tool that activates **Tor + DNSCrypt-proxy + I2P** simultaneously with a single command, layering all three anonymity systems at once.

```bash
entropy-shield --help
```

---

## Tor

Tor 0.4.8.12 routes your traffic through a volunteer-operated relay network with three hops, making it very difficult to trace traffic back to your IP address.

### Tor Browser

The most private way to use Tor:

```bash
torbrowser-launcher
```

On first run it fetches the latest Tor Browser. Tor Browser is pre-hardened: JavaScript is restricted, fonts and canvas are fingerprint-resistant, no history is kept between sessions.

### Tor Daemon (SOCKS proxy)

For routing other applications through Tor:

```bash
sudo systemctl start tor
```

This starts a SOCKS5 proxy on `127.0.0.1:9050`:

```bash
curl --proxy socks5h://127.0.0.1:9050 https://check.torproject.org/api/ip
```

Enable tor at boot:

```bash
sudo systemctl enable tor
```

### OnionShare

Share files or host a web service accessible only over a Tor `.onion` address:

```bash
onionshare /path/to/file
```

The receiver accesses the `.onion` URL in Tor Browser. The file is never uploaded to a third-party server.

---

## Browsers: Privacy Comparison

| Browser | Best for | Fingerprint resistance | Tor support |
|---------|----------|----------------------|-------------|
| Firefox (hardened) | Daily use | High (hardened defaults) | Via SOCKS proxy |
| Brave | Everyday + Chromium compat | High (built-in shielding) | Via SOCKS proxy or Tor windows |
| Mullvad Browser | VPN users wanting Tor-Browser-level hardening | Very high | Designed for VPN, not Tor |
| Tor Browser | Maximum anonymity | Very high (shared fingerprint) | Native |

### Firefox hardening details

The Maze Firefox profile disables:

- Telemetry, crash reporter, data collection
- Pocket, sponsored content, Firefox Suggest
- Studies and experiments

It enables:

- Enhanced Tracking Protection (Strict mode)
- Fingerprinting protection
- Cryptomining protection
- DNS over HTTPS (change to your preferred resolver in Settings)

No extension required — baked into the default profile.

---

## KDE Telemetry

All KDE Plasma and application usage reporting is **disabled** by default in Maze. KDE's opt-in telemetry (User Feedback) is turned off in the Maze system configuration — no usage data is sent to KDE.

---

## VPN

### Mullvad VPN

The Mullvad VPN client is preconfigured. Keeps no logs, accepts anonymous payment, no email required.

```bash
mullvad-vpn
```

### ProtonVPN

The GUI client is installed (account required):

```bash
proton-vpn-gtk-app
```

### WireGuard

Import a WireGuard configuration file from your VPN provider:

```bash
sudo cp your-vpn.conf /etc/wireguard/wg0.conf
sudo wg-quick up wg0
```

Enable at boot:

```bash
sudo systemctl enable wg-quick@wg0
```

### OpenVPN

Import an `.ovpn` file through NetworkManager or via CLI:

```bash
sudo openvpn --config your-vpn.ovpn
```

---

## Session — Private Messaging

Session is an end-to-end encrypted messenger with no account required (uses a Session ID instead of a phone number) and no central metadata server.

```bash
session-desktop
```

---

## Network Analysis Tools

### Wireshark

Capture and inspect network packets. Your user is in the `wireshark` group so you can capture without `sudo`.

```bash
wireshark
```

### nmap

Scan for open ports on your own system or an authorized network:

```bash
nmap -sV -p 1-65535 localhost
```

### aircrack-ng

Wi-Fi security testing. Use only on networks you own or are authorized to test.

### tcpdump

CLI packet capture:

```bash
sudo tcpdump -i eth0 -n
```

---

## Haze and HazeDrop

**Haze** — a Tor-based onion messenger using the Haze Protocol. Run `haze --help` for usage.

**HazeDrop** — anonymous file and text transfer over Tor. Run `hazedrop --help` for usage.

---

## Maze Control Center — Privacy Tab

Open `maze-control-center` and select the **Privacy** tab to see:

- Current MAC address on each interface.
- Whether the MAC changer service is active.
- Whether the Tor daemon is running.
- Copyable commands for `change-mac-now`, starting Tor, and launching Tor Browser.

---

## Privacy Checklist

- [ ] MAC randomization service is active (`systemctl status mac-changer`)
- [ ] Firefox is the default browser with hardened profile intact
- [ ] DNS-over-HTTPS is configured in Firefox Settings
- [ ] WebRTC is disabled if you are not using video calls
- [ ] ProtonVPN or WireGuard is configured if you use a VPN
- [ ] Tor Browser is used for sensitive browsing
- [ ] Session is used instead of SMS/WhatsApp for private conversations
- [ ] Maze Guard is active and rules have been reviewed

# Sekizinci Tur — Kurulu Sistem Denetimi (gerçek donanım)

**Tarih:** 11 Eylül 2026
**Makine:** Lenovo ThinkPad 21JQS2MD00 (Raptor Lake-P, Intel CNVi WiFi, MX550/nouveau),
LUKS2 + btrfs, Secure Boot **açık**, MOK kayıtlı
**Kurulum:** 9 Eylül 2026 19:31 — bu depodan (`packages.x86_64` 9 Eyl 21:34 hâli)
üretilen ISO ile, Calamares/`deploy-to-target.sh` (`maze-installer` 2.0.0-21)
**Yöntem:** Önceki yedi tur kodu okudu. Bu tur **çalışan kurulu sistemi** kodun
vaadiyle karşılaştırdı. Bunun için yeni bir araç yazıldı:
`tools/audit-installed-system.sh` — kaynak ağacından türetilmiş ~400 kontrol,
salt-okunur, `sudo` ile koşar, raporu `/var/tmp/maze-audit-<tarih>.txt`'e yazar.
Rapor: 306 OK · 2 FAIL · ~8 gerçek uyarı. Ardından yetkisiz oturum düzeyinde
ikinci bir el taraması yapıldı.

**Genel sonuç:** Boot zinciri, LUKS/initramfs, root kilidi, canlı ortam
temizliği, paket kümesi, pacman.conf/keyring, servisler, sysctl, btrfs/snapper
düzeni — hepsi kaynaktaki beklentiyle birebir uyuşuyor. Kurulu
`maze-secureboot/snapshots/tools/hardening` dosyaları repo ile bayt bayt aynı.
`maze-boot-check` ve `maze-doctor` temiz. Aşağıdaki bulgular bunun *dışında*
kalanlar.

Bu belge **yaşayan bir liste**dir: her bulgu düzeltildikçe `Durum` satırı
güncellenir ve doğrulama komutu yeniden koşturulur.

---

## Durum tablosu

| # | Bulgu | Ağırlık | Dosya | Durum |
|---|---|---|---|---|
| 1 | `wl` modülü Intel WiFi'de yükleniyor, kernel mitigation'ını kapatıyor | 🔴 | `maze-hardening` 1.0.0-4 (modprobe.d + udev), `maze-tools` 1.1.0-34 (doctor) | ✅ **makinede doğrulandı** — reboot sonrası (14 Eyl 21:34) `wl` yok, `Unpatched return thunk` 0, **`/proc/sys/kernel/tainted` = 0**, iwlwifi/WiFi çalışıyor |
| 2 | Installer kısayolu paket güncellemesiyle `/etc/skel` paneline geri geldi | 🔴 | `maze-plasma-config` 1.2.1-2, `setup-live-user.sh` | ✅ **makinede doğrulandı** (14 Eyl: "installer launcher stripped from skel panel") |
| 3 | mDNS + LLMNR açık; `avahi-daemon` ve `passim` çalışıyor | 🟠 | `maze-hardening` 1.0.0-4 (resolved drop-in + mask), `enable-services.sh`, deploy 5f, doctor | ✅ **makinede doğrulandı** (`-LLMNR -mDNS`, üç birim masked+inactive) |
| 4 | NVRAM'de imzasız `Fallback Linux Boot Manager` girişi kalıyor | 🟠 | `deploy-to-target.sh` 4b, `maze-boot-entries` (1.2.0-14) | ✅ kaynakta düzeltildi · ✅ bu makinede `Boot0001` silindi (14 Eyl) |
| 5 | `calamares` + `xorg-xhost` kurulu sistemde kalıyor | 🟡 | `deploy-to-target.sh` 2c-bis, doctor | ✅ kaynakta düzeltildi · ✅ bu makinede `-Rns` ile kaldırıldı (+ yaml-cpp, libpwquality, cracklib gitti) |
| 6 | `linux-chan-ai` / `sentinai` varsayılan kuruluyor (belge ↔ kod çelişkisi) | 🟡 | `deploy-to-target.sh` `DEFAULT_MAZE_APPS`, `packages.x86_64` yorumu | ✅ kaynakta düzeltildi |
| 7 | `snapper-timeline.timer` etkin — `create-config` kendisi açıyor | 🟡 | `maze-snapshots` 1.1.0-4 (`ensure_timeline_off`, her boot) | ✅ **makinede doğrulandı** (paket scriptlet'i timer'ı kapattı: `disabled`) |
| 8 | DNS gizlilik yapılandırması yok; deploy'daki yorum eski | 🟡 karar | `deploy-to-target.sh` 5e | ✅ karar zaten verilmişti (bkz. bulgu) — yorum düzeltildi |
| 9 | `paru-debug` kuruluyor | ⚪ | `deploy-to-target.sh` `build_one` | ✅ kaynakta düzeltildi |
| 10 | Gerçek kullanıcı `kvm`/`wireshark` gruplarına eklenmiyor | ⚪ | `deploy-to-target.sh` 3 | ✅ kaynakta düzeltildi |
| 11 | archiso kalıntı dosyaları (zararsız) | ⚪ | deploy 5a-bis, `airootfs/usr/share/grub` silindi | ✅ kaynakta düzeltildi |
| 12 | `plasma-meta → plasma-welcome` kırık bağımlılık | ℹ️ bilinen | — | tasarım gereği (audit script açıklıyor) |
| 13 | Kurulum chroot'unda `snap-pac` "fatal library error" | ℹ️ | `in_chroot` → `SNAP_PAC_SKIP=y` | ✅ kaynakta düzeltildi |
| 14 | `ollama` modeli çekilmemiş | ℹ️ | `maze-ai` | ✅ sorun değil — uygulama içinde "download a model" seçici var (`ollama_backend.py`) |
| 15 | İlk boot'ta `freshclam` ve `plasmashell` tek seferlik hatalar | ℹ️ | — | zararsız |
| 16 | `airootfs/etc/modprobe.d/broadcom-wl.conf` ölü; `brcmfmac` kara listede | 🟡 yeni | `broadcom-wl-dkms` | ⬜ açık (aşağıda) |
| 17 | **`maze-boot-entries` hiçbir girişi doğrulayamıyor** — efibootmgr ≥ 18 çıktı biçimi | 🟠 yeni (14 Eyl prova) | `maze-secureboot` 1.2.0-15 | ✅ **makinede doğrulandı** (22:04: `0002 … ok`, "every Maze entry points somewhere real") |
| 18 | ESP'de gereksiz `vmlinuz-<pkgbase>` (16 MB/çekirdek), üstelik imzalanıyor | ⚪ yeni (14 Eyl prova) | `maze-secureboot` 1.2.0-15 (`maze-sb-sign` siliyor) | ✅ **makinede doğrulandı** (paket kurulunca `maze-sb-resign.path` tetiklendi, "removed loose vmlinuz-linux-lts") |
| 19 | Firmware'de önceki kurulumun MOK anahtarı hâlâ kayıtlı (2 makine anahtarı + canlı ISO anahtarı) | 🟡 makine hijyeni | — | ⬜ elle temizlenecek (aşağıda) |
| 20 | `firejail` kurulu ama hiçbir şey sandbox'lanmıyor; Maze uygulamaları için AppArmor profili yok | 🟡 karar | `maze-meta`, uygulamalar | ⬜ karar bekliyor |
| 21 | `mkinitcpio`: `consolefont` hook'u var, `FONT` yok ("no font found") | ⚪ | Calamares `initcpiocfg` | ⬜ kozmetik |
| 22 | **İki farklı `maze-guard` ikilisi** — `/usr/local/bin` (guardd istemcisi) PATH'te uygulamayı gölgeliyor | 🟠 yeni | `maze-tools` 1.1.0-35 → `maze-guardctl` | ✅ kaynakta düzeltildi — 🔲 makinede doğrulanacak |
| 23 | `maze-doctor` root'suz "No active firewall detected" diyor (nft root ister) | ⚪ yeni | `maze-tools` 1.1.0-35 | ✅ kaynakta düzeltildi |
| 24 | `maze-ai --version` 1.12.0 diyor, paket 1.17.0 | ⚪ yeni | `Maze-AI` sürüm dizesi | ⬜ Maze-AI deposunda |
| 25 | `maze-install-vmware` "Missing dependencies: vmware-keymaps" ile çöküyor | 🟡 yeni | `maze-tools` 1.1.0-36 | ✅ **makinede doğrulandı** (VMware kuruldu, modüller yüklü) |
| 26 | **deploy, ISO'daki yeni paketi public'teki eskisine düşürüyor** (`pacman -S --needed` downgrade) | 🔴 yeni (VM testi) | `maze-installer` 2.0.0-23, `maze-aur-setup` | ✅ kaynakta düzeltildi — 🔲 yeni ISO ile doğrulanacak |
| 27 | `maze-aur-setup` listesinde de `linux-chan-ai`/`sentinai` (Bulgu 6'nın 3. kopyası) | 🟡 yeni | `airootfs/…/maze-aur-setup` | ✅ kaynakta düzeltildi |

**Kaynakta yapılan değişiklikler (11 Eylül 2026, bu tur):** aşağıdaki paketler
yeniden derlendi ve `pkgrel` artırıldı. **14 Eylül:** beşi bu makineye `pacman -U`
ile kuruldu (`maze-installer` canlı ISO'ya özgü, kurulmaz); elle adımlar
(`-Rns calamares xorg-xhost`, `efibootmgr -B 0001`) yapıldı; audit script
yeniden koştu: **331 OK · 1 FAIL (wl — o boot'un eski Call Trace'i) · 0 gerçek
uyarı.** Reboot sonrası (21:34): `wl` yüklenmedi, kernel WARNING/Call Trace 0,
`tainted` = 0, failed unit yok, boot 38 s. **Bulgu 1–7 bu makinede kapandı.**
Henüz **yayınlanmadı**.

| Paket | Sürüm | İçerik |
|---|---|---|
| `maze-hardening` | 1.0.0-**4** | Bulgu 1 (`10-maze-broadcom-wl.conf`, `80-maze-broadcom-wl.rules`), Bulgu 3 (`zz-maze-privacy.conf`, `.install` ile tek seferlik `passim`/`avahi` mask) |
| `maze-plasma-config` | 1.2.1-**2** | Bulgu 2 (skel'den `maze-calamares.desktop` pin'i çıkarıldı) |
| `maze-snapshots` | 1.1.0-**4** | Bulgu 7 (`ensure_timeline_off`, her boot) |
| `maze-tools` | 1.1.0-**37** | -33/-34: `maze-doctor` wl/14e4, "Unpatched return thunk", `calamares`/`xorg-xhost`, mDNS/LLMNR, avahi/passim · -35: **Bulgu 22** (`maze-guard` istemcisi → `maze-guardctl`; `maze-panic`, `maze-panic-restore`, `maze-killswitch`, `maze-doctor` güncellendi) + **Bulgu 23** · -36: **Bulgu 25** (`maze-install-vmware` önce `vmware-keymaps`) · -37: `maze-audit` + `maze-exercise` pakete girdi |
| `maze-secureboot` | 1.2.0-**15** | -14: `maze-boot-entries` imzasız systemd-boot girişlerini işaretler · -15: **Bulgu 17** (`path_file` yeni efibootmgr biçimini okuyor) + **Bulgu 18** (`maze-sb-sign` layout=uki'de gevşek `vmlinuz-*`'ı siliyor) |
| `maze-installer` | 2.0.0-**23** | -22: Bulgu 3, 4, 5, 6, 8, 9, 10, 11, 13 · -23: **Bulgu 26** (downgrade yok) |
| ISO (`MazeLinux/`) | — | `setup-live-user.sh` (pin canlı kullanıcıya), `enable-services.sh` (mask), `packages.x86_64` yorumları, `airootfs/usr/share/grub` silindi, `tools/audit-installed-system.sh` yeni beklentiler |

**Bu makinede doğrulama sırası** (kaynaktan derlenen paketlerle):
```sh
cd /run/media/berkkucukk/Backup/Projects/Maze-Linux-Source
sudo pacman -U maze-hardening/maze-hardening-1.0.0-4-any.pkg.tar.zst \
               maze-plasma-config/maze-plasma-config-1.2.1-2-any.pkg.tar.zst \
               maze-snapshots/maze-snapshots-1.1.0-4-any.pkg.tar.zst \
               maze-tools/maze-tools-1.1.0-33-any.pkg.tar.zst \
               maze-secureboot/maze-secureboot-1.2.0-14-any.pkg.tar.zst
sudo pacman -Rns calamares xorg-xhost                       # Bulgu 5 (bu makine için elle)
sudo efibootmgr --bootnum 0001 --delete-bootnum             # Bulgu 4 (Fallback Linux Boot Manager, bu makine için elle)
sudo systemctl start maze-snapshots-setup.service           # Bulgu 7 timer'ı hemen kapatsın
sudo MazeLinux/tools/audit-installed-system.sh              # → Bulgu 1/2/3/5/7 yeşil olmalı
sudo reboot                                                 # wl yüklenmemeli, journal'da Call Trace olmamalı
```
Yayınlama (`publish.sh` sırası: `maze-hardening maze-plasma-config maze-snapshots
maze-secureboot maze-tools maze-installer`, sonra `maze-meta` gerekmez — bağımlılık
listesi değişmedi) ve yeni ISO derlemesi ayrı adımlar; ikisi de bu makinedeki
doğrulamadan **sonra**.

---

## Bulgu 1 — `broadcom-wl` (`wl`) modülü Broadcom olmayan makinede yükleniyor 🔴

**Kanıt (journal, bu boot, tek "Call Trace" bu):**

```
kernel: You are using the broadcom-wl driver, which is not maintained and is
        incompatible with Linux kernel security mitigations. ...
kernel: ------------[ cut here ]------------
kernel: Unpatched return thunk in use. This should not happen!
kernel: WARNING: arch/x86/kernel/cpu/bugs.c:3776 at __warn_thunk+0x10/0x20, CPU#8: (udev-worker)/822
kernel: Tainted: [P]=PROPRIETARY_MODULE, [O]=OOT_MODULE, [E]=UNSIGNED_MODULE
kernel: Call Trace:
kernel:  getvar+0x20/0x70 [wl ...]
kernel:  wl_module_init+0x23/0xb0 [wl ...]
```

Makinede Broadcom yok: `lspci` → `00:14.3 Network controller [0280]: Intel
Raptor Lake PCH CNVi WiFi [8086:51f1]`, sürücü `iwlwifi`. Ama `lsmod` →
`wl 6524928 0`.

**Neden yükleniyor:** `modinfo wl` →
`alias: pci:v*d*sv*sd*bc02sc80i*` — **vendor/device joker**, yalnızca PCI
class `02`/subclass `80` ("Network controller, other"). Intel CNVi tam bu
sınıfta. udev her boot'ta `wl`'i "eşleşen sürücü" olarak yükler.
`airootfs/etc/modprobe.d/broadcom-wl.conf` yalnızca yorumdan oluşuyor
(releng'den miras; asıl amacı `b43` kara listesini *iptal etmek*).

**Neden önemli:** Hardened bir dağıtımda, Broadcom'u olmayan **her** Intel/Realtek
WiFi'li makinede:
- imzasız, proprietary modül kernel'i taint ediyor (`P O E`),
- `Unpatched return thunk` → retbleed/SRSO return-thunk mitigation **tüm
  kernel için** devre dışı,
- her boot'ta bir kernel WARNING + Call Trace (kullanıcı `maze-doctor`'da
  "kernel error" görüyor, donanım sanıyor).

**Düzeltme (öneri, birini seç):**
- **A)** `airootfs/etc/modprobe.d/broadcom-wl.conf`'a `blacklist wl` ekle;
  Broadcom varsa yükleyecek bir udev kuralı ekle:
  `airootfs/etc/udev/rules.d/80-maze-broadcom-wl.rules`
  `ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x14e4", ATTR{class}=="0x028000", RUN+="/usr/bin/modprobe wl"`
  (blacklist yalnızca alias yüklemesini keser; açık `modprobe wl` çalışır.)
- **B)** `broadcom-wl-dkms` + `dkms`'i `packages.x86_64`'ten çıkar; Broadcom
  kullanıcısı `maze-gpu-driver` benzeri bir yolla sonradan kurar.

A seçilirse `maze-doctor`'un "Kernels and out-of-tree modules" bölümüne
"wl yüklü ama 14e4 yok" kontrolü de eklenmeli.

**Doğrulama:**
```sh
lsmod | grep -E '^wl '                         # Intel makinede boş olmalı
journalctl -b -k | grep -c 'Unpatched return thunk'   # 0
cat /proc/sys/kernel/tainted                   # 0 (nouveau/DKMS yoksa)
```

**Yapılan (11 Eyl):** Seçenek A, `maze-hardening` 1.0.0-4 içinde (kurulu makinelere
`pacman -Syu` ile ulaşsın diye airootfs yerine paket):
`usr/lib/modprobe.d/10-maze-broadcom-wl.conf` (`blacklist wl`),
`usr/lib/udev/rules.d/80-maze-broadcom-wl.rules` (`vendor 0x14e4` + class
`0x028000` → `modprobe wl`). `.install` canlı sistemde Broadcom yoksa `wl`'i
hemen `modprobe -r` ile kaldırıyor. `maze-doctor` (1.1.0-33) iki kontrol
kazandı: "wl yüklü ama 14e4 yok" (FAIL) ve journal'da "Unpatched return thunk"
(WARN) — bu makinede ikisi de yakalandı. `packages.x86_64`'e not düşüldü.

**14 Eyl, makinede:** `maze-hardening` 1.0.0-4 kuruldu; scriptlet
"unloaded the stray Broadcom wl module (no Broadcom hardware here)" yazdı,
`lsmod`'da `wl` yok. Audit script'in 14. bölümdeki FAIL'i bu boot'un 18:55'teki
(paket öncesi) yüklemesinden — reboot sonrası `journalctl -b -k | grep -c
'Unpatched return thunk'` = 0 ve `lsmod | grep wl` boş olmalı.

**Reboot sonrası (14 Eyl 21:34):**
```
lsmod | grep -E '^wl '                              → boş
journalctl -b -k | grep -c 'Unpatched return thunk' → 0
cat /proc/sys/kernel/tainted                        → 0      (önceki boot'lar: P O E)
journalctl -b -q | grep -i 'modprobe wl'            → boş    (udev kuralı Intel'de tetiklenmedi)
nmcli dev                                           → wlan0 wifi connected (iwlwifi)
```
Yan etki yok: failed unit 0, boot süresi 38 s (öncekiyle aynı).

**Durum:** ✅ kapandı — kaynakta düzeltildi, makinede reboot ile kanıtlandı

---

## Bulgu 2 — `maze-plasma-config` güncellemesi `/etc/skel` paneline installer kısayolunu geri getirdi 🔴

**Kanıt:**
```
/etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc:
  launchers=applications:maze-calamares.desktop,applications:maze-control-center.desktop,...
pacman.log: [2026-09-10T21:27:03] upgraded maze-plasma-config (1.2.0-1 -> 1.2.1-1)
pacman -Qkk maze-plasma-config: 135 total files, 0 altered files   ← dosya paketin orijinali
```
Kullanıcının (`berkkucukk`) kendi paneli temiz (deploy 3. adımda ev dizinini
ayrıca temizliyor). Ama `/etc/skel` artık tekrar kirli: **bundan sonra
oluşturulan her kullanıcı** dock'ta "Install Maze Linux" görür.

**Sebep:** `MAZE-TAM-REFERANS.md` §9.12'de "olabilir" diye yazan şey sahada
oldu. `maze-plasma-config` skel'i `maze-calamares.desktop` pin'iyle paketliyor;
`deploy-to-target.sh` `strip_installer_launcher()` ile `sed` uyguluyor; pacman
paketi güncelleyince paketin dosyası geri geliyor. Kalıcı çözüm `sed` değil,
**paketin kendisi**.

**Düzeltme:**
1. `maze-plasma-config/maze-plasma-config/etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc`
   içindeki `launchers=` listesinden `applications:maze-calamares.desktop,`
   kaldır, `pkgrel` artır, yayınla.
2. `airootfs/usr/local/share/maze/setup-live-user.sh`'a canlı kullanıcının
   `~/.config/plasma-org.kde.plasma.desktop-appletsrc`'sine pin'i **ekleyen**
   bir `sed` koy (ISO'da kısayol kalmaya devam etsin):
   `sed -i -E 's#^(launchers=)#\1applications:maze-calamares.desktop,#' ...`
3. `deploy-to-target.sh`'daki `strip_installer_launcher` çağrıları kalabilir
   (eski ISO'lardan gelen skel için zararsız güvenlik ağı).

**Doğrulama:**
```sh
grep -c maze-calamares /etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc   # 0
sudo pacman -S maze-plasma-config && grep -c maze-calamares /etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc   # hâlâ 0
```

**Yapılan (11 Eyl):** `maze-plasma-config` 1.2.1-2: `launchers=` listesinden
`applications:maze-calamares.desktop,` çıkarıldı (paket içinde `grep -c` = 0
doğrulandı). `setup-live-user.sh`: `useradd` skel'i kopyaladıktan sonra canlı
kullanıcının kendi `appletsrc`'sine pin'i ekliyor (idempotent). Deploy'daki
`strip_installer_launcher` eski ISO'lar için güvenlik ağı olarak kaldı.

**Durum:** ✅ makinede doğrulandı (14 Eyl, audit: "installer launcher stripped from skel panel", `pacman -Qkk maze-plasma-config: intact`)

---

## Bulgu 3 — mDNS/LLMNR açık, `avahi-daemon` ve `passim` LAN'a yayın yapıyor 🟠

**Kanıt:**
```
resolvectl status (Global):  Protocols: +LLMNR +mDNS -DNSOverTLS DNSSEC=no/unsupported
ss -ltnup:
  udp 0.0.0.0:5353  avahi-daemon
  udp 0.0.0.0:5353  systemd-resolve      (mDNS)
  udp 0.0.0.0:5355  systemd-resolve      (LLMNR)
systemctl is-active avahi-daemon passim  → active active
avahi-daemon: TriggeredBy=avahi-daemon.socket, WantedBy=passim.service
pacman -Qi avahi → Required By: cups libcups ostree passim pipewire-pulse tinysparql
```

**Sebep:** deploy 5e adımı archiso'nun `resolved.conf.d/archiso.conf`'unu
(mDNS=yes) siliyor, ama Arch'ın `systemd-resolved` derleme varsayılanı zaten
`MulticastDNS=yes` + `LLMNR=yes`. Yerine bir "hayır" konmuyor. `passim`
(`fwupd`'nin LAN firmware önbellek paylaşım daemon'u) `static` birim, `fwupd`
ile geliyor ve `avahi-daemon.socket`'i tetikliyor.

**Neden önemli:** "Hiçbir şey makineden çıkmaz" diyen bir dağıtım, hostname'ini
her LAN'a multicast ile duyuruyor ve LLMNR ile isim sorgularına cevap veriyor.
`maze-guard`'ın "hostname_hide" stealth modülü varken bu çelişki.

**Düzeltme:**
1. `airootfs/etc/systemd/resolved.conf.d/10-maze-privacy.conf`:
   ```
   [Resolve]
   MulticastDNS=no
   LLMNR=no
   ```
   (Bu dosya deploy 5e'de **silinmemeli**; yalnız archiso.conf ve maze-dns.conf silinir.)
2. `deploy-to-target.sh` servis bölümüne: `systemctl mask passim.service avahi-daemon.socket avahi-daemon.service`
   — ya da `enable-services.sh`'a (ISO'da da gereksiz). cups'ın ağ yazıcı
   keşfi kaybolur; kabul edilebilir, kullanıcı `maze-control-center`'dan
   açabilmeli (opsiyonel toggle).
3. `maze-doctor` "Security posture" bölümüne mDNS/LLMNR/avahi kontrolü.

**Doğrulama:**
```sh
resolvectl status | grep -m1 Protocols        # -LLMNR -mDNS
ss -lun | grep -E ':5353|:5355'               # boş
systemctl is-active avahi-daemon passim       # inactive inactive
```

**Yapılan (11 Eyl):** `maze-hardening` 1.0.0-4:
`etc/systemd/resolved.conf.d/zz-maze-privacy.conf` (`MulticastDNS=no`,
`LLMNR=no`; `zz-` ile canlı ortamdaki `archiso.conf`'u da geçiyor; `backup=`).
`.install`: `passim.service avahi-daemon.socket avahi-daemon.service` **tek
seferlik** mask (`/var/lib/maze/hardening-lan-silenced` işareti; admin sonradan
unmask ederse bir sonraki güncelleme dokunmaz), canlı sistemde stop + resolved
restart. Aynı mask `enable-services.sh` (ISO) ve deploy 5f'de (hedef) tekrar.
`maze-doctor`: `+mDNS/+LLMNR` ve aktif avahi/passim için WARN.
Yan etki: cups ağ yazıcı keşfi (avahi) kapanır; `maze-control-center`'a
"LAN keşfi" toggle'ı **sonraki iş**.

**Durum:** ✅ makinede doğrulandı (14 Eyl: `Protocols: -LLMNR -mDNS`, passim/avahi `masked` + `inactive`, udp/5353-5355'te resolved/avahi yok). udp/5353'te kalan tek dinleyici `kdeconnectd` — KDE Connect'in kendi keşfi, bilinçli özellik; audit script artık bunu bilgi olarak ayrı yazıyor.

---

## Bulgu 4 — NVRAM'de imzasız `Fallback Linux Boot Manager` girişi kalıyor 🟠

**Kanıt:**
```
Boot0001* Fallback Linux Boot Manager  HD(1,GPT,...)/\EFI\systemd\systemd-boot-fallbackx64.efi
Boot0003* Maze Linux                   HD(1,GPT,...)/\EFI\BOOT\BOOTX64.EFI
BootOrder: 0003,0001,...
```

**Sebep:** Calamares'in `bootctl install`'ı yeni systemd'de iki giriş yaratıyor:
`Linux Boot Manager` (→ `systemd-bootx64.efi`) ve `Fallback Linux Boot
Manager` (→ `systemd-boot-fallbackx64.efi`). deploy 4b yalnızca
`grep -i 'systemd-bootx64\.efi'` ile ilkini siliyor; fallback dosya adı bu
desene uymuyor.

**Neden önemli:** Giriş imzasız bir systemd-boot'a bakıyor; SB açıkken asla
açılmaz. BootOrder'da Maze önde olduğu sürece zararsız, ama NVRAM
sıfırlanır/yeniden sıralanırsa "Security Violation" ekranı. Ayrıca
`maze-boot-entries` bunu "Maze dışı" sayıp dokunmuyor.

**Düzeltme:** `deploy-to-target.sh` 4b: `grep -iE 'systemd-boot(-fallback)?x64\.efi'`.
`maze-boot-entries`'e de "systemd-boot fallback girişi" için bir uyarı satırı.

**Doğrulama:**
```sh
sudo efibootmgr -v | grep -ci 'systemd-boot'   # 0
```

**Yapılan (11 Eyl):** deploy 4b deseni `systemd-boot(-fallback)?x64\.efi`.
`maze-boot-entries` (1.2.0-14) imzasız systemd-boot girişlerini satırda
işaretliyor ve özette sayıyor (silmiyor — Maze'e ait değil kuralı korunuyor).
Bu makinedeki `Boot0001` elle silinecek.

**Durum:** ✅ tamam — bu makinede `Boot0001` silindi (14 Eyl), audit: "no direct unsigned systemd-boot entry", tek `Maze Linux` girişi

---

## Bulgu 5 — `calamares` ve `xorg-xhost` kurulu sistemde kalıyor 🟡

**Kanıt:** `pacman -Q calamares` → `3.4.2-3`, `Install Reason: Explicitly
installed`; `pacman.log` 19:31:47 `removed maze-installer` var, calamares yok.

**Sebep:** deploy 2c-bis yorumu "`-Rns` calamares ve xorg-xhost'u da götürür,
başka bir şey ihtiyaç duymuyorsa" diyor — ama `packages.x86_64` ikisini de
**açıkça** listeliyor, yani pacman'da "explicit" işaretli; `-Rns` explicit
paketlere dokunmaz.

**Neden önemli:** ~60 MB ölü ağırlık + kurulu masaüstünde bir installer ikilisi
(launcher silindiği için menüde görünmüyor). `maze-doctor` "Calamares installer
not present" diyor çünkü yalnız `maze-installer` paketine bakıyor.

**Düzeltme:** deploy 2c-bis:
```sh
in_chroot pacman -Rns --noconfirm maze-installer calamares xorg-xhost
```
(`calamares` yoksa `-Rns` "target not found" ile **tüm** işlemi iptal eder —
önce `pacman -Qq` ile filtrele.) `maze-doctor`'a `calamares` paketi kontrolü.

**Doğrulama:** `pacman -Q calamares xorg-xhost` → ikisi de "was not found".

**Yapılan (11 Eyl):** deploy 2c-bis: `maze-installer calamares xorg-xhost` önce
`pacman -Qq` ile filtrelenip tek `-Rns` ile kaldırılıyor. `maze-doctor`
"Live-medium residue" bölümüne `calamares`/`xorg-xhost` paket kontrolü (bu
makinede WARN veriyor).

**Durum:** ✅ tamam — bu makinede kaldırıldı (14 Eyl; `yaml-cpp libpwquality cracklib` de bağımlılık olarak gitti — `systemd` `libpwquality`'yi yalnız opsiyonel istiyor)

---

## Bulgu 6 — `linux-chan-ai` ve `sentinai` varsayılan kuruluyor 🟡

**Kanıt:** `pacman -Q linux-chan-ai sentinai` → `1.1.4-2`, `1.5.0-1`;
`pacman.log` 19:32-19:33 `installed linux-chan-ai`, `installed sentinai`.

**Sebep:** `maze-meta/PKGBUILD` ve `MAZE-TAM-REFERANS.md` §4.3 ikisini
bilerek dışarıda bırakıyor ("Google Gemini'ye veri gönderebiliyor, sormadan
kurulamaz"). Ama `deploy-to-target.sh:97`:
```sh
DEFAULT_MAZE_APPS=(entropy-shield qlam maze-guard hazedrop haze linux-chan-ai sentinai maze-ai maze-connect maze-cloak)
```
ve Calamares `'all'` geçiriyor → her kurulumda ikisi de geliyor.

**Düzeltme:** İki paketi `DEFAULT_MAZE_APPS`'ten çıkar. (Ya da tam tersi:
belgeyi ve `maze-meta`'yı değiştir — ama gizlilik tezi ilkini söylüyor.)
`maze-welcome`/`maze-control-center`'da "isteğe bağlı: SentinAI, Linux Chan"
kurulum düğmesi zaten varsa yeter; yoksa eklenmeli.

**Doğrulama:** Yeni ISO ile kurulumda `pacman -Q linux-chan-ai sentinai` boş.

**Yapılan (11 Eyl):** `DEFAULT_MAZE_APPS`'ten `linux-chan-ai sentinai` çıkarıldı,
gerekçe yorumda; `packages.x86_64`'teki eski "all Maze apps: … linux-chan-ai,
sentinai" yorumu da düzeltildi. Bu makinede kurulu kalıyorlar (kullanıcı
isterse `pacman -Rns`).

**Durum:** ✅ kaynakta düzeltildi

---

## Bulgu 7 — `snapper-timeline.timer` etkin; `snapper create-config` kendisi açıyor 🟡

**Kanıt (ilk boot journal'ı, 9 Eyl 19:50:27):**
```
Starting Create the Maze snapper configuration for / (once)...
maze-snapshots-setup[1207]: creating the snapper configuration for /
Started DBus interface for snapper.
Reload requested from client PID 1287 ('systemctl') (unit snapperd.service)...
Started Timeline of Snapper Snapshots.                     ← snapperd enable --now yaptı
maze-snapshots-setup[1207]: done.
```
Şimdi: `systemctl is-enabled snapper-timeline.timer` → `enabled`, saat başı
çalışıyor; `TIMELINE_CREATE=no` olduğu için snapshot üretmiyor.

**Sebep:** `86-maze-snapshots.preset` bilerek yalnız `snapper-cleanup.timer`'ı
açıyor, ama `snapper create-config` (D-Bus/snapperd üzerinden) yeni snapper
sürümlerinde timeline timer'ını kendisi etkinleştiriyor. `maze-snapshots-setup`
*sonra* `TIMELINE_CREATE=no` yazıyor, timer'a dokunmuyor.

**Neden önemli:** Zararsız (boş çalışıyor) ama preset'in "bilinçli olarak
kapalı" iddiasıyla çelişiyor; bir gün biri `TIMELINE_CREATE=yes` yaparsa
beklenmedik saatlik snapshot'lar başlar.

**Düzeltme:** `maze-snapshots/maze-snapshots/usr/bin/maze-snapshots-setup`,
`set-config TIMELINE_CREATE=no`'dan sonra:
```sh
systemctl disable --now snapper-timeline.timer >/dev/null 2>&1 || true
```

**Doğrulama:** `systemctl is-enabled snapper-timeline.timer` → `disabled`.

**Yapılan (11 Eyl):** `maze-snapshots-setup` 1.1.0-4: `create_config` içinde
`set-config`'den hemen sonra `systemctl disable --now snapper-timeline.timer`;
ayrıca yeni **3. iş** `ensure_timeline_off` her boot'ta çalışıyor — config'de
`TIMELINE_CREATE=no` iken timer `enabled` ise kapatıyor, admin `yes` yaptıysa
dokunmuyor (bu makine gibi config'i zaten olan kurulumlara böyle ulaşıyor).

**Durum:** ✅ makinede doğrulandı (14 Eyl: scriptlet "TIMELINE_CREATE=no but snapper-timeline.timer is enabled … disabling it"; `is-enabled` → `disabled`)

---

## Bulgu 8 — DNS gizlilik yapılandırması yok; deploy yorumu eski 🟡 (karar)

**Kanıt:** `resolvectl status` → `Current DNS Server: 192.168.1.1` (router,
düz UDP), `-DNSOverTLS`, `DNSSEC=no`; `/etc/NetworkManager/conf.d/` yalnız
`99-maze-cloak.conf`; `/etc/systemd/resolved.conf.d/` boş.
deploy 5e yorumu: *"maze-hardening provides its own NetworkManager-based DNS
config instead"* — `maze-hardening` yalnızca `sysctl.d/99-maze-hardening.conf`
taşıyor. `git status`: `D airootfs/etc/NetworkManager/conf.d/dns-cloudflare.conf`
— dosya bu turda silinmiş, yorum güncellenmemiş.

**Karar gerektiriyor:** Varsayılan DNS ne olmalı?
- (a) Router/DHCP (şimdiki) — ISS her sorguyu görür.
- (b) `resolved` ile `DNSOverTLS=opportunistic` + Quad9/Cloudflare `DNS=` —
  deploy'un sildiği `dns-cloudflare.conf`'un yaptığı şey, muhtemelen bilerek
  kaldırıldı (`maze-cloak`/`entropy-shield` ile çakışma?).
- (c) `entropy-shield`'in DNSCrypt'ine bırak (opt-in).

En azından yorum düzeltilmeli; (b)/(c) seçilirse Bulgu 3'teki
`10-maze-privacy.conf` aynı dosyaya `DNSOverTLS=` satırı alabilir.

**Karar (bulundu):** `maze-hardening/PKGBUILD` başlığı zaten yazıyor: *"A global
DNS override — forcing all DNS through Cloudflare via [global-dns-domain-*]
overrode VPN/DHCP resolvers (DNS leaks) and broke Tor and split-DNS. DNS is
left to the connection / VPN / DHCP."* Yani (a) bilinçli; şifreli DNS isteyen
`entropy-shield`'in DNSCrypt'ini açar (c). Deploy 5e yorumu buna göre yeniden
yazıldı ve Bulgu 3'ün `zz-maze-privacy.conf`'una işaret ediyor. DoT'yi
varsayılan yapmak (b) ayrı bir tartışma; şimdilik hayır.

**Durum:** ✅ kapatıldı (karar belgelendi, yorum düzeltildi)

---

## Bulgu 9 — `paru-debug` kuruluyor ⚪

**Kanıt:** `pacman.log`: `pacman -U ... paru-2.1.0-2-x86_64.pkg.tar.zst
paru-debug-2.1.0-2-x86_64.pkg.tar.zst`; `pacman -Qq | grep -- -debug$` → `paru-debug`.

**Sebep:** `build_one()` makepkg çıktısındaki **tüm** `*.pkg.tar.zst`'leri
`-U` ile kuruyor; makepkg `OPTIONS+=(debug)` varsayılanıyla `-debug` alt
paketi de üretiyor.

**Düzeltme:** `build_one`'da `pacman -U` listesinden `*-debug-*.pkg.tar.zst`'i
ele; ya da build user için `~/.makepkg.conf`'a `OPTIONS=(!debug)`.

**Yapılan (11 Eyl):** `build_one`: `*-debug-*.pkg.tar.*` dosyaları `pacman -U`
listesinden atlanıyor.

**Durum:** ✅ kaynakta düzeltildi

---

## Bulgu 10 — Gerçek kullanıcı `kvm`/`wireshark` gruplarına eklenmiyor ⚪

**Kanıt:** `id berkkucukk` → `wheel maze entropy-shield users ...`; `kvm` ve
`wireshark` yok (gruplar mevcut).

**Sebep:** `setup-live-user.sh` canlı kullanıcıyı `libvirt kvm wireshark`'a
ekliyor; `deploy-to-target.sh` 3. adım gerçek kullanıcı için yalnız `maze` +
sysusers gruplarını ekliyor. `wireshark-qt` kurulu; grup olmadan capture için
root ister. `qemu`/`libvirt` sonradan kurulursa (`maze-install-vmware`, kullanıcı
kendisi) `kvm`/`libvirt` üyeliği de eksik kalır.

**Düzeltme:** deploy 3. adım döngüsüne `for grp in libvirt kvm wireshark; do
getent group ... && usermod -aG ...; done` (canlı hook'takiyle aynı).

**Yapılan (11 Eyl):** deploy 3. adım döngüsüne `wireshark kvm libvirt`
(grup varsa `gpasswd -a`).

**Durum:** ✅ kaynakta düzeltildi

---

## Bulgu 11 — archiso kalıntı dosyaları (zararsız) ⚪

Kurulu sistemde duran, hiçbir şey tarafından kullanılmayan releng dosyaları:

```
/etc/systemd/system/choose-mirror.service        (ConditionKernelCommandLine ile kapalı)
/etc/systemd/system/livecd-talk.service
/etc/systemd/system/livecd-alsa-unmuter.service
/usr/local/bin/choose-mirror
/usr/local/bin/Installation_guide
/usr/local/bin/livecd-sound
/usr/local/share/livecd-sound/
/root/.automated_script.sh
/root/.zlogin                                    (→ .automated_script.sh çağırır)
/etc/systemd/network/20-{ethernet,wlan,wwan}.network   (networkd kapalı, NM aktif)
/etc/systemd/system/systemd-networkd-wait-online.service.d/
/etc/xdg/reflector/reflector.conf                (reflector.timer bunu KULLANIYOR — kalsın)
/usr/share/grub/themes/maze                      (grub kaldırıldı; airootfs'ten silinebilir)
```

**Düzeltme:** deploy 2c-bis'e bir `rm -f` bloğu; `usr/share/grub/themes/maze`
doğrudan `airootfs`'ten silinsin. `/root/.zlogin`'i silerken root'un
`grml-zsh-config` deneyimi bozulmaz (yalnız automated_script'i çağırıyor).

**Yapılan (11 Eyl):** deploy'a 5a-bis bloğu: listedeki her şey (+ `*.wants`
symlink'leri, `/usr/local/share/livecd-sound`) siliniyor; `reflector.conf`
bilerek kalıyor. `airootfs/usr/share/grub/themes/maze` depodan silindi.

**Durum:** ✅ kaynakta düzeltildi

---

## Bulgu 12 — `plasma-meta → plasma-welcome` kırık bağımlılık ℹ️ (bilinen)

`pacman -Dk` → `error: missing 'plasma-welcome' dependency for 'plasma-meta'`.
deploy 2f `pacman -Rdd plasma-welcome` ile bilerek kaldırıyor. Sonuç: her
`pacman -S plasma-meta` (ya da `-Syu` sırasında plasma-meta güncellemesi)
plasma-welcome'ı **geri getirir**; skel'deki `Hidden=true` maskesi bunu
karşılıyor (bu makinede doğrulandı: `~/.config/autostart/org.kde.plasma.welcome.desktop`
`Hidden=true`). `pacman.conf`'taki `NoExtract = usr/lib/qt6/plugins/kf6/kded/kded_plasma_welcome.so`
da aynı amaçla. Tasarım gereği; `-Dk` çıktısı `maze-doctor`'da açıklanmalı.

**Durum:** tasarım gereği — `maze-doctor`'a açıklama eklenmesi ⬜

---

## Bulgu 13 — Kurulum chroot'unda `snap-pac` "fatal library error, lookup self" ℹ️

`pacman.log`'da yalnız 9 Eyl 19:31–19:36 (deploy'un `in_chroot pacman`
çağrıları) sırasında, her `05-snap-pac-pre`/`zz-snap-pac-post` hook'undan sonra.
`arch-chroot` içinde `snapper` kullanıcı çözümlemesi yapamıyor; o anda snapper
config'i de yok. Kurulum sonrası hiç tekrarlamadı. Zararsız; istenirse deploy
`in_chroot pacman ... --hookdir /dev/null`… **hayır** — diğer hook'lar lazım.
Alternatif: chroot'ta `SNAP_PAC_SKIP=y` ortam değişkeni (snap-pac bunu tanır).

**Yapılan (11 Eyl):** `in_chroot()` artık `arch-chroot … env SNAP_PAC_SKIP=y`;
AUR build kullanıcısının geçici sudoers'ına `Defaults env_keep += "SNAP_PAC_SKIP"`
(yoksa `sudo pacman -U` içinde kaybolurdu).

**Durum:** ✅ kaynakta düzeltildi

---

## Bulgu 14 — `ollama` modeli çekilmemiş ℹ️ (doğrulanacak)

`ollama list` boş; `maze-ai` `llama3.1` bekliyor. Eğer `maze-ai` ilk açılışta
modeli kendisi çekiyorsa sorun yok; çekmiyorsa `maze-welcome`/`maze-ai` ilk
çalıştırmada "model indiriliyor" adımı olmalı. Bu makinede maze-ai henüz
açılmadı; **uygulama açılıp bakılacak.**

**Durum:** ⬜ doğrulanacak

---

## Bulgu 15 — İlk boot tek seferlik hatalar ℹ️

- `freshclam: Update failed for database: daily — HTTP GET failed` (19:50, ağ
  henüz yok). Sonraki denemede başarılı; `/var/lib/clamav` dolu.
- `plasmashell: The backend got an unknown wallpaper provider type. Falling
  back to default` (ilk giriş). `maze-apply-wallpaper` autostart'ı sonra Maze
  duvar kâğıdını uyguladı; şimdi `Image=file:///usr/share/wallpapers/Maze/...`.
  Muhtemelen skel'deki `a2n.blur` (video wallpaper) plugin'i ilk oturumda
  henüz kayıtlı değil. Kozmetik.
- `sddm-helper: gkr-pam: unable to locate daemon control file` — auth
  aşamasında beklenen; keyring session'da açılıyor (`Locked=false` doğrulandı).
- `PM: Some devices failed to suspend, or early wake event detected` (21:14)
  — donanım; bir kez.

**Durum:** zararsız

---

## Prova — çekirdek güncelleme yolu GERÇEK bir yükseltmeyle kanıtlandı (14 Eyl 21:51)

`tools/exercise-installed-system.sh` (bu turda yazıldı; durumu değiştiren
testler) `linux-lts`'i yeniden kurmayı denedi, mirror'da yeni sürüm vardı:
**6.18.50-2 → 6.18.51-1**, yani prova gerçek bir çekirdek güncellemesine dönüştü.
76 saniyede, tek bir uyarı bile olmadan:

```
hook ran: 85-maze-kernel-install / zz-maze-secureboot / zzz-maze-boot-verify / snap-pac pre+post
DKMS: broadcom-wl 6.18.50 kaldırıldı, 6.18.51 için derlendi
LTS UKI yeniden üretildi (152 MB), .uname = 6.18.51-1-lts, MOK imzalı, initrd'de hooks/encrypt, wl.ko yok
recovery imajı yenilendi + imzalı, recovery shim bozulmamış, NVRAM girişi yerinde
birincil imaj: hâlâ 7.2.4-arch1-2, hâlâ doğrulanıyor (yalnız yeniden imzalandı), shim bozulmamış
maze-sb-sign eski 6.18.50 UKI'sini sildi ("removed stale UKI")
maze-sb-resign.path ayrıca tetiklendi (flock ile serileştirildi) — çakışma yok
boot-unsafe yok, maze-boot-check geçti, snapshot 20 → 22, ESP 2452 → 2436 MB
```

Servis dayanıklılığı: `maze-guardd`/`maze-cloak`/`maze-sentinel` restart →
üçü de geri geldi, soketler `root:maze 660`, MAC her iki arayüzde yeniden
rastgele, resolved restart sonrası mDNS/LLMNR kapalı, ağ kopmadı.

`lynis` hardening index **75**; 3 uyarı: reboot gerekli (yeni LTS — yalnız
kurtarma çekirdeği, birincil değişmedi), `127.0.0.53` cevap vermiyor (lynis'in
resolved stub'ını anlamaması), `wlan0` promiscuous (**maze-guard'ın paket
yakalaması — beklenen**).

Referans belgenin §9.1 "denenmemişler" listesinden **çekirdek güncelleme yolu**
artık çıkarılabilir. Bu prova sırasında iki yeni bulgu çıktı (17, 18).

---

## Bulgu 17 — `maze-boot-entries` hiçbir girişi doğrulayamıyor 🟠 (prova sırasında)

**Kanıt:**
```
  0002   Maze Linux (recovery kernel)       could not verify - kept
```
ESP `/boot`'ta bağlı, dosya `/boot/EFI/maze-recovery/BOOTX64.EFI` yerinde, root
ile koşuyor — yine de "could not verify".

**Sebep:** `path_file()` yalnız eski efibootmgr'nin `File(\EFI\...)` biçimini
tanıyor. efibootmgr ≥ 18 ham device path basıyor:
`HD(1,GPT,…)/\EFI\maze-recovery\BOOTX64.EFI` — `File(` yok → `_file` boş →
`target_exists` 2 döndürüyor → "could not verify".

**Etki:** Aracın tek işi (ölü Maze girişlerini bulmak) hiçbir güncel sistemde
çalışmıyordu; `--clean` asla bir şey silmiyordu. Güvenli yönde başarısız
("bakamadım"ı "ölü"ye saymama kuralı sayesinde) ama **işlevsiz**. Yedinci tur
bu aracı "gerçek kirli makinede koşturulmadı" diye işaretlemişti — işte sonucu.

**Yapılan:** `path_file` iki biçimi de kabul ediyor; `[)/]File(` ile `FvFile(`
karışması da önlendi. Üç biçim test edildi (yeni, eski, FvFile → boş).
`maze-secureboot` 1.2.0-15.

**Doğrulama:** paket kurulunca `sudo maze-boot-entries` → 0002 için
"could not verify" görünmemeli.

**Durum:** ✅ makinede doğrulandı (14 Eyl 22:04: `0002   Maze Linux (recovery kernel)   ok`)

---

## Bulgu 18 — ESP'de gevşek `vmlinuz-linux-lts` (16 MB), `maze-sb-sign` imzalıyor ⚪ (prova sırasında)

**Kanıt:** provadan sonra ESP listesinde `/boot/vmlinuz-linux-lts` (16 451 664
B) belirdi; hook çıktısında `maze-sb-sign: SIGNED /boot/vmlinuz-linux-lts`.

**Sebep:** mkinitcpio'nun `90-mkinitcpio-install.hook`'u preset boş olsa bile
`/usr/lib/modules/<kver>/vmlinuz`'u `/boot/vmlinuz-<pkgbase>` olarak kopyalıyor.
`layout=uki`'de bunu hiçbir şey boot etmiyor (BLS girişi yok). Kurulumdan gelen
`linux` için dosya yoktu (unpackfs, hook çalışmadı); ilk `linux` güncellemesinde
`/boot/vmlinuz-linux` da gelecek. ESP 3 GiB olduğu için bütçe sorunu değil,
ama her çekirdek güncellemesinde 16 MB yazma + gereksiz imza.

**Yapılan:** `maze-sb-sign` (1.2.0-15) `layout=uki` **ve** o ESP'de
`loader/entries/*.conf` yoksa `vmlinuz-*`'ı siliyor ("removed loose …");
başka her durumda eski davranış (imzala, dokunma).

**Durum:** ✅ makinede doğrulandı — 1.2.0-15 kurulur kurulmaz `maze-sb-resign.path`
kendiliğinden tetiklendi (self-heal kanıtı), journal: "removed loose
vmlinuz-linux-lts (unused with layout=uki)"; `/boot/vmlinuz-*` yok.

---

## Bulgu 19 — Firmware'de eski kurulumun MOK anahtarı 🟡 (makine hijyeni)

**Kanıt (`mokutil --list-enrolled`, Subject satırları):**
```
2 × CN=Maze Linux Secure Boot machine key      ← biri bu kurulum, biri 9 Eyl öncesi kurulumdan
1 × CN=Maze Linux Secure Boot                  ← canlı ISO'nun paylaşılan anahtarı
1 × Fedora Secure Boot CA (shim'in gömülü vendor CA'sı — MokListRT'de görünür, MOK değil)
```

**Neden önemli:** Eski anahtarın özel yarısı silinen diskle gitti; yine de bu
firmware onunla imzalı her şeyi çalıştırır. Tehdit düşük (anahtar kimsede yok),
ama "her kurulum kendi anahtarı" tasarımının amacı buydu. Canlı ISO anahtarı
da yalnız canlı ortamı açmak için gerekli; kalıcı olması gerekmez.

**Temizlik (elle, MokManager fiziksel onay ister):**
```sh
cd /tmp && sudo mokutil --export                # MOK-000N.der dosyaları
for f in MOK-*.der; do openssl x509 -inform der -in $f -noout -subject -fingerprint -sha256; done
openssl x509 -in /var/lib/maze-secureboot/MOK.crt -noout -fingerprint -sha256   # BU kalacak
sudo mokutil --delete MOK-000N.der              # eşleşmeyen "machine key" (ve istenirse ISO anahtarı)
# reboot → MokManager "Delete MOK" → onayla
```
Yeni ISO ile temiz makinede bu durum oluşmaz; yeniden kurulumlarda oluşur.
`deploy-to-target.sh` bunu otomatik yapamaz (silme fiziksel onay ister),
ama ENROLLMENT.txt'e bir not eklenebilir.

**Durum:** ⬜ elle temizlenecek

---

## Bulgu 20 — `firejail` kurulu ama kullanılmıyor; Maze uygulamalarına AppArmor profili yok 🟡 (karar)

`maze-meta` `firejail`'i "application sandbox" diye çekiyor; `/usr/local/bin`'de
`firecfg` symlink'i yok, Maze profili yok → hiçbir uygulama sandbox'ta
çalışmıyor. AppArmor: 170 profil yüklü (87 enforce) ama hepsi dağıtım
profilleri (`firefox`, `torbrowser`, …); `maze-guard`/`entropy-shield`/`qlam`/
`haze`/`hazedrop` için profil yok.

Seçenekler: (a) `firecfg`'yi yalnız seçili uygulamalar için (tarayıcı, ofis,
sohbet) `maze-control-center`'dan açılır yapmak; (b) bağımlılığı `maze-meta`'dan
çıkarmak; (c) öncelikle kendi kriptografisini yapan `haze`/`hazedrop` ve ağ
dinleyen `maze-guard` için AppArmor profilleri yazmak. (c) en değerlisi ama
en çok iş.

**Durum:** ⬜ karar bekliyor

---

## Bulgu 21 — `consolefont` hook'u, `FONT` yok ⚪

mkinitcpio çıktısı: `WARNING: consolefont: no font found in configuration`.
Calamares `initcpiocfg` `consolefont`'u ekliyor, `/etc/vconsole.conf`'ta
`FONT=` yok. Zararsız; `deploy-to-target.sh` HOOKS'tan `consolefont`'u
çıkarabilir ya da `FONT=ter-116n` (terminus-font ISO'da var) yazabilir.
`qat_6xxx` firmware uyarısı da zararsız (Intel QAT, bu makinede yok).

**Durum:** ⬜ kozmetik

---

## Bulgu 22 — İki farklı `maze-guard` ikilisi; istemci uygulamayı gölgeliyor 🟠

**Kanıt:**
```
/usr/bin/maze-guard        maze-guard 2.16.0-2   (Maze Guard — ağ güvenlik izleyici uygulaması)
/usr/local/bin/maze-guard  maze-tools 1.1.0-34   (maze-guardd broker'ının 1140 baytlık istemcisi)
PATH=…:/usr/local/bin:/usr/bin:…
$ maze-guard --version   →   ERR bad-command
```
Menü girişi (`maze-guard.desktop`, `Exec=/usr/bin/maze-guard`) çalışıyor;
terminalden, `mazelinux` CLI'dan ya da belgelerdeki "run `maze-guard`"
talimatından çalışmıyor. `MAZE-TAM-REFERANS.md` §4.2 çakışmayı "aynı isimde ama
farklı bir daemon" diye not etmiş, PATH sonucunu görmemiş.

**Yapılan:** istemci `maze-guardctl` oldu (`maze-tools` 1.1.0-35). Çağıranlar:
`maze-panic` (`maze-guardctl panic`), `maze-panic-restore` (`restore`),
`maze-killswitch` (`status`/`kill`), `maze-doctor`'un araç listesi, deploy'un
`copy_to_target` satırı, audit script. Eski dosya paket güncellemesiyle
pacman tarafından kaldırılır (uyumluluk shim'i bilerek yok — aynı adla
kalırsa gölgeleme sürer).

**Doğrulama:** `maze-guard --version` → Maze Guard'ın sürümü;
`maze-guardctl status` → guardd cevabı; `maze-killswitch status` çalışıyor.

**Durum:** ✅ kaynakta düzeltildi — 🔲 makinede doğrulanacak

---

## Bulgu 23 — `maze-doctor` root'suz "No active firewall detected" ⚪

`nft list ruleset` root ister; root'suz boş cevap "bakamadım" demek, "firewall
yok" değil. 1.1.0-35: root değilse ve `firewalld` aktifse
"firewalld active (rules not inspectable without root)" diyor.

**Durum:** ✅ kaynakta düzeltildi

---

## Bulgu 24 — `maze-ai --version` → 1.12.0, paket 1.17.0-1 ⚪

Uygulamanın kendi sürüm dizesi PKGBUILD ile birlikte artırılmamış. `Maze-AI`
deposunda düzeltilmeli (kozmetik; kullanıcı "güncel mi" sorusuna yanlış cevap alır).

**Durum:** ⬜ Maze-AI deposunda

---

## VM kurulum testi — yeni ISO'dan taze kurulum (14 Eyl 23:25, VMware, UEFI, SB kapalı, LUKS'suz)

`out/mazelinux-2026.09.14-x86_64.iso` (localrepo'daki 10 override paketle
derlendi; `build.sh` logu `logs/build-20260914-222429.log`, `test-boot.sh`
OVMF secboot ile 45 s'de masaüstü). VMware'de Calamares ile kuruldu, kurulu
sistemde `audit-installed-system.sh --deep`: **303 OK · 0 FAIL · 3 WARN**
(üçü VM tercihi: SB kapalı → MOK enroll yok; LUKS yok → `dm_crypt` uyarısı
script yanlış pozitifiydi, düzeltildi).

Yalnız `deploy-to-target.sh`'ta yaşayan düzeltmelerin ilk gerçek kanıtı:

| Bulgu | Taze kurulumda |
|---|---|
| 2 | skel'de installer pin'i yok (`installer launcher stripped from skel panel`); canlı ISO'da pin var (test-boot ekran görüntüsü) |
| 3 | `-LLMNR -mDNS`, passim/avahi masked |
| 4 | tek `Maze Linux` + recovery girişi; `Linux Boot Manager`/`Fallback` hiç yok |
| 5 | `calamares not installed`, orphan yok |
| 6 | 17 Maze paketi — `linux-chan-ai`/`sentinai` yok |
| 7 | `timeline snapshots off` |
| 9 | `paru-debug` yok |
| 10 | kullanıcı `wireshark` grubunda |
| 11 | tek bir archiso kalıntı satırı yok; `choose-mirror`/`livecd-*` "not-found" |
| 13 | pacman.log'da "fatal library error" yok |
| 1 | `wl` yüklü değil, Call Trace yok |

Boot 18.9 s, failed unit yok, keyring dolu, snapper ilk boot'ta kuruldu,
`/.snapshots` bağlandı, `maze-sb-resign`/`maze-boot-check` ilk boot'ta koştu.
MAZE-TAM-REFERANS §9.1 "root kilidi yalnız yeni ISO ile" → **kanıtlandı**
(`root is locked`). §9.4 "VM kurulum testi" → ilk kez yapıldı;
`tools/vm-install-test.sh` bunun için yazıldı.

VM'de `exercise`: `pacman -Sy` tüm mirror'larda "Could not resolve host" —
VM'in DNS'i o an ölüydü (kurulum 10 dk önce 200 MB AUR indirmişti), Maze
hatası değil; script artık preflight'ta DNS'i ayrıca kontrol ediyor. VM'de
`maze-cloak` NM drop-in yazmamış, `ens33` kalıcı MAC'te — VMware sanal NIC'te
davranış, `journalctl -u maze-cloak` ile bakılacak (⬜).

---

## Bulgu 26 — deploy, ISO'daki yeni paketi public'teki eskisine düşürüyor 🔴 (VM testinde)

**Kanıt:** ISO `localrepo`'dan `haze 2.11.2-1` ve `maze-cloak 1.2.1-2` taşıdı;
VM'e kurulan sistemde `haze 2.11.1-1`, `maze-cloak 1.2.1-1` (audit §12) —
public `[mazelinux]` sürümleri.

**Sebep:** `install_maze_repo_apps()` `pacman -S --noconfirm --needed
<DEFAULT_MAZE_APPS>` çalıştırıyor. `--needed` yalnız **birebir aynı** sürümü
atlar; kurulu sürüm depodakinden yeniyse pacman depodakini kurar = downgrade.
`unpackfs` zaten her uygulamayı hedefe koyduğu için bu adımın tek meşru işi
*eksik* olanı kurmaktı. `maze-tools`/`maze-secureboot` gibi paketler listede
olmadığı için etkilenmedi (o yüzden audit 0 FAIL verdi). Aynı desen
`setup_secure_boot()`'taki `pacman -S --needed maze-secureboot …`'ta da vardı
(keyring hazır olmadığı için rastlantıyla başarısız oluyordu) ve ilk-boot
yardımcısı `maze-aur-setup`'ta.

**Neden kritik:** Public depoya erişimi olmadan `localrepo` ile derlenen her ISO
— tam da bu turun doğrulama yolu — kurulumda sessizce eski paketlere düşüyordu;
audit bunu ancak sürüm karşılaştırmasıyla görebilirdi (VM'de kaynak ağacı yok).

**Yapılan:** üç yerde de yalnız `pacman -Qq` ile **kurulu olmayan** paketler
kuruluyor; kurulu olan "already on the target (sürüm) — left as shipped" diye
loglanıyor. `maze-installer` 2.0.0-23, `maze-aur-setup` (airootfs).

**Doğrulama:** yeni ISO'dan kurulumda `pacman -Q haze maze-cloak` → 2.11.2-1 /
1.2.1-2; deploy logunda "left as shipped" satırları.

**Durum:** ✅ kaynakta düzeltildi — 🔲 yeni ISO ile doğrulanacak

---

## Bulgu 27 — `maze-aur-setup` listesinde `linux-chan-ai`/`sentinai` 🟡

Bulgu 6 iki yerde düzeltilmişti (`DEFAULT_MAZE_APPS`, `packages.x86_64`
yorumu); ilk-boot yeniden deneme yardımcısı `airootfs/usr/share/maze/
target-firstboot/maze-aur-setup`'ın `MAZE_REPO_PKGS` listesi atlanmıştı.
Bulgu 26 düzeltmesiyle (eksikleri kur) bu liste taze kurulumda ikisini
**kurar** hâle gelecekti. Liste `DEFAULT_MAZE_APPS` ile hizalandı
(`maze-ai maze-connect maze-cloak` eklendi, ikisi çıkarıldı).

**Durum:** ✅ kaynakta düzeltildi

---

## Bulgu 25 — `maze-install-vmware` çöküyor: "Missing dependencies: vmware-keymaps" 🟡

**Kanıt (14 Eyl 22:54, gerçek makine):** `paru -S --needed vmware-workstation
open-vm-tools` → paru "Aur (1) vmware-workstation" listeliyor, makepkg
"Missing dependencies: -> vmware-keymaps" ile duruyor.

**Sebep:** AUR `vmware-workstation` PKGBUILD'i `vmware-keymaps`'i `depends`'e
çalışma zamanında bir `if [ -z "$_remove_vmware_keymaps_dependency" ]` ile
ekliyor. `.SRCINFO`/AUR RPC bunu görmüyor (RPC `Depends`: dkms, fuse2, gtkmm3,
… — keymaps yok), paru çözümlemeye almıyor, makepkg PKGBUILD'i değerlendirince
buluyor ve ölüyor. paru'nun bilinen kör noktası; aracın bunu bilmesi gerekir.

**Yapılan:** `maze-install-vmware` (1.1.0-36) önce `paru -S --needed
vmware-keymaps` çalıştırıyor, sonra `vmware-workstation open-vm-tools`.

**Durum:** ✅ kaynakta düzeltildi — 🔲 `maze-install-vmware` yeniden koşturulunca doğrulanacak

---

## Bulgu 16 — `airootfs/etc/modprobe.d/broadcom-wl.conf` ölü; `brcmfmac` kara listede 🟡 (yeni, Bulgu 1'i işlerken görüldü)

**Kanıt:** Arch'ın `broadcom-wl-dkms` paketi
`/usr/lib/modprobe.d/broadcom-wl-dkms.conf` ile `b43 b43legacy bcm43xx bcma
brcm80211 brcmfmac brcmsmac ssb`'yi kara listeye alıyor. releng'den miras
`airootfs/etc/modprobe.d/broadcom-wl.conf` bunu **iptal etmek** için var
(yorumu öyle diyor) ama dosya adı `broadcom-wl.conf` ≠ `broadcom-wl-dkms.conf`
→ hiçbir şeyi override etmiyor. Sonuç: in-tree `brcmfmac` (yeni Broadcom
çipleri — BCM4356/43602/4364…) **her Maze makinesinde kara listede**; `wl` bu
çipleri desteklemediği için o kartlarda WiFi yok.

**Neden bu turda çözülmedi:** `wl` ile `brcmfmac`'in kesişen/ayrık çip listeleri
ve gerçek Broadcom donanımı olmadan denenemez. Bulgu 1'in udev kuralı bu durumu
değiştirmiyor (Broadcom'lu makinede davranış bugünkünün aynısı).

**Öneri:** Ya (a) `broadcom-wl-dkms`'i ISO'dan çıkarıp `maze-gpu-driver`
benzeri bir `maze-wifi-driver` ile isteğe bağlı kurmak (in-tree sürücüler
varsayılan olur), ya da (b) airootfs dosyasını `broadcom-wl-dkms.conf` adıyla
boşaltıp udev kuralını `wl`'in desteklediği device-id'lerle sınırlamak.
Broadcom'lu bir test makinesi gerekir.

**Durum:** ⬜ açık — donanım bekliyor

---

## Doğrulanan ve TEMİZ çıkanlar (tekrar bakmaya gerek yok)

Boot zinciri: shim bayt bayt paket kopyası; `grubx64.efi` MOK ile doğrulanıyor,
`.uname` = çalışan çekirdek; UKI içi initrd `hooks/encrypt` + `hooks/plymouth`
+ maze teması taşıyor; her iki çekirdek (7.2.4 / 6.18.50-lts) için imzalı UKI;
`EFI/maze-recovery` LTS ile hazır ve NVRAM girişi var; MOK kayıtlı, SB açık;
`layout=uki`; `/etc/kernel/cmdline` ≡ `/proc/cmdline`; `loader.conf timeout 0
console-mode keep`; ESP 2.4 GB boş; boot-unsafe bayrağı yok; gölgeleyen `/etc`
kopyası yok.

Canlı kalıntı: 17 dosya silinmiş; hook sızıntısı yok; `maze` kullanıcısı ve
`/home/maze` yok; NOPASSWD yok; root `!` ile kilitli; `SULOGIN_FORCE` drop-in'leri
var; `maze-installer` paketi kaldırılmış.

Paketler: `maze-meta` bağımlılıkları tam; `packages.x86_64` (calamares hariç)
eksiksiz; sürümler kaynak ağaçtaki en yeni build ile aynı; 6 Maze paketi
kaynakla **bayt bayt** aynı; `[mazelinux]` var, `[maze-aur]` yok; keyring dolu,
Maze anahtarı var; curated AUR set (paru, onlyoffice, upscayl, session, joplin,
claude-code) tamam.

Servisler: beklenen 32 etkin (hepsi aktif ya da oneshot-done), 20 canlı-only
kapalı; failed unit yok; firewalld `kdeconnect maze-connect` açık; sysctl
profilinin 33 değeri canlı; AppArmor 170 profil; auditd kuralları yüklü.

Depolama: `@ @home @cache @log` + `/.snapshots` mount; `compress=zstd:1 noatime`;
snapper config + 16 snapshot; zram 38.8G; SMART ok; fstab `findmnt --verify`
temiz; LUKS `discards` ile açık.

Oturum: gnome-keyring tek `org.freedesktop.secrets` sahibi, login keyring
açık; `com.mazelinux.oled` L&F; panic plasmoid panelde; MAC rastgeleleştirme
iki arayüzde de gerçekten çalışıyor; `maze-cloak` durum dosyası yayınlıyor;
`guard.sock`/`maze.sock` `root:maze 660`; Tor 9050; NTP senkron; önceki boot
temiz kapanmış.

---

## Bu turda bakılanlar (14 Eyl, ikinci geçiş) ve hâlâ bakılmayanlar

Yapıldı:
- ✅ Çekirdek güncelleme yolu — gerçek yükseltmeyle (bkz. "Prova" bölümü).
- ✅ `maze-doctor --deep` (tüm sistem `-Qkk`: temiz), `lynis` (index 75).
- ✅ `tmpfiles.d`/`sysusers.d` bildirimleri tek tek (`--deep` §18): hepsi
  uygulanmış. `hazedrop` ve `maze-connect` hiç bildirim taşımıyor, yalnız
  `.install` — unpackfs kurulumda o scriptlet'ler çalışmadı (§5.3 borcu; bu
  ikisinin scriptlet'i ne yapıyor, ayrıca bakılmalı).
- ✅ Mühürlü initrd'nin içi: LUKS keyfile yok, özel anahtar yok, `encrypt` +
  `plymouth` + tema var, 70 modül, 766 firmware dosyası, 138 MB.
- ✅ LUKS başlığı: tek keyslot, argon2id, aes-xts-plain64 — Calamares'in
  `luksbootkeyfile` modülü keyfile bırakmamış (öksüz slot yok).
- ✅ ESP'nin tamamı listelendi; bilinen düzen dışında yalnız Bulgu 18.
- ✅ Servis restart dayanıklılığı (guardd/cloak/sentinel).

- ✅ **Suspend/resume** (14 Eyl 22:08, `exercise --suspend`): `PM: suspend entry
  (s2idle)` → 5 s sonra `suspend exit`; başarısız cihaz yok, GPU hatası yok,
  wlan0 geri bağlandı, failed unit yok, maze-cloak durumu korundu. Deploy'un
  sildiği `do-not-suspend.conf` gerçekten gitmiş — güç yönetimi kurulu sistemde
  çalışıyor. (s2idle bu ThinkPad'in tek modu: `/sys/power/mem_sleep` = `[s2idle]`.)

Hâlâ denenmedi:
- **Kurtarma çekirdeğiyle boot** — yeni LTS (6.18.51) imajı firmware menüsünden
  seçilip açılmadı (8 Eyl'de eski sürümle açılmıştı; imaj bu provada değişti).
- Maze GUI uygulamalarını açıp kullanma.
- ~~`hazedrop`/`maze-connect` `.install` içeriği vs. unpackfs~~ — bakıldı:
  `hazedrop.install` yalnız mesaj basıyor, `maze-connect.install` firewalld
  kuralı ekliyor ve deploy + `enable-services.sh` bunu zaten yedekliyor
  (audit: `firewalld allows maze-connect`). Bu ikisi için borç yok.

---

## Araç notu — `maze-audit` / `maze-exercise` (`maze-tools` ≥ 1.1.0-37)

14 Eyl gece: iki script `maze-tools` paketine `/usr/local/bin/maze-audit` ve
`/usr/local/bin/maze-exercise` olarak taşındı — her kurulu makinede ve bir
sonraki ISO'da hazır; VM testinde artık HTTP ile çekmeye gerek yok.
`MazeLinux/tools/{audit,exercise}-installed-system.sh` pakete symlink (tek
kopya). Kaynak ağacından çalıştırılınca `maze-audit` checkout'u kendisi bulur
ve 7/8. bölümlerdeki kaynak sapması + sürüm karşılaştırmasını da yapar;
kurulu makinede o iki bölüm atlanır. `maze-doctor` araç listesi ve README
güncellendi. Aşağıdaki not eski adlarla yazıldı, içerik aynı.

### (eski) `tools/audit-installed-system.sh`

Bu turda yazıldı. `maze-doctor` "makine sağlıklı mı" sorusunu cevaplar; bu
script "**bu kaynak ağacından üretilen ISO, deploy'un vaat ettiği durumu
bıraktı mı**" sorusunu. Her kontrol kaynakta bir yere bağlı (`packages.x86_64`,
`maze-meta`, `deploy-to-target.sh`, preset'ler, Calamares modülleri). Kaynak
ağacıyla bayt karşılaştırması ve sürüm karşılaştırması yapar. Yeni bir ISO'dan
her kurulumdan sonra koşturulmalı:

```sh
sudo ./tools/audit-installed-system.sh            # rapor: /var/tmp/maze-audit-<tarih>.txt
sudo ./tools/audit-installed-system.sh --skip-doctor --no-color
```

Bulgu 1, 3, 4, 5 için özel kontroller eklendi (wl/14e4, mDNS/LLMNR/avahi/passim,
fallback NVRAM girişi, calamares paketi). Düzeltmeler yapıldıkça bu script
yeşile dönmeli; dönmüyorsa ya düzeltme ya script eksik demektir.

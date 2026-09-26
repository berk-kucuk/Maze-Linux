# Maze Linux Wiki — Düzeltme Görevi

Kaynak: https://mazelinux.berkkucukk.com.tr/wiki (19 sayfa, `/wiki/<slug>.md` olarak servis ediliyor)
Doğrulama tarihi: 2026-09-22
Doğrulama yöntemi: her iddia `/run/media/berkkucukk/Backup/Projects/Maze-Linux-Source` altındaki kaynak ağaca karşı kontrol edildi.

Aşağıdaki her madde kaynaktaki kanıt dosyasıyla birlikte verilmiştir. "Doğrulanmadı" denmeyen her madde kaynakta teyit edilmiştir.

---

## P0 — Kullanıcıyı yanlış yönlendiren, yanlış bilgiler

### 1. `Installation.md` "Known Issues" bölümü tamamen ters (KRİTİK)

Sayfanın sonundaki blok, aynı sayfanın üst yarısıyla ve tüm wiki ile çelişiyor:

| Wiki'de yazan | Gerçek |
|---|---|
| "**Secure Boot is not supported.** Disable Secure Boot in your firmware settings before booting." | Secure Boot **destekleniyor ve varsayılan**. `SecureBoot.md`, `FirstBoot.md`, `FAQ.md` hepsi tam tersini söylüyor. |
| "**Btrfs subvolume layouts** are not supported in the installer. Use ext4 or XFS for root." | Aynı sayfa 60 satır yukarıda "Choose **btrfs** for the root partition" diyor. `maze-snapshots` btrfs'e bağımlı (`maze-snapshots/PKGBUILD`). |
| "UEFI Secure Boot — Maze does not ship signed bootloader binaries." | `packages.x86_64` içinde `shim-signed`, `sbsigntools`, `mokutil`; `maze-secureboot/.../maze-sb-sign` tüm zinciri imzalıyor. |

**Yapılacak:** Bu "Known Issues" bloğunun tamamı silinecek. Yerine gerçek bilinen sorunlar yazılacak (bkz. `Limitations.md` içeriğiyle hizalanmalı).

### 2. "Maze Guard = OpenSnitch" eşitlemesi yanlış

`Tools.md` ve `Security.md`, "Maze Guard (OpenSnitch)" başlığı altında ikisini aynı şey sanıyor. Bunlar **iki ayrı ürün**:

- **Maze Guard** — `maze-guard/README.md`: "Public WiFi Security Monitor — MITM detection · firewalld integration · Packet analysis", PyQt6 GUI + `maze-guardd.service`. Ağdaki saldırganı tespit eder.
- **OpenSnitch** — `packages.x86_64` içinde ayrı paket, `opensnitchd.service`. Uygulama bazlı giden bağlantı firewall'u.

`Home.md` doğru söylüyor ("Network attack detection"), `Limitations.md` da doğru. Sadece `Tools.md` + `Security.md` + `After-Install.md` + `FAQ.md` karışık.

**Yapılacak:** İkisi ayrı başlıklar altına bölünecek. `After-Install.md`'deki "**Maze Guard** will prompt you the first time any application tries to make a network connection" cümlesi OpenSnitch'e ait, düzeltilecek. `FAQ.md`'deki "Maze Guard keeps asking me about the same app" sorusu da OpenSnitch sorusu.

### 3. OpenSnitch varsayılan olarak **pasif** modda başlıyor — wiki bunu hiç söylemiyor

`deploy-to-target.sh:1830`:
> `# OpenSnitch: daemon always enabled but starts in allow-all (passive) mode.`
> `# GUI autostarts so user sees it in the tray; they can activate interception manually.`

Wiki ise (`Security.md`, `FAQ.md`, `After-Install.md`) "her bağlantıda soracak" diyor. Kullanıcı hiçbir prompt görmeyince "bozuk" sanacak.

**Yapılacak:** OpenSnitch bölümüne "varsayılan allow-all/passive; interception'ı tray'den manuel açarsınız" adımı eklenecek.

### 4. ClamAV "on-access scanning" iddiası yanlış

`Security.md`, `Tools.md`: "On-access scanning and scheduled definition updates are active from first boot."

`deploy-to-target.sh:1820` yalnızca şunu enable ediyor:
```
sec_selected clamav && in_chroot systemctl enable clamav-freshclam
```
`clamav-daemon` / `clamd` / `clamonacc` **hiçbir yerde enable edilmiyor**. Yani gerçekte sadece tanım güncellemeleri aktif, on-access tarama yok.

**Yapılacak:** "on-access scanning" iddiası kaldırılacak; "scheduled definition updates (freshclam) aktif, tarama on-demand (QLAM veya `clamscan`)" yazılacak.

### 5. MAC randomizasyonu bölümünün tamamı eski (`Privacy.md`, `Tools.md`, `FAQ.md`)

Wiki'nin anlattığı hiçbir şey artık yok:

| Wiki'de geçen | Durum |
|---|---|
| `macchanger` paketi | `packages.x86_64` içinde **yok** |
| `mac-changer.service` | **yok** |
| `change-mac-now` komutu | Kaynakta **hiçbir yerde yok** |
| `/var/log/mac-changer.log` | **yok** |
| `systemctl status mac-changer` (Privacy Checklist) | **yok** |

Gerçek: **Maze Cloak** (`maze-cloak.service`, maze-meta bağımlılığı). `maze-cloak/README.md`: üç katman (scan randomisation, connection randomisation, scheduled rotation), `ip link` ile daemon, `/etc/NetworkManager/conf.d/99-maze-cloak.conf` yazıyor, VPN-aware pause, 3 adres stratejisi (fully random / keep vendor prefix / random vendor prefix), tray-first PyQt6 arayüz.

**Yapılacak:** `Privacy.md`'nin "MAC Address Randomization" bölümü Maze Cloak'a göre baştan yazılacak. `Tools.md`'den `macchanger` ve `change-mac-now` girdileri silinecek, Maze Cloak girdisi genişletilecek. `FAQ.md`'deki MAC cevabı düzeltilecek.

> **Not — önce netleştirilmeli:** `deploy-to-target.sh:1823` yorumu "MAC randomization is owned exclusively by **maze-guard** now" diyor, ama `maze-meta` ve `maze-cloak/README.md` bunun **maze-cloak** olduğunu söylüyor. Wiki yazılmadan önce hangisinin sahip olduğu kaynakta netleştirilmeli.

### 6. DNSCrypt-proxy hiç kurulu değil ama "her boot'ta aktif" deniyor

`Home.md` ("Encrypted DNS / DNSCrypt-proxy" pre-enabled tablosunda), `Privacy.md` ("Active on every boot"), `After-Install.md` §9, `Tools.md` — hepsi `systemctl status dnscrypt-proxy` ve `/etc/dnscrypt-proxy/dnscrypt-proxy.toml` diyor.

Gerçek: `dnscrypt-proxy` **`packages.x86_64` içinde yok**, hiçbir service listesinde yok. Canlı ISO'da `systemd-resolved` enable. DNSCrypt sadece **Entropy Shield** üzerinden, o da kullanıcı başlattığında (`entropy-shield/README.md`: "Tor transparent proxy · DNSCrypt · I2P (i2pd) · Onion Server").

**Yapılacak:** "pre-enabled" tablolarından DNSCrypt satırı çıkarılacak veya "Entropy Shield ile birlikte, manuel" olarak işaretlenecek. `After-Install.md` §9 tamamen yeniden yazılacak. Aynı şey I2P için geçerli — `i2p`/`i2pd` de pakette yok.

### 7. Sanallaştırma bölümleri tamamen yanlış (`After-Install.md` §11, `Tools.md`, `AI-Dev.md`)

Üç sayfa da "QEMU, libvirt, virt-manager preinstalled; your user is already in the `libvirt` and `kvm` groups" diyor.

`deploy-to-target.sh:1725-1738` aynen şunu söylüyor:
> `# Virtualization is NOT set up at install time — by design, and no longer even attempted here.`
> `# Anyone who wants the KVM stack instead is one command away:`
> `#     sudo pacman -S qemu-desktop libvirt virt-manager edk2-ovmf`

`packages.x86_64` içinde `qemu-*`, `libvirt`, `virt-manager`, `edk2-ovmf` **yok**. Gruplar da yalnızca zaten varsa ekleniyor (`deploy-to-target.sh:1118`), yani kurulmamışsa kullanıcı o gruplarda değil.

Ayrıca `maze-install-vmware` (maze-tools) diye VMware Workstation kuran bir komut var — wiki'de **hiç geçmiyor**.

**Yapılacak:** Üç sayfadaki "preinstalled" iddiası kaldırılacak; `sudo pacman -S qemu-desktop libvirt virt-manager edk2-ovmf` ve `maze-install-vmware` yolları belgelenecek.

### 8. Kurulu olmayan uygulamalar "Installed & configured" diye listeleniyor

`packages.x86_64` (249 paket) + `maze-meta/PKGBUILD` + `deploy-to-target.sh` karşısında:

| Wiki'de "kurulu" denen | Gerçek |
|---|---|
| Brave | Pakette yok, localrepo'da build yok |
| Mullvad Browser | Pakette yok |
| Mullvad VPN | Pakette yok (`proton-vpn-gtk-app` var) |
| Spotify (`spotify-launcher`) | Pakette yok |
| ONLYOFFICE | ISO'da **kasten yok**, kurulum sırasında AUR'dan çekiliyor (ağ gerekir) |
| Node.js / npm | Pakette yok |
| Rust / rustup | Pakette yok |
| Go | Pakette yok |
| `paru` | ISO'da yok; kurulum sırasında kaynaktan derleniyor (ağ gerekir) |
| Oh My Zsh | `airootfs/etc/skel/.oh-my-zsh` var ✓ (bu doğru) |
| SentinAI, Linux Chan AI | `maze-meta` ve `deploy-to-target.sh:104` **kasten hariç** — ama `Tools.md` ve `AI-Dev.md` bunları kurulu gibi anlatıyor. `Limitations.md` doğru söylüyor. |

**Yapılacak:** `Tools.md`, `Privacy.md`, `AI-Dev.md` paket listeleri gerçek `packages.x86_64` + `maze-meta` depends'e göre yeniden üretilecek. Her girdi "ISO'da kurulu / kurulumda çekilir / `pacman -S` ile bir komut uzakta" diye etiketlenecek.

### 9. `FAQ.md` — "install completely offline" yanlış

"Do I need an internet connection to install? **No.**" deniyor. Ama `deploy-to-target.sh:76-92`, `paru` ve `onlyoffice-bin`'i her kurulumda AUR'dan çekiyor (paru kaynaktan derleniyor, onlyoffice ~350 MB indirme).

**Yapılacak:** "Çekirdek sistem offline kurulur; `paru` ve ONLYOFFICE kurulum sırasında ağ ister, ağ yoksa `maze-aur-setup` ile ilk boot sonrası tamamlanır" şeklinde düzeltilecek.

### 10. `FAQ.md` — `maze-aur` repo içeriği yanlış

Wiki: "maze-aur ... `entropy-shield`, `qlam`, `haze`, `hazedrop`, `linux-chan-ai`, `sentinai`, `brave-bin`, `mullvad-browser-bin`, `session-desktop-bin`, `joplin-bin`, `upscayl-bin`, `paru`".

Gerçek `MazeLinux/localrepo/` içeriği: `calamares`, `claude-code`, `joplin-bin`, `obfs4proxy`, `session-desktop-bin`, `shim-signed`, `upscayl-bin`. Hepsi bu.

Maze'in kendi uygulamaları (`entropy-shield`, `qlam`, `haze`, `hazedrop`, `maze-ai`, `maze-connect`, `maze-cloak`, `maze-guard`) **`[mazelinux]` repo'sundan** geliyor (`https://mazerepo.berkkucukk.com.tr/packages`, `pacman.conf`). `Updating.md` bunu doğru söylüyor — `FAQ.md` ile çelişiyor.

**Yapılacak:** `FAQ.md` girdisi iki repoyu ayıracak şekilde yeniden yazılacak.

### 11. Sürüm bilgileri 3 ay eski / yanlış

| Wiki | Gerçek |
|---|---|
| "Release 2026-06-21 'Labyrinth'" | Son ISO: `mazelinux-2026.09.22-x86_64.iso`. Sürümleme tarih tabanlı (`profiledef.sh`: `iso_version="$(date +%Y.%m.%d)"`), kaynakta "Labyrinth" kod adı **hiç geçmiyor**. |
| "Linux 6.9.8-arch1" | `work/x86_64/.../usr/lib/modules/`: **7.2.4-arch1-2** (mainline) + **6.18.51-1-lts** |
| "ISO size ~4.7 GB" | 4.852.051.968 bayt ≈ **4.85 GB / 4.52 GiB** |
| "Ollama 0.3 / 0.3.12" | Doğrulanmadı ama 0.3 çok eski; `pacman -Q ollama` ile teyit edilmeli |
| "KDE Plasma 6.7.0" | `plasma-meta` Arch'tan geliyor, pinlenmiş sürüm rolling'de çürür |
| AppArmor 3.1.7, firewalld 2.2.3, ClamAV 1.4.1, OpenSnitch 1.6, Tor 0.4.8.12 | Hepsi rolling repo'dan; sabit sürüm yazmak yanlış |

**Yapılacak:** Rolling release'de sabit sürüm numaraları yazılmayacak. Tek tarih kaynağı olarak ISO tarihi kullanılacak; kod adı ya kaynağa eklenecek ya wiki'den çıkarılacak.

---

## P1 — Eski / çelişkili içerik

### 12. GRUB referansları (sistemde GRUB yok)

`profiledef.sh`: `bootmodes=('uefi.systemd-boot')`, BIOS desteği kaldırılmış. Zincir: `shim → grubx64.efi` — ama bu dosya **GRUB değil**, shim'in ikinci aşama olarak beklediği isimle kurulan **imzalı UKI**'dir (`maze-sb-sign:93`: "grubx64.efi, the exact name shim chainloads"). `maze-sb-sign:252`: "there is no systemd-boot menu".

Düzeltilecek yerler:
- `Installation.md`: "Choose **Maze Linux** from the GRUB menu" → systemd-boot
- `Installation.md` Troubleshooting: "try the non-quiet boot entry in GRUB"
- `Security.md`: "The `apparmor` kernel parameter is added to the **GRUB command line**" → gerçekte UKI'ye gömülü cmdline: `lsm=landlock,lockdown,yama,integrity,apparmor,bpf apparmor=1 security=apparmor` (`efiboot/loader/entries/01-archiso-linux.conf`)
- `FAQ.md` dual-boot: "The Maze **GRUB** bootloader will detect Windows ... Note: disable Secure Boot first" → hem GRUB yanlış hem "Secure Boot kapat" wiki'nin geri kalanıyla çelişiyor
- `FAQ.md` karşılaştırma tablosu: "Maze OLED theme, splash, **GRUB**"
- `Installation.md`'deki NVIDIA tavsiyesi "edit the GRUB entry, add `nomodeset`" → UKI'de cmdline düzenleme farklı çalışır, doğru yordam yazılmalı

**Ayrıca eklenmeli:** `SecureBoot.md` zincir diyagramı `firmware → shim → systemd-boot → UKI` diyor, gerçekte systemd-boot menüsü yok; `firmware → shim → grubx64.efi (= imzalı UKI)`. Bu isimlendirme kafa karıştırıcı olduğu için wiki'de açıkça açıklanmalı (aksi halde kullanıcı `grubx64.efi` görüp GRUB sanıyor).

### 13. archinstall referansları (installer artık Calamares)

`Installation.md` ve `FAQ.md` iki yerde `cat /tmp/archinstall.log` diyor. Installer `calamares` (`packages.x86_64`, `localrepo/calamares-3.4.2-3`). Doğru log yolu kaynakta teyit edilip yazılmalı (Calamares tipik olarak `/var/log/Calamares.log` ve `~/.cache/calamares/session.log`).

`SecureBoot.md` "How it's built" bölümü de `airootfs/opt/maze-archinstall/archinstall/lib/installer.py` diyor — bu yol artık yok; gerçek yer `airootfs/usr/share/maze/install/deploy-to-target.sh`.

`Installation.md` "Unattended / Pre-seeded Install" bölümü `/etc/maze-installer/maze.json.example` diyor ve hemen altında "installer is now Calamares, check `maze-installer --help`" notu var — yani bölüm kendi kendini geçersiz kılıyor. Ya gerçek Calamares unattended yordamı yazılacak ya bölüm kaldırılacak.

### 14. `Security.md` sysctl tablosu — bir değer yanlış, yarısı eksik

Gerçek dosya: `/etc/sysctl.d/**99**-maze-hardening.conf` (wiki `maze-hardening.conf` diyor — `After-Install.md` "Key Directories" tablosunda da yanlış).

| Parametre | Wiki | Gerçek |
|---|---|---|
| `net.ipv4.conf.all.rp_filter` | **1** | **2** (loose mode — VPN/Tor uyumu için bilinçli tercih, `maze-hardening/README.md`) |

Tabloda hiç geçmeyen, gerçekte set edilenler: `dev.tty.ldisc_autoload=0`, `fs.protected_fifos=2`, `fs.protected_regular=2`, `net.ipv4.conf.default.*` karşılıkları, `net.ipv6.conf.{all,default}.accept_redirects=0`, `net.ipv6.conf.{all,default}.accept_source_route=0`, `net.ipv4.conf.{all,default}.secure_redirects=0`, `net.ipv4.icmp_ignore_bogus_error_responses=1`, `net.ipv4.conf.default.log_martians=1`.

### 15. Tor "manuel başlatılır" deniyor ama boot'ta enable

`Privacy.md` tablosu: "Tor daemon | Installed (**manual start**)" ve "`sudo systemctl start tor`" / "Enable tor at boot: `sudo systemctl enable tor`".

`deploy-to-target.sh:1745` kurulan sistemde `tor`'u enable ediyor; `enable-services.sh` canlı ISO'da da enable ediyor. Yani zaten açık.

### 16. `Privacy.md` Firefox iddiaları politikadan biraz sapıyor

`airootfs/etc/firefox/policies/policies.json` gerçeği:
- "Enhanced Tracking Protection (**Strict mode**)" → politika `EnableTrackingProtection.Value: true` (standart), strict değil
- "crash reporter disabled" → politikada ayrı bir crash reporter anahtarı yok
- "Firefox Suggest disabled" → politikada yok
- Wiki "hardened default **profile**" diyor; gerçekte enterprise **policies.json** (kullanıcı profili değil) — davranışı farklı, doğru terim kullanılmalı
- Politikada olup wiki'de olmayan: `OverrideFirstRunPage` ve `Homepage` Maze sitesine ayarlı, `DisableFirefoxAccounts: false`

### 17. `MazeConnect.md` yayında bozuk

- İçinde **`[SCREENSHOT: dashboard — place at /public/screenshots/...]`** gibi 4 adet doldurulmamış placeholder var, canlı sitede görünüyor
- Dosyanın sonunda kaçak bir **`</content>`** etiketi var
- APK indirme linki **`/maze-connect-apk/latest.apk` → HTTP 404** (kontrol edildi)

### 18. Bağlantı biçimi tutarsız

`VirtualMachine.md` mutlak yol kullanıyor (`/wiki/Installation`), diğer 18 sayfa göreli (`Installation`). Tek biçime getirilmeli.

### 19. `Kernels.md` — `maze-kernel-helper` kullanıcıya doğrudan veriliyor

`maze-kernel-helper` başlığındaki açıklama: "privileged backend for the Maze Kernel Switcher GUI ... The GUI never touches the system directly: it invokes this helper **through pkexec**". Wiki `sudo maze-kernel-helper set-default linux-lts` diyor. Teknik olarak çalışır ama önerilen yol GUI (`maze-kernel`). Wiki GUI'yi "Maze Kernel Switcher" diye anıyor ama çalıştırılabilir adı (`maze-kernel`) hiç yazmıyor.

---

## P2 — Eksik içerik (wiki'de hiç geçmeyen, sistemde olan şeyler)

### 20. Belgelenmemiş Maze araçları

`maze-tools/maze-tools/usr/local/bin/` içinde olup wiki'de **hiç geçmeyenler**:

| Komut | Ne olduğu (kaynak yorumundan) |
|---|---|
| `maze-panic` / `maze-panic-restore` | Panik butonu ve geri alma — **güvenlik odaklı dağıtım için en önemli eksik** |
| `maze-audit` | Denetim aracı |
| `maze-sentinel` / `maze-sentinel-setup` | Kurulu sistemde **enable ediliyor** (`deploy-to-target.sh:1747`), wiki'de yok. Dikkat: `sentinai` ile karıştırılmamalı |
| `maze-hardware` | Wiki sadece uygulama adı olarak anıyor, komut olarak değil |
| `maze-killswitch` | Kill switch CLI'ı |
| `maze-guardctl` / `maze-guardd` | Maze Guard CLI + daemon |
| `maze-gpu-driver` | GPU sürücü yardımcısı |
| `maze-install-vmware` | VMware Workstation kurar (madde 7) |
| `maze-flatpak-setup` | Flathub kurulumu (boot'ta enable) |
| `maze-power-saver` | Güç yönetimi |
| `maze-primary-screen` | Birincil ekran ayarı |
| `maze-exercise` | ? |
| `mazelinux` | Ana CLI giriş noktası |
| `maze-apply-wallpaper` | Duvar kağıdı |
| `maze-kernel` | Kernel Switcher GUI (madde 19) |
| `maze-enable-blackarch` | `FAQ.md`'de geçiyor ✓ ama `Tools.md`'de yok |

`maze-secureboot/usr/bin/` içinde belgelenmemişler: `maze-boot-notify`, `maze-boot-guard` (shutdown inhibitor — bozuk boot zinciriyle kapanmayı engelliyor, önemli davranış), `maze-initramfs-rebuild`, `maze-kernel-install-add`.

`maze-snapshots/usr/bin/`: `maze-snapshots-setup` belgelenmemiş.

### 21. Belgelenmemiş paketler (ISO'da var, wiki'de yok)

`steam` + `lib32-vulkan-*` (oyun desteği), `claude-code` (kurulumda da çekiliyor), `clamtk` (ikinci ClamAV GUI), `yakuake`, `konsole`, `irssi`, `mc`, `clonezilla`, `testdisk`, `ddrescue`, `fsarchiver`, `partclone`, `partimage`, `gpart` (kurtarma araç seti), `plymouth` (boot splash), `sequoia-sq`, `openpgp-card-tools`, `libfido2` (FIDO2/donanım anahtarı), `tpm2-tools` / `tpm2-tss` (TPM), `tesseract-data-tur` (Türkçe OCR), `onionshare` (`Privacy.md`'de var ✓, `Tools.md`'de kısmen).

### 22. Belgelenmemiş Maze uygulamaları

- **Maze AI** — `maze-meta` bağımlılığı, her kurulumda geliyor. `Maze-AI/README.md`: v1.12.0, PySide6 GUI, agentic (clipboard/dosya/dizin/shell history/ekran görüntüsü okuyan araçlar), **Türkçe native**, Ollama tabanlı. `Home.md` ve `Limitations.md` adını anıyor ama `Tools.md`/`AI-Dev.md`'de **girdisi yok** — oysa `linux-chan-ai` ve `sentinai` (kurulu olmayanlar) detaylıca anlatılıyor.
- **Said360** — artık `maze-meta` bağımlılığı değil (maze-meta 1.5.0-2), isteğe bağlı Plasma applet (`plasma6-applet-said360`). Wiki'de **sıfır** referans.
- **mazelinux-keyring** — paket imzalama anahtarlığı, `Updating.md`'deki GPG iddiasının dayanağı. Belgelenmemiş.
- **Firejail** — `maze-meta` bağımlılığı. `Limitations.md` "Firejail sandboxing" diye anıyor ama `Tools.md`'de girdisi yok, nasıl kullanılacağı hiç yazmıyor.
- **maze-connect** — `maze-meta` bağımlılığı, yani **varsayılan kurulu**. `MazeConnect.md` ise "install the `maze-connect` package" diyor, sanki opsiyonelmiş gibi. Ayrıca firewalld servisi TCP+UDP **38271** portunu açıyor (`deploy-to-target.sh`) — port bilgisi wiki'de yok.

### 23. Hiç sayfası olmayan konular

- **Türkçe / yerelleştirme** — Maze AI Türkçe native, Maze Cloak "English + Turkish with live switching", `tesseract-data-tur` kurulu. Wiki tamamen İngilizce ve çok dilliliğe hiç değinmiyor.
- **ISO'yu kendin derleme / katkı** — `build.sh`, `profiledef.sh`, `tools/gen-sb-keys.sh` var; `FAQ.md` "How do I contribute?" sadece "GitHub'da" diyor. Ayrı bir Building/Contributing sayfası gerekiyor.
- **LUKS / disk şifreleme** — birçok sayfa değiniyor, özel sayfa yok (parola değiştirme, keyfile, kurtarma).
- **Maze Guard'ın kendi sayfası** — dağıtımın imza ürünü, sadece bir paragrafı var.
- **Entropy Shield'ın kendi sayfası** — `entropy-shield/README.md`'de kill switch, onion server, izole Firefox profilleri, nftables IPv6 leak koruması gibi özellikler var; wiki'de tek satır + `--help`.
- **`[mazelinux]` deposu** — `Updating.md`'de bir paragraf; imzalama, anahtarlık, mirror bilgisi yok.

### 24. `os-release` hatası (wiki değil ama wiki'yi etkiliyor)

`airootfs/etc/os-release`:
```
DOCUMENTATION_URL="https://wiki.archlinux.org/"
BUG_REPORT_URL="https://mazelinux.berkkucukk.com.tr"
```
`DOCUMENTATION_URL` Maze wiki'sine değil Arch wiki'sine gidiyor. `BUG_REPORT_URL` da GitHub issues yerine ana siteye gidiyor, oysa wiki her yerde "open an issue on GitHub" diyor. Düzeltilmeli (kaynak tarafı).

---

## P3 — Teknik doğruluk detayları

### 25. `AI-Dev.md` — OpenAI API iddiası yanlış

"`http://localhost:11434` ... **Compatible with the OpenAI API format**" deyip hemen altında `/api/chat` örneği veriyor. `/api/chat` Ollama'nın **kendi** formatı. OpenAI uyumlu uç nokta `/v1/chat/completions`. İkisi ayrı ayrı gösterilmeli.

### 26. `AI-Dev.md` — `OLLAMA_GPU` diye bir değişken yok

```
OLLAMA_GPU=cuda ollama serve
OLLAMA_GPU=rocm ollama serve
```
Ollama'da böyle bir ortam değişkeni yok. Ayrıca `ollama.service` zaten çalışıyorken `ollama serve` çalıştırmak 11434 portunda çakışır. AMD için gerçek değişken `HSA_OVERRIDE_GFX_VERSION`. Bölüm doğru komutlarla yeniden yazılmalı.

### 27. `AI-Dev.md` / `After-Install.md` — Ollama sürümü ve model listesi eski

"Ollama 0.3.12", `llama3` / `codellama` / `phi3` / `mistral`. Sürüm ve model önerileri güncellenmeli (`pacman -Q ollama` ile gerçek sürüm alınmalı).

### 28. `Tools.md` — yanlış açıklamalar

- **sentinai**: "AI-assisted security monitoring tool" → gerçekte `maze-meta` yorumuna göre "PassGen/OSINT tooling aimed at authorised penetration testing", Gemini bulut yolu var. `Limitations.md` doğru, `Tools.md` yanlış.
- **linux-chan-ai**: "All inference runs locally via Ollama — **no data leaves your machine**" → `maze-meta` yorumu: "Linux Chan has **no offline mode at all**, and it reads files and screenshots for you — everything it sees goes to Google." **Tam ters.** Bu, gizlilik dağıtımında ciddi bir yanlış bilgi.
- İkisi de varsayılan **kurulu değil** — bu her iki girdide de belirtilmeli.

### 29. `Snapshots.md` / `Updating.md` — mekanizma eksik anlatılmış

Doğru (`maze-snapshots/PKGBUILD`: snapper + snap-pac bağımlı) ama:
- `maze-snapshots-setup.service` ilk boot'ta snapper config'i oluşturuyor — ilk boot'ta snapshot **henüz yok**, wiki bunu söylemiyor
- Kurulum sırasında `SNAP_PAC_SKIP=y` ile snapshot atlanıyor (`deploy-to-target.sh`)
- `btrfs-assistant` optdepend olarak geçiyor, `packages.x86_64`'te var ✓

### 30. `Diagnostics.md` sayılarının durumu

- `maze-doctor` "18 sections" → **doğru** (kaynakta 19 `section` çağrısı, biri "Summary")
- `maze-boot-check` "12 checks" → **doğrulanamadı**, kaynaktan gerçek sayı çıkarılıp yazılmalı veya sayı kaldırılmalı
- `maze-doctor --deep` ve `--no-color` bayrakları wiki'de yok, eklenmeli
- `maze-boot-check --quiet` ve `--no-flag` bayrakları yok, eklenmeli
- `maze-boot-check` başarısız olunca `/var/lib/maze/boot-unsafe` yazıyor ve `maze-boot-guard` **shutdown inhibitor** tutuyor — kullanıcının karşılaşacağı çok görünür bir davranış, wiki'de hiç yok

### 31. `Recovery.md` — teknik olarak doğru ama açıklamasız

Step 2'deki `cp /boot/EFI/BOOT/grubx64.efi.maze-prev /boot/EFI/BOOT/grubx64.efi` **kaynakta teyit edildi** (`maze-sb-sign:251`). Ama wiki hiçbir yerde `grubx64.efi`'nin aslında imzalı UKI olduğunu söylemiyor, dolayısıyla komut kullanıcıya anlamsız görünüyor. Kısa bir açıklama eklenmeli.

Recovery boot girdisinin adı `"Maze Linux (recovery kernel)"` — **doğru** (`maze-sb-sign:361`). Ayrı ESP dizininde (`EFI/maze-recovery`) kendi shim+mmx64 kopyasıyla tam bağımsız ikinci zincir olduğu belirtilebilir.

### 32. `SecureBoot.md` — MOK dosya adları

`maze-sb-sign`: `MOK.crt` (imzalama için, `/var/lib/maze-secureboot/`) ve `MOK.cer` (enrollment için, ESP kökünde `$ESP/MOK.cer`). Wiki hep `MOK.cer` diyor — enrollment bağlamında **doğru**. Ama `maze-boot-check` `MOK.crt` kullanıyor; ikisinin farkı bir cümleyle açıklanmalı.

"signs `systemd-boot` and the UKI" ifadesi düzeltilmeli — systemd-boot menüsü çalışma zamanında devrede değil.

---

## Önerilen çalışma sırası

1. **P0 #1** (`Installation.md` Known Issues) — tek başına en zararlı blok, hemen silinmeli
2. **P0 #2, #3, #4** — Maze Guard/OpenSnitch ayrımı + varsayılan davranışlar
3. **P0 #5, #6, #7, #8** — kurulu olmayan şeyleri "kurulu" diye anlatan tüm bölümler
4. **P0 #11 + P1 #12, #13** — sürüm/bootloader/installer temizliği (tüm sayfalara dokunur)
5. **P1 #14–19** — kalan çelişkiler
6. **P2 #20–23** — eksik sayfalar ve araç belgeleri
7. **P3 #25–32** — teknik detay düzeltmeleri

## Wiki yazılmadan önce kaynakta netleştirilmesi gerekenler

- MAC randomizasyonunun sahibi: `maze-guard` mı `maze-cloak` mı? (madde 5)
- Sürüm kod adı ("Labyrinth") kaynağa eklenecek mi, yoksa wiki'den çıkarılacak mı? (madde 11)
- `maze-connect-apk/latest.apk` yayına konacak mı, link kaldırılacak mı? (madde 17)
- `maze-exercise` ne yapıyor? (madde 20)
- `maze-boot-check` gerçek kontrol sayısı (madde 30)

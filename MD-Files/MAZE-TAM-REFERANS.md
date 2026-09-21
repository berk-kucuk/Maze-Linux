# Maze Linux — Tam Referans

**Son güncelleme:** 8 Eylül 2026

Bu belge Maze Linux'un **ne olduğunu, neyin nasıl çalıştığını ve nerede
eksik olduğunu** tek yerde toplar. Amacı övmek değil; bir yıl sonra bu depoya
bakan birinin (ya da bugünün geliştiricisinin) "burada ne var, neden böyle
yapılmış, nesi zayıf" sorularına kaynak koda dalmadan cevap bulabilmesi.

Diğer belgelerle ilişkisi:

| Belge | Kapsamı |
|---|---|
| **Bu belge** | Her şeyin haritası + dürüst eksik listesi |
| `ARCHITECTURE.md` | Mimari kararların gerekçeleri |
| `BOOT-DAYANIKLILIK.md` | Boot zincirinin derinlemesine anlatımı |
| `SNAPSHOT-BOOT.md` | Snapshot/rollback tasarımı ve sahada öğrenilenler |
| `CALAMARES.md` | Kurulum modülleri |
| `SECURITY.md` | Güvenlik duruşu |
| `CHANGELOG.md` | Ne zaman ne değişti |

---

## 1. Maze nedir

**Tez:** Günlük kullanılan, mahremiyeti azami tutan, kendini savunan ve
saldırıya uğradığında **saldırganı teşhis edebilen** bir masaüstü işletim
sistemi.

Hedef kitle siber güvenlik uzmanları *değil* — sıradan kullanıcı. Fark şurada:
ticari EDR'ler (CrowdStrike, SentinelOne) bir saldırıyı kime ait olduğuyla
birlikte raporlar ama kurumsaldır. Tüketici işletim sistemleri (Windows
Defender, macOS XProtect) korur ama **kullanıcıya atıf vermez** — "bir şey
engellendi" der, "şu cihaz, şu saatte, şunu yaptı" demez.

Maze'in doldurmaya çalıştığı boşluk bu.

Teknik temel: **Arch Linux**, `archiso` ile üretilen canlı ISO, **KDE Plasma
(Wayland)** masaüstü, **btrfs + LUKS** kök, **UEFI Secure Boot** zinciri.

---

## 2. archiso releng'den ne değişti

Maze, `archiso`'nun `releng` profilinden türetilmiştir. Farklar:

### 2.1 `profiledef.sh`

| Ayar | releng | Maze | Neden |
|---|---|---|---|
| `iso_name` | `archlinux` | `mazelinux` | — |
| `install_dir` | `arch` | `maze` | ISO içi yol |
| `cow_spacesize` | yok | `6G` | Canlı oturumda Calamares + venv'ler için yazılabilir alan |
| `bootmodes` | BIOS + UEFI çoklu | **yalnız** `uefi.systemd-boot` | BIOS boot desteklenmiyor; Secure Boot zinciri UEFI'ye bağlı |
| Sıkıştırma | zstd 15 | **zstd 22, 1M blok** | ISO boyutu; 250 paketlik bir sistem sığdırılıyor |

`file_permissions` blokuna Maze'e özgü beş giriş eklendi (canlı kullanıcı
kurulumu, duvar kâğıdı, servis etkinleştirme betikleri ve `sudoers.d/10-maze`).

### 2.2 `packages.x86_64`

Stock releng ~100 paket; Maze **250**. Eklenenler dört gruba ayrılır:

1. **Masaüstü** — KDE Plasma (Wayland), SDDM, Qt6/PySide6, ses/ağ yığını
2. **Güvenlik/gizlilik** — `tor`, `i2pd`, `dnscrypt-proxy`, `clamav`,
   `firejail`, `apparmor`, `nftables`, `usbguard`, `opensnitch`, `fail2ban`,
   `rkhunter`, `audit`
3. **Boot zinciri** — `sbsigntools`, `systemd-ukify`, `efibootmgr`, `shim`
   (AUR), `amd-ucode`, `intel-ucode`
4. **Maze'in kendi paketleri** — `[mazelinux]` deposundan çekilir

Kritik sıralama detayı: `mazelinux-keyring` listede **açıkça ve önce** yer alır,
yoksa `pacstrap` sırasında diğer `[mazelinux]` paketlerinin imzaları
doğrulanamaz.

### 2.3 `pacman.conf` — üç depo

```
[core] [extra] [multilib]     Arch resmî            SigLevel = Required DatabaseOptional
[maze-aur]                    yerel, build-time     SigLevel = Optional TrustAll
[mazelinux]                   Maze'in resmî deposu  SigLevel = Required DatabaseOptional
```

`[maze-aur]` yalnızca ISO derlerken var olur (`file://./localrepo`); kurulu
sisteme hiç geçmez. AUR'dan temiz chroot'ta derlenen paketleri taşır —
Microsoft imzalı `shim` dahil.

**`[mazelinux]` imza doğrulaması yapar.** Bu, `mazelinux-keyring` paketiyle
birlikte kapatılmış bir açıktır; `CHANGELOG.md` uzun süre bunu açık gibi
gösterdi, düzeltildi.

### 2.4 `airootfs` — canlı sistem katmanı

ISO'nun kök dosya sistemine eklenenler:

- **`etc/pacman.d/hooks/`** — ISO **derlenirken** çalışan altı hook:
  `0350` mirror açma, `0400` locale, `0500` os-release'i Maze yapma,
  `0600` canlı kullanıcı, `0700` duvar kâğıdı, `0800` servisler.
  `zzzz99-remove-custom-hooks-from-airootfs.hook` en sonda bu hook'ları
  airootfs'ten **siler** — yoksa kurulu sisteme sızarlardı.
- **`etc/kernel/install.conf`** — `layout=uki`. Boot zincirinin temeli.
- **`etc/mkinitcpio.conf.d/archiso.conf`** — canlı ortam initramfs ayarları.
  Kurulumda hedeften temizlenir (aksi hâlde kurulu sistem archiso hook'larıyla
  açılmaya çalışır).
- **`etc/maze/sentinel.conf`**, `etc/sddm.conf.d/`, `etc/plymouth/`,
  `etc/firefox/`, `etc/audit/`, `etc/fail2ban/`, `etc/opensnitchd/`,
  `etc/polkit-1/`, `etc/ssh/sshd_config.d/`, `etc/sudoers.d/10-maze`
- **`usr/local/share/maze/`** — canlı kullanıcı kurulumu, duvar kâğıdı,
  servis etkinleştirme betikleri

---

## 3. Boot zinciri

Maze'in en derin ve en riskli özelleştirmesi burasıdır. Sahibi
**`maze-secureboot`** paketidir.

### 3.1 Zincir

```
UEFI firmware
   │
   ├─ NVRAM girişi "Maze Linux"  ─────┐
   └─ (veya çıkarılabilir yol)        │
      \EFI\BOOT\BOOTX64.EFI  ─────────┤
                                      ▼
                            shim (Microsoft imzalı)
                                      │ MOK ile doğrular
                                      ▼
                    \EFI\BOOT\grubx64.efi   ← aslında bir UKI
                                      │
                                      ▼
                       çekirdek + initramfs + cmdline
                          (hepsi tek imzalı PE içinde)
```

**`grubx64.efi` bir GRUB değildir.** shim ikinci aşamayı sabit bu adla arar;
Maze oraya imzalanmış UKI'yi koyar. Dosya adı bir uyum gereğidir, yalan
söylüyor gibi görünmesi bilinçli bir maliyettir.

### 3.2 Neden UKI

Bir **Unified Kernel Image** çekirdeği, initramfs'i ve **komut satırını** tek
bir PE dosyasında mühürler ve imzalar. Kazanç:

- `apparmor=1`, `security=apparmor`, `lsm=...` boot ekranından silinemez
- `init=/bin/sh` eklenemez
- LUKS kökte initramfs de imzalıdır → parola yakalayıcı yerleştirilemez

Maliyet:

- Boot menüsü yok (cmdline düz metne inerse yukarıdaki her şey kaybolur)
- Her çekirdek güncellemesinde yeniden üretim + imzalama gerekir
- Her imaj ~90 MB → ESP bütçesi

### 3.3 `maze-secureboot` bileşenleri

| Dosya | İşi |
|---|---|
| `usr/bin/maze-sb-sign` | UKI'yi imzalar, `grubx64.efi` olarak kurar, kurtarma girişini üretir, ölü UKI'leri temizler |
| `usr/bin/maze-boot-check` | 12 kontrolle zinciri uçtan uca doğrular |
| `usr/bin/maze-boot-entries` | Firmware boot menüsündeki ölü/kopya Maze girişlerini temizler |
| `usr/bin/maze-boot-guard` | Zincir bozuksa kapanmayı gerekçeli olarak engeller |
| `usr/bin/maze-boot-notify` | Girişte kritik masaüstü bildirimi |
| `usr/bin/maze-kernel-install-add` | `kernel-install add` sarmalayıcısı |
| `usr/lib/kernel/install.d/95-maze-sb-sign.install` | `kernel-install` eklentisi |
| `85-maze-kernel-install.hook` | Çekirdek paketi değişince UKI üret |
| `zz-maze-secureboot.hook` | İşlem sonunda imzala |
| `zzz-maze-boot-verify.hook` | En sonda `maze-boot-check --quiet` |
| `maze-sb-resign.path/.service` | ESP'de yeni UKI belirirse kendiliğinden imzala |
| `maze-boot-check.timer` | Boot'tan 3 dk sonra, sonra günlük |
| `maze-boot-guard.path/.service` | Bayrak dosyası belirirse guard'ı başlat |
| `emergency/rescue .service.d/10-maze-sulogin.conf` | Acil kabuğu parolasız açılabilir yapar |

### 3.4 Çekirdek güncellemesinde ne olur

```
pacman -Syu linux
   │
   ├─ 85-maze-kernel-install.hook → kernel-install add <kver>
   │     └─ ukify → $ESP/EFI/Linux/<machine-id>-<kver>.efi   (UKI üretildi)
   │           └─ 95-maze-sb-sign.install → maze-sb-sign
   │
   ├─ zz-maze-secureboot.hook → maze-sb-sign
   │     ├─ hangi çekirdek boot edecek? (/etc/maze/kernel-default pini varsa o)
   │     ├─ o UKI'yi imzala → EFI/BOOT/grubx64.efi
   │     ├─ önceki sürümü grubx64.efi.maze-prev olarak sakla
   │     ├─ diğer çekirdek için EFI/maze-recovery/ hazırla
   │     └─ modülü olmayan çekirdeklerin UKI'lerini sil
   │
   └─ zzz-maze-boot-verify.hook → maze-boot-check --quiet
         └─ sorun varsa /var/lib/maze/boot-unsafe yaz
               └─ maze-boot-guard.path → kapanmayı engelle + bildirim
```

`maze-sb-sign` üç ayrı kaynaktan tetiklenebildiği için `flock` ile
serileştirilmiştir. Bu koruma olmadan iki eşzamanlı imzalama aynı geçici dosyaya
yazıp **%63 kesik bir UKI** ve boot'ta kernel panic üretmişti — üretimde
yaşanmış bir olay.

### 3.5 Kurtarma yolları

| Yol | Nasıl | Durum |
|---|---|---|
| **Kurtarma çekirdeği** | Firmware boot menüsü → *Maze Linux (recovery kernel)* → `EFI/maze-recovery/` altındaki ikinci shim + LTS UKI | ✅ **Gerçek donanımda denendi, LTS ile açıldı** |
| **`.maze-prev`** | `cp -f grubx64.efi.maze-prev grubx64.efi` | Çalışır, ama modülleri silinmiş bir çekirdeğe işaret edebilir |
| **Snapshot** | `maze-rollback <n>` | Dosya kurtarma çalışır; **boot rollback kanıtlanmadı** |
| **Acil kabuk** | Mount hatasında otomatik | Yeni, `SULOGIN_FORCE=1` ile |
| **Çıkarılabilir yol** | NVRAM silinse bile firmware `\EFI\BOOT\BOOTX64.EFI`'yi bulur | Çalışır |
| **Canlı USB** | Son çare | Çalışır |

---

## 4. Paket envanteri

### 4.1 Sistem paketleri

| Paket | Sürüm | İçerik | İşi |
|---|---|---|---|
| `maze-meta` | 1.5.0-1 | dosya yok | **Tek doğruluk kaynağı.** Varsayılan paket setini `depends` ile tanımlar |
| `maze-secureboot` | 1.2.0-10 | 22 dosya | Boot zinciri (bkz. bölüm 3) |
| `maze-snapshots` | 1.1.0-1 | 5 dosya | snapper + snap-pac + rollback araçları |
| `maze-tools` | 1.1.0-23 | 38 dosya | Kullanıcıya dönük araçlar ve teşhis |
| `maze-branding` | 1.5.0-2 | 70 dosya | Plymouth teması, logolar, os-release, SDDM teması |
| `maze-plasma-config` | 1.2.0-1 | 87 dosya | KDE varsayılanları, `/etc/skel` |
| `maze-hardening` | 1.0.0-3 | 1 dosya | `sysctl.d/99-maze-hardening.conf` |
| `mazelinux-keyring` | 20260720-1 | anahtar | `[mazelinux]` imza doğrulaması |
| `maze-installer` | 2.0.0-18 | 31 dosya | Calamares yapılandırması + `deploy-to-target.sh` |

**`maze-meta` neden önemli:** `pacman -Syu` yalnızca kurulu paketleri günceller;
yeni bir paket kendiliğinden kurulmaz. Yeni bir varsayılanı **kurulu tüm
makinelere** ulaştırmanın tek yolu onu `maze-meta`'nın bağımlılığına eklemek ve
`pkgrel`'i artırmaktır. `maze-installer` bilerek listede **yoktur** — canlı
ISO'ya özgüdür, kurulu masaüstüne inmemelidir.

### 4.2 `maze-tools` içeriği

Kullanıcıya dönük her araç burada:

| Araç | İşi |
|---|---|
| `maze-doctor` | 18 bölümlük sistem sağlık raporu (~860 satır) |
| `maze-control-center` | Merkezi ayar paneli |
| `maze-hardware` | Donanım kill switch arayüzü (kamera, mikrofon, BT, WiFi, USB) |
| `maze-killswitch` | Aynısının CLI'ı |
| `maze-guardd` | Kill switch'leri uygulayan ayrıcalıklı daemon (`/run/maze/guard.sock`) |
| `maze-panic` / `maze-panic-restore` | Ağı kes, geçmişi sil, oturumu kilitle |
| `maze-kernel` / `maze-kernel-helper` | Çekirdek değiştirici (pin mekanizması) |
| `maze-sentinel` | Sistem izleme servisi |
| `maze-welcome` | İlk açılış karşılama |
| `maze-gpu-driver` | NVIDIA sürücü kurulumu (imzalı DKMS) |
| `maze-flatpak-setup`, `maze-enable-blackarch`, `maze-install-vmware` | İsteğe bağlı kurulumlar |
| `maze-power-saver`, `maze-primary-screen`, `maze-apply-wallpaper` | Masaüstü yardımcıları |

**Kill switch mekanizması** (önemli, çünkü bir donanım arızasıyla karıştırılabilir):
- Kamera kapatma → `/etc/modprobe.d/maze-killswitch-camera.conf` yazılır
  (`blacklist uvcvideo`, `gspca_main`) + modüller kaldırılır. **Kalıcıdır.**
- Mikrofon → `wpctl`/`pactl` ile session katmanında susturma + `amixer nocap`.
  Yeniden başlatmada geri gelir.
- USB → `usbguard` politikası `ImplicitPolicyTarget=block`
- WiFi/BT → `rfkill block`

`maze-doctor` 1.1.0-23'ten itibaren kamera killswitch'ini ve mikrofon
susturmasını raporlar; cihaz hiç yoksa **Maze'in engellemediğini açıkça söyler**
ve BIOS/fiziksel sürgü/firmware'e yönlendirir.

### 4.3 Uygulamalar

| Uygulama | Ne yapar | Varsayılan kurulum |
|---|---|---|
| `maze-guard` | Ağ güvenlik izleyici: MITM, rogue AP/DHCP/RA, DNS spoof, SSL strip, port tarama tespiti + **saldırgan dosyaları** | ✅ |
| `maze-cloak` | MAC adresi rastgeleleştirme, zamanlanmış rotasyon, VPN farkında | ✅ |
| `entropy-shield` | Tor şeffaf proxy, DNSCrypt, I2P, onion servis yönetimi | ✅ |
| `qlam` | ClamAV arayüzü (antivirüs) | ✅ |
| `haze` | Tor üzerinden efemeral P2P grup sohbeti | ✅ |
| `hazedrop` | Tor üzerinden uçtan uca şifreli dosya transferi (ChaCha20-Poly1305, Argon2id) | ✅ |
| `maze-ai` | **Yerel** LLM asistanı (Ollama, `llama3.1`) — hiçbir veri makineden çıkmaz | ✅ |
| `maze-connect` | PC↔Android bağlantı | ✅ |
| `said360` | KDE plasmoid | ✅ |
| `sentinai` | OSINT + parola listesi üretimi (Gemini veya Ollama) | ❌ opsiyonel |
| `linux-chan-ai` | Anime karakterli asistan (**yalnızca Google Gemini**) | ❌ opsiyonel |

**`sentinai` ve `linux-chan-ai` neden varsayılan değil:** ikisi de Google
Gemini'ye veri gönderebiliyor, Linux Chan'ın çevrimdışı modu hiç yok ve dosya
okuyup gönderiyor. "Hiçbir şey makineden çıkmaz" diyen bir dağıtım bunları
sormadan kuramaz. `[mazelinux]` deposunda kalırlar, isteyen `pacman -S` ile
kurar; ikisi de bulut arka ucu seçildiğinde tek seferlik uyarı gösterir.

### 4.4 `maze-guard` iç yapısı

Tezi taşıyan paket bu, o yüzden ayrıntı hak ediyor.

```
maze/
  detection/   arp_watch, rogue_ap, dns_validator, ssl_strip, tls_monitor, anomaly
  protection/  firewall, block_log, port_scanner, process_map, dns_leak
  stealth/     hostname_hide, fingerprint, service_blocker
  core/        events, incident, device_intel, explain, inventory, posture, profile
  network/     identity, auto_profile
  helper.py    root daemon — paket yakalama + firewall (soket: /run/maze/maze.sock)
  gui/         PyQt6 arayüz (normal kullanıcı olarak çalışır)
```

**Paket yakalama:** `helper.py` dinlemeyi 10 dakikalık dilimler hâlinde yapar.
Dilim bitmesini beklemeden arayüz değişince çıkan bir `stop_filter` vardır, yani
link değişimine anında tepki verirken soketi seyrek yıkar. Bu 8 Eylül'de 60
saniyeden çıkarıldı: eski değer bir akşamda ~600 kez promiscuous moda girip
çıkmak demekti. Kablolu kartta yalnızca israf, ama USB WiFi adaptöründe
tehlike — yakalamayı yeniden ayağa kaldırmak, `rt2x00usb` gibi sürücülerin
ortadan kaybolan bir cihazı yanlış ele aldığı yoldur, ve harici adaptör bu
kitlede istisna değil normdur.

**Ayrıcalık ayrımı:** GUI normal kullanıcıdır, hiç parola sormaz. Ayrıcalıklı iş
`helper.py` daemon'ında yapılır; sokete erişim `maze` grubuyla kapılır. Yıkıcı
işlemler (korumaları kapatma) polkit ile onaylanır.

**`incident.py` — atıf katmanı.** Her düşman kaynak için kalıcı bir dosya:
MAC, üretici, hostname, tahmini OS, yaptığı her şey, ona karşı yürütülen keşif,
ve **Maze'in kendi müdahalelerinin denetim kaydı.** Ağırlıklandırılmış skorlama
(ARP spoof 45, rogue AP 40, DNS spoof 40, SSL strip 35, port tarama 25,
bilinmeyen süreç 3).

**`posture.py` — savunma duruşu.** Bir kaynak ilk kez düşmanlık ettiğinde o
andaki durum kaydedilir: MAC rastgele miydi, DNS şifreli miydi, Tor açık mıydı,
son zararlı taraması ne zamandı. Rapora *"Your defences at the time"* bölümü
olarak yazılır. Böylece dosya "bu cihaz sana saldırdı"dan **"saldırı anında
savunman şuydu"**ya çıkar.

Kural: **bilinmeyen `None`'dır, asla `False` değil.** Entropy Shield kurulu
olmayan bir makinede "DNS açıktaydı" demek, eksik bir dosya hakkında değil
kullanıcının koruması hakkında yanlış bir iddiadır.

### 4.5 Suite durum sözleşmesi

`/run/maze/status/<app>.json` — her Maze uygulaması küçük, düz bir JSON nesnesi
yayınlayabilir; okuyan yalnızca anladığı anahtarları alır.

Bugünkü durum: `maze-cloak` yayınlıyor, `maze-guard` okuyor. `entropy-shield` ve
`qlam` henüz yayınlamıyor — `maze-guard` onlar için mevcut artefaktlara
(resolved drop-in, Qlam geçmişi) düşüyor.

---

## 5. Kurulum

Calamares kullanılır. Modül sırası (`settings.conf`):

```
GÖSTER:  welcome → locale → keyboard → partition → users → summary

ÇALIŞTIR:
  partition          disk bölümleme
  mount              hedefi bağla
  unpackfs           canlı sistemi hedefe kopyala          ← kritik, bkz. aşağı
  shellprocess@mountapi   /dev /proc /sys /run bind
  machineid, locale, keyboard
  luksbootkeyfile    LUKS anahtar dosyası (parola bir kez sorulsun)
  fstab
  removeuser         unpackfs'in getirdiği canlı 'maze' kullanıcısını sil
  users              gerçek kullanıcıyı oluştur
  networkcfg, displaymanager, hwclock
  initcpiocfg, initcpio
  bootloader         systemd-boot + kernel-install (UKI)
  services-systemd
  shellprocess@mazedeploy  → deploy-to-target.sh   ← Maze'in tüm işi
  umount
```

### 5.1 `deploy-to-target.sh` — 2113 satır

Kurulumun Maze'e özgü her şeyi burada yapılır. Ana başlıklar:

1. Canlı ortam kalıntılarını temizle (archiso mkinitcpio ayarları, parolasız
   sudo, Calamares'in kendisi)
2. Kullanıcıyı `maze` grubuna ekle, kabuğu zsh yap, `~/.ssh` izinlerini düzelt
3. **Root hesabını kilitle** ve sonucu doğrula (bkz. 5.2)
4. NVIDIA sürücüsü varsa yapılandır (modeset + erken KMS)
5. `mkinitcpio` HOOKS'u düzenle (LUKS için `encrypt`, `plymouth`, `kms`)
6. Secure Boot: MOK anahtarı üret, shim'i kur, UKI'yi imzala, NVRAM girişi
   oluştur (ölü eski girişleri temizleyerek)
7. `[mazelinux]` deposunu hedefin `pacman.conf`'una yaz
8. Plymouth teması, duvar kâğıdı, varsayılan uygulamalar
9. `systemd-sysusers` + `systemd-tmpfiles --create` çalıştır
10. `pacman -Rns maze-installer` — kendini hedeften kaldır

### 5.2 Root hesabı

Canlı ISO root'u **parolasız** taşır (`root::`), Calamares
`setRootPassword: false` ile kuruludur ve `unpackfs` `/etc/shadow`'u olduğu gibi
kopyalar. Bu, uzun süre kurulu her sistemde TTY'den parolasız root girişi
demekti.

`deploy-to-target.sh` artık:
1. `passwd -l root` çalıştırır
2. Sonucu `passwd -S` ile **doğrular**
3. Alan hâlâ boşsa `/etc/shadow`'u doğrudan düzeltir (`root::` → `root:!:`)

Karşılığında `maze-secureboot`, `emergency.service` ve `rescue.service` için
`SULOGIN_FORCE=1` gönderir — kilitli root ile `sulogin` acil kabuğu reddeder,
yani insanın en çok kabuk istediği an kapı kapalı kalırdı.

Bunun Maze'de güvenli olmasının sebebi **mühürlü cmdline**:
`systemd.unit=emergency.target` boot ekranında eklenemez, çünkü eklenecek bir
satır yok ve imajı düzenlemek imzayı bozar. Acil moda ancak gerçek bir arıza ile
girilir.

### 5.3 Yapısal sorun: `unpackfs` ve scriptlet'ler

`unpackfs` canlı sistemin tamamını `/var/lib/pacman` **dahil** kopyalar. Sonuç:
hedefte `pacman -S --needed` her Maze paketini "zaten kurulu" görür ve
**hiçbir `.install` scriptlet'i hedefte çalışmaz.**

Bunun anlamı: her paketin ilk açılış işi `deploy-to-target.sh` içinde elle
tekrarlanmak zorunda. Kurulum zamanı hatalarının çoğu buradan çıktı.

Kısmi çözüm olarak bazı paketler işi **boot-time systemd birimlerine** taşıdı
(`maze-snapshots-setup.service` gibi) — bu yaklaşım çalışıyor ve yaygınlaştırılmalı.

---

## 6. Güncelleme ve dağıtım modeli

```
Geliştirme makinesi                    Kullanıcı makinesi
──────────────────                     ──────────────────
paket kaynağı düzenle
  │
  ├─ build.sh / build-pkg.sh
  │     └─ .pkg.tar.zst
  │
  └─ publish.sh  ──────────────────→   [mazelinux] deposu
        │  (bağımlılık sırasını             │
        │   topolojik çözer)                ▼
        │                             pacman -Syu
        └─ maze-meta EN SON              maze-meta güncellenir
           yayınlanmalı                     └─ yeni bağımlılıklar kurulur
```

**`publish.sh` neden topolojik sıralama yapar:** `maze-meta` diğer her Maze
paketine bağımlıdır. Önce o yayınlanırsa kurulu makinelerde bir sonraki
`pacman -Syu` "target not found" ile patlar. Sıralama artık kodun bir özelliği,
insanın hatırlaması gereken bir şey değil.

**Yeni ISO ne zaman gerekli:**

| Değişiklik türü | `pacman -Syu` ile ulaşır | Yeni ISO gerekir |
|---|---|---|
| Paket içeriği (araçlar, uygulamalar, boot zinciri) | ✅ | hayır |
| `maze-meta` bağımlılık listesi | ✅ | hayır |
| `deploy-to-target.sh` (kurulum davranışı) | ❌ | **evet** |
| `packages.x86_64`, `airootfs`, `profiledef.sh` | ❌ | **evet** |

---

## 7. Teşhis araçları

### 7.1 `maze-boot-check` — 12 kontrol

Her pacman işleminin **son** hook'u olarak çalışır, ayrıca boot'tan 3 dk sonra
ve günlük.

1. Kurulu çekirdekler
2. Her kurulu çekirdek için ESP'de UKI var mı
3. `grubx64.efi` var mı
4. Boot imajı kurulu bir çekirdeğe mi işaret ediyor
5. `grubx64.efi` gerçekten o çekirdeği mi taşıyor (PE `.uname` bölümü)
6. Makine MOK anahtarıyla imzalı mı
7. shim yerinde mi
8. Secure Boot açık ve anahtar kayıtlı mı
9. LUKS kökte `encrypt` hook'u initramfs'te mi
10. cmdline'daki her UUID gerçek bir cihaza mı çözülüyor
11. btrfs varsayılan subvolume çalışan kök mü (rollback için)
12. **Kurtarma girişi var, imzalı ve kurulu bir çekirdeğe mi bakıyor**

Ek: `layout=uki` hâlâ yürürlükte mi, ESP'de yer var mı, `/etc`'te paketlenmiş
dosyaları gölgeleyen kopya var mı.

Başarısızlıkta `/var/lib/maze/boot-unsafe` yazılır → `maze-boot-guard` kapanmayı
gerekçeli olarak engeller + kritik bildirim.

**9. kontrol özellikle değerli:** "açılır ama diskini açamaz" durumunun tek
uyarısıdır. Her katman ayrı ayrı başarılı rapor verirken makine parola kutusu
bile göstermeden takılır.

### 7.2 `maze-doctor` — 18 bölüm

Sistem, boot zinciri, çekirdekler ve DKMS, Maze paketleri, kimlik/marka,
cmdline ve initramfs, paket yöneticisi, canlı ortam kalıntısı, Maze araçları,
paket sistemi, depolama, dosya sistemi bütünlüğü, snapshot'lar, servisler,
güvenlik duruşu, journal'daki son sorunlar, donanım.

Kullanıcının sistemine güvenmek için çalıştırdığı araç budur.

### 7.3 `maze-doctor` — Stability bölümü

Diğer kontroller "bir şey bozuk mu" sorusunu cevaplar. Bu bölüm kullanıcının
makinesi tuhaf davrandığında gerçekten sorduğu soruyu cevaplar: **"bu Maze
miydi, yoksa donanım mı?"**

Yaptığı:
- Son 5 boot'un temiz kapanıp kapanmadığını tespit eder
- Temiz kapanmayan varsa, o boot'ta çekirdeğin **son yazdığı satırı** gösterir
- O satırı bir katmana sınıflandırır: DONANIM (USB kayboldu / disk cevap vermedi
  / aşırı ısınma), YAZILIM (bellek tükendi), EKRAN KARTI SÜRÜCÜSÜ, ÇEKİRDEK
- Kanıt yetersizse **tahmin etmez**, "belirsiz" der
- Ayrıca: 7 gündeki USB kopmaları ve termal olaylar

Gerçek bir örnek — 7 Eylül'deki donma:

```
[WARN]  1 of the last 5 boots ended without a clean shutdown
        last kernel message before it: rt2x00usb_vendor_request: Error ... -19
        looks like HARDWARE - a USB device vanished while in use
        nothing in Maze causes this
```

Bunun var olma sebebi: bu sistemin yaşadığı **her** çökme donanımdı (kendi
kendine kopan USB WiFi adaptörü, tamir sonrası takılmamış panel kablosu, kutuda
gevşemiş SSD) ve her biri saatlerce yanlış yerde arattı. Sağlam olduğu hâlde
kırılgan hissettiren şey buydu.

**Tespit ederken iki yanlış desen denendi**, ikisi de kayda geçti:
`Reached target Power-Off` journal'a hiç ulaşmıyor (journald ondan önce
durur) — her temiz kapanış çökme sanıldı. `Deactivated successfully` ise normal
oturum kapanışlarına da uyuyor — gerçekten donmuş bir boot temiz sanıldı. Doğru
imza yalnızca dosya sistemi sökme ve hedef durdurma satırlarıdır.

### 7.4 `maze-boot-entries`

Firmware boot menüsündeki ölü ve kopya Maze girişlerini temizler.

Güvenlik kuralları:
- Maze dışı girişlere (Windows, firmware setup, ağ boot) **dokunmaz**
- Açılışta kullanılan girişi (`BootCurrent`) silmez
- Son Maze girişini silmez, ölü görünse bile
- Silmeden önce durumu `/var/lib/maze/efi-entries.before` dosyasına yazar;
  **yazamazsa hiç silmez**
- "Ölü" kararını tahminle değil **takip ederek** verir: bölüm var mı ve
  üzerinde o dosya var mı. Bakılamıyorsa (bağlı değil, root değil) **korur** —
  "bakamadım"ı "ölü"ye saymak ikinci bir kurulumun girişini silmenin yoludur

---

## 8. Kurtarma senaryoları — uçtan uca

| Senaryo | Ne olur | Kullanıcı ne yapar |
|---|---|---|
| Bozuk kütüphane, yarım güncelleme | Sistem açılır ama uygulamalar çalışmaz | `maze-rollback <n>` |
| Yeni çekirdek açılmıyor | — | F12 → *Maze Linux (recovery kernel)* |
| Yeni çekirdek açılıyor ama modülsüz | wifi/GPU yok | `.maze-prev` geri yükle veya LTS'e geç |
| Boot zinciri bozuk, henüz kapatılmadı | Guard kapanmayı engeller + bildirim | `sudo maze-boot-check --repair` |
| fstab hatası, mount başarısız | Acil kabuk açılır (parolasız) | Elle onar |
| NVRAM silindi | Firmware `\EFI\BOOT\BOOTX64.EFI`'yi bulur | Bir şey yapmaz |
| Dosya yanlışlıkla silindi | — | Snapper ile dosya düzeyinde geri alma |
| Hiçbiri işe yaramaz | — | Canlı USB + chroot |

---

## 9. Bilinen eksikler

Bu bölüm belgenin asıl sebebidir. Sıralama önem sırasına göredir.

### 9.1 Yeni işin bir kısmı hâlâ denenmedi

**Kurtarma çekirdeği artık kanıtlandı** — firmware boot menüsünden seçildi ve
LTS çekirdeğiyle açıldı (8 Eylül 2026). Bugüne kadarki en büyük kanıtlanmamış
iddia buydu ve tuttu.

Hâlâ denenmemiş olanlar:
- **Root kilidi** — yalnızca yeni bir ISO ile yapılan kurulumda çalışır
- **`maze-boot-entries --clean`** — gerçek bir kirli makinede koşturulmadı
- **`/.snapshots` fstab girdisi** — rollback boot'u çalışmadığı için sınanamadı

Bu belgede "çalışır" yazan diğer yeni özellikler "yazıldı ve birim testlerinden
geçti" anlamına gelir. Profesyonellik bir özellik listesi değil, *"çalıştığını
biliyoruz çünkü denedik"* cümlesini kurabilmektir.

### 9.2 Otomatik kurtarma yok

Kurtarma çekirdeği artık seçilebiliyor ama **seçen bir insan olmak zorunda.**
Sıradan kullanıcı, açılmayan bir makinede boot menüsüne girip doğru satırı
seçemez.

Gereken: **boot counting.** İmaj üç kez açılmayı dener, `boot-complete.target`'a
ulaşamazsa kendiliğinden bir öncekine döner. Bu, zincire systemd-boot'un
girmesini gerektiriyor (`shim → systemd-boot → UKI`). systemd-boot bilerek
çıkarılmıştı: katı firmware'ler (MSI/ASUS) gevşek çekirdek için MOK'u yok
sayıyor. Geri koymak OVMF secboot'ta **ve** gerçek donanımda test gerektirir.

### 9.3 Rollback'ten boot etmek kanıtlanmadı

`maze-enable-rollback --apply` gerçek donanımda çalıştı — makine
`rootflags=subvol=` olmadan açıldı, btrfs varsayılanından kök bağlandı, cmdline
mühürlü kaldı. **Ama** `snapper --ambit classic rollback 7` varsayılanı snapshot'a
çevirdiği hâlde makine yine `@` ile açıldı.

Sebebi bilinmiyor. Ayırt edici veri: o reboot'tan sonraki
`btrfs subvolume get-default /` çıktısı. 270 ise boot varsayılanı yok saymış,
256 ise dışarıdan bir şey sıfırlamış.

Bu çözülmeden Faz A kurulum varsayılanı yapılmayacak.

### 9.4 VM kurulum/yükseltme testi yok

En yüksek getirili tek yatırım. Kurulu bir imaj → `pacman -Syu` → reboot →
`maze-doctor` döngüsünü otomatikleştirmek.

Gerekçesi ampirik: bu projede **her** gerçek hata gerçek çalıştırmadan çıktı,
statik incelemeden bir tane bile çıkmadı.

### 9.5 `unpackfs` scriptlet borcu

Bölüm 5.3'te anlatıldı. Yapısal kırılganlık; kurulum zamanı hatalarının
kaynağı. Kalıcı çözüm iki yoldan biri:
- Kurulumdan sonra hedefte Maze paketlerini gerçekten yeniden kurmak
- Her paketin ilk açılış işini boot-time birimlere taşımak
  (`maze-snapshots-setup` bu yaklaşımın çalışan örneği)

### 9.6 Test kapsamı çok dengesiz

| Paket | Test dosyası | Not |
|---|---|---|
| `maze-guard` | 13 | 285 test, iyi kapsanmış |
| `maze-cloak` | 2 | 48 test |
| `maze-ai` | 21 | — |
| **`entropy-shield`** | **0** | Tor/DNSCrypt/I2P yönetiyor |
| **`haze`** | **0** | **kendi kriptografisini yapıyor** |
| **`hazedrop`** | **0** | **ChaCha20-Poly1305, Argon2id** |
| **`qlam`** | 0 | — |
| **`maze-tools`** | 0 | `maze-doctor` 860 satır |
| `sentinai`, `linux-chan-ai` | 0 | — |

En rahatsız edici ikisi `haze` ve `hazedrop`: bir güvenlik dağıtımında sıfır
testli şifreleme kodu, doğrulanmamış en riskli yüzeydir. Kripto tam olarak
"gözle bakınca doğru görünen ama sessizce yanlış olan" kod türüdür.

`maze-tools` da önemli: `maze-doctor` kullanıcının sistemine güvenmek için
çalıştırdığı araç ve tek oturumda üç hata çıkardı.

### 9.7 Çalışan CI yok

`maze-secureboot/.github/workflows/lint.yml` var ama o klasörün `.git`'i yok —
dosya hiç çalışmadı. `MazeLinux/` içindekiler statik lint.

Bu oturumda çıkan hataların çoğu `shellcheck` + `unittest` ile otuz saniyede
yakalanırdı.

### 9.8 Test suite yük altında kırılgan

8 Eylül'de bulundu: makine meşgulken `maze-guard` suite'inde 15 test kalıyor,
makine boştayken hepsi geçiyor (285/285, 8.3s). Testler yük altında 13.3s'ye
çıkıyor ve zamanlamaya duyarlı olanlar düşüyor.

Yani suite yeşil olduğunda bile "kod doğru" demiyor — "makine boştu" da diyor
olabilir. CI kurulduğunda bu ilk düzeltilmesi gerekenlerden.

### 9.9 Üç paketin git deposu yok

`maze-tools`, `maze-secureboot`, `maze-snapshots` — yani **boot'a ve sistem
sağlığına karar veren üç paket.** Diğer on bir pakette depo var.

Sonuç: geçmiş yok, diff yok, "bu ne zaman bozuldu" sorusuna cevap yok.

### 9.10 `.maze-prev` modül uyumsuzluğu

Çekirdek güncellemesinden sonra `.maze-prev` artık kurulu olmayan bir çekirdeğin
UKI'sini tutar. Geri yüklenirse modülsüz bir sisteme açılır (wifi/GPU yok).

Kurtarma girişi geldiğine göre önemi azaldı — gerçek kurtarma yolu artık LTS.
Ama `maze-boot-check` bunu ayrıca uyarabilir.

### 9.11 Suite sözleşmesi yarı benimsenmiş

`entropy-shield` ve `qlam` `/run/maze/status/` altına yayın yapmıyor.
`maze-guard` onlar için artefakt sezgisine düşüyor — çalışıyor ama kırılgan.

### 9.12 Küçük ama not düşülmeye değer

- **`grubx64.efi` bir UKI.** Çalışıyor ama ESP'ye bakan biri GRUB sanıyor.
  Menüsüzlüğün ve `.maze-prev` mekanizmasının kaynağı bu tercih.
- **DKMS modülleri imzasız.** Arch çekirdeği lockdown'ı zorlamadığı sürece
  zararsız.
- **`maze-plasma-config` skel dosyaları** kurulumda `sed` ile düzenleniyor, yani
  paket güncellenince değişiklikler kayboluyor. Yalnızca sonradan oluşturulan
  kullanıcıları etkiler.

---

## 10. Gerçek hatalardan çıkan dersler

Bunlar teorik değil; hepsi bu projede yaşandı ve hepsi **çalıştırma** ile
bulundu.

**Statik inceleme kurulum zamanı hatalarını yakalamaz.** `verify-iso.sh` ve
`test-boot.sh` yeşilken kurulum çöktü, `maze-cloak` başlamadı, çekirdek
güncellemesi yarım kaldı. Tek çare gerçek koşum.

**İmzalanmış kopya ile orijinali bayt bayt karşılaştırmayın.** `grubx64.efi`,
UKI'nin `sbsign` çıktısıdır; farklı olmaları normaldir. Doğru karşılaştırma PE
`.uname` bölümüdür.

**`enable` başlatmaz.** Birimler etkin ama pasif kalmıştı; guard ve timer tam
ihtiyaç duyulan anda ölüydü. `preset`/`enable` yanına `start` gerekir.

**ISO'ya durum sızar.** `boot-unsafe` bayrağı squashfs'e girmişti — her taze
kurulum kapanmayı reddedecekti. Canlı ortamda oluşan hiçbir çalışma-zamanı
dosyası ISO'ya girmemeli.

**Fonksiyon adları gerçek komutları gölgeler.** `head()` `| head -N`'i bozdu,
`info()` çıktının ortasına `info: No menu item ...` bastı. Kabuk betiğinde
yardımcı fonksiyon adlarını PATH'teki komutlarla çakıştırmayın.

**Kabuk yönlendirme hatası yutulabilir.** `if ! { ...; } > dosya` yapısı,
dosya açılamasa bile başarı bildiriyor. Sonucu çıkış koduna değil, dosyayı geri
okuyarak doğrulayın.

**`/etc` kopyaları paketi gölgeler.** `/etc/pacman.d/hooks/` içindeki aynı
adlı dosya `/usr/share/libalpm/hooks/` içindekini sessizce iptal eder. Eski
kurulumların devralınmasında en sinsi tuzak buydu.

**Öksüz GID'ler sessizce kırar.** `removeuser` canlı kullanıcının birincil
grubunu sildi, `systemd-sysusers` `maze` grubunu farklı bir GID'le yeniden
yarattı, `config.json` sayısal bir GID'e ait kaldı. `tmpfiles.d` yalnız dizini
kapsıyordu, dosyayı değil.

**Donanımı yazılım sanmayın.** Saatlerce dosya sistemi bozulması kovalandı;
sebep USB kutusunda gevşemiş bir SSD'ydi. Aynı sınıf: bugün "kamera çalışmıyor"
diye bakılan şey takılmamış bir panel kablosuydu, ve "işletim sistemi dondu"
diye bakılan şey kendi kendine kopan bir USB WiFi dongle'ıydı.

Ortak ders: **okumalar güvenilir değilken yıkıcı işlem yapmayın.** `fsck -y`
o gün çalıştırılmadığı için veri kaybı olmadı.

---

## 11. Sıradaki işler

Öncelik sırasına göre:

1. **Bugün yazılanları gerçek donanımda dene** — özellikle kurtarma boot girişi
2. **Rollback boot sorununu teşhis et** (bölüm 9.3)
3. **VM kurulum/yükseltme testi** (bölüm 9.4)
4. **Üç pakete git deposu** (bölüm 9.9)
5. **CI: `shellcheck` + `unittest`** (bölüm 9.7), yük altındaki kırılganlığı
   düzelterek
6. **`haze` ve `hazedrop`'a kripto testleri** (bölüm 9.6)
7. **Boot counting** — otomatik kurtarma (bölüm 9.2)
8. **`unpackfs` borcu** (bölüm 9.5)
9. **Suite sözleşmesini tamamla** (bölüm 9.11)

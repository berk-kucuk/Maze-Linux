# Maze Linux — Mimari: ISO Derlemesi ↔ Installer

İki bileşenin nasıl birbirine bağlandığı, hangi parametrelerle çalıştığı ve
canlı ISO ile kurulan sistemin nerede ayrıştığı.

- **`MazeLinux/`** — archiso profili + `build.sh`. Canlı ISO'yu üretir.
- **`maze-installer`** — Calamares yapılandırması + iki kabuk scripti. Canlı
  sistemi kalıcı bir kuruluma dönüştürür. ISO'ya bir pacman paketi olarak biner.

Bağlantı noktası tek: `packages.x86_64` içinde `maze-installer` var, dolayısıyla
paket airootfs'e kurulur ve `/etc/calamares/*` ile `/usr/share/maze/install/*`
canlı ortamda hazır bulunur.

---

## 1. ISO Derlemesi

### 1.1 Araç zinciri

`build.sh` (root gerektirir) → `mkarchiso`. Ama düz bir sarmalayıcı değil:
**çalışma anında `mkarchiso`'nun bir kopyasını awk ile yamalar** ve içine
`_maze_sb_sign_esp()` fonksiyonunu enjekte eder.

| Yama | Amaç |
|---|---|
| `_make_bootmode_uefi.systemd-boot()` içine fonksiyon eklenir | ESP düzenini baştan kurmak |
| Bootmode sonuna `_maze_sb_sign_esp` çağrısı | systemd-boot kurulduktan *sonra* çalışsın |
| `-n ARCHISO_EFI` → `-n MAZE_EFI` | FAT etiketi (kozmetik, MokManager'da görünür) |
| FAT slack `+8192` → `+65536` KiB | UKI ~261 MiB tek parça; 8 MiB pay `mcopy: disk full` veriyordu |

Yamanın tutunduğu 3 çapa derleme başında `grep -F` ile doğrulanır; archiso
değişmişse build **erken** hata verir, saatler sonra değil.

### 1.2 `profiledef.sh` parametreleri

| Parametre | Değer | Not |
|---|---|---|
| `iso_name` | `mazelinux` | |
| `iso_label` | `MAZE_$(YYYYMM)` | |
| `install_dir` | `maze` | `unpackfs.conf` yolunun bağlı olduğu değer |
| `buildmodes` | `('iso')` | |
| `bootmodes` | `('uefi.systemd-boot')` | **BIOS yok — Maze UEFI-only** |
| `airootfs_image_type` | `squashfs` | `unpackfs` `airootfs.sfs` bekler |
| `airootfs_image_tool_options` | `-comp zstd -Xcompression-level 22 -b 1M` | |
| `cow_spacesize` | `6G` | Canlı oturumun yazma katmanı |
| `pacman_conf` | `pacman.conf` | Depo sırası kritik, aşağıda |
| `bootstrap_packages` | `arch-install-scripts`, `base` | |

`file_permissions[]`: `/etc/shadow` 400, `/root` 750, `/etc/sudoers.d/10-maze`
440, canlı yardımcı scriptler 755.

### 1.3 Depo sırası — `pacman.conf`

```
[maze-aur]    SigLevel = Optional TrustAll        Server = file://./localrepo
[mazelinux]   SigLevel = Required DatabaseOptional Server = https://mazerepo…
[core] [extra] [multilib]
```

`[maze-aur]` = `MazeLinux/localrepo/`. `aur/` altındaki PKGBUILD dizinlerinden
önceden derlenmiş AUR paketleri, `calamares`, `shim-signed` ve **Maze'in kendi
paketleri** burada durur. `update-repo.sh` `repo-add` çalıştırır ve her isim
için yalnızca en yeni sürümü tutar (eskileri diskten siler).

> **Sürüm önceliği:** pacman depolar arasında en yüksek sürümü seçer. localrepo'ya
> uzak repodakinden yüksek `pkgrel` ile paket koymak, ISO derlemesinin yereli
> kullanmasını garanti eder. Yerel paket sürümü uzaktan düşükse **uzak repo kazanır.**

### 1.4 Canlı ISO'nun boot zinciri

`_maze_sb_sign_esp()`, archiso ESP'yi hazırladıktan sonra düzeni **tamamen
değiştirir**:

1. systemd-boot ve gevşek kernel/initramfs ESP'den silinir
2. `ukify build` ile UKI üretilir:
   `--linux=vmlinuz-linux --initrd=<mikrokod…> --initrd=initramfs-linux.img
   --stub=/usr/lib/systemd/boot/efi/linuxx64.efi.stub --cmdline=…`
   (mikrokod initramfs'e gömülü değilse **önce** eklenir)
3. `sbsign` ile **paylaşılan Maze anahtarıyla** imzalanır → `grubx64.efi`
4. `shim-signed`'ın `shimx64.efi`'si → `BOOTx64.EFI`, yanına `mmx64.efi`,
   ESP köküne `MOK.cer`

```
firmware → BOOTx64.EFI (shim, Microsoft imzalı)
         → grubx64.efi (Maze imzalı UKI)
         → kernel
```

Shim ikinci aşamayı **her zaman** kendi `shim_lock` protokolüyle (MOK tabanlı)
doğrular, firmware'in `db`'siyle değil. Kernel UKI'nin içinde gömülü olduğu için
firmware ayrıca `vmlinuz` yüklemez — MSI/ASUS gibi katı firmware'lerin
"Security Policy Violation" vermesinin önüne bu geçer.

**Canlı cmdline** (`efiboot/loader/entries/01-*.conf` ile birebir aynı olmak
zorunda):
```
archisobasedir=maze archisosearchuuid=<uuid> quiet splash bgrt_disable
logo.nologo lsm=landlock,lockdown,yama,integrity,apparmor,bpf
apparmor=1 security=apparmor
```

> `efiboot/loader/` **artıktır**. Çalışma anında hiç okunmaz; yalnızca archiso
> `uefi.systemd-boot` buildmode'u için dizinin var olması gerektiğinden durur.
> Dosyaların içindeki yorumlar da bunu söyler.

### 1.5 İmzalama anahtarları — iki ayrı anahtar

| Anahtar | Nerede üretilir | Kapsam | Ne imzalar |
|---|---|---|---|
| `keys/secureboot/Maze.{key,crt,cer}` | Derleme makinesinde, bir kez (`tools/gen-sb-keys.sh`) | **Tüm ISO'larda ortak** | Canlı ISO'nun UKI'si |
| `/var/lib/maze-secureboot/MOK.{key,crt,cer}` | **Kurulan makinede**, kurulum anında | O makineye özel | Kurulu sistemin UKI'si + DKMS modülleri |

Ortak ISO anahtarı bilinçli: kullanıcı her yeni sürümde anahtarı yeniden enroll
etmek zorunda kalmaz. Kurulan sistemin anahtarı ise makineye özeldir ve özel
yarısı makineyi hiç terk etmez.

---

## 2. Kurulum — Calamares

### 2.1 Modül sırası (`settings.conf`)

```
show : welcome → locale → keyboard → partition → users → summary

exec : partition → mount → unpackfs → shellprocess@mountapi → machineid
     → locale → keyboard → luksbootkeyfile → fstab → removeuser → users
     → networkcfg → displaymanager → hwclock → initcpiocfg → initcpio
     → bootloader → services-systemd → shellprocess@mazedeploy → umount

show : finished
```

İki `shellprocess` örneği Maze'e ait: **mountapi** (unpackfs'ten hemen sonra) ve
**mazedeploy** (her şeyin sonunda).

### 2.2 Modül parametreleri

| Modül | Kritik ayarlar |
|---|---|
| `partition` | ESP `/boot`, **3 GiB**, ad `ESP` · varsayılan fs `btrfs` · `luksGeneration: luks2` · `userSwapChoices: none, file` |
| `mount` | Alt birimler `/@`, `/@home`, `/@cache`, `/@log` · btrfs `noatime,compress=zstd:1` · efi `umask=0077` |
| `fstab` | efi `defaults,umask=0077` · `crypttabOptions: luks,discard` |
| `unpackfs` | `/run/archiso/bootmnt/maze/x86_64/airootfs.sfs` (squashfs) → `/` |
| `initcpiocfg` | `useSystemdHook: false` → busybox kancaları (`encrypt`, `sd-encrypt` değil) |
| `initcpio` | `kernel: all` |
| `bootloader` | `systemd-boot` · `kernelSearchPath: /usr/lib/modules` · `kernelPattern: ^vmlinuz.*` · `timeout: 0` · `efiBootloaderId: Maze` · `installEFIFallback: true` |
| `users` | kabuk `/usr/bin/zsh` · `sudoersGroup: wheel` · `setRootPassword: false` · minLength 8 |

> `userSwapChoices` bilinçli olarak **swap partisyonu sunmaz**: şifreli kurulumda
> Calamares `openswap` mkinitcpio kancasını ekler, o kanca Arch'ta yoktur ve
> `mkinitcpio` çöküp kurulumu tamamen başarısız kılar. Sonuç: `resume` kancası
> yok, cmdline'da `resume=` yok → **hibernation mümkün değil** (suspend-to-RAM çalışır).

### 2.3 `calamares-mount-api.sh` — shellprocess@mountapi

unpackfs'ten hemen sonra, hedef sistem henüz ham kopyayken:

1. `/proc /sys /dev /run` + `efivarfs` hedefe bind edilir (chroot'suz adımlar için)
2. **De-archiso:** `mkinitcpio.conf.d/archiso.conf` silinir; preset `PRESETS=()`
   olarak yeniden yazılır — sistem `layout=uki` ile boot ettiği için gevşek
   `/boot/initramfs-*.img` üretmek hem gereksiz hem de FAT32 ESP'de ~250-400 MB israf
3. Canlı `maze` kullanıcısının `/home/maze`'i **`users` modülü çalışmadan önce**
   silinir (gerçek kullanıcı da `maze` adını seçerse temiz skel alsın diye)

### 2.4 `deploy-to-target.sh` — shellprocess@mazedeploy

~2300 satır, `dontChroot: true` (canlı sistemde çalışır, `$TARGET` üzerinden),
**best-effort** — tek bir adımın hatası kurulumu iptal etmez. `arch-chroot`
gerektiren işler `in_chroot()` ile yapılır (stdin `/dev/null`, prompt kilitlenmesi olmaz).

| Adım | İş |
|---|---|
| 2 | Masaüstü/marka/araçlar canlıdan hedefe (48 yol) |
| 2c | **Canlı-only temizliği:** autologin, parolasız sudo+pkexec, archiso sshd drop-in, volatile journald, mDNS, canlı `motd` |
| 3 | Kullanıcı başına: skel, `maze`/`entropy-shield` grupları, avatar, home `700`, `.ssh` modları, zsh |
| 3b | NVIDIA `modprobe.d` yapılandırması (kuruluysa); nvidia `MODULES` dışında tutulur |
| 4 / 4b | Plymouth; archiso mkinitcpio drop-in'i kaldır, `COMPRESSION=zstd` sabitle |
| 5 | `/etc/kernel/cmdline` yazılır (+ LUKS `allow-discards`) |
| 5b | `setup_secure_boot` — MOK üretimi, imzalayıcı, kancalar |
| 6 | Servisleri aç/kapat (21 servis; canlı-only ve boot'u yavaşlatanlar kapatılır) |
| 7 | pacman ayarı, `[mazelinux]` ekle, `[maze-aur]`/`[blackarch]` temizle |
| 8b | `pacman-key --init/--populate` |
| 10 | `[mazelinux]`'ten Maze uygulamaları |
| 11 | AUR: `paru` (kaynaktan) + `onlyoffice-bin` |
| 12 / 12b | Son Secure Boot imzalama + **doğrulama ve boot kontrolü** |
| 13 | Keyring'i sıfırdan kur, doğrula, ilk-boot yedeğini kur |

### 2.5 Kurulan sistemin boot zinciri

`/etc/kernel/install.conf` → `layout=uki`. Gerçek boot artefaktı:

```
$ESP/EFI/Linux/<machine-id>-<kver>.efi     ← kernel-install üretir
$ESP/EFI/BOOT/grubx64.efi                  ← onun MOK ile imzalı KOPYASI
$ESP/EFI/BOOT/BOOTX64.EFI                  ← shim

firmware → BOOTX64.EFI (shim) → grubx64.efi (MOK imzalı UKI) → kernel
```

> `grubx64.efi` UKI'nin **ayrı bir kopyasıdır**. `EFI/Linux/` altını düzenlemek
> ona dokunmaz — teşhis sırasında en çok yanıltan nokta budur.

**Kalıcılık mekanizmaları** (çekirdek güncellemelerinde zinciri ayakta tutar):

Bunların tamamı **`maze-secureboot` paketiyle** gelir (`maze-meta` ona bağımlı).
Eskiden kurulum sırasında `/usr/local/bin` ve `/etc` altına yazılan sahipsiz
dosyalardı; öyleyken kurulu bir makinede *düzeltilemiyorlardı*. Paketin
`.install` scriptleti eski kopyaları devralır — ayrıntı: `maze-secureboot/README.md`.

| Bileşen | Tetikleyici |
|---|---|
| `/usr/share/libalpm/hooks/85-maze-kernel-install.hook` | `usr/lib/modules/*/vmlinuz` yazılınca → `kernel-install add` |
| `/usr/lib/kernel/install.d/95-maze-sb-sign.install` | Her `kernel-install add` sonrası → imzala |
| `/usr/share/libalpm/hooks/zz-maze-secureboot.hook` | nvidia/dkms/mkinitcpio/systemd kurulunca → yeniden imzala |
| `maze-sb-resign.path` → `.service` | `$ESP/EFI/Linux` değişince (pacman dışı) |
| `systemd-boot-update.service.d/99-maze-resign.conf` | `bootctl update` shim'i ezerse geri koyar |

**Yeniden başlatmadan önce doğrulama:** `maze-boot-check` zinciri uçtan uca
kontrol eder — her kurulu çekirdeğin UKI'si, `grubx64.efi`'nin modülleri diskte
duran bir çekirdeği gösterip göstermediği, iddia ettiği UKI ile bayt eşitliği,
MOK imzası, shim, Secure Boot açıkken MOK kaydı, LUKS kökünde `encrypt` hook'u,
cmdline UUID'lerinin gerçekliği, `layout=uki`, ESP boş alanı ve `/etc` altında
gölgeleyen kopya olup olmadığı. Her transaction'ın sonunda
`zzz-maze-boot-verify.hook` ile çalışır; başarısız olursa
`/var/lib/maze/boot-unsafe` bayrağını yazar.

Bayrak varken `maze-boot-guard` bir logind shutdown inhibitor'ı tutar: Plasma
çıkış menüsü ve oturum içi `systemctl reboot` sebebiyle birlikte reddedilir.
`systemctl reboot -i` ve `reboot -f` bilerek serbesttir — yönetici kendi
makinesinde son sözü söyler, buradaki iş kararı bilgilendirmektir.

**Çekirdek dışı kurtarma:** `maze-snapshots` (snapper + snap-pac) her pacman
işleminin öncesi ve sonrasında `@` subvol'ünün btrfs snapshot'ını alır. Boot
zincirine dokunmayan çökmeler — bozuk kütüphane, yarım yükseltme — buradan geri
alınır.

**Hangi çekirdek boot eder:** `maze-sb-sign` önce `/etc/maze/kernel-default`
(çekirdek değiştiricinin sabitlediği pkgbase) dosyasına bakar, o çekirdek kurulu
ve ESP'de UKI'si varsa onu `grubx64.efi` yapar; değilse en yeniye düşer ve
sebebini yazar. Bir önceki imaj `grubx64.efi.maze-prev` olarak saklanır (yalnız
çekirdek *sürümü* değişince döner, `grubx64.efi.maze-kver` ile izlenir) — menü
olmayan bir zincirde tek geri dönüş yolu budur:
`cp -f $ESP/EFI/BOOT/grubx64.efi.maze-prev $ESP/EFI/BOOT/grubx64.efi`

**Nihai HOOKS:**
```
base udev autodetect microcode kms modconf block keyboard keymap
consolefont plymouth encrypt filesystems
```

**Nihai cmdline:**
```
quiet splash rw rootflags=subvol=/@
cryptdevice=UUID=<luks>:luks-<luks>:allow-discards
root=/dev/mapper/luks-<luks>
bgrt_disable logo.nologo lsm=landlock,lockdown,yama,integrity,apparmor,bpf
apparmor=1 security=apparmor
[+ nvidia-drm.modeset=1 nvidia-drm.fbdev=1 — nvidia kuruluysa]
```

---

## 3. Canlı ISO ↔ Kurulan Sistem

| | Canlı ISO | Kurulan sistem |
|---|---|---|
| Kök dosya sistemi | squashfs + overlay (`cow_spacesize=6G`) | LUKS2 + btrfs alt birimler |
| UKI'yi üreten | `ukify`, `mkarchiso`'ya enjekte edilmiş | `kernel-install` (`layout=uki`) |
| UKI konumu | Yalnızca `EFI/BOOT/grubx64.efi` | `EFI/Linux/<mid>-<kver>.efi` + `grubx64.efi` kopyası |
| İmza anahtarı | Ortak `keys/secureboot/Maze.key` | Makineye özel MOK |
| initramfs kancaları | `base udev microcode modconf plymouth archiso* block filesystems keyboard` — `autodetect`/`encrypt`/`kms` **yok** | `… autodetect microcode kms … encrypt filesystems` |
| initramfs sıkıştırma | `zstd` | `zstd` (deploy tarafından sabitlenir) |
| mkinitcpio preset | archiso preset | `PRESETS=()` (UKI kullanıldığı için) |
| sudo | Parolasız (`10-maze`) | **Parola zorunlu** (`10-maze-wheel`) |
| Autologin | Var | Yok |
| sshd | Açık (uzaktan kurulum için) | **Kapalı** |
| journald | `Storage=volatile` | Kalıcı (varsayılan) |
| pacman keyring | Her boot'ta `pacman-init.service` | Kurulumda bir kez, kalıcı |
| Tarayıcı | Firefox (kurumsal politika ile Maze ana sayfası) | Firefox (stok varsayılanlar) |

---

## 4. Bilinen sınırlar

- **UEFI-only.** BIOS/GRUB yolu yok; `is_uefi()` kontrolü yalnızca uyarı üretir.
- **Hibernation yok.** §2.2'deki swap kararının doğrudan sonucu.
- **`grubx64.efi` UKI'nin ikinci tam kopyası.** ESP'de UKI boyutu iki kere ödenir;
  shim zincirinin gereği.
- **`maze-sb-sign` ve kancalar kurulum anında üretilir** (`deploy-to-target.sh`
  içindeki heredoc'lardan), paket dosyası olarak gelmez. Bu dosyalardaki bir hata
  mevcut kurulumlarda `pacman -Syu` ile düzeltilemez.
- **Bayat yorum:** `deploy-to-target.sh` adım 4b, canlı drop-in'in
  `COMPRESSION="xz"` (-9e) olduğunu ve bunun boot'u yavaşlattığını söyler;
  `airootfs/etc/mkinitcpio.conf.d/archiso.conf` bugün `zstd` kullanıyor.
  Kod zararsız (zstd'yi zaten sabitliyor), gerekçe artık geçerli değil.
- **Early KMS bedeli.** `kms` kancası nouveau'lu makinelerde `/lib/firmware/nvidia/`
  ağacını initramfs'e sokar (ölçüm: 20 MB → 138 MB, 106 MB'ı bu ağaç). Proprietary
  sürücü kurulup nouveau blacklist'lenince sonraki derlemede düşer.

---

## 5. Derleme sırası

```bash
# 1) AUR paketleri (aur/<pkg>/ altında) → localrepo
cd MazeLinux/localrepo && ./update-repo.sh

# 2) Maze paketleri: pkgrel artır → makepkg → localrepo → update-repo.sh
cd maze-tools     && makepkg -f
cd maze-installer && makepkg -f

# 3) ISO (root gerekir)
sudo ./build.sh
```

Adım 2'de `pkgrel` artırmak zorunludur: uzak `[mazelinux]` deposunda aynı veya
daha yüksek bir sürüm varsa mkarchiso onu seçer ve yerel değişiklikler ISO'ya girmez.

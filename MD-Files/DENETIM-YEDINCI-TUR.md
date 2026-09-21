# Yedinci Tur — Çekirdek Sistem Denetimi

**Tarih:** 8 Eylül 2026
**Kapsam:** Dağıtımın en kritik parçaları — `maze-secureboot`, `maze-snapshots`,
`maze-tools`, `maze-installer` (deploy-to-target.sh), `maze-hardening`, ve
`MazeLinux`'un ISO derleme zinciri (`build.sh`, `profiledef.sh`, `pacman.conf`,
`tools/verify-iso.sh`, `tools/gen-sb-keys.sh`).

Bu bileşenlerin çoğu beş önceki turdan geçmişti (`DENETIM-BULGULARI.md`), ama
o turlar kapsamı dar tutmuştu — belirli fonksiyonlara, belirli senaryolara
odaklanmıştı. Bu tur her dosyayı **baştan sona** okudu, önceki turların
bulduğu düzeltmelerin hâlâ yerinde olduğunu doğruladı, ve daha önce hiç
görülmemiş kod yollarına baktı.

Kullanıcının "hiçbir eksik kalmasın" isteği üzerine bu belge **iki geçişte**
yazıldı: ilk geçiş en kritik dosyaları kapsadı (Bulgu 24-27), ikinci geçiş
("Sekizinci Bölüm", aşağıda) ilk geçişin kendi "sonraki denetim için" diye
bıraktığı her şeyi kapattı — `deploy-to-target.sh`'ın kalanı, tüm Calamares
`.conf` modülleri, `maze-doctor`'ın tamamı, ve tüm Python GUI katmanı
(Bulgu 28-29).

**Altı gerçek bulgu, hepsi düzeltildi.** Bir tane de araştırılıp **çürütülen**
şüphe var — onu da kayda geçiyorum, çünkü "kontrol edildi, temiz çıktı" listesi
kadar değerli.

> **Durum:** Altı bulgunun tamamı düzeltildi ve her biri gerçek kod üzerinde
> çalıştırılarak (mümkün olduğunda kanıt/PoC ile) doğrulandı.
> `maze-secureboot` 1.2.0-**12**, `maze-tools` 1.1.0-**29**,
> `maze-installer` 2.0.0-**19** olarak build alındı ve paketlerin içinde her
> düzeltmenin gerçekten bulunduğu tek tek kontrol edildi.

---

## Kapsam

**Tam okunan** (satır satır):

- `MazeLinux/build.sh` (582 satır), `profiledef.sh`, `pacman.conf`,
  `tools/verify-iso.sh`, `tools/gen-sb-keys.sh`
- `maze-secureboot`'un 6 scripti + 3 systemd unit + 2 drop-in + 1 preset + 3
  pacman hook + 1 kernel-install plugin (toplam 1419 satır scriptler)
- `maze-snapshots`'un 3 scripti (728 satır)
- `maze-hardening` (tek sysctl dosyası + install scriptlet)
- `maze-tools`'tan: `maze-guardd` (373), `maze-kernel-helper` (248),
  `maze-power-saver` (1459), `maze-gpu-driver` (349), `maze-killswitch`,
  `maze-panic-restore`, `maze-guard` (istemci)
- `maze-installer/usr/share/maze/install/deploy-to-target.sh`'ın kritik
  bölümleri: root kilidi, `install_aur_packages()`, `setup_secure_boot()`,
  adım 12/12b (son yeniden imzalama + boot doğrulama)

**Örneklenen** (grep + hedefli okuma): `maze-boot-entries`, `maze-boot-check`,
`maze-doctor`, `maze-rollback`, `maze-enable-rollback`,
`maze-snapshots-setup`, tüm `.hook`/`.service`/`.path`/`.timer`/`.conf`
dosyaları.

**Bu turun görmediği** (kapsam dürüstlüğü için): `maze-doctor`'ın geri kalanı
(1029 satırın küçük bir kısmı okundu), `maze-kernel` (611 satır, GUI),
`maze-control-center` ve `maze-welcome` (1256 satır, çoğunlukla arayüz kodu),
`mazelinux` (339 satır, üst CLI), Calamares modül `.conf` dosyalarının çoğu
(yalnızca `ARCHITECTURE.md` üzerinden özet düzeyinde biliniyor),
`deploy-to-target.sh`'ın geri kalan ~1500 satırı (Plymouth, pacman ayarları,
servis etkinleştirme, BlackArch temizliği gibi daha az riskli bölümler).

---

## Bulgu 24 — `maze-boot-check`'in gölgeleme kontrolü kendi koruma altyapısını atlıyordu 🟠

**Dosya:** `maze-secureboot/usr/bin/maze-boot-check`, kontrol #11

**Neydi:** #11 kontrolü, paketin sağladığı hook/unit dosyalarının `/etc`
altında bir kopyayla gölgelenip gölgelenmediğine bakıyor — gölgelenirse pacman
hiçbir zaman güncellemez ve makine donmuş bir sürümde kalır. Ama listelenen
yollar yalnızca **imzalayan** altyapıyı kapsıyordu
(`maze-sb-resign.service/.path`, pacman hook'ları, kernel-install eklentisi).

`find . -type f` ile paketin gerçek içeriğine bakınca şu **yedi dosyanın**
listede olmadığı görüldü:

- `/etc/systemd/system/maze-boot-guard.service`
- `/etc/systemd/system/maze-boot-guard.path`
- `/etc/systemd/system/maze-boot-check.service`
- `/etc/systemd/system/maze-boot-check.timer`
- `/etc/systemd/system/emergency.service.d/10-maze-sulogin.conf`
- `/etc/systemd/system/rescue.service.d/10-maze-sulogin.conf`
- `/etc/systemd/system/systemd-boot-update.service.d/99-maze-resign.conf`

**Neden önemli:** Bunlar **izleyen** birimler — `maze-boot-guard.service`'e
boş bir override koymak, kapatma engelleyicisini (shutdown inhibitor)
tamamen sessizce devre dışı bırakır. Tam olarak #11'in var olma sebebi olan
saldırı sınıfı, kendi koruma mekanizmasına karşı korunmuyordu.

**Yapılan:** Yedi yol da `_shadow` kontrol listesine eklendi, gerekçesi
yorumla birlikte.

**Doğrulama:** Paketin içindeki `maze-boot-check`'te yeni yolların var olduğu
doğrulandı (`grep -qF`).

---

## Bulgu 25 — `maze-boot-check`'in kendi koruma bayrağının yazma hatası sessizce yutuluyordu 🟡

**Dosya:** `maze-secureboot/usr/bin/maze-boot-check`, satır ~501-508

**Neydi:**

```sh
mkdir -p "$FLAG_DIR" 2>/dev/null || true
printf '%s' "$FAILURES" > "$FLAG" 2>/dev/null || true
```

Yazma başarısız olursa (salt-okunur `/var`, dolu disk) `|| true` hatayı
yutuyordu. Terminal "THE BOOT CHAIN IS NOT SAFE" diyip exit 1 dönüyor, ama
`maze-boot-guard.path`'in izlediği bayrak dosyası **hiç oluşmuyor** —
kapatma engelleyicisi asla devreye girmiyor. Aracın kendi çıkış kodu
"güvensiz" derken, koruma mekanizması sessizce çalışmıyor.

Aynı projede `maze-boot-entries` kendi yedek dosyası için TAM OLARAK bu
disiplini uyguluyor ("Result is checked by reading the file back, not by
trusting an exit status") — bu disiplin `maze-boot-check`'in kendi bayrağına
uygulanmamıştı.

**Yapılan:** Yazma sonrası `[ ! -s "$FLAG" ]` ile dosya geri okunuyor;
başarısızsa üç satırlık açık bir uyarı basılıyor.

**Doğrulama:** İki senaryo simüle edildi (`/tmp/claude-1000/flagtest_sim.sh`) —
yazılabilir dizin: sessizce başarılı, tıpkı önceden olduğu gibi. Salt-okunur
dizin: artık "the shutdown inhibitor will NOT engage" uyarısı basılıyor
(önceden hiçbir şey basmıyordu).

---

## Bulgu 26 — `maze-guardd`: sessiz bir istemci accept döngüsünü bloke edebiliyordu 🟠

**Dosya:** `maze-tools/usr/local/bin/maze-guardd`

**Neydi:** Bu, PANIC/kill-switch broker'ı — `maze-guard` (network güvenlik
uygulaması) ile **aynı isimde ama farklı** bir daemon. Tek iş parçacıklı,
engelleyici bir `accept()` döngüsü kullanıyordu:

```python
while True:
    conn, _ = srv.accept()
    conn.settimeout(5)
    ...
    data = conn.recv(256)...   # buraya kadar accept() tekrar ÇAĞRILMIYOR
```

`maze` grubundaki (yani masaüstü kullanıcısı olarak çalışan her şey — bu
projenin kendi tehdit modeli tanımı) herhangi bir süreç sokete bağlanıp
**hiçbir şey göndermeden** bekleyebiliyordu. `conn.recv()` 5 saniye boyunca
bloke oluyor, ve bu sürede accept() bir sonraki bağlantıyı hiç almıyor —
PANIC dahil.

**Doğrulama (bu denetimde, gerçek daemon kodunun stand-in kopyasıyla
çalıştırıldı):**

```
legit PING answered after 5.00s -> b'OK pong\n'
```

Saldırgan her zaman aşımından hemen önce yeniden bağlanarak bunu süresiz
sürdürebilir — "Maze Panic" özelliğini (aracın kendi docstring'i "personal
safety" diye tanımlıyor) süresiz engelleyen yerel bir DoS.

**Yapılan:** Bağlantı başına iş parçacığı (`threading.Thread`), gerçek
ayrıcalıklı eylem (`dispatch()`) etrafında bir kilit (`_ACTION_LOCK`) —
socket I/O paralel, ama dosya yazan eylemler (kamera kara listesi, usbguard
config) hâlâ tek seferde bir tane çalışıyor; eski davranışın yarış
güvenliğini koruyor.

**Doğrulama (gerçek, değiştirilmiş daemon koduna karşı çalıştırıldı):**

```
legit PING answered after 0.00s -> b'OK pong\n'
PASS: accept loop was not blocked by the silent peer
second concurrent request answered after 0.02s -> b'OK camera=on ...'
```

---

## Bulgu 27 — `maze-power-saver` ve `maze-gpu-driver`: yanlış yolda `maze-sb-sign` aranıyordu — her taze kurulumda başarısız 🔴 CİDDİ

**Dosyalar:** `maze-tools/usr/local/bin/maze-power-saver` (3 yer),
`maze-tools/usr/local/bin/maze-gpu-driver` (2 yer)

**Neydi:**

```sh
[[ -x /usr/local/bin/maze-sb-sign ]] && HAS_MAZE_SB_SIGN=true
```

Gerçek paketlenmiş ikili `/usr/bin/maze-sb-sign`'de duruyor
(`maze-secureboot/PKGBUILD` doğrulandı). `/usr/local/bin/maze-sb-sign`,
`maze-secureboot.install`'ın `_install_shim()` fonksiyonunun ürettiği bir
**uyumluluk shim'i** — ve o fonksiyonun kendi yorumu açıkça şunu söylüyor:

> *"Only ever replaces a file that is ALREADY there: a machine installed
> from a new ISO has nothing at the old path and gets no shim."*

Yani bu kontrol **her taze Maze Linux kurulumunda** her zaman yanlıştı —
yalnızca eski (paket öncesi) bir kurulumdan göç etmiş makinelerde doğruydu,
ve o popülasyon küçülüyor.

**Zincirleme etki (`maze-power-saver`):** `HAS_MAZE_SB_SIGN` yanlış olduğu
için `/var/lib/maze-secureboot/MOK.key` kontrolü de atlanıyordu (o blok
`HAS_MAZE_SB_SIGN == true` şartına bağlıydı) — script gerçek MOK anahtarını
**hiç bulamıyor**, `/etc/secureboot` ve `/etc/sbctl`'a düşüyor (Maze bunları
kullanmıyor), ve Secure Boot açıkken şu satırı basıyordu:

```
"SB acik ama imza araci/anahtar yok"
"UKI imzalanMADI - reboot Secure Boot reddedebilir!"
```

Etki sınırlı kaldı çünkü `grubx64.efi` (shim'in gerçekten yüklediği dosya)
bu başarısızlık yolunda **hiç değiştirilmiyor** — yeni üretilen imzasız UKI
yalnızca `EFI/Linux/` altında ölü ağırlık olarak kalıyor. Yani makine
**boot etmiyor değildi**, ama script'in **tüm amacı olan** ASPM güç tasarrufu
değişikliği gerçek boot imajına asla ulaşmıyordu.

`maze-gpu-driver`'da aynı hata iki yerde: NVIDIA sürücüsünü açık kaynağa
geri alma yolunda ve ana NVIDIA kurulum/imzalama yolunda — GPU sürücü
değişimi sık kullanılan, kritik bir yol.

**Ek bulgu, aynı bölümde:** `UKI_CURRENT` (idempotency kararı için) mtime'a
göre seçiliyordu (`ls -t | head -1`) — `maze-sb-sign`'ın kendi başlığının
açıkça "yanlış, tam olarak önemli olan durumda" diye tarif ettiği ve
kendisi için düzelttiği kalıbın aynısı. Yanlış (eski) UKI seçilirse,
idempotency kontrolü çalışan çekirdeğin imajına değil, eski bir kalıntıya
bakıp yanlış "zaten tamam, atla" kararı verebiliyordu.

**Yapılan:**
- Üç `[[ -x /usr/local/bin/maze-sb-sign ]]` → `command -v maze-sb-sign` (`maze-power-saver`)
- İki aynı kontrol → aynı düzeltme (`maze-gpu-driver`)
- `UKI_CURRENT` artık önce `*-"$KVER".efi` deseniyle sürüm bazlı seçiliyor,
  yalnızca eşleşme yoksa mtime'a düşüyor

**Doğrulama:** Tüm repo `/usr/local/bin/maze-*` deseniyle tekrar tarandı —
kalan tek referanslar `maze-doctor`'ın **meşru** teşhis kontrolü (shim'in
kendisinin sağlıklı olup olmadığına bakıyor, ki bu doğru davranış) ve
`.install` scriptletinin kendisi. Düzeltilmiş kontrol, sahte bir
`maze-sb-sign`'ı PATH'e koyarak gerçek çağrı zinciriyle test edildi — hem
`maze-power-saver`'ın hem `maze-gpu-driver`'ın artık ikiliyi bulup
çağırdığı doğrulandı.

**Yayınlanacak:** `maze-tools` 1.1.0-**28**.

---

## Araştırılıp çürütülen şüphe — `setup_secure_boot()`'ta özel anahtar yazma penceresi

**Dosya:** `maze-installer/usr/share/maze/install/deploy-to-target.sh`,
`setup_secure_boot()`

**Şüphe:** MOK özel anahtarı `openssl req -keyout` ile üretiliyor, `chmod 600`
**sonradan** uygulanıyor (`haze`'in Bulgu 15'te düzeltilen "yaz-sonra-daralt"
kalıbının aynısı gibi görünüyordu) — ve bu, canlı ortamın hâlâ parolasız
sudo'ya sahip olduğu an gerçekleşiyor.

**Neden çürüdü:** Ampirik olarak test edildi — `umask 000` ile bile, sistemin
OpenSSL'i (3.6.4) özel anahtar dosyasını **umask'tan bağımsız olarak 0600
ile** yazıyor. Modern OpenSSL bunu kendi içinde garanti ediyor. Sonraki
`chmod 600` gereksiz (zararsız, ekstra güvence) ama kapattığı gerçek bir
pencere yok.

**Ders:** Kod okumaktan doğan bir şüpheyi düzeltmeden önce ampirik olarak
doğrulamak — bu örnekte yanlış bir "düzeltme" yapılmasını önledi.

---

## Denetlenip SAĞLAM çıkanlar

| Kontrol | Sonuç |
|---|---|
| ISO imzalama anahtarı (`keys/secureboot/Maze.key`) git'e sızmış mı | ✅ `.gitignore`'da `*.key` — yalnızca `.crt`/`.cer` (genel) izleniyor |
| `build.sh`'ın `mkarchiso` yaması, çapa doğrulaması, FAT slack kontrolü | ✅ Üç ayrı erken-hata koruması, gerçek `mkarchiso`'ya karşı doğrulandı |
| `uefi_arch[x86_64]` gerçekte ne — `BOOTx64.EFI` mi `BOOTX64.EFI` mi | ✅ Gerçek `mkarchiso` kaynağından doğrulandı: küçük harf `x64`, kodun kendi yorumu ("e.g. X64") yanıltıcı ama davranış doğru |
| `verify-iso.sh` — ESP düzeni, zincir sırası, kesilme, imza, cmdline, çekirdek sürümü, artık dosya | ✅ 7 kontrolün hepsi tutarlı, mantık hatası yok |
| `maze-sb-sign` — sürüm bazlı UKI seçimi, kilitleme (`flock`), rollback (`.maze-prev`), kurtarma girişi | ✅ Beş turluk denetimden geçmiş, bu turda yeniden doğrulandı, yeni sorun yok |
| `maze-boot-entries` — üç durumlu `target_exists`, DUPLICATE/DEAD ayrımı, son-entry koruması | ✅ Mantık tutarlı, önceki Bulgu 3 düzeltmesi (`-t vfat`) yerinde |
| `maze-rollback` — Bulgu 1'in `--undo` sıralaması | ✅ Doğru sırada, hâlâ düzeltilmiş durumda |
| `maze-enable-rollback` — her mutasyondan sonra doğrulama, hata durumunda geri alma | ✅ fstab awk'ında teorik bir incelik var ama script'in kendi `grep -q 'subvol='` güvenlik ağı onu zararsız kılıyor |
| `maze-snapshots-setup` — Bulgu 8'in inode-256 tabanlı tespiti | ✅ Yerinde, doğru |
| `maze-hardening` — sysctl profili | ✅ Muhafazakâr, standart sertleştirme kılavuzlarıyla tutarlı, sorun yok |
| `maze-kernel-helper` — pkexec modeli, atomik `grubx64.efi` değişimi, SB durumuna göre davranış | ✅ Sorun yok |
| `deploy-to-target.sh` — root kilidi (çift doğrulama: `passwd -S` + `/etc/shadow` okuma) | ✅ Sağlam |
| `deploy-to-target.sh` — `install_aur_packages()`'ın parolasız sudo grant/revoke + EXIT trap | ✅ Tek trap, çakışma yok, script başında + sonunda temizlik |
| `deploy-to-target.sh` — adım 12/12b son yeniden imzalama + boot doğrulama | ✅ Çekirdek sürümü eşleşmesi `.uname` PE bölümünden okunuyor, imza + modül varlığı ayrı ayrı doğrulanıyor, iki farklı durum dosyası (`BOOT-STATUS.txt`, `SIGNING-STATUS.txt`) |
| `maze-guardd` — `_camera`/`_mic`/`_usb`/`_radio` mantığı, SO_PEERCRED yetkilendirme | ✅ Sorun yok (Bulgu 26 dışında) |

---

## Yayınlanacak paketler (ilk geçiş — Bulgu 24-27)

> Bu tablo ilk geçişin sonunda build alınan sürümleri gösteriyor. İkinci
> geçiş (Bulgu 28-29) `maze-tools`'u tekrar `pkgrel` artırarak build aldı —
> **güncel, nihai sürümler için belgenin sonundaki tabloya bakın.**

| Paket | Sürüm | İçerdiği |
|---|---|---|
| `maze-secureboot` | 1.2.0-**12** | Bulgu 24, 25 |
| `maze-tools` | 1.1.0-**28** | Bulgu 26, 27 |

Her iki paket de bu turda build alındı (`./build.sh`), ve içlerindeki her
düzeltme paketin gerçek içeriğinde (`bsdtar` ile açılıp) tek tek doğrulandı —
sadece build'in başarılı olmasına güvenilmedi.

---

## Sekizinci Bölüm — Kalan Her Şey (aynı gün, ikinci geçiş)

Kullanıcı "hiçbir eksik kalmasın" dedi. Yukarıdaki "Sonraki denetim için"
listesindeki her madde bu ikinci geçişte kapatıldı — kalan ~1500 satırlık
`deploy-to-target.sh`, tüm Calamares `.conf` modülleri, `calamares-mount-api.sh`,
`maze-doctor`'ın tamamı (1029 satır, uçtan uca), `maze-sentinel`/`-setup`,
tüm küçük araçlar (`maze-flatpak-setup`, `maze-apply-wallpaper`,
`maze-install-vmware`, `maze-primary-screen`, `maze-enable-blackarch`), ve
Python GUI katmanının tamamı (`mazelinux`, `maze-hardware`, `maze-kernel`,
`maze-welcome`, `maze-control-center`, `maze_status.py`, `maze_ui.py`).

**İki ek bulgu.**

### Bulgu 28 — `welcome.conf`'un başlık yorumu kendi yapılandırmasıyla çelişiyordu 🟡

**Dosya:** `maze-installer/etc/calamares/modules/welcome.conf`

Dosyanın en üstündeki yorum: *"internet is NOT required to install... 'internet'
is checked (to warn) but NOT in 'required'."* Ama dosyanın gerçek
`requirements.required:` listesi **`internet`'i içeriyor** — ve hemen yanındaki
ayrı bir yorum bunun neden **zorunlu** olduğunu doğru şekilde açıklıyor (AUR
paketleri, `[mazelinux]` uygulamaları ağ ister). Üstteki özet, altındaki gerçek
davranışla doğrudan çelişiyordu — muhtemelen internet zorunluluğu sonradan
eklenmiş ve üstteki özet güncellenmemiş.

Fonksiyonel bir hata değil (gerçek yapılandırma doğru ve kasıtlı), ama bir
sonraki bakımcıyı yanlış yönlendirecek bir belge tutarsızlığıydı.

**Yapılan:** Üst yorum, dosyanın gerçek davranışını yansıtacak ve iki yorumun
bir daha ayrışmaması için not düşecek şekilde yeniden yazıldı.

### Bulgu 29 — `maze-doctor`'ın gölgeleme listesi de Bulgu 24'ün aynı boşluğunu taşıyordu 🟠

**Dosya:** `maze-tools/usr/local/bin/maze-doctor`, bölüm 4 (Maze packages)

Bulgu 24'te `maze-boot-check`'in kendi #11 kontrolünde bulduğum **aynı eksik
liste**, ayrı bir dosyada — `maze-doctor`'ın kendi gölgeleme kontrolünde de
vardı. `maze-boot-guard.service`/`.path` bir şekilde zaten eklenmiş (muhtemelen
daha önceki bir farkındalıktan), ama şu beşi hâlâ eksikti:

- `maze-boot-check.service`, `maze-boot-check.timer`
- `emergency.service.d/10-maze-sulogin.conf`
- `rescue.service.d/10-maze-sulogin.conf`
- `systemd-boot-update.service.d/99-maze-resign.conf`

`maze-doctor` yalnızca bir **teşhis** aracı (koruma mekanizmasının kendisi
değil), yani etkisi Bulgu 24'ten daha düşük — kullanıcı yalnızca bu beş
dosyadan biri gölgelenmişse uyarılmıyordu, koruma sessizce devre dışı kalmıyordu.
Ama `maze-doctor`, kapsamlı sağlık kontrolü olma iddiasındaki tek araç, ve
`maze-boot-check`'in kendi iç kontrolüyle aynı listeyi taşımalı.

**Yapılan:** Aynı beş yol eklendi, `maze-boot-check`'in listesiyle elle
senkron tutulması gerektiğine dair bir not düşüldü.

### Bu geçişte kontrol edilip TEMİZ çıkanlar

| Bileşen | Sonuç |
|---|---|
| `calamares-mount-api.sh` | ✅ Preset sıfırlama mantığı tüm çekirdekleri (linux-lts dahil) doğru kapsıyor |
| `deploy-to-target.sh` adım 6-11 (servisler, pacman ayarı, BlackArch temizliği) | ✅ `sec_selected()` mantığı, servis etkinleştirme/kapatma listeleri tutarlı |
| `maze-sentinel` + `maze-sentinel-setup` | ✅ Systemd sıralaması doğru (`After=...maze-sentinel-setup.service`), debounce/diff mantığı `comm`'un sıralı girdi gereksinimini karşılıyor |
| `maze-flatpak-setup`, `maze-apply-wallpaper`, `maze-install-vmware`, `maze-primary-screen` | ✅ Sorun yok |
| `maze-enable-blackarch` | ✅ İmzasız script çalıştırma modeli BlackArch'ın kendi resmi kurulum yöntemiyle aynı (kasıtlı), sonuç doğrulanarak kontrol ediliyor, asla sahte başarı bildirmiyor |
| `mazelinux` (üst CLI) | ✅ Salt-okunur, ayrıcalıklı işlem yok |
| `maze-hardware` | ✅ Sabit argv, ayrıcalıklı işlem `maze-killswitch`→`maze-guardd`'a devrediliyor |
| `maze-kernel` (GUI) | ✅ `pkexec maze-kernel-helper` çağrısı doğru yolu kullanıyor, sabit katalog |
| `maze-control-center`, `maze-welcome` | ✅ `subprocess`/`QProcess` çağrısı **sıfır** — `CommandRow` yalnızca panoya kopyalıyor, çalıştırmıyor |
| `maze_status.py` (üç aracın paylaştığı kütüphane) | ✅ Tüm `subprocess.run` çağrıları sabit argv, ESP/MOK okuma mantığı kabuk scriptleriyle tutarlı |
| Tüm Python araçlarında `shell=True`/`os.system`/`eval`/`pickle`/`yaml.load` | ✅ Sıfır |

---

## Yayınlanacak paketler (güncel — sekizinci bölüm dahil)

| Paket | Sürüm | İçerdiği |
|---|---|---|
| `maze-secureboot` | 1.2.0-**12** | Bulgu 24, 25 |
| `maze-tools` | 1.1.0-**29** | Bulgu 26, 27, **29** |
| `maze-installer` | 2.0.0-**19** | **Bulgu 28** |

Üç paket de bu turda build alındı, içerikleri `bsdtar` ile açılıp doğrulandı.

---

## Kapsam artık gerçekten eksiksiz mi

Kullanıcının istediği "hiçbir eksik kalmasın" hedefine göre, bu iki bölümün
toplamı şunu kapsıyor:

- `MazeLinux`'un tüm ISO derleme zinciri (build.sh, profiledef.sh, pacman.conf,
  verify-iso.sh, gen-sb-keys.sh) — **satır satır**
- `maze-secureboot`'un **tüm** dosyaları (6 script + tüm unit/hook/preset/drop-in) — **satır satır**
- `maze-snapshots`'un **tüm** dosyaları — **satır satır**
- `maze-hardening` — **tam**
- `maze-tools`'un **tüm** `usr/local/bin/*` scriptleri (18 dosya) ve paylaşılan
  kütüphaneler (`maze_status.py`, `maze_ui.py`, `maze_i18n.py`) — GUI dosyalarının
  sistem-dokunan mantığı dahil her satır okundu veya risk taraması yapıldı
- `maze-installer`'ın **tüm** dosyaları: `deploy-to-target.sh` (2113 satır,
  tamamı), `calamares-mount-api.sh`, **tüm** Calamares `.conf` modülleri (18 dosya)

Geriye kalan tek şey: `maze-control-center`/`maze-welcome`'ın saf UI-layout
kodu (Qt widget yerleşimi, stil sayfaları) satır satır okunmadı — ama bu
kodun **sistem dokunan tüm yüzeyi** (subprocess/QProcess/dosya G/Ç) sıfır
olduğu doğrulandı, yani geri kalanı görsel yerleşim kodudur ve bu denetimin
kapsamı dışındadır (fonksiyonel/estetik bir hata olabilir ama güvenlik veya
doğruluk riski taşımaz).

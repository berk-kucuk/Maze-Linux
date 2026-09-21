# Boot dayanıklılığı ve snapshot desteği

Bu belge tek bir çalışmada eklenen özellikleri, hangi sorunu çözdüklerini ve
nasıl kullanıldıklarını anlatır. Paket sürümleri: `maze-secureboot 1.2.0-5`,
`maze-snapshots 1.0.0-6`, `maze-tools 1.1.0-18`, `maze-meta 1.4.0-1`,
`maze-guard 2.14.0-3`, `maze-installer 2.0.0-15`.

---

## Neden bu iş yapıldı

Maze'in boot zinciri — UKI'yi yeniden kuran, MOK ile imzalayan, shim'in
yükleyeceği `grubx64.efi`'yi yerine koyan her şey — kurulum sırasında
`deploy-to-target.sh` tarafından `/usr/local/bin` ve `/etc` altına **satır içi
heredoc olarak** yazılıyordu.

Bunun anlamı şuydu: pacman o dosyaların hiçbirinin sahibi değildi, dolayısıyla
imzalayıcıdaki bir hata ya da `kernel-install` sözleşmesini bozan bir upstream
değişikliği **kurulmuş bir makinede asla düzeltilemezdi**. Arıza biçimi "makine
açılmıyor" olan tek katman, güncelleme yolu olmayan tek katmandı.

Geri kalan her şey bunun etrafında büyüdü.

---

## 1. Boot zinciri artık bir paket

**`maze-secureboot`**

| Dosya | İşi |
|---|---|
| `/usr/bin/maze-sb-sign` | UKI'yi MOK ile imzalar, `grubx64.efi` olarak kurar, shim'i yerleştirir, geri dönüş kopyası tutar, ölü UKI'leri temizler |
| `/usr/bin/maze-kernel-install-add` | Çekirdek yükseltmesinde `kernel-install add` çalıştırır — stok Arch'ın hiç yapmadığı adım |
| `/usr/share/libalpm/hooks/85-maze-kernel-install.hook` | Çekirdek yazılınca UKI'yi yeniden kurar |
| `/usr/share/libalpm/hooks/zz-maze-secureboot.hook` | nvidia/dkms/mkinitcpio/systemd sonrası idempotent yeniden imzalama |
| `/usr/lib/kernel/install.d/95-maze-sb-sign.install` | Her `kernel-install add` sırasında satır içi imzalar |
| `maze-sb-resign.{service,path}` | pacman dışı çekirdek yazımları için kendi kendini onarma |
| `systemd-boot-update.service.d/99-maze-resign.conf` | `bootctl update` shim'i ezerse zinciri onarır |

Artık bir düzeltme `pkgrel++` ve `[mazelinux]`'a yayın demek.

### Eski kurulumların devralınması

Eski ISO'dan kurulmuş makineler aynı dosyaları `/etc` ve `/usr/local/bin`
altında taşıyor ve bunlar paketlenmiş olanları **gölgeliyor** — `/etc/pacman.d/hooks`
aynı adlı `/usr/share/libalpm/hooks` dosyasını ezer. pacman çakışma bildirmez,
çünkü yollar farklıdır. Paket kurulur ve hiçbir şey değişmezdi.

`maze-secureboot.install` bunu çözer: gölgeleyen kopyaları siler, eski
`/usr/local/bin` yollarına exec shim bırakır (pacman hook dizinlerini scriptlet
çalıştığında zaten okumuştur; eski hook'lar o transaction'da bir kez daha
ateşlenebilir), dangling enable symlink'lerini temizler ve zinciri yeniden kurup
imzalar.

---

## 2. İkinci çekirdek

`maze-meta` artık `linux-lts` ve `linux-lts-headers`'a bağımlı.

Tek çekirdekle bozuk bir güncelleme canlı USB demekti. İki çekirdekle önceki
bilinen-iyi imaj zaten ESP'de derlenmiş ve imzalanmış durumda duruyor.
`-headers` şart: `nvidia-open-dkms` ve `broadcom-wl-dkms` LTS için de
derlenmezse kurtarma çekirdeği ekransız ve wifisiz açılır.

### İkinci çekirdek artık gerçekten seçilebiliyor  ✅ kanıtlandı

Uzun süre eksik olan parça buydu: LTS kuruluydu, UKI'si üretilmişti, imzalıydı,
modülleri derlenmişti — ve **açmanın hiçbir yolu yoktu.** shim tek bir dosyayı
(`EFI/BOOT/grubx64.efi`) yükler, menü yoktur, ve firmware MOK ile imzalı bir
imajı doğrudan yükleyemez çünkü MOK'u doğrulayan şey shim'in kendisidir. Yani
kurtarma çekirdeği, canlı USB olmadan bozdurulamayan bir sigortaydı.

Çözüm shim'in kendi davranışını kullanıyor: **ikinci aşamayı kendi bulunduğu
dizinde arar.**

```
EFI/BOOT/BOOTX64.EFI           shim  →  EFI/BOOT/grubx64.efi           (boot çekirdeği)
EFI/maze-recovery/BOOTX64.EFI  shim  →  EFI/maze-recovery/grubx64.efi  (kurtarma çekirdeği)
```

`maze-sb-sign` her çalıştığında ikinci dizini güncel tutuyor ve firmware boot
menüsüne **Maze Linux (recovery kernel)** girişini bir kez ekliyor. MOK bir UEFI
değişkeninde durduğu için iki shim de aynı kaydı kullanır; yeniden kayıt yok.

Kurtarma çekirdeği seçimi otomatik: `linux-lts` kuruluysa o, değilse boot
çekirdeği **olmayan** herhangi bir kurulu çekirdek. Kullanıcı LTS'i boot
varsayılanı yaparsa kurtarma mainline olur — kopyası alınan şey hiçbir zaman az
önce bozulmuş imaj değildir.

Birincil zincire dokunulmuyor. Buradaki her hata uyarıdır, `status_ok`'i asla
düşürmez: kurtarma girişi yazılamasa bile normal boot etkilenmez. ESP alanı da
bu yüzden sıkı tutuluyor — kurtarma imajı, bir sonraki çekirdek güncellemesinin
birincil imajına yer bırakmayacaksa hiç yazılmıyor.

`maze-boot-check`'in 12. kontrolü bunu doğruluyor: imaj var mı, imzalı mı, kurulu
bir çekirdeğe mi işaret ediyor, ve NVRAM girişi duruyor mu.

**8 Eylül 2026:** gerçek donanımda denendi. Firmware boot menüsünden
*Maze Linux (recovery kernel)* seçildi, sistem LTS çekirdeğiyle açıldı. Yani
"iki çekirdeğimiz var" cümlesi artık gerçekten bir kurtarma yolu anlamına
geliyor.

### Acil durum kabuğu artık açılabiliyor

Buna bağlı ikinci bir tuzak vardı. Canlı ISO root'u **parolasız** taşıyor
(`root::`), Calamares `setRootPassword: false` ile kurulu ve unpackfs
`/etc/shadow`'u olduğu gibi kopyalıyor — yani kurulu sistemde TTY'de "root"
yazan herkes root olabiliyordu.

`deploy-to-target.sh` artık root'u kilitliyor, sonucu `passwd -S` ile doğruluyor
ve tutmadıysa `shadow`'u doğrudan düzeltiyor. Ama kilitli root tek başına ikinci
bir sorun yaratır: `sulogin` parolasız hesabı reddeder, yani başarısız bir mount
sonrası acil kabuk da kapalı kalır — insanın en çok kabuk istediği an.

Bu yüzden `maze-secureboot` `emergency.service` ve `rescue.service` için
`SULOGIN_FORCE=1` drop-in'i gönderiyor. Maze'de bunun güvenli olmasının sebebi
mühürlü cmdline: `systemd.unit=emergency.target` boot ekranında eklenemez, çünkü
eklenecek bir satır yok ve imajı düzenlemek imzayı bozar. Acil moda ancak
**gerçek bir arıza** ile girilir, saldırganın tetikleyebileceği bir yolla değil.
Varsayılan kurulumda disk zaten LUKS ile şifreli.

`maze-doctor` ikisini birlikte kontrol ediyor: root kilitli mi, ve acil kabuk
açılabiliyor mu.

---

## 3. Snapshot desteği

**`maze-snapshots`** — `snapper` + `snap-pac`.

Her `pacman` işleminin **öncesinde ve sonrasında** `@` subvolume'ünün btrfs
snapshot'ı alınır. Bozuk bir kütüphane, yarım kalan bir yükseltme ya da hatalı
bir `maze-*` paketi geri alınabilir hâle gelir.

Yapılandırmayı bir **boot-time oneshot** oluşturur, pacman scriptleti değil:
ISO derlemesi sırasında scriptlet airootfs'e karşı çalışır ve orada
yapılandırılacak btrfs kökü yoktur. Unit ilk açılışta çalışır, yapılandırma
varsa kendini atlar.

### Snapshot'ları görmek

`snapper` bir komut satırı aracıdır ve `/.snapshots` root'a aittir (750), yani
**root gerektirir**. Kullanıcı olarak çalıştırınca "No permissions" der:

```sh
sudo snapper -c root list          # snapshot'ları listele
sudo snapper -c root status 14..15 # iki snapshot arasındaki farkı gör
sudo snapper -c root undochange 14..15 /etc/foo.conf   # tek dosyayı geri al
```

Grafik arayüz isteyenler için `btrfs-assistant` (optdepend) kurulu.

Snapper'ın saatlik timeline'ı **bilerek kapalı** — bu paketin amacı pacman
snapshot'ları; timeline farklı disk profili olan ayrı bir karar. Açmak istersen:

```sh
sudo snapper -c root set-config TIMELINE_CREATE=yes
```

### Tam rollback henüz kapalı

Bugün alınan snapshot'lar **dosya düzeyinde** geri alma sağlıyor. Tam rollback
(`snapper rollback`) çalışmıyor, çünkü cmdline UKI'nin içinde mühürlü:

```
rootflags=subvol=/@
```

`snapper rollback` btrfs'in *varsayılan subvolume*'ünü değiştirir, ama boot her
seferinde `/@`'yi zorlar. Ayrıntı ve çözüm: `SNAPSHOT-BOOT.md`.

`maze-enable-rollback` bunu açan araç — yazıldı, test edildi, pakette duruyor,
ama **kurulum varsayılanı değiştirilmedi**. Kullanmak isteyene:

```sh
sudo maze-enable-rollback          # ne değişeceğini göster, dokunma
sudo maze-enable-rollback --apply  # uygula
sudo maze-enable-rollback --undo   # geri al
```

Cmdline'a dokunmadan önce btrfs varsayılanını ayarlayıp aygıtı geçici olarak
`subvol=` vermeden bağlar ve içinde `/usr`, `/etc` ve bir init var mı diye bakar
— yani "boot etmesi lazım" tahminini ölçüme çevirir. Kök bulunamazsa varsayılanı
geri alıp hiçbir şeye dokunmadan durur. `fstab`'ın `/` satırındaki `subvol=`
sabitlemesini de kaldırır (yoksa systemd rollback'i her boot'ta sessizce iptal
ederdi); `@home`, `@cache`, `@log`, `@swap` sabitlemeleri korunur.

---

## 4. Yeniden başlatmadan önce doğrulama

**`maze-boot-check`** — zinciri uçtan uca denetler:

1. Her kurulu çekirdeğin ESP'de UKI'si var mı
2. `grubx64.efi` modülleri diskte duran bir çekirdeği mi gösteriyor
3. İmajın içindeki çekirdek sürümü (PE `.uname`) işaretçiyle uyuşuyor mu
4. MOK imzası geçerli mi
5. shim yerinde mi
6. Secure Boot açıksa MOK kayıtlı mı
7. **LUKS kökünde `encrypt` hook'u var mı**
8. cmdline'daki UUID'ler gerçek cihazlara karşılık geliyor mu
9. btrfs varsayılan subvolume çalışan kökü gösteriyor mu
10. `layout=uki` yürürlükte mi
11. ESP'de bir sonraki UKI için yer var mı
12. `/etc` altında paketlenmiş dosyaları gölgeleyen kopya var mı

7. madde önemli: derlenmiş ve imzalanmış ama `encrypt` hook'u olmayan bir UKI
makineyi açar, disk açılamaz, parola sorulmaz — ve zincirin başka hiçbir katmanı
bunu fark etmez.

Her transaction'ın sonunda `zzz-maze-boot-verify.hook` ile çalışır. Başarısızsa
`/var/lib/maze/boot-unsafe` bayrağını yazar.

**`maze-boot-guard`** o bayrak varken logind shutdown inhibitor'ı tutar: Plasma
çıkış menüsü ve oturum içi `systemctl reboot` sebebiyle birlikte reddedilir.
`systemctl reboot -i` ve `reboot -f` bilerek serbesttir — yönetici kendi
makinesinde son sözü söyler, buradaki iş kararı bilgilendirmektir.

Yanında: girişte kritik masaüstü bildirimi, TTY/SSH için `/etc/profile.d`
uyarısı, ve boot'tan 3 dk sonra + günlük çalışan bir timer (pacman dışı
sürüklenmeyi yakalar).

---

## 5. Geri dönüş kopyası

shim yalnızca `grubx64.efi`'yi yükler — menü yok, sd-boot NVRAM girişi bilerek
kaldırılmış. Kötü bir çekirdek canlı USB dışında çıkış bırakmıyordu.

Giden imaj artık `grubx64.efi.maze-prev` olarak saklanıyor. Rotasyon **çekirdek
sürümü** değişince oluyor (`grubx64.efi.maze-kver` ile izleniyor), çünkü
imzalayıcı tek güncellemede üç kez çalışıyor ve her çalışmada döndürseydi
fallback'i tam da fallback olduğu imajla ezerdi.

```sh
cp -f /boot/EFI/BOOT/grubx64.efi.maze-prev /boot/EFI/BOOT/grubx64.efi
```

---

## 6. Sabitlenen çekirdek artık korunuyor

`maze-sb-sign` en yeni çekirdeği alıyor ve `/etc/maze/kernel-default`'u yok
sayıyordu — yani `maze-kernel-helper set-default` ile yaptığın seçim her çekirdek
güncellemesinde eziliyordu. Switcher bunu kullanıcıya uyarı olarak basmak zorunda
kalıyordu.

Artık pin onurlandırılıyor. Pin **tavsiye niteliğinde**: sabitlenen çekirdek
kurulu değilse ya da ESP'de UKI'si yoksa en yeniye düşülüyor ve sebebi
yazılıyor — yani pin makineyi hiçbir koşulda boot imajsız bırakamıyor.

---

## 7. Sistem teşhis aracı

**`maze-doctor`** (`maze-tools` içinde) — 18 bölümde Maze'in Arch üstüne koyduğu
her katmanı denetler. Salt-okunur; inceler, onarmaz. Her bulgu düzeltme komutunu
basar.

```sh
sudo maze-doctor              # tam kontrol
sudo maze-doctor --deep       # her kurulu dosyayı paketiyle karşılaştır (yavaş)
maze-doctor --no-color        # hata bildirimi için düz metin
```

Kapsam: boot zinciri, çekirdekler ve DKMS modülleri, Maze paketleri ve gölgeleme,
markalama ve kimlik, çekirdek komut satırı ve initramfs hook'ları, pacman
yapılandırması ve imza politikası, **canlı ortam kalıntıları** (installer,
parolasız sudo, autologin, canlı kullanıcı — gerçek bir kurulumda güvenlik açığı
sınıfı), depolama ve ESP alanı, dosya sistemi ve btrfs bütünlüğü, snapshot'lar,
systemd birimleri, güvenlik duruşu, journal'daki çekirdek hataları, ve her diskte
SMART.

Çıkış kodu: temizse 0, sadece uyarı varsa 2, ilgilenilmesi gereken bir şey varsa 1.

---

## 8. Kök sebebinden düzeltilen üç hata

**`maze-installer` kurulu masaüstünde kalıyordu.** Deploy scripti dosyalarını tek
tek siliyor ama paketi bırakıyordu: pacman veritabanında ölü bir kayıt, her
`pacman -Qkk`'de "eksik dosya", ve sadece kurulum için çekilen `calamares` +
`xorg-xhost` masaüstünde asılı. Artık hedef chroot'ta `pacman -Rns` ile düzgün
kaldırılıyor.

**`maze-guard` kendi kendiyle çelişiyordu.** PKGBUILD dosyaları 644 kuruyor,
`.install` scripti sonra tüm ağacı `chmod 644` yapıyordu — paket veritabanı
diskle kalıcı olarak uyuşmuyordu. Artık paket doğru modları kuruyor, scriptlet
sadece pip'in ürettiği venv'i normalize ediyor, uygulama ağacına dokunmuyor.

**`maze-cloak` ilk kurulumda çalışmıyordu** — ve sebebi tüm uygulamaları
kapsıyordu. `unpackfs` canlı sistemi `/var/lib/pacman` dahil kopyaladığı için her
Maze uygulaması hedefe "zaten kurulu" geliyor; `pacman -S --needed` hepsini
atlıyor ve **hiçbir `.install` scripti hedefte çalışmıyor**. Dosyalar ve venv'ler
kopyayla taşınıyor ama `sysusers.d`'deki gruplar ve `tmpfiles.d`'deki
sahiplik/izinler taşınamıyor. `maze-cloak` `g maze -` ve
`d /etc/maze-cloak 0775 root maze` beyan ettiği için grup oluşmuyor ve config
dizini `root:root` kalıyordu. Artık hedefte `systemd-sysusers` ve
`systemd-tmpfiles --create` çalıştırılıyor, grup üyelikleri de paketlerin kendi
beyanlarından türetiliyor.

---

## 9. Yayın sırası artık kodda

**`publish.sh`** PKGBUILD'lerden paket adı ↔ dizin haritasını çıkarır, bağımlılık
grafiğini topolojik sıralar ve yayınlanmayan bağımlılıkları uyarır.

`maze-meta` diğer her maze paketine bağımlı. Repoya ondan önce giderse her
kurulu makinenin `pacman -Syu`'su "target not found" ile patlar. Bu bilgi artık
akılda değil, kodda.

```sh
./publish.sh maze-secureboot maze-snapshots maze-guard maze-tools maze-installer
```

---

## Yapılmayanlar

- **Otomatik kurtarma (boot counting)** — kurtarma çekirdeği artık boot
  menüsünden seçilebiliyor, ama seçen bir **insan** olmak zorunda. Makinenin
  açılamadığını fark edip kendiliğinden geri dönmesi için boot counting gerekir
  (imaj üç kez denenir, `boot-complete.target`'a ulaşılamazsa öncekine dönülür),
  o da zincire systemd-boot'un girmesini gerektirir. Sıradan kullanıcı için
  doğru kurtarma budur; menü ikinci en iyisi. systemd-boot'un çıkarılma sebebi
  katı firmware'lerin (MSI/ASUS) gevşek çekirdek için MOK'u yok sayması; geri
  koymak OVMF secboot'ta ve gerçek donanımda test gerektirir.
- **Kurtarma UKI'si (Faz B2)** — snapshot seçebilen bir kurtarma initramfs'i.
  Tasarımı `SNAPSHOT-BOOT.md`'de, kodu yok.
- **Faz A kurulum varsayılanı** — `maze-enable-rollback` var ama yeni ISO'lar hâlâ
  `rootflags=subvol=/@` ile çıkıyor.
- **VM yükseltme testi** — en önemli eksik. Kurulu bir imaj alıp üzerinde
  `pacman -Syu` + reboot koşturan bir CI adımı. Bu çalışma boyunca dört turda
  elle bulunan hata sınıfının (imza katmanı farkı, `enable`/`start` ayrımı,
  izin yönünün ters çevrilmesi) hepsini tek seferde yakalardı.
- **Modül imzalama** — nvidia/dkms modülleri imzasız. Arch çekirdeği lockdown'ı
  zorlamadığı sürece zararsız.

# Kod Denetimi — Bulgular

**Tarih:** 8 Eylül 2026
**Yöntem:** `MAZE-TAM-REFERANS.md`'deki sıra takip edilerek, belgedeki her
iddianın kaynak kodda karşılığı arandı.

Beş sorun bulundu, **beşi de düzeltildi.** Aşağıda her biri için ne olduğu,
neden önemli olduğu, ne yapıldığı ve nasıl doğrulandığı yazılı.

---

## Kapsam

**İncelenen** (referans belgesinin 2–8. bölümleri, yani kod taşıyan kısımlar):

- `maze-secureboot` — `maze-sb-sign`, `maze-boot-check`, `maze-boot-entries`,
  `maze-boot-guard`, hook'lar ve systemd birimleri
- `maze-snapshots` — `maze-snapshots-setup`, `maze-enable-rollback`,
  `maze-rollback`
- `maze-tools` — `maze-doctor`, `maze-guardd` (kill switch yolu),
  `maze-tools.install`
- `maze-installer` — `deploy-to-target.sh` (root kilidi ve NVRAM bölümleri)
- `publish.sh`, `maze-meta`
- Referans belgesindeki tüm sayısal iddialar

**İncelenmeyen** — bu denetimin sınırı, bilinerek:

- Uygulamaların iç kodu: `haze`, `hazedrop`, `qlam`, `entropy-shield`,
  `maze-ai`, `maze-connect`. Özellikle `haze` ve `hazedrop`'un **kriptografisi
  denetlenmedi** ve ikisinin de testi yok (bkz. `MAZE-TAM-REFERANS.md` 9.6).
- `maze-guard`'ın tespit motoru ve GUI'si (285 testi var, mekanik olarak
  kapsanıyor)
- Plasma yapılandırması, marka dosyaları

---

## Bulgu 1 — `maze-rollback --undo` hiçbir zaman çalışamıyordu  🔴 CİDDİ

**Dosya:** `maze-snapshots/.../usr/bin/maze-rollback`

**Neydi:** Akış şöyleydi:

1. btrfs varsayılanı çalışan kökten farklı mı diye bakılıyor
2. Farklıysa *"rollback zaten hazırlanmış — reboot et, ya da
   `sudo maze-rollback --undo` ile geri al"* yazıp **`exit 1`**
3. `--undo` işlemesi bu çıkışın **altında**

**Neden önemli:** Araç kullanıcıya, çalışması imkânsız bir komut söylüyordu.
Hazırlanmış bir rollback'i iptal etmek isteyen kişi `--undo` çalıştırıyor, aynı
mesajı tekrar alıyor, hiçbir şey olmuyor.

Bu, `snapper rollback`'in *"Cannot detect ambit"* deyip sessizce hiçbir şey
yapmamasıyla aynı sınıfta bir hata — ki `maze-rollback` zaten **onu** düzeltmek
için yazılmıştı.

**Yapılan:** `--undo` bloğu, hazırlanmış-rollback kontrolünün **önüne** taşındı.
Hazırlanmış bir rollback, undo'nun var olma sebebidir; onu önce kontrol etmek
aracı kendi tavsiyesini reddeder hâle getiriyordu. Koda gerekçe yorumu eklendi.

**Doğrulama:** `UNDO=1` ve `cur_id≠def_id` durumunda undo yolunun çalıştığı
sınandı.

---

## Bulgu 2 — Çökme sınıflandırıcısında çalışmayan desen  🟡

**Dosya:** `maze-tools/.../usr/local/bin/maze-doctor`

**Neydi:** Yeni Stability bölümündeki `case` deseni:

```sh
*"CPU.*throttled"*)
```

`case` **glob** kullanır, regex değil. `.` ve `*` burada düz karakterdir, yani
bu desen yalnızca birebir `CPU.*throttled` metnine uyar — gerçek çekirdek
mesajlarının hiçbirine uymaz.

**Neden önemli:** Aşırı ısınmadan kaynaklanan bir donma "belirsiz" olarak
raporlanırdı. Etkisi sınırlıydı çünkü aynı satırdaki `*thermal*` deseni çoğu
durumu zaten yakalıyordu — ama sınıflandırma eksik kalıyordu.

**Yapılan:** `*throttl*` ile değiştirildi ve neden regex yazılamayacağı koda
not düşüldü.

**Doğrulama:** `CPU 3 throttled`, `thermal throttling detected`,
`temperature above threshold` üçü de eşleşiyor.

---

## Bulgu 3 — `maze-boot-entries` rastgele bölümleri bağlamayı deniyordu  🟡

**Dosya:** `maze-secureboot/.../usr/bin/maze-boot-entries`

**Neydi:** Bir boot girişinin gerçekten bir yükleyiciye işaret edip etmediğini
anlamak için bağlı olmayan bölüm geçici olarak salt-okunur bağlanıyordu:

```sh
mount -o ro,nosuid,nodev,noexec "$_dev" "$_tmp"
```

Dosya sistemi türü belirtilmediği için `mount` sırayla **her** dosya sistemi
sürücüsünü dener.

**Neden önemli:** Bozuk veya beklenmedik bir bölümde bu uzun süre bloke
olabilir. Salt-okunur bir rapor üretmesi gereken araç, kullanıcının önünde
donabilirdi.

**Yapılan:** `-t vfat` eklendi. EFI sistem bölümü her zaman vfat'tır; türü
belirtmek başka her şeyde `mount`'un anında başarısız olmasını sağlar.

---

## Bulgu 4 — `maze-boot-check` doğrulamadığı bir şeyi iddia ediyordu  🟡

**Dosya:** `maze-secureboot/.../usr/bin/maze-boot-check`, 12. kontrol

**Neydi:** Kurtarma girişi kontrolünde `efibootmgr` yoksa veya `efivars`
erişilemezse akış `else` dalına düşüyor ve şunu yazıyordu:

```
[ OK ]  Recovery entry present - selectable from the firmware boot menu
```

Oysa NVRAM girişinin varlığı **hiç kontrol edilmemişti.**

**Neden önemli:** Bu, projenin kendi standardının ihlali. `posture.py`'da
"bilinmeyen `None`'dır, asla `False` değil" kuralı var; `maze-boot-entries`
"bakamadım"ı "ölü" saymıyor. Aynı titizlik burada uygulanmamıştı — ve bu, bir
kurtarma yolunun varlığına dair yanlış güven verir.

**Yapılan:** Doğrulanamayan durum ayrı bir dala alındı. Artık imajın hazır
olduğunu söylüyor ama **firmware girişini okuyamadığını açıkça belirtiyor.**

---

## Bulgu 5 — Paket kaldırılınca kamera kalıcı olarak kapalı kalıyordu  🟠

**Dosya:** `maze-tools/maze-tools.install`

**Neydi:** Kamera kesme anahtarı `/etc/modprobe.d/maze-killswitch-camera.conf`
yazarak çalışır ve bu **bilerek kalıcıdır.** Ama `post_remove` bu dosyayı
silmiyordu.

**Neden önemli:** Kamerasını kapatmış bir kullanıcı `maze-tools`'u kaldırdığında
kamera ölü kalıyor **ve onu geri açacak araç da gitmiş oluyor.** Kullanıcının
elinde ne kamera ne de sebebini gösteren bir şey kalıyor.

Bu, daha önce yaşanmış bir hatanın aynısı: `boot-unsafe` bayrağı ISO'ya
sızdığında her taze kurulum kapanmayı reddediyordu. `maze-secureboot` dersi
almış ve `post_remove`'unda o bayrağı siliyor — `maze-tools` almamıştı.

**Yapılan:** `post_remove` artık kara listeyi siliyor, `uvcvideo`'yu geri
yüklüyor ve kullanıcıya kameranın yeniden çalıştığını söylüyor.

---

## İncelenip temiz çıkanlar

Bunlar kontrol edildi ve sorun bulunmadı — sonraki denetimde tekrar bakılması
gerekmesin diye kayda geçiyor:

| Kontrol | Sonuç |
|---|---|
| `maze-sb-sign` çalışma sırası: imzalama döngüsü kurtarma bloğundan önce mi | ✅ Doğru sırada — LTS UKI imzalanmadan kurtarma girişi üretilmiyor |
| `prune_stale_ukis` kurtarma imajını siler mi | ✅ Silmiyor; farklı dizinde ve çekirdek kurulu olduğu için UKI'si de korunuyor |
| `ensure_recovery_nvram`'ın kullandığı `lsblk` sütunları | ✅ `PARTN` ve `PKNAME` bu util-linux sürümünde çalışıyor |
| BootOrder geri yükleme mantığı | ✅ Beş senaryoda orijinal sıra korunuyor, yeni giriş sona ekleniyor |
| `recovery_kver` seçimi | ✅ Beş senaryo doğru; boot çekirdeği asla kurtarma olarak seçilmiyor |
| `snapshots_subvol` yol türetmesi | ✅ Sekiz senaryo doğru, rollback sonrası durum dahil |
| Stability: olmayan boot için sayım | ✅ `journalctl` 1 döndürüyor, sayım şişmiyor |
| `deploy-to-target.sh` root kilidi kapsamı | ✅ Fonksiyon dışında, `local` kullanılmıyor |
| `set -e` ile `[ -d X ] && rm -rf X` kalıbı | ✅ AND listesinde son komut değil, muaf |
| Referans belgesindeki tüm sayılar | ✅ Beşi de kaynakla birebir |
| `maze-doctor` çıkış kodu 2 | ✅ Hata değil — "uyarı var" konvansiyonu (satır 981) |

---

## Düzeltilmeyen, düşük öncelikli

**`maze-boot-entries`'te boş anahtar kenar durumu.** Bir boot girişinin
`File()` kısmı hiç yoksa `key` yalnızca etiket + sekme olur ve `SEEN`
listesindeki baştaki boş satırla teorik olarak eşleşebilir. Gerçek bir EFI
girişinin yükleyici yolu olmadan var olması pratikte mümkün değil; not olarak
duruyor.

---

## Yayınlanacak paketler

| Paket | Sürüm | İçerdiği düzeltme |
|---|---|---|
| `maze-snapshots` | 1.1.0-**2** | Bulgu 1 |
| `maze-tools` | 1.1.0-**25** | Bulgu 2, Bulgu 5 |
| `maze-secureboot` | 1.2.0-**11** | Bulgu 3, Bulgu 4 |

Bekleyen diğerleri (önceki oturumdan): `maze-guard 2.16.0-1`,
`maze-installer 2.0.0-18`.

---

## Sonraki denetim için

Bu denetim boot ve sistem katmanını kapsadı. **Uygulamaların iç kodu
incelenmedi.** Sıradaki en değerli denetim `haze` ve `hazedrop`'un
kriptografisidir: ikisi de kendi şifrelemesini yapıyor
(ChaCha20-Poly1305, Argon2id), ikisinin de **sıfır testi** var, ve kripto tam
olarak gözle bakınca doğru görünen ama sessizce yanlış olabilen kod türüdür.

---

# İkinci Tur — Güvenlik Denetimi

**Tarih:** 8 Eylül 2026 (birinci turdan sonra)
**Odak:** Ayrıcalık sınırları, zafiyet, yetki yükseltme

Bu tur ilkinden farklı bir soru sordu: *"yetkisiz bir kullanıcı bu sistemde
root olabilir mi?"*

**İki bulgu çıktı, ikisi de düzeltildi.** Daha önemlisi: aranan ciddi
zafiyetler **bulunamadı** — aşağıda neyin kontrol edildiği tek tek yazılı, ki
bir sonraki denetim aynı yeri tekrar kazmasın.

---

## Bulgu 6 — Ayar dosyası her kaydetmede `maze` grubundan çıkıyordu  🟠

**Dosya:** `maze-cloak/mazecloak/core/config.py`, `save_config()`

**Neydi:** `tmpfiles.d` şunu beyan ediyor:

```
z /etc/maze-cloak/config.json 0664 root maze -
```

Amaç: `maze` grubundaki **her** kullanıcı MAC ayarlarını değiştirebilsin.

Ama `save_config` geçici dosyaya yazıp `os.replace` yapıyor. `rename` inode'u
korur — yani hedef, geçici dosyanın **hem modunu hem sahipliğini** devralır.
Kodda mod açıkça ayarlanmış (`chmod 0o664`) ama **sahiplik ayarlanmamış.**

Gerçek makinede sonuç:

```
775 root:maze              /etc/maze-cloak          ← doğru
664 berkkucukk:berkkucukk  /etc/maze-cloak/config.json  ← olması gereken: root:maze
```

**Neden önemli:** İzinler doğru *görünüyor* ve tek kullanıcılı makinede hiçbir
şey bozulmuyor. Ama ikinci bir `maze` üyesi ayarları kaydedemez hâle geliyor —
sessizce. Dosya ancak bir sonraki açılışta `systemd-tmpfiles` çalışınca
`root:maze`'e dönüyor, yani sorun oturum boyunca sürüyor ve reboot'ta kayboluyor;
teşhis edilmesi en zor tipteki hata.

Bu, daha önce yaşanan maze-cloak GID olayıyla aynı sınıf: dosya sayısal bir
GID'e ait kalmış ve uygulama başlamamıştı.

**Yapılan:** `os.replace`'ten önce grup açıkça `maze` yapılıyor. Root
çalıştırıyorsa sahip de root'a çekiliyor; normal kullanıcı çalıştırıyorsa
sahip `-1` ile bırakılıyor (kendi dosyasını root'a veremez, ama üyesi olduğu
gruba verebilir — paylaşımı sağlayan kısım zaten bu).

**Doğrulama:** Üç yeni test — ilk kayıt, mod korunması, ve **ikinci kayıt**
(asıl kayan yol buydu). `maze` grubu yoksa veya kullanıcı üye değilse testler
atlanıyor.

---

## Bulgu 7 — Soket ile dizini iki farklı grup kapılıyordu  🟡

**Dosya:** `maze-tools/.../usr/local/bin/maze-guardd`

**Neydi:** Gerçek makinede:

```
drwxr-x---  root:maze   /run/maze          ← maze-guard'ın helper'ı ayarlıyor
srw-rw----  root:wheel  /run/maze/guard.sock   ← maze-guardd ayarlıyor
srw-rw----  root:maze   /run/maze/maze.sock
```

`guard.sock` `wheel` grubuna açık, ama içinde bulunduğu dizin `maze` grubuyla
kapılı. Yani gerçek gereksinim **"wheel VE maze"** iken kod "wheel" olduğunu
sanıyordu.

**Neden önemli:** Güvenlik açığı değil — daha kapalı, daha açık değil. Ama
`maze` grubuna eklenmiş ikinci bir hesap (ki belgelerde "Maze grubu" diye geçen
budur) donanım kesme anahtarlarını **sessizce** kullanamaz hâle gelirdi. İlk
kullanıcı ikisine birden eklendiği için gizli kalmıştı.

**Yapılan:** Soket artık `maze` grubunu kullanıyor — `sysusers.d`'nin
oluşturduğu, yanındaki helper soketini kapılayan ve Maze Cloak'un config'ine
sahip olan grup bu. `wheel` sudo grubudur, başka bir şey ifade eder. `maze`
yoksa `wheel`'e düşüyor, eski sistemler çalışmaya devam etsin diye.

---

## Aranan ve BULUNAMAYAN zafiyetler

Bunlar ciddi şekilde arandı ve temiz çıktı. Sonraki denetim buraları tekrar
kazmasın diye kayda geçiyor.

| Kontrol | Sonuç |
|---|---|
| **MOK özel anahtarı** okunabilir mi | ✅ `/var/lib/maze-secureboot` = `700 root:root`, anahtar `600`. Root dışı okuyamaz. Okunabilseydi tüm Secure Boot zinciri çökerdi |
| Root daemon'larda **kabuk kullanımı** | ✅ `shell=True`, `os.system`, `eval`, `exec` — hiçbiri yok. Her komut sabit argv |
| Çağıran kimliği **sahtelenebilir mi** | ✅ `SO_PEERCRED` kullanılıyor, mesajdan uid alınmıyor |
| `fw_cmd` **argüman enjeksiyonu** | ✅ `args[0]` birebir `firewall-cmd` olmak zorunda; kalan her argüman whitelist veya `^...$` ile **tam sabitlenmiş** regex. Yazar önek-eşleşme tuzağını bilmiş ve yoruma yazmış |
| `--set-default-zone` ile firewall bypass | ✅ Bilerek whitelist dışı, gerekçesi yorumda |
| `svc` ile **keyfi birim** durdurma | ✅ `_SVC_ALLOWED` whitelist |
| `sysctl_set` ile **keyfi çekirdek ayarı** | ✅ `_SYSCTL_ALLOWED` whitelist + değer yalnız rakam |
| Grup-yazılabilir config → root daemon | ✅ `O_NOFOLLOW` (symlink saldırısı), 64 KB okuma sınırı, `from_dict` → `sanitised()`, ve `nm.render()` ayrıca yeniden doğruluyor |
| Canlı ortamın **parolasız sudo**'su kuruluma sızıyor mu | ✅ `deploy-to-target.sh` `10-maze`, pkexec kuralı, autologin — hepsini siliyor, "SECURITY: do not remove" notuyla |
| polkit politikası | ✅ Yıkıcı işlemler `auth_admin`; aktif oturumda `auth_admin_keep` |
| Paketlerde **setuid/setgid/dünya-yazılabilir** dosya | ✅ Beş pakette de sıfır |
| `/etc/maze/kernel-default` (boot pini) kim yazabilir | ✅ `644 root:root`, dizin `755 root:root` — yalnız root |
| Daemon'da **DoS**: sınırsız okuma | ✅ `recv(256)`, `settimeout(5)`, `conn.close()` `finally`'de |

---

## Düşük öncelikli, düzeltilmedi

**`re.match(r'^\d+$', value)`** — Python'da `$` satır sonundan **önceki** yeni
satırla da eşleşir, yani `"1\n"` geçer. Değer tek bir argv elemanına gittiği
için enjeksiyon değil ve `sysctl` sondaki yeni satırı zararsız işliyor.
Doğrusu `re.fullmatch`; kozmetik.

---

## Genel değerlendirme

Ayrıcalıklı daemon'lar **iyi yazılmış.** `SO_PEERCRED`, whitelist doğrulama,
sabit argv, tam sabitlenmiş regexler, polkit onayı, denetim kaydı, `O_NOFOLLOW`,
okuma sınırları — bunların hepsi zaten yerinde ve çoğunun gerekçesi kodda
yazılı. Kapatılmış eski zafiyetlerin notları bile duruyor
(`--set-default-zone`).

İki turda bulunan yedi sorunun **hiçbiri yetki yükseltme değildi.** Beşi mantık
hatası, ikisi izin/grup tutarsızlığı.

Denetlenmemiş asıl alan hâlâ aynı: `haze` ve `hazedrop`'un kriptografisi.

---

## Yayınlanacak paketler (güncel)

| Paket | Sürüm | İçerdiği |
|---|---|---|
| `maze-tools` | 1.1.0-**26** | Bulgu 2, 5, 7 |
| `maze-cloak` | 1.2.1-**1** | Bulgu 6 |
| `maze-secureboot` | 1.2.0-**11** | Bulgu 3, 4 |
| `maze-snapshots` | 1.1.0-**2** | Bulgu 1 |
| `maze-guard` | 2.16.0-**1** | (önceki oturum) |
| `maze-installer` | 2.0.0-**18** | (önceki oturum) |

---

# Üçüncü Tur — Gerçek Bir Güncellemenin Çıktısından

**Tarih:** 8 Eylül 2026
**Tetikleyen:** 69 paketlik bir `pacman -Syu` çıktısında hata gibi görünen satırlar

Sistem sağlamdı — `boot-unsafe` bayrağı yazılmamıştı, imzalama başarılıydı,
kurtarma girişi günceldi, hiçbir birim başarısız değildi. Ama çıktı okuyan biri
için felaket gibi görünüyordu. İki gerçek sorun çıktı.

## Bulgu 8 — `/.snapshots` fstab girdisi hiçbir zaman eklenmiyordu  🟠

**Dosya:** `maze-snapshots/.../usr/bin/maze-snapshots-setup`

**Neydi:** Kontrol şuydu:

```sh
btrfs subvolume list / | awk -v want="@/.snapshots" '$NF == want {...}'
```

Ama `btrfs subvolume list`, yolu **sorguladığın subvolume'e göreli** yazar. `@`
içinden bakıldığında depo `.snapshots` diye listelenir — `@/.snapshots` diye
değil. Tam eşleşme bu yüzden hiç tutmuyordu.

Çıktıdaki mesaj: `no @/.snapshots subvolume yet — skipping the /.snapshots entry`

**Neden önemli:** Mesaj meşru bir atlama gibi okunuyor, oysa hata. Sonuç:
`/.snapshots`'ı fstab'dan bağlama düzeltmesi — ki tüm amacı rollback sonrası
snapper'ın kör kalmasını önlemekti — **hiçbir makinede uygulanmadı.** Sessizce.

Bu, bu projede tekrar eden bir kalıp: bir kontrolün başarısızlığı, normal bir
durum gibi raporlanıyor.

**Yapılan:** `btrfs` çıktısını ayrıştırmayı bıraktım. Her btrfs subvolume'ün
kökü **inode 256**'dır — yetki gerektirmeyen, ayrıştırma istemeyen ve
btrfs-progs biçimlendirmesiyle değişmeyen bir gerçek.

**Doğrulama:** Gerçek makinede `/.snapshots`, `/` ve `/home` subvolume olarak;
`/etc` ve `/tmp` değil olarak doğru tespit ediliyor.

## Bulgu 9 — Boot hook'u her güncellemede sahte ERROR basıyordu  🟡

**Dosya:** `maze-branding/.../hooks/90-maze-plymouth-update.hook`

**Neydi:** Hook `mkinitcpio -P || true` çalıştırıyordu ve çıktıya şunu
basıyordu:

```
==> ERROR: No presets found in /etc/mkinitcpio.d
```

`|| true` sayesinde hiçbir şeyi bozmuyordu. Ama **boot-kritik bir hook'un
ortasında, her güncellemede** görünen bir ERROR satırı, okuyan için gerçek bir
arızadan ayırt edilemez.

**Neden kaldırıldı, susturulmadı:** UKI sisteminde `mkinitcpio -P`'nin boot
açısından hiçbir işlevi yok. Hook'un kendi yorumu ve `linux.preset`'in içindeki
uzun açıklama bunu zaten söylüyor: Maze `shim → grubx64.efi (UKI)` ile açılır,
BLS girdisi ve menü yoktur, dolayısıyla hiçbir gevşek initramfs bu sistemde
yüklenmez. Tutulma gerekçesi "fallback girdisi kaymasın"dı — ama kayacak bir
fallback girdisi yok.

**Yapılan:** Çağrı hook'tan çıkarıldı, gerekçesi yerine yazıldı. `kernel-install`
gerçek imajı (UKI) zaten yeniden üretiyor; hook'un asıl işi buydu.

## Not — düzeltilmedi, bilinsin

**`linux-lts.preset` boşaltılmamış.** `linux.preset` bilerek `PRESETS=()` ile
gelir; içindeki açıklama gerekçeyi anlatır: UKI sisteminde gevşek imajlar hiç
boot edilmez ve **her çekirdek güncellemesinde ESP'de 250-400 MB** boşa gider.
`linux-lts` aynı muameleyi görmemiş, o yüzden her LTS güncellemesinde
`/boot/initramfs-linux-lts.img` üretiliyor.

Boot'a etkisi yok, sadece israf ve tasarımla tutarsızlık. ESP'de yer varken
(bu makinede %48 dolu) acil değil. Canlı bir makinede preset davranışını
değiştirmek daha önce bir kurulumu bozduğu için, bilerek ertelendi.

## Yayınlanacak (bu turdan)

| Paket | Sürüm | Bulgu |
|---|---|---|
| `maze-snapshots` | 1.1.0-**3** | 8 |
| `maze-branding` | 1.5.0-**3** | 9 |

---

# Dördüncü Tur — Taze ISO Kurulumunun Loglarından

**Tarih:** 8 Eylül 2026
**Kaynak:** Yeni ISO ile temiz kurulum + `maze-gpu-driver` + iki `maze-doctor` koşumu

## Sahada doğrulananlar

Bu loglar, günün düzeltmelerinin **taze bir kurulumda** çalıştığını gösterdi:

| Doğrulanan | Kanıt |
|---|---|
| Kurtarma girişi kurulumda oluşuyor | `Recovery entry present (kernel 6.18.49-3-lts) - selectable from the firmware boot menu` |
| Root kilidi çalışıyor | `root account is locked (login is via sudo)` |
| Acil kabuk erişilebilir | `Emergency shell is reachable without a root password` |
| Bulgu 8 gerçekten düzeldi | `maze-snapshots: adding a /.snapshots entry for subvol=@/.snapshots` → `mounted` |
| Bulgu 9 gerçekten düzeldi | `ERROR: No presets found` artık çıkmıyor |
| Kamera kontrolü doğru çalışıyor | `No camera device found` + `Nothing in Maze is blocking it` (bu makinede kablo gerçekten takılı değil) |
| NVIDIA kurulumu boot'u bozmuyor | `maze-gpu-driver` sonrası zincir doğrulandı, `0 failures` |

## Bulgu 10 — Mikrofon mesajı suçu Maze'e atıyordu  🟡

`maze-doctor` şunu yazıyordu: *"Maze Hardware can mute it. Unmute in Maze
Hardware"*. Kullanıcı Maze Hardware'e gidiyor, orada kapalı bir şey bulamıyor.

Çünkü **mikrofonun susturulması diskte iz bırakmaz.** Kameranın aksine
(modprobe.d dosyası) mikrofonda okunacak bir işaret yok: ALSA'nın kendi
varsayılanı, dizüstünün Fn sessize alma tuşu ve Maze Hardware **birebir aynı
durumu** üretir.

Üstelik bu ilk görüldüğü makinede mikrofon susturulmuş bile değildi — ekran
tamiri sonrası **fiziksel olarak takılı değildi.** Yani mesaj kullanıcıyı tam
tersi yöne gönderiyordu; oysa bu kontrolün var olma sebebi "bu Maze değil"
diyebilmekti.

**Yapılan:** Olguyu bildiriyor, üç olası sebebi sayıyor, hiçbirini iddia
etmiyor: *"Could be the Fn mute key, an ALSA default, or Maze Hardware — Maze
leaves no record either way."*

## Bulgu 11 — Taze kurulumda çözümü olmayan bir uyarı  🟡

`No rollback image (grubx64.efi.maze-prev)` her taze kurulumda **uyarı** olarak
çıkıyor ve "Worth a look" listesine giriyor — ama kullanıcının yapabileceği bir
şey yok, mesajın kendisi de "ilk çekirdek değişimine kadar normal" diyor.

Dahası artık yanlış: `.maze-prev` eskiden önceki çekirdeğe dönmenin **tek**
yoluydu. Kurtarma girişi geldiğinden beri değil — ve kurtarma girişi daha iyi
bir yedek, çünkü modülleri diskte duruyor (döndürülmüş bir `.maze-prev` bunu
garanti edemez).

**Yapılan:** Üç durumlu hâle getirildi. Kurtarma girişi varsa bu bir bilgi
(`[ -- ]`), ikisi de yoksa gerçek bir uyarı (*"There is no prepared way back to
another kernel"*).

## Bulgu 12 — Kalıcı, beklenen bir farkı uyarı olarak göstermek  🟡

`/etc/skel` altındaki üç dosya (`plasma-org.kde.plasma.desktop-appletsrc`,
`mimeapps.list`, `kdeglobals`) kurulumda **bilerek** düzenleniyor: Calamares
başlatıcısı panelden çıkarılıyor ve varsayılan tarayıcı ayarlanıyor. İkisi de
canlı imajın taşıdığı hâlde olamaz ve `unpackfs` kopyaladıktan sonra yapılmak
zorunda.

Sonuç: `pacman -Qkk` bunları **her makinede, sonsuza kadar** değişmiş gösteriyor
ve `maze-doctor` her koşumda aynı uyarıyı basıyordu.

Hep aynı uyarıyı gösteren bir sağlık raporu, okuyucuya uyarılar bölümünü
atlamayı öğretir — ki gerçek uyarılar tam orada çıkar.

**Yapılan:** Bu üç dosya filtreleniyor ve sebebi yazılıyor. **Gerçek farkları
gizlemiyor:** başka bir dosya da değişmişse o raporlanıyor, filtre yalnızca
"sadece beklenen üç dosya" durumunda devreye giriyor. Üç senaryoda sınandı.

## Yayınlanacak (bu turdan)

| Paket | Sürüm | Bulgu |
|---|---|---|
| `maze-tools` | 1.1.0-**27** | 10, 11, 12 |

---

# Beşinci Tur — Kriptografi Denetimi

**Tarih:** 8 Eylül 2026
**Kapsam:** `hazedrop` ve `haze` — kendi şifrelemesini yapan, sıfır testi olan
iki uygulama. Dört turdur "sıradaki en değerli denetim" diye işaretlenen alan.

**Bir ciddi zafiyet, iki sertleştirme.** Kriptografinin kendisi büyük ölçüde
doğru çıktı; sorun kriptonun *etrafındaydı*.

---

## Bulgu 13 — Gönderen, alıcının diskinde dosyanın nereye yazılacağını seçebiliyordu  🔴 CİDDİ

**Dosya:** `HazeDrop/hazedrop/core/receiver.py`, `core/crypto.py`

**Neydi:** Alınan dosyanın adı, şifrelenmiş başlıktan okunup doğrudan yola
çevriliyordu:

```python
filename, plaintext = decrypt_file_chunked(encrypted_data, key)
out_path = os.path.join(output_dir, filename)
```

Chunk'lar AEAD ile korunuyor ama **başlık korunmuyor**, ve dosya adını
**gönderen belirliyor**. Hiçbir temizleme yoktu.

İki saldırı biçimi, ikincisi Python'a özgü ve daha sinsi:

```
os.path.join("~/Downloads", "../../.config/autostart/evil.desktop")
    -> ~/.config/autostart/evil.desktop

os.path.join("~/Downloads", "/home/kullanici/.bashrc")
    -> /home/kullanici/.bashrc        # dizin TAMAMEN atiliyor
```

`os.path.join`, ikinci argüman mutlak yolsa ilkini sessizce atar.

**Neden ciddi:** Alıcı kullanıcı olarak **keyfi dosya yazma**. `~/.bashrc` veya
`~/.config/autostart/*.desktop` yazmak, bir sonraki oturumda **kod çalıştırma**
demektir. Kullanıcı "bir dosya indiriyorum" sanırken gönderen makinesine kalıcı
erişim bırakabilir.

Tehdit modeli açısından kritik ayrım şu: gönderenin **içeriği** belirlemesi
beklenen ve kabul edilen şeydir — dosyayı zaten ondan alıyorsunuz. Gönderenin
**nereye yazılacağını** belirlemesi değildir.

**Yapılan — iki katman:**

1. `crypto.py`'ye `safe_filename()`: her iki ayraç türü temizleniyor (gönderen
   Linux'ta olmak zorunda değil, `..\..\x` `basename`'i geçerdi), yalnızca son
   bileşen alınıyor, kontrol karakterleri atılıyor, saf nokta adları
   reddediliyor, 255 karaktere kırpılıyor. Çağrı yerinde değil,
   `decrypt_file_chunked`'ın **çıkışında** yapılıyor ki gelecekteki her çağıran
   da korunsun.
2. `receiver.py`'ye kapsama kontrolü: yazmadan hemen önce `realpath` ile
   çözülen hedefin seçilen dizinin içinde kaldığı doğrulanıyor. Yazma geri
   alınamaz olduğu için ikinci savunma orada duruyor.

Meşru adlar bozulmuyor — `.gitignore`, `türkçe-ad.txt`, `a.tar.gz` aynen
kalıyor. (İlk denememde baştaki noktaları da soyuyordum; `.gitignore` →
`gitignore` oluyordu. Güvenlik ayraçların kaldırılmasından geliyor, nokta
soymaktan değil; düzeltildi.)

## Bulgu 14 — Parola karşılaştırması sabit zamanlı değildi  🟡

**Dosya:** `HazeDrop/hazedrop/core/server.py` (iki yer)

`if hash_password_for_auth(provided) != expected:` — sırlar `!=` ile
karşılaştırılınca kaç baytın eşleştiği zamanlamadan sızar.

Pratik risk küçüktü (iki taraf da SHA-256 özeti; kısmi eşleşme parola hakkında
bir şey söylemez, çünkü SHA-256 ön-görüntü dirençli). Ama `hmac.compare_digest`
bedava ve soruyu ortadan kaldırıyor. İkisi de değiştirildi.

## Bulgu 15 — Tuzak vault'un varlığı herkese ilan ediliyordu  🟠

**Dosya:** `haze/src/haze/storage/settings.py`

`settings.json`, `vault_lock_hash` ve `vault_decoy_hash` alanlarını tutuyor ama
`open(..., "w")` ile yazılıyordu — varsayılan umask'la **0644, yani herkes
okuyabilir**.

İki sonuç, ikincisi daha ağır:

* Kilit hash'i her yerel hesaba açık olunca, hız sınırlı bir açma ekranı
  **çevrimdışı tahmin problemine** dönüşüyor. scrypt N=2^15 bunu pahalı tutuyor
  ama hiç sunulmamalı.
* Daha kötüsü: dolu bir `vault_decoy_hash` **bir tuzak vault olduğunu ilan
  ediyor.** Tuzak yalnızca kimse diğer parolayı sormayı akıl etmediği sürece
  işe yarar; dünya-okunur bir kopya özelliği zayıflatmıyor, **tamamen
  anlamsızlaştırıyor.**

**Yapılan:** Dosya baştan `0600` ile açılıyor (önce yazıp sonra `chmod` etmek,
hash'lerin diskte okunabilir olduğu bir pencere bırakırdı), dizin `0700`
yapılıyor, ve dünya-okunur bir sürümden yükselten için mevcut dosyanın modu da
düzeltiliyor.

---

## Denetlenip SAĞLAM çıkanlar

Kriptografinin kendisi iyi. Bunlar arandı ve sorun bulunmadı:

| Kontrol | Sonuç |
|---|---|
| **Nonce tekrarı** (ChaCha20-Poly1305) | ✅ Her chunk için `os.urandom(12)` — tekrar yok |
| **Nonce tekrarı** (AES-GCM, web istemcileri) | ✅ Her mesajda `os.urandom(12)`. GCM'de nonce tekrarı anahtar kurtarmaya kadar gider; rastgele 96-bit ile doğum günü sınırı ~2^32 mesaj, sohbet için erişilemez |
| **Anahtar üretimi** | ✅ `os.urandom(32)`, `random` modülü değil |
| **Parola → anahtar türetme** (hazedrop) | ✅ Argon2**id**, t=3, m=64 MiB, p=2, 32 baytlık rastgele salt — OWASP asgarisinin üstünde |
| **Vault parola türetme** (haze) | ✅ scrypt N=2^15 (tahmin başına 32 MiB), PBKDF2 200k'dan geçiş yolu ve gerekçesi yazılı |
| **Oturum anahtarı paroladan mı türetiliyor** | ✅ Hayır — rastgele üretilip her istemciye X25519/P-256 ECDH ile sarmalanıyor. Parola yalnızca odaya giriş için |
| **Anahtar anlaşması** | ✅ Efemeral X25519 (P-256 yedekli), HKDF-SHA256 |
| **Kimlik doğrulamalı şifreleme** | ✅ Her yerde AEAD; düz şifre + ayrı MAC birleştirmesi yok |
| **Vault hash karşılaştırması** | ✅ `hmac.compare_digest` |
| **Base64 çözümleme** | ✅ `validate=True` — sessiz kabul yok |
| **Şifre çözme hatasında sızıntı** | ✅ İstisna yakalanıp `WebCryptoError`'a çevriliyor, kısmi düz metin dönmüyor |
| **3 yanlış parolada kilit** | ✅ Uygulanmış — `force_expire()` |

## Chunk sırası ve kesme — neden bulgu değil

Chunk'lar `AAD=None` ile şifreleniyor, yani hiçbir şey chunk sırasını veya
toplam sayısını bağlamıyor. Genel olarak bu, sıra değiştirme ve sondan kesmeye
karşı açıklıktır.

Burada pratik bir zafiyet değil, çünkü akışı üretebilecek tek taraf gönderendir
— ve gönderen zaten içeriğin tamamını belirliyor. Taşıma Tor onion, yani ağ
üzerinde araya giren bir taraf yok. Ayrıca URL'deki SHA-256, mevcut olduğunda
düz metnin tamamını doğruluyor.

Aynı mantık dosya adı için **geçerli değildi** ve Bulgu 13'ün özü buydu:
gönderenin içeriği belirlemesi beklenen, diskte konumu belirlemesi değil.

---

## Yayınlanacak (bu turdan)

| Paket | Sürüm | Bulgu |
|---|---|---|
| `hazedrop` | 1.4.0-**1** | 13, 14 |
| `haze` | 2.11.2-**1** | 15 |

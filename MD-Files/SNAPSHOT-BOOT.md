# Snapshot'tan boot — tasarım

Hedef: kullanıcı boot ekranında bir snapshot seçip ona dönebilsin.

Bu belge tasarımı ve **neden iki fazda yapılması gerektiğini** anlatır.

**Durum (7 Eylül 2026):** Faz A gerçek donanımda uygulandı ve yarısı kanıtlandı.
Neyin kanıtlandığı ve neyin hâlâ açık olduğu aşağıda "Sahada öğrendiklerimiz"
bölümünde tek tek yazılı. Faz B tasarım hâlinde.

---

## Bugünkü durum ve eksik parça

`maze-snapshots` (snapper + snap-pac) her pacman işleminden önce ve sonra
snapshot alıyor. Ama şu an bunlar **yalnızca dosya düzeyinde geri alma** sağlıyor:

```
/etc/kernel/cmdline:  ... rootflags=subvol=/@ ...
```

Bu satır UKI'nin içinde **mühürlü ve imzalı**. `snapper rollback` btrfs'in
*varsayılan subvolume*'ünü değiştirir — ama boot her seferinde `/@`'yi zorladığı
için değişikliğin hiçbir etkisi olmaz. Yani tam rollback bugün çalışmıyor.

Ayrıca ortada seçim yapılacak bir ekran da yok: zincir
`shim → grubx64.efi (UKI) → çekirdek` şeklinde doğrudan ilerliyor, systemd-boot
menüsü ve sd-boot NVRAM girişi bilerek kaldırılmış durumda.

---

## Neden basit çözüm işe yaramıyor

Klasik yöntem (grub-btrfs tarzı) her snapshot için düz metin bir boot girişi
üretir ve `rootflags`'i orada değiştirir. Maze'de bu bir **güvenlik gerilemesi**:

UKI'nin bütün değeri çekirdek + initramfs + cmdline'ı tek bir imzalı PE'de
mühürlemesi. cmdline düz metin bir `loader/entries/*.conf`'a inerse ESP'ye
yazabilen biri `apparmor=1`'i silebilir, `init=/bin/sh` ekleyebilir — ve
`mokutil --sb-state` hâlâ *enabled* der. Kök LUKS olduğu için initramfs de
imzasız kalır, yani parola yakalayıcı yerleştirme yolu açılır.

Dolayısıyla snapshot seçimi, cmdline mühürlü kalacak şekilde çözülmeli.

---

## Faz A — rollback'i çalışır hâle getir  ◐ YARISI KANITLANDI

`maze-enable-rollback` (maze-snapshots paketinde) bunu yapıyor. Kurulum
varsayılanı **hâlâ değiştirilmedi** — Faz A bir makinede uçtan uca çalıştığı
görülene kadar yeni ISO'ların boot davranışına dokunulmuyor. Araç isteğe bağlı,
kendi kendini doğruluyor ve geri alınabilir.

```sh
sudo maze-enable-rollback          # ne değişeceğini göster, hiçbir şey yapma
sudo maze-enable-rollback --apply  # uygula
sudo maze-enable-rollback --undo   # geri al

sudo maze-rollback                 # geri dönülebilecek snapshot'ları listele
sudo maze-rollback 12              # 12'ye dön (önce sorar)
sudo maze-rollback --undo          # hazırlanan rollback'i iptal et
```

Her adım bir sonrakinden önce doğrulanıyor: `set-default` uygulanmadan cmdline'a
dokunulmuyor, yeniden yazılan satırda `root=` yoksa iptal ediliyor, ve
`maze-boot-check` mutsuzsa eski cmdline geri yüklenip yeniden derleniyor.

`maze-boot-check`'e de bir kontrol eklendi: cmdline'da subvol sabitlemesi yokken
btrfs varsayılanı çalışan kökü göstermiyorsa gürültülü hata veriyor. Bu, sessiz
ve tam bir boot kaybının tek uyarısı.

### Yöntem

**Boot menüsü gerektirmez, en yüksek değer/risk oranı.**

`rootflags=subvol=/@`'yi cmdline'dan çıkar ve btrfs'in **varsayılan
subvolume**'ünü `@` yap. btrfs `subvol=` verilmediğinde varsayılanı bağlar,
`snapper rollback` de tam olarak varsayılanı değiştirir — ikisi birleşince
rollback sealed cmdline'a dokunmadan çalışır.

Kurulumda (`deploy-to-target.sh`):

```sh
# @ subvolume'unu varsayılan yap, cmdline'dan subvol= çıkar
btrfs subvolume set-default "$(btrfs subvolume list / | awk '$NF=="@"{print $2}')" /
```

Sonrasında akış şu olur:

```sh
snapper -c root list          # snapshot'ları gör
sudo snapper rollback 42      # 42'yi yeni varsayılan yap
sudo reboot
```

**Dikkat:** `subvol=` çıkarılıp varsayılan yanlış ayarlanırsa btrfs en üst
seviyeyi (subvolid 5) bağlar ve sistem açılmaz. Bu yüzden değişiklik VM'de
doğrulanmadan gönderilmemeli, ve `maze-boot-check`'e "varsayılan subvolume `@`'yi
gösteriyor mu" kontrolü eklenmeli.

Kapsamadığı durum: sistem hiç açılmıyorsa `snapper rollback` çalıştıracak bir
kabuk da yok. Oradan Faz B devreye girer.

---

## Sahada öğrendiklerimiz

Faz A bir ThinkPad'e uygulandı. Kâğıt üzerinde görünmeyen dört şey çıktı.

### 1. cmdline değişikliği çalışıyor  ✅ kanıtlandı

`--apply` sonrası makine `rootflags=subvol=` olmadan açıldı. `/proc/cmdline`
temiz, `maze-boot-check` yeşil, kök btrfs varsayılan subvolume'ünden bağlandı.
UKI mühürlü ve imzalı kaldı. Bu, tasarımın en riskli kısmıydı ve tuttu.

### 2. `snapper rollback` tek başına çalışmıyor  ✅ çözüldü

Maze'in kökü düz bir `@` subvolume'ü; snapper ise kökün *kendisinin bir
snapshot olmasını* bekleyen openSUSE düzenine göre yazılmış. Algılayamayınca:

```
Cannot detect ambit since default subvolume is unknown.
```

`exit 1` verip **hiçbir şeyi değiştirmiyor**. Bu satırı kaçıran kullanıcı
yeniden başlatır, aynı sistemi bulur ve bir şeyin ters gittiğini gösteren
hiçbir iz olmaz — bir kurtarma aracının başarısız olabileceği en kötü biçim.

Çözüm `--ambit classic`. `maze-rollback` bunu her zaman veriyor; kullanıcının
bilmesi gereken bir ayrıntı olmaktan çıktı.

### 3. `.snapshots` iç içe duruyor  ✅ çözüldü

Snapshot deposu `@/.snapshots`, yani kök subvolume'ün **içinde**. İç içe
subvolume'ler üst subvolume'ün snapshot'ına dahil edilmez — boş dizin olarak
görünürler. Sonuç: bir snapshot'a dönüp boot ettiğinde `/.snapshots` boştur,
`snapper list` hiçbir şey göstermez, ve ileri geri gitmek için gereken tek araç
kör kalır.

openSUSE bunu depoyu fstab'dan ayrıca bağlayarak çözüyor. `maze-snapshots-setup`
artık aynısını yapıyor: hangi kökten açılırsan aç, depo aynı yerden bağlanıyor.
`nofail` ile — yanlış bir satır snapshot'a mal olabilir, boot'a asla.

### 4. Rollback'ten boot etmek hâlâ kanıtlanmadı  ⚠ AÇIK

Tek denemede `snapper --ambit classic rollback 7` başarılı oldu ve varsayılanı
`@/.snapshots/9/snapshot` (id 270) yaptı — `get-default` bunu doğruladı. Ama
yeniden başlatınca makine yine `@` ile açıldı: işaret dosyası yerindeydi,
`findmnt` `/@` gösterdi.

**Sebebi henüz bilinmiyor.** Ayırt edici veri, reboot sonrası
`btrfs subvolume get-default /` çıktısı: hâlâ 270 ise boot varsayılanı yok
saymış, 256'ya dönmüşse dışarıdan bir şey sıfırlamış demektir. Repoda
`set-default` çağıran tek yer `maze-enable-rollback`, yani ikincisi için Maze
dışı bir sebep aranmalı.

Bu çözülmeden Faz A kurulum varsayılanı yapılmayacak.

---

## Faz B — kurtarma UKI'si

**Sistem açılmadığında boot ekranından snapshot seçebilmek.**

İki parça gerekir.

### B1 — zincire systemd-boot'u geri koy

`shim → systemd-boot → UKI`. UKI korunur, yani cmdline ve initramfs imzalı
kalır; değişen sadece ikinci aşamanın menülü bir yükleyici olması. sd-boot
`$ESP/EFI/Linux/*.efi` altındaki UKI'leri kendiliğinden listeler.

**Bu adım tahminle yapılamaz.** systemd-boot zincirden şu sebeple çıkarılmıştı:
katı firmware'ler (ARCHITECTURE.md'de MSI/ASUS diye geçiyor) gevşek çekirdek
için MOK'u yok sayıyor. sd-boot'un UKI'yi yüklerken `shim_lock` protokolünü
kullanıp kullanmadığı önce `tools/test-boot.sh --secboot` ile OVMF'de, sonra
gerçek donanımda doğrulanmalı.

Yan kazanç: `bootctl set-default` yeniden çalışır, boot counting açılabilir
(`ad+3.efi` → üç deneme, `boot-complete.target`'a ulaşılamazsa otomatik geri
dönüş), `grubx64.efi` kopyası ve `.maze-prev` mekanizması gereksizleşir.

### B2 — tek bir kurtarma imajı

ESP'ye **bir adet** ek imzalı UKI: `maze-recovery.efi` (~90 MB, sabit maliyet).

Kendi initramfs'i özel bir mkinitcpio hook'u taşır:

1. LUKS'u açar (mevcut `encrypt` hook'u yeniden kullanılır)
2. btrfs'in en üst seviyesini geçici bağlar
3. `@/.snapshots/*/snapshot` altını listeler, tarih ve açıklamalarıyla bir menü
   gösterir
4. Seçilen subvolume'ü kök olarak bağlar ve `switch_root` yapar

Böylece **her** snapshot seçilebilir, ESP bütçesi sabit kalır ve cmdline mühürlü
kalır — çünkü seçim cmdline'da değil, initramfs'in içinde yapılır.

Karşılaştırma:

| Yöntem | ESP maliyeti | Snapshot sayısı | cmdline imzalı |
|---|---|---|---|
| Kurtarma UKI'si | ~90 MB sabit | sınırsız | evet |
| Snapshot başına UKI | ~90 MB × N | 3-5 (2.6 GB ESP) | evet |
| Gevşek çekirdek + BLS | ihmal edilebilir | sınırsız | **hayır** |

---

## Sıralama

1. **Yukarıdaki 4. maddeyi teşhis et.** Rollback'ten boot etmek çalışmadan
   gerisinin bir anlamı yok.
2. **VM yükseltme test koşumu** (dayanıklılık planındaki 4. madde). Bugüne kadar
   her gerçek hata ancak gerçek çalıştırmada ortaya çıktı.
3. **Faz A'yı installer'a al** — ancak 1 ve 2 bittikten sonra.
4. **B1** — sd-boot'u OVMF secboot'ta, sonra gerçek MSI donanımında dene.
   Asıl kazancı snapshot menüsü değil, **boot counting**: imaj üç kez açılmayı
   dener, `boot-complete.target`'a ulaşamazsa kendiliğinden bir öncekine döner.
   Sıradan kullanıcı için doğru kurtarma budur — menü değil.
5. **B2** — kurtarma hook'unu yaz, kurtarma UKI'sini üret ve imzala.

Her adım bir öncekine bağımlı. Atlanırsa hata boot anında ortaya çıkar, yani
düzeltmenin en pahalı olduğu yerde.

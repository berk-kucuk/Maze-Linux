# Site ve Wiki Güncelleme Brief'i

**Hazırlanma tarihi:** 8 Eylül 2026
**Hedef:** https://mazelinux.berkkucukk.com.tr (Vite + React + TS, 3 dilli)

Bu belge sunucuda Claude Code'a verilmek üzere yazıldı. İçindeki her bulgu
canlı sitede doğrulandı, her iddia kaynak kodda kontrol edildi.

---

## 0. Bu işi yapan ajana talimat

**Yapılacak:** Aşağıdaki A, B ve C bölümlerindeki değişiklikleri uygula.

**Yapılmayacak:**
- Sitenin yapısını, tasarımını veya bölüm sırasını değiştirme
- Bu belgede olmayan yeni iddia uydurma
- Metinleri bileşenlere gömme — **tüm metin `src/i18n/locales/` altındadır**

**Kritik kural:** Site üç dilli (`tr.json`, `en.json`, `de.json`). Bir metni
değiştirirken **üçünü birden** değiştir. Tek dilde bırakılan bir düzeltme,
sitenin dile göre farklı şeyler iddia etmesi demektir.

**Almanca metinler için not:** Aşağıdaki `de` çevirileri ana dili Almanca olan
biri tarafından gözden geçirilmeli. Anlam doğru, ama akıcılık kontrol edilmeli.

---

## A. Doğrulanmayan iddialar — ÖNCELİK

Bunlar bilen bir kullanıcının kontrol edeceği ve tutmadığında güvenilirliğe
zarar vereceği iddialar.

### A1. "Every layer is already active" + USBGuard

**Nerede:** Bölüm 3 (Defense in depth), L1 · Root of trust

**Sorun:** `usbguard` varsayılan olarak **kapalı**. Kurulu sistemde
`systemctl is-enabled usbguard` → `disabled`. Yalnızca kullanıcı Maze
Hardware'den USB kesme anahtarını açtığında etkinleşiyor.

**Çözüm — iki seçenek:**

1. **Tercih edilen:** USBGuard'ı listede tut ama etiketini değiştir.
   Bölümün "Every layer is already active" cümlesi de yumuşamalı.

   | Dil | Eski | Yeni |
   |---|---|---|
   | tr | Her katman zaten aktif. | Katmanların çoğu ilk açılıştan itibaren aktif; kalanı tek tıkla. |
   | en | Every layer is already active. | Most layers are active from first boot; the rest are one click away. |
   | de | Jede Schicht ist bereits aktiv. | Die meisten Schichten sind ab dem ersten Start aktiv, der Rest ist einen Klick entfernt. |

   USBGuard etiketi: `USBGuard` → `USBGuard (opsiyonel)` / `USBGuard (optional)` /
   `USBGuard (optional)`

2. Alternatif: `usbguard`'ı kurulumda varsayılan etkinleştir. **Önerilmez** —
   yeni USB cihazları varsayılan olarak bloklamak sıradan kullanıcı için
   "klavyem çalışmıyor" demektir.

### A2. "TPM support"

**Nerede:** Bölüm 3, L1 · Root of trust

**Sorun:** `tpm2-tools` ve `tpm2-tss` paketleri kurulu, ama **hiçbir şey onları
kullanmıyor.** LUKS `systemd-cryptenroll` ile TPM'e bağlanmıyor, boot zinciri
TPM'e ölçüm yapmıyor. Yani gerçekte "araçlar mevcut, isterseniz kendiniz
kurarsınız".

**Çözüm:** Bu maddeyi L1'den **çıkar.** Bir "root of trust" katmanında
kullanılmayan bir teknolojiyi saymak, o katmanın tamamına duyulan güveni
zedeler.

Yerine gerçekten doğru olan bir madde koyulabilir:

| Dil | Yeni madde |
|---|---|
| tr | İmzalı çekirdek imajı |
| en | Signed kernel image |
| de | Signierte Kernel-Abbildung |

Bu doğrudur ve TPM'den daha güçlü bir iddiadır: çekirdek, initramfs ve komut
satırı tek bir imzalı dosyada mühürlüdür.

---

## B. Eksik içerik — YENİ BÖLÜM: Dayanıklılık

**Bu, sitenin en büyük eksiği.** Mevcut site saldırıya karşı korumayı anlatıyor
ama *"güncelleme sistemimi bozarsa ne olur"* sorusuna hiçbir yerde cevap
vermiyor — ki bu, rolling release'ten çekinen insanların bir numaralı endişesi.

Anlatılacak her şey doğrulanmış durumda.

**Yerleştirme:** Bölüm 3 (Defense in depth) ile Bölüm 4 (The Desktop) arasına.
Savunmadan hemen sonra, "peki ya kendi kendine bozulursa" sorusunun doğal yeri.

**Numaralandırma:** Site `X / 10` şeklinde sayıyor. Yeni bölüm eklenince tüm
bölümler `X / 11` olarak yeniden numaralandırılmalı.

### B1. Bölüm başlığı

| Alan | tr | en | de |
|---|---|---|---|
| eyebrow | `Dayanıklılık` | `Resilience` | `Widerstandsfähigkeit` |
| başlık | Bozulursa geri dönersiniz. | Break it, and come back. | Kaputt? Kein Problem. |
| alt metin | Rolling release'in korkulan yanı, güncellemenin sistemi bozması. Maze her güncellemede geri dönüş yolunu önceden hazırlar. | The thing people fear about a rolling release is an update that breaks the system. Maze prepares the way back before every update. | Was viele an Rolling Releases fürchtet: ein Update, das das System zerstört. Maze bereitet den Rückweg vor jedem Update vor. |

### B2. Kartlar (dört adet)

**Kart 1 — İkinci çekirdek**

| Dil | Başlık | Metin |
|---|---|---|
| tr | Her zaman ikinci bir çekirdek | Maze iki çekirdek tutar: güncel olan ve uzun destekli LTS. Güncel çekirdek açılmazsa boot menüsünden kurtarma çekirdeğini seçersiniz — kurulu, derlenmiş ve imzalı hâlde hazır bekler. |
| en | Always a second kernel | Maze keeps two kernels: the current one and the long-term-support one. If the current kernel will not boot, you pick the recovery kernel from the boot menu — already installed, built and signed. |
| de | Immer ein zweiter Kernel | Maze hält zwei Kernel bereit: den aktuellen und den LTS-Kernel. Startet der aktuelle nicht, wählen Sie im Boot-Menü den Recovery-Kernel — bereits installiert, gebaut und signiert. |

**Kart 2 — Otomatik snapshot**

| Dil | Başlık | Metin |
|---|---|---|
| tr | Her güncellemeden önce anlık görüntü | Her `pacman` işleminin öncesinde ve sonrasında btrfs snapshot alınır. Bir güncelleme bir şeyi bozarsa, değişen dosyaları görebilir ve geri alabilirsiniz. |
| en | A snapshot before every update | A btrfs snapshot is taken before and after every `pacman` transaction. If an update breaks something, you can see exactly what changed and undo it. |
| de | Ein Snapshot vor jedem Update | Vor und nach jeder `pacman`-Transaktion wird ein btrfs-Snapshot erstellt. Wenn ein Update etwas zerstört, sehen Sie genau, was sich geändert hat, und machen es rückgängig. |

**Kart 3 — Boot zinciri doğrulaması**

| Dil | Başlık | Metin |
|---|---|---|
| tr | Yeniden başlatmadan önce kontrol | Her güncellemeden sonra boot zinciri baştan sona doğrulanır — çekirdek imajı, imza, şifreli disk açma. Bir sorun varsa sistem siz kapatmadan önce uyarır ve nedenini söyler. |
| en | Checked before you reboot | After every update the whole boot chain is verified — kernel image, signature, encrypted-disk unlock. If something is wrong, the system warns you before you shut down and tells you what it is. |
| de | Geprüft, bevor Sie neu starten | Nach jedem Update wird die gesamte Boot-Kette geprüft — Kernel-Abbild, Signatur, Entsperrung der verschlüsselten Festplatte. Stimmt etwas nicht, warnt das System vor dem Herunterfahren und nennt den Grund. |

**Kart 4 — Maze mi, donanım mı**

| Dil | Başlık | Metin |
|---|---|---|
| tr | Maze mi, donanım mı? | Bilgisayarınız donduğunda `maze-doctor` size nedenini söyler: kaybolan bir USB cihazı mı, cevap vermeyen bir disk mi, aşırı ısınma mı, yoksa gerçekten bir yazılım hatası mı. Saatlerce yanlış yerde aramazsınız. |
| en | Was it Maze, or the hardware? | When your machine freezes, `maze-doctor` tells you why: a USB device that vanished, a disk that stopped answering, overheating — or a real software fault. No more hours spent looking in the wrong place. |
| de | War es Maze oder die Hardware? | Wenn Ihr Rechner einfriert, sagt Ihnen `maze-doctor` warum: ein verschwundenes USB-Gerät, eine Festplatte, die nicht mehr antwortet, Überhitzung — oder tatsächlich ein Softwarefehler. Kein stundenlanges Suchen an der falschen Stelle. |

### B3. ⚠ Bu bölümde ASLA iddia edilmeyecekler

Bunlar henüz doğru değil. Yazılırsa ilk şikayette geri teper.

- ❌ **"Otomatik olarak geri döner"** / "self-healing" / "automatic rollback"
  → Kurtarma çekirdeğini **kullanıcı** seçer. Makine kendiliğinden geri dönmez.
- ❌ **"Tam sistem geri alma"** / "full system rollback"
  → Dosya düzeyinde geri alma çalışıyor; tam geri dönüş her makinede
    güvenilir değil, üzerinde çalışılıyor.
- ❌ **"Asla açılmaz duruma gelmez"** / "unbreakable" / "never fails to boot"
  → Böyle bir garanti verilemez.

Doğru çerçeve şu: **"bozulursa geri dönüş yolu hazır"**, "hiç bozulmaz" değil.

---

## C. Küçük düzeltmeler

### C1. Maze Cloak eksik

**Nerede:** Bölüm 6 (Built-in tools) — sekiz kart var, Maze Cloak yok.

**Sorun:** MAC rastgeleleştirme sitenin başka yerlerinde iddia ediliyor
(bölüm 1 ve 2) ama onu yapan uygulama araç listesinde görünmüyor.

**Ekle:**

| Dil | Başlık | Kategori | Metin |
|---|---|---|---|
| tr | Maze Cloak | gizlilik | Ağ kartınızın MAC adresini rastgeleleştirir ve isterseniz düzenli aralıklarla değiştirir. Bağlanmadığınız ağlar bile cihazınızı takip edemez. |
| en | Maze Cloak | privacy | Randomises your network adapter's MAC address, and rotates it on a schedule if you want. Even networks you never join cannot track your device. |
| de | Maze Cloak | Datenschutz | Randomisiert die MAC-Adresse Ihrer Netzwerkkarte und wechselt sie auf Wunsch regelmäßig. Selbst Netzwerke, mit denen Sie sich nie verbinden, können Ihr Gerät nicht verfolgen. |

### C2. Paket tablosu bayat

**Nerede:** Bölüm 11 (Package Repository)

**Sorun:** Tablo 02.09.2026 tarihli ve "19 paket" diyor. Güncel değil:

| Paket | Sitede | Güncel |
|---|---|---|
| `maze-tools` | 1.1.0-14 | **1.1.0-24** |
| `maze-installer` | 2.0.0-13 | **2.0.0-18** |
| `maze-guard` | 2.14.0-1 | **2.16.0-1** |
| `maze-cloak` | 1.1.1-1 | **1.2.0-1** |
| `maze-meta` | 1.1.1 | **1.5.0-1** |
| `maze-secureboot` | **yok** | 1.2.0-10 |
| `maze-snapshots` | **yok** | 1.1.0-1 |

**Yapılacak:** Tablo depodan otomatik üretiliyorsa yeni paketler yayınlanınca
kendiliğinden düzelir — **doğrula.** Elle yazılmışsa güncelle ve mümkünse
otomatik üretime çevir; elle tutulan bir sürüm tablosu her yayında bayatlar.

`maze-secureboot` ve `maze-snapshots` özellikle önemli: ikisi de artık
varsayılan kurulumun parçası ve sitenin anlattığı dayanıklılık özelliklerini
sağlayan paketler bunlar.

### C3. İsim tutarsızlığı

**Nerede:** Bölüm 7 (Compare) ve bölüm 10 (Download) — "maze-install wizard"

**Gerçek ad:** `Install Maze Linux (Calamares)` — masaüstündeki başlatıcının
`.desktop` dosyasındaki adı bu.

Kullanıcı "maze-install" diye bir şey arayıp bulamaz. Metinlerde "guided
installer" / "kurulum sihirbazı" gibi genel bir ifade kullan, ya da gerçek adı
yaz.

---

## D. Wiki

Wiki için içerik kaynağı: **`WEB-VE-WIKI-ICERIGI.md`** (bu belgeyle birlikte
verilmeli). 15 bölüm, kullanıcının arama sırasına göre dizili.

### D1. Sayfa yapısı

Şu sayfalara bölünmesi öneriliyor:

| Sayfa | Kaynak bölüm | Neden önemli |
|---|---|---|
| **Başlangıç / Maze Linux nedir** | 1, 2 | Giriş |
| **Kurulum** | 3.1, 3.2 | — |
| **⚠ İlk açılış: güvenlik anahtarı (MOK)** | 3.3 | **En kritik sayfa.** Mavi ekran kullanıcıyı panikletir ve yanlış seçim Secure Boot'u devre dışı bırakır |
| **Uygulamalar** | 4 | — |
| **Mahremiyet: ne çıkar, ne çıkmaz** | 5 | — |
| **Güvenlik modeli** | 6 | "Ne korumaz" tablosu dahil — sınırı söylemek güven inşa eder |
| **Güncelleme** | 7 | — |
| **Çekirdek yönetimi** | 8 | — |
| **Snapshot ve geri alma** | 9 | — |
| **🔧 Sistem açılmıyorsa** | 10 | **En çok aranacak sayfa.** Beş adım, yukarıdan aşağıya |
| **Donanım kesme anahtarları** | 11 | "Kameram neden çalışmıyor" sorusunun cevabı |
| **Teşhis araçları** | 12 | — |
| **SSS** | 13 | — |
| **Bilinen sınırlamalar** | 14 | Saklanırsa ilk şikayette geri teper |

### D2. Wiki için kurallar

- Bölüm 6.2 ("Ne korumaz") ve bölüm 14 ("Bilinen sınırlamalar") **kesinlikle
  atlanmamalı.** Bir güvenlik aracının sınırını söylemesi, söylememesinden daha
  güvenilirdir.
- Komut örnekleri kopyalanabilir olmalı.
- MOK sayfasına ekran görüntüsü eklenmeli — mavi MokManager ekranı metinle
  anlatmak zor.

---

## E. Doğrulama

Değişiklikler bittikten sonra, iddiaların hâlâ doğru olduğunu kontrol etmek
için (kurulu bir Maze makinesinde):

```bash
sudo maze-doctor              # genel durum, 18 bölüm
sudo maze-boot-check          # boot zinciri, 12 kontrol
systemctl is-enabled usbguard # "disabled" bekleniyor (A1)
pacman -Q linux linux-lts     # iki çekirdek (B2 kart 1)
snapper -c root list          # snapshot'lar (B2 kart 2)
```

Sitede yazan her teknik iddianın karşılığı bu komutlardan birinde
görünmelidir. Görünmüyorsa iddia ya yanlıştır ya da henüz doğru değildir.

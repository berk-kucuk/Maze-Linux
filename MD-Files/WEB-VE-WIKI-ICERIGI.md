# Maze Linux — Web Sitesi ve Wiki İçeriği

**Son güncelleme:** 8 Eylül 2026

Bu belge **kullanıcıya dönük** içeriğin kaynağıdır. `MAZE-TAM-REFERANS.md`'den
farkı: orası mühendislik referansıdır (eksikler, yapılan hatalar, alınan
dersler) ve web sitesine konmaz. Burası kullanıcının arayacağı şeyleri
cevaplar.

**Bölümlerin çoğu doğrudan wiki sayfası olarak kullanılabilir.** Sıralama,
insanların gerçekten arama sırasına göredir: önce "bu nedir", sonra "nasıl
kurulur", sonra "açılmıyor, ne yapacağım".

> **Not:** Uluslararası erişim için İngilizce çeviri gerekir. Uygulama
> README'leri zaten İngilizce; site ve wiki şu an Türkçe.

---

## 1. Maze Linux nedir

Arch Linux tabanlı, KDE Plasma masaüstülü, **günlük kullanım için** tasarlanmış
bir işletim sistemi. Üç şeyi birlikte yapmaya çalışır:

1. **Mahremiyeti korur** — varsayılan kurulumda hiçbir veri makineden çıkmaz
2. **Kendini savunur** — ağ saldırılarını gerçek zamanlı tespit eder ve engeller
3. **Saldırganı teşhis eder** — "bir şey engellendi" demez; *hangi cihazın,
   ne zaman, ne yaptığını* söyler

Üçüncüsü ayırt edici olan. Kurumsal EDR ürünleri bunu yapar ama tüketiciye
satılmaz; Windows Defender ve macOS XProtect korur ama size saldıranın kim
olduğunu söylemez.

**Teknik temel:** Arch Linux · KDE Plasma (Wayland) · btrfs + LUKS tam disk
şifreleme · UEFI Secure Boot · imzalı Unified Kernel Image

### Kimin için

Bilgisayarını günlük işleri için kullanan, ama mahremiyetine önem veren ve
başına bir şey geldiğinde **ne olduğunu öğrenebilmek** isteyen herkes.

### Kimin için değil

- Sızma testi dağıtımı arayanlar → Kali veya BlackArch daha uygun
  (Maze'e BlackArch deposu `maze-enable-blackarch` ile eklenebilir)
- BIOS/Legacy boot gerekenler → Maze yalnızca UEFI destekler
- Arch'ın yuvarlanan sürüm modeliyle rahat olmayanlar

---

## 2. Sistem gereksinimleri

| | Asgari | Önerilen |
|---|---|---|
| Boot | **UEFI zorunlu** (BIOS/Legacy desteklenmez) | UEFI + Secure Boot |
| İşlemci | x86_64 | — |
| RAM | 4 GB | 8 GB+ (yerel yapay zekâ için 16 GB) |
| Disk | 40 GB | 100 GB+ |
| ESP | 512 MB | **1 GB+** (iki çekirdek imajı için) |
| Ekran kartı | — | NVIDIA için `maze-gpu-driver` |

**ESP boyutu önemli:** Maze her çekirdeği ~90 MB'lık tek bir imzalı imaj olarak
saklar ve iki çekirdek tutar (biri kurtarma için). 512 MB dar kalır, 1 GB rahat.

---

## 3. Kurulum

### 3.1 ISO'yu yazma

```bash
sudo dd if=mazelinux-YYYY.MM.DD-x86_64.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

`/dev/sdX` USB diskin **kendisi**, bölümü değil (`/dev/sdb`, `/dev/sdb1` değil).

### 3.2 Kurulum adımları

1. USB'den açın (firmware'de boot sırasını değiştirin)
2. Canlı masaüstü gelince **Install Maze Linux (Calamares)** simgesine tıklayın
3. Dil, klavye, saat dilimi
4. **Disk bölümleme** — "Diski sil" en kolayı. Şifreleme kutusunu işaretleyin
   (önerilir; LUKS tam disk şifrelemesi)
5. Kullanıcı adı ve parola
6. Özeti onaylayın, kurulum başlasın
7. Bitince **yeniden başlatın**

### 3.3 ⚠ İlk açılış: güvenlik anahtarını onaylayın

**Bu adım bir kez yapılır ve atlanamaz.** İlk yeniden başlatmada mavi bir ekran
gelir — *"Verification failed"* ya da *"MOK Management"*. **Bu bir hata
değildir.**

Maze her bilgisayar için o makineye özel bir imzalama anahtarı üretir. Firmware
bu anahtarı henüz tanımadığı için bir kez onayınızı ister. Parola yoktur;
onay fiziksel olarak makinenin başında olmanızla verilir.

Yapılacaklar:

```
1. "Enroll key from disk"  seçin
2. EFI bölümünü seçin, ardından dosyayı:   MOK.cer
3. "Continue" → "Yes"
4. "Reboot"
```

Bundan sonra sistem normal açılır. Fabrika ve Windows anahtarlarına
dokunulmaz; çekirdek güncellemeleri kendiliğinden yeniden imzalanır.

Doğrulamak için:

```bash
mokutil --sb-state          # "SecureBoot enabled" demeli
sudo maze-boot-check        # zincirin tamamını kontrol eder
```

> **Ekranı kaçırdıysanız veya yanlış seçtiyseniz:** sorun değil, makine açılır
> ama Secure Boot devre dışı kalır. `sudo mokutil --import /var/lib/maze-secureboot/MOK.cer`
> çalıştırıp yeniden başlatın, mavi ekran tekrar gelir.

### 3.4 Kurulumdan sonra

```bash
sudo maze-doctor      # sistemin tam sağlık raporu
```

Her şeyin yolunda olduğunu görmek için. Çıktıda `0 failures` görmelisiniz.

---

## 4. Uygulamalar

Varsayılan kurulumda gelenler:

| Uygulama | Ne yapar |
|---|---|
| **Maze Guard** | Ağ güvenlik izleyici. Sahte erişim noktası, ARP/DNS zehirleme, SSL strip, port taraması tespiti. Saldıran cihaz için kalıcı dosya tutar |
| **Maze Cloak** | MAC adresinizi rastgeleleştirir. Bağlanmadığınız ağlar bile cihazınızı takip edemez |
| **Entropy Shield** | Tor, DNSCrypt, I2P yönetimi. Tek tıkla tüm trafiği Tor üzerinden geçirme |
| **Qlam** | Antivirüs (ClamAV arayüzü) |
| **Haze** | Tor üzerinden iz bırakmayan grup sohbeti. Hesap yok, kayıt yok, oturum bitince hiçbir şey kalmaz |
| **HazeDrop** | Tor üzerinden uçtan uca şifreli dosya transferi |
| **Maze AI** | **Tamamen yerel** yapay zekâ asistanı (Ollama). Hiçbir veri makineden çıkmaz |
| **Maze Connect** | Telefon–bilgisayar bağlantısı |
| **Maze Hardware** | Kamera, mikrofon, Bluetooth, WiFi, USB için donanım kesme anahtarları |
| **Maze Panic Mode** | Tek tıkla ağı kes, geçmişi sil, oturumu kilitle |
| **Maze Control Center** | Tüm ayarlar tek yerde |

İsteğe bağlı (varsayılan **gelmez**, `pacman -S` ile kurulur):

| Uygulama | Neden varsayılan değil |
|---|---|
| **SentinAI** | OSINT ve parola listesi araçları; ayrıca Google Gemini'ye bağlanabiliyor |
| **Linux Chan AI** | Yalnızca Google Gemini ile çalışır, çevrimdışı modu yok |

---

## 5. Mahremiyet: makineden ne çıkar

**Varsayılan kurulumda hiçbir şey.** Telemetri yok, kullanım istatistiği yok,
"deneyimi iyileştirme" verisi yok.

Yapay zekâ asistanı **Maze AI** modelleri sizin makinenizde çalıştırır (Ollama).
Yazdıklarınız internete çıkmaz.

İnternete çıkan tek şeyler, siz istediğinizde:

- Paket güncellemeleri (Arch ve Maze depoları)
- Açıkça kullandığınız uygulamalar (tarayıcı, Tor, vb.)
- İsteğe bağlı kurduysanız **SentinAI** veya **Linux Chan AI**'ın bulut modu —
  ikisi de ilk kullanımda uyarı gösterir

---

## 6. Güvenlik modeli

### 6.1 Ne korur

| Katman | Nasıl |
|---|---|
| **Disk** | LUKS tam disk şifrelemesi |
| **Boot** | Secure Boot + imzalı çekirdek imajı. Çekirdek, initramfs ve komut satırı tek bir imzalı dosyada mühürlü |
| **Çekirdek** | AppArmor, sertleştirilmiş sysctl profili, `lockdown`, `yama` |
| **Ağ** | nftables güvenlik duvarı, Maze Guard izleme, DNS sızıntı koruması |
| **Uygulamalar** | Firejail sandbox |
| **Kimlik** | MAC rastgeleleştirme, hostname gizleme |

**Mühürlü komut satırı ne demek:** Bilgisayarınıza fiziksel erişimi olan biri
boot ekranından `apparmor=1`'i silemez, `init=/bin/sh` ekleyip parolasız kabuk
açamaz. Bunlar imzalı imajın içindedir; değiştirmek imzayı bozar ve sistem
açılmaz.

### 6.2 Ne korumaz

Bunu bilmek koruma kadar önemlidir. Bir güvenlik aracının sınırını söylemesi,
söylememesinden daha güvenilirdir.

| Kapsam dışı | Neden | Ne korur |
|---|---|---|
| **Oltalama** — sahte siteye parola girmek | Gerçek bir sunucuya normal HTTPS trafiği | Tarayıcı uyarıları, parola yöneticisi (yanlış alan adında doldurmaz) |
| **Zaten çalışan zararlı yazılım** | Maze Guard süreçleri değil ağı izler | Qlam taraması, Firejail |
| **Kullandığınız servisin hacklenmesi** | Makinenizle ilgisi yok | Farklı parolalar, iki adımlı doğrulama |
| **Kapalı makineye fiziksel erişim** | Ağ olayı değil | LUKS + Secure Boot |

Maze Guard **bağlandığınız ağda** çok iyidir: kafede, otelde, havaalanında size
saldıran cihazın MAC adresini, üreticisini, işletim sistemini ve ne yaptığını
öğrenirsiniz. Bunun dışındaki kulvarlarda başka araçlar gerekir.

---

## 7. Güncelleme

```bash
sudo pacman -Syu
```

Her güncellemede otomatik olarak:

- Öncesinde ve sonrasında **btrfs snapshot** alınır (snap-pac)
- Çekirdek değiştiyse imaj yeniden üretilir ve imzalanır
- İşlem sonunda **boot zinciri baştan sona doğrulanır**

Bir sorun bulunursa sistem kapanmadan önce uyarır ve nedenini söyler.

---

## 8. Çekirdek yönetimi

Maze **iki çekirdek** tutar:

- `linux` — güncel Arch çekirdeği, normalde açılan
- `linux-lts` — uzun destekli çekirdek, **kurtarma için**

Bozuk bir güncelleme geldiğinde ikincisi zaten kurulu, derlenmiş ve imzalı
hâlde bekler.

**Grafik arayüz:** *Maze Kernel Switcher* (uygulama menüsünde)

**Belirli bir çekirdeği varsayılan yapmak:**

```bash
sudo maze-kernel-helper set-default linux-lts
```

Bu tercih güncellemelerde korunur.

---

## 9. Snapshot ve geri alma

Her `pacman` işleminden önce ve sonra otomatik snapshot alınır.

**Görüntülemek:**

```bash
snapper -c root list
```

Grafik arayüz: **Btrfs Assistant**

**Tek bir dosyayı geri almak:**

```bash
sudo snapper -c root status 42..0        # neyin değiştiğini gör
sudo snapper -c root undochange 42..0    # geri al
```

**Tam geri dönüş** (sistemin tamamını eski hâline döndürmek) ek bir kurulum
gerektirir:

```bash
sudo maze-enable-rollback           # ne değişeceğini gösterir
sudo maze-enable-rollback --apply   # uygular
sudo maze-rollback                  # dönülebilecek snapshot'ları listeler
sudo maze-rollback 42               # 42'ye dön
```

> **Bilinen sınırlama:** Tam geri dönüş şu an her makinede güvenilir
> çalışmıyor; üzerinde çalışılıyor. Dosya düzeyinde geri alma sorunsuz.

---

## 10. 🔧 Sistem açılmıyorsa

En çok aranacak sayfa budur. Yukarıdan aşağıya deneyin.

### Adım 1 — Kurtarma çekirdeğiyle açın

Açılışta firmware boot menüsünü açın (çoğu makinede **F12**, bazılarında F11,
F9 veya Esc) ve şunu seçin:

```
Maze Linux (recovery kernel)
```

Bu, LTS çekirdeğiyle açar. Güncel çekirdek bozulduysa bu çalışır.

Açıldıktan sonra sorunu onarın:

```bash
sudo maze-boot-check --repair
```

### Adım 2 — Önceki çekirdek imajını geri yükleyin

Kurtarma girişi yoksa:

```bash
sudo cp -f /boot/EFI/BOOT/grubx64.efi.maze-prev /boot/EFI/BOOT/grubx64.efi
sudo reboot
```

### Adım 3 — Sistem açılıyor ama masaüstü gelmiyorsa

Ctrl+Alt+F2 ile metin konsoluna geçin, kullanıcı adınız ve parolanızla girin:

```bash
sudo maze-doctor          # neyin bozuk olduğunu söyler
sudo systemctl status sddm
```

### Adım 4 — Acil kabuk

Bir disk bağlanamazsa sistem otomatik olarak acil kabuğa düşer. Maze'de bu
kabuk **parola sormadan** açılır (diskiniz zaten LUKS ile şifreli olduğu için
güvenlidir). Buradan `/etc/fstab`'ı onarabilirsiniz.

### Adım 5 — Canlı USB

Son çare. Maze USB'sinden açın, diski açıp chroot'a girin:

```bash
sudo cryptsetup open /dev/nvme0n1p2 kurtarma
sudo mount -o subvol=@ /dev/mapper/kurtarma /mnt
sudo mount /dev/nvme0n1p1 /mnt/boot
sudo arch-chroot /mnt
maze-boot-check --repair
```

---

## 11. Donanım kesme anahtarları

**Maze Hardware** uygulamasından kamera, mikrofon, Bluetooth, WiFi ve USB'yi
donanım düzeyinde kapatabilirsiniz.

**Kamera kapatma kalıcıdır** — yeniden başlatmadan sonra da kapalı kalır.
Sürücü kara listeye alınır, yani kamerayı kullanmaya çalışan hiçbir uygulama
onu göremez.

> **"Kameram çalışmıyor, ne yaptım?"**
> Önce şunu çalıştırın: `sudo maze-doctor`
> Kesme anahtarı açıksa Maze bunu açıkça söyler. Söylemiyorsa sebep Maze
> değildir — BIOS ayarı, fiziksel kamera sürgüsü (ThinkPad'lerde vardır) veya
> donanım arızası olabilir; `maze-doctor` bunu da belirtir.

---

## 12. Teşhis araçları

### `maze-doctor`

Sistemin tam sağlık raporu — 18 bölüm. Bir sorun yaşadığınızda çalıştırılacak
ilk şey.

```bash
sudo maze-doctor
```

**Stability bölümü**, "bu Maze'in hatası mıydı yoksa donanım mı" sorusunu
cevaplar. Makineniz dondu veya kendiliğinden kapandıysa, son açılışta çekirdeğin
yazdığı son satırı gösterir ve nedenini sınıflandırır: donanım (kaybolan USB
cihazı, cevap vermeyen disk, aşırı ısınma), bellek yetersizliği, ekran kartı
sürücüsü veya çekirdek hatası. Kanıt yetersizse tahmin etmez, "belirsiz" der.

### `maze-boot-check`

Boot zincirini uçtan uca doğrular — 12 kontrol. Her güncellemeden sonra
kendiliğinden çalışır, elle de çağırabilirsiniz:

```bash
sudo maze-boot-check
sudo maze-boot-check --repair    # bulduğu sorunları onarır
```

### `maze-boot-entries`

Birden fazla kez kurulum yaptıysanız boot menüsünde eski girişler birikmiş
olabilir. Bu araç ölü olanları temizler:

```bash
sudo maze-boot-entries           # sadece gösterir
sudo maze-boot-entries --clean   # temizler (onay ister)
```

Başka işletim sistemlerinin girişlerine ve o an açıldığınız girişe asla
dokunmaz.

---

## 13. Sık sorulanlar

**İlk açılışta mavi ekran geldi, sistem bozuldu mu?**
Hayır. Güvenlik anahtarı onayı — bölüm 3.3.

**Secure Boot'u kapatmam gerekir mi?**
Hayır. Maze Secure Boot **açıkken** çalışacak şekilde tasarlandı.

**Windows ile yan yana kurabilir miyim?**
Evet. Maze diğer işletim sistemlerinin boot girişlerine dokunmaz.

**Verilerim bir yere gönderiliyor mu?**
Hayır — bölüm 5.

**Yapay zekâ internete bağlanıyor mu?**
Maze AI hayır, tamamen yereldir. İsteğe bağlı kurulan SentinAI ve Linux Chan AI
bulut modunda evet; ikisi de ilk kullanımda uyarır.

**Güncelleme sistemimi bozarsa?**
Her güncellemede snapshot alınır ve boot zinciri doğrulanır. Bozulursa kurtarma
çekirdeğiyle açabilirsiniz — bölüm 10.

**BIOS/Legacy modda kurabilir miyim?**
Hayır. Maze yalnızca UEFI destekler; güvenlik zinciri buna bağlıdır.

**Sızma testi araçları var mı?**
Varsayılan gelmez. `sudo maze-enable-blackarch` ile BlackArch deposunu
ekleyebilirsiniz.

---

## 14. Bilinen sınırlamalar

Dürüstlük güven inşa eder; bunlar açıkça yazılmalı.

- **Tam snapshot geri dönüşü** her makinede güvenilir çalışmıyor. Dosya
  düzeyinde geri alma sorunsuz.
- **Otomatik kurtarma yok.** Sistem açılmazsa kurtarma çekirdeğini boot
  menüsünden **siz** seçmelisiniz; makine kendiliğinden geri dönmez.
- **BIOS/Legacy boot desteklenmiyor.**
- **DKMS modülleri (NVIDIA vb.) imzasız.** Arch çekirdeği lockdown'ı
  zorlamadığı için pratikte sorun çıkarmaz.
- **ESP 512 MB ise dar kalır** — iki çekirdek imajı sığmayabilir.

---

## 15. Yardım ve katkı

- **Web:** https://mazelinux.berkkucukk.com.tr
- **Depo:** paket kaynakları ve belgeler
- **Sorun bildirimi:** `sudo maze-doctor > rapor.txt` çıktısını ekleyin —
  neredeyse her soruyu tek başına cevaplar

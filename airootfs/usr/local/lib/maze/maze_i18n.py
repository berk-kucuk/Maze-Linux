"""maze_i18n — tiny self-contained EN/TR translation layer for Maze GUI apps.

English is the source language and the default; Turkish is the only alternative.
`tr(text)` returns the Turkish string when the active language is "tr" and a
translation exists, otherwise it returns the English source unchanged. No Qt
dependency, so shared libs (maze_status) can import it freely. The choice is
persisted to ~/.config/maze/language and read back on next launch.
"""
from __future__ import annotations

import os
from pathlib import Path

_CONFIG = Path(os.path.expanduser("~/.config/maze/language"))
_lang: str | None = None
SUPPORTED = ("en", "tr")


def current_language() -> str:
    global _lang
    if _lang is None:
        try:
            val = _CONFIG.read_text().strip().lower()
        except Exception:  # noqa: BLE001
            val = "en"
        _lang = val if val in SUPPORTED else "en"
    return _lang


def set_language(lang: str) -> None:
    global _lang
    _lang = lang if lang in SUPPORTED else "en"
    try:
        _CONFIG.parent.mkdir(parents=True, exist_ok=True)
        _CONFIG.write_text(_lang)
    except Exception:  # noqa: BLE001
        pass


def tr(text: str) -> str:
    if current_language() == "tr":
        return _TR.get(text, text)
    return text


# English source string → Turkish. Proper nouns (OpenSnitch, AppArmor, Tor,
# Ollama, firewalld, auditd, fail2ban, GPU/CPU, sysctl…) are intentionally left
# untranslated. Strings with {placeholders} are .format()-ed by the caller.
_TR: dict[str, str] = {
    # -- shared widgets / states ------------------------------------------
    "Copy": "Kopyala",
    "Copied": "Kopyalandı",
    "Active": "Etkin",
    "Inactive": "Devre dışı",
    "Not available": "Mevcut değil",
    "Running": "Çalışıyor",
    "Stopped": "Durduruldu",
    "Stopped (start when needed)": "Durduruldu (gerekince başlat)",
    "Enabled": "Etkin",
    "Disabled": "Devre dışı",
    "Ready": "Hazır",
    "Pass": "Geçti",
    "Fail": "Başarısız",
    "On": "Açık",
    "Off": "Kapalı",
    "Refresh": "Yenile",
    "Close": "Kapat",
    "Language": "Dil",
    # -- live metric labels ----------------------------------------------
    "Memory": "Bellek",
    "Disk": "Disk",
    # -- network labels / values -----------------------------------------
    "Local IP": "Yerel IP",
    "Interface": "Arayüz",
    "Wi-Fi": "Wi-Fi",
    "VPN": "VPN",
    "Tor": "Tor",
    "DNS": "DNS",
    "MAC randomisation": "MAC rastgeleleştirme",
    "Connected ({iface})": "Bağlı ({iface})",
    "Not connected": "Bağlı değil",
    "Reachable (127.0.0.1:9050)": "Erişilebilir (127.0.0.1:9050)",
    "Not running": "Çalışmıyor",
    # -- gpu / facts ------------------------------------------------------
    "{driver} driver": "{driver} sürücüsü",
    "GPU driver: unknown": "GPU sürücüsü: bilinmiyor",
    # -- hardening checks -------------------------------------------------
    "{label} active": "{label} etkin",
    "Secure Boot enabled": "Güvenli Önyükleme etkin",
    "Kernel/network hardening (sysctl)": "Çekirdek/ağ sıkılaştırma (sysctl)",
    "VPN or Tor active": "VPN veya Tor etkin",
    # -- Control Center: shell / nav -------------------------------------
    "Control Center": "Kontrol Merkezi",
    "Overview": "Genel Bakış",
    "Security": "Güvenlik",
    "Privacy": "Gizlilik",
    "Network": "Ağ",
    "AI": "Yapay Zekâ",
    "Hardening": "Sıkılaştırma",
    "Maintenance": "Bakım",
    "Actions are shown as commands — copy and run them in a terminal.":
        "İşlemler komut olarak gösterilir — kopyalayıp bir terminalde çalıştırın.",
    # -- Control Center: Overview ----------------------------------------
    "A live snapshot of your Maze system.":
        "Maze sisteminizin canlı bir görünümü.",
    "Hardware & system": "Donanım ve sistem",
    "Security services": "Güvenlik servisleri",
    "Hardening score": "Sıkılaştırma puanı",
    "Local AI (Ollama)": "Yerel YZ (Ollama)",
    # -- Control Center: Security ----------------------------------------
    "Live state of the Maze defensive services. To change a service, copy "
    "its command and run it in a terminal.":
        "Maze savunma servislerinin canlı durumu. Bir servisi değiştirmek için "
        "komutunu kopyalayıp bir terminalde çalıştırın.",
    "Secure Boot": "Güvenli Önyükleme",
    "Start all security services": "Tüm güvenlik servislerini başlat",
    "Enable them at every boot": "Her açılışta etkinleştir",
    "Open the firewall configuration": "Güvenlik duvarı yapılandırmasını aç",
    # -- Control Center: Privacy -----------------------------------------
    "Anonymity controls. MAC randomisation hides your hardware identity; "
    "Tor routes traffic anonymously.":
        "Anonimlik denetimleri. MAC rastgeleleştirme donanım kimliğinizi "
        "gizler; Tor trafiği anonim olarak yönlendirir.",
    "MAC randomisation": "MAC rastgeleleştirme",
    "Tor service": "Tor servisi",
    "Randomise your MAC address now": "MAC adresinizi şimdi rastgeleleştirin",
    "View MAC change logs": "MAC değişim günlüklerini görüntüle",
    "Start Tor": "Tor'u başlat",
    # -- Control Center: Network -----------------------------------------
    "Your connection and anonymity at a glance. Every check is local — "
    "Maze never contacts an external service to gather this.":
        "Bağlantınız ve anonimliğiniz bir bakışta. Her kontrol yereldir — "
        "Maze bunu toplamak için hiçbir dış servise bağlanmaz.",
    "Open Proton VPN": "Proton VPN'i aç",
    "Browse anonymously with Tor": "Tor ile anonim gezin",
    # -- Control Center: AI ----------------------------------------------
    "Artificial Intelligence": "Yapay Zekâ",
    "Run large language models locally and offline with Ollama.":
        "Ollama ile büyük dil modellerini yerel ve çevrimdışı çalıştırın.",
    "Ollama service": "Ollama servisi",
    "Installed models": "Yüklü modeller",
    "Pull a model": "Bir model indir",
    "Chat with a model": "Bir modelle sohbet et",
    "Remove a model": "Bir modeli kaldır",
    # -- Control Center: Hardening ---------------------------------------
    "How locked down this system is right now, scored across Maze's core "
    "defences.":
        "Bu sistemin şu anda ne kadar sıkılaştırıldığı, Maze'in temel "
        "savunmaları üzerinden puanlanmış.",
    "Security score": "Güvenlik puanı",
    "{passed} of {total} checks passed": "{total} kontrolden {passed} tanesi geçti",
    # -- Control Center: Maintenance -------------------------------------
    "Keep Maze healthy and up to date. Copy a command and run it when ready.":
        "Maze'i sağlıklı ve güncel tutun. Bir komutu kopyalayıp hazır "
        "olduğunuzda çalıştırın.",
    "Update the whole system": "Tüm sistemi güncelle",
    "Update firmware": "Ürün yazılımını güncelle",
    "Antivirus scan of your home folder": "Ev klasörünüzü virüs taraması yap",
    "Rootkit check": "Rootkit kontrolü",
    "Security audit": "Güvenlik denetimi",
    "Clean old package cache": "Eski paket önbelleğini temizle",
    # -- Welcome: shell / nav --------------------------------------------
    "Welcome": "Karşılama",
    "System": "Sistem",
    "Software": "Yazılım",
    "Updates": "Güncellemeler",
    "Visit Website": "Web Sitesini Ziyaret Et",
    "Got it": "Anladım",
    # -- Welcome: home ----------------------------------------------------
    "Welcome to Maze Linux": "Maze Linux'a Hoş Geldiniz",
    "A fully loaded Arch desktop, ready for security, privacy and AI. "
    "Use the tabs on the left to inspect your system, or click a card "
    "below to learn more.":
        "Güvenlik, gizlilik ve yapay zekâ için hazır, eksiksiz bir Arch "
        "masaüstü. Sisteminizi incelemek için soldaki sekmeleri kullanın "
        "veya daha fazlasını öğrenmek için aşağıdaki bir karta tıklayın.",
    "OpenSnitch, AppArmor, firewalld.": "OpenSnitch, AppArmor, firewalld.",
    "Maze ships with layered defences, on by default. OpenSnitch is an "
    "application firewall that asks for your approval before any program "
    "is allowed to connect to the internet. AppArmor confines apps so "
    "they can only touch what they need, and firewalld manages your "
    "network zones — so a compromised app can do far less harm.":
        "Maze, varsayılan olarak açık katmanlı savunmalarla gelir. OpenSnitch, "
        "herhangi bir programın internete bağlanmasına izin verilmeden önce "
        "onayınızı isteyen bir uygulama güvenlik duvarıdır. AppArmor "
        "uygulamaları yalnızca ihtiyaç duyduklarına erişecek şekilde sınırlar "
        "ve firewalld ağ bölgelerinizi yönetir — böylece ele geçirilmiş bir "
        "uygulama çok daha az zarar verebilir.",
    "Tor, MAC randomisation, hardened apps.":
        "Tor, MAC rastgeleleştirme, sıkılaştırılmış uygulamalar.",
    "Stay anonymous by design. The Tor Browser routes your traffic "
    "through the Tor network, MAC address randomisation hides your "
    "hardware identity on every network you join, and privacy-respecting "
    "applications come preconfigured out of the box.":
        "Tasarım gereği anonim kalın. Tor Browser trafiğinizi Tor ağı "
        "üzerinden yönlendirir, MAC adresi rastgeleleştirme katıldığınız her "
        "ağda donanım kimliğinizi gizler ve gizliliğe saygılı uygulamalar "
        "kutudan çıktığı gibi önceden yapılandırılmış gelir.",
    "Local LLMs with Ollama, fully offline.":
        "Ollama ile yerel LLM'ler, tamamen çevrimdışı.",
    "Run powerful large language models entirely on your own machine "
    "with Ollama. Nothing is sent to the cloud and no data ever leaves "
    "your computer. Once a model is downloaded it works completely "
    "offline — private AI that's yours alone.":
        "Ollama ile güçlü büyük dil modellerini tamamen kendi makinenizde "
        "çalıştırın. Buluta hiçbir şey gönderilmez ve hiçbir veri "
        "bilgisayarınızdan ayrılmaz. Bir model indirildikten sonra tamamen "
        "çevrimdışı çalışır — yalnızca size ait özel yapay zekâ.",
    "Install thousands of apps with Discover.":
        "Discover ile binlerce uygulama kurun.",
    "Discover is the graphical app store for your desktop. Browse and "
    "install thousands of applications from the Arch repositories and "
    "Flatpak with a single click — no terminal required.":
        "Discover, masaüstünüz için grafik uygulama mağazasıdır. Arch "
        "depolarından ve Flatpak'ten binlerce uygulamaya göz atın ve tek "
        "tıklamayla kurun — terminal gerekmez.",
    "Keep your rolling-release system current.":
        "Yuvarlanan sürüm sisteminizi güncel tutun.",
    "Maze is a rolling release built on Arch Linux, so you always get "
    "the latest software without ever reinstalling. Updating regularly "
    "is the best way to stay secure.":
        "Maze, Arch Linux üzerine kurulu bir yuvarlanan sürümdür; böylece "
        "yeniden kurulum yapmadan her zaman en yeni yazılıma sahip olursunuz. "
        "Düzenli güncelleme, güvende kalmanın en iyi yoludur.",
    "Inspect your hardware and services.":
        "Donanımınızı ve servislerinizi inceleyin.",
    "The System tab shows your live hardware details and the running "
    "state of every Maze security service, with a first-steps checklist "
    "to help you get going.":
        "Sistem sekmesi, canlı donanım ayrıntılarınızı ve her Maze güvenlik "
        "servisinin çalışma durumunu, başlamanıza yardımcı olacak bir ilk "
        "adımlar listesiyle birlikte gösterir.",
    # -- Welcome: pages ---------------------------------------------------
    "These defensive services are installed and enabled on Maze by "
    "default. Below is their live state on this system.":
        "Bu savunma servisleri Maze'de varsayılan olarak kurulu ve etkindir. "
        "Aşağıda bu sistemdeki canlı durumları yer alır.",
    "Status unavailable.": "Durum bilgisi alınamadı.",
    "Maze is built to keep you anonymous. Tor is available for anonymous "
    "browsing, and your hardware MAC address is randomised on every "
    "network you join.":
        "Maze sizi anonim tutmak için tasarlanmıştır. Anonim gezinme için Tor "
        "mevcuttur ve donanım MAC adresiniz katıldığınız her ağda "
        "rastgeleleştirilir.",
    "Ollama lets you run large language models locally and offline. "
    "Pull a model from a terminal with, for example, `ollama run llama3`.":
        "Ollama, büyük dil modellerini yerel ve çevrimdışı çalıştırmanızı "
        "sağlar. Bir terminalden, örneğin `ollama run llama3` ile model indirin.",
    "No models installed yet — pull one to get started.":
        "Henüz model yüklü değil — başlamak için bir tane indirin.",
    "First steps": "İlk adımlar",
    "Explore your security tools in the Security tab":
        "Güvenlik araçlarınızı Güvenlik sekmesinde keşfedin",
    "Pull a local AI model: ollama run llama3":
        "Yerel bir YZ modeli indirin: ollama run llama3",
    "Pick a wallpaper (right-click the desktop)":
        "Bir duvar kâğıdı seçin (masaüstüne sağ tıklayın)",
    "Update your system to the latest packages":
        "Sisteminizi en yeni paketlere güncelleyin",
    "Visit the Maze website to learn more":
        "Daha fazlası için Maze web sitesini ziyaret edin",
    # -- Welcome: tips ----------------------------------------------------
    "Tip: OpenSnitch asks before any app connects to the internet — "
    "review the prompts.":
        "İpucu: OpenSnitch, herhangi bir uygulama internete bağlanmadan önce "
        "sorar — istemleri inceleyin.",
    "Tip: Your MAC address is randomised on every network for privacy.":
        "İpucu: MAC adresiniz gizlilik için her ağda rastgeleleştirilir.",
    "Tip: Run local AI models fully offline with `ollama run <model>`.":
        "İpucu: Yerel YZ modellerini `ollama run <model>` ile tamamen "
        "çevrimdışı çalıştırın.",
    "Tip: Maze is a rolling release — update regularly to stay secure.":
        "İpucu: Maze yuvarlanan bir sürümdür — güvende kalmak için düzenli "
        "güncelleyin.",
    "Tip: Find thousands more apps in Discover, no terminal required.":
        "İpucu: Discover'da binlerce uygulama daha bulun, terminal gerekmez.",
    "Tip: Press Esc to close this window.":
        "İpucu: Bu pencereyi kapatmak için Esc'ye basın.",
}


# The original English TIPS list, exposed so the Welcome app can translate the
# rotating tip text by index without re-declaring the strings here.
TIPS_EN: tuple[str, ...] = (
    "Tip: OpenSnitch asks before any app connects to the internet — "
    "review the prompts.",
    "Tip: Your MAC address is randomised on every network for privacy.",
    "Tip: Run local AI models fully offline with `ollama run <model>`.",
    "Tip: Maze is a rolling release — update regularly to stay secure.",
    "Tip: Find thousands more apps in Discover, no terminal required.",
    "Tip: Press Esc to close this window.",
)

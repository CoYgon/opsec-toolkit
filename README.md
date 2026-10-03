# OPSEC Aggressive Isolation & Fail-Closed Toolkit

**OPSEC Aggressive Isolation Toolkit**, Linux sistemler için tasarlanmış; çekirdek (kernel) ve ağ seviyesinde tam izolasyon, bellek adli inceleme (forensic) önleme ve sızıntı koruması sağlayan otonom bir güvenlik ve anonimlik orkestratörüdür.

Sistem, harici bir zamanlayıcıya (cron/systemd timer) ihtiyaç duymadan kendi içinde **60 saniyelik otonom döngü** ile çalışır. Herhangi bir bağlantı kopması veya Tor daemon çökmesi durumunda ağ trafiğini kernel seviyesinde felç eden **Fail-Closed Dead-Man's Switch** mekanizmasına sahiptir.

---

## 🚀 Öne Çıkan Özellikler

- **Otonom Daemon Yapısı:** `master.sh` ana betiği kendi içinde sonsuz döngü barındırır. Her 60 saniyede bir güvenlik politikalarını tazeleyerek kesintisiz koruma sağlar.
- **Fail-Closed Kill-Switch:** `nftables` üzerindeki varsayılan çıkış politikası `DROP` olarak kilitlenmiştir. Yalnızca Tor prosesine (`TOR_UID`) izin verilir; ham paketlerin ağ arabirimine çıkışı engellenir.
- **Arka Plan Watcher (Dead-Man's Switch):** Arka planda çalışan izleyici daemon, Tor TransPort (`9040`) durumunu 2 saniyede bir kontrol eder. Tünelin kopması durumunda ağı anında kilitler (`Blackhole Drop`).
- **Şeffaf Ağ & DNS Hijacking:** Tüm TCP trafiği Tor TransPort'a (`9040`), tüm DNS sorguları ise Tor DNSPort'a (`5353`) yönlendirilir.
- **UDP, QUIC ve WebRTC Engeli:** Chrome/Firefox gibi tarayıcıların Tor'u baypas etmesini önlemek amacıyla tüm UDP trafiği ve WebRTC STUN paketleri engellenir.
- **IPv6 Blackhole:** IPv6 protokolü `sysctl` seviyesinde kapatılarak IPv6 tabanlı sızıntı vektörleri sıfırlanır.
- **Bellek ve İz Temizliği (RAM Purge):** Her döngüde `PageCache`, `dentry` ve `inode` önbellekleri temizlenir, bellek sıkıştırılır (memory compaction) ve kabuk geçmişi (`HISTFILE`) sıfırlanır.
- **Atomic Execution & Lock File:** `/tmp/opsec_toolkit.lock` mekanizması ile çifte çalıştırma engellenir; `trap` sinyal yakalayıcıları sayesinde güvenli kapanış sağlanır.

---

## 📁 Proje Yapısı

Tüm modüller ve ana çalıştırıcı betik aynı kök dizin içerisinde yer alır:

```text
.
├── master.sh                          # Otonom ana orkestratör ve daemon betiği
├── 01-kernel-memory-purge.sh          # RAM ve iz temizleme modülü
├── 02-network-check.sh                # Ağ durumu ve arayüz kontrol modülü
├── 03-tor-network-isolation.sh        # Tor TransPort, nftables Kill-Switch & Watcher
├── 04-process-telemetry-isolation.sh  # Telemetri ve sistem log servislerini maskeleme
└── 05-security-audit.sh               # Sistem sıkılaştırma ve denetim modülü

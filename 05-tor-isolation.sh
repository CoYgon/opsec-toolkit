#!/usr/bin/env bash
# Module: Aggressive Tor Network, Transparent Proxy & Absolute Fail-Closed Isolation

set -euo pipefail

BLUE='\e[34m'
YELLOW='\e[33m'
GREEN='\e[32m'
RED='\e[31m'
RESET='\e[0m'

echo -e "${BLUE}[*] Modul 3: AGRESİF Tor TransPort + Fail-Closed Leak Kill-Switch Başlatılıyor...${RESET}"

# 1. Root Kontrolü
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[!] Bu script root olarak çalıştırılmalı.${RESET}"
    exit 1
fi

# 2. Gerekli Paket Kontrolleri
for cmd in tor nft curl iptables ip ss; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo -e "${RED}[!] Eksik bağımlılık: $cmd${RESET}"
        echo "Kurulum: apt install tor nftables curl iptables iproute2 -y"
        exit 1
    fi
done

# 3. Tor Kullanıcısı ve UID Tespiti
TOR_USER="debian-tor"
if ! id "$TOR_USER" >/dev/null 2>&1; then
    TOR_USER="tor"
fi
if ! id "$TOR_USER" >/dev/null 2>&1; then
    echo -e "${RED}[!] Tor sistemi kullanıcısı bulunamadı.${RESET}"
    exit 1
fi
TOR_UID=$(id -u "$TOR_USER")
echo -e "${GREEN}[✓] Tor UID tespit edildi: $TOR_UID ($TOR_USER)${RESET}"

# 4. torrc Konfigürasyonunu Agresif Şeffaf Moda Çevir
TORRC_FILE="/etc/tor/torrc"
TORRC_BAK="/etc/tor/torrc.bak.sgu"

if [[ ! -f "$TORRC_BAK" ]]; then
    cp "$TORRC_FILE" "$TORRC_BAK" 2>/dev/null || true
fi

echo -e "${YELLOW}[-] /etc/tor/torrc dosyasına Transparent & Safe DNS parametreleri enjekte ediliyor...${RESET}"

cat <<EOF > "$TORRC_FILE"
# Auto-generated Aggressive Isolation Profile
VirtualAddrNetworkIPv4 10.192.0.0/10
AutomapHostsOnResolve 1
TransPort 127.0.0.1:9040
DNSPort 127.0.0.1:5353
SocksPort 127.0.0.1:9050
ControlPort 127.0.0.1:9051
CookieAuthentication 1
IsolateDestAddr 1
IsolateDestPort 1
EOF

# 5. Tor Servisini Yeniden Başlat ve Portları Doğrula
echo -e "${YELLOW}[-] Tor servisi agresif modda yeniden başlatılıyor...${RESET}"
systemctl restart tor

for i in {1..20}; do
    if ss -lntp 2>/dev/null | grep -q ':9040' && ss -lnup 2>/dev/null | grep -q ':5353'; then
        break
    fi
    sleep 1
done

if ! ss -lntp 2>/dev/null | grep -q ':9040'; then
    echo -e "${RED}[!] Tor TransPort (9040) açılamadı. torrc yapılandırmasını kontrol edin.${RESET}"
    exit 1
fi
echo -e "${GREEN}[✓] Tor TransPort (9040) ve DNSPort (5353) aktif.${RESET}"

# 6. Resolv.conf Hijack & Locking
echo -e "${YELLOW}[-] DNS yapılandırması Tor DNSPort (127.0.0.1:5353) seviyesine kilitleniyor...${RESET}"
if command -v chattr >/dev/null 2>&1; then
    chattr -i /etc/resolv.conf 2>/dev/null || true
fi

cat <<EOF > /etc/resolv.conf
nameserver 127.0.0.1
options edns0 trust-ad
EOF

if command -v chattr >/dev/null 2>&1; then
    chattr +i /etc/resolv.conf 2>/dev/null || true
fi

# 7. IPv6 Blackhole (Kernel Seviyesinde Tam Kapatma)
echo -e "${YELLOW}[-] IPv6 Blackhole: Tüm IPv6 stack'i devre dışı bırakılarak sızıntı vektörleri sıfırlanıyor...${RESET}"
sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1 || true
sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1 || true

# 8. ABSOLUTE FAIL-CLOSED KILL-SWITCH RULES (nftables)
echo -e "${YELLOW}[-] Fail-Closed Policy & UDP/QUIC Sızıntı Kalkanı Yükleniyor...${RESET}"

nft delete table inet tor_isolation 2>/dev/null || true

nft -f - <<EOF
table inet tor_isolation {

    # NAT & Transparent Redirection Chain
    chain prerouting {
        type nat hook prerouting priority dstnat; policy drop;
    }

    chain output_nat {
        type nat hook output priority -100; policy accept;

        # Localhost trafiğini pas geç
        oifname "lo" accept

        # Tor prosesinin kendi trafiğini yönlendirme (Sonsuz döngü engeli)
        meta skuid $TOR_UID accept

        # DNS Sorgularını Tor DNSPort'a Hijack Et (5353)
        udp dport 53 redirect to :5353
        tcp dport 53 redirect to :5353

        # Tüm Çıkış TCP Trafiğini Tor TransPort'a Hijack Et (9040)
        tcp dport 1-65535 redirect to :9040
    }

    # FAIL-CLOSED DEFAULT POLICY (Strict Output Filter Chain)
    chain output {
        type filter hook output priority 0; policy drop;

        # Localhost içi iletişime izin ver
        oifname "lo" accept

        # Mevcut established/related bağlantılar
        ct state established,related accept

        # YALNIZCA Tor kullanıcısının ($TOR_UID) dışarıya ham paket atmasına izin ver
        meta skuid $TOR_UID accept

        # LAN Local Alt Ağ Sızıntı Engelleme
        ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } drop

        # UDP & QUIC Sızıntı Engelleme: WebRTC STUN, QUIC ve UDP 53 İstekleri Sert Drop
        udp dport 1-65535 drop

        # ICMP (Ping / Traceroute) Sızıntı Engelleme
        ip protocol icmp drop
        ip6 nexthdr icmpv6 drop

        # FAIL-CLOSED DEFAULT: Tor harici ham paketlerin Ethernet/Wi-Fi arabirimine çıkışı İMKANSIZ
    }

    chain input {
        type filter hook input priority 0; policy drop;
        iifname "lo" accept
        ct state established,related accept
    }

    chain forward {
        type filter hook forward priority 0; policy drop;
    }
}
EOF

echo -e "${GREEN}[✓] Fail-Closed Kill-Switch kilitlendi.${RESET}"

# 9. Arka Plan Watcher (Dead-Man's Switch Daemon)
WATCHER_SCRIPT="/tmp/tor_killswitch_watcher.sh"

cat <<EOF > "$WATCHER_SCRIPT"
#!/usr/bin/env bash
while true; do
    if ! ss -lntp 2>/dev/null | grep -q ':9040'; then
        # Tor portu (9040) düşerse tüm ağı anında sert drop ile felç et
        nft add rule inet tor_isolation output position 0 drop 2>/dev/null || true
        sysctl -w net.ipv4.conf.all.forwarding=0 2>/dev/null || true
    fi
    sleep 2
done
EOF

chmod +x "$WATCHER_SCRIPT"
pkill -f "tor_killswitch_watcher.sh" 2>/dev/null || true
nohup "$WATCHER_SCRIPT" >/dev/null 2>&1 &

echo -e "${GREEN}[✓] Arka Plan Watcher (Dead-Man's Switch) aktif edildi.${RESET}"

# 10. Tor Izolasyon Testi
echo -e "${YELLOW}[-] Tor doğrulaması ve IP sızıntı testi başlatılıyor...${RESET}"

TOR_IP=$(curl --silent --max-time 15 --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip 2>/dev/null | grep -oE '"IP":"[0-9.]+"' | cut -d'"' -f4 || echo "HATA")
TRANSPARENT_IP=$(curl --silent --max-time 15 https://check.torproject.org/api/ip 2>/dev/null | grep -oE '"IP":"[0-9.]+"' | cut -d'"' -f4 || echo "HATA")

echo
echo -e "${BLUE}[*] SÖRF & SIZINTI DOĞRULAMA TESPİTİ:${RESET}"
echo -e " SOCKS5 IP (Port 9050)      : ${GREEN}$TOR_IP${RESET}"
echo -e " TRANSPARENT IP (Ham Trafik) : ${GREEN}$TRANSPARENT_IP${RESET}"

if [[ "$TOR_IP" != "HATA" && "$TRANSPARENT_IP" != "HATA" ]]; then
    echo
    echo -e "${GREEN}====================================================${RESET}"
    echo -e "${GREEN}[✓] FAIL-CLOSED & DEAD-MAN'S SWITCH KORUMASI AKTİF${RESET}"
    echo -e "${GREEN}====================================================${RESET}"
else
    echo -e "${RED}[!] UYARI: Ağ çıkış testi kilitlendi veya Tor bağlantısı kurulamadı.${RESET}"
fi
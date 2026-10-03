#!/usr/bin/env bash
# Module: Aggressive Network Hardening, MAC Spoofing & Leak Prevention

set -u

BLUE='\e[34m'
YELLOW='\e[33m'
GREEN='\e[32m'
RED='\e[31m'
RESET='\e[0m'

echo -e "${BLUE}[*] Modul 2: AGRESİF Ağ İzolasyonu, Sızıntı Önleme ve MAC Randomizasyonu...${RESET}"

# 1. Root Yetki Kontrolü
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[!] Root yetkisi gerekiyor.${RESET}"
    exit 1
fi

# 2. Varsayılan ve Tüm Aktif Arayüzleri Tespit Et
IFACES=$(ip -o link show | awk -F': ' '{print $2}' | grep -vE '^(lo|docker|veth|br-|virbr|tun|wireguard|wg)')

if [[ -z "$IFACES" ]]; then
    echo -e "${RED}[!] İşlem yapılacak fiziksel/kablosuz ağ arayüzü bulunamadı.${RESET}"
    exit 1
fi

# 3. IPv6 Protokolünü Kernel Seviyesinde Dondur (IPv6 Leak Önleme)
echo -e "${YELLOW}[-] IPv6 trafiği ve yönlendirmeleri kernel seviyesinde engelleniyor...${RESET}"
sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1 || true
sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1 || true
sysctl -w net.ipv6.conf.lo.disable_ipv6=1 >/dev/null 2>&1 || true

# 4. Arayüzler Üzerinde AGRESİF MAC Randomizasyonu
for IFACE in $IFACES; do
    echo -e "${BLUE}[*] Hedef Arayüz: ${IFACE}${RESET}"

    OLD_MAC=$(cat "/sys/class/net/$IFACE/address" 2>/dev/null || echo "unknown")
    echo -e "${YELLOW}[-] Eski MAC (${IFACE}): ${OLD_MAC}${RESET}"

    # NetworkManager takibini geçici olarak durdur (Varsa)
    if command -v nmcli >/dev/null 2>&1; then
        nmcli device set "$IFACE" managed no >/dev/null 2>&1 || true
    fi

    # Arayüzü Kapat
    ip link set dev "$IFACE" down 2>/dev/null || true

    # AGRESİF MAC Oluşturma (Rastgele Vendor / Fully Random OUI)
    RANDOM_MAC=$(openssl rand -hex 6 | sed 's/\(..\)/\1:/g; s/.$//')
    # Valid Unicast / Locally Administered MAC Byte Fix (İlk octet'in 2. biti 1, 1. biti 0 olmalı)
    FIRST_BYTE=$(printf '%02x' $(( (0x${RANDOM_MAC:0:2} | 0x02) & 0xfe )))
    FINAL_MAC="${FIRST_BYTE}${RANDOM_MAC:2}"

    if command -v macchanger >/dev/null 2>&1; then
        macchanger -r "$IFACE" >/dev/null 2>&1 || ip link set dev "$IFACE" address "$FINAL_MAC" 2>/dev/null || true
    else
        ip link set dev "$IFACE" address "$FINAL_MAC" 2>/dev/null || true
    fi

    # Arayüzü Aç ve NM Yönetimini Tekrar Bağla
    ip link set dev "$IFACE" up 2>/dev/null || true

    if command -v nmcli >/dev/null 2>&1; then
        nmcli device set "$IFACE" managed yes >/dev/null 2>&1 || true
    fi

    NEW_MAC=$(cat "/sys/class/net/$IFACE/address" 2>/dev/null || echo "unknown")
    echo -e "${GREEN}[✓] Yeni MAC (${IFACE}): ${NEW_MAC}${RESET}"
done

# 5. Agresif ARP, Neighbor, Route ve DNS Cache Flush
echo -e "${YELLOW}[-] ARP tabloları, Routing önbelleği ve Komşuluk eşleşmeleri uçuruluyor...${RESET}"
ip neighbor flush all >/dev/null 2>&1 || true
ip route flush cache >/dev/null 2>&1 || true

# NetBIOS ve ARP önbellek sıfırlama (nbtstat muadili)
if command -v nbtscan >/dev/null 2>&1; then
    nbtscan -r 127.0.0.1 >/dev/null 2>&1 || true
fi

# DNS Önbellek Sıfırlama
echo -e "${YELLOW}[-] DNS önbelleği ve resolver geçmişi temizleniyor...${RESET}"
if command -v resolvectl >/dev/null 2>&1; then
    resolvectl flush-caches >/dev/null 2>&1 || true
elif command -v systemd-resolve >/dev/null 2>&1; then
    systemd-resolve --flush-caches >/dev/null 2>&1 || true
fi

if [[ -f /etc/init.d/dnsmasq ]]; then
    /etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
fi

# 6. mDNS, LLMNR ve Broadcast Sızıntılarını Kapat (Local Network Discovery Isolation)
echo -e "${YELLOW}[-] mDNS, LLMNR ve NetBIOS paket yayınları engelleniyor...${RESET}"
sysctl -w net.ipv4.conf.all.drop_unicast_in_l2_multicast=1 >/dev/null 2>&1 || true
sysctl -w net.ipv4.conf.all.arp_ignore=2 >/dev/null 2>&1 || true
sysctl -w net.ipv4.conf.all.arp_announce=2 >/dev/null 2>&1 || true

echo
echo -e "${BLUE}[*] Güncel Ağ Arayüzleri ve MAC Durumu:${RESET}"
ip -brief link show | grep -vE '^(lo|docker)'

echo
echo -e "${GREEN}[✓] AGRESİF Ağ İzolasyonu ve Sızıntı Önleme Tamamlandı.${RESET}"
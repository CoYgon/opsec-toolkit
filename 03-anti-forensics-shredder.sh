#!/usr/bin/env bash
# Module: Deep System Maintenance & Aggressive Purge

set -u

BLUE='\e[34m'
YELLOW='\e[33m'
GREEN='\e[32m'
RED='\e[31m'
RESET='\e[0m'

echo -e "${BLUE}[*] Modul 3: AGRESİF Sistem ve Bellek Purge İşlemi Başlatılıyor...${RESET}"

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[!] Root yetkisi gerekiyor.${RESET}"
    exit 1
fi

# 1. Shell Geçmişi ve Oturum Kalıntılarını Uçur
echo -e "${YELLOW}[-] Shell ve Kullanıcı komut geçmişleri sıfırlanıyor...${RESET}"
export HISTSIZE=0
export HISTFILESIZE=0
history -c 2>/dev/null || true

USERS_HOMES=$(cut -d: -f6 /etc/passwd 2>/dev/null || echo "/root")
for h in $USERS_HOMES; do
    if [[ -d "$h" ]]; then
        rm -rf "$h"/.bash_history "$h"/.zsh_history "$h"/.lesshst "$h"/.viminfo "$h"/.python_history "$h"/.node_repl_history "$h"/.wget-hsts 2>/dev/null || true
    fi
done

# 2. Journal Loglarını ve Systemd İzlerini Sıfırla
if command -v journalctl >/dev/null 2>&1; then
    echo -e "${YELLOW}[-] Journal logları vakumlanıyor ve sıfırlanıyor...${RESET}"
    journalctl --rotate >/dev/null 2>&1 || true
    journalctl --vacuum-time=1s >/dev/null 2>&1 || true
    journalctl --vacuum-size=1K >/dev/null 2>&1 || true
fi

# 3. /var/log Altındaki Tüm Log Dosyalarını Truncate Et (İzinleri Bozmadan Boyutunu 0 B Yap)
echo -e "${YELLOW}[-] /var/log altındaki tüm log verileri boşaltılıyor...${RESET}"
find /var/log -type f -exec truncate -s 0 {} + 2>/dev/null || true
rm -rf /var/log/*.gz /var/log/*.[0-9] /var/log/*/*.gz 2>/dev/null || true

# 4. Agresif Temp Temizliği (Yaşına Bakmaksızın /tmp ve /var/tmp Klasörlerini Sıfırla)
echo -e "${YELLOW}[-] /tmp ve /var/tmp dizinleri AGRESİF şekilde temizleniyor...${RESET}"
find /tmp -mindepth 1 -xdev -delete 2>/dev/null || true
find /var/tmp -mindepth 1 -xdev -delete 2>/dev/null || true

# 5. Kernel Ring Buffer ve Önbellek (RAM/PageCache) Purge
echo -e "${YELLOW}[-] Kernel ring buffer ve RAM önbellekleri serbest bırakılıyor...${RESET}"
dmesg -c >/dev/null 2>&1 || true
sync || true
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true

# 6. Swap Alanını Boşalt ve Sıfırla (RAM Kalıntılarını Temizler)
if [[ $(swapon --show 2>/dev/null | wc -l) -gt 1 ]]; then
    echo -e "${YELLOW}[-] Swap alanı sıfırlanıyor...${RESET}"
    swapoff -a 2>/dev/null && swapon -a 2>/dev/null || true
fi

# 7. Paket Yöneticisi Önbellekleri (Apt, Pacman, Dnf vb.)
echo -e "${YELLOW}[-] Paket yöneticisi önbellekleri temizleniyor...${RESET}"
if command -v apt-get >/dev/null 2>&1; then
    apt-get clean >/dev/null 2>&1 || true
    apt-get autoclean >/dev/null 2>&1 || true
elif command -v pacman >/dev/null 2>&1; then
    pacman -Scc --noconfirm >/dev/null 2>&1 || true
elif command -v dnf >/dev/null 2>&1; then
    dnf clean all >/dev/null 2>&1 || true
fi

# 8. Disk Durumu
echo
echo -e "${BLUE}[*] Temizlik Sonrası Disk Durumu:${RESET}"
df -h /

echo
echo -e "${GREEN}[✓] AGRESİF Purge işlemi tamamlandı. Kalıntılar temizlendi.${RESET}"
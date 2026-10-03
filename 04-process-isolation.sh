#!/usr/bin/env bash
# Module: Aggressive Process & Telemetry Isolation

set -u

BLUE='\e[34m'
YELLOW='\e[33m'
GREEN='\e[32m'
RED='\e[31m'
RESET='\e[0m'

echo -e "${BLUE}[*] Modul 4: AGRESİF Telemetri, Izleme ve Hata Raporlama Izolasyonu Başlatılıyor...${RESET}"

# 1. Root Kontrolü
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[!] Bu script root olarak çalıştırılmalı.${RESET}"
    exit 1
fi

# 2. Hedef Telemetri, Hata Raporlama ve Denetim Servisleri
TELEMETRY_SERVICES=(
    "whoopsie"
    "apport"
    "canonical-livepatch"
    "ubuntu-report"
    "pop-system-daemon"
    "kerneloops"
    "systemd-coredump"
    "auditd"
)

# 3. İlgili Socket ve Timer Birliktelikleri
TELEMETRY_SOCKETS=(
    "systemd-journald-audit.socket"
    "apport-forward.socket"
    "whoopsie.path"
)

TELEMETRY_TIMERS=(
    "motd-news.timer"
    "apt-daily.timer"
    "apt-daily-upgrade.timer"
)

# 4. Servisleri Durdur, Devre Dışı Bırak ve Maskele (Kilitle)
echo -e "${YELLOW}[-] Telemetri ve hata bildirim servisleri agresif olarak kilitleniyor...${RESET}"

for svc in "${TELEMETRY_SERVICES[@]}"; do
    if systemctl list-unit-files "$svc.service" &>/dev/null; then
        systemctl stop "$svc.service" 2>/dev/null || true
        systemctl disable "$svc.service" 2>/dev/null || true
        systemctl mask "$svc.service" 2>/dev/null || true
        echo -e "${GREEN}[✓] Servis durduruldu ve MASKELENDİ: $svc${RESET}"
    fi
done

# 5. Socket ve Path Tetikleyicilerini Kapat
echo -e "${YELLOW}[-] Telemetri socket ve yol tetikleyicileri etkisizleştiriliyor...${RESET}"
for sck in "${TELEMETRY_SOCKETS[@]}"; do
    if systemctl list-unit-files "$sck" &>/dev/null; then
        systemctl stop "$sck" 2>/dev/null || true
        systemctl disable "$sck" 2>/dev/null || true
        systemctl mask "$sck" 2>/dev/null || true
        echo -e "${GREEN}[✓] Socket/Path kilitlendi: $sck${RESET}"
    fi
done

# 6. Arka Plan Telemetri Timer'larını Maskele
echo -e "${YELLOW}[-] Zamanlanmış haberleşme ve arka plan timer'ları maskeleniyor...${RESET}"
for tmr in "${TELEMETRY_TIMERS[@]}"; do
    if systemctl list-unit-files "$tmr" &>/dev/null; then
        systemctl stop "$tmr" 2>/dev/null || true
        systemctl disable "$tmr" 2>/dev/null || true
        systemctl mask "$tmr" 2>/dev/null || true
        echo -e "${GREEN}[✓] Timer maskelendi: $tmr${RESET}"
    fi
done

# 7. Kernel Core Dump & Apport Crash Handler Engelleme
echo -e "${YELLOW}[-] Kernel seviyesinde çekirdek dökümü (Core Dump) handler'ları sıfırlanıyor...${RESET}"

# Apport crash yakalayıcısını konfigürasyondan kapat
if [[ -f /etc/default/apport ]]; then
    sed -i 's/enabled=1/enabled=0/g' /etc/default/apport 2>/dev/null || true
fi

# Kernel core_pattern alanını boşaltarak crash dump iletimini kes
if [[ -w /proc/sys/kernel/core_pattern ]]; then
    echo "core" > /proc/sys/kernel/core_pattern 2>/dev/null || true
fi

# MotD News telemetrisini sil/kapat
if [[ -f /etc/default/motd-news ]]; then
    sed -i 's/ENABLED=1/ENABLED=0/g' /etc/default/motd-news 2>/dev/null || true
fi

echo
echo -e "${GREEN}[✓] AGRESİF Telemetri ve Izleme Izolasyonu Tamamlandı.${RESET}"
#!/usr/bin/env bash
# Module: Aggressive Kernel, Memory & IPC Purge

set -u

BLUE='\e[34m'
YELLOW='\e[33m'
GREEN='\e[32m'
RED='\e[31m'
RESET='\e[0m'

echo -e "${BLUE}[*] Modul 1: AGRESİF Kernel, Bellek (RAM) ve IPC Purge Başlatılıyor...${RESET}"

# 1. Root Kontrolü
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[!] Bu script root olarak çalıştırılmalı.${RESET}"
    exit 1
fi

# 2. Disk Buffer'larını Tam Sync Et
echo -e "${YELLOW}[-] Disk buffer'ları tam sync ediliyor...${RESET}"
sync; sync

# 3. Kernel Memory Compaction & Aggressive Cache Drop
echo -e "${YELLOW}[-] Memory Compaction ve PageCache / dentries / inodes agresif bırakılıyor...${RESET}"

# RAM konfigürasyonunu ve sıkıştırmayı zorla (Memory Defrag)
if [[ -w /proc/sys/vm/compact_memory ]]; then
    echo 1 > /proc/sys/vm/compact_memory 2>/dev/null || true
fi

# PageCache, dentries ve inodes nesnelerini çekirdek seviyesinde serbest bırak
if [[ -w /proc/sys/vm/drop_caches ]]; then
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
else
    echo -e "${RED}[!] drop_caches erişilebilir değil.${RESET}"
fi

# 4. IPC (Inter-Process Communication) & Shared Memory (shm) Sıfırlama
echo -e "${YELLOW}[-] Sahipsiz paylaşımlı bellek (Shared Memory) ve IPC havuzları temizleniyor...${RESET}"
if command -v ipcrm >/dev/null 2>&1 && command -v ipcs >/dev/null 2>&1; then
    # Shared Memory Segments
    for id in $(ipcs -m | awk 'NR>3 {print $2}' | grep -E '^[0-9]+$'); do
        ipcrm -m "$id" >/dev/null 2>&1 || true
    done
    # Semaphore Arrays
    for id in $(ipcs -s | awk 'NR>3 {print $2}' | grep -E '^[0-9]+$'); do
        ipcrm -s "$id" >/dev/null 2>&1 || true
    done
    # Message Queues
    for id in $(ipcs -q | awk 'NR>3 {print $2}' | grep -E '^[0-9]+$'); do
        ipcrm -q "$id" >/dev/null 2>&1 || true
    done
fi

# /dev/shm ve /run/shm Geçici Bellek Klasörlerini Temizle
rm -rf /dev/shm/* /dev/shm/.* /run/shm/* /run/shm/.* 2>/dev/null || true

# 5. Core Dump & Crash Dump Bellek Kalıntılarını Sil
echo -e "${YELLOW}[-] Process Core Dump ve sistem crash bellek dökümleri uçuruluyor...${RESET}"
rm -rf /var/crash/* /var/lib/systemd/coredump/* 2>/dev/null || true
if [[ -w /proc/sys/kernel/core_pattern ]]; then
    ulimit -c 0 2>/dev/null || true
fi

# 6. Agresif Swap Boşaltma & RAM Sıfırlama
if swapon --show --noheadings 2>/dev/null | grep -q .; then
    echo -e "${YELLOW}[-] Swap alanı tamamen boşaltılıyor ve RAM'e çekilip sıfırlanıyor...${RESET}"

    if swapoff -a 2>/dev/null; then
        swapon -a 2>/dev/null || true
        echo -e "${GREEN}[✓] Swap alanı sıfırlandı.${RESET}"
    else
        echo -e "${RED}[!] Swap kapatılamadı. Kilitli süreçler olabilir.${RESET}"
    fi
else
    echo -e "${YELLOW}[-] Aktif swap bulunamadı.${RESET}"
fi

# 7. Kernel Ring Buffer & Pointer Kısıtlamaları (dmesg & kptr_restrict)
echo -e "${YELLOW}[-] Kernel ring buffer ve sembol adresleri kilitlenip temizleniyor...${RESET}"

# Kernel pointer adreslerini (kptr) gizle
sysctl -w kernel.kptr_restrict=2 >/dev/null 2>&1 || true
sysctl -w kernel.dmesg_restrict=1 >/dev/null 2>&1 || true

if command -v dmesg >/dev/null 2>&1; then
    dmesg -c >/dev/null 2>&1 || true
    echo -e "${GREEN}[✓] Kernel ring buffer temizlendi.${RESET}"
fi

# 8. Güncel Bellek Durumu
echo
echo -e "${BLUE}[*] Güncel Bellek Durumu:${RESET}"
free -h

echo
echo -e "${GREEN}[✓] AGRESİF Kernel ve RAM Purge tamamlandı.${RESET}"
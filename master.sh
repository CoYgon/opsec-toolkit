#!/usr/bin/env bash
# ==============================================================================
# OPSEC TOOLKIT - AGGRESSIVE ISOLATION ENGINE (AUTONOMOUS DIRECT DAEMON)
# ==============================================================================

set -euo pipefail

# Renk Tanımlamaları
RED='\e[31m'
CYAN='\e[1;36m'
GREEN='\e[1;32m'
YELLOW='\e[33m'
BOLD='\e[1m'
RESET='\e[0m'

# 1. Root Kontrolü
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[!] HATA: Bu toolkit doğrudan Kernel & Network seviyesine müdahale ettiği için ROOT yetkisi şarttır.${RESET}"
    exit 1
fi

# 2. Atomic Run & Single Instance Lock Protection
LOCK_FILE="/tmp/opsec_toolkit.lock"
if [[ -e "$LOCK_FILE" ]]; then
    PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "bilinmiyor")
    echo -e "${RED}[!] Toolkit zaten çalışıyor! (PID: $PID). Çift çalıştırılma engellendi.${RESET}"
    exit 1
fi
echo $$ > "$LOCK_FILE"

# Sinyal Yakalama ve Temiz Kapanış (Graceful Cleanup)
cleanup() {
    local exit_code=$?
    echo -e "\n${YELLOW}[-] Kapanış sinyali alındı, süreçler ve kilit temizleniyor...${RESET}"
    rm -f "$LOCK_FILE" 2>/dev/null || true
    pkill -f "tor_killswitch_watcher.sh" 2>/dev/null || true
    if [[ $exit_code -ne 0 ]]; then
        echo -e "${RED}[!] OPSEC Daemon durduruldu (Exit Code: $exit_code).${RESET}"
    fi
    exit $exit_code
}
trap cleanup EXIT SIGINT SIGTERM SIGHUP

# Betiğin Çalıştığı Ana Dizin
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# 3. Aynı Dizindeki Modüllerin Listesi
# (Aynı klasörde yer alan 01-*, 02-* tarzı .sh dosyalarını sıralı alır)
MODULES=(
    "01-kernel-memory-purge.sh"
    "02-network-check.sh"
    "03-tor-network-isolation.sh"
    "04-process-telemetry-isolation.sh"
    "05-security-audit.sh"
)

clear
echo -e "${CYAN}============================================================${RESET}"
echo -e "${CYAN}   OPSEC AUTONOMOUS DAEMON (DIRECT DIRECTORY ENFORCEMENT)   ${RESET}"
echo -e "${CYAN}============================================================${RESET}"
echo -e "${YELLOW}[-] Çalışma Dizini: $SCRIPT_DIR${RESET}"
echo -e "${YELLOW}[-] Modüller doğrulanıyor ve yetkilendiriliyor...${RESET}"

# 4. Ön Kontrol & Bütünlük Taraması
for module in "${MODULES[@]}"; do
    FILE="$SCRIPT_DIR/$module"

    if [[ ! -f "$FILE" ]]; then
        echo -e "${RED}[!] HATA: Kritik modül eksik: $FILE${RESET}"
        exit 1
    fi

    # İzinleri sadece root için kilitle
    chmod 700 "$FILE"
    chown root:root "$FILE" 2>/dev/null || true
done
echo -e "${GREEN}[✓] Tüm modüller aynı dizinde doğrulandı. Otonom döngü başlatılıyor.${RESET}\n"

# 5. OTONOM SONSUZ DÖNGÜ
CYCLE=1

while true; do
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "${CYAN}[+] DÖNGÜ #$CYCLE BAŞLADI - $TIMESTAMP${RESET}"
    echo -e "${CYAN}------------------------------------------------------------${RESET}"

    EXECUTION_SUCCESS=true

    for module in "${MODULES[@]}"; do
        FILE="$SCRIPT_DIR/$module"

        echo -e "${BOLD}${YELLOW}[*] [$TIMESTAMP] YÜRÜTÜLÜYOR: $module${RESET}"

        if command -v timeout >/dev/null 2>&1; then
            if timeout 180s "$FILE"; then
                echo -e "${GREEN}[✓] $module tamamlandı.${RESET}"
            else
                EXIT_STATUS=$?
                echo -e "${RED}[!] HATA: $module başarısız veya zaman aşımına uğradı (Kod: $EXIT_STATUS).${RESET}"
                EXECUTION_SUCCESS=false
                break
            fi
        else
            if "$FILE"; then
                echo -e "${GREEN}[✓] $module tamamlandı.${RESET}"
            else
                echo -e "${RED}[!] HATA: $module başarısız.${RESET}"
                EXECUTION_SUCCESS=false
                break
            fi
        fi
    done

    # İz ve Log Temizliği
    unset HISTFILE 2>/dev/null || true
    history -c 2>/dev/null || true

    if [[ "$EXECUTION_SUCCESS" = true ]]; then
        echo -e "${GREEN}[✓] DÖNGÜ #$CYCLE BAŞARIYLA TAMAMLANDI. KORUMA AKTİF.${RESET}"
    else
        echo -e "${RED}[!] UYARI: DÖNGÜ #$CYCLE HATA İLE BİTTİ. BİR SONRAKİ DÖNGÜ BEKLENİYOR...${RESET}"
    fi

    echo -e "${YELLOW}[i] 60 saniyelik bekleme periyoduna giriliyor (Ctrl+C ile durdurulabilir)...${RESET}\n"
    
    CYCLE=$((CYCLE + 1))
    
    # 60 Saniyelik Kesintisiz Bekleme
    sleep 60
done
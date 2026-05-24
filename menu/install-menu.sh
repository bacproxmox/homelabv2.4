#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT_DIR/utils/env-loader.sh"
source "$ROOT_DIR/utils/logging.sh"
start_log "install-menu"

run(){
  echo
  echo "▶️ $*"
  if bash "$ROOT_DIR/$1"; then
    return 0
  else
    local c=$?
    echo "❌ Script hata verdi ($c): $1"
    return "$c"
  fi
}

ensure_truenas_api_ready(){
  local api_env="${SECRETS_DIR:-/root/homelab-secrets}/truenas-api.env"
  local login_env="${SECRETS_DIR:-/root/homelab-secrets}/truenas-login.env"

  if [[ -f "$api_env" ]]; then
    echo "✅ TrueNAS API env mevcut: $api_env"
    return 0
  fi

  cat <<CHECK

TrueNAS API env henüz yok:
  $api_env

v2.4 akışı:
  1) TrueNAS manuel kurulumu bitmiş olmalı
  2) Router DHCP reservation önerisi: 02:23:14:00:01:01 -> 192.168.50.101
  3) TrueNAS WebUI > System Settings > Services > SSH açılmalı
     - Allow Password Authentication: ON
     - Password Login Groups: builtin_administrators veya truenas_admin admin grubu
     - Save, SSH Start
  4) Post-install helper tank/private import eder ve truenas-api.env oluşturur

Not: truenas_admin şifresi Option 1'de $login_env içine kaydedilmiş olmalı.
CHECK

  if [[ ! -f "$login_env" ]]; then
    echo "❌ $login_env yok. Önce Install Menu -> 1) Bootstrap secrets/env çalıştır."
    return 1
  fi

  read -r -p "TrueNAS SSH açıldıysa post-install helper şimdi çalışsın mı? [y/N]: " ans
  if [[ ! "$ans" =~ ^[Yy]$ ]]; then
    echo "ℹ️ TrueNAS post-install helper atlandı. Option 4 devam etmeyecek."
    return 1
  fi

  if ! run services/truenas/00-truenas-postinstall-import-api-network.sh; then
    echo "❌ TrueNAS post-install helper başarısız oldu."
    return 1
  fi
  [[ -f "$api_env" ]] || { echo "❌ Helper bitti ama $api_env oluşmadı."; return 1; }
  return 0
}

run_required(){
  local script="$1"
  if run "$script"; then
    return 0
  fi
  local c=$?
  echo
  echo "❌ Kritik adım başarısız oldu: $script ($c)"
  echo "Pipeline güvenli şekilde durduruldu. Loglar: ${LOG_DIR:-/root/homelab-logs}"
  return "$c"
}

run_best_effort(){
  local script="$1"
  if run "$script"; then
    return 0
  fi
  local c=$?
  echo "⚠️ Opsiyonel/devam edilebilir adım hata verdi, pipeline devam edecek: $script ($c)"
  return 0
}

run_core_services(){
  run_required services/arr/01-arr-service-install.sh || return $?
  run_required services/seerr/01-seerr-service-install.sh || return $?
  run_required services/uptime-kuma/01-uptime-kuma-service-install.sh || return $?
  run_required services/nextcloud/01-nextcloud-service-install.sh || return $?
  run_required services/jellyfin/01-jellyfin-service-install.sh || return $?
  run_required services/immich/01-immich-service-install.sh || return $?
  run_required services/ollama/01-ollama-openwebui-service-install.sh || return $?
  run_required services/lidarr/01-lidarr-service-install.sh || return $?
  run_required services/homeassistant/01-homeassistant-service-install.sh || return $?
  run_required services/pbs/01-pbs-service-install.sh || return $?
}

run_final_cloudflared(){
  cat <<'CLOUDFLARE_NOTE'

==================================================
 FINAL REMOTE ACCESS: Cloudflared
==================================================
Bu adım Cloudflare browser auth linki gösterebilir.
Bu yüzden ana kurulumun sonunda çalıştırılır; local servisler kurulmadan pipeline'ı bekletmez.

Cloudflared tamamlanınca uzak erişim/DNS tunnel config aktif olur.
CLOUDFLARE_NOTE
  echo
  read -r -p "Cloudflared final remote access setup şimdi çalışsın mı? [y/N]: " cf_ans
  if [[ ! "$cf_ans" =~ ^[Yy]$ ]]; then
    echo "ℹ️ Cloudflared final setup atlandı. Daha sonra Install Menu -> 14 ile çalıştırabilirsin."
    return 0
  fi
  run_required services/cloudflared/01-cloudflared-service-install.sh || return $?
}

run_repair_basics(){
  run_best_effort config/nextcloud/01-nextcloud-local-and-cloudflare-fix.sh
  run_best_effort config/nextcloud/04-bacscloud-production-hardening.sh
  run_best_effort config/immich/01-immich-storage-verify.sh
  run_best_effort services/cloudflared/02-generate-ingress-config-reference.sh
}

run_phase4(){
  run_best_effort config/smtp/01-write-service-smtp-reference.sh
  run_best_effort config/uptime-kuma/02-uptime-kuma-auto-config.sh
  run_required services/chia/01-chia-farmer-service-install.sh || return $?
}

run_full_install_pipeline(){
  clear || true
  cat <<'PIPE'
=========================================
 Homelab v2.4 - Guided full pipeline
=========================================
Bu seçenek mevcut mimariyi bozmaz; menüdeki scriptleri sırayla çağırır.

Akış:
  1) Bootstrap secrets/env
  2) Create Proxmox users
  12) Normalize Proxmox local storage
  3) Install TrueNAS VM 101

Sonra bilinçli manuel durak:
  - TrueNAS installer'ı VM console'dan manuel bitir
  - Router reservation önerisi: 02:23:14:00:01:01 -> 192.168.50.101
  - TrueNAS WebUI'den SSH'i aç

Devamında otomatik:
  4) TrueNAS postinstall + storage bootstrap + VM102-107 + VM110 PBS
  5) Prepare all Docker hosts
  6) Install core services
  7) Configure / repair basics
  8) Run all core config scripts
  9) SMTP / Uptime Kuma / Chia

Not: Cloudflared browser auth artık ana servis kurulumunu bekletmesin diye final aşamasına taşındı.
PIPE
  echo
  read -r -p "Bu uzun pipeline başlasın mı? [y/N]: " start_ans
  [[ "$start_ans" =~ ^[Yy]$ ]] || { echo "İptal edildi."; return 0; }

  echo
  echo "==================== PHASE A: Proxmox hazırlık ===================="
  run_required bootstrap/00-bootstrap-secrets.sh || return $?
  run_required bootstrap/01-create-proxmox-users.sh || return $?
  run_best_effort bootstrap/02-normalize-local-storage.sh

  echo
  echo "==================== PHASE B: TrueNAS VM 101 ===================="
  run_required vm/101-truenas-vm-install.sh || return $?

  cat <<'MANUAL'

==================================================
 MANUEL DURAK: TrueNAS kurulumu + SSH açma
==================================================
1) Proxmox VM101 console'dan TrueNAS installer'ı manuel bitir.
2) Kurulumda sadece 64GB OS diskini seç.
3) VM reboot sonrası TrueNAS WebUI genelde burada olmalı:
     http://192.168.50.101
4) WebUI > System Settings > Services > SSH > Edit:
   - Allow Password Authentication: ON
   - Password Login Groups: builtin_administrators veya truenas_admin'in admin grubu
   - Save
   - SSH Start
   - İstersen Start Automatically açık kalsın

Hazır olunca pipeline devam edip TrueNAS post-install helper'ı çalıştıracak.
MANUAL
  echo
  read -r -p "TrueNAS manuel kurulum bitti ve SSH açıldı mı? [y/N]: " tn_ans
  if [[ ! "$tn_ans" =~ ^[Yy]$ ]]; then
    echo "Pipeline burada durduruldu. Hazır olunca Install Menu -> 4 veya bu pipeline tekrar çalıştırılabilir."
    return 1
  fi

  echo
  echo "==================== PHASE C: TrueNAS API/storage + VM102-107 + VM110 ===================="
  ensure_truenas_api_ready || return $?
  run_required services/truenas/01-truenas-api-bootstrap-storage.sh || return $?
  run_required vm/102-docker-arr-vm-install.sh || return $?
  run_required vm/103-network-vm-install.sh || return $?
  run_required vm/104-nextcloud-vm-install.sh || return $?
  run_required vm/105-homeassistant-vm-install.sh || return $?
  run_required vm/106-media-ai-vm-install.sh || return $?
  run_required vm/107-chia-farmer-vm-install.sh || return $?
  run_required vm/110-pbs-backup-vm-install.sh || return $?

  echo
  echo "==================== PHASE D: Docker host hazırlığı ===================="
  run_required services/common/01-prepare-all-docker-hosts.sh || return $?

  echo
  echo "==================== PHASE E: Core service install ===================="
  run_core_services || return $?

  echo
  echo "==================== PHASE F: Basic repair/config ===================="
  run_repair_basics

  echo
  echo "==================== PHASE G: Phase 3 service config ===================="
  run_best_effort config/00-run-all-core-config.sh

  echo
  echo "==================== PHASE H: Phase 4 SMTP / Chia ===================="
  run_phase4 || return $?

  echo
  echo "==================== PHASE I: Final Cloudflared remote access ===================="
  run_final_cloudflared || return $?

  echo
  echo "==================== FINAL HEALTH CHECKS ===================="
  run_best_effort maintenance/health/vm-resource-audit.sh
  run_best_effort maintenance/health/full-health-check.sh
  run_best_effort maintenance/health/full-service-audit.sh

  echo
  echo "✅ Guided full pipeline tamamlandı."
  echo "Loglar: ${LOG_DIR:-/root/homelab-logs}"
}

while true; do
  clear || true
  cat <<'MENU'
=========================================
 Homelab v2.4 - Install Menu
=========================================
0) Guided full install pipeline (1→9 + final Cloudflared, TrueNAS manuel duraklı)
1) Bootstrap secrets/env
2) Create Proxmox users
3) Install TrueNAS VM 101
4) Bootstrap TrueNAS storage + install all VMs except TrueNAS
5) Prepare all Docker hosts
6) Install core local services (Cloudflared auth yok)
7) Configure / repair basics
8) Phase 3 service configuration
9) Phase 4 Chia / SMTP
10) Maintenance menu
11) Additionals menu
12) Normalize Proxmox local storage
13) Exit
14) Final Cloudflared remote access setup
MENU
  read -r -p "Seçim: " choice
  case "$choice" in
    0) run_full_install_pipeline ;;
    1) run bootstrap/00-bootstrap-secrets.sh ;;
    2) run bootstrap/01-create-proxmox-users.sh ;;
    3) run vm/101-truenas-vm-install.sh ;;
    4)
      if ensure_truenas_api_ready; then
        run services/truenas/01-truenas-api-bootstrap-storage.sh
        run vm/102-docker-arr-vm-install.sh
        run vm/103-network-vm-install.sh
        run vm/104-nextcloud-vm-install.sh
        run vm/105-homeassistant-vm-install.sh
        run vm/106-media-ai-vm-install.sh
        run vm/107-chia-farmer-vm-install.sh
        run vm/110-pbs-backup-vm-install.sh
      else
        echo "❌ TrueNAS API hazır değil; VM bootstrap aşaması güvenli şekilde durduruldu."
      fi ;;
    5) run services/common/01-prepare-all-docker-hosts.sh ;;
    6) run_core_services ;;
    7) run_repair_basics ;;
    8) bash "$ROOT_DIR/menu/config-menu.sh" ;;
    9) run_phase4 ;;
    10) bash "$ROOT_DIR/menu/maintenance-menu.sh" ;;
    11) bash "$ROOT_DIR/menu/additionals-menu.sh" ;;
    12) run bootstrap/02-normalize-local-storage.sh ;;
    13) exit 0 ;;
    14) run_final_cloudflared ;;
    *) echo "Geçersiz seçim"; sleep 2 ;;
  esac
  read -r -p "Devam için Enter..." _
done

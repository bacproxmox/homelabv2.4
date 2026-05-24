#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/env-loader.sh"
source "$SCRIPT_DIR/../utils/logging.sh"
source "$SCRIPT_DIR/../utils/env-write.sh"
start_log "bootstrap-secrets"
require_root

ask_visible_confirm() {
  local var="$1" prompt="$2" a="" b=""
  while true; do
    read -r -p "$prompt: " a
    read -r -p "$prompt tekrar: " b
    [[ -n "$a" ]] || { echo "❌ Boş bırakılamaz."; continue; }
    [[ "$a" == "$b" ]] || { echo "❌ Girdiler eşleşmedi."; continue; }
    printf -v "$var" "%s" "$a"
    break
  done
}

ask_visible_once() {
  local var="$1" prompt="$2" value=""
  read -r -p "$prompt: " value
  printf -v "$var" "%s" "$value"
}

ask_text_default() {
  local var="$1" prompt="$2" def="$3" value=""
  if [[ -n "$def" ]]; then
    read -r -p "$prompt [$def]: " value
    printf -v "$var" "%s" "${value:-$def}"
  else
    read -r -p "$prompt: " value
    printf -v "$var" "%s" "$value"
  fi
}

mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

# v2.2 uyumluluğu: eski scriptlerin /root/.secrets aramasını bozma.
if [[ ! -e /root/.secrets ]]; then
  ln -s "$SECRETS_DIR" /root/.secrets
elif [[ -d /root/.secrets && ! -L /root/.secrets ]]; then
  echo "ℹ️ /root/.secrets mevcut; homelab-secrets ile senkron kullanılacak."
fi

echo
echo "🔐 Homelab v2.4 - secrets/env bootstrap"
echo "Klasör: $SECRETS_DIR"
echo "Not: Gizli input yok. Yazdığın değerler terminalde görünür."
echo

if [[ ! -f "$SECRETS_DIR/global.env" ]]; then
  DOMAIN="bacmastercloud.com"
  LAN_GW="192.168.50.1"
  LAN_DNS="1.1.1.1"
  VM_STORAGE="nvme-vm"
  echo "🏗️ Mimari varsayılanları otomatik kullanılacak:"
  echo "  DOMAIN=$DOMAIN"
  echo "  LAN_GW=$LAN_GW"
  echo "  LAN_DNS=$LAN_DNS"
  echo "  VM_STORAGE=$VM_STORAGE"
  read -r -p "Advanced override ister misin? [y/N]: " ADVANCED_OVERRIDE
  if [[ "${ADVANCED_OVERRIDE:-N}" =~ ^[Yy]$ ]]; then
    ask_text_default DOMAIN "Ana domain" "$DOMAIN"
    ask_text_default LAN_GW "Gateway" "$LAN_GW"
    ask_text_default LAN_DNS "DNS" "$LAN_DNS"
    ask_text_default VM_STORAGE "Proxmox VM storage" "$VM_STORAGE"
  fi
  {
    write_env_header
    write_env_line HOMELAB_VERSION "2.4"
    write_env_line DOMAIN "$DOMAIN"
    write_env_line LAN_GW "$LAN_GW"
    write_env_line LAN_DNS "$LAN_DNS"
    write_env_line VM_STORAGE "$VM_STORAGE"
    write_env_line STACKS_DIR "/opt/homelab"
    write_env_line DOCKER_NETWORK "homelab"
    write_env_line TZ "Europe/Istanbul"
    write_env_line VM101_MAC "02:23:14:00:01:01"
    write_env_line VM102_MAC "02:23:14:00:01:02"
    write_env_line VM103_MAC "02:23:14:00:01:03"
    write_env_line VM104_MAC "02:23:14:00:01:04"
    write_env_line VM105_MAC "02:23:14:00:01:05"
    write_env_line VM106_MAC "02:23:14:00:01:06"
    write_env_line VM107_MAC "02:23:14:00:01:07"
    write_env_line VM110_MAC "02:23:14:00:01:10"
  } > "$SECRETS_DIR/global.env"
  chmod 600 "$SECRETS_DIR/global.env"
fi

if [[ ! -f "$SECRETS_DIR/users.env" ]]; then
  ask_visible_confirm BACMASTER_PASS "bacmaster şifresi"
  ask_visible_confirm TULUMBA_PASS "tulumba şifresi"
  ask_visible_confirm MEDIA_PASS "media servis kullanıcısı şifresi"
  ask_visible_confirm BACKUP_PASS "backup kullanıcısı/PBS şifresi"
  ask_visible_confirm ATLON_PASS "Jellyfin atlon şifresi"
  ask_visible_confirm ELIFEZEL_PASS "Jellyfin elifezel şifresi"
  {
    write_env_header
    write_env_line MEDIA_USER "media"
    write_env_line MEDIA_PASS "$MEDIA_PASS"
    write_env_line MEDIA_UID "1000"
    write_env_line MEDIA_GID "1000"
    write_env_line BACMASTER_USER "bacmaster"
    write_env_line BACMASTER_PASS "$BACMASTER_PASS"
    write_env_line BACMASTER_UID "1100"
    write_env_line BACMASTER_GID "1100"
    write_env_line TULUMBA_USER "tulumba"
    write_env_line TULUMBA_PASS "$TULUMBA_PASS"
    write_env_line TULUMBA_UID "1200"
    write_env_line TULUMBA_GID "1200"
    write_env_line BACKUP_USER "backup"
    write_env_line BACKUP_PASS "$BACKUP_PASS"
    write_env_line BACKUP_UID "1300"
    write_env_line BACKUP_GID "1300"
    write_env_line ATLON_USER "atlon"
    write_env_line ATLON_PASS "$ATLON_PASS"
    write_env_line ELIFEZEL_USER "elifezel"
    write_env_line ELIFEZEL_PASS "$ELIFEZEL_PASS"
    write_env_line NEXTCLOUD_ADMIN_USER "bacmaster"
    write_env_line NEXTCLOUD_ADMIN_PASS "$BACMASTER_PASS"
    write_env_line NEXTCLOUD_DB_PASS "$MEDIA_PASS"
    write_env_line IMMICH_ADMIN_EMAIL "admin@bacmastercloud.com"
    write_env_line IMMICH_ADMIN_PASS "$BACMASTER_PASS"
    write_env_line IMMICH_SECOND_USER_EMAIL "cinarburhan1601@gmail.com"
    write_env_line IMMICH_SECOND_USER_PASS "$BACMASTER_PASS"
    write_env_line OPENWEBUI_ADMIN_EMAIL "admin@bacmastercloud.com"
    write_env_line OPENWEBUI_ADMIN_PASS "$BACMASTER_PASS"
    write_env_line ARR_USER "bacmaster"
    write_env_line ARR_PASS "$BACMASTER_PASS"
  } > "$SECRETS_DIR/users.env"
  chmod 600 "$SECRETS_DIR/users.env"
fi

if [[ ! -f "$SECRETS_DIR/truenas-login.env" ]]; then
  echo
  echo "🧊 TrueNAS SSH login bilgisi"
  echo "Bu şifre, manuel TrueNAS kurulumundan sonra WebUI'den SSH'i açınca post-install helper tarafından kullanılacak."
  echo "Kullanıcı sabit: truenas_admin"
  ask_visible_confirm TRUENAS_SSH_PASS "TrueNAS truenas_admin şifresi"
  {
    write_env_header
    write_env_line TRUENAS_VMID "101"
    write_env_line TRUENAS_SSH_USER "truenas_admin"
    write_env_line TRUENAS_SSH_PASS "$TRUENAS_SSH_PASS"
    write_env_line TRUENAS_HOST "192.168.50.101"
    write_env_line TRUENAS_FINAL_IP "192.168.50.101"
    write_env_line TRUENAS_GATEWAY "192.168.50.1"
    write_env_line TRUENAS_DNS1 "192.168.50.1"
    write_env_line TRUENAS_DNS2 "192.168.50.1"
    write_env_line TRUENAS_DNS3 "1.1.1.1"
    write_env_line TRUENAS_FIXED_MAC "02:23:14:00:01:01"
  } > "$SECRETS_DIR/truenas-login.env"
  chmod 600 "$SECRETS_DIR/truenas-login.env"
else
  echo "✅ TrueNAS SSH login env mevcut: $SECRETS_DIR/truenas-login.env"
fi

if [[ ! -f "$SECRETS_DIR/smtp.env" ]]; then
  echo
  echo "📧 SMTP app password bilgileri. Boş bırakırsan ilgili servis sonra atlanır."
  ask_visible_once ZOHO_NEXTCLOUD_APP_PASS "Zoho Nextcloud app password"
  ask_visible_once ZOHO_IMMICH_APP_PASS "Zoho Immich app password"
  ask_visible_once ZOHO_SEERR_APP_PASS "Zoho Seerr app password"
  ask_visible_once ZOHO_UPTIME_KUMA_APP_PASS "Zoho Uptime Kuma app password"
  ask_visible_once ZOHO_TRUENAS_APP_PASS "Zoho TrueNAS app password"
  {
    write_env_header
    write_env_line SMTP_FROM "admin@bacmastercloud.com"
    write_env_line SMTP_HOST "smtppro.zoho.eu"
    write_env_line SMTP_PORT "465"
    write_env_line SMTP_SECURITY "SSL/TLS"
    write_env_line SMTP_SECURE "ssl"
    write_env_line SMTP_TEST_TO "admin@bacmastercloud.com"
    write_env_line ZOHO_NEXTCLOUD_APP_PASS "$ZOHO_NEXTCLOUD_APP_PASS"
    write_env_line ZOHO_IMMICH_APP_PASS "$ZOHO_IMMICH_APP_PASS"
    write_env_line ZOHO_SEERR_APP_PASS "$ZOHO_SEERR_APP_PASS"
    write_env_line ZOHO_JELLYSEERR_APP_PASS "$ZOHO_SEERR_APP_PASS"
    write_env_line ZOHO_UPTIME_KUMA_APP_PASS "$ZOHO_UPTIME_KUMA_APP_PASS"
    write_env_line ZOHO_TRUENAS_APP_PASS "$ZOHO_TRUENAS_APP_PASS"
  } > "$SECRETS_DIR/smtp.env"
  chmod 600 "$SECRETS_DIR/smtp.env"
fi

if [[ ! -f "$SECRETS_DIR/google.env" ]]; then
  ask_text_default GOOGLE_CLIENT_ID "Google Client ID" ""
  ask_visible_once GOOGLE_CLIENT_SECRET "Google Client Secret"
  {
    write_env_header
    write_env_line GOOGLE_CLIENT_ID "$GOOGLE_CLIENT_ID"
    write_env_line GOOGLE_CLIENT_SECRET "$GOOGLE_CLIENT_SECRET"
  } > "$SECRETS_DIR/google.env"
  chmod 600 "$SECRETS_DIR/google.env"
fi

if [[ ! -f "$SECRETS_DIR/cloudflare.env" ]]; then
  {
    write_env_header
    write_env_line CLOUDFLARE_AUTH_MODE "interactive-login"
    write_env_line CLOUDFLARE_NOTE "cloudflared tunnel login will be used during cloudflared install; no token is requested at bootstrap"
  } > "$SECRETS_DIR/cloudflare.env"
  chmod 600 "$SECRETS_DIR/cloudflare.env"
fi

if [[ ! -f /root/.ssh/id_ed25519 ]]; then
  echo "🔑 Proxmox root SSH key oluşturuluyor..."
  ssh-keygen -t ed25519 -N "" -f /root/.ssh/id_ed25519
else
  echo "✅ SSH key mevcut."
fi

chmod 700 /root/.ssh
chmod 600 "$SECRETS_DIR"/*.env

echo
echo "✅ Secrets hazır."
ls -lah "$SECRETS_DIR"

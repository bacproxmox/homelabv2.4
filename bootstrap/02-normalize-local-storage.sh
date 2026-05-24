#!/usr/bin/env bash
set -Eeuo pipefail

STORAGE_CFG="/etc/pve/storage.cfg"
BACKUP_DIR="/root/homelab-backups/storage"
mkdir -p "$BACKUP_DIR"

echo
echo "🧩 Proxmox local storage normalize ediliyor..."

if [[ ! -f "$STORAGE_CFG" ]]; then
  echo "❌ $STORAGE_CFG bulunamadı. Bu script Proxmox host üzerinde çalışmalı."
  exit 1
fi

cp "$STORAGE_CFG" "$BACKUP_DIR/storage.cfg.backup.before-local.$(date +%F-%H%M%S)"

# Disabled/legacy dir: local bloğunu kaldır.
awk '
BEGIN { skip=0 }
$0=="dir: local" { skip=1; next }
skip && NF==0 { skip=0; next }
!skip { print }
' "$STORAGE_CFG" > /tmp/storage.cfg.new

cat /tmp/storage.cfg.new > "$STORAGE_CFG"

# Fresh BTRFS kurulumlarında local storage farklı isimlerle gelebiliyor.
# Homelab scriptleri klasik local:iso/... beklediği için normalize ediyoruz.
sed -i   -e 's/^btrfs: local-system$/btrfs: local/'   -e 's/^btrfs: local-btrfs$/btrfs: local/'   "$STORAGE_CFG"

# Eski hatalı apt backup dosyalarını sources.list.d dışına taşı; apt warninglerini susturur.
APT_BACKUP_DIR="/root/homelab-backups/apt-sources"
mkdir -p "$APT_BACKUP_DIR"
find /etc/apt/sources.list.d -maxdepth 1 -type f   \( -name '*.backup.*' -o -name '*.bak.*' \)   -exec mv -f {} "$APT_BACKUP_DIR/" \; 2>/dev/null || true

echo
echo "===== Yeni storage.cfg ====="
cat "$STORAGE_CFG"

echo
echo "===== Proxmox storage durumu ====="
pvesm status || true

echo
echo "✅ local storage normalize tamamlandı."

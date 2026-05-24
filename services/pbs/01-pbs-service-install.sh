#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "pbs-service-install"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"

: "${BACKUP_USER:=backup}"
: "${BACKUP_PASS:?BACKUP_PASS eksik. Önce Install Menu -> 1 Bootstrap secrets/env çalıştır.}"

PBS_VM="110"
PBS_IP="192.168.50.110"
TMP_REMOTE="/tmp/homelab-pbs-install-remote.sh"
ENV_REMOTE="/tmp/homelab-pbs.env"

sq() { printf "%s" "$1" | sed "s/'/'\\''/g; s/^/'/; s/$/'/"; }

cat > /tmp/homelab-pbs.env <<ENV
BACKUP_USER=$(sq "$BACKUP_USER")
BACKUP_PASS=$(sq "$BACKUP_PASS")
PBS_DATASTORE_NAME=homelab
PBS_DATASTORE_PATH=/backup/datastore/homelab
ENV
chmod 600 /tmp/homelab-pbs.env

cat > /tmp/homelab-pbs-install-remote.sh <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

log(){ echo "[$(date -Is)] $*"; }
need_env(){ local v="$1"; [[ -n "${!v:-}" ]] || { echo "❌ $v eksik"; exit 1; }; }
need_env BACKUP_USER
need_env BACKUP_PASS
PBS_DATASTORE_NAME="${PBS_DATASTORE_NAME:-homelab}"
PBS_DATASTORE_PATH="${PBS_DATASTORE_PATH:-/backup/datastore/homelab}"

log "PBS base update/upgrade başlıyor..."
apt-get update
apt-get dist-upgrade -y
apt-get install -y wget curl ca-certificates gnupg lsb-release jq openssh-server sudo

CODENAME="$(. /etc/os-release; echo "${VERSION_CODENAME:-}")"
if [[ "$CODENAME" != "trixie" ]]; then
  echo "⚠️ Bu script Proxmox Backup Server 4.x için Debian 13/Trixie bekliyor. Algılanan codename: ${CODENAME:-unknown}"
  echo "Yine de devam edilecek; apt repo trixie olarak ayarlanacak."
  CODENAME="trixie"
fi

log "Proxmox Backup Server no-subscription repo ekleniyor..."
wget -qO /usr/share/keyrings/proxmox-archive-keyring.gpg https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg
cat >/etc/apt/sources.list.d/proxmox-pbs.sources <<PBSREPO
Types: deb
URIs: http://download.proxmox.com/debian/pbs
Suites: ${CODENAME}
Components: pbs-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
PBSREPO

# Enterprise repo varsa subscription hatası üretmesin.
if [[ -f /etc/apt/sources.list.d/pbs-enterprise.sources ]]; then
  sed -i 's/^Enabled: true/Enabled: false/i' /etc/apt/sources.list.d/pbs-enterprise.sources || true
fi
if [[ -f /etc/apt/sources.list.d/pbs-enterprise.list ]]; then
  sed -i 's/^deb /# deb /' /etc/apt/sources.list.d/pbs-enterprise.list || true
fi

apt-get update
log "proxmox-backup-server kuruluyor..."
apt-get install -y proxmox-backup-server

log "backup Linux/PAM kullanıcısı hazırlanıyor..."
if ! id "$BACKUP_USER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$BACKUP_USER"
fi
echo "${BACKUP_USER}:${BACKUP_PASS}" | chpasswd
usermod -aG sudo "$BACKUP_USER" || true

# PBS user/ACL best effort. PAM kullanıcısı Linux tarafında var; PBS tarafında görünür ve Admin yetkisi verilir.
log "PBS kullanıcı/ACL ayarlanıyor: ${BACKUP_USER}@pam"
proxmox-backup-manager user create "${BACKUP_USER}@pam" 2>/dev/null || proxmox-backup-manager user update "${BACKUP_USER}@pam" --enable true 2>/dev/null || true
proxmox-backup-manager acl update / Admin --auth-id "${BACKUP_USER}@pam" || true

log "Varsayılan datastore hazırlanıyor: ${PBS_DATASTORE_NAME} -> ${PBS_DATASTORE_PATH}"
mkdir -p "$PBS_DATASTORE_PATH"
chown backup:backup "$PBS_DATASTORE_PATH" 2>/dev/null || true
if ! proxmox-backup-manager datastore list --output-format json 2>/dev/null | jq -e --arg n "$PBS_DATASTORE_NAME" '.[]? | select(.name==$n)' >/dev/null 2>&1; then
  proxmox-backup-manager datastore create "$PBS_DATASTORE_NAME" "$PBS_DATASTORE_PATH" || echo "⚠️ Datastore create başarısız/atlanmış olabilir. WebUI'den kontrol et."
else
  echo "✅ Datastore zaten mevcut: $PBS_DATASTORE_NAME"
fi
proxmox-backup-manager acl update "/datastore/${PBS_DATASTORE_NAME}" DatastoreAdmin --auth-id "${BACKUP_USER}@pam" || true

systemctl enable --now proxmox-backup-proxy proxmox-backup || true
sleep 3

log "PBS status"
systemctl --no-pager --full status proxmox-backup-proxy || true
ss -ltnp | grep ':8007' || true
proxmox-backup-manager version || true

echo
cat <<DONE
✅ Proxmox Backup Server kurulum denemesi tamamlandı.
Web UI:
  https://192.168.50.110:8007
Login:
  ${BACKUP_USER}@pam
  şifre: /root/homelab-secrets/users.env içindeki BACKUP_PASS
Datastore:
  ${PBS_DATASTORE_NAME} -> ${PBS_DATASTORE_PATH}
DONE
REMOTE
chmod +x /tmp/homelab-pbs-install-remote.sh

wait_ssh "$PBS_VM"
scp "${SSH_OPTS[@]}" /tmp/homelab-pbs.env "$SSH_USER@$PBS_IP:$ENV_REMOTE" >/dev/null
scp "${SSH_OPTS[@]}" /tmp/homelab-pbs-install-remote.sh "$SSH_USER@$PBS_IP:$TMP_REMOTE" >/dev/null
ssh "${SSH_OPTS[@]}" "$SSH_USER@$PBS_IP" "chmod +x '$TMP_REMOTE' && sudo bash -c 'set -a; source $ENV_REMOTE; set +a; $TMP_REMOTE; rm -f $ENV_REMOTE'"

rm -f /tmp/homelab-pbs.env /tmp/homelab-pbs-install-remote.sh

echo "✅ PBS service install tamamlandı: https://192.168.50.110:8007"

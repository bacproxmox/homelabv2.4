#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

echo "========================================="
echo " Homelab v2.3 - Repo Audit"
echo "========================================="

fail=0

check() {
  local name="$1" cmd="$2"
  echo
  echo "▶️ $name"
  if bash -c "$cmd"; then
    echo "✅ OK: $name"
  else
    echo "❌ FAIL: $name"
    fail=1
  fi
}

check "Bash syntax" 'find . -name "*.sh" -print0 | xargs -0 -n1 bash -n'
check "Executable scripts" 'missing=$(find . -name "*.sh" ! -perm -111); [[ -z "$missing" ]] || { echo "$missing"; exit 1; }'
check "No old starter naming" '! grep -R "homelabv2.3-starter\|starter repo" -n . --exclude-dir=.git --exclude=audit-repo.sh'
check "No placeholder TrueNAS warning in executable flow" '! grep -R "starter dosya" -n vm services config menu maintenance utils bootstrap* lib gpu docs README.md --exclude=audit-repo.sh'
check "Required directories" 'for d in bootstrap vm services config menu utils maintenance lib docs gpu additionals; do [[ -d "$d" ]] || exit 1; done'
check "Core bootstrap exists" '[[ -f bootstrap.sh && -f menu/install-menu.sh && -f utils/env-loader.sh && -f utils/env-write.sh ]]'
check "Required service installers" 'for f in services/arr/01-arr-service-install.sh services/seerr/01-seerr-service-install.sh services/uptime-kuma/01-uptime-kuma-service-install.sh services/nextcloud/01-nextcloud-service-install.sh services/jellyfin/01-jellyfin-service-install.sh services/immich/01-immich-service-install.sh services/ollama/01-ollama-openwebui-service-install.sh services/lidarr/01-lidarr-service-install.sh services/homeassistant/01-homeassistant-service-install.sh services/cloudflared/01-cloudflared-service-install.sh; do [[ -f "$f" ]] || { echo "missing $f"; exit 1; }; done'

if [[ "$fail" -eq 0 ]]; then
  echo
  echo "✅ Repo audit temiz."
else
  echo
  echo "❌ Repo audit hata buldu."
fi
exit "$fail"

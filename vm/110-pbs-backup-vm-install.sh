#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/utils/logging.sh"
start_log "vm-110-pbs-backup"
source "$REPO_ROOT/lib/vm-cloudinit-common.sh"

# PBS server packages are officially installed on Debian.  Keep the same cloud-init
# VM flow as the Ubuntu app VMs, but use Debian 13/Trixie as the base image.
create_debian_vm 110 "pbs-backup" "192.168.50.110/24" 8192 4 256G "no" "none"

echo "✅ VM110 hazır: pbs-backup"
echo "   Web UI service kurulumundan sonra: https://192.168.50.110:8007"

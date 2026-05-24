# Homelab v2.4

Proxmox + TrueNAS + Docker service automation package.

## Bootstrap

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/bacproxmox/homelabv2.4/main/bootstrap.sh)
```

## v2.4 focus

- TrueNAS post-install helper integrated into the install flow.
- Option 1 now stores `truenas_admin` SSH credentials in `/root/homelab-secrets/truenas-login.env`.
- VM101 now uses fixed MAC `02:23:14:00:01:01`; router DHCP reservation to `192.168.50.101` is recommended.
- Option 4 no longer asks for a TrueNAS API key; it uses `/root/homelab-secrets/truenas-api.env` or runs the helper first.
- TrueNAS helper imports `tank` and `private`, creates the API key, writes env files, applies DNS/network settings, and reboots TrueNAS.
- VM102-VM107 now get stable fixed MACs by default from `02:23:14:00:01:02` through `02:23:14:00:01:07`.
- Existing v2.3.13 stabilization fixes are retained.


## v2.4

See `docs/RELEASE-2.4.md` for the stabilization/polish changelog.

- Install Menu option `0` adds a guided full pipeline that calls existing steps 1→9 with the TrueNAS manual checkpoint preserved.


### PBS Backup VM

- VM110 `pbs-backup` is added for Proxmox Backup Server at `192.168.50.110`, fixed MAC `02:23:14:00:01:10`.
- PBS is installed on Debian via the official Proxmox Backup Server APT repository, because the server package is documented for Debian-based PBS installs.

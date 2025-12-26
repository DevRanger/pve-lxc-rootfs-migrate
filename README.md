# Proxmox LXC RootFS Migrator (local-lvm)

A safety-first script to migrate a Proxmox **LXC container root filesystem**
from one LVM-thin volume to a new, correctly sized one.

This is intended for situations where:
- a container disk was accidentally resized to an absurd size (e.g. TB instead of GB)
- shrinking is not supported by Proxmox
- rebuilding the container is undesirable

---

## ⚠️ Disclaimer

This software is provided **“as is”**, without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and noninfringement.

This script performs **low-level storage operations** and may modify or permanently delete storage volumes.  
If used incorrectly, it **may result in data loss, system downtime, or an unbootable container**.

- **Do not run this in a production environment**
- **Test thoroughly in a non-production / lab environment first**
- **Ensure you have verified and restorable backups before use**

In no event shall the author(s) or copyright holder(s) be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.

---

## Scope & Limitations

Supported:
- Proxmox VE
- LXC containers
- local-lvm (LVM-thin)
- ext4 root filesystem

Not supported:
- QEMU VMs
- ZFS rootfs
- Ceph / RBD
- directory-backed storage
- bind-mounted rootfs

---

## How it works (high level)

1. Stops the container
2. Allocates a new LVM-thin volume
3. Temporarily mounts it inside the container
4. Rsyncs / into the new volume
5. Swaps rootfs in /etc/pve/lxc/<CTID>.conf
6. Boots the container on the new root
7. Optionally deletes the old volume

---

## Installation

```bash
git clone https://github.com/DevRanger/pve-lxc-rootfs-migrate.git
cd pve-lxc-rootfs-migrate
chmod +x pve-lxc-rootfs-migrate.sh
```

---

## Usage

```bash
sudo ./pve-lxc-rootfs-migrate.sh --ctid <CTID> --size <GiB> [options]
```

---

## Required arguments

--ctid <id>
  LXC container ID (example: 126)

--size <GiB>
  New root filesystem size in GiB (example: 128)

---

## Optional arguments

--dry-run
  Print actions without making changes (recommended first run)

--delete-old
  Delete the old rootfs LV after successful migration (DESTRUCTIVE)

--yes
  Non-interactive mode (assume yes for prompts)

--mount <path>
  Temporary mount path inside the container (default: /mnt/newroot)

--mpid <N>
  Explicit mount point ID (mp0, mp1, etc). Auto-selected if omitted

--keep-mp
  Keep the temporary mount point in the container config (not recommended)

---

## Examples

Dry run (recommended):
```bash
sudo ./pve-lxc-rootfs-migrate.sh --ctid 126 --size 128 --dry-run
```

Migrate rootfs (leave old disk orphaned):
```bash
sudo ./pve-lxc-rootfs-migrate.sh --ctid 126 --size 128
```

Migrate and delete old disk (destructive):
```bash
sudo ./pve-lxc-rootfs-migrate.sh --ctid 126 --size 128 --delete-old
```

Fully non-interactive:
```bash
sudo ./pve-lxc-rootfs-migrate.sh --ctid 126 --size 128 --delete-old --yes
```

---

## Verification

Inside the container:
```bash
pct enter <CTID>
df -h /
```

Expected:
- Root filesystem reflects the new size (e.g. ~125G)

On the host:
```bash
lvs | grep vm-<CTID>
```

If --delete-old was used, only the new disk should remain.

---

## Rollback

A backup of the container config is created automatically:

/etc/pve/lxc/<CTID>.conf.bak.TIMESTAMP

Rollback steps:
1. Stop the container
2. Restore the backup config
3. Start the container

---

## Notes

- Rsync exit codes 23 and 24 are normal (runtime sockets / permissions)
- Always verify / is mounted on the new disk before deleting the old one
- This script intentionally avoids shrinking volumes (unsafe for LXC rootfs)

---

## License

MIT
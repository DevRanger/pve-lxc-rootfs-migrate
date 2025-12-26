---
name: Bug report
about: Report a problem or unexpected behavior
title: "[BUG] "
labels: bug
assignees: ""
---

## Description
Briefly describe what you were trying to do and what went wrong.

---

## Environment
- Proxmox version:
- Storage backend (e.g. local-lvm):
- Container type (LXC):
- Container OS:
- Script version / commit hash:

---

## Command Used
Paste the exact command you ran:

```bash
sudo ./pve-lxc-rootfs-migrate.sh --ctid <id> --size <GiB>
```

---

## Expected Behavior
What did you expect to happen?

---

## Actual Behavior
What actually happened?

---

## Output / Logs
Paste any relevant output or errors here:

```text
<logs>
```

---

## Checklist
Please confirm the following before submitting:

- [ ] I tested this in a **non-production environment**
- [ ] I verified I had **working backups**
- [ ] I ran the script with `--dry-run` first
- [ ] I read the README and disclaimer

---

## Additional Context
Anything else that might be relevant (screenshots, config snippets, etc.).

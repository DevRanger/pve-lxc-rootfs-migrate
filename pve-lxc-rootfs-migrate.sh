#!/usr/bin/env bash
set -euo pipefail

CTID=""
NEW_SIZE_GIB=""
MOUNTPOINT="/mnt/newroot"
MPID=""
ASSUME_YES="0"
DELETE_OLD="0"
KEEP_MP="0"
DRY_RUN="0"

log() { echo -e "\n==> $*\n"; }
warn() { echo -e "WARN: $*\n" >&2; }
die() { echo -e "ERROR: $*\n" >&2; exit 1; }

run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[dry-run] $*"
  else
    eval "$@"
  fi
}

confirm() {
  [[ "$ASSUME_YES" == "1" ]] && return 0
  read -r -p "$1 [y/N]: " ans
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

require_root() {
  [[ "$(id -u)" -eq 0 ]] || die "Run as root (sudo)."
}

require_cmds() {
  for c in pct pvesm lvs lvremove mkfs.ext4 sed awk grep findmnt; do
    command -v "$c" >/dev/null || die "Missing command: $c"
  done
}

conf_path() { echo "/etc/pve/lxc/${CTID}.conf"; }

pct_state() {
  pct status "$CTID" 2>/dev/null | awk '{print $2}'
}

get_rootfs_volid() {
  grep -E '^rootfs:' "$(conf_path)" | head -n1 | sed -E 's/^rootfs:\s*([^,]+).*/\1/'
}

get_storage() {
  get_rootfs_volid | cut -d: -f1
}

volname_from_volid() {
  echo "$1" | cut -d: -f2
}

vg_for_lv() {
  lvs --noheadings -o vg_name --select "lv_name=$1" 2>/dev/null | awk '{$1=$1;print}' | head -n1
}

first_free_mpid() {
  for i in $(seq 0 15); do
    grep -qE "^mp${i}:" "$(conf_path)" || { echo "$i"; return; }
  done
  die "No free mp slots (mp0..mp15)."
}

backup_conf() {
  local bkp
  bkp="$(conf_path).bak.$(date +%Y%m%d-%H%M%S)"
  run "cp -a '$(conf_path)' '$bkp'"
  echo "$bkp"
}

rsync_inside_ct() {
  local cmd
  cmd=$(cat <<EOF
rsync -aHAX --numeric-ids --info=progress2 \
  --exclude={"${MOUNTPOINT}/*","/proc/*","/sys/*","/dev/*","/tmp/*","/run/*"} \
  / "${MOUNTPOINT}" || rc=\$?; rc=\${rc:-0}; \
  if [[ \$rc -ne 0 && \$rc -ne 23 && \$rc -ne 24 ]]; then exit \$rc; else exit 0; fi
EOF
)
  run "pct exec '$CTID' -- bash -lc $(printf '%q' "$cmd")"
}

main() {
  require_root
  require_cmds

  [[ -f "$(conf_path)" ]] || die "CT config not found"
  [[ "$(get_storage)" == "local-lvm" ]] || die "Only local-lvm is supported"

  local old_volid old_lv old_vg old_lv_path
  old_volid="$(get_rootfs_volid)"
  old_lv="$(volname_from_volid "$old_volid")"
  old_vg="$(vg_for_lv "$old_lv")"
  old_lv_path="/dev/${old_vg}/${old_lv}"

  [[ -e "$old_lv_path" ]] || die "Old LV not found"

  [[ -n "$MPID" ]] || MPID="$(first_free_mpid)"

  log "CTID: $CTID"
  log "Old rootfs: $old_volid"
  log "New size: ${NEW_SIZE_GIB}G"

  [[ "$DRY_RUN" == "1" ]] || confirm "Proceed?" || die "Aborted"

  if [[ "$(pct_state)" == "running" ]]; then
    confirm "CT is running. Stop it?" || die "CT must be stopped"
    run "pct stop '$CTID'"
  fi

  log "Allocating new volume"
  local new_volid new_lv new_vg new_lv_path
  new_volid="$(pvesm alloc local-lvm "$CTID" rootfs "${NEW_SIZE_GIB}G")"
  new_lv="$(volname_from_volid "$new_volid")"
  new_vg="$(vg_for_lv "$new_lv")"
  new_lv_path="/dev/${new_vg}/${new_lv}"

  log "Adding temporary mountpoint mp${MPID}"
  run "pct set '$CTID' -mp${MPID} '${new_volid},mp=${MOUNTPOINT},backup=1'"

  log "Formatting new volume"
  findmnt -rn -S "$new_lv_path" && die "Refusing to format mounted LV"
  run "mkfs.ext4 -F '$new_lv_path' >/dev/null"

  log "Starting CT"
  run "pct start '$CTID'"

  log "Rsyncing rootfs"
  rsync_inside_ct

  run "pct exec '$CTID' -- bash -lc 'du -sh \"${MOUNTPOINT}\" || true'"

  log "Stopping CT for rootfs swap"
  run "pct stop '$CTID'"

  log "Backing up config and swapping rootfs"
  backup_conf >/dev/null

  if [[ "$DRY_RUN" != "1" ]]; then
    sed -i "s|^rootfs: .*|rootfs: ${new_volid},size=${NEW_SIZE_GIB}G|" "$(conf_path)"
    [[ "$KEEP_MP" == "1" ]] || sed -i "/^mp${MPID}:/d" "$(conf_path)"
  fi

  log "Starting CT on new rootfs"
  run "pct start '$CTID'"
  run "pct exec '$CTID' -- df -h /"

  if [[ "$DELETE_OLD" == "1" ]]; then
    confirm "Delete old LV $old_lv_path ?" || die "Delete aborted"
    run "pct stop '$CTID'"
    run "lvremove -y '$old_lv_path'"
    run "pct start '$CTID'"
  else
    warn "Old LV not deleted: $old_lv_path"
  fi

  log "Done"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ctid) CTID="$2"; shift 2;;
    --size) NEW_SIZE_GIB="$2"; shift 2;;
    --mount) MOUNTPOINT="$2"; shift 2;;
    --mpid) MPID="$2"; shift 2;;
    --yes) ASSUME_YES="1"; shift;;
    --delete-old) DELETE_OLD="1"; shift;;
    --keep-mp) KEEP_MP="1"; shift;;
    --dry-run) DRY_RUN="1"; shift;;
    -h|--help) exit 0;;
    *) die "Unknown argument: $1";;
  esac
done

[[ -n "$CTID" && -n "$NEW_SIZE_GIB" ]] || die "Missing --ctid or --size"
main

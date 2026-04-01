#!/usr/bin/env bash
# mac-ssd-rescue.sh — Reclaim SSD space by migrating Xcode artifacts to an external USB drive.
# Works on macOS Sonoma 14.x, Sequoia 15.x and macOS 26 (Tahoe).
# No dependencies — pure bash + built-in macOS tools.
set -euo pipefail

# ── Colours & helpers ────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

info()  { printf "${CYAN}[INFO]${NC}  %s\n" "$*"; }
ok()    { printf "${GREEN}[OK]${NC}    %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
die()   { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; exit 1; }

bytes_to_human() {
  local bytes=$1
  if (( bytes >= 1073741824 )); then
    printf "%.1f GB" "$(echo "scale=1; $bytes / 1073741824" | bc)"
  elif (( bytes >= 1048576 )); then
    printf "%.1f MB" "$(echo "scale=1; $bytes / 1048576" | bc)"
  else
    printf "%d KB" "$(( bytes / 1024 ))"
  fi
}

dir_size_bytes() {
  if [[ -d "$1" ]]; then
    du -sk "$1" 2>/dev/null | awk '{print $1 * 1024}'
  else
    echo 0
  fi
}

# ── Sanity checks ───────────────────────────────────────────────────────────
[[ "$(uname)" == "Darwin" ]] || die "This script only runs on macOS."

if [[ $EUID -eq 0 ]]; then
  die "Do not run as root. The script will use sudo only when needed."
fi

# ── Configuration ────────────────────────────────────────────────────────────
# Paths that eat the most SSD space
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
DEVICE_SUPPORT="$HOME/Library/Developer/Xcode/iOS DeviceSupport"
CORE_SIMULATOR="$HOME/Library/Developer/CoreSimulator"
SPM_CACHE="$HOME/Library/Developer/Xcode/SPMCache"
SPM_REPOS="$HOME/Library/Caches/org.swift.swiftpm"
ARCHIVES="$HOME/Library/Developer/Xcode/Archives"

SOURCES=(
  "$DERIVED_DATA"
  "$DEVICE_SUPPORT"
  "$CORE_SIMULATOR"
  "$SPM_CACHE"
  "$SPM_REPOS"
  "$ARCHIVES"
)

SOURCE_LABELS=(
  "DerivedData"
  "iOS DeviceSupport"
  "CoreSimulator"
  "SPM Cache"
  "SPM Repos"
  "Archives"
)

# ── Detect external volume ──────────────────────────────────────────────────
detect_volume() {
  local volumes=()
  while IFS= read -r vol; do
    # Skip system volumes
    [[ "$vol" == "/" ]] && continue
    [[ "$vol" == /System/* ]] && continue
    [[ "$vol" == */Macintosh\ HD* ]] && continue
    volumes+=("$vol")
  done < <(df -Hl | awk 'NR>1 && /\/Volumes\// {for(i=9;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ *$//')

  if [[ ${#volumes[@]} -eq 0 ]]; then
    die "No external volumes found. Please connect your USB drive and try again."
  fi

  if [[ ${#volumes[@]} -eq 1 ]]; then
    VOLUME="${volumes[0]}"
    info "Detected external volume: $VOLUME"
  else
    echo ""
    info "Multiple external volumes detected:"
    for i in "${!volumes[@]}"; do
      printf "  %d) %s\n" "$((i + 1))" "${volumes[$i]}"
    done
    echo ""
    while true; do
      read -rp "Select volume [1-${#volumes[@]}]: " choice
      if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#volumes[@]} )); then
        VOLUME="${volumes[$((choice - 1))]}"
        break
      fi
      warn "Invalid selection. Try again."
    done
  fi
}

# ── Show current disk usage ─────────────────────────────────────────────────
show_usage() {
  echo ""
  printf "${CYAN}%-25s %12s${NC}\n" "Directory" "Size"
  printf "%-25s %12s\n" "─────────────────────────" "────────────"

  local total=0
  for i in "${!SOURCES[@]}"; do
    local size
    size=$(dir_size_bytes "${SOURCES[$i]}")
    total=$((total + size))
    printf "%-25s %12s\n" "${SOURCE_LABELS[$i]}" "$(bytes_to_human "$size")"
  done

  echo "─────────────────────────────────────────"
  printf "${GREEN}%-25s %12s${NC}\n" "Total reclaimable" "$(bytes_to_human $total)"
  echo ""
}

# ── Migrate a single directory ──────────────────────────────────────────────
migrate_dir() {
  local src="$1" label="$2" dest_base="$3"
  local dest="$dest_base/$label"

  if [[ ! -d "$src" ]]; then
    warn "$label: source not found, skipping."
    return
  fi

  local size
  size=$(dir_size_bytes "$src")
  if (( size == 0 )); then
    warn "$label: empty, skipping."
    return
  fi

  info "$label: migrating $(bytes_to_human "$size") ..."

  # Create destination and sync
  mkdir -p "$dest"
  rsync -a --delete "$src/" "$dest/" 2>/dev/null

  # Verify copy succeeded (compare file count)
  local src_count dest_count
  src_count=$(find "$src" -type f 2>/dev/null | wc -l | tr -d ' ')
  dest_count=$(find "$dest" -type f 2>/dev/null | wc -l | tr -d ' ')

  if (( dest_count < src_count )); then
    die "$label: copy verification failed (src=$src_count, dest=$dest_count). Aborting migration for this directory."
  fi

  # Replace original with symlink
  rm -rf "$src"
  ln -s "$dest" "$src"

  ok "$label: migrated and symlinked."
}

# ── Restore (undo) ──────────────────────────────────────────────────────────
restore_dir() {
  local src="$1" label="$2"

  if [[ ! -L "$src" ]]; then
    warn "$label: not a symlink, skipping restore."
    return
  fi

  local target
  target=$(readlink "$src")

  if [[ ! -d "$target" ]]; then
    warn "$label: symlink target not found ($target). Removing broken symlink."
    rm -f "$src"
    return
  fi

  info "$label: restoring from $target ..."
  rm "$src"
  mkdir -p "$src"
  rsync -a --delete "$target/" "$src/" 2>/dev/null
  ok "$label: restored to local SSD."
}

# ── Status check ────────────────────────────────────────────────────────────
show_status() {
  echo ""
  printf "${CYAN}%-25s %-10s %s${NC}\n" "Directory" "Status" "Location"
  printf "%-25s %-10s %s\n" "─────────────────────────" "──────────" "────────────────────────────"

  for i in "${!SOURCES[@]}"; do
    local src="${SOURCES[$i]}" label="${SOURCE_LABELS[$i]}"
    if [[ -L "$src" ]]; then
      local target
      target=$(readlink "$src")
      printf "%-25s ${GREEN}%-10s${NC} %s\n" "$label" "migrated" "$target"
    elif [[ -d "$src" ]]; then
      printf "%-25s ${YELLOW}%-10s${NC} %s\n" "$label" "local" "$src"
    else
      printf "%-25s %-10s %s\n" "$label" "absent" "—"
    fi
  done
  echo ""
}

# ── Interactive selector ────────────────────────────────────────────────────
select_sources() {
  echo ""
  info "Select which directories to migrate (space-separated numbers, or 'all'):"
  echo ""

  for i in "${!SOURCES[@]}"; do
    local size
    size=$(dir_size_bytes "${SOURCES[$i]}")
    local status="local"
    [[ -L "${SOURCES[$i]}" ]] && status="already migrated"
    printf "  %d) %-25s %12s  [%s]\n" "$((i + 1))" "${SOURCE_LABELS[$i]}" "$(bytes_to_human "$size")" "$status"
  done

  echo ""
  read -rp "Your choice: " selection

  SELECTED=()
  if [[ "$selection" == "all" ]]; then
    for i in "${!SOURCES[@]}"; do
      SELECTED+=("$i")
    done
  else
    for n in $selection; do
      if [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#SOURCES[@]} )); then
        SELECTED+=("$((n - 1))")
      else
        warn "Ignoring invalid selection: $n"
      fi
    done
  fi

  if [[ ${#SELECTED[@]} -eq 0 ]]; then
    die "No directories selected."
  fi
}

# ── Main ─────────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF
Usage: $(basename "$0") [command]

Commands:
  migrate   Move Xcode artifacts to an external USB drive (default)
  restore   Move artifacts back to the local SSD and remove symlinks
  status    Show which directories are local vs. migrated
  usage     Show current disk usage of each directory

Examples:
  $(basename "$0")              # interactive migrate
  $(basename "$0") migrate      # same as above
  $(basename "$0") restore      # undo all migrations
  $(basename "$0") status       # check current state
EOF
}

COMMAND="${1:-migrate}"

case "$COMMAND" in
  migrate)
    echo ""
    echo "  ╔══════════════════════════════════════╗"
    echo "  ║        mac-ssd-rescue v1.0.0         ║"
    echo "  ║   Reclaim your Mac's SSD space       ║"
    echo "  ╚══════════════════════════════════════╝"
    echo ""

    show_usage
    detect_volume

    DEST_BASE="$VOLUME/mac-ssd-rescue"
    mkdir -p "$DEST_BASE"

    select_sources

    echo ""
    warn "This will move selected directories to $DEST_BASE and replace them with symlinks."
    read -rp "Continue? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || die "Aborted."
    echo ""

    for idx in "${SELECTED[@]}"; do
      migrate_dir "${SOURCES[$idx]}" "${SOURCE_LABELS[$idx]}" "$DEST_BASE"
    done

    echo ""
    ok "Done! Reclaimed SSD space. Your Xcode projects will work as before."
    info "Keep the USB drive connected while using Xcode."
    echo ""
    ;;

  restore)
    echo ""
    info "Restoring migrated directories back to local SSD..."
    echo ""
    for i in "${!SOURCES[@]}"; do
      restore_dir "${SOURCES[$i]}" "${SOURCE_LABELS[$i]}"
    done
    ok "All directories restored."
    echo ""
    ;;

  status)
    show_status
    ;;

  usage)
    show_usage
    ;;

  help|--help|-h)
    usage
    ;;

  *)
    die "Unknown command: $COMMAND. Run '$(basename "$0") help' for usage."
    ;;
esac

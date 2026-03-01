#!/bin/bash
# stellarmate_backup.sh

set -euo pipefail

# --- Determine the original user (not root) ---
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# --- Configuration ---
BACKUP_DIR="$REAL_HOME/Documents/backup_files"

# --- Core paths (always backed up) ---
CORE_PATHS=(
    /etc/hosts
    /etc/NetworkManager/system-connections
    "$REAL_HOME/Documents/sequences"
    "$REAL_HOME/Documents/scheduler"
    "$REAL_HOME/.indi"
    "$REAL_HOME/.config/autostart"
    "$REAL_HOME/.config/kstars"
    "$REAL_HOME/.config/kstarsrc"
    "$REAL_HOME/.config/kstars.kmessagebox"
    "$REAL_HOME/.config/kstars.notifyrc"
    "$REAL_HOME/.local/share/ekoslive"
    "$REAL_HOME/.local/share/kstars"
    "$REAL_HOME/.ssh"
)

# --- Optional paths (backed up if present) ---
OPTIONAL_PATHS=(
    "$REAL_HOME/.config/kstarsrc.lock"
    "$REAL_HOME/.phd2"
    "$REAL_HOME/.ZWO"
    "$REAL_HOME/.PHDGuidingV2"
    "$REAL_HOME/FireCapture"
    "$REAL_HOME/.astropy"
    "$REAL_HOME/.java"
    "$REAL_HOME/bin"
)

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PV_AVAILABLE=false
TREE_AVAILABLE=false
ALL_PATHS=()

# ---------------------------------------------------------------------------

usage() {
    echo "Usage: sudo $0 [backup]"
    echo "       sudo $0 restore"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}ERROR: This script requires root privileges (sudo) for /etc/ paths.${NC}"
        usage
        exit 1
    fi
}

check_deps() {
    local missing=()
    local -A fallback_msg=(
        [pv]="progress bar → checkpoint dots"
        [tree]="directory tree → plain file list"
    )

    for cmd in pv tree; do
        if command -v "$cmd" &>/dev/null; then
            case "$cmd" in
                pv)   PV_AVAILABLE=true   ;;
                tree) TREE_AVAILABLE=true  ;;
            esac
        else
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        echo -e "${GREEN}All optional dependencies present (pv, tree).${NC}"
        return
    fi

    echo -e "${YELLOW}Missing optional tools:${NC}"
    for cmd in "${missing[@]}"; do
        echo -e "  - $cmd  (fallback: ${fallback_msg[$cmd]})"
    done
    echo ""
    read -r -p "Install ${missing[*]}? [y/N] " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        local pkg_cmd=()
        if command -v pacman &>/dev/null; then
            pkg_cmd=(pacman -S --noconfirm)
        elif command -v apt-get &>/dev/null; then
            pkg_cmd=(apt-get install -y)
        else
            echo -e "${RED}Unknown package manager. Please install manually: ${missing[*]}${NC}"
            return
        fi
        echo "Installing ${missing[*]}..."
        "${pkg_cmd[@]}" "${missing[@]}" || true

        # Re-check what actually got installed
        for cmd in "${missing[@]}"; do
            if command -v "$cmd" &>/dev/null; then
                echo -e "  ${GREEN}$cmd installed.${NC}"
                case "$cmd" in
                    pv)   PV_AVAILABLE=true   ;;
                    tree) TREE_AVAILABLE=true  ;;
                esac
            else
                echo -e "  ${RED}$cmd installation failed — using fallback.${NC}"
            fi
        done
    else
        echo "Skipping. Fallbacks will be used."
    fi
}

# collect_paths [strict|lenient]
#   strict  (default): aborts if any core path is missing
#   lenient           : warns about missing core paths but continues with what exists
# Sets the global ALL_PATHS array.
collect_paths() {
    local mode="${1:-strict}"

    echo "Checking core paths..."
    local missing_core=()
    local found_core=()
    for path in "${CORE_PATHS[@]}"; do
        if [[ ! -e "$path" ]]; then
            missing_core+=("$path")
            echo -e "  ${RED}MISSING:${NC} $path"
        else
            found_core+=("$path")
            echo -e "  ${GREEN}OK:${NC}      $path"
        fi
    done

    if [[ ${#missing_core[@]} -gt 0 ]]; then
        if [[ "$mode" == strict ]]; then
            echo ""
            echo -e "${RED}ABORTED: ${#missing_core[@]} core path(s) missing. Backup will not be created.${NC}"
            exit 1
        else
            echo -e "  ${YELLOW}WARNING: ${#missing_core[@]} core path(s) missing — skipped in pre-restore backup.${NC}"
        fi
    fi

    echo ""
    echo "Checking optional paths..."
    local found_optional=()
    for path in "${OPTIONAL_PATHS[@]}"; do
        if [[ -e "$path" ]]; then
            found_optional+=("$path")
            echo -e "  ${GREEN}FOUND:${NC}   $path"
        else
            echo -e "  ${YELLOW}SKIPPED (not present):${NC} $path"
        fi
    done

    ALL_PATHS=("${found_core[@]}" "${found_optional[@]}")
}

# make_archive <output_path>
# Creates a compressed archive of ALL_PATHS to output_path.
make_archive() {
    local output_path="$1"

    echo ""
    echo "Estimating backup size..."
    local raw_bytes raw_human estimated_bytes estimated_human avail_bytes avail_human
    # Exclude the backup dir itself — avoids recursive inclusion and symlinks pointing to NAS/cloud
    raw_bytes=$(du -sbc --exclude="$BACKUP_DIR" "${ALL_PATHS[@]}" 2>/dev/null | tail -1 | cut -f1)
    raw_human=$(du -shc --exclude="$BACKUP_DIR" "${ALL_PATHS[@]}" 2>/dev/null | tail -1 | cut -f1)
    estimated_bytes=$(( raw_bytes / 2 ))
    estimated_human=$(numfmt --to=iec --suffix=B "$estimated_bytes")
    avail_bytes=$(df -B1 "$BACKUP_DIR" | awk 'NR==2 {print $4}')
    avail_human=$(df -h "$BACKUP_DIR" | awk 'NR==2 {print $4}')

    echo "  Uncompressed data:      $raw_human"
    echo "  Estimated archive size: ~$estimated_human  (assuming ~50% compression)"
    echo "  Available disk space:   $avail_human"

    local estimated_with_margin=$(( estimated_bytes + estimated_bytes / 10 ))
    if [[ $avail_bytes -lt $estimated_with_margin ]]; then
        echo ""
        echo -e "${RED}ERROR: Insufficient disk space.${NC}"
        echo "  Required (est. + 10% margin): $(numfmt --to=iec --suffix=B "$estimated_with_margin")"
        echo "  Available:                    $avail_human"
        exit 1
    else
        echo -e "  ${GREEN}Disk space OK.${NC}"
    fi

    echo ""
    echo "Creating archive: $(basename "$output_path")..."
    if [[ "$PV_AVAILABLE" == true ]]; then
        tar -cz --exclude="$BACKUP_DIR" "${ALL_PATHS[@]}" | pv -s "$raw_bytes" > "$output_path"
    else
        tar -czf "$output_path" --exclude="$BACKUP_DIR" --checkpoint=100 --checkpoint-action=dot "${ALL_PATHS[@]}"
        echo ""
    fi

    local actual_size actual_bytes compression_ratio
    actual_size=$(du -sh "$output_path" | cut -f1)
    actual_bytes=$(du -sb "$output_path" | cut -f1)
    compression_ratio=$(awk "BEGIN {printf \"%.1f\", (1 - $actual_bytes / $raw_bytes) * 100}")

    echo ""
    echo -e "${GREEN}=== Archive complete ===${NC}"
    echo "File:              $output_path"
    echo "Actual size:       $actual_size"
    echo "Estimated size:    ~$estimated_human"
    echo "Compression ratio: ${compression_ratio}%"
    echo ""
    echo "Contents (directory tree):"
    if [[ "$TREE_AVAILABLE" == true ]]; then
        tar -tzf "$output_path" | tree --fromfile -a
    else
        tar -tzf "$output_path"
    fi
}

# ---------------------------------------------------------------------------

do_backup() {
    local backup_path="$BACKUP_DIR/stellarmate_backup_$(date +%Y%m%d_%H%M).tar.gz"

    echo -e "${GREEN}=== StellarMate Backup ===${NC}"
    echo "User:   $REAL_USER ($REAL_HOME)"
    echo "Target: $backup_path"
    echo ""

    collect_paths strict
    make_archive "$backup_path"
}

do_restore() {
    echo -e "${GREEN}=== StellarMate Restore ===${NC}"
    echo "User:       $REAL_USER ($REAL_HOME)"
    echo "Backup dir: $BACKUP_DIR"
    echo ""

    # List available backups, newest first
    local files=()
    while IFS= read -r f; do
        files+=("$f")
    done < <(ls -t "$BACKUP_DIR"/stellarmate_*.tar.gz 2>/dev/null || true)

    if [[ ${#files[@]} -eq 0 ]]; then
        echo -e "${RED}No backups found in $BACKUP_DIR${NC}"
        exit 1
    fi

    echo "Available backups (newest first):"
    for i in "${!files[@]}"; do
        local fname size
        fname=$(basename "${files[$i]}")
        size=$(du -sh "${files[$i]}" | cut -f1)
        printf "  %2d)  %-52s  %s\n" "$((i+1))" "$fname" "$size"
    done
    echo ""

    read -r -p "Select backup to restore [1]: " selection
    selection="${selection:-1}"

    if ! [[ "$selection" =~ ^[0-9]+$ ]] || \
       [[ "$selection" -lt 1 ]] || \
       [[ "$selection" -gt "${#files[@]}" ]]; then
        echo -e "${RED}Invalid selection.${NC}"
        exit 1
    fi

    local restore_file="${files[$((selection-1))]}"
    local prerestore_path="$BACKUP_DIR/stellarmate_prerestore_$(date +%Y%m%d_%H%M).tar.gz"

    echo ""
    echo "Restore from: $(basename "$restore_file")"
    echo ""

    # --- Select paths to exclude from restore ---
    echo "Paths in archive:"
    local archive_paths=()
    while IFS= read -r p; do
        [[ -n "$p" ]] && archive_paths+=("$p")
    done < <(
        tar -tzf "$restore_file" \
        | sed 's|^[./]*||; s|/$||' \
        | awk -F/ '{
            if ($1=="home") {
                if (NF>=3) key=$1"/"$2"/"$3
                else next
            } else if ($1=="etc") {
                if (NF>=2) key=$1"/"$2
                else next
            } else if (NF>=1) {
                key=$1
            } else next
            print key
          }' \
        | sort -u \
        | grep -v '^$'
    )

    for i in "${!archive_paths[@]}"; do
        printf "  %2d)  %s\n" "$((i+1))" "${archive_paths[$i]}"
    done
    echo ""
    read -r -p "Exclude paths from restore (comma-separated numbers), or Enter to restore all: " excl_input

    local exclude_args=()
    if [[ -n "$excl_input" ]]; then
        IFS=',' read -ra excl_selections <<< "$excl_input"
        for sel in "${excl_selections[@]}"; do
            sel="${sel// /}"
            if [[ "$sel" =~ ^[0-9]+$ ]] && \
               [[ "$sel" -ge 1 ]] && \
               [[ "$sel" -le "${#archive_paths[@]}" ]]; then
                exclude_args+=("--exclude=${archive_paths[$((sel-1))]}")
                echo -e "  ${YELLOW}Excluding:${NC} ${archive_paths[$((sel-1))]}"
            fi
        done
        echo ""
    fi

    # Step 1: snapshot current state so the restore can be reverted
    echo -e "${YELLOW}--- Step 1/2: Pre-restore backup (enables revert) ---${NC}"
    echo "Target: $prerestore_path"
    echo ""
    collect_paths lenient
    make_archive "$prerestore_path"

    # Step 2: extract the requested archive to /
    echo ""
    echo -e "${YELLOW}--- Step 2/2: Restoring from archive ---${NC}"
    local restore_bytes
    restore_bytes=$(du -sb "$restore_file" | cut -f1)

    if [[ "$PV_AVAILABLE" == true ]]; then
        pv -s "$restore_bytes" -N "Restoring" "$restore_file" | tar -xz "${exclude_args[@]}" -C /
    else
        tar -xzf "$restore_file" "${exclude_args[@]}" --checkpoint=100 --checkpoint-action=dot -C /
        echo ""
    fi

    echo ""
    echo -e "${GREEN}=== Restore complete ===${NC}"
    echo "Restored from:      $restore_file"
    echo "Pre-restore backup: $prerestore_path"
    echo ""
    echo -e "To revert: ${YELLOW}sudo $0 restore${NC}  and select $(basename "$prerestore_path")"
}

# ---------------------------------------------------------------------------

MODE="${1:-backup}"

mkdir -p "$BACKUP_DIR"
check_root
echo ""
check_deps
echo ""

case "$MODE" in
    backup)
        do_backup
        ;;
    restore)
        do_restore
        ;;
    *)
        echo -e "${RED}ERROR: Unknown mode '$MODE'${NC}"
        usage
        exit 1
        ;;
esac

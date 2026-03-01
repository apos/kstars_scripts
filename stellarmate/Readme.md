# StellarMate Scripts

## Automated backup/restore script (`backup_sm_linux.sh`)

A safe, interactive backup and restore script for StellarMate configurations.
Works on Debian/Ubuntu-based systems (StellarMate OS) and Arch Linux (SMOS).

### What gets backed up

**Core paths** (always — backup aborts if any are missing):

| Path | Content |
|---|---|
| `/etc/hosts` | Host file |
| `/etc/NetworkManager/system-connections` | WiFi/network credentials |
| `~/Documents/sequences` | KStars capture sequences |
| `~/Documents/scheduler` | KStars scheduler jobs |
| `~/.indi` | INDI driver profiles and config |
| `~/.config/autostart` | Autostart entries |
| `~/.config/kstars*` | KStars/Ekos configuration |
| `~/.local/share/ekoslive` | EkosLive settings |
| `~/.local/share/kstars` | KStars data (catalogs, logs, …) |
| `~/.ssh` | SSH keys |

**Optional paths** (included if present):
`~/.phd2`, `~/.ZWO`, `~/.PHDGuidingV2`, `~/FireCapture`, `~/.astropy`, `~/.java`, `~/bin`

**Always excluded:**
`~/Documents/backup_files` — the backup directory itself is never archived, whether it is a real
directory or a symlink (e.g. pointing to a NAS or cloud mount). This prevents recursive inclusion
and keeps archive sizes predictable. Large data such as astro images should be handled separately
through dedicated NAS or cloud backup solutions.

### Requirements

- `sudo` / root (required for `/etc/` access)
- `pv` — optional, for progress bar (fallback: checkpoint dots)
- `tree` — optional, for directory tree display (fallback: plain file list)

All optional dependencies are checked at startup. If missing, the script offers to
install them via `pacman` (Arch/SMOS) or `apt-get` (Debian/Ubuntu).

### Backup

```bash
sudo ./backup_sm_linux.sh
# or explicitly:
sudo ./backup_sm_linux.sh backup
```

Creates `~/Documents/backup_files/stellarmate_backup_YYYYMMDD_HHMM.tar.gz`
plus a `.manifest` sidecar file (used to speed up restore path listing).

The script checks all core paths, estimates disk space (with 10% safety margin),
then creates a compressed archive and prints a content tree on completion.

### Restore

```bash
sudo ./backup_sm_linux.sh restore
```

**Step 1 — Select a backup:**

Lists all available backups in `~/Documents/backup_files/` (newest first).
Press Enter to restore the most recent, or type a number.

**Step 2 — Exclude paths:**

The script lists the top-level path groups contained in the archive:

```
Paths in archive:
   1)  astrometry_files.txt
   2)  etc/hosts
   3)  etc/NetworkManager
   4)  home/stellarmate/.config
   5)  home/stellarmate/Documents
   6)  home/stellarmate/.indi
   7)  home/stellarmate/.local
   8)  home/stellarmate/.ssh
Exclude paths from restore (comma-separated numbers), or Enter to restore all:
```

Enter comma-separated numbers to skip specific paths, or press Enter to restore everything.

If a `.manifest` file exists alongside the archive, the path listing is instant.
For archives without a manifest (e.g. older or external backups), the script falls
back to scanning the archive with `tar -tzf` (slow for large files). You can
generate a manifest for an existing archive manually:

```bash
sudo tar -tzf stellarmate_backup_20260228_1505.tar.gz > stellarmate_backup_20260228_1505.manifest
```

**Step 3 — Pre-restore safety snapshot:**

Before extracting, the script automatically snapshots the current system state to
`stellarmate_prerestore_YYYYMMDD_HHMM.tar.gz` — the same format as a regular backup.
To revert a restore, simply run `restore` again and select the `prerestore` file.

**Step 4 — Extract:**

The selected archive is extracted to `/` with any excluded paths filtered out.

### File naming

| Pattern | Created by |
|---|---|
| `stellarmate_backup_YYYYMMDD_HHMM.tar.gz` | `backup` mode |
| `stellarmate_backup_YYYYMMDD_HHMM.manifest` | `backup` mode (sidecar) |
| `stellarmate_prerestore_YYYYMMDD_HHMM.tar.gz` | automatically before every restore |
| `stellarmate_prerestore_YYYYMMDD_HHMM.manifest` | automatically before every restore (sidecar) |

### Arch Linux / SMOS notes

SMOS ships with only the `[smos]` repo in `/etc/pacman.conf`. To install standard
Arch packages like `pv` or `tree`, add `[core]` and `[extra]` repos:

```ini
[core]
Include = /etc/pacman.d/mirrorlist
Usage = Sync Install

[extra]
Include = /etc/pacman.d/mirrorlist
Usage = Sync Install
```

`Usage = Sync Install` allows installing individual packages without pulling in
full system upgrades from standard Arch repos, keeping SMOS packages intact.

**Important:** Always back up `/etc/pacman.conf` with a timestamp before editing:

```bash
sudo cp /etc/pacman.conf /etc/pacman.conf.bak.$(date +%Y%m%d_%H%M%S)
```

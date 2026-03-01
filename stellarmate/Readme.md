# StellarMate Scripts

## Automated backup/restore script (`backup_sm_linux.sh`)

A safe, interactive backup and restore script for StellarMate configurations.
Works on Debian/Ubuntu-based systems (StellarMate OS) and Arch Linux.

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
- `pv` — optional, for progress bar (script offers to install it automatically)
- `tree` ≥ 1.8 (for archive contents display after backup)

### Backup

```bash
sudo ./backup_sm_linux.sh
# or explicitly:
sudo ./backup_sm_linux.sh backup
```

Creates `~/Documents/backup_files/stellarmate_backup_YYYYMMDD_HHMM.tar.gz`.

The script checks all core paths, estimates disk space (with 10 % safety margin),
then creates a compressed archive and prints a content tree on completion.

### Restore

```bash
sudo ./backup_sm_linux.sh restore
```

Lists all available backups in `~/Documents/backup_files/` (newest first):

```
Available backups (newest first):
   1)  stellarmate_backup_20260301_1430.tar.gz          245M
   2)  stellarmate_prerestore_20260301_1200.tar.gz       238M
   3)  stellarmate_backup_20260228_0900.tar.gz           240M

Select backup to restore [1]:
```

Press Enter to restore the most recent, or type a number.

**Before extracting**, the script automatically snapshots the current system state to
`stellarmate_prerestore_YYYYMMDD_HHMM.tar.gz` — the same format as a regular backup.
To revert a restore, simply run `restore` again and select the `prerestore` file.

### Backup file naming

| Pattern | Created by |
|---|---|
| `stellarmate_backup_YYYYMMDD_HHMM.tar.gz` | `backup` mode |
| `stellarmate_prerestore_YYYYMMDD_HHMM.tar.gz` | automatically before every restore |

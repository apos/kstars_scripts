# Native arm64 KStars/INDI build via plain KDE Craft

## Why this exists

[rlancaste/kstars-on-osx-craft](https://github.com/rlancaste/kstars-on-osx-craft) (see
[`../kstars-on-osx-craft/`](../kstars-on-osx-craft/) in this repo) explicitly targets x86_64/Rosetta.
That's not useful on Apple Silicon — Homebrew already ships an x86_64 KStars cask, so a from-source
Rosetta build gets you nothing you didn't already have. The actual goal is a **native arm64** build.

Per [this indilib.org forum thread](https://indilib.org/forum/ekos/16006-kstars-ekos-apple-silicon-to-whom-it-might-concern.html),
the way to get there is simpler than rlancaste's wrapper script: bootstrap
[KDE Craft](https://community.kde.org/Craft) directly, with no wrapper at all. Craft's own bootstrap
defaults to arm64 on Apple Silicon — no ABI override needed, which is the opposite of what
`kstars-on-osx-craft` does.

## Tested environment

- macOS 26.6 (Tahoe), build 25G72
- MacBook Pro, Apple M4 Pro (Mac16,7), 14 cores (10P+4E), 24 GB RAM
- Xcode Command Line Tools 26.6.0 (no full Xcode installed)
- Homebrew 6.0.17

## Steps

```bash
mkdir -p /tmp/craft-bootstrap && cd /tmp/craft-bootstrap   # do NOT run this inside the target prefix,
                                                              # CraftBootstrap.py refuses a non-empty dir
curl -sL raw.githubusercontent.com/KDE/craft/master/setup/CraftBootstrap.py -o setup.py

# --use-defaults picks arm64 non-interactively (Craft's actual default on Apple Silicon).
# Without it, the installer prompts "Select target architecture [0] x86_64, [1] arm64 (Default is arm64)"
# and blocks on stdin if run non-interactively (e.g. in CI or backgrounded).
python3 setup.py --prefix ~/CraftRoot --use-defaults

source ~/CraftRoot/craft/craftenv.sh
```

Known required patch before building (per the forum thread — `libftdi`'s blueprint tries to build its
test suite, which needs a boost test framework component that isn't pulled in):

```bash
# edit ~/CraftRoot/etc/blueprints/locations/craft-blueprints-kde/libs/libftdi/libftdi.py
# add "-DBUILD_TESTS=OFF" to its CMake args (see the file for the existing args list to append to)
```

Then:

```bash
craft kstars
```

This resolves INDI as a KStars dependency automatically — no need to separately `craft -i indi` etc. like
`kstars-on-osx-craft` does.

Launch with:

```bash
open ~/CraftRoot/Applications/KDE/KStars.app/Contents/MacOS/kstars
```

## Building a distributable .dmg

Craft has a built-in packaging action, no need for a hand-rolled `macdeployqt` + `hdiutil` script like
`kstars-on-osx-craft/generate-dmg-KStars.sh`:

```bash
craft --package kstars
```

This bundles all dependencies into a copy of the app (`install_name_tool`-rewriting library paths so it's
self-contained), builds the `.dmg` via `dmgbuild`, and drops it in `$CRAFT_PREFIX/tmp/`, e.g.:

```
~/CraftRoot/tmp/kstars-stable-3.8.4-<hash>-3.8.4-macos-clang-arm64.dmg
```

Took about 2m45s on the environment above, ~196 MB. The DMG'd copy is genuinely self-contained (Qt's
`cocoa` platform plugin and a `qt.conf` get bundled in) — unlike the app sitting directly in
`$CRAFT_PREFIX/Applications/KDE/`, which relies on `QT_PLUGIN_PATH` from `source craftenv.sh` and won't
launch standalone (see the gotcha below, though it's a different symptom than that one).

## Known gotcha: stale D-Bus launchd registrations block startup with no useful error

KStars registers a per-user macOS `launchd` LaunchAgent for its private D-Bus session
(`~/Library/LaunchAgents/org.freedesktop.dbus-kstars.plist`, label `org.freedesktop.dbus-kstars`) — and
there's a second one for the general D-Bus session bus, `org.freedesktop.dbus-session`. Both plists get
**rewritten with whatever bundle path launched them**, and `launchd` **caches the job definition at load
time** — deleting or editing the plist file does nothing to an already-loaded job.

Symptom: KStars starts, prints normal startup logging, then hangs forever right after:

```
Trying to Setup DBus
DBus Setup Succeeded.  Trying to Start DBus
Load failed: 5: Input/output error
Try running `launchctl bootstrap` as root for richer errors.
DBus Started
```

No window ever appears, 0% CPU, no crash, no further output. This happens if:

- an **older KStars install** (e.g. the Homebrew cask, or a previous Craft build you later deleted)
  already registered one of these labels pointing at a binary that no longer exists, or
- you deleted/moved a `CraftRoot` that still has a job registered in `launchd`'s runtime state.

Diagnose with:

```bash
launchctl list org.freedesktop.dbus-kstars
launchctl list org.freedesktop.dbus-session
# check the "Program" path in the output actually exists
```

Fix — unload the stale job (not just delete the plist, that alone doesn't touch the already-loaded job):

```bash
launchctl bootout gui/$(id -u)/org.freedesktop.dbus-kstars
launchctl bootout gui/$(id -u)/org.freedesktop.dbus-session
rm -f ~/Library/LaunchAgents/org.freedesktop.dbus-kstars.plist
```

Then relaunch KStars — it re-registers a fresh, correct job pointing at wherever you actually launched it
from. `install.sh` in this folder checks for and cleans this up automatically before building/launching.

## Which copy do I actually run — and which one is "installed"?

A Craft build produces several `kstars.app` copies (build work dir, `image-RelWithDebInfo-*` intermediate,
`archive` copy used for packaging, and the final `$CRAFT_PREFIX/Applications/KDE/kstars.app`). None of
those are meant for daily use:

- `$CRAFT_PREFIX/Applications/KDE/kstars.app` relies on `QT_PLUGIN_PATH` etc. from
  `source $CRAFT_PREFIX/craft/craftenv.sh` — launch it without that sourced and it hangs identically to the
  D-Bus gotcha above (missing `libqcocoa` platform plugin, no window ever appears).
- The **DMG-packaged copy is the real deliverable** — self-contained, installable to `/Applications` like
  any other Mac app, works for other users/machines with no Craft install at all.

`install.sh` copies the DMG's app to `/Applications/kstars.app` as the last step and unregisters the other
copies from `launchservicesd`. Do the same if you're doing this by hand: macOS's LaunchServices keys apps by
bundle identifier (`org.kde.kstars`, shared by every copy — and by the Homebrew cask, if you have that
installed too), so more than one registered copy makes `open -a KStars`, Spotlight, and Dock/Finder resolve
unpredictably to whichever one LaunchServices feels like that day. Same root cause class as the D-Bus
gotcha (a macOS system service keyed by a fixed identifier, oblivious to which of several installs is
"current"), just a different subsystem:

```bash
# see what's currently registered for this bundle ID
lsregister=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
"$lsregister" -dump 2>/dev/null | grep -B15 "org.kde.kstars$" | grep -E "^\s*path:"

# drop everything except the one you actually want registered
"$lsregister" -u /path/to/stale/kstars.app
```

If you also have the **Homebrew cask** (`brew install --cask kstars`, x86_64/Rosetta) installed, it
registers the exact same bundle ID too. Decide on one; running both isn't useful (the whole point of this
folder is to replace that Rosetta build), and having both around is exactly the kind of duplicate-identifier
mess described above. `brew uninstall --cask kstars` removes it and its own `launchctl` D-Bus registration.

## Updating to a newer KStars

```bash
source ~/CraftRoot/craft/craftenv.sh
craft --check-for-updates kstars   # tells you if craft-blueprints-kde has a newer version
craft kstars                       # rebuilds if so — same command as the initial build
craft --package kstars             # fresh .dmg
# then replace /Applications/kstars.app with the new DMG's copy, as in "Which copy" above
```

Or run [`update_kstars.sh`](./update_kstars.sh) — same three commands plus the `/Applications` swap and
LaunchServices cleanup, split out from `install.sh` for when Craft is already bootstrapped and you just
want to update. (Re-running [`install.sh`](./install.sh) works too — it's idempotent and includes this.)

## Status: works

Confirmed working end-to-end on the environment above:

- `python3 setup.py --prefix ~/CraftRoot --use-defaults` bootstrapped Craft with `ABI: macos-clang-arm64`
  with no manual architecture selection needed (`--use-defaults` is required to avoid it blocking on stdin
  when run non-interactively — the interactive prompt defaults to arm64 anyway).
- The `libftdi` patch above was applied preemptively; unclear whether it was still actually needed with
  the current `craft-blueprints-kde` (the blueprint already had a dynamic `buildTests` option we
  overrode instead of a hardcoded `ON`), but it didn't hurt and `libftdi` built fine.
- `craft kstars` ran clean, no failed packages, total **~24 minutes** wall time (bootstrap + `craft kstars`
  combined) on the M4 Pro above — most dependencies came down as prebuilt arm64 binaries from KDE's cache
  rather than compiling from source, only INDI/KStars itself and a handful of others actually compiled.
- Resulting binary confirmed native:
  ```
  $ file ~/CraftRoot/Applications/KDE/KStars.app/Contents/MacOS/kstars
  Mach-O 64-bit executable arm64
  ```
- `craft --package kstars` produced a working, self-contained ~196 MB `.dmg` in ~2m45s.
- First launch attempt hung on the D-Bus startup gotcha documented above (a stale registration left over
  from testing multiple KStars installs — Homebrew cask, a deleted x86_64 CraftRoot, a temp copy — in the
  same session). `launchctl bootout` on both stale labels + removing the plist fixed it immediately;
  KStars then opened a real window, loaded DSO/star/comet catalogs, and ran normally. This is an
  environment-hygiene issue, not a bug in the build itself, but likely to bite anyone who's tried more than
  one KStars build/install on the same Mac.
- No workarounds beyond the `libftdi` patch were needed for the build itself — no equivalent of the
  `indiserver` renaming issue or the arm64/x86_64 mismatch problems documented in
  [`../kstars-on-osx-craft/`](../kstars-on-osx-craft/), because this approach never introduces a
  cross-architecture bootstrap in the first place.

## install.sh

[`install.sh`](./install.sh) automates all of the above: bootstrap, `libftdi` patch, stale-D-Bus-job
cleanup, `craft kstars`, `craft --package kstars`. Re-running it is safe — already-done steps are skipped.

```bash
./install.sh                              # installs to ~/CraftRoot
CRAFT_PREFIX=/other/path ./install.sh     # or elsewhere
```

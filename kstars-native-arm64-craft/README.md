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

## Status

In progress — this README will be updated with what we actually hit once the build runs far enough to
tell. Forum thread reports ~30 minutes on an M1 iMac; expect roughly that ballpark or better on M4 Pro,
but Qt6/KDE Frameworks 6 is a large dependency chain and first-run numbers are unreliable until confirmed
here.

# Fix for rlancaste/kstars-on-osx-craft (Aug 2026) — SUPERSEDED, WRONG TRACK

> **This whole approach builds for x86_64/Rosetta, not native Apple Silicon.** That was not the actual
> goal — Homebrew already ships an x86_64 KStars build (`brew install --cask kstars`, runs under Rosetta),
> so reproducing that via a from-source Craft build adds no value. The two bugs documented below are real
> and the fixes work, but only get you to the same place `brew` already gets you.
>
> The actual goal — a **native arm64** build — turns out to need a completely different approach: bootstrap
> plain KDE Craft directly (no wrapper script) and let it default to arm64, per
> [this indilib.org forum thread](https://indilib.org/forum/ekos/16006-kstars-ekos-apple-silicon-to-whom-it-might-concern.html).
> See [`../kstars-native-arm64-craft/`](../kstars-native-arm64-craft/) for that attempt. Keeping this
> folder around because the two bugs and their root causes are still accurate documentation of
> `rlancaste/kstars-on-osx-craft` specifically, in case anyone actually wants an x86_64 build from source
> for some reason (e.g. testing, or a non-Apple-Silicon Mac).

[rlancaste/kstars-on-osx-craft](https://github.com/rlancaste/kstars-on-osx-craft) builds INDI + KStars on
macOS via [KDE Craft](https://community.kde.org/Craft). The repo's last commit is from Feb 2024; the
`craft-blueprints-kde` repo it depends on has moved on since then. As of Aug 2026, a fresh run of
`build-kstars.sh` fails with:

```
Failed to find indiserver:
Craft was unable to find indiserver
```

## Tested environment

- macOS 26.6 (Tahoe), build 25G72
- MacBook Pro, Apple M4 Pro (Mac16,7), 14 cores (10P+4E), 24 GB RAM
- Xcode Command Line Tools 26.6.0 (no full Xcode installed)
- Homebrew 6.0.17
- Craft build ABI: `macos-clang-x86_64` — i.e. built for Intel/Rosetta even though the hardware is Apple
  Silicon. This is the documented, tested target for this script (see the
  [macobservatory build writeup](https://macobservatory.com/kstars-ekos-apple-silicon-mac-build-2026/));
  native arm64 builds via this script are known to hit separate `ld: symbol(s) not found for architecture
  arm64` errors and aren't what this fix addresses.

This folder documents the two real, independent bugs behind that message and one follow-up issue, plus a
script (`fix-script.sh`) that patches the first two automatically.

## Bug 1: `indiserver` was renamed to `indi`

`build-kstars.sh` calls:

```
craft -i indiserver
craft -i indiserver-3rdparty-libraries
craft -i indiserver-3rdparty
```

The current `craft-blueprints-kde` layout (`libs/indilib/…`) no longer has packages under these names.
`craft --search indi` shows the actual current names:

| Script calls (broken) | Current package name |
|---|---|
| `indiserver` | `indi` |
| `indiserver-3rdparty` | `indi-3rdparty` |
| `indiserver-3rdparty-libraries` | `indi-3rdparty-libs` |

This alone explains the "Failed to find indiserver" message — Craft simply doesn't know a package by that
name anymore. `fix-script.sh` patches all six occurrences in `build-kstars.sh` (three `craft -i` calls and
three convenience-symlink blocks further down).

## Bug 2: stale arm64 binaries in an x86_64 Craft root

Independent of Bug 1, if your `craft-root` was ever bootstrapped natively on Apple Silicon (arm64) before
you (or the script) pinned the build ABI to `macos-clang-x86_64` — which is the documented, tested target
for this script, see the [macobservatory build writeup](https://macobservatory.com/kstars-ekos-apple-silicon-mac-build-2026/)
— Craft's own bootstrap dependencies can be left behind as arm64 `.dylib` files under `craft-root/lib`,
while everything built afterwards is x86_64. The linker silently *ignores* an architecture-mismatched
`.dylib` instead of erroring clearly, so the actual symptom shows up much later and looks unrelated, e.g.:

```
Undefined symbols for architecture x86_64:
  "_uncompress", referenced from: AstrometryDriver::processBLOB(...)
ld: symbol(s) not found for architecture x86_64
```

or, for `libgphoto2` (part of `indi-3rdparty`):

```
checking for lt_dlinit in -lltdl... no
configure: error: libgphoto2 requires the ltdl library, included with libtool
```

Both are the same root cause: `libz.dylib` / `libltdl.dylib` (and about a dozen other bootstrap libs —
openssl, sqlite, libxml2, expat, icu, libffi, gettext, libunistring, liblzma, libb2, libbzip2, pkgconf)
were arm64, so the x86_64 linker step couldn't use them.

Check for this yourself with:

```bash
for f in "$CRAFT_DIR"/lib/*.dylib; do
  arch=$(lipo -info "$f" 2>/dev/null | grep -o "architecture: .*")
  [[ -n "$arch" && "$arch" != *"x86_64"* ]] && echo "$(basename "$f"): $arch"
done
```

`fix-script.sh` does exactly this and, for anything it finds, runs `craft --unmerge`, deletes the stale
`build/…` work directory, and does a clean `craft -i` for that package so it gets rebuilt for the correct
ABI. Note `craft -i --compile <pkg>` on its own is **not** enough here — if the package's `work` directory
is a leftover from an earlier build/fetch, `--compile` (`--configure --make`) can fail with a `configure:
No such file or directory` because the source was never freshly unpacked. The full unmerge-and-clean cycle
is what actually fixes it.

## Follow-up issue (not automated, situational): `indi-3rdparty` master vs. stable

Even with both bugs above fixed, building `indi-3rdparty` from the `master` target can fail while
compiling `indi-toupbase` (shared by the ToupTek/AltairCam/OGMA/... camera family):

```
error: use of undeclared identifier 'Toupcam_get_Int'; did you mean 'Toupcam_get_Size'?
```

This is a version skew between the `indi-3rdparty` git master source and the vendored camera SDK headers
Craft installs alongside it — the master branch expects a newer SDK API than what's currently packaged.
Building the tagged release instead sidesteps it, since tag and SDK version are kept in sync:

```bash
craft -i --target stable indi-3rdparty   # instead of --target master
```

We did **not** bake this into `fix-script.sh` because it trades away whatever driver fixes exist only on
`master` — if you don't own a ToupTek/AltairCam-family camera you may not even hit this, and if you do
want `master`, you may prefer to just exclude/patch that one driver instead. Documenting it here so you
know what you're looking at if you hit it.

## Usage

```bash
cd kstars-on-osx-craft        # rlancaste's repo, wherever you cloned it
/path/to/fix-script.sh
```

The script:
1. Backs up `build-kstars.sh` to `build-kstars.sh.orig` (skipped if that backup already exists).
2. Patches the `indiserver` → `indi` naming (idempotent — safe to run more than once).
3. If `ASTRO_ROOT`/`CRAFT_DIR` (see `build-env.sh`) already exists, scans `craft-root/lib` for
   architecture-mismatched `.dylib` files and offers to rebuild them for the current Craft ABI.

It does not touch the `indi-3rdparty` master/stable question above — that's a judgement call depending on
what hardware you're targeting.

## Status upstream

Tracked so far only in this repo: [apos/kstars_scripts#1](https://github.com/apos/kstars_scripts/issues/1).
**No issue or PR has been filed against `rlancaste/kstars-on-osx-craft` yet** — that's a deliberate,
separate decision, not done yet.

Bug 1 (the rename) is small and unambiguous enough to be a clean PR against the upstream script, if/when
that's decided. Bug 2 is specific to how an individual `craft-root` was bootstrapped, so it's not something
a PR against the script itself can really fix; it's documented here for the next person who searches the
error message.

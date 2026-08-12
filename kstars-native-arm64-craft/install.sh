#!/usr/bin/env bash
#
# install.sh — end-to-end native arm64 KStars/INDI build via plain KDE Craft.
# See README.md in this folder for background on why this approach exists
# (short version: rlancaste/kstars-on-osx-craft targets x86_64/Rosetta, which
# is pointless on Apple Silicon since Homebrew already ships that build).
#
# What this does:
#   1. Bootstraps a fresh Craft install at $CRAFT_PREFIX (default: ~/CraftRoot),
#      non-interactively defaulting to native arm64.
#   2. Patches the libftdi blueprint to skip its test suite (missing boost
#      test framework dependency otherwise).
#   3. Builds KStars (which pulls in INDI as a dependency automatically).
#   4. Packages a self-contained .dmg via Craft's built-in `--package` action.
#   5. Cleans up stale launchd D-Bus job registrations that are the single
#      most confusing failure mode here (see README's "Known gotcha" section)
#      — matters most on a second run if a previous attempt left broken state.
#
# Usage:
#   ./install.sh                    # fresh install to ~/CraftRoot
#   CRAFT_PREFIX=/other/path ./install.sh
#
# Safe to re-run: steps that are already done are skipped or no-ops.

set -euo pipefail

CRAFT_PREFIX="${CRAFT_PREFIX:-$HOME/CraftRoot}"
WORK_DIR="$(mktemp -d /tmp/craft-bootstrap.XXXXXX)"

log() { echo ""; echo "== $* =="; }

# ---------------------------------------------------------------------------
# 1. Bootstrap Craft
# ---------------------------------------------------------------------------
if [[ -f "$CRAFT_PREFIX/craft/craftenv.sh" ]]; then
	log "Craft already bootstrapped at $CRAFT_PREFIX, skipping bootstrap"
else
	log "Bootstrapping Craft at $CRAFT_PREFIX (native arm64 by default)"
	mkdir -p "$CRAFT_PREFIX"
	if [[ -n "$(ls -A "$CRAFT_PREFIX" 2>/dev/null)" ]]; then
		echo "error: $CRAFT_PREFIX exists and is not empty — CraftBootstrap.py refuses that." >&2
		echo "Remove it or pick a different CRAFT_PREFIX." >&2
		exit 1
	fi
	curl -sL raw.githubusercontent.com/KDE/craft/master/setup/CraftBootstrap.py -o "$WORK_DIR/setup.py"
	# --use-defaults is required for a non-interactive run: without it the
	# installer prompts "Select target architecture [0] x86_64, [1] arm64
	# (Default is arm64)" and blocks forever on stdin if there's no tty.
	python3 "$WORK_DIR/setup.py" --prefix "$CRAFT_PREFIX" --use-defaults
fi

# shellcheck disable=SC1091
source "$CRAFT_PREFIX/craft/craftenv.sh"

ABI=$(craft --version 2>&1 | grep -o "macos-clang-[a-z0-9_]*" | head -1)
echo "Craft ABI: ${ABI:-unknown}"
if [[ "$ABI" != "macos-clang-arm64" ]]; then
	echo "warning: expected macos-clang-arm64, got '$ABI' — this script assumes native arm64." >&2
fi

# ---------------------------------------------------------------------------
# 2. Patch libftdi (skip its test suite)
# ---------------------------------------------------------------------------
FTDI_BLUEPRINT="$CRAFT_PREFIX/etc/blueprints/locations/craft-blueprints-kde/libs/libftdi/libftdi.py"
if [[ -f "$FTDI_BLUEPRINT" ]]; then
	if grep -q 'BUILD_TESTS={self.subinfo' "$FTDI_BLUEPRINT"; then
		log "Patching libftdi blueprint to disable its test suite"
		sed -i '' \
			-e 's/f"-DBUILD_TESTS={self\.subinfo\.options\.dynamic\.buildTests\.asOnOff}",/"-DBUILD_TESTS=OFF",/' \
			"$FTDI_BLUEPRINT"
	else
		log "libftdi blueprint already patched (or doesn't need it), skipping"
	fi
else
	log "libftdi blueprint not found yet — Craft will fetch it on first use, patch step skipped"
	echo "  (if the build later fails on libftdi with a missing boost test framework error,"
	echo "   re-run this script — the blueprint will exist by then and get patched.)"
fi

# ---------------------------------------------------------------------------
# 3. Clean stale D-Bus launchd registrations (see README's "Known gotcha")
# ---------------------------------------------------------------------------
log "Checking for stale D-Bus launchd job registrations"
UID_NUM=$(id -u)
for label in org.freedesktop.dbus-kstars org.freedesktop.dbus-session; do
	info=$(launchctl list "$label" 2>/dev/null || true)
	if [[ -n "$info" ]]; then
		program=$(echo "$info" | grep '"Program"' | sed -E 's/.*"Program" = "(.*)";/\1/')
		if [[ -n "$program" && ! -x "$program" ]]; then
			echo "  $label points to a missing binary ($program) — unloading stale job"
			launchctl bootout "gui/$UID_NUM/$label" 2>/dev/null || true
		else
			echo "  $label looks fine, leaving it alone"
		fi
	fi
done
rm -f "$HOME/Library/LaunchAgents/org.freedesktop.dbus-kstars.plist.stale-check" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 4. Build KStars (pulls in INDI automatically)
# ---------------------------------------------------------------------------
log "Building KStars (this resolves and builds INDI as a dependency automatically)"
craft kstars

# ---------------------------------------------------------------------------
# 5. Package a self-contained .dmg
# ---------------------------------------------------------------------------
log "Packaging a self-contained .dmg"
craft --package kstars

DMG=$(find "$CRAFT_PREFIX/tmp" -maxdepth 1 -iname "kstars-*.dmg" -newer "$CRAFT_PREFIX/craft/craftenv.sh" 2>/dev/null | head -1)
if [[ -z "$DMG" ]]; then
	DMG=$(find "$CRAFT_PREFIX/tmp" -maxdepth 1 -iname "kstars-*.dmg" 2>/dev/null | sort | tail -1)
fi

log "Done"
echo "App (needs \`source $CRAFT_PREFIX/craft/craftenv.sh\` first, for QT_PLUGIN_PATH):"
echo "  $CRAFT_PREFIX/Applications/KDE/kstars.app"
echo ""
echo "Self-contained DMG (no craft environment needed, this is the one to give to"
echo "someone else or just drag into /Applications):"
echo "  ${DMG:-<not found — check $CRAFT_PREFIX/tmp manually>}"

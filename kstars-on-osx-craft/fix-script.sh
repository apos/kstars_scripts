#!/usr/bin/env bash
#
# fix-script.sh — patches rlancaste/kstars-on-osx-craft for two bugs hit when
# building on macOS in Aug 2026 (Craft blueprint renames + a stale-arch
# craft-root). See README.md in this folder for the full explanation of both
# bugs and why they happen.
#
# Usage:
#   cd /path/to/kstars-on-osx-craft   # rlancaste's repo checkout
#   /path/to/fix-script.sh
#
# Safe to run more than once (idempotent).

set -uo pipefail

SCRIPT_NAME="build-kstars.sh"

if [[ ! -f "$SCRIPT_NAME" ]]; then
	echo "error: $SCRIPT_NAME not found in the current directory." >&2
	echo "cd into your kstars-on-osx-craft checkout first." >&2
	exit 1
fi

# ---------------------------------------------------------------------------
# Bug 1: indiserver -> indi package rename
# ---------------------------------------------------------------------------
echo "== Bug 1: patching indiserver -> indi package names in $SCRIPT_NAME =="

if grep -q "indiserver" "$SCRIPT_NAME"; then
	if [[ ! -f "${SCRIPT_NAME}.orig" ]]; then
		cp "$SCRIPT_NAME" "${SCRIPT_NAME}.orig"
		echo "backed up original to ${SCRIPT_NAME}.orig"
	fi

	# Order matters: longest match first, so shorter names don't clobber
	# substrings of the longer ones.
	sed -i '' \
		-e 's/indiserver-3rdparty-libraries/indi-3rdparty-libs/g' \
		-e 's/indiserver-3rdparty/indi-3rdparty/g' \
		-e 's/indiserver/indi/g' \
		"$SCRIPT_NAME"

	echo "patched. Diff against the backup:"
	diff "${SCRIPT_NAME}.orig" "$SCRIPT_NAME" || true
else
	echo "no 'indiserver' references found — already patched, or this is a newer"
	echo "version of the script that doesn't need it. Nothing to do."
fi

echo ""

# ---------------------------------------------------------------------------
# Bug 2: stale arm64 binaries in an x86_64 craft-root
# ---------------------------------------------------------------------------
echo "== Bug 2: checking craft-root for architecture-mismatched libraries =="

ASTRO_ROOT="${ASTRO_ROOT:-$HOME/AstroRoot}"
CRAFT_DIR="${CRAFT_DIR:-$ASTRO_ROOT/craft-root}"

if [[ ! -d "$CRAFT_DIR/craft" ]]; then
	echo "no craft-root found yet at $CRAFT_DIR — nothing to check."
	echo "(this check only matters after you've bootstrapped Craft at least once.)"
	exit 0
fi

# shellcheck disable=SC1091
source "$CRAFT_DIR/craft/craftenv.sh" >/dev/null 2>&1

TARGET_ARCH=$(craft --version 2>&1 | grep -o "x86_64\|arm64" | head -1)
TARGET_ARCH="${TARGET_ARCH:-x86_64}"   # this script assumes the documented x86_64/Rosetta target

mismatched=()
for f in "$CRAFT_DIR"/lib/*.dylib; do
	[[ -e "$f" ]] || continue
	arch=$(lipo -info "$f" 2>/dev/null | grep -o "architecture: .*" | sed 's/architecture: //')
	if [[ -n "$arch" && "$arch" != "$TARGET_ARCH" ]]; then
		mismatched+=("$(basename "$f")")
	fi
done

if [[ ${#mismatched[@]} -eq 0 ]]; then
	echo "all libraries in $CRAFT_DIR/lib match the target architecture ($TARGET_ARCH). Nothing to fix."
	exit 0
fi

echo "found ${#mismatched[@]} mismatched .dylib files (expected $TARGET_ARCH):"
printf '  %s\n' "${mismatched[@]}"
echo ""

# Map dylib basenames back to their craft package short name. This list
# covers what we saw in practice; if craft --search doesn't find one of
# these for your setup, it's skipped with a warning rather than failing.
declare -A DYLIB_TO_PKG=(
	[libb2]=libb2
	[libbz2]=libbzip2
	[libcrypto]=openssl
	[libssl]=openssl
	[libexpat]=expat
	[libffi]=libffi
	[libasprintf]=gettext
	[libgettextlib]=gettext
	[libgettextpo]=gettext
	[libgettextsrc]=gettext
	[libintl]=gettext
	[libicudata]=icu
	[libicui18n]=icu
	[libicuio]=icu
	[libicutest]=icu
	[libicutu]=icu
	[libicuuc]=icu
	[libltdl]=libtool
	[liblzma]=liblzma
	[libpkgconf]=pkgconf
	[libsqlite3]=sqlite
	[libunistring]=libunistring
	[libxml2]=libxml2
	[libz]=zlib
)

pkgs_to_fix=()
for name in "${mismatched[@]}"; do
	base="${name%%.*}"
	pkg="${DYLIB_TO_PKG[$base]:-}"
	if [[ -n "$pkg" ]]; then
		if [[ ! " ${pkgs_to_fix[*]:-} " =~ " $pkg " ]]; then
			pkgs_to_fix+=("$pkg")
		fi
	else
		echo "warning: no known craft package for $name — skipping, fix manually if needed."
	fi
done

echo "will rebuild these craft packages for $TARGET_ARCH: ${pkgs_to_fix[*]}"
read -r -p "proceed? [y/N] " ans
if [[ ! "$ans" =~ ^[Yy]$ ]]; then
	echo "skipped rebuild. Run again when ready."
	exit 0
fi

for pkg in "${pkgs_to_fix[@]}"; do
	echo ""
	echo "--- rebuilding $pkg ---"
	craft --unmerge "$pkg" || true
	builddir=$(find "$CRAFT_DIR" -maxdepth 3 -type d -iname "$pkg" -path "*/build/*" 2>/dev/null | head -1)
	if [[ -n "$builddir" ]]; then
		echo "removing stale build dir: $builddir"
		rm -rf "$builddir"
	fi
	craft -i "$pkg"
done

echo ""
echo "done. Re-run this script to verify — it should report no mismatches left."

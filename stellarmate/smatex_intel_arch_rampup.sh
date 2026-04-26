#!/bin/bash
# smatex_intel_arch_rampup.sh
#
# Setup-Skript für StellarMate auf Intel/Arch Linux.
# Aktuell: installiert udev-Regel zur eindeutigen Identifikation
# der CH340-USB-Serial-Adapter (OnStep + Genesis Focuser).
#
# Hintergrund: Beide Geräte haben identische USB-IDs (1a86:7523)
# und keine Seriennummer. Unterscheidung über USB-Topologie:
# - OnStep:   direkt am USB-Controller (devpath ohne Punkt)
# - Focuser:  hinter einem USB-Hub        (devpath mit Punkt)

set -euo pipefail

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

RULE_FILE="/etc/udev/rules.d/99-ch340-astronomy.rules"

if [[ $EUID -ne 0 ]]; then
    echo -e "${YELLOW}Bitte mit sudo ausführen.${NC}"
    exec sudo "$0" "$@"
fi

echo -e "${GREEN}>>> Schreibe udev-Regel nach ${RULE_FILE}${NC}"

cat > "$RULE_FILE" << 'EOF'
# CH340-Adapter eindeutig identifizieren (OnStep + Genesis Focuser)
# Beide Geräte haben identische USB-IDs (1a86:7523).
# Unterscheidung über USB-Topologie via devpath:
#   - Focuser hängt hinter einem USB-Hub  -> devpath enthält Punkt(e)
#   - OnStep  hängt direkt am Controller  -> devpath ohne Punkt

# Genesis Focuser: CH340 über Hub (devpath enthält Punkte)
SUBSYSTEM=="tty", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="7523", ATTRS{devpath}=="*.*", ENV{CH340_DEVICE}="focuser"

# Symlink Genesis Focuser
SUBSYSTEM=="tty", ENV{CH340_DEVICE}=="focuser", SYMLINK+="serial/by-id/usb-CH340_Genesis-Focuser-if00-port0"

# Symlink OnStep (alle anderen CH340)
SUBSYSTEM=="tty", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="7523", ENV{CH340_DEVICE}!="focuser", SYMLINK+="serial/by-id/usb-CH340_OnStep-if00-port0"
EOF

chmod 644 "$RULE_FILE"
echo -e "${GREEN}>>> Regel installiert.${NC}"

echo -e "${GREEN}>>> udev-Regeln neu laden${NC}"
udevadm control --reload-rules

echo -e "${GREEN}>>> Trigger für tty-Subsystem auslösen${NC}"
udevadm trigger --action=change --subsystem-match=tty
udevadm settle

# Falls die Symlinks nach reinem Trigger noch nicht erscheinen,
# binden wir die CH340-USB-Geräte einmal kurz neu.
if ! ls /dev/serial/by-id/usb-CH340_* >/dev/null 2>&1; then
    echo -e "${YELLOW}>>> Symlinks fehlen - rebinde CH340-USB-Geräte${NC}"
    for dev in /sys/bus/usb/devices/*/idProduct; do
        [[ -f "$dev" ]] || continue
        product=$(cat "$dev")
        vendor=$(cat "${dev%/idProduct}/idVendor")
        if [[ "$vendor" == "1a86" && "$product" == "7523" ]]; then
            usbid=$(basename "${dev%/idProduct}")
            echo "   - rebind $usbid"
            echo "$usbid" > /sys/bus/usb/drivers/usb/unbind 2>/dev/null || true
            sleep 0.3
            echo "$usbid" > /sys/bus/usb/drivers/usb/bind   2>/dev/null || true
        fi
    done
    udevadm settle
fi

echo
echo -e "${GREEN}>>> Aktuelle by-id-Einträge:${NC}"
ls -la /dev/serial/by-id/ 2>/dev/null || echo -e "${RED}   (keine vorhanden)${NC}"

echo
echo -e "${GREEN}Fertig.${NC} In KStars/Ekos verwenden:"
echo "  OnStep:  /dev/serial/by-id/usb-CH340_OnStep-if00-port0"
echo "  Focuser: /dev/serial/by-id/usb-CH340_Genesis-Focuser-if00-port0"

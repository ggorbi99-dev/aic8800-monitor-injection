#!/usr/bin/env bash
# AIC8800D80: Frame injizieren (Monitor-Mode).
#
# Aufruf:  sudo aic-inject.sh <kanal> <typ> [anzahl] [mac-endbyte]
#   typ: deauth | auth | disassoc | beacon | probereq | action
# Beispiel: sudo aic-inject.sh 36 deauth 5      (5 Deauth-Frames auf Kanal 36)
#
# WICHTIG: Der Treiber braucht vor jeder Sitzung ein down/up + set channel,
# sonst bleibt die TX-Queue des Monitor-VIFs unbenutzt und die Firmware
# verwirft die Frames stillschweigend. Dieses Skript macht das automatisch.
set -u
CH="${1:?Kanal fehlt (z.B. 36 oder 6)}"
TYP="${2:?Typ fehlt (deauth|auth|disassoc|beacon|probereq|action)}"
CNT="${3:-5}"
MAC="${4:-01}"

MON=$(for i in $(iw dev | awk '/Interface/{print $2}'); do
         t=$(iw dev "$i" info 2>/dev/null | awk '/type/{print $2}')
         [ "$t" = "monitor" ] && { echo "$i"; break; }
      done)
[ -n "${MON:-}" ] || { echo "Kein Monitor-Interface gefunden. Stick gesteckt? Treiber geladen?"; iw dev; exit 1; }

# Managed-VIF des AIC gibt die Kanalhoheit nicht frei, solange es existiert
MGD=$(for i in $(iw dev | awk '/Interface/{print $2}'); do
         [ "$i" = "wlan0" ] && continue
         t=$(iw dev "$i" info 2>/dev/null | awk '/type/{print $2}')
         [ "$t" = "managed" ] && { echo "$i"; break; }
      done)
[ -n "${MGD:-}" ] && iw dev "$MGD" del

# Die entscheidende Sequenz: down -> up -> Kanal
ip link set "$MON" down;  sleep 1
ip link set "$MON" up;    sleep 1
iw dev "$MON" set channel "$CH" || { echo "Kanal $CH setzbar? (1-13, 36-48, 149-165)"; exit 1; }
sleep 1

echo "Injiziere $CNT x $TYP auf Kanal $CH über $MON"
python3 $(dirname "$0")/inject-raw.py "$MON" "$CH" "$TYP" "$CNT" "$MAC"

echo
echo "Firmware-Rückmeldung:"
dmesg | grep "AICMON: cfm" | tail -"$CNT"

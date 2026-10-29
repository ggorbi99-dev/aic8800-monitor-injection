#!/usr/bin/env bash
# AIC8800D80: Frame injizieren (Monitor-Mode) — nur für autorisierte Netze.
#
# Aufruf:  sudo aic-inject.sh <kanal> <typ> [anzahl] [mac-endbyte] [bssid]
#   typ: beacon | probereq | wildprobe | action | auth | deauth | disassoc
#
# Beispiele (unkritisch):
#   sudo aic-inject.sh 11 beacon   10
#   sudo aic-inject.sh 36 probereq  5
#   sudo aic-inject.sh 6  wildprobe 3
#
# deauth/disassoc beenden fremde Verbindungen und sind nur für Netze gedacht,
# die dir gehören. Sie verlangen eine ausdrückliche Bestätigung:
#   I_AM_AUTHORISED=1 sudo -E aic-inject.sh 6 deauth 3
#
# WICHTIG: Der Treiber braucht vor jeder Sitzung ein down/up + set channel,
# sonst bleibt die TX-Queue des Monitor-VIFs unbenutzt und die Firmware
# verwirft die Frames stillschweigend. Dieses Skript macht das automatisch.
set -u

NOTICE="Nutzung nur auf Netzen/Geräten, für die du berechtigt bist. Details: NOTICE.md"

CH="${1:?Kanal fehlt (z.B. 36 oder 6)}"
TYP="${2:?Typ fehlt (beacon|probereq|wildprobe|action|auth|deauth|disassoc)}"
CNT="${3:-5}"
MAC="${4:-01}"
BSSID="${5:-}"
CLIENT="${6:-}"

case "$TYP" in
  deauth|disassoc)
    echo "Hinweis: '$TYP' beendet bestehende Verbindungen anderer Stationen."
    echo "$NOTICE"
    if [ "${I_AM_AUTHORISED:-}" != "1" ]; then
      echo
      echo "Abgebrochen. Wenn das dein eigenes Testnetz ist, ausdrücklich bestätigen mit:"
      echo "    I_AM_AUTHORISED=1 sudo -E $0 $CH $TYP $CNT $MAC"
      exit 2
    fi
    ;;
  *) echo "$NOTICE" ;;
esac

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

echo
echo "Injiziere $CNT x $TYP auf Kanal $CH über $MON"
python3 "$(dirname "$0")/inject-raw.py" "$MON" "$CH" "$TYP" "$CNT" "$MAC" "$BSSID" "" "$CLIENT"

echo
echo "Firmware-Rückmeldung:"
dmesg | grep "AICMON: cfm" | tail -"$CNT" 2>/dev/null || echo "  (keine AICMON-Zeilen — Debug-Patch 0002 nicht angewendet)"

#!/usr/bin/env bash
# AIC8800D80 als WiFi-Sniffer: Kanal waehlen, mitschneiden.
# Aufruf:  sudo ~/wifi-sniff.sh [kanal] [ausgabedatei]
# Beispiel: sudo ~/wifi-sniff.sh 6 /tmp/kanal6.pcapng
#           sudo ~/wifi-sniff.sh 36
# Beenden mit Ctrl-C.
set -u
CH="${1:-6}"
OUT="${2:-/tmp/sniff-${CH}-$(date +%H%M%S).pcapng}"

find_mon() {
  for i in $(iw dev | awk '/Interface/{print $2}'); do
    t=$(iw dev "$i" info 2>/dev/null | awk '/type/{print $2}')
    [ "$t" = "monitor" ] && { echo "$i"; return; }
  done
}
find_aic_managed() {
  for i in $(iw dev | awk '/Interface/{print $2}'); do
    [ "$i" = "wlan0" ] && continue
    t=$(iw dev "$i" info 2>/dev/null | awk '/type/{print $2}')
    [ "$t" = "managed" ] && { echo "$i"; return; }
  done
}

MON=$(find_mon)
if [ -z "${MON:-}" ]; then
  echo "!! Kein Monitor-Interface. Stick gesteckt? Treiber geladen?"
  iw dev | grep -E "Interface|type"
  exit 1
fi

# Managed-VIF muss weg, sonst bestimmt sie den Kanal (-EBUSY)
MGD=$(find_aic_managed)
[ -n "${MGD:-}" ] && { echo "Entferne Managed-Interface $MGD (gibt Kanalhoheit frei)"; iw dev "$MGD" del; }

ip link set "$MON" up
sleep 0.5
if ! iw dev "$MON" set channel "$CH" 2>/dev/null; then
  echo "!! Kanal $CH nicht setzbar. Verfuegbar sind z.B. 1-13, 36-48, 149-165."
  exit 1
fi

echo "Sniffer laeuft: $MON auf Kanal $CH -> $OUT"
echo "Beenden mit Ctrl-C."
echo
exec dumpcap -i "$MON" -w "$OUT" -q

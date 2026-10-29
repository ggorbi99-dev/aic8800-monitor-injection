#!/usr/bin/env python3
"""Injiziert 802.11-Frames über ein Monitor-Interface (Radiotap + Raw-Socket).

Aufruf: sudo python3 inject-raw.py <iface> <kanal> [typ] [anzahl]
   typ: beacon | action | probereq   (Standard: action)
"""
import socket, struct, sys, time

IFACE = sys.argv[1] if len(sys.argv) > 1 else "wlan2"
CHAN  = int(sys.argv[2]) if len(sys.argv) > 2 else 36
KIND  = (sys.argv[3] if len(sys.argv) > 3 else "action").lower()
COUNT = int(sys.argv[4]) if len(sys.argv) > 4 else 5
LASTMAC = int(sys.argv[5], 16) if len(sys.argv) > 5 else 0x01
TARGET_BSSID = bytes.fromhex(sys.argv[6].replace(":","")) if len(sys.argv) > 6 else None
SSID_ARG = sys.argv[7].encode() if len(sys.argv) > 7 and sys.argv[7] else None
CLIENT_MAC = bytes.fromhex(sys.argv[8].replace(":","")) if len(sys.argv) > 8 and sys.argv[8] else None

SRC = bytes([0x02, 0x00, 0x00, 0xde, 0xad, LASTMAC])   # lokal verwaltete MAC

def tx_packets():
    try:
        with open("/sys/class/net/%s/statistics/tx_packets" % IFACE) as f:
            return int(f.read())
    except OSError:
        return -1

def radiotap():
    """version 0, pad 0, len 8, present 0 -> keine Felder, Treiber nimmt Defaults."""
    return struct.pack("<BBHI", 0, 0, 8, 0)

def hdr(fc0, addr1=None, addr2=None, addr3=None):
    """addr1 = DA, addr2 = SA, addr3 = BSSID.
    Standard: DA Broadcast, SA = unsere Test-MAC, BSSID = SA."""
    return (struct.pack("<BB", fc0, 0x00)     # Frame Control
            + struct.pack("<H", 0)            # Duration
            + (addr1 if addr1 else b"\xff" * 6)   # Addr1 DA
            + (addr2 if addr2 else SRC)       # Addr2 SA
            + (addr3 if addr3 else SRC)       # Addr3 BSSID
            + struct.pack("<H", 0))           # Sequence Control

BROADCAST = b"\xff" * 6

def build(kind):
    if kind == "beacon":
        fixed = struct.pack("<QHH", 0, 100, 0x0411)
        ssid = b"aic-inject-test"
        ies = bytes([0x00, len(ssid)]) + ssid + bytes([0x01, 0x01, 0x82])
        return hdr(0x80) + fixed + ies
    if kind == "probereq":
        ssid = SSID_ARG or b"aic-inject-test"
        ies = bytes([0x00, len(ssid)]) + ssid + bytes([0x01, 0x01, 0x82])
        return hdr(0x40, addr3=BROADCAST) + ies
    if kind == "wildprobe":
        # Wildcard-Probe-Request: SSID-IE mit Laenge 0 -> jeder AP antwortet
        ies = bytes([0x00, 0x00]) + bytes([0x01, 0x01, 0x82])
        return hdr(0x40, addr3=BROADCAST) + ies
    if kind == "deauth":
        # Deauth: DA = Ziel-Client, SA/BSSID = Access Point (gefälscht)
        b = TARGET_BSSID or BROADCAST
        da = CLIENT_MAC or b
        return hdr(0xc0, addr1=da, addr2=b, addr3=b) + struct.pack("<H", 7)
    if kind == "auth":
        # Authentication, Open System, Seq 1, Status 0 — an BSSID adressiert
        b = TARGET_BSSID or BROADCAST
        return hdr(0xb0, addr1=b, addr3=b) + struct.pack("<HHH", 0, 1, 0)
    if kind == "disassoc":
        b = TARGET_BSSID or BROADCAST
        da = CLIENT_MAC or b
        return hdr(0xa0, addr1=da, addr2=b, addr3=b) + struct.pack("<H", 8)
    # action (0xd0): Category 127 vendor specific + OUI + Typ + Nutzlast
    body = bytes([0x7f]) + b"\xae\xe2\xae" + bytes([0x01]) + b"AICMON-INJECT-PROBE"
    return hdr(0xd0) + body

def main():
    frame = radiotap() + build(KIND)
    s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW)
    s.bind((IFACE, 0))
    before = tx_packets()
    print("Interface %s Kanal %d Typ %s" % (IFACE, CHAN, KIND))
    print("Frame %d Bytes (Radiotap 8 + 802.11 %d), FC=0x%02x"
          % (len(frame), len(frame) - 8, frame[8]))
    print("TX-Zaehler vorher: %d" % before)
    for i in range(1, COUNT + 1):
        s.send(frame)
        print("  gesendet %d/%d" % (i, COUNT))
        time.sleep(0.2)
    time.sleep(0.6)
    after = tx_packets()
    print("TX-Zaehler nachher: %d (Delta %d)" % (after, after - before))

if __name__ == "__main__":
    main()

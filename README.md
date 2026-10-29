# aic8800-monitor-injection

**Making the AIC8800D80 (USB Wi-Fi 6, e.g. UGREEN AX900) work as a monitor-mode
sniffer *and* a frame injector on Linux.**

Verified working: monitor mode, radiotap injection, on both 2.4 GHz and 5 GHz.
No firmware modification — two small patches to the out-of-tree Linux driver.

> **Authorised use only.** Monitor mode and frame injection are standard,
> documented 802.11 features and this repository exists to make a device the
> author owns work as specified under Linux. Use it only on networks and
> hardware you own or are authorised to test. See [NOTICE.md](NOTICE.md).

---

## TL;DR

Out of the box, an AIC8800D80 on Linux gives you monitor mode that *receives*
fine but whose *transmitted* frames never reach the air. The driver reports
success, the firmware reports `done=1`, and a second radio sees nothing.

Three things are wrong, and all three are fixable in the driver:

| # | Problem | Fix |
|---|---------|-----|
| 1 | Monitor interface creation fails with `-EINVAL` (`Monitor+Data interface support (MON_DATA) disabled`) | `CONFIG_RWNX_MON_DATA=y` — it is hard-coded to `n` while `interface_modes` already advertises `monitor` |
| 2 | Firmware loading fails with "file failed to open" on kernel 7.x, because the loader opens firmware via `filp_open()` | `CONFIG_USE_FW_REQUEST=y` (the proper `request_firmware()` path exists but was never built) |
| 3 | **Injected frames are silently dropped** | Route `raw_frame` frames through the confirmation ring (`status_desc_addr` bit 31) instead of the `fixed_rate` path (bit 30) |

Plus one usage requirement: the monitor interface must be **re-opened**
(`down` → `up` → `set channel`) before injecting, because the TX queue for an
unknown/monitor VIF is only initialised in `rwnx_open()`.

---

## Verification

Closed-loop test: inject from the AIC, capture on a **second radio** on the same
channel, count the frames that actually appear in the air.

| Frame | 2.4 GHz (ch 11) | 5 GHz (ch 36) | Firmware status |
|-------|-----------------|---------------|-----------------|
| Deauthentication (0xc0) | 3/3 | 3/3 | `done=1` |
| Beacon (0x80) | 3/3 | 3/3 | `done=1` |
| Probe Request (0x40) | 3/3 | 3/3 | `done=1` |
| Action (0xd0) | 3/3 | 3/3 | `done=1` |
| Authentication (0xb0) | 3/3 | 3/3 | `done=1` |

Before the patch, only Action frames (`0xd0`) were transmitted — they happen to
take the confirmation-ring path already. Beacons and everything else vanished.

---

## Why only Action frames worked before

`rwnx_tx_push()` picks the push path from the frame-control byte:

```c
if ((flags & TXU_CNTRL_MGMT) && (fc == 0xd0 || fc == 0x10 || fc == 0x30)) || ethertype 0x8e88/0xb488
    need_cfm = 1;  status_desc_addr = (1 << 31) | ring_idx;    /* works */
else
    need_cfm = 0;  status_desc_addr = (1 << 30) | rate_config; /* silently dropped */
```

The D80 firmware only transmits frames pushed through the confirmation ring.
The `fixed_rate` encoding is accepted — no error, no log — and never sent.

---

## Applying the patches

The patches target the out-of-tree driver used by Arch/CachyOS DKMS packages
(`aic8800d80-dkms` and friends), which is based on
[shenmintao/aic8800d80](https://github.com/shenmintao/aic8800d80)
(branch `legacy-mcu1` for units reporting `chip_mcu_id=1`, `main` otherwise).

```bash
git clone --branch legacy-mcu1 https://github.com/shenmintao/aic8800d80.git
cd aic8800d80
git apply /path/to/patches/0001-monitor-injection-fix.patch
git apply /path/to/patches/0003-firmware-chipdir-path.patch
# optional, for verbose diagnostics:
# git apply /path/to/patches/0002-debug-instrumentation.patch

sudo ./install.sh          # builds DKMS modules + installs firmware
# replug the adapter, then:
iw dev                     # expect a monitor interface
```

### Why patch 0003 is needed (kernel 7.x)

With `CONFIG_USE_FW_REQUEST=y` the loader passes the firmware name **without**
the chip subdirectory, so the kernel searches `/lib/firmware/` while the files
live in `/lib/firmware/aic8800D80/`. Patch 0003 adds `aic_req_fw_chipdir()`,
which prepends the chip directory (derived from `chipid`) and falls back to the
bare name, so both layouts keep working.

Without that patch, the workaround is to make the names resolvable at the
firmware root:

```bash
sudo sh -c 'cd /lib/firmware/aic8800D80 && for f in *; do
              [ -e "/lib/firmware/$f" ] || ln -s "aic8800D80/$f" "/lib/firmware/$f"; done'
```

---

## Usage

### Sniffing

```bash
sudo ./tools/wifi-sniff.sh 6          # 2.4 GHz channel 6
sudo ./tools/wifi-sniff.sh 36 out.pcapng
```

The script removes the managed VIF (which otherwise keeps channel ownership and
makes `set channel` fail with `-EBUSY`), sets the channel and runs `dumpcap`.

### Injecting

```bash
sudo ./tools/aic-inject.sh <channel> <type> [count] [mac-suffix] [bssid]

sudo ./tools/aic-inject.sh 11 beacon   10     # advertise a test BSS
sudo ./tools/aic-inject.sh 36 probereq  5     # directed probe request
sudo ./tools/aic-inject.sh 6  wildprobe 3     # broadcast probe request
```

Supported frame types: `beacon`, `probereq`, `wildprobe`, `action`, `auth`,
`deauth`, `disassoc`.

`deauth` and `disassoc` terminate other stations' connections. They are
implemented for interoperability and regression testing on networks you control,
are deliberately absent from every example above, and require an explicit
acknowledgement before the tool will send them:

```bash
I_AM_AUTHORISED=1 sudo -E ./tools/aic-inject.sh 6 deauth 3
```

The script performs the mandatory `down → up → set channel` sequence, then sends
raw frames through a `AF_PACKET` socket and prints the firmware's confirmation.

---

## Notes and limitations

* **`aireplay-ng` will not work** on this driver. It switches the interface into
  monitor mode via the legacy WEXT ioctl `SIOCSIWMODE`, which the AIC driver does
  not implement, so it aborts before transmitting anything. `tools/inject-raw.py`
  needs no WEXT and is self-contained (Python 3 standard library only).
* Channel setting requires that no other VIF holds the channel: delete the
  managed interface first (the tool does this).
* Broadcast injections are never ACKed; the `acked` bit in the firmware status is
  not meaningful for them.
* Do not rely on Probe-Response based "is my injection working?" tests with
  consumer APs — in testing, neither the local AP nor neighbours answered
  *any* probe request (including from real clients). Use a second radio on the
  same channel instead.
* Only Wi-Fi management frames were tested. Data frames from a monitor VIF were
  not part of this work.
* This repository contains no firmware blobs and redistributes no driver code;
  it ships patches and tools only.

## Legal

Use only on networks and hardware you own or are authorised to test. Injecting
deauthentication or other management frames into networks you do not control is
illegal in most jurisdictions.

This repository contains **no firmware images and no decompiled firmware** —
only patches against GPL-2.0 driver code, and standalone tools (MIT). No
protection measure was circumvented and no firmware was modified.

The firmware examination served interoperability only (understanding the
driver/firmware interface). See [NOTICE.md](NOTICE.md) for the full statement on
purpose, licensing, dual use and liability. Not affiliated with AICSemi, Radxa,
UGREEN, TP-Link or any upstream driver repository.

None of this is legal advice; for commercial use obtain qualified advice.

## Credits

* [shenmintao/aic8800d80](https://github.com/shenmintao/aic8800d80) — maintained
  AIC8800 driver tree this work is based on
* AICSemi / Radxa — original driver source (GPL-2.0)
* RivieraWaves UMACS MAC stack, which the firmware is built from

## License

Patches: **GPL-2.0-only**, inherited from the driver they modify.
Tools (`tools/`): **MIT**.

---

## Appendix: firmware analysis (why the fix is what it is)

The firmware (ARM Thumb-2, ARMv7-M, base `0x120000`, build
`zh Dec 29 2023 - gf876b0f`) was analysed with Ghidra. Relevant findings:

* `me_config_monitor_req_handler` exists and configures a monitor channel —
  the firmware *does* understand monitor VIFs. It reads
  `vif_mgmt_env.monitor_vif` (offset `+0x10`, `0xff` = invalid) and returns
  status `0xff` when no channel context is set.
* `vif_t` has stride `0x528`; `vif->type` is at `+0x6a` (`0` = STA, `2` = AP).
* There is **no** `if (type == monitor) drop;` in the TX software path. The
  frame is built, the descriptor filled and queued; the loss happens below the
  MAC software, which is why the descriptor encoding (bit 31 vs bit 30) is what
  decides delivery.
* The driver's patch-table mechanism (`patch_tbl_d80`, uploaded via
  `rwnx_send_dbg_mem_write_req`) would allow modifying firmware behaviour
  without touching the blob — not needed for this fix, since the driver side
  suffices.

# NOTICE — purpose, licensing and legal scope

This document records why this repository exists, what it contains, and under
which terms it is published. It is not legal advice.

## 1. Purpose: interoperability

The work in this repository was done to make a device the author owns work as
documented in the IEEE 802.11 standard on the operating system of the author's
choice. Monitor mode and frame injection are standard, documented capabilities
of 802.11 and of the Linux wireless stack; they are not a vendor-specific
extension and not a circumvention technique.

Where the firmware of the device was examined, that examination served solely to
understand the interface between driver and firmware — i.e. interoperability in
the sense of § 69d UrhG (German copyright act; Art. 6 of the EU Software
Directive 2009/24/EC). It was **not** used to create a competing product and no
firmware code was copied.

## 2. What this repository does not contain

* **No firmware images or firmware extracts.** No `*.bin`, no unpacked firmware,
  no disassembly or decompilation listings of firmware. Findings are described
  as addresses, offsets and function names only.
* **No driver source code.** The patches are diffs against a GPL-2.0 licensed
  driver obtained from its upstream repository. They contain the minimal
  context lines required for `git apply`.
* **No circumvented protection measure.** The device firmware carries no
  signature verification or other technical protection measure that was
  bypassed (§ 69e UrhG). No firmware was modified, patched or re-flashed.

## 3. Licensing

| Part | License |
|------|---------|
| `patches/` — modifications to GPL-2.0 driver code | **GPL-2.0-only** (see `LICENSE`), inherited from the code they modify |
| `tools/` — standalone scripts | **MIT** (see `LICENSE-MIT`) |

Redistributing a modification of GPL-2.0 code requires the same license and the
availability of the corresponding source. The patch text is the corresponding
source for the modification; the unmodified driver is available from its
upstream repository.

## 4. No affiliation

This repository is not affiliated with, endorsed by or supported by AICSemi,
Radxa, UGREEN, TP-Link, or the maintainers of any upstream driver repository.
All trademarks belong to their respective owners. Product names are used
descriptively only.

## 5. Intended use

The tools are dual-use. Monitor mode and frame injection are used legitimately
for network analysis, driver and firmware development, interoperability testing,
teaching, and security research on networks one owns or is authorised to test.

Using these tools against networks, devices or radio traffic you are not
authorised to test may be unlawful — in Germany this includes § 202a StGB
(accessing data not intended for you), § 148 TKG (interception of
telecommunications) and, for personal data, the GDPR. The author publishes the
technical findings; responsibility for lawful use lies with the user.

## 6. No warranty

Provided "as is", without warranty of any kind. Applying kernel patches and
loading out-of-tree drivers can destabilise a system, and modifying driver
behaviour may violate the warranty terms of the hardware vendor. Use at your own
risk.

# LightScope OPNsense Plugin - Development Session Notes
**Date:** 2025-12-27
**Status:** ALL TESTS PASSING

## Objective
Compile and test the LightScope OPNsense plugin.

## Environment
- FreeBSD 14.3-RELEASE amd64
- OPNsense plugin tools at `/usr/plugins`
- Plugin source at `/usr/thelightscope/OPNsense` (also copied to `/usr/plugins/security/lightscope`)

---

## Issues Found and Fixed

### 1. Wrong Python pcap package name
**Problem:** Makefile had `py311-libpcap` which doesn't exist in FreeBSD repos.
**Fix:** Changed to `py311-pypcap` (the correct package providing `import pcap`).

```
# Before
PLUGIN_DEPENDS= python311 py311-dpkt py311-requests py311-psutil py311-libpcap

# After
PLUGIN_DEPENDS= python311 py311-dpkt py311-requests py311-psutil py311-pypcap
```

### 2. Wrong src directory structure
**Problem:** Config file was at `src/usr/local/etc/lightscope.conf.sample` which installed to `/usr/local/usr/local/etc/` (doubled path).
**Fix:** Moved to `src/etc/lightscope.conf.sample` which correctly installs to `/usr/local/etc/`.

```bash
# The fix applied:
mv src/usr/local/etc/lightscope.conf.sample src/etc/
rm -rf src/usr
```

### 3. Makefile include path
**Problem:** Absolute path `.include "/usr/plugins/Mk/plugins.mk"` only works when building from that location.
**Fix:** Changed to relative path `.include "../../Mk/plugins.mk"` for portability.

### 4. Missing python3 symlink
**Problem:** rc script uses `/usr/local/bin/python3` but only `python3.11` was installed.
**Fix:** Created symlink:
```bash
ln -s /usr/local/bin/python3.11 /usr/local/bin/python3
```

### 5. Error message in pflog_reader.py
**Problem:** Import error message referenced wrong package name `py311-libpcap`.
**Fix:** Updated to `py311-pypcap`.

### 6. CRITICAL: Wrong PFLOG_HDRLEN (pflog header length)
**Problem:** `pflog_reader.py` had `PFLOG_HDRLEN = 100` but FreeBSD 14.3 uses 72 bytes.
**Symptom:** Packets were captured but `parse_pflog_packet()` returned None for all packets because it was reading garbage after skipping 100 bytes instead of the actual IP header at offset 72.

**Root Cause Analysis:**
```
Packet hex dump showed:
  Offset 0:  45 02 01 00 65 6d 30 00 ...  <- pflog header (starts with interface "em0")
  Offset 72: 45 00 00 3c 00 00 40 00 ...  <- actual IP header (0x45 = IPv4, IHL=5)
```

The pflog header structure from `/usr/include/net/if_pflog.h`:
```c
struct pfloghdr {
    u_int8_t    length;           // 1
    sa_family_t af;               // 1
    u_int8_t    action;           // 1
    u_int8_t    reason;           // 1
    char        ifname[16];       // 16 (IFNAMSIZ)
    char        ruleset[16];      // 16 (PFLOG_RULESET_NAME_SIZE)
    u_int32_t   rulenr;           // 4
    u_int32_t   subrulenr;        // 4
    uid_t       uid;              // 4
    pid_t       pid;              // 4
    uid_t       rule_uid;         // 4
    pid_t       rule_pid;         // 4
    u_int8_t    dir;              // 1
    u_int8_t    pad[3];           // 3
    u_int32_t   ridentifier;      // 4
    u_int8_t    reserve;          // 1
    u_int8_t    pad2[3];          // 3
};                                // Total: 72 bytes
```

**Fix applied to `pflog_reader.py` line 33:**
```python
# Before
PFLOG_HDRLEN = 100  # FreeBSD pflog header length

# After
# Structure size: 1+1+1+1+16+16+4+4+4+4+4+4+1+3+4+1+3 = 72 bytes
PFLOG_HDRLEN = 72  # FreeBSD pflog header length
```

---

## Build Process

### Successful build commands:
```bash
# Plugin must be in /usr/plugins/<category>/<name>/ structure
cp -r /usr/thelightscope/OPNsense/* /usr/plugins/security/lightscope/

# Update Makefile include path
sed -i '' 's|/usr/plugins/Mk/plugins.mk|../../Mk/plugins.mk|' /usr/plugins/security/lightscope/Makefile

# Build
cd /usr/plugins/security/lightscope
rm -rf work
make package

# Package output location:
# /usr/plugins/security/lightscope/work/pkg/os-lightscope-1.0.pkg
```

### Install:
```bash
pkg install -y /usr/plugins/security/lightscope/work/pkg/os-lightscope-1.0.pkg
```

### Installed files:
```
/usr/local/etc/inc/plugins.inc.d/lightscope.inc
/usr/local/etc/lightscope.conf.sample
/usr/local/etc/rc.d/os-lightscope
/usr/local/opnsense/mvc/app/models/OPNsense/Lightscope/Lightscope.php
/usr/local/opnsense/mvc/app/models/OPNsense/Lightscope/Lightscope.xml
/usr/local/opnsense/scripts/lightscope/__init__.py
/usr/local/opnsense/scripts/lightscope/honeypot.py
/usr/local/opnsense/scripts/lightscope/lightscope_daemon.py
/usr/local/opnsense/scripts/lightscope/pflog_reader.py
/usr/local/opnsense/scripts/lightscope/reconfigure.sh
/usr/local/opnsense/scripts/lightscope/uploader.py
/usr/local/opnsense/service/conf/actions.d/actions_lightscope.conf
/usr/local/opnsense/service/templates/OPNsense/Lightscope/+TARGETS
/usr/local/opnsense/service/templates/OPNsense/Lightscope/lightscope.conf
/usr/local/opnsense/version/lightscope
```

---

## Final Test Results - ALL PASSING

### Prerequisites for testing:
```bash
# Load pf kernel modules
kldload pf
kldload pflog

# Create pflog interface (or let rc script do it)
ifconfig pflog0 create

# Enable pf with test rules
pfctl -e
echo 'block out log quick proto tcp from any to any port 9998' | pfctl -f -
```

### Component Test Results:

| Component | Status | Details |
|-----------|--------|---------|
| Package build | **PASS** | Builds correctly with fixed Makefile |
| Package install | **PASS** | Installs to correct locations |
| Service start | **PASS** | `service os-lightscope onestart` works |
| Honeypot listeners | **PASS** | Opens ports 8080, 2323, 8443, 3389, 5900 |
| Honeypot forwarding | **PASS** | Forwards connections to remote server with PROXY protocol |
| Honeypot uploader | **PASS** | Sends connection data to thelightscope.com |
| pf/pflog0 interface | **PASS** | Captures blocked packets |
| pypcap library | **PASS** | Captures pflog packets (datalink type 117) |
| **pflog_reader** | **PASS** | Correctly parses packets with PFLOG_HDRLEN=72 |
| **Packet upload** | **PASS** | Full pipeline working: capture → parse → upload |

### Successful test output:
```
pflog_reader: Capturing on pflog0
pflog_reader: sent 10 packets, queue=0
uploader: Sent 10 items
pflog_reader: sent 3 packets, queue=0
uploader: Sent 3 items
```

### Honeypot test:
```bash
# Connect to honeypot port
echo "TEST" | nc -w 2 127.0.0.1 8080

# Output showed:
# honeypot: Connection from 127.0.0.1:53727 to port 8080
# honeypot: Sending PROXY header: PROXY TCP4 127.0.0.1 <database_id> 53727 8080
# honeypot: Connection from 127.0.0.1 closed
# honeypot_uploader: Sent 1 items
```

---

## Files Modified in Source Repo

All changes applied to `/usr/thelightscope/OPNsense/`:

1. **Makefile** - Fixed dependency (`py311-pypcap`) and include path
2. **src/etc/lightscope.conf.sample** - Moved from `src/usr/local/etc/`
3. **src/opnsense/scripts/lightscope/pflog_reader.py**:
   - Line 21: Fixed error message to reference `py311-pypcap`
   - Line 33-34: Fixed `PFLOG_HDRLEN` from 100 to 72

---

## Quick Start for Next Session

```bash
# 1. Go to plugin directory
cd /usr/plugins/security/lightscope

# 2. If source changed, copy updates:
cp -r /usr/thelightscope/OPNsense/* /usr/plugins/security/lightscope/
sed -i '' 's|/usr/plugins/Mk/plugins.mk|../../Mk/plugins.mk|' Makefile

# 3. Rebuild:
pkg delete -y os-lightscope
rm -rf work
make package
pkg install -y work/pkg/os-lightscope-1.0.pkg

# 4. Setup test environment:
kldload pf pflog 2>/dev/null
ifconfig pflog0 create 2>/dev/null
pfctl -e
echo 'block out log quick proto tcp from any to any port 9998' | pfctl -f -

# 5. Start service:
service os-lightscope onestart

# 6. Generate test traffic:
nc -w 1 8.8.8.8 9998

# 7. Check logs - look for "pflog_reader: sent X packets" and "uploader: Sent X items"
```

---

## Database/Reports

The test instance registered with:
- Database ID: `20251227_fcpdfcllytxwkvrewfxwjpyzeoevdkleffkjgmbbrumohtq`
- Reports URL: https://thelightscope.com/light_table/20251227_fcpdfcllytxwkvrewfxwjpyzeoevdkleffkjgmbbrumohtq

---

## Debugging Commands Used

### Find correct pflog header offset:
```python
import pcap
sniffer = pcap.pcap(name="pflog0", snaplen=65535, promisc=False, immediate=True, timeout_ms=100)
for ts, buf in sniffer:
    # Look for 0x45 (IPv4 header start)
    for i, b in enumerate(buf):
        if b == 0x45 and buf[i+9] == 6:  # IPv4 + TCP
            print(f"IP header at offset {i}")
    break
```

### Verify pflog capture:
```bash
tcpdump -i pflog0 -c 5
```

### Check pf blocked packets:
```bash
pfctl -vsr
```

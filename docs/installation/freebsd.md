# LightScope on FreeBSD

Native FreeBSD package for LightScope. It runs the same `lightscope_core.py`
and `lightscope-runner.py` as the Linux packages; only the service plumbing
differs (rc.d and `daemon(8)` instead of systemd, `/dev/bpf` permissions
instead of Linux capabilities, `pkg` instead of dpkg/rpm).

Supported: FreeBSD 13.x and 14.x, amd64 and arm64. The OPNsense plugin in
`OPNsense/` is a different, pf-log-based variant and is not covered here.

## Requirements

Runtime (installed automatically as package dependencies):

| Package | Why |
|---|---|
| `python311` | interpreter (the build picks the ports default; see `PYVER` below) |
| `py311-dpkt` | packet parsing |
| `py311-psutil` | interface and process discovery |
| `py311-requests` | uploads |
| `py311-cryptography` | signature verification of core updates |
| `py311-packaging` | version comparison |
| `py311-pypcap` | packet capture (`import pcap`), replaces the vendored python-libpcap used on Linux |

Nothing is compiled at install time and pip is not used.

## Build the package

On a FreeBSD build host:

```sh
pkg install python311 py311-dpkt py311-psutil py311-requests \
            py311-cryptography py311-packaging py311-pypcap
./build-freebsd-pkg.sh
```

This writes `lightscope-<version>.pkg` to the repository root. Options:

```sh
LIGHTSCOPE_NO_HONEYPOT=1 ./build-freebsd-pkg.sh   # lightscope-nohoneypot-<version>.pkg
PYVER=312 ./build-freebsd-pkg.sh                   # depend on python312 / py312-* instead
./build-freebsd-pkg.sh --stage-only                # assemble build-freebsd/ only; runs on macOS/Linux
```

The version comes from `ls_version` in `lightscope/lightscope_core.py`, like
the other packages.

## Install

```sh
pkg install ./lightscope-<version>.pkg
```

`pkg install` on a local file pulls the Python dependencies from the
configured FreeBSD repository. The post-install step:

1. creates the `lightscope` user and group (shell `/usr/sbin/nologin`)
2. creates `/usr/local/lightscope/{bin,config,logs,updates}`, `/var/log/lightscope`, `/var/run/lightscope`
3. writes `/usr/local/lightscope/config.ini` with a generated database name (an existing file is kept)
4. sets `lightscope_enable=YES` in `/etc/rc.conf`
5. prints the dashboard URL

The service is then started by a pkg trigger
(`/usr/local/share/pkg/triggers/lightscope.ucl`), which pkg runs once the
transaction is committed. It cannot be started from the post-install script:
pkg runs install scripts under a process reaper and SIGKILLs every process they
leave behind, `daemon(8)` included. The trigger runs `service lightscope start`
if the service is enabled, so an upgrade comes back up by itself as well
(`+PRE_DEINSTALL` of the old version stops it first). Triggers need pkg 1.17 or
newer; FreeBSD 14 ships 1.20 and later.

To install without enabling the service:

```sh
env LIGHTSCOPE_NO_AUTOSTART=1 pkg install ./lightscope-<version>.pkg
```

## How it runs

```
rc.d/lightscope (su -m lightscope)  ->  daemon(8) -r  ->  python3.11 lightscope-runner.py  ->  lightscope_core (threads + worker processes)
```

- `daemon(8)` restarts the runner if it exits (10 s delay) and captures its
  output to `/var/log/lightscope/lightscope.log`. This replaces
  `Restart=always`. There is no systemd watchdog equivalent; the runner's own
  retry/backoff logic covers crashes of the core.
- The runner checks `https://thelightscope.com/latest/version`, downloads
  `lightscope_core.py` plus its signature, verifies it with the bundled public
  key and swaps it in. This is OS-independent and works unchanged.
- Everything runs as the unprivileged `lightscope` user. rc.subr performs the
  switch (`lightscope_user` is its reserved `${name}_user` variable), so
  `daemon` is deliberately started without `-u`.

### Packet capture permissions

FreeBSD has no `CAP_NET_RAW`. The rc script instead runs, on every start,
`chgrp lightscope /dev/bpf; chmod 0660 /dev/bpf`. devfs node permissions
persist until reboot, and the rc script runs at every boot, so this is enough
in practice. Two alternatives:

- persistent devfs ruleset: see `/usr/local/share/lightscope/devfs.rules.sample`,
  then `sysrc lightscope_bpf_chmod=NO`
- run as root: `sysrc lightscope_user=root lightscope_group=wheel`

Promiscuous mode is off, so no interface flags are changed.

### Honeypot ports and pf

Honeypot ports are chosen at or above 1024, below FreeBSD's
`net.inet.ip.portrange.reservedhigh` floor, so no root is needed. If `pf` (or
`ipfw`) blocks inbound traffic by default, honeypots will not receive
connections. Allow the port range you are comfortable with, for example:

```
pass in quick proto tcp from any to (egress) port 1024:65535 user lightscope
```

### Interfaces

All up interfaces with a non-loopback address are monitored, except the
pseudo and tunnel interfaces listed in `is_virtual_interface` in the core
(`tap`, `tun`, `wg`, `epair`, `pflog`, `pfsync`, `enc`, `gif`, `gre`, `ipfw`,
plus the container names used on Linux). Bridges, lagg and vlan interfaces that
carry an address are monitored like physical NICs. An interface whose link type
is not Ethernet is skipped with a line in the log. To pin interfaces:

```ini
interface = em0,igb1
```

## Operate

```sh
service lightscope status
service lightscope stop
service lightscope start
tail -f /var/log/lightscope/lightscope.log
tail -f /usr/local/lightscope/logs/lightscope-runner.log
sysrc lightscope_enable=NO            # keep installed, do not start at boot
```

rc.conf variables (defaults in parentheses): `lightscope_enable` (NO),
`lightscope_user` (lightscope), `lightscope_group` (lightscope),
`lightscope_home` (/usr/local/lightscope), `lightscope_python`
(/usr/local/bin/python3.11), `lightscope_logfile`
(/var/log/lightscope/lightscope.log), `lightscope_bpf_chmod` (YES).

Log rotation is configured in `/usr/local/etc/newsyslog.conf.d/lightscope.conf`.

Database name and dashboard URL:

```sh
grep ^database /usr/local/lightscope/config.ini
```

## Upgrade and remove

```sh
pkg install ./lightscope-<newer>.pkg   # config.ini and database name are kept
pkg delete lightscope                  # keeps config, logs, user and rc.conf entry
env LIGHTSCOPE_PURGE=1 pkg delete lightscope   # removes everything
```

Because the runner replaces `bin/lightscope_core.py` in place when it
self-updates, `pkg check -s lightscope` will report a checksum mismatch for
that file afterwards. That is expected and the same on Linux.

## Jails

Capturing inside a jail needs `allow.raw_sockets` on the jail and the BPF
device exposed through the jail's devfs ruleset (`add path 'bpf*' unhide mode
0660 group lightscope`). Monitoring from the host covers jail traffic on
`bridge`/`epair` members without this.

## Troubleshooting

- **Not running right after `pkg install`**: the trigger did not fire. Check
  `pkg -v` is 1.17 or newer and that the install output contains
  `Running trigger: lightscope.ucl`; otherwise `service lightscope start`.
- **"Permission denied" opening `/dev/bpf`** in the log: the chmod did not
  run (daemon started by hand instead of through the rc script?) or a devfs
  ruleset reset it. Run `service lightscope restart`, or install the devfs
  ruleset.
- **`python3.11: not found`**: the package was built for a different Python
  flavor than the one installed. Either install that flavor or
  `sysrc lightscope_python=/usr/local/bin/python3.12`.
- **"not capturing on X: datalink N is not Ethernet"**: expected for tunnels
  and point-to-point links; the interface is skipped.
- **No uploads**: check `curl -sI https://thelightscope.com/ipinfo` from the
  host and the pf rules for outbound HTTPS from the `lightscope` user.
- **Which pcap backend is in use**: `python3.11 -c "import pcap; print(pcap.__version__)"`.
  The core prefers the vendored `pylibpcap` if it is importable and otherwise
  uses `pcap` (pypcap).

# FreeBSD package sources

Template for the native FreeBSD package (`lightscope-<version>.pkg`), the
counterpart of `debian_package/` and `rpm-build/`. It ships the same
`lightscope_core.py` and `lightscope-runner.py` as the Linux packages;
only the service plumbing is FreeBSD-specific.

| Path | Purpose |
|---|---|
| `usr/local/etc/rc.d/lightscope` | rc.d script; runs the runner under `daemon(8)` as the `lightscope` user |
| `usr/local/etc/newsyslog.conf.d/lightscope.conf` | log rotation |
| `usr/local/share/lightscope/config.ini.sample` | config template |
| `usr/local/share/lightscope/devfs.rules.sample` | optional persistent `/dev/bpf` permissions |
| `+PRE_INSTALL`, `+POST_INSTALL`, `+PRE_DEINSTALL`, `+POST_DEINSTALL` | pkg scripts |
| `+DESC` | package description |

`@PYTHON@`, `@PYVER@`, `@VERSION@`, `@HONEYPOT_DEFAULT@` and `@PREFIX@` are
filled in by `../build-freebsd-pkg.sh`. See `../docs/installation/freebsd.md`.

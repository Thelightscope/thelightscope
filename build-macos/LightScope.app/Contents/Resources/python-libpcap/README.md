# python-libpcap

[![pypi.python.org](https://img.shields.io/pypi/v/python-libpcap.svg)](https://pypi.python.org/pypi/python-libpcap)
[![pypi.python.org](https://img.shields.io/pypi/pyversions/python-libpcap.svg)](https://pypi.python.org/pypi/python-libpcap)
[![travis-ci.org](https://api.travis-ci.com/caizhengxin/python-libpcap.svg?branch=master)](https://travis-ci.org/JanKinCai/python-libpcap)
[![pypi.python.org](https://img.shields.io/pypi/dm/python-libpcap.svg)](https://pypi.python.org/pypi/python-libpcap)
[![readthedocs.org](https://readthedocs.org/projects/python-libpcap/badge/?version=latest)](https://python-libpcap.readthedocs.io/en/latest/?badge=latest)
[![img.shields.io](https://img.shields.io/github/languages/code-size/caizhengxin/python-libpcap)](https://pypi.python.org/pypi/python-libpcap)
[![img.shields.io](https://img.shields.io/pypi/l/python-libpcap)](https://github.com/caizhengxin/python-libpcap/blob/master/LICENSE)

This is the Cython encapsulated of the C libpcap library for python.

- Github repo: https://github.com/caizhengxin/python-libpcap
- Documentation: https://python-libpcap.readthedocs.io
- Free software: BSD lincense

## Features

- [x] Read pcap file
- [x] Write pcap file
- [x] Merge pcap file
- [x] Multi-file quick merge
- [x] Get first iface
- [x] Get iface list
- [x] Send raw packet
- [x] Capture data

## Install

To install python-libpcap, run this command in your terminal:

```bash
$ sudo apt-get install libpcap-dev
$ pip3 install python-libpcap
```

Or

```bash
$ git clone https://github.com/caizhengxin/python-libpcap.git
$ cd python-libpcap
$ pip3 install -e .
```

## Usage

### Command

```bash
# Multi-file quick merge
$ libpcap-merge -i test.pcap -o pcap.pcap port 502
$ libpcap-merge -i pcap/ -o pcap.pcap port 502

# Capture data packet
$ sudo libpcap-capture -i enp0s3 -v -p port 22
$ sudo libpcap-capture -i enp0s3 -o pcap.pcap port 22

# Write packet
$ libpcap-write --output pcap.pcap ac64175ffa41000ec6c9157e08004500004b8a1e400080060000c0a80002c0a80001c794006618e119b56ef0831d5018faf081910000030000231ee00000001d00c1020600c20f53494d415449432d524f4f542d4553c0010a

# Read packet
$ libpcap-read -i test.pcap -v -p port 502
```

### Read pcap file

```python
from pylibpcap.pcap import rpcap


for len, t, pkt in rpcap("tests/dns.pcap"):
    print("Time:", t)
    print("Buf length:", len)
    print("Buf:", pkt)
```

### Write pcap file

```python
from pylibpcap import wpcap


buf = b'\x00\xc0\x9f2A\x8c\x00\xe0\x18\xb1\x0c\xad\x08\x00E\x00\x008' \
        b'\x00\x00@\x00@\x11eG\xc0\xa8\xaa\x08\xc0\xa8\xaa\x14\x80\x1b' \
        b'\x005\x00$\x85\xed\x102\x01\x00\x00\x01\x00\x00\x00\x00\x00' \
        b'\x00\x06google\x03com\x00\x00\x10\x00\x01'


wpcap(buf, "pcap.pcap")
wpcap([buf, buf], "pcap.pcap")
```

Or

```python
from pylibpcap import OpenPcap


with OpenPcap("pcap.pcap", "a") as f:
    f.write(buf)
```

### Merge pcap file

```python
from pylibpcap.pcap import mpcap


mpcap("demo.pcap", "demo2.pcap")
mpcap("pcap/", "output.pcap", "port 502")
```

### Get first iface

```python
from pylibpcap import get_first_iface

print(get_first_iface())
```

### Get iface list

```python
from pylibpcap import get_iface_list

print(get_iface_list())
```

### Send raw packet

```python
from pylibpcap import send_packet


buf = b'\x00\xc0\x9f2A\x8c\x00\xe0\x18\xb1\x0c\xad\x08\x00E\x00\x008' \
        b'\x00\x00@\x00@\x11eG\xc0\xa8\xaa\x08\xc0\xa8\xaa\x14\x80\x1b' \
        b'\x005\x00$\x85\xed\x102\x01\x00\x00\x01\x00\x00\x00\x00\x00' \
        b'\x00\x06google\x03com\x00\x00\x10\x00\x01'

send_packet("enp2s0", buf)
```

### Capture packet

```python
from pylibpcap.pcap import sniff


for plen, t, buf in sniff("enp2s0", filters="port 53", count=-1, promisc=1, out_file="pcap.pcap"):
    print("[+]: Payload len=", plen)
    print("[+]: Time", t)
    print("[+]: Payload", buf)
```

Or

```python
from pylibpcap.base import Sniff

sniffobj = None

try:
    sniffobj = Sniff("enp2s0", filters="port 53", count=-1, promisc=1, out_file="pcap.pcap")

    for plen, t, buf in sniffobj.capture():
        print("[+]: Payload len=", plen)
        print("[+]: Time", t)
        print("[+]: Payload", buf)
except KeyboardInterrupt:
    pass
except LibpcapError as e:
    print(e)

if sniffobj is not None:
    stats = sniffobj.stats()
    print(stats.capture_cnt, " packets captured")
    print(stats.ps_recv, " packets received by filter")
    print(stats.ps_drop, "  packets dropped by kernel")
    print(stats.ps_ifdrop, "  packets dropped by iface")
```

## Credits

This package was created with [Cookiecutter](https://github.com/cookiecutter/cookiecutter) and the [caizhengxin/cookiecutter-package](https://github.com/caizhengxin/cookiecutter-package) project template.
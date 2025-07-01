# -*- coding: utf-8 -*-
# @Author: JanKinCai
# @Date:   2019-05-10 11:46:33
# @Last Modified by:   jankincai12@gmail.com
# @Last Modified time: 2019-09-12 13:28:50
from pylibpcap.base import Sniff, LibPcap
from pylibpcap.open import OpenPcap


def rpcap(path, filters=""):
    """
    Read pcap file.

    :param path: 文件路径.
    :param filters: BPF Filters

    return tuple: (Buf length，Capture time，Buf)
    """

    return LibPcap(path, filters=filters).read()


def wpcap(v, path):
    """
    Write pcap file.

    :param v: Buf/Buf(list)
    :param out_file: Output file
    """

    with OpenPcap(path, "a") as f:
        f.write(v)


def mpcap(path, out_file, filters=""):
    """
    Merge many pcap file.

    :param path: Input dir/file
    :param out_file: Output file
    :param filters: BPF Filters, default ``""``
    """

    with OpenPcap(out_file, "a", filters=filters) as f:
        f.write_path(path)


def sniff(*args, **kwargs):
    """
    Capture packet

    :param iface: Iface
    :param count: Capture packet num, default ``-1``
    :param promisc: Promiscuous mode, default ``0``
    :param snaplen: Cut packet lenght, default ``65535``
    :param filters: BPF filter rules, default ``""``
    :param out_file: Output pcap file, default ``""``
    """

    return Sniff(*args, **kwargs).capture()

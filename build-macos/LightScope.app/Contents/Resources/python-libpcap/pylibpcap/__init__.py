# -*- coding: utf-8 -*-
# @Author: JanKinCai
# @Date:   2019-11-09 14:57:10
# @Last Modified by:   JanKinCai
# @Last Modified time: 2020-04-04 11:59:02

__version__ = "0.5.2"
__author__ = "JanKinCai"
__all__ = [
    "rpcap",
    "wpcap",
    "mpcap",
    "sniff",
    "get_first_iface",
    "get_iface_list",
    "send_packet"
]


try:
    from pylibpcap.pcap import rpcap, wpcap, mpcap, sniff
    from pylibpcap.base import get_first_iface, get_iface_list, send_packet
    from pylibpcap.open import OpenPcap
except ImportError:
    pass

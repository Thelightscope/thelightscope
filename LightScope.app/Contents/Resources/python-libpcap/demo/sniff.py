# -*- coding: utf-8 -*-
# @Author: JanKinCai
# @Date:   2019-09-04 14:35:32
# @Last Modified by:   JanKinCai
# @Last Modified time: 2019-11-12 09:18:03
from pylibpcap.pcap import sniff


for plen, t, buf in sniff("enp2s0", count=3, promisc=1, filters="port 53", out_file="pcap.pcap"):
    print("[+]: Payload len=", plen)
    print("[+]: Time", t)
    print("[+]: Payload", buf)

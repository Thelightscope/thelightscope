# -*- coding: utf-8 -*-
# @Author: JanKinCai
# @Date:   2019-09-04 14:31:53
# @Last Modified by:   JanKinCai
# @Last Modified time: 2019-11-12 09:17:44
from pylibpcap.pcap import mpcap


mpcap("demo.pcap", "demo2.pcap")

mpcap("pcap/", "output.pcap", "port 502")

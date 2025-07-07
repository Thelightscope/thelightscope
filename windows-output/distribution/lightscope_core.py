# Standard library imports
import argparse
import configparser
import datetime
import hashlib
import ipaddress
import json
import logging
import multiprocessing
import os
import queue
import random
import re
import socket
import string
import sys
import threading
import time
from collections import defaultdict, deque, OrderedDict
from sys import platform
from collections import Counter
import socket, select, time
# Third-party imports
import dpkt
import platform as platforminfo
import psutil
import requests
import copy

ls_version = "1.0.2"

print(f"ls_version: {ls_version}")

benchmark_times=[]

# Global watchdog notification function (set by runner)
systemd_watchdog_notify = None

verbose=1
if verbose == 0:
    logging.root.setLevel(logging.NOTSET)
    logging.basicConfig(level=logging.NOTSET)
elif verbose == 1:
    logging.root.setLevel(logging.WARNING)
    logging.basicConfig(level=logging.WARNING)
elif verbose == 2:
    logging.root.setLevel(logging.ERROR)
    logging.basicConfig(level=logging.ERROR)





# Global memory management constant
MAX_SIZE = 100000  # Maximum size for all deques, queues, and collections

# packet_info.py
import dpkt
import datetime
import socket
import struct
from collections import namedtuple


def parse_ethernet(packet_bytes, datalink):
    """
    Parse the packet bytes using the appropriate dpkt class based on the datalink type.
    """
    # DLT_EN10MB = 1: Standard Ethernet.
    if datalink == dpkt.pcap.DLT_EN10MB:
        try:
            eth = dpkt.ethernet.Ethernet(packet_bytes)
        except Exception as e:
            raise Exception(f"Ethernet parsing failed: {e}")
    # DLT_LINUX_SLL = 113: Linux cooked capture.
    elif datalink == 113:
        try:
            # dpkt.sll.SLL parses Linux cooked capture packets.
            # Note: SLL packets don't automatically convert to an Ethernet frame,
            # so we might need to adjust how we extract the IP packet.
            sll = dpkt.sll.SLL(packet_bytes)
            # sll.data should contain the encapsulated packet. In many cases it is already an IP packet.
            if not isinstance(sll.data, dpkt.ip.IP):
                raise Exception("Not an IP packet inside SLL")
            eth = sll  # We use the SLL object as our 'eth' equivalent.
        except Exception as e:
            raise Exception(f"Linux cooked capture parsing failed: {e}")
    else:
        raise Exception(f"Unsupported datalink type: {datalink}")
    return eth

#begin packetin
# Define the namedtuple for packet information.
PacketInfo = namedtuple("PacketInfo", [
    "packet_num", "proto", "packet_time",
    "ip_version", "ip_ihl", "ip_tos", "ip_len", "ip_id", "ip_flags", "ip_frag",
    "ip_ttl", "ip_proto", "ip_chksum", "ip_src", "ip_dst", "ip_options",
    "tcp_sport", "tcp_dport", "tcp_seq", "tcp_ack", "tcp_dataofs",
    "tcp_reserved", "tcp_flags", "tcp_window", "tcp_chksum", "tcp_urgptr", "tcp_options"
])


def tcp_flags_to_str(flags_value):
    """Convert dpkt TCP flags value to a comma-separated string."""
    flag_names = []
    if flags_value & dpkt.tcp.TH_FIN:
        flag_names.append("FIN")
    if flags_value & dpkt.tcp.TH_SYN:
        flag_names.append("SYN")
    if flags_value & dpkt.tcp.TH_RST:
        flag_names.append("RST")
    if flags_value & dpkt.tcp.TH_PUSH:
        flag_names.append("PSH")
    if flags_value & dpkt.tcp.TH_ACK:
        flag_names.append("ACK")
    if flags_value & dpkt.tcp.TH_URG:
        flag_names.append("URG")
    return ",".join(flag_names) if flag_names else ""


import struct, socket, datetime
import dpkt

ETH_HDR_LEN = 14
ETH_P_IP    = 0x0800
ETH_P_IPV6  = 0x86DD
ETH_P_8021Q = 0x8100

def parse_packet_info_fast(buf: bytes, pkt_no: int) -> PacketInfo:
    # --- L2 ----------------------------------------------------------------
    eth_type = struct.unpack('!H', buf[12:14])[0]
    off = ETH_HDR_LEN
    if eth_type == ETH_P_8021Q:          # optional VLAN tag
        eth_type = struct.unpack('!H', buf[16:18])[0]
        off += 4

    # --- IPv4 path ---------------------------------------------------------
    if eth_type == ETH_P_IP:
        ip4 = dpkt.ip.IP(buf[off:])
        if ip4.p != dpkt.ip.IP_PROTO_TCP:
            raise Exception(f"Not TCP (IPv4 proto={ip4.p})")
        ip_hdr_len = ip4.hl * 4
        tcp = dpkt.tcp.TCP(buf[off + ip_hdr_len:])
        src = socket.inet_ntoa(ip4.src)
        dst = socket.inet_ntoa(ip4.dst)
        ip_opts = ip4.opts.hex() if ip4.opts else ""

        # Build flags string from individual flag properties
        flags = []
        if ip4.df:
            flags.append("DF")
        if ip4.mf:
            flags.append("MF")
        ip_flags_str = ",".join(flags) if flags else ""

        return PacketInfo(
            packet_num   = pkt_no,
            proto        = "TCP",
            packet_time  = datetime.datetime.now().timestamp(),

            ip_version   = ip4.v,
            ip_ihl       = ip4.hl,
            ip_tos       = ip4.tos,
            ip_len       = ip4.len,
            ip_id        = ip4.id,
            ip_flags     = ip_flags_str,
            ip_frag      = ip4.offset >> 3,  # offset is in bytes, convert to 8-byte units
            ip_ttl       = ip4.ttl,
            ip_proto     = ip4.p,
            ip_chksum    = ip4.sum,
            ip_src       = src,
            ip_dst       = dst,
            ip_options   = ip_opts,

            tcp_sport    = tcp.sport,
            tcp_dport    = tcp.dport,
            tcp_seq      = tcp.seq,
            tcp_ack      = tcp.ack,
            tcp_dataofs  = tcp.off * 4,
            tcp_reserved = 0,
            tcp_flags    = tcp_flags_to_str(tcp.flags),
            tcp_window   = tcp.win,
            tcp_chksum   = tcp.sum,
            tcp_urgptr   = tcp.urp,
            tcp_options  = tcp.opts
        )

   # --- IPv6 path ---------------------------------------------------------
    elif eth_type == ETH_P_IPV6:
        # pull out the fixed 40-byte IPv6 header
        hdr = buf[off:off+40]

        # next header is at hdr[6]
        nh = hdr[6]
        # drop anything that's not TCP
        if nh != dpkt.ip.IP_PROTO_TCP:
            raise Exception(f"Not TCP (IPv6 next header={nh})")

        # now you know it's TCP, so parse the 40-byte header + TCP
        tcphdr_start = off + 40
        ip6 = dpkt.ip6.IP6(hdr + buf[tcphdr_start:])  # or just use hdr+buf and slice as you like
        tcp = dpkt.tcp.TCP(buf[tcphdr_start:])

        src = socket.inet_ntop(socket.AF_INET6, hdr[8:24])
        dst = socket.inet_ntop(socket.AF_INET6, hdr[24:40])

        # pack our IPv6 header summary into ip_options
        ver_tc_fl = struct.unpack('!I', hdr[0:4])[0]
        tc    = (ver_tc_fl >> 20) & 0xFF
        flow  = ver_tc_fl & 0xFFFFF
        plen  = struct.unpack('!H', hdr[4:6])[0]
        hlim  = hdr[7]
        ip_opts = f"tc={tc},flow={flow},plen={plen},nh={nh},hlim={hlim}"

        return PacketInfo(
            packet_num   = pkt_no,
            proto        = "TCP",
            packet_time  = datetime.datetime.now().timestamp(),

            ip_version   = 6,
            ip_ihl       = None,
            ip_tos       = None,
            ip_len       = plen,
            ip_id        = None,
            ip_flags     = "",
            ip_frag      = 0,
            ip_ttl       = hlim,
            ip_proto     = nh,
            ip_chksum    = None,
            ip_src       = src,
            ip_dst       = dst,
            ip_options   = ip_opts,

            tcp_sport    = tcp.sport,
            tcp_dport    = tcp.dport,
            tcp_seq      = tcp.seq,
            tcp_ack      = tcp.ack,
            tcp_dataofs  = tcp.off * 4,
            tcp_reserved = 0,
            tcp_flags    = tcp_flags_to_str(tcp.flags),
            tcp_window   = tcp.win,
            tcp_chksum   = tcp.sum,
            tcp_urgptr   = tcp.urp,
            tcp_options  = tcp.opts
        )

    else:
        raise Exception(f"Unsupported ethertype 0x{eth_type:04x}")



# Expanded mapping from IANA Kind values  names
TCP_OPT_NAMES = {
    0:  "EOL",
    1:  "NOP",
    2:  "MSS",
    3:  "WSCALE",
    4:  "SACK_PERMITTED",
    5:  "SACK",
    6:  "ECHO",
    7:  "ECHO_REPLY",
    8:  "TIMESTAMP",
    9:  "PARTIAL_ORDER",
    10: "PARTIAL_ORDER_SERVICE_PROFILE",
    11: "CC",
    12: "CC.NEW",
    13: "CC.ECHO",
    14: "ALT_CHECKSUM_REQUEST",
    15: "ALT_CHECKSUM_DATA",
    16: "TCP_MD5_SIG",
    17: "TCP_FASTOPEN",
    18: "TCP_FASTOPEN_COOKIE",
    19: "TCP_AUTHENTICATION",  # RFC 5925
    # and any future ones will be rendered as OPT<kind>
}

def human_readable_tcp_opts(raw_opts: bytes) -> list[str]:
    """
    Turn the raw TCP-options bytes into a list of humanreadable strings.
    Unknown kinds become "OPT<kind>".
    """
    out = []
    if not raw_opts:
        return out

    for kind, data in dpkt.tcp.parse_opts(raw_opts):
        name = TCP_OPT_NAMES.get(kind, f"OPT{kind}")

        # Endoflist
        if kind == 0:
            out.append(name)
            break

        # Noop
        if kind == 1:
            out.append(name)
            continue

        # All the singlevalue options:
        if kind == 2 and len(data) == 2:  # MSS
            (mss,) = struct.unpack("!H", data)
            out.append(f"{name}={mss}")
        elif kind == 3 and len(data) == 1:  # Window Scale
            w = data[0]
            out.append(f"{name}={w}")
        elif kind == 4:  # SACK Permitted
            out.append(name)
        elif kind == 5:  # SACK blocks
            sacks = []
            for i in range(0, len(data), 8):
                start, end = struct.unpack("!II", data[i : i + 8])
                sacks.append(f"{start}-{end}")
            out.append(f"{name}={'|'.join(sacks)}")
        elif kind in (6, 7):  # Echo / Echo Reply (each 4bytes)
            if len(data) == 4:
                (val,) = struct.unpack("!I", data)
                out.append(f"{name}={val}")
            else:
                out.append(name)
        elif kind == 8 and len(data) == 8:  # Timestamp
            tsval, tsecr = struct.unpack("!II", data)
            out.append(f"{name} val={tsval}, echo={tsecr}")
        elif kind in (9, 10):  # Partial Order (no payload)
            out.append(name)
        elif kind in (11, 12, 13):  # CC, CC.NEW, CC.ECHO (each 4bytes)
            if len(data) == 4:
                (ccv,) = struct.unpack("!I", data)
                out.append(f"{name}={ccv}")
            else:
                out.append(name)
        elif kind in (14, 15):  # Alternate checksum
            out.append(f"{name} len={len(data)}")
        elif kind == 16 and len(data) == 16:  # MD5 Signature
            out.append(f"{name}={data.hex()}")
        elif kind == 17:  # Fast Open
            out.append(f"{name} cookie_len={len(data)}")
        elif kind == 18:  # Fast Open Cookie (server)
            out.append(f"{name} cookie_len={len(data)}")
        elif kind == 19:  # TCP Authentication (timestamp + signature)
            out.append(f"{name} len={len(data)}")
        else:
            # any future or unhandled option
            out.append(f"{name} len={len(data)}")

    return out

def parse_packet_info(packet_bytes, packet_number, datalink=dpkt.pcap.DLT_EN10MB):
    """
    Parse raw packet bytes using dpkt and return a PacketInfo namedtuple.
    
    Raises:
        Exception: if the packet is not Ethernet/IP/TCP.
    """
    # Use current timestamp (you could use a timestamp from a pcap if available)
    packet_time = datetime.datetime.now().timestamp()
    
    # Parse the Ethernet frame.
    try:
        eth = dpkt.ethernet.Ethernet(packet_bytes)
    except Exception as e:
        raise Exception(f"Could not parse Ethernet frame: {e}")
    
    # Depending on the datalink type, the IP packet may be in different attributes.
    # For Ethernet, the payload is in eth.data.
    if not isinstance(eth.data, dpkt.ip.IP):
        raise Exception("Not an IP packet")
    ip = eth.data

    # Ensure the IP payload is a TCP segment.
    if not isinstance(ip.data, dpkt.tcp.TCP):
        raise Exception("Not a TCP packet")
    tcp = ip.data
    tcp = ip.data

    # Extract IP header fields.
    ip_version = ip.v
    ip_ihl = ip.hl
    ip_tos = ip.tos
    ip_len = ip.len
    ip_id = ip.id
    # ip.off encodes the flags in the upper 3 bits and fragment offset in the lower 13 bits.
    # Use modern dpkt properties instead of deprecated ip.off
    flags = []
    if ip.df:
        flags.append("DF")
    if ip.mf:
        flags.append("MF")
    ip_flags = ",".join(flags) if flags else ""
    ip_frag = ip.offset >> 3  # offset is in bytes, convert to 8-byte units
    ip_ttl = ip.ttl
    ip_proto = ip.p if hasattr(ip, 'p') else ip.proto
    ip_chksum = ip.sum if hasattr(ip, 'sum') else ip.chksum
    ip_src = socket.inet_ntoa(ip.src)
    ip_dst = socket.inet_ntoa(ip.dst)
    ip_options = ip.opts.hex() if hasattr(ip, 'opts') and ip.opts else ""

    # Extract TCP header fields.
    tcp_sport = tcp.sport
    tcp_dport = tcp.dport
    tcp_seq = tcp.seq
    tcp_ack = tcp.ack
    tcp_dataofs = tcp.off * 4  # dpkt.tcp.TCP.off is in 32-bit words.
    tcp_reserved = 0  # dpkt does not provide reserved bits directly.
    tcp_flags = tcp_flags_to_str(tcp.flags)
    tcp_window = tcp.win
    tcp_chksum = tcp.sum if hasattr(tcp, 'sum') else tcp.chksum
    tcp_urgptr = tcp.urp
    tcp_options = tcp.opts

    # Return the PacketInfo named tuple.
    return PacketInfo(
        packet_num=packet_number,
        proto="TCP",
        packet_time=packet_time,
        ip_version=ip_version,
        ip_ihl=ip_ihl,
        ip_tos=ip_tos,
        ip_len=ip_len,
        ip_id=ip_id,
        ip_flags=ip_flags,
        ip_frag=ip_frag,
        ip_ttl=ip_ttl,
        ip_proto=ip_proto,
        ip_chksum=ip_chksum,
        ip_src=ip_src,
        ip_dst=ip_dst,
        ip_options=ip_options,
        tcp_sport=tcp_sport,
        tcp_dport=tcp_dport,
        tcp_seq=tcp_seq,
        tcp_ack=tcp_ack,
        tcp_dataofs=tcp_dataofs,
        tcp_reserved=tcp_reserved,
        tcp_flags=tcp_flags,
        tcp_window=tcp_window,
        tcp_chksum=tcp_chksum,
        tcp_urgptr=tcp_urgptr,
        tcp_options=tcp_options
    )

        
class Ports:
    def __init__(self,
            producer_upload_conn,
            internal_ips,
            internal_ip_equals_external,
            interface,
            external_network_information,
            config_settings,
            system_info,
            top_unwanted_ports_producer,
            shared_open_honeypots
            ):
        

        self.producer_upload_conn=producer_upload_conn
        self.unprocessed_packed_buffer=[]
        self.currently_open_ip_list = {}
        self.previously_open_ip_list_A = {}
        self.previously_open_ip_list_B = {}
        self.previously_open_ip_list_ptr=self.previously_open_ip_list_A
        self.previously_open_ip_list_ptr["time_started"]=0

        self.packets_to_watch = OrderedDict()      # key -> list[Packet]

        self.system_info=system_info
        self.ARP_requests = collections.deque(maxlen=MAX_SIZE)
        self.ARP_same_timestamp = collections.deque(maxlen=MAX_SIZE)
        self.timer=0
        self.SYN_reply_timeout=10
        self.ARP_reply_timeout=0.5
        self.Recently_closed_port_timeout=600
        
        
        self.num_total_tcp_packets=0
        self.num_unwanted_tcp_packets=0
        

        self.check_if_ip_changed_packet_interval=2000
        self.external_ip= external_network_information["queried_ip"]
        self.internal_ips=internal_ips
        self.asn=0
        self.external_network_information=external_network_information
        #self.internal_network_information=internal_network_information
        self.max_unwanted_buffer_size=5000
        self.interface=interface

        self.database=config_settings['database']
        self.randomization_key=config_settings['randomization_key']
        self.verbose=verbose
        self.os_info=""
        self.packet_number=0

        self.unwanted_packet_count=0

        #self.internal_ip_randomized = [ self.randomize_ip(ip) for ip in internal_ips ]
        
        self.internal_ip_randomized_v4 = [ self.randomize_ip(ip) for ip in self.internal_ips['ipv4'] ]
        self.internal_ip_randomized_v6 = [ self.randomize_ip(ip) for ip in self.internal_ips['ipv6'] ]

        self.external_ip_randomized=self.randomize_ip(self.external_ip)
        #TODO check for ipv6 and randomize that

        self.interface_human_readable=self.interface

        self.top_unwanted_ports_producer=top_unwanted_ports_producer
        
        # Store reference to shared honeypot ports (thread-safe, no locking needed for reads)
        self.shared_open_honeypots = shared_open_honeypots
        self.local_copy_open_honeypots = set()  # Local copy of honeypot ports
        
        # Track port activity for honeypot rotation
        self.port_counts = Counter()





        if platforminfo.system() == "Windows":
            import re, wmi

            # initialize WMI once
            _wmi = wmi.WMI()
            m = re.search(r'\{([0-9A-Fa-f-]+)\}', self.interface)
            if m:
                guid = m.group(1).lower()
                # search the *adapter* class (not the Configuration class!)
                for nic in _wmi.Win32_NetworkAdapter():
                    if not nic.GUID:
                        continue
                    if nic.GUID.strip('{}').lower() == guid:
                        friendly = (
                            nic.NetConnectionID
                            or nic.Name
                            or nic.Description
                            or self.interface
                        )
                        # *** assignment, not comparison! ***
                        self.interface_human_readable = friendly +self.interface_human_readable
                        break

        print(f"Monitoring {internal_ips} on {self.interface_human_readable}")
        


    def log_local_terminal_and_GUI_WARN(self,event_string,level):
        pass
        print(event_string, flush=True)



    
    def open_port(self,local_ip,local_port,remote_ip,pkt_info):
        #print(f"open_port:local_ip {local_ip} local_port {local_port} remote_ip {remote_ip}",flush=True)
        if local_port not in self.currently_open_ip_list:
            self.currently_open_ip_list[local_port] = set()
        # add the remote IP
        self.currently_open_ip_list[local_port].add(remote_ip)
        #print(f"open_port: {local_port} {self.currently_open_ip_list.keys()}",flush=True)

            
    def close_port(self,local_ip,local_port,remote_ip,historical_unacked_syn):
        remotes = self.currently_open_ip_list.get(local_port)
        if not remotes:
            return

        remotes.discard(remote_ip)  # discard() is safe if not present
        if not remotes:
            # no more connections  delete key, preserving order of the rest
            del self.currently_open_ip_list[local_port]

        # still record for previously open logic
        self.add_port_to_previously_open(local_ip, local_port, remote_ip, historical_unacked_syn)


    def num_open_connections(self, local_port) -> int:
        """
        Number of distinct remote IPs currently connected.
        """
        return len(self.currently_open_ip_list.get(local_port, ()))    

    def num_previously_open_connections(self, local_port) -> int:
        """
        Return the number of distinct remote IPs that were previously
        open on local_port, across both A and B windows.
        """
        a = self.previously_open_ip_list_A.get(local_port, set())
        b = self.previously_open_ip_list_B.get(local_port, set())
        # union so we dont doublecount an IP seen in both windows
        return len(a | b)

    def add_port_to_previously_open(self, local_ip, local_port, remote_ip, pkt_info):
        
        #print(f"add_port_to_previously_open:local_port {local_port} remote_ip {remote_ip}",flush=True)
        # rollingwindow switch (unchanged)
        if pkt_info.packet_time - self.previously_open_ip_list_ptr["time_started"] > \
           self.Recently_closed_port_timeout:

            tmp = (
                self.previously_open_ip_list_B
                if self.previously_open_ip_list_ptr is self.previously_open_ip_list_A
                else self.previously_open_ip_list_A
            )
            tmp.clear()
            tmp["time_started"] = pkt_info.packet_time
            self.previously_open_ip_list_ptr = tmp

        # now record the remote_ip in a set for that port
        wins = self.previously_open_ip_list_ptr
        if local_port not in wins:
            wins[local_port] = set()
        wins[local_port].add(remote_ip)
        #print(f"add_port_to_previously_open:self.previously_open_ip_list_A {self.previously_open_ip_list_A}",flush=True)
        #print(f"add_port_to_previously_open:self.previously_open_ip_list_B {self.previously_open_ip_list_B}",flush=True)




    def was_port_previously_open(self, local_ip, local_port, remote_ip):
        # look in both windows A and B:
        for window in (self.previously_open_ip_list_A,
                       self.previously_open_ip_list_B):
            remotes = window.get(local_port)
            if remotes and remote_ip in remotes:
                return True
        return False
        


            
    def is_port_open(self, local_ip, local_port, remote_ip):
        # Check if the local IP is present.
        if local_port in self.currently_open_ip_list :
            return True
        return False


    
    
    
    def is_ip_dst_on_local_network(self,ip_dst):
        if ip_dst in self.internal_ips['ipv4'] or ip_dst in self.internal_ips['ipv6'] or ip_dst==self.external_ip:
            return True
        else:
            return False
        
    def is_ip_src_on_local_network(self,ip_src):
        if ip_src in self.internal_ips['ipv4'] or ip_src in self.internal_ips['ipv6'] or ip_src==self.external_ip:
            return True
        else:
            return False
    
    def add_L2_reachable_host(self,ip,MAC,current_packet):
        if not self.is_ip_dst_on_local_network(ip):
            self.currently_open_ip_list[ip]={}
            #self.log_local_terminal_and_GUI_WARN(f"ARP: Added add_L2_reachable_host {ip} based on num {current_packet.packet_num} {current_packet.packet}",4)
            justification=f"Justification: Packet Number {current_packet.packet_num}  {current_packet.packet.payload}"
            #self.gui_sock.send(f"ARP: Added add_L2_reachable_host {ip} based on num {current_packet.packet_num} {current_packet.packet}")
            
    def remove_L2_reachable_host(self,ip,MAC):
        if self.is_ip_dst_on_local_network(ip):
            #self.currently_open_ip_list.remove(ip)
            del self.currently_open_ip_list[ip]

    

    
    def print_currently_open_ports(self): 
        return
        if self.verbose ==0:
            #self.log_local_terminal_and_GUI_WARN("----- Currently Open Ports -----",0)
            for ip, ports in self.currently_open_ip_list.items():
                #self.log_local_terminal_and_GUI_WARN(f"IP: {ip}", 0)
                # Check if the value is a dictionary (it should be in your design)
                if isinstance(ports, dict):
                    for port, pkt_list in ports.items():
                        #self.log_local_terminal_and_GUI_WARN(f"  Port: {port}", 0)
                        # Each item in pkt_list is assumed to be a Packet_info object.
                        for remote_ip in pkt_list:
                            pass
                            #self.log_local_terminal_and_GUI_WARN(f"    remote_ip {remote_ip}", 0)
                else:
                    pass
                    # print the value directly if it's not a dictionary.
                    #self.log_local_terminal_and_GUI_WARN(f"  {ports}",0)
            #self.log_local_terminal_and_GUI_WARN("----- End of Currently Open Ports -----",0)
      
           

    '''                
    def Remove_ARP_from_watch(self,Matching_ARP):
        for x in range(len(self.ARP_requests) - 1, -1, -1):
            historical_ARP= self.ARP_requests[x]
            if  historical_ARP.packet[ARP].pdst == Matching_ARP.packet[ARP].psrc :
                    #self.log_local_terminal_and_GUI_WARN(f"Removed answered ARP self.ARP_requests[x] {self.ARP_requests[x].packet} after {Matching_ARP.packet.time - self.ARP_requests[x].packet.time} delay"+\f" due to Matching_ARP.packet {Matching_ARP.packet} {Matching_ARP.packet.time} with {self.ARP_requests[x].packet} {self.ARP_requests[x].packet.time}",1)
                    #self.log_local_terminal_and_GUI_WARN(f"Matching_ARP.packet[ARP].psrc {Matching_ARP.packet[ARP].psrc} Matching_ARP.packet[ARP].pdst {Matching_ARP.packet[ARP].pdst} self.ARP_requests[x].packet[ARP].psrc {self.ARP_requests[x].packet[ARP].psrc} self.ARP_requests[x].packet[ARP].pdst {self.ARP_requests[x].packet[ARP].pdst}",1)
                    del self.ARP_requests[x]
    '''
                    
    
    def Check_SYN_watch(self,current_packet):
        pass

        
    def Process_ACK(self,pkt_info):
        #TODO: find the SYN and remove it before timer expires, if port closed mark as open
        self.remove_pkt_from_watch(pkt_info)
        
    def Process_Outgoing_TCP(self,pkt_info):
        
        if  'SYN' in pkt_info.tcp_flags and 'ACK' in pkt_info.tcp_flags and 'RST' not in pkt_info.tcp_flags:
            #If honeypot, lets log the synack to prove the attacker knew the port was open
            if pkt_info.tcp_sport in self.local_copy_open_honeypots:
                self.prepare_synack_data(pkt_info)
            #If not honeypot lets just make sure the port is open and the syn gets removed from the watch list
            else:
                #logging.info(f"Outgoing SA detected, so remove corresponding syn from list of unacked syns and process it as an open port{current_packet.packet}")
                #self.log_local_terminal_and_GUI_WARN(f" Process_Outgoing_TCP: Outgoing non R or F detected, so remove corresponding pckts from list of unacked and process it as an open port",1)
                self.Process_ACK(pkt_info)
                self.open_port(pkt_info.ip_src,pkt_info.tcp_sport,pkt_info.ip_dst, pkt_info)
                # So this will show "who knew" the port was open, but not if the handshake was successful. We won't know that for services running locally beacuse I'm not going to handle all the edge cases 
                #but we will for the honeypot ports.
                
        #This isn't exact, but it's close enough since we don't use ports being open to determine if a packet is unwanted

        if "FIN" in pkt_info.tcp_flags:

            #self.log_local_terminal_and_GUI_WARN(f"Process_Outgoing_TCP: Fin flag, add_port_to_previously_open(pkt_info.ip_src,pkt_info.tcp_sport,pkt_info.ip_dst)",0)
            self.close_port(pkt_info.ip_src,pkt_info.tcp_sport,pkt_info.ip_dst,pkt_info)
            #self.add_port_to_previously_open(pkt_info.ip_src,pkt_info.tcp_sport,pkt_info.ip_dst,pkt_info)
            




    #only called if we got an ack, so we can remove all if duplicates so we error on the side of false negatives
    def remove_pkt_from_watch(self, pkt):
        key = (pkt.ip_dst, pkt.tcp_dport,pkt.ip_src, pkt.tcp_sport)
        #print(f"remove_pkt_from_watch: {key}",flush=True)
        #bucket = self.packets_to_watch.get(key)
        #print(f"is in watch? {bucket}",flush=True)
        self.packets_to_watch.pop(key, None)
        #bucket = self.packets_to_watch.get(key)
        #print(f"how about now? {bucket}",flush=True)

    # ---------- hotpath: add packet ------------------------------------
    def add_pkt_to_watch(self, pkt):
        key = (pkt.ip_src, pkt.tcp_sport, pkt.ip_dst, pkt.tcp_dport)
        bucket = self.packets_to_watch.get(key)
        if bucket is None:              # new flow
            self.packets_to_watch[key] = [pkt]     # key goes to the end (newest)
        else:
            bucket.append(pkt)          # duplicates keep flow position

    # ---------- coldpath: reap expired ---------------------------------
    def clear_expired_pkts(self, now):

        while self.packets_to_watch:
            key, bucket = next(iter(self.packets_to_watch.items()))  # oldest flow
            first_pkt = bucket[0]

            # stop if the oldest packet is still within the timeout
            if now - first_pkt.packet_time <= self.SYN_reply_timeout:
                break

            # unpack our flow-key
            src_ip, src_port, dst_ip, dst_port = key

            # if the port is open *now*, drop this entire bucket
            if self.is_port_open(dst_ip, dst_port, src_ip):
                # removes the oldest item
                self.packets_to_watch.popitem(last=False)
                #print(f"clear_expired_pkts:was going to report but port is open now, bucket dropped {key}",flush=True)
                continue
            
            # if the port is open *now*, drop this entire bucket
            if self.was_port_previously_open(dst_ip, dst_port, src_ip):
                # removes the oldest item
                self.packets_to_watch.popitem(last=False)
                #print(f"clear_expired_pkts:was going to report but port was previously open, bucket dropped {key}",flush=True)
                continue

            # otherwise, this port truly never opened-report *all* expired packets
            while bucket and now - bucket[0].packet_time > self.SYN_reply_timeout:
                un_acked_pkt = bucket.pop(0)
                #print(f"clear_expired_pkts:reporting packet to port {dst_port}, open ports are {self.currently_open_ip_list.keys} prev open are {self.previously_open_ip_list_A.keys} {self.previously_open_ip_list_B}",flush=True)
                self.Report_unwanted_traffic(un_acked_pkt, "N/A", "N/A")

            # if nothing left in this bucket, remove the key
            if not bucket:
                self.packets_to_watch.popitem(last=False)
            else:
                # still has newer packets: move this key to the newest position
                self.packets_to_watch.move_to_end(key)


    def clear_and_report_all_watched_packets(self):
        # flush everything still being watched
        while self.packets_to_watch:
            key, bucket = self.packets_to_watch.popitem(last=False)  # oldest flow
            src_ip, src_port, dst_ip, dst_port = key

            # if the port is open now, skip reporting this bucket entirely
            if self.is_port_open(dst_ip, dst_port, src_ip):
                #print(f"clear_and_report_all_watched_packets:was going to report but port is open now, bucket dropped {key}",flush=True)
                continue
            
            # if the port is open *now*, drop this entire bucket
            if self.was_port_previously_open(dst_ip, dst_port, src_ip):
                # removes the oldest item
                #self.packets_to_watch.popitem(last=False)
                #TODO veridfy this logic
                #print(f"clear_and_report_all_watched_packets:was going to report but port was previously open, bucket dropped {key}",flush=True)
                continue

            # otherwise, report every packet in the bucket
            for un_acked_pkt in bucket:
                self.Report_unwanted_traffic(un_acked_pkt, "N/A", "N/A")




    def Clear_unreplied_ARPs(self,current_packet):
        while len(self.ARP_requests):
            if current_packet.packet.time - self.ARP_requests[0].packet.time >= self.ARP_reply_timeout :
                if self.is_ip_dst_on_local_network(self.ARP_requests[0].packet[ARP].pdst):
                    #self.log_local_terminal_and_GUI_WARN(f"ARP: Remove ip {self.ARP_requests[0].packet[ARP].pdst} from local hosts  ARP TIMEOUT: self.ARP_requests was never replied to, packet number :{self.ARP_requests[0].packet_num} {self.ARP_requests[0].packet} ",4)
                    unwanted_packet=self.ARP_requests.popleft()
                    self.remove_L2_reachable_host(unwanted_packet.packet[ARP].pdst,"")
                else:
                    #self.log_local_terminal_and_GUI_WARN(f"ARP:would remove ip {self.ARP_requests[0].packet[ARP].pdst} but it's not in local hosts. TIMEOUT: self.ARP_requests was never replied to, packet number :{self.ARP_requests[0].packet_num} {self.ARP_requests[0].packet}, ",4)
                    self.ARP_requests.popleft()

            else:
                break
    
    def Process_TCP(self,pkt_info):
        #incoming packets,we onlcy care about those to enpoints we monitor
        if self.is_ip_dst_on_local_network(pkt_info.ip_dst):
            self.num_total_tcp_packets=self.num_total_tcp_packets+1

            #self.log_local_terminal_and_GUI_WARN(f"Process_TCP: ***************** packet_num:{pkt_info.packet_num} seq:{pkt_info.tcp_seq} Incoming Seen at Process_TCP ******************",0)
            #self.log_local_terminal_and_GUI_WARN(f"Process_TCP: Incoming pkt_info.ip_src:{pkt_info.ip_src} pkt_info.ip_dst:{pkt_info.ip_dst} pkt_info.tcp_sport:{pkt_info.tcp_sport} pkt_info.tcp_dport:{pkt_info.tcp_dport} pkt_info.tcp_seq:{pkt_info.tcp_seq} ",0)
            #self.log_local_terminal_and_GUI_WARN(f"Process_TCP: ***************** {pkt_info.tcp_seq} self.print_currently_open_ports() ******************",0)
            #self.log_local_terminal_and_GUI_WARN(self.print_currently_open_ports(),0)
            #self.log_local_terminal_and_GUI_WARN(f"Process_TCP:  ***************** {pkt_info.tcp_seq} end currently_open_ports() ******************",0)

            '''if self.is_port_open(pkt_info.ip_dst,pkt_info.tcp_dport,pkt_info.ip_src):
                #self.log_local_terminal_and_GUI_WARN(f"Process_TCP: ***************** {pkt_info.tcp_seq} self.is_port_open came back true {pkt_info.ip_dst} ,{ pkt_info.tcp_dport} ",0)
                pass
            #error on side of caution, if port was previously open there's a chance packets may not be unwanted
            elif self.was_port_previously_open(pkt_info.ip_dst,pkt_info.tcp_dport,pkt_info.ip_src,pkt_info ) is True:
                #self.log_local_terminal_and_GUI_WARN(f"Process_TCP: ***************** {pkt_info.tcp_seq} self.is_port_open false, but self.was_port_previously_open came back true {pkt_info.ip_dst} ,{ pkt_info.tcp_dport} ",0)
                pass          
            else:
                #self.log_local_terminal_and_GUI_WARN(f"Process_TCP: ***************** {pkt_info.tcp_seq} self.was_port_previously_open came back false {pkt_info.ip_dst} ,{ pkt_info.tcp_dport} ",0)
                #strrr=self.print_previously_open_ports()
                #self.log_local_terminal_and_GUI_WARN(f"Process_TCP: entries in was_port_previously_open {strrr}",0)
            '''
            #add to watch only if a new syn. Maybe make a new thread to handle the connections and opening the ports
            if pkt_info.tcp_flags == "SYN":
                self.add_pkt_to_watch(pkt_info)          
        #outgoing packets
        elif self.is_ip_src_on_local_network(pkt_info.ip_src):
            #self.log_local_terminal_and_GUI_WARN(f"Process_TCP: ***************** packet_num:{pkt_info.packet_num} seq:{pkt_info.tcp_seq} Outgoing Seen at Process_TCP ******************",0)
            #self.log_local_terminal_and_GUI_WARN(f"Process_TCP: Outgoing pkt_info.ip_src:{pkt_info.ip_src} pkt_info.ip_dst:{pkt_info.ip_dst} pkt_info.tcp_sport:{pkt_info.tcp_sport} pkt_info.tcp_dport:{pkt_info.tcp_dport} pkt_info.tcp_seq:{pkt_info.tcp_seq} ",0)
            self.Process_Outgoing_TCP(pkt_info)
        #self.log_local_terminal_and_GUI_WARN(f"\n\n=============================\n\n",0)


    def print_previously_open_ports(self):
        if self.verbose ==0:
            strrr=""
            for outer_key  in self.previously_open_ip_list_A.keys():
                strrr+="A"+str(outer_key)+","
            for outer_key in self.previously_open_ip_list_B.keys():
                strrr+="B"+str(outer_key)+","
        
            
            #self.log_local_terminal_and_GUI_WARN(f"print_previously_open_ports: {strrr}",0)
            
        
    def hash_segment(self, segment, key):
        """
        Hash a segment (an int or string) together with the key,
        and map to 0255.
        """
        combined = f"{segment}-{key}"
        h = hashlib.sha256(combined.encode()).hexdigest()
        return int(h[:2], 16) % 256

    def randomize_ip(self, ip_str):
        """
        Randomize an IPv4 *or* IPv6 address, returning a string
        in the same notation (dotted-quad or compressed IPv6).
        """
        try:
            ip = ipaddress.ip_address(ip_str)
        except ValueError:
            raise ValueError(f"Invalid IP address: {ip_str!r}")

        key = self.randomization_key
        # operate on the raw bytes of the address
        orig_bytes = ip.packed  # b'\xC0\xA8\x00\x01' for 192.168.0.1, or 16 bytes for IPv6

        # hash each byte  new byte
        new_bytes = bytes(self.hash_segment(b, key) for b in orig_bytes)

        # reconstruct an IP object from those bytes
        rand_ip = ipaddress.IPv4Address(new_bytes) if ip.version == 4 else ipaddress.IPv6Address(new_bytes)
        return str(rand_ip)
    


            
            
                   
    def Report_unwanted_traffic(self,pkt_info,reason,confidence):
        
        self.num_unwanted_tcp_packets+=1
        if pkt_info.tcp_dport >1023:
            self.port_counts[pkt_info.tcp_dport] += 1
            ###print(f"Report_unwanted_traffic: Added port {pkt_info.tcp_dport} to counts. Total tracked ports: {len(self.port_counts)}")
        #self.verify_ip(pkt_info)
        self.prepare_unwanted_syn_data(pkt_info)

       
    
    def send_heartbeat(self):
        current_open_common_ports = []
        for port, remotes in self.currently_open_ip_list.items():
            # skip non-numeric keys (like "time_started" in your prev lists) if any
            if not isinstance(port, int):
                continue
                count = len(remotes)
                current_open_common_ports.append(f"{port}x{count}")

        previosuly_open_common_ports = []
        # gather all ports seen in either A or B
        all_prev_ports = set(self.previously_open_ip_list_A) | set(self.previously_open_ip_list_B)
        for port in all_prev_ports:
            if port == "time_started" or not isinstance(port, int):
                continue

            # union the two sets so we count each remote IP only once
            remotes_a = self.previously_open_ip_list_A.get(port, set())
            remotes_b = self.previously_open_ip_list_B.get(port, set())
            count = len(remotes_a | remotes_b)
            previosuly_open_common_ports.append(f"{port}x{count}")

        

        heartbeat_message = {
            "db_name":                        "heartbeats",
            "unwanted_db":                    self.database,
            "pkts_last_hb":                   self.num_total_tcp_packets,
            "ext_dst_ip_country":             self.external_network_information['country'],
            "type":                           self.external_network_information['type'],
            "ASN":                            self.external_network_information['ASN'],
            "domain":                         self.external_network_information['domain'],
            "city":                           self.external_network_information['city'],
            "as_type":                        self.external_network_information['as_type'],
            
            "external_is_private":            check_ip_is_private(self.external_ip) ,
            "open_ports":                     ",".join(current_open_common_ports), 
            "previously_open_ports":          ",".join(previosuly_open_common_ports),        
            "interface":                      self.interface_human_readable,
            "internal_ip_randomized":         ",".join(str(v) for v in self.internal_ip_randomized_v4 + self.internal_ip_randomized_v6),
            "external_ip_randomized":         self.external_ip_randomized,

            "System_info":                   self.system_info['System'],
            "Release_info":                  self.system_info['Release'],
            "Version_info":                  self.system_info['Version'],
            "Machine_info":                       self.system_info['Machine'],
            "Total_Memory":                  self.system_info['Total_Memory'],
            "processor":                     self.system_info['processor'],
            "architecture" :                 self.system_info['architecture'],
            "open_honeypot_ports":           ",".join(str(port) for port in self.local_copy_open_honeypots),
            "ls_version":                    ls_version
        }

        #print(payload,flush=True)
        self.num_total_tcp_packets=0
        self.producer_upload_conn.send(heartbeat_message)                
    

    def prepare_unwanted_syn_data(self,pkt_info):
        current_open_common_ports = []
        for port, remotes in self.currently_open_ip_list.items():
            # skip non-numeric keys (like "time_started" in your prev lists) if any
            if not isinstance(port, int):
                continue

            count = len(remotes)
            current_open_common_ports.append(f"{port}x{count}")

        previosuly_open_common_ports = []
        # gather all ports seen in either A or B
        all_prev_ports = set(self.previously_open_ip_list_A) | set(self.previously_open_ip_list_B)
        for port in all_prev_ports:
            if port == "time_started" or not isinstance(port, int):
                continue

            # union the two sets so we count each remote IP only once
            remotes_a = self.previously_open_ip_list_A.get(port, set())
            remotes_b = self.previously_open_ip_list_B.get(port, set())
            count = len(remotes_a | remotes_b)
            previosuly_open_common_ports.append(f"{port}x{count}")

        

        payload = {
            "db_name":                        self.database,
            "system_time":                    str(pkt_info.packet_time),
            "ip_version":                     pkt_info.ip_version,
            "ip_ihl":                         pkt_info.ip_ihl,
            "ip_tos":                         pkt_info.ip_tos,
            "ip_len":                         pkt_info.ip_len,
            "ip_id":                          pkt_info.ip_id ,
            "ip_flags":                       ",".join(str(v) for v in pkt_info.ip_flags),
            "ip_frag":                        pkt_info.ip_frag,
            "ip_ttl":                         pkt_info.ip_ttl,
            "ip_proto":                       pkt_info.ip_proto,
            "ip_chksum":                      pkt_info.ip_chksum,
            "ip_src":                         pkt_info.ip_src,
            "ip_dst_randomized":              self.randomize_ip(pkt_info.ip_dst), #todo ipv6?
            "ip_options":                     ",".join(str(v) for v in pkt_info.ip_options ),
            "tcp_sport":                      pkt_info.tcp_sport,           
            "tcp_dport":                      pkt_info.tcp_dport,           
            "tcp_seq":                        pkt_info.tcp_seq ,            
            "tcp_ack":                        pkt_info.tcp_ack ,            
            "tcp_dataofs":                    pkt_info.tcp_dataofs ,        
            "tcp_reserved":                   pkt_info.tcp_reserved,   
            "tcp_flags":                      pkt_info.tcp_flags,
            "tcp_window":                     pkt_info.tcp_window,
            "tcp_chksum":                     pkt_info.tcp_chksum,
            "tcp_urgptr":                     pkt_info.tcp_urgptr,
            
            "ext_dst_ip_country":             self.external_network_information['country'],
            "type":                           self.external_network_information['type'],
            "ASN":                            self.external_network_information['ASN'],
            "domain":                         self.external_network_information['domain'],
            "city":                           self.external_network_information['city'],
            "as_type":                        self.external_network_information['as_type'],
            
            "ip_dst_is_private":              check_ip_is_private(pkt_info.ip_dst) ,
            "external_is_private":            check_ip_is_private(self.external_ip) ,
            "open_ports":                     ",".join(current_open_common_ports), 
            "previously_open_ports":          ",".join(previosuly_open_common_ports),        
            "tcp_options":                     ",".join(str(v) for v in human_readable_tcp_opts(pkt_info.tcp_options) ),
            "interface":                      self.interface_human_readable,
            "internal_ip_randomized":         ",".join(str(v) for v in self.internal_ip_randomized_v4 + self.internal_ip_randomized_v6),
            "external_ip_randomized":         self.external_ip_randomized,

            "System_info":                   self.system_info['System'],
            "Release_info":                  self.system_info['Release'],
            "Version_info":                  self.system_info['Version'],
            "Machine_info":                       self.system_info['Machine'],
            "Total_Memory":                  self.system_info['Total_Memory'],
            "processor":                     self.system_info['processor'],
            "architecture" :                 self.system_info['architecture'],
            "honeypot_status":               str(pkt_info.tcp_dport in self.local_copy_open_honeypots),
            "payload":                       "N/A",
            "ls_version":                    ls_version
        }

        #print(payload,flush=True)

        self.producer_upload_conn.send(payload)
        self.unwanted_packet_count=self.unwanted_packet_count+1
        ###print(f"Et tu, Brute? {payload}")
        '''if self.unwanted_packet_count % 1000 ==0:
            #self.log_local_terminal_and_GUI_WARN(f"self.unwanted_packet_count {self.unwanted_packet_count}",0)
        '''

    def prepare_synack_data(self,pkt_info):
        current_open_common_ports = []
        for port, remotes in self.currently_open_ip_list.items():
            # skip non-numeric keys (like "time_started" in your prev lists) if any
            if not isinstance(port, int):
                continue

            count = len(remotes)
            current_open_common_ports.append(f"{port}x{count}")

        previosuly_open_common_ports = []
        # gather all ports seen in either A or B
        all_prev_ports = set(self.previously_open_ip_list_A) | set(self.previously_open_ip_list_B)
        for port in all_prev_ports:
            if port == "time_started" or not isinstance(port, int):
                continue

            # union the two sets so we count each remote IP only once
            remotes_a = self.previously_open_ip_list_A.get(port, set())
            remotes_b = self.previously_open_ip_list_B.get(port, set())
            count = len(remotes_a | remotes_b)
            previosuly_open_common_ports.append(f"{port}x{count}")

        

        payload = {
            "db_name":                        self.database,
            "system_time":                    str(pkt_info.packet_time),
            "ip_version":                     pkt_info.ip_version,
            "ip_ihl":                         pkt_info.ip_ihl,
            "ip_tos":                         pkt_info.ip_tos,
            "ip_len":                         pkt_info.ip_len,
            "ip_id":                          pkt_info.ip_id ,
            "ip_flags":                       ",".join(str(v) for v in pkt_info.ip_flags),
            "ip_frag":                        pkt_info.ip_frag,
            "ip_ttl":                         pkt_info.ip_ttl,
            "ip_proto":                       pkt_info.ip_proto,
            "ip_chksum":                      pkt_info.ip_chksum,
            "ip_src":                         self.randomize_ip(pkt_info.ip_src),
            "ip_dst_randomized":              pkt_info.ip_dst, #todo ipv6?
            "ip_options":                     ",".join(str(v) for v in pkt_info.ip_options ),
            "tcp_sport":                      pkt_info.tcp_sport,           
            "tcp_dport":                      pkt_info.tcp_dport,           
            "tcp_seq":                        0,            
            "tcp_ack":                        "HP",            
            "tcp_dataofs":                    "HP",        
            "tcp_reserved":                   "HP",   
            "tcp_flags":                      "HP-SA",
            "tcp_window":                     "HP",
            "tcp_chksum":                     "HP",
            "tcp_urgptr":                     "HP",
            
            "ext_dst_ip_country":             "outgoing-syn-ack",
            "type":                           "outgoing-syn-ack",
            "ASN":                            "outgoing-syn-ack",
            "domain":                         "outgoing-syn-ack",
            "city":                           "outgoing-syn-ack",
            "as_type":                        "outgoing-syn-ack",
            
            "ip_dst_is_private":              check_ip_is_private(pkt_info.ip_dst) ,
            "external_is_private":            check_ip_is_private(self.external_ip) ,
            "open_ports":                     ",".join(current_open_common_ports), 
            "previously_open_ports":          ",".join(previosuly_open_common_ports),        
            "tcp_options":                     ",".join(str(v) for v in human_readable_tcp_opts(pkt_info.tcp_options) ),
            "interface":                      self.interface_human_readable,
            "internal_ip_randomized":         ",".join(str(v) for v in self.internal_ip_randomized_v4 + self.internal_ip_randomized_v6),
            "external_ip_randomized":         self.external_ip_randomized,

            "System_info":                   self.system_info['System'],
            "Release_info":                  self.system_info['Release'],
            "Version_info":                  self.system_info['Version'],
            "Machine_info":                       self.system_info['Machine'],
            "Total_Memory":                  self.system_info['Total_Memory'],
            "processor":                     self.system_info['processor'],
            "architecture" :                 self.system_info['architecture'],
            "honeypot_status":               str(pkt_info.tcp_sport in self.local_copy_open_honeypots),
            "payload":                       "N/A",
            "ls_version":                    ls_version
        }

        #print(payload,flush=True)

        self.producer_upload_conn.send(payload)
        self.unwanted_packet_count=self.unwanted_packet_count+1
        '''if self.unwanted_packet_count % 1000 ==0:
            #self.log_local_terminal_and_GUI_WARN(f"self.unwanted_packet_count {self.unwanted_packet_count}",0)
        '''

 


    def ARP_add_hosts(self,current_packet):
        #logging.info(f"AAAAAAAAAAAAAAA current_packet.packet[ARP] {current_packet.packet[ARP].show(dump=True)}")
        #logging.warning(f"AAAAAAAAAAAAAAA  {dir(current_packet.packet[ARP])}")
        self.add_L2_reachable_host(current_packet.packet[ARP].psrc,current_packet.packet[ARP].hwsrc,current_packet)
        
    
    def ARP_add_request_watch(self,current_packet):
        #Track the ARP request, if it goes unanswered remove the requested host from L2 reachable
        #current_packet.packet[ARP].op == 2 means it was an ARP reply, ==1 is a request
        matching_out_of_order_reply=0
        self.ARP_same_timestamp.append(current_packet)
        if self.ARP_same_timestamp[0].packet.time != current_packet.packet.time:
            self.ARP_same_timestamp.clear()
            self.ARP_same_timestamp.append(current_packet)
        else:
            self.ARP_same_timestamp.append(current_packet)
        
        if current_packet.packet[ARP].op == 1:
            if self.ARP_same_timestamp:
                if self.ARP_same_timestamp[0].packet.time == current_packet.packet.time:
                    for ARP_with_same_timestamp in self.ARP_same_timestamp:
                        if  current_packet.packet[ARP].pdst == ARP_with_same_timestamp.packet[ARP].psrc :
                            matching_out_of_order_reply=1
                            #self.log_local_terminal_and_GUI_WARN(f"Out of order ARP reply for num {current_packet.packet_num} {current_packet.packet} and {ARP_with_same_timestamp.packet_num} {ARP_with_same_timestamp.packet} ",1)  
                if not matching_out_of_order_reply:
                    self.ARP_requests.append(current_packet)
            
    

                    
    def Process_ARP(self,current_packet):
        #if collecting on all IPs use ARP method
        pass
        '''if self.collection_ip == "all":
            if current_packet.packet.haslayer(ARP):# 
                #Add the sender of the ARP request, we know they are there
                self.ARP_add_hosts(current_packet)
                self.ARP_add_request_watch(current_packet)
                #TODO: maybe change logic here to detect MAC issues with ip addresses and ARP, for now if it's responding/originating ARP then you can remove unreplied ARPs
                self.Clear_unreplied_ARPs(current_packet)
                self.Remove_ARP_from_watch(current_packet)'''
            
    
        
      
        
    def Process_packet(self,pkt_info):
        #self.Process_ARP(pkt_info)
        self.Process_TCP(pkt_info)
        

    def ensure_directory(self,directory_name):
        """Ensure the directory exists, and if not, create it."""
        if not os.path.exists(directory_name):
            os.makedirs(directory_name)



    
            
            
    def packet_handler(self, unprocessed_packets):
        next_hb = time.monotonic()  
        honeypot_open_ports_updates = time.monotonic()  
        honeypot_send_top_ports = time.monotonic()  
        work_deque  = deque(maxlen=MAX_SIZE)
        packets_processed=0
        prior_time=time.monotonic()

        def fill_work_deque():
            while True:
                batch = unprocessed_packets.recv()    # blocks until a batch arrives
                work_deque.append(batch)           # atomic in CPython

        # start receiver…
        t = threading.Thread(target=fill_work_deque, daemon=True)
        t.start()

        while True:

            now = time.monotonic()
            
            # Send systemd watchdog notification (if available)
            if systemd_watchdog_notify:
                try:
                    systemd_watchdog_notify()
                except:
                    pass  # Ignore watchdog errors

            #send the honypot the top ports
            if now >= honeypot_send_top_ports:
                self.top_unwanted_ports_producer.send((self.interface_human_readable,self.port_counts))
                honeypot_send_top_ports = now + 60 * 60 * 1  # Send every 5 minutes for better data

            #check for honeypot open ports
            if now >= honeypot_open_ports_updates:
                # Get current honeypot ports from shared memory (non-blocking, thread-safe)
                import copy
                self.local_copy_open_honeypots = copy.deepcopy(set(self.shared_open_honeypots))
                # Send our port count data for honeypot rotation
                self.send_port_counts()
                # You can now use current_honeypot_ports for your logic
                # Example: print(f"Current honeypot ports: {self.local_copy_open_honeypots}")
                honeypot_open_ports_updates = now + 10   # Check every 10 seconds


            #heartbeats
            if now >= next_hb:
                self.send_heartbeat()
                next_hb = now + 60 * 15


                            #Open ports for honeypots

            try:
                batch = work_deque.popleft()      # atomic pop from left
            except IndexError:
                # no work right now
                time.sleep(1)
                #time.sleep(0.1)
                #self.clear_and_report_all_watched_packets()
                continue
 

            # 2) process it
            for pkt in batch:
                self.Process_packet(pkt)
                packets_processed+=1
            self.clear_expired_pkts(batch[-1].packet_time)




            if (now - prior_time) >= 1:
                ###print(f"packet_handler: pps {packets_processed} port_counts {len(self.port_counts)} self.local_copy_open_honeypots {self.local_copy_open_honeypots} len(work_deque) {len(work_deque)} {self.interface_human_readable}",flush=True)
                packets_processed=0
                prior_time=now
                    
    def send_port_counts(self):
        """Send port count data to honeypot worker for rotation decisions"""
        if self.top_unwanted_ports_producer and self.port_counts:
            try:
                port_data = dict(self.port_counts.most_common(50))
                ###print(f"send_port_counts: Sending {len(port_data)} ports from {self.interface_human_readable}: {list(port_data.keys())[:10]}")
                self.top_unwanted_ports_producer.send((self.interface_human_readable, port_data))
            except Exception as e:
                ###print(f"send_port_counts: Error sending data: {e}")
                pass
        else:
            ###print(f"send_port_counts: No data to send from {self.interface_human_readable}. port_counts: {len(self.port_counts) if self.port_counts else 0}")
            pass

    #Note that nmap scans will hit all the ports we have open, so we don't need to do anything special for those
    #We just need to catch the ones that sporadically check random ports, and the ones that only hit one or a cople ports like 23
    #so every 5 minutes, lets see if anyone hit our ports. If they did, close them and move on the next ones. 





   

    
                    



                    


        
        
import collections
from collections import deque
import time
import requests
from requests.adapters import HTTPAdapter

from collections import deque
import time
import threading
import requests
from requests.adapters import HTTPAdapter

def send_honeypot_data(consumer_upload_conn):
    DATA_URL      = "https://thelightscope.com/log_mysql_data"  # Use existing endpoint temporarily
    HEADERS       = {
        "Content-Type": "application/json",
        "X-API-Key":    "lightscopeAPIkey2025_please_dont_distribute_me_but_im_write_only_anyways"
    }

    BATCH_SIZE     = 100  # Smaller batch size for honeypot data
    IDLE_FLUSH_SEC = 5.0    # flush data if idle this long
    RETRY_BACKOFF  = 5      # seconds to wait on failure

    session = requests.Session()
    adapter = HTTPAdapter(pool_connections=2, pool_maxsize=2)
    session.mount("https://", adapter)
    session.mount("http://",  adapter)

    queue = deque(maxlen=MAX_SIZE)
    last_activity = time.monotonic()
    stop_event    = threading.Event()

    # --------------------------- reader thread ---------------------------
    def reader():
        nonlocal last_activity
        while not stop_event.is_set():
            try:
                item = consumer_upload_conn.recv()
            except (EOFError, OSError):
                stop_event.set()
                break
            queue.append(item)
            last_activity = time.monotonic()
        # drain any leftover
        while True:
            try:
                queue.append(consumer_upload_conn.recv_nowait())
            except Exception:
                break

    t = threading.Thread(target=reader, daemon=True)
    t.start()

    # --------------------------- flush loop ---------------------------
    try:
        while not stop_event.is_set() or queue:
            # check if it's time to flush a batch of honeypot data records
            now     = time.monotonic()
            elapsed = now - last_activity

            if queue and (len(queue) >= BATCH_SIZE or elapsed >= IDLE_FLUSH_SEC):
                to_send = min(len(queue), BATCH_SIZE)
                batch   = [queue.popleft() for _ in range(to_send)]
                try:
                    resp = session.post(
                        DATA_URL,
                        json={"batch": batch},
                        headers=HEADERS,
                        timeout=10,
                    )
                    if resp.status_code != 200:
                        print(f"[honeypot] rejected ({to_send} items): {resp.status_code} {resp.text}", flush=True)
                        pass
                    else:
                        ###print(f"[honeypot] flushed {to_send} items successfully", flush=True)
                        pass
                    resp.raise_for_status()
                    last_activity = time.monotonic()
                except requests.RequestException as e:
                    # push them back on front, and retry later
                    print(f"[honeypot] error, will retry batch: {e}", flush=True)
                    for item in reversed(batch):
                        queue.appendleft(item)
                    time.sleep(RETRY_BACKOFF)
                    # note: we do _not_ update last_activity so idle timer will trigger again
            else:
                time.sleep(0.1)

    finally:
        stop_event.set()
        t.join()


def send_data(consumer_upload_conn):
    DATA_URL      = "https://thelightscope.com/log_mysql_data"
    HEARTBEAT_URL = "https://thelightscope.com/heartbeat"
    HEADERS       = {
        "Content-Type": "application/json",
        "X-API-Key":    "lightscopeAPIkey2025_please_dont_distribute_me_but_im_write_only_anyways"
    }

    BATCH_SIZE     = 600
    IDLE_FLUSH_SEC = 5.0    # flush data if idle this long
    RETRY_BACKOFF  = 5      # seconds to wait on failure

    session = requests.Session()
    adapter = HTTPAdapter(pool_connections=4, pool_maxsize=4)
    session.mount("https://", adapter)
    session.mount("http://",  adapter)

    queue = deque(maxlen=MAX_SIZE)
    last_activity = time.monotonic()
    stop_event    = threading.Event()

    # --------------------------- reader thread ---------------------------
    def reader():
        nonlocal last_activity
        while not stop_event.is_set():
            try:
                item = consumer_upload_conn.recv()
            except (EOFError, OSError):
                stop_event.set()
                break
            queue.append(item)
            last_activity = time.monotonic()
        # drain any leftover
        while True:
            try:
                queue.append(consumer_upload_conn.recv_nowait())
            except Exception:
                break

    t = threading.Thread(target=reader, daemon=True)
    t.start()

    # --------------------------- flush loop ---------------------------
    try:
        while not stop_event.is_set() or queue:
            # 1) first, pull out _all_ pending heartbeats and send them
            hb_count = 0
            n = len(queue)
            for _ in range(n):
                item = queue.popleft()
                if item.get("db_name") == "heartbeats":
                    hb_count += 1
                    try:
                        resp = session.post(
                            HEARTBEAT_URL,
                            json=item,
                            headers=HEADERS,
                            timeout=10,
                            
                        )
                        if resp.status_code != 200:
                            print(f"[heartbeat] rejected ({resp.status_code}): {resp.text}", flush=True)
                            pass
                        resp.raise_for_status()
                    except requests.RequestException as e:
                        print(f"[heartbeat] error, will drop: {e}", flush=True)
                        pass
                else:
                    queue.append(item)
            if hb_count:
                print(f"[heartbeat] sent {hb_count} message(s)", flush=True)
                pass

            # 2) now, see if it's time to flush a batch of normal data records
            now     = time.monotonic()
            elapsed = now - last_activity

            if queue and (len(queue) >= BATCH_SIZE or elapsed >= IDLE_FLUSH_SEC):
                to_send = min(len(queue), BATCH_SIZE)
                batch   = [queue.popleft() for _ in range(to_send)]
                try:
                    resp = session.post(
                        DATA_URL,
                        json={"batch": batch},
                        headers=HEADERS,
                        timeout=10,
                        
                    )
                    if resp.status_code != 200:
                        ###print(f"[data] rejected ({to_send} items): {resp.status_code} {resp.text}", flush=True)
                        pass
                    else:
                        ###print(f"[data] flushed {to_send} items", flush=True)
                        pass
                    resp.raise_for_status()
                    last_activity = time.monotonic()
                except requests.RequestException as e:
                    # push them back on front, and retry later
                    #print(f"[data] error, will retry batch: {e}", flush=True)
                    pass
                    for item in reversed(batch):
                        queue.appendleft(item)
                    time.sleep(RETRY_BACKOFF)
                    # note: we do _not_ update last_activity so idle timer will trigger again
            else:
                time.sleep(0.1)

    finally:
        stop_event.set()
        t.join()





                
def read_from_interface_mac_linux(network_interface,
                        unprocessed_packets,         # duplex Pipe
                        promisc_mode=False):

    import pylibpcap.base
    BATCH_SIZE      = 280
    IDLE_FLUSH_SECS = 1.0
    SLEEP_DELAY     = 0.001  # 1ms when no flush condition met
    send_deque   = deque(maxlen=MAX_SIZE)
    last_activity = time.monotonic()

    # --------------------------- sender thread ---------------------------
    def sender_thread():
        nonlocal last_activity
        
        #todo remove debug

        prior_time=time.monotonic()
        packets_processed=0

        

        while True:
            now = time.monotonic()
            to_send = 0

            if (now - prior_time) >= IDLE_FLUSH_SECS:
                ###print(f"read_from_interface_mac_linux: pps {packets_processed} {network_interface}  len(send_deque) {len(send_deque)} ",flush=True)
                packets_processed=0
                prior_time=now



            # 1) full batch ready?
            if len(send_deque) >= BATCH_SIZE:
                to_send = BATCH_SIZE

            # 2) idle timeout expired & buffer non-empty?
            elif send_deque and (now - last_activity) >= IDLE_FLUSH_SECS:
                to_send = len(send_deque)

            # 3) nothing to do right now
            else:
                time.sleep(SLEEP_DELAY)
                continue
            
            
            # build and send batch
            batch = [send_deque.popleft() for _ in range(to_send)]
            try:
                unprocessed_packets.send(batch)       # send to handler
            except Exception as e:
                ###print("pipe send error:", e, file=sys.stderr)
                return



            #todo remove debug code
            packets_processed+=to_send

           

    threading.Thread(target=sender_thread, daemon=True).start()

    # --------------------------- sniffer init ----------------------------
    try:
        sniffobj = pylibpcap.base.Sniff(
            network_interface,
            count=-1,
            promisc=int(promisc_mode),
            #todo may need to allow ARP again if discovering
            filter="ip and tcp",
            buffer_size=1 << 20,
            snaplen=256
        )
    except Exception as e:
        ###print(f"ERROR initializing capture: {e}", file=sys.stderr)
        sys.exit(1)

    # --------------------------- capture loop ---------------------------
    packet_number = 0
    for plen, ts, buf in sniffobj.capture():
        packet_number += 1
        try:
            try:
                pkt_info = parse_packet_info_fast(buf, packet_number)
            except Exception as a:
                pkt_info = parse_packet_info(buf, packet_number)
                #print(f"parse_packet_info_fast {a}",flush=True)
        except Exception as v:
            # could be VLAN, ARP, IPv6, malformedjust drop it
            #print(f"parse_packet_info_ slow {v}",flush=True)
            continue

        send_deque.append(pkt_info)
        last_activity = time.monotonic()


import sys
import time
import threading
from collections import deque



def read_from_interface_windows(network_interface,
                                unprocessed_packets,  # duplex Pipe
                                promisc_mode=False):

    interface_human_readable=""
    import re, wmi

    # initialize WMI once
    _wmi = wmi.WMI()
    m = re.search(r'\{([0-9A-Fa-f-]+)\}', network_interface)
    if m:
        guid = m.group(1).lower()
        # search the *adapter* class (not the Configuration class!)
        for nic in _wmi.Win32_NetworkAdapter():
            if not nic.GUID:
                continue
            if nic.GUID.strip('{}').lower() == guid:
                friendly = (
                    nic.NetConnectionID
                    or nic.Name
                    or nic.Description
                )
                # *** assignment, not comparison! ***
                interface_human_readable = friendly +network_interface
                break

    import pcap
    # --- 1) Discover all raw NPF device names ---
    devs = pcap.findalldevs()
    if not devs:
        ###print("No capture devices found. Is Npcap installed and running?", file=sys.stderr)
        sys.exit(1)

    # If the caller passed a friendly name (e.g. "Ethernet"), try to match it:
    if network_interface not in devs:
        ###print(f"Warning: '{network_interface}' is not one of the NPF devices.", file=sys.stderr)
        ###print("Available devices:", file=sys.stderr)
        for i, d in enumerate(devs, 1):
            ###print(f"  {i}. {d}", file=sys.stderr)
            pass
        # fall back to first device
        network_interface = devs[0]
        ###print(f"Falling back to first device: {network_interface!r}", file=sys.stderr)

    BATCH_SIZE      = 280
    IDLE_FLUSH_SECS = 1.0
    SLEEP_DELAY     = 0.001  # 1ms when no flush condition met
    send_deque      = deque(maxlen=MAX_SIZE)
    last_activity   = time.monotonic()

    # --------------------------- sender thread ---------------------------
    def sender_thread():
        nonlocal last_activity
        prior_time = time.monotonic()
        packets_processed = 0

        while True:
            now = time.monotonic()
            to_send = 0

            if (now - prior_time) >= IDLE_FLUSH_SECS:
                ###print(f"len(send_deque) {len(send_deque)} pps {packets_processed} {interface_human_readable}", flush=True)
                packets_processed = 0
                prior_time = now

            if len(send_deque) >= BATCH_SIZE:
                to_send = BATCH_SIZE
            elif send_deque and (now - last_activity) >= IDLE_FLUSH_SECS:
                to_send = len(send_deque)
            else:
                time.sleep(SLEEP_DELAY)
                continue

            batch = [send_deque.popleft() for _ in range(to_send)]
            try:
                unprocessed_packets.send(batch)
            except Exception as e:
                ###print("pipe send error:", e, file=sys.stderr)
                return

            packets_processed += to_send
            

    threading.Thread(target=sender_thread, daemon=True).start()

    # --------------------------- sniffer init ----------------------------
    try:
        sniffer = pcap.pcap(
            name=network_interface,
            snaplen=256,
            promisc=bool(promisc_mode),
            immediate=True,
            timeout_ms=50
        )
    except Exception as e:
        ###print(f"ERROR initializing capture: {e}", file=sys.stderr)
        sys.exit(1)

    # --- verify it really opened ---
    linktype = sniffer.datalink()
    if linktype < 0:
        ###print(f"ERROR: Failed to open '{network_interface}' (datalink() returned {linktype})", file=sys.stderr)
        sys.exit(1)

    # --- install the BPF filter ---
    try:
        sniffer.setfilter("ip and tcp")
    except Exception as e:
        ###print(f"ERROR setting filter: {e}", file=sys.stderr)
        sys.exit(1)

    # --------------------------- capture loop ----------------------------
    packet_number = 0
    for ts, buf in sniffer:
        packet_number += 1
        try:
            try:
                pkt_info = parse_packet_info_fast(buf, packet_number)
            except Exception:
                pkt_info = parse_packet_info(buf, packet_number)
        except Exception:
            continue

        send_deque.append(pkt_info)
        last_activity = time.monotonic()



import re

def fix_npf_name(s: str) -> str:
    # 1) collapse '\\'  '\'
    s = s.replace('\\\\', '\\')
    # 2) collapse '{{GUID}}'  '{GUID}'
    return re.sub(r'\{\{(.*?)\}\}', r'{\1}', s)

def is_npcap_installed():
            try:
                import ctypes
                # Attempt to load both DLLs
                ctypes.WinDLL("wpcap.dll")
                ctypes.WinDLL("Packet.dll")
                ###print("Npcap is installed and available on Windows!")
                return True
            except OSError:
                ###print(f"\n\n\n**Error detected*** \n",flush=True)
                ###print(f"Please install Npcap, which can be found here! https://npcap.com/#download",flush=True)
                ###print(f"Please choose 'Npcap 1.81 installer for Windows 7/2008R2, 8/2012, 8.1/2012R2, 10/2016, 2019, 11 (x86, x64, and ARM64)'",flush=True)
                ###print(f"When installing, make sure you select Install Npcap in WinPcap API-compatible Mode. This should be selected by default.",flush=True)
                ###print(f"\n***Exiting***\n",flush=True)
                sys.exit(1)
                return False
            

def choose_windows_interface():
    import pcap, wmi, re
    from ipaddress import ip_address

    # 1) get raw NPF names
    devs = pcap.findalldevs()

    # 2) build a GUID → {ipv4, ipv6} map from WMI
    c = wmi.WMI()
    guid_ip_map = {}
    for cfg in c.Win32_NetworkAdapterConfiguration():
        if not cfg.SettingID:
            continue
        guid = cfg.SettingID.strip('{}').lower()
        addrs = cfg.IPAddress or []
        v4, v6 = [], []
        for ip in addrs:
            try:
                ip_obj = ip_address(ip)
            except ValueError:
                continue
            if ip_obj.version == 4:
                v4.append(ip)
            else:
                v6.append(ip)
        guid_ip_map[guid] = {'ipv4': v4, 'ipv6': v6}

    # 3) produce final mapping from NPF name → its IP lists
    result = {}
    for dev in devs:
        m = re.search(r'\{([0-9A-Fa-f-]+)\}', dev)
        if m:
            guid = m.group(1).lower()
            result[dev] = guid_ip_map.get(guid, {'ipv4': [], 'ipv6': []})
        else:
            result[dev] = {'ipv4': [], 'ipv6': []}

    return result



import psutil
import socket
import time

def choose_mac_linux_interface():
    '''return {'en0':{
          'ipv4': ['10.78.180.31'],
          'ipv6': ['fe80::1434:1d02:bea8:c2c5']
        }}'''
    """
    Returns a dict mapping each up network interface
    to a dict containing its non-loopback IPv4 and IPv6 addresses.
    Example return value:
      {
        'en0': {
          'ipv4': ['192.168.1.42'],
          'ipv6': ['fe80::1234:abcd:5678:9ef0']
        },
        'eth0': {
          'ipv4': ['10.0.0.5'],
          'ipv6': []
        },
        ...
      }
    """
    stats = psutil.net_if_stats()
    addrs = psutil.net_if_addrs()
    result = {}

    for iface, s in stats.items():
        if not s.isup:
            continue

        ipv4s = [
            a.address for a in addrs.get(iface, [])
            if a.family == socket.AF_INET
            and not a.address.startswith("127.")
        ]
        ipv6s = [
            a.address for a in addrs.get(iface, [])
            if a.family == socket.AF_INET6
            and not (a.address == '::1' or a.address.startswith('fe80::1'))
        ]

        if ipv4s or ipv6s:
            result[iface] = {
                'ipv4': ipv4s,
                'ipv6': ipv6s
            }

    return result

        
def check_ip_is_private(ip_str):
    try:
        # Create an IP address object (works for both IPv4 and IPv6)
        ip_obj = ipaddress.ip_address(ip_str)
    
        if ip_obj.is_private:
            return(f"True")
        else:
            return(f"False")
    except ValueError:
        return(f" is not a valid IP address.")

def fetch_light_scope_info(url="https://thelightscope.com/ipinfo"):
    try:
        resp = requests.get(url, timeout=10)  # Increased timeout from 5 to 10 seconds
        resp.raise_for_status()
        data = resp.json()

        # Top-level
        queried_ip = data.get("queried_ip")

        # Drill into the asn and location and company buckets:
        asn_rec      = data["results"].get("asn",      {}).get("record", {})
        loc_rec      = data["results"].get("location",  {}).get("record", {})
        company_rec  = data["results"].get("company",   {}).get("record", {})

        return {
            "queried_ip": queried_ip,
            "ASN":         asn_rec.get("asn"),
            "domain":      asn_rec.get("domain"),
            "city":        loc_rec.get("city"),
            "country":     loc_rec.get("country"),
            "as_type":     company_rec.get("as_type"),
            "type":        asn_rec.get("type")
        }
    except requests.exceptions.Timeout:
        ###print("Warning: Timeout fetching external network information. Using fallback values.")
        return {
            "queried_ip": "0.0.0.0",
            "ASN": "unknown",
            "domain": "unknown",
            "city": "unknown",
            "country": "unknown",
            "as_type": "unknown",
            "type": "unknown"
        }
    except requests.exceptions.RequestException as e:
        ###print(f"Warning: Network error fetching external network information: {e}. Using fallback values.")
        return {
            "queried_ip": "0.0.0.0",
            "ASN": "unknown",
            "domain": "unknown",
            "city": "unknown",
            "country": "unknown",
            "as_type": "unknown",
            "type": "unknown"
        }
    except Exception as e:
        ###print(f"Warning: Unexpected error fetching external network information: {e}. Using fallback values.")
        return {
            "queried_ip": "0.0.0.0",
            "ASN": "unknown",
            "domain": "unknown",
            "city": "unknown",
            "country": "unknown",
            "as_type": "unknown",
            "type": "unknown"
        }



def lightscope_run():
    if  platforminfo.system() != "Windows":
        from systemd import daemon
        
        config_reader = configuration_reader()
        config_settings = config_reader.get_config()
        system_info = get_system_info()
        external_network_information = fetch_light_scope_info()

         # begin honeypot
        # Create shared memory for honeypot ports (accessible by all processes)
        import multiprocessing
        manager = multiprocessing.Manager()
        shared_open_honeypots = manager.list()  # Shared list of open honeypot ports
        
        top_unwanted_ports_consumer, top_unwanted_ports_producer = multiprocessing.Pipe(duplex=False)
        hp_upload_consumer, hp_upload_producer = multiprocessing.Pipe(duplex=False)

        hp_proc = multiprocessing.Process(
            target=_honeypot_worker,
            args=(top_unwanted_ports_consumer, shared_open_honeypots, hp_upload_producer, external_network_information, config_settings, system_info),
            daemon=True
        )
        hp_uploader = multiprocessing.Process(
            target=send_honeypot_data,
            args=(hp_upload_consumer,),
            name="honeypot_uploader"
        )
        hp_proc.start()
        hp_uploader.start()
        # end honeypot

        # helper to spawn the three subprocesses for one interface
        def spawn_for_interface_mac_linux(iface, internal_ips, top_unwanted_ports_producer, shared_open_honeypots):
            # 1) make the two duplex pipes
            unproc_consumer, unproc_producer = multiprocessing.Pipe(duplex=True)
            up_consumer, up_producer     = multiprocessing.Pipe(duplex=False)

            port_status = Ports(
                up_producer,
                internal_ips,
                False,              # internal == external
                iface,
                external_network_information,
                config_settings,
                system_info,
                top_unwanted_ports_producer,
                shared_open_honeypots
            )

            p_lscope = multiprocessing.Process(
                target=port_status.packet_handler,
                args=(unproc_consumer,),
                name=f"lightscope[{iface}]"
            )
            p_reader = multiprocessing.Process(
                target=read_from_interface_mac_linux,
                args=(iface, unproc_producer),
                name=f"reader[{iface}]"
            )
            p_uploader = multiprocessing.Process(
                target=send_data,
                args=(up_consumer,),
                name=f"uploader[{iface}]"
            )

            for p in (p_lscope, p_reader, p_uploader):
                p.start()

            return {
                "internal_ips":           internal_ips,
                "pipes": {
                    "unprocessed": (unproc_consumer, unproc_producer),
                    "upload":      (up_consumer, up_producer),
                },
                "lightscope_process":         p_lscope,
                "read_from_interface_process": p_reader,
                "upload_process":             p_uploader,
            }

        # --- initial discovery & spawn ---
        interfaces_and_ips = choose_mac_linux_interface()
        processes_per_interface = {}
        for iface, ips in interfaces_and_ips.items():
            print(f"Spawning processes for {iface}: {ips}")
            processes_per_interface[iface] = spawn_for_interface_mac_linux(iface, ips,top_unwanted_ports_producer, shared_open_honeypots)

        print("Live interfaces:", list(processes_per_interface))

        # --- monitor loop ---
        while True:
            time.sleep(60)  # Check every 60 seconds instead of busy waiting
            
            new_mapping = choose_mac_linux_interface()
            old_ifaces = set(interfaces_and_ips)
            new_ifaces = set(new_mapping)
            
            # Try to update external network information, but don't crash if it fails
            try:
                external_network_information = fetch_light_scope_info()
            except Exception as e:
                print(f"Warning: Failed to update external network information: {e}. Continuing with previous values.")
                # Continue with existing external_network_information

            # 1) clean up removed interfaces
            for gone in old_ifaces - new_ifaces:
                print(f"[+] Interface {gone!r} went away, terminating its processes")
                ctx = processes_per_interface.pop(gone)
                for pname in ("lightscope_process", "read_from_interface_process", "upload_process"):
                    p = ctx[pname]
                    if p.is_alive():
                        p.terminate()
                        p.join(timeout=1)
                interfaces_and_ips.pop(gone)

            # 2) detect interfaces whose IP list changed
            for same in old_ifaces & new_ifaces:
                old_ips = interfaces_and_ips[same]
                new_ips = new_mapping[same]
                if old_ips != new_ips:
                    print(f"[+] Interface {same!r} IPs changed {old_ips} -> {new_ips}; restarting")
                    # terminate old procs
                    ctx = processes_per_interface.pop(same)
                    for pname in ("lightscope_process", "read_from_interface_process", "upload_process"):
                        p = ctx[pname]
                        if p.is_alive():
                            p.terminate()
                            p.join(timeout=1)
                    interfaces_and_ips.pop(same)
                    # spawn fresh
                    processes_per_interface[same] = spawn_for_interface_mac_linux(same, new_ips, top_unwanted_ports_producer, shared_open_honeypots)
                    interfaces_and_ips[same] = new_ips

            # 3) spawn any brand new interfaces
            for born in new_ifaces - old_ifaces:
                ips = new_mapping[born]
                print(f"[+] New interface {born!r} with IPs {ips}: spawning")
                processes_per_interface[born] = spawn_for_interface_mac_linux(born, ips, top_unwanted_ports_producer, shared_open_honeypots)
                interfaces_and_ips[born] = ips

            # (optionally) print status
            #print("-> active interfaces:", list(processes_per_interface.keys()))





    if  platforminfo.system() == "Windows":
        config_reader = configuration_reader()
        config_settings = config_reader.get_config()
        system_info = get_system_info()
        external_network_information = fetch_light_scope_info()

        # begin honeypot  
        # Create shared memory for honeypot ports (accessible by all processes)
        import multiprocessing
        manager = multiprocessing.Manager()
        shared_open_honeypots = manager.list()  # Shared list of open honeypot ports
        
        top_unwanted_ports_consumer, top_unwanted_ports_producer = multiprocessing.Pipe(duplex=False)
        hp_upload_consumer, hp_upload_producer = multiprocessing.Pipe(duplex=False)
        
        hp_proc = multiprocessing.Process(
            target=_honeypot_worker,
            args=(top_unwanted_ports_consumer, shared_open_honeypots, hp_upload_producer, external_network_information, config_settings, system_info),
            daemon=True
        )
        hp_uploader = multiprocessing.Process(
            target=send_honeypot_data,
            args=(hp_upload_consumer,),
            name="honeypot_uploader"
        )
        hp_proc.start()
        hp_uploader.start()
        # end honeypot

        # helper to spawn the three subprocesses for one interface
        def spawn_for_interface_windows(iface, internal_ips):
            # 1) make the two duplex pipes
            unproc_consumer, unproc_producer = multiprocessing.Pipe(duplex=True)
            up_consumer, up_producer     = multiprocessing.Pipe(duplex=False)

            port_status = Ports(
                up_producer,
                internal_ips,
                False,              # internal == external
                iface,
                external_network_information,
                config_settings,
                system_info,
                top_unwanted_ports_producer,
                shared_open_honeypots
            )

            p_lscope = multiprocessing.Process(
                target=port_status.packet_handler,
                args=(unproc_consumer,),
                name=f"lightscope[{iface}]"
            )
            p_reader = multiprocessing.Process(
                target=read_from_interface_windows,
                args=(iface, unproc_producer),
                name=f"reader[{iface}]"
            )
            p_uploader = multiprocessing.Process(
                target=send_data,
                args=(up_consumer,),
                name=f"uploader[{iface}]"
            )

            for p in (p_lscope, p_reader, p_uploader):
                p.start()

            return {
                "internal_ips":           internal_ips,
                "pipes": {
                    "unprocessed": (unproc_consumer, unproc_producer),
                    "upload":      (up_consumer, up_producer),
                },
                "lightscope_process":         p_lscope,
                "read_from_interface_process": p_reader,
                "upload_process":             p_uploader,
            }

        # --- initial discovery & spawn ---
        interfaces_and_ips = choose_windows_interface()
        processes_per_interface = {}
        for iface, ips in interfaces_and_ips.items():
            print(f"Spawning processes for {iface}: {ips}")
            processes_per_interface[iface] = spawn_for_interface_windows(iface, ips)

        print("Live interfaces:", list(processes_per_interface))

        # --- monitor loop ---
        while True:
            time.sleep(60)

            # Try to update external network information, but don't crash if it fails
            try:
                external_network_information = fetch_light_scope_info()
            except Exception as e:
                print(f"Warning: Failed to update external network information: {e}. Continuing with previous values.")
                # Continue with existing external_network_information
                
            new_mapping = choose_windows_interface()
            old_ifaces = set(interfaces_and_ips)
            new_ifaces = set(new_mapping)

            # 1) clean up removed interfaces
            for gone in old_ifaces - new_ifaces:
                print(f"[+] Interface {gone!r} went away, terminating its processes")
                ctx = processes_per_interface.pop(gone)
                for pname in ("lightscope_process", "read_from_interface_process", "upload_process"):
                    p = ctx[pname]
                    if p.is_alive():
                        p.terminate()
                        p.join(timeout=1)
                interfaces_and_ips.pop(gone)

            # 2) detect interfaces whose IP list changed
            for same in old_ifaces & new_ifaces:
                old_ips = interfaces_and_ips[same]
                new_ips = new_mapping[same]
                if old_ips != new_ips:
                    print(f"[+] Interface {same!r} IPs changed {old_ips} -> {new_ips}; restarting")
                    # terminate old procs
                    ctx = processes_per_interface.pop(same)
                    for pname in ("lightscope_process", "read_from_interface_process", "upload_process"):
                        p = ctx[pname]
                        if p.is_alive():
                            p.terminate()
                            p.join(timeout=1)
                    interfaces_and_ips.pop(same)
                    # spawn fresh
                    processes_per_interface[same] = spawn_for_interface_windows(same, new_ips)
                    interfaces_and_ips[same] = new_ips

            # 3) spawn any brand new interfaces
            for born in new_ifaces - old_ifaces:
                ips = new_mapping[born]
                print(f"[+] New interface {born!r} with IPs {ips}: spawning")
                processes_per_interface[born] = spawn_for_interface_windows(born, ips)
                interfaces_and_ips[born] = ips

            # (optionally) print status
            #print("-> active interfaces:", list(processes_per_interface.keys()))
    



def get_system_info():
        system_info = {
                "System": platforminfo.system(),
                "Release": platforminfo.release(),
                "Version": platforminfo.version(),
                "Machine": platforminfo.machine(),
                "Total_Memory": f"{psutil.virtual_memory().total / (1024 ** 3):.2f} GB",
                'processor'    : platforminfo.processor(),
                'architecture' : platforminfo.architecture()[0]
                #'uname'        : platform.uname()._asdict()
        }

        return system_info

class configuration_reader:
    def __init__(self, config_file='config.ini'):
        # Default values
        #this is the value in the config file
        self.database = "uninitialized"
        self.self_telnet_and_ssh_honeypot_ports_to_forward=[]
        self.osinfo=""
        self.lookup_network_information_list={}
        self.autoupdate=""
        self.randomization_key="uninitialized"
        self.initialize_config("config.ini")
        self.load_config(config_file)
        print(f"***SAVE THIS URL:To view your lightscope reports, please visit https://thelightscope.com/tables/{self.database}")


    def get_config(self):
        config={'database':self.database,'self_telnet_and_ssh_honeypot_ports_to_forward':self.self_telnet_and_ssh_honeypot_ports_to_forward,
        'autoupdate':self.autoupdate,'randomization_key':self.randomization_key}
        return config

    
    def load_config(self, config_file):

        config = configparser.ConfigParser()
        config.read(config_file)
        # Assuming all configuration is under the [Settings] section.
        if 'Settings' in config:
            self.database = config.get('Settings', 'database', fallback="Can't read config").lower()
            self.randomization_key=config.get('Settings', 'randomization_key', fallback="Can't read config").lower()
            self.autoupdate=config.get('Settings', 'autoupdate', fallback="Can't read config").lower()
            self.self_telnet_and_ssh_honeypot_ports_to_forward=config.get('Settings', 'self_telnet_and_ssh_honeypot_ports_to_forward', fallback=[])



                
    def initialize_config(self,config_file):
        # Create a ConfigParser object and read the file (if it exists)
        config = configparser.ConfigParser()
        if os.path.exists(config_file):
            config.read(config_file)
        else:
            # If the file doesn't exist, create it with a default [Settings] section.
            config.add_section('Settings')

        # Ensure the "Settings" section exists.
        if not config.has_section('Settings'):
            config.add_section('Settings')

        # Check for the 'database' option. Priority order:
        # 1. Environment variable LIGHTSCOPE_DB_NAME (set by systemd during installation)
        # 2. Existing value in config file
        # 3. Generate new one if neither exists
        env_db_name = os.environ.get('LIGHTSCOPE_DB_NAME', '').strip()
        if env_db_name:
            # Use database name from environment (systemd service)
            config['Settings']['database'] = env_db_name
            print(f"Using database name from environment: {env_db_name}")
        elif 'database' not in config['Settings'] or not config['Settings']['database'].strip():
            # Generate new database name only if not in environment and not in config
            today = datetime.date.today().strftime("%Y%m%d")        # 8 chars
            max_len = 63                                   # leave room under 64
            rand_len = max_len - len(today) - 1            # "-1" for the underscore
            rand_part = ''.join(random.choices(string.ascii_lowercase, k=rand_len))
            config['Settings']['database'] = f"{today}_{rand_part}"
            print(f"Database not found; generated random database name: {config['Settings']['database']}")
        else:
            # Use existing database name from config file
            print(f"Using existing database name from config: {config['Settings']['database']}")


        # Check for the 'randomization_key' option.
        if 'randomization_key' not in config['Settings'] or not config['Settings']['randomization_key'].strip():
            randomization_key="randomization_key_"+''.join(random.choices(string.ascii_lowercase, k=46))
            config['Settings']['randomization_key'] = randomization_key
            print(f"randomization_key not found; generated random randomization_key name: {randomization_key}")


        # Check for the 'self_telnet_and_ssh_honeypot_ports_to_forward' option.
        if 'self_telnet_and_ssh_honeypot_ports_to_forward' not in config['Settings'] or not config['Settings']['self_telnet_and_ssh_honeypot_ports_to_forward'].strip():
            self_telnet_and_ssh_honeypot_ports_to_forward="no"
            config['Settings']['self_telnet_and_ssh_honeypot_ports_to_forward'] = self_telnet_and_ssh_honeypot_ports_to_forward
            print(f"self_telnet_and_ssh_honeypot_ports_to_forward not found; generated : {self_telnet_and_ssh_honeypot_ports_to_forward}")

        # Check for the 'autoupdate' option.
        if 'autoupdate' not in config['Settings'] or not config['Settings']['autoupdate'].strip():
            autoupdate="no"
            config['Settings']['autoupdate'] = autoupdate
            print(f"autoupdate not found; : {autoupdate}")


        # Optionally, you can also add the comment as a separate step manually 
        # (Comments are not preserved automatically by configparser when writing back.)
        # Write the configuration back to the file.
        with open(config_file, 'w') as f:
            config.write(f)
        print(f"Configuration updated and saved to {config_file}")
        


# -- Honeypot worker using pipes with service emulation and input logging -------------------------
def _honeypot_worker(top_unwanted_ports_consumer, shared_open_honeypots, hp_upload_producer, external_network_information, config_settings, system_info):
    try:
        import sys
        import traceback
        
        # Ensure all prints are immediately visible
        sys.stdout.flush()
        sys.stderr.flush()
        
        print(f"_honeypot_worker: Starting honeypot worker process", flush=True)
        
        sockets = {}  # socket -> port mapping
        service_map = {0:'HTTP',1:'SSH',2:'SMTP',3:'FTP',4:'TELNET',5:'POP3',6:'IMAP',7:'ECHO',8:'TIME',9:'DISCARD'}
        print(f"_honeypot_worker: started", flush=True)
        
        # Auto-rotation state
        next_rotation = time.time() + 4 * 60 * 60  # Start first rotation in 10 seconds for testing
        interface_port_counts = {}  # Track port counts per interface: {interface_name: {port: count}}
        interface_names = set()  # Track all interface names we've seen
        loop_count = 0  # Debug counter
        
        # Port history tracking - avoid reopening ports for 7 days
        program_start_time = time.time()
        history_clear_time = program_start_time + 7 * 24 * 60 * 60  # Clear history after 7 days
        previously_opened_ports = set()  # Track ports we've opened before
        
        def hash_segment(segment, key):
            """Hash a single byte segment with the given key."""
            return (segment + key) % 256
        
        def randomize_ip(ip_str, randomization_key=0x42):
            """
            Randomize an IPv4 or IPv6 address using the same logic as the main Ports class.
            """
            import ipaddress
            try:
                ip = ipaddress.ip_address(ip_str)
            except ValueError:
                return "HP"  # Fallback for invalid IPs
            
            # Operate on the raw bytes of the address
            orig_bytes = ip.packed  # Raw bytes of the IP
            
            # Hash each byte to new byte
            new_bytes = bytes(hash_segment(b, randomization_key) for b in orig_bytes)
            
            # Reconstruct an IP object from those bytes
            try:
                rand_ip = ipaddress.IPv4Address(new_bytes) if ip.version == 4 else ipaddress.IPv6Address(new_bytes)
                return str(rand_ip)
            except:
                return "HP"  # Fallback for any issues
        
        def update_shared_honeypot_ports():
            """Update the shared memory list with current open ports"""
            try:
                current_ports = list(sockets.values())
                shared_open_honeypots[:] = current_ports  # Replace all contents atomically
                print(f"_honeypot_worker: Updated shared ports: {current_ports}", flush=True)
            except Exception as e:
                print(f"_honeypot_worker: Error updating shared ports: {e}", flush=True)
        
        # Define priority ports to open first
        priority_ports = [2323, 6379, 8080, 5555, 17001, 2222, 12281, 8728, 1024]
        
        # Open initial ports (priority first, then random if needed)
        import random
        initial_ports = priority_ports.copy()
        
        # If we need more than priority ports, add random ones
        if len(initial_ports) < 10:
            additional_needed = 10 - len(initial_ports)
            available_random = [p for p in range(1024, 65536) if p not in priority_ports]
            initial_ports.extend(random.sample(available_random, min(additional_needed, len(available_random))))
        
        print(f"_honeypot_worker: initial_ports: {initial_ports}", flush=True)
        
        # Try to open initial ports
        for port in initial_ports:
            try:
                s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                s.bind(("", port))
                s.listen()
                sockets[s] = port
                previously_opened_ports.add(port)  # Track this port in history
                print(f"_honeypot_worker: Initial startup port {port} opened successfully", flush=True)
            except Exception as e:
                print(f"_honeypot_worker: Failed to open initial port {port}: {e}", flush=True)
                import os
                try:
                    print(f"_honeypot_worker: Running as UID {os.getuid()}, GID {os.getgid()}", flush=True)
                except:
                    print(f"_honeypot_worker: Could not get UID/GID", flush=True)
                if port < 1024:
                    print(f"_honeypot_worker: Port {port} < 1024 requires root or CAP_NET_BIND_SERVICE", flush=True)
        
        # Update shared memory with initial ports
        print(f"_honeypot_worker: Opened {len(sockets)} ports initially", flush=True)
        update_shared_honeypot_ports()

        def prepare_honeypot_connection_data(sport, service, ipsrc,dport):
            """
            Process honeypot connection data for upload - structured like prepare_synack_data
            This function prepares honeypot connection data in the same format as regular lightscope data
            """
            
            # =============================================================================
            # BASIC RECORD IDENTIFICATION
            # =============================================================================
            db_name = config_settings['database']          # Use actual database name like in prepare_synack_data
            system_time = str(connection_start_time)
            
            # =============================================================================
            # IP HEADER FIELDS (Simulated for honeypot connections)
            # =============================================================================
            ip_version = "HP"                             # Honeypot marker
            ip_ihl = "HP"                                 # Honeypot marker
            ip_tos = "HP"                                 # Honeypot marker
            ip_len = "HP"                                 # Honeypot marker
            ip_id = "HP"                                  # Honeypot marker
            ip_flags = "HP"                               # Honeypot marker
            ip_frag = "HP"                                # Honeypot marker
            ip_ttl = "HP"                                 # Honeypot marker
            ip_proto = "HP"                               # Honeypot marker
            ip_chksum = "HP"                              # Honeypot marker
            ip_src = ipsrc                            # Source IP (attacker)
            ip_dst_randomized = external_network_information.get("ip", "HP")  # Destination (our honeypot)
            ip_options = "HP"                             # Honeypot marker
            
            # =============================================================================
            # TCP HEADER FIELDS (Simulated for honeypot connections)
            # =============================================================================
            tcp_sport = str(sport)                  # Source port (attacker)
            tcp_dport = str(dport)                         # Destination port (honeypot service)
            tcp_seq = 0                                   # Use 0 for honeypot data (database expects INT UNSIGNED)
            tcp_ack = "HP"                                # Honeypot marker
            tcp_dataofs = "HP"                            # Honeypot marker
            tcp_reserved = "HP"                           # Honeypot marker
            tcp_flags = "HP"                              # Honeypot marker
            tcp_window = "HP"                             # Honeypot marker
            tcp_chksum = "HP"                             # Honeypot marker
            tcp_urgptr = "HP"                             # Honeypot marker
            tcp_options = "HP"                            # Honeypot marker
            
            # =============================================================================
            # EXTERNAL NETWORK INFORMATION (Use actual values when available)
            # =============================================================================
            ext_dst_ip_country = external_network_information.get("country", "HP")
            network_type = external_network_information.get("type", "HP")  # Use actual type like prepare_unwanted_syn_data
            ASN = str(external_network_information.get("ASN", "HP"))  # Match key from prepare_synack_data
            domain = external_network_information.get("domain", "HP")
            city = external_network_information.get("city", "HP")
            as_type = external_network_information.get("as_type", "HP")  # Use actual value when available
            
            # =============================================================================
            # NETWORK CLASSIFICATION (Use actual functions like in prepare_synack_data)
            # =============================================================================
            ip_dst_is_private = "HP"                      # Could check if honeypot server is private
            external_is_private = "HP"                    # Could check if external IP is private
            
            # =============================================================================
            # PORT INFORMATION
            # =============================================================================
            open_ports = f""                     # Format: port x connection_count
            previously_open_ports = ""                   # Empty like in prepare_synack_data when no history
            
            # =============================================================================
            # INTERFACE AND IP INFORMATION
            # =============================================================================
            interface = "honeypot_global"                 # Descriptive interface name
            internal_ip_randomized = "HP"                # Mark as honeypot data
            # Randomize external IP using same logic as main Ports class
            external_ip = external_network_information.get("ip", "HP")
            if external_ip != "HP":
                try:
                    import ipaddress
                    ip = ipaddress.ip_address(external_ip)
                    randomization_key = 0x42  # Same key as main class
                    orig_bytes = ip.packed
                    new_bytes = bytes((b + randomization_key) % 256 for b in orig_bytes)
                    rand_ip = ipaddress.IPv4Address(new_bytes) if ip.version == 4 else ipaddress.IPv6Address(new_bytes)
                    external_ip_randomized = str(rand_ip)
                except:
                    external_ip_randomized = "HP"  # Fallback for any issues
            else:
                external_ip_randomized = "HP"
            
            # =============================================================================
            # SYSTEM INFORMATION (Match prepare_synack_data key names)
            # =============================================================================
            System_info = system_info.get("System", "HP")
            Release_info = system_info.get("Release", "HP")
            Version_info = system_info.get("Version", "HP")
            Machine_info = system_info.get("Machine", "HP")
            Total_Memory = str(system_info.get("Total_Memory", "HP"))
            processor = system_info.get("processor", "HP")
            architecture = system_info.get("architecture", "HP")
            
            # =============================================================================
            # HONEYPOT SPECIFIC INFORMATION
            # =============================================================================
            honeypot_status = "True"                      # Mark as honeypot data
            
            # Detailed payload with connection information
            payload_info = {

            }
            payload = f"{service}"
            
            # =============================================================================
            # RETURN STRUCTURED DATA PAYLOAD
            # =============================================================================
            return {
                # Basic identification
                "db_name": db_name,
                "system_time": system_time,
                
                # IP header fields
                "ip_version": ip_version,
                "ip_ihl": ip_ihl,
                "ip_tos": ip_tos,
                "ip_len": ip_len,
                "ip_id": ip_id,
                "ip_flags": ip_flags,
                "ip_frag": ip_frag,
                "ip_ttl": ip_ttl,
                "ip_proto": ip_proto,
                "ip_chksum": ip_chksum,
                "ip_src": ip_src,
                "ip_dst_randomized": ip_dst_randomized,
                "ip_options": ip_options,
                
                # TCP header fields
                "tcp_sport": tcp_sport,
                "tcp_dport": tcp_dport,
                "tcp_seq": tcp_seq,
                "tcp_ack": tcp_ack,
                "tcp_dataofs": tcp_dataofs,
                "tcp_reserved": tcp_reserved,
                "tcp_flags": tcp_flags,
                "tcp_window": tcp_window,
                "tcp_chksum": tcp_chksum,
                "tcp_urgptr": tcp_urgptr,
                
                # External network info
                "ext_dst_ip_country": ext_dst_ip_country,
                "type": network_type,
                "ASN": ASN,
                "domain": domain,
                "city": city,
                "as_type": as_type,
                
                # Network classification
                "ip_dst_is_private": ip_dst_is_private,
                "external_is_private": external_is_private,
                
                # Port information
                "open_ports": open_ports,
                "previously_open_ports": previously_open_ports,
                "tcp_options": tcp_options,
                
                # Interface and IP info
                "interface": interface,
                "internal_ip_randomized": internal_ip_randomized,
                "external_ip_randomized": external_ip_randomized,
                
                # System information
                "System_info": System_info,
                "Release_info": Release_info,
                "Version_info": Version_info,
                "Machine_info": Machine_info,
                "Total_Memory": Total_Memory,
                "processor": processor,
                "architecture": architecture,
                
                # Honeypot specific
                "honeypot_status": honeypot_status,
                "payload": payload,
                "ls_version": ls_version  # Use global ls_version variable
            }

        def rotate_honeypots():
            """Auto-rotate to top 10 ports based on collected data"""
            try:
                print(f"_honeypot_worker: Starting rotation. interface_port_counts has {len(interface_port_counts)} interfaces", flush=True)
                
                # Aggregate port counts from all interfaces
                aggregated_counts = {}
                for interface_name, port_counts in interface_port_counts.items():
                    print(f"_honeypot_worker: Interface {interface_name} has {len(port_counts)} port entries", flush=True)
                    for port, count in port_counts.items():
                        aggregated_counts[port] = aggregated_counts.get(port, 0) + count
                
                print(f"_honeypot_worker: Total aggregated ports: {len(aggregated_counts)}", flush=True)
                if aggregated_counts:
                    print(f"_honeypot_worker: Top 5 ports: {sorted(aggregated_counts.items(), key=lambda x: x[1], reverse=True)[:5]}", flush=True)
                
                # Get top ports > 1023, filter out system ports and previously opened ports
                valid_ports = {p: c for p, c in aggregated_counts.items() if p > 1023}
                print(f"_honeypot_worker: Valid ports (>1023): {len(valid_ports)}", flush=True)
                
                # Filter out previously opened ports from top targets
                available_ports = {p: c for p, c in valid_ports.items() if p not in previously_opened_ports}
                if len(available_ports) < len(valid_ports):
                    filtered_count = len(valid_ports) - len(available_ports)
                    print(f"_honeypot_worker: Filtered out {filtered_count} previously opened ports from traffic analysis", flush=True)
                
                # Use available ports if we have enough, otherwise fall back to all valid ports
                ports_to_use = available_ports if len(available_ports) >= 5 else valid_ports
                top_ports = sorted(ports_to_use.items(), key=lambda x: x[1], reverse=True)[:10]
                target_ports = [p for p, _ in top_ports]
                
                print(f"_honeypot_worker: Target ports from traffic: {target_ports}", flush=True)
                
                # If first run or insufficient data, fill with priority ports first, then random
                if len(target_ports) < 10:
                    import random
                    # Priority ports to prefer when data is insufficient
                    priority_ports = [2323, 6379, 8080, 5555, 17001, 2222, 12281, 8728, 1024]
                    existing = set(target_ports)
                    
                    # First add priority ports that aren't already in target_ports and haven't been used recently
                    available_priority = [p for p in priority_ports if p not in existing and p not in previously_opened_ports]
                    needed = 10 - len(target_ports)
                    
                    # Add priority ports first
                    priority_to_add = available_priority[:needed]
                    target_ports.extend(priority_to_add)
                    
                    # If still need more ports after priority, add random ones (avoiding previously opened)
                    still_needed = 10 - len(target_ports)
                    if still_needed > 0:
                        all_existing = set(target_ports)
                        available_random = [p for p in range(1024, 65536) if p not in all_existing and p not in previously_opened_ports]
                        if len(available_random) >= still_needed:
                            random_ports = random.sample(available_random, still_needed)
                            target_ports.extend(random_ports)
                            print(f"_honeypot_worker: Added {len(priority_to_add)} priority ports and {len(random_ports)} random ports: priority={priority_to_add}, random={random_ports}", flush=True)
                        else:
                            # If we can't avoid all previously opened ports, use what we can
                            all_available = [p for p in range(1024, 65536) if p not in all_existing]
                            random_ports = random.sample(all_available, min(still_needed, len(all_available)))
                            target_ports.extend(random_ports)
                            print(f"_honeypot_worker: Added {len(priority_to_add)} priority ports and {len(random_ports)} random ports (some may be reused): priority={priority_to_add}, random={random_ports}", flush=True)
                    else:
                        print(f"_honeypot_worker: Added {len(priority_to_add)} priority ports: {priority_to_add}", flush=True)   
                
                current_ports = set(sockets.values())
                to_open = set(target_ports) - current_ports
                to_close = current_ports - set(target_ports)
                
                print(f"_honeypot_worker: Current ports: {current_ports}", flush=True)
                print(f"_honeypot_worker: Target ports: {set(target_ports)}", flush=True)
                print(f"_honeypot_worker: Ports to open: {to_open}", flush=True)
                print(f"_honeypot_worker: Ports to close: {to_close}", flush=True)
                
                # Close old ports
                for port in to_close:
                    for s, p in list(sockets.items()):
                        if p == port:
                            try: s.close(); del sockets[s]
                            except: pass
                            print(f"_honeypot_worker: Closed port {port}", flush=True)
                
                # Open new ports  
                for port in to_open:
                    try:
                        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                        s.bind(("", port))
                        s.listen()
                        sockets[s] = port
                        previously_opened_ports.add(port)  # Track this port in history
                        print(f"_honeypot_worker: Auto-opened port {port}", flush=True)
                    except Exception as e:
                        print(f"_honeypot_worker: Failed to auto-open port {port}: {e}", flush=True)

                update_shared_honeypot_ports()
                interface_port_counts.clear()  # Reset for next cycle
                print(f"_honeypot_worker: Rotation complete. Active sockets: {len(sockets)}", flush=True)
            except Exception as e:
                print(f"_honeypot_worker: Error in rotate_honeypots: {e}", flush=True)
                traceback.print_exc()

        print(f"_honeypot_worker: Starting main loop", flush=True)
        
        while True:
            try:
                now = time.time()
                loop_count += 1
                
                # Debug: print every 1000 loops to show we're running
                if loop_count % 1000 == 0:
                    print(f"_honeypot_worker: Loop {loop_count}, now={now:.1f}, next_rotation={next_rotation:.1f}, diff={next_rotation-now:.1f}, history_size={len(previously_opened_ports)}, active_sockets={len(sockets)}", flush=True)
                
                # Collect port count data from all interfaces (new format: interface_name, port_counts)
                while top_unwanted_ports_consumer.poll():
                    try:
                        data = top_unwanted_ports_consumer.recv()
                        if isinstance(data, tuple) and len(data) == 2:
                            interface_name, port_data = data
                            if isinstance(port_data, dict):
                                # Store/overwrite port counts for this interface
                                interface_port_counts[interface_name] = port_data.copy()
                                interface_names.add(interface_name)
                                ###print(f"_honeypot_worker: Updated port counts for {interface_name}: {len(port_data)} ports", flush=True)
                        elif isinstance(data, dict):
                            # Handle old format for compatibility
                            interface_port_counts["unknown"] = data.copy()
                            interface_names.add("unknown")
                    except Exception as e:
                        print(f"_honeypot_worker: Error processing port count data: {e}", flush=True)
                
                # Check if we need to clear port history (after 7 days)
                if now >= history_clear_time:
                    print(f"_honeypot_worker: Clearing port history after 7 days. Previously opened: {len(previously_opened_ports)} ports", flush=True)
                    previously_opened_ports.clear()
                    history_clear_time = now + 7 * 24 * 60 * 60  # Reset for another 7 days
                
                # Auto-rotate every 4 hours
                if now >= next_rotation:
                    print(f"\n\n _honeypot_worker: Rotating honeypots\n\n", flush=True)    
                    rotate_honeypots()
                    next_rotation = now + 4 * 60 * 60  # Rotate every 4 hours

                # 2) accept & emulate
                if sockets:
                    try:
                        ready, _, _ = select.select(list(sockets), [], [], 1.0)
                       
                        for sock in ready:
                            try:
                                connection_start_time = time.time()
                                
                                local_conn, addr = sock.accept()

                                port = sockets[sock]
                                # Even ports use SSH, odd ports use TELNET
                                if port % 2 == 0:
                                    svc = 'SSH'
                                else:
                                    svc = 'TELNET'

                                print(f"_honeypot_worker: Received connection from {addr[0]}:{addr[1]} to port {port} (service: {svc})", flush=True)

                                # only proxy SSH and TELNET
                                if svc in ('SSH', 'TELNET'):
                                    remote_host = "128.9.28.79"
                                    # map to your Docker host ports:
                                    if svc == 'SSH':
                                        connect_port = 12345    # host→container2222
                                    else:  # TELNET
                                        connect_port = 12346    # host→container2223

                                    remote_conn = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                                    remote_conn.settimeout(30.0)
                                    try:
                                        remote_conn.connect((remote_host, connect_port))
                                    except Exception as e:
                                        print(f"_honeypot_worker: proxy connect failed for {svc} on port {port}: {e}", flush=True)
                                        local_conn.close()
                                        continue

                                    # send PROXY header - format: PROXY TCP4 src_ip dest_ip src_port dest_port
                                    # Get the local IP that the client connected to
                                    local_ip = local_conn.getsockname()[0]
                                    #hdr = f"PROXY TCP4 {addr[0]} {local_ip} {addr[1]} {port}\r\n"
                                    hdr = f"PROXY TCP4 {addr[0]} {config_settings['database']} {addr[1]} {port}\r\n"
                                    print(f"_honeypot_worker: Sending PROXY header: {hdr.strip()}", flush=True)
                                    remote_conn.sendall(hdr.encode())

                                    # bi-directional forwarding
                                    def forward(src, dst, direction="unknown"):
                                        try:
                                            while True:
                                                buf = src.recv(4096)
                                                if not buf:
                                                    print(f"_honeypot_worker: {direction} connection closed normally", flush=True)
                                                    break
                                                dst.sendall(buf)
                                        except Exception as e:
                                            print(f"_honeypot_worker: {direction} forwarding error: {e}", flush=True)
                                        finally:
                                            for s in (src, dst):
                                                try: s.close()
                                                except: pass

                                    import threading
                                    threading.Thread(target=forward, args=(local_conn, remote_conn, f"client->server({svc})"), daemon=True).start()
                                    threading.Thread(target=forward, args=(remote_conn, local_conn, f"server({svc})->client"), daemon=True).start()

                                    try:
                                        honeypot_data = prepare_honeypot_connection_data(addr[1], svc, addr[0], port)
                                        
                                        hp_upload_producer.send(honeypot_data)
                                        print(f"_honeypot_worker: Sent honeypot data for {addr[0]}:{addr[1]} -> {port} ({svc})", flush=True)
                                    except Exception as e:
                                        print(f"_honeypot_worker: Failed to send honeypot data: {e}", flush=True)
                                        traceback.print_exc()

                                    print(f"_honeypot_worker: proxied {addr[0]}:{addr[1]} → {remote_host}:{connect_port} ({svc})", flush=True)
                                else:
                                    # Just close the connection for non-SSH/TELNET services
                                    local_conn.close()
                                    print(f"_honeypot_worker: Closed connection from {addr[0]}:{addr[1]} to port {port} (unsupported service)", flush=True)
                            except Exception as e:
                                print(f"_honeypot_worker: Error handling connection: {e}", flush=True)
                                traceback.print_exc()
                    except Exception as e:
                        print(f"_honeypot_worker: Error in select loop: {e}", flush=True)
                        traceback.print_exc()
                else:
                    time.sleep(1.0)
                    
            except Exception as e:
                print(f"_honeypot_worker: Error in main loop: {e}", flush=True)
                traceback.print_exc()
                time.sleep(1.0)  # Prevent tight error loop

    except Exception as e:
        print(f"_honeypot_worker: FATAL ERROR - Worker crashed: {e}", flush=True)
        import traceback
        traceback.print_exc()
        sys.stdout.flush()
        sys.stderr.flush()
        # Don't exit here, let the process manager handle it



if __name__ == '__main__':
    import multiprocessing
    multiprocessing.freeze_support()  # Optional, but safe
    lightscope_run()

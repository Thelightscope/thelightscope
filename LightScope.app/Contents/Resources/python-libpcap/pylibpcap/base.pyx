# -*- coding: utf-8 -*-
# @Author: JanKinCai
# @Date:   2019-09-10 12:53:07
# @Last Modified by:   jankincai
# @Last Modified time: 2024-09-26 14:17:31
import os
import time
from threading import Thread

from pylibpcap.utils import to_c_str, from_c_str, get_pcap_file
from pylibpcap.exception import LibpcapError


DEF BUFSIZ = 65535
DEF PCAP_VERSION_MAJOR = 2
DEF PCAP_VERSION_MINOR = 4
DEF PCAP_ERRBUF_SIZE = 256
DEF PCAP_IF_LOOPBACK = 0x00000001
DEF MODE_CAPT = 0
DEF MODE_STAT = 1

DEF PCAP_ERROR = -1
DEF PCAP_ERROR_BREAK = -2
DEF PCAP_ERROR_NOT_ACTIVATED = -3
DEF PCAP_ERROR_ACTIVATED = -4
DEF PCAP_ERROR_NO_SUCH_DEVICE = -5


cdef class BasePcap(object):
    """BasePcap

    :param path: Input file
    :param filters: BPF Filters, default ``""``
    :param mode: open model, default ``r``
    :param snaplen: Cut packet lenght, default ``65535``
    """

    def __init__(self, str path, mode="r", str filters="", int snaplen=65535, *args, **kwargs):
        """
        init
        """

        self.path = os.path.expanduser(self._to_c_str(path))
        self.filters = self._to_c_str(filters)
        self.snaplen = snaplen
        self.mode = mode
        self.handler = pcap_open_dead(1, self.snaplen);

        if mode == "r":
            self.in_pcap = pcap_open_offline(self.path, self.errbuf)

            if self.in_pcap == NULL:
                raise LibpcapError(self._from_c_str(self.errbuf))
        elif mode == "a":
            if not os.path.exists(path):
                # create file
                open(self.path, 'w').close()

            self.out_pcap = pcap_dump_open_append(self.handler, self.path)

            if self.out_pcap == NULL:
                raise LibpcapError(self.get_handler_error())
        elif mode == "w":
            # create file
            open(self.path, 'w').close()

            self.out_pcap = pcap_dump_open(self.handler, self.path)    

            if self.out_pcap == NULL:
                raise LibpcapError(self.get_handler_error())        

    def _to_c_str(self, v):
        """Python str to C str
        """

        return to_c_str(v)

    def _from_c_str(self, v):
        """C str to Python str
        """

        return from_c_str(v)

    def get_errbuf(self):
        """Get errbuf
        """

        return self._from_c_str(self.errbuf)

    @property
    def isr(self):
        """Is Read
        """

        return self.mode == "r"

    @property
    def isw(self):
        """
        Is Write
        """

        return self.mode == "a" or self.mode == "w"

    def get_handler_error(self):
        """handler error
        """

        return self._from_c_str(pcap_geterr(self.handler)) if self.handler != NULL else ""

    cdef void set_filter(self, pcap_t* p, char* filters):
        """
        Set BPF Filter
        """

        cdef bpf_program fp

        if pcap_compile(p, &fp, filters, 1, 0) == -1:
            raise LibpcapError("compile bpf_filter error.")
        if pcap_setfilter(p, &fp) == -1:
            raise LibpcapError("set bpf_filter error.")
        pcap_freecode(&fp)

    cdef void pcap_write_dump(self, pcap_pkthdr pkt_header, bytes buf):
        """
        pcap write dump

        :param pkt_header: pcap_pkthdr struct.
        :param buf: bytes.
        """

        pkt_header.caplen = len(buf)
        pkt_header.len = pkt_header.caplen
        pkt_header.ts.tv_sec = int(time.time());
        pcap_dump(<u_char*>self.out_pcap, &pkt_header, buf)

    cdef void pcap_next_dump(self, pcap_t* in_pcap, char* filters):
        """
        pcap next dump
        """

        cdef u_char* pkt
        cdef pcap_pkthdr pkt_header

        if filters:
            self.set_filter(in_pcap, filters)

        while 1:
            pkt = <u_char*>pcap_next(in_pcap, &pkt_header)

            if pkt == NULL:
                break

            pcap_dump(<u_char*>self.out_pcap, &pkt_header, pkt)

    cdef void pcap_next_dumps(self, str path):
        """
        pcap_next_dumps
        """

        cdef pcap_t* in_pcap = NULL

        for f in get_pcap_file(path):
            in_pcap = pcap_open_offline(self._to_c_str(f), self.errbuf)

            if in_pcap == NULL:
                raise LibpcapError(self.get_errbuf())

            self.pcap_next_dump(in_pcap, self.filters)
            pcap_close(in_pcap)

    def close(self):
        """
        close
        """

        if self.out_pcap:
            pcap_dump_flush(self.out_pcap)
            pcap_dump_close(self.out_pcap)
            self.out_pcap = NULL

        if self.in_pcap:
            pcap_close(self.in_pcap)
            self.in_pcap = NULL

    def __dealloc__(self):
        """
        free memory
        """

        self.close()


cdef class LibPcap(BasePcap):
    """
    Pcap
    """

    def write(self, v):
        """
        Write pcap
        """

        cdef pcap_pkthdr pkt_header

        if not self.isw:
            raise LibpcapError("Not write.")

        if isinstance(v, bytes):
            self.pcap_write_dump(pkt_header, v)
        else:
            for buf in v:
                if isinstance(buf, bytes):
                    self.pcap_write_dump(pkt_header, buf)

    def read(self):
        """
        Read pcap
        """

        cdef pcap_pkthdr pkt_header

        cdef u_char *pkt

        if not self.isr:
            raise LibpcapError("Not Read.")

        if self.filters:
            self.set_filter(self.in_pcap, self.filters)

        while 1:

            pkt = <u_char*>pcap_next(self.in_pcap, &pkt_header)

            if pkt == NULL:
                break

            yield pkt_header.caplen, pkt_header.ts.tv_sec, (<char *>pkt)[:pkt_header.caplen]

    def write_path(self, path):
        """
        Write path
        """

        return self.pcap_next_dumps(path)


class StatsObject(object):
    def __init__(self, capture_cnt, ps_recv, ps_drop, ps_ifdrop):
        self.capture_cnt = capture_cnt
        self.ps_recv = ps_recv
        self.ps_drop = ps_drop
        self.ps_ifdrop = ps_ifdrop


cdef class Sniff(BasePcap):
    """
    Capture packet

    :param iface: Iface
    :param count: Capture packet num, default ``-1``
    :param promisc: Promiscuous mode, default ``0``
    :param snaplen: Cut packet lenght, default ``65535``
    :param timeout: capture timeout, default ``0``
    :param filters: BPF filter rules, default ``""``
    :param out_file: Output pcap file, default ``""``
    """

    cdef object nonblocking_thread

    def __init__(self, str iface, int count=-1, int promisc=0, int snaplen=65535,
                 int timeout=0, str filters="", str out_file="", int monitor=-1, *args, **kwargs):
        """init
        """

        self.out_file = os.path.expanduser(self._to_c_str(out_file))
        self.filters = self._to_c_str(filters)
        self.iface = self._to_c_str(iface)
        self.count = count
        self.handler = pcap_create(self.iface, self.errbuf)
        self.capture_cnt = 0
        self.nonblocking_thread = 0

        # self.handler = pcap_open_live(self.iface, snaplen, promisc, 0, self.errbuf)

        pcap_set_snaplen(self.handler, snaplen)
        pcap_set_promisc(self.handler, promisc)
        pcap_set_timeout(self.handler, timeout)
        pcap_set_immediate_mode(self.handler, 1)

        #check and set monitor mode if available
        if monitor > 0:
            rfmon_available = pcap_can_set_rfmon(self.handler)

            if rfmon_available == 1:
                #monitor mode can be set, set it now
                rfmon_set = pcap_set_rfmon(self.handler, 1)
                if rfmon_set == PCAP_ERROR_ACTIVATED:
                    raise LibpcapError("Monitor Mode Unavailable, capture handle already activated")
                elif rfmon_set != 0:
                    raise LibpcapError("Monitor Mode Unavailable, A Unknown Error has occurred")

            #see pcap_can_set_rfmon(3) Man Page
            elif rfmon_available == 0:
                raise LibpcapError("Monitor Mode unavailable")
            elif rfmon_available == PCAP_ERROR_NO_SUCH_DEVICE:
                raise LibpcapError("Monitor Mode Is unavailable, Device specified when handle created does not exist. [PCAP_ERROR_NO_SUCH_DEVICE]")
            elif rfmon_available == PCAP_ERROR_ACTIVATED:
                raise LibpcapError("Error enabling Monitor Mode, capture handle already activated")
            elif rfmon_available == PCAP_ERROR:
                raise LibpcapError(self.get_handler_error())

        if pcap_activate(self.handler) != 0:
            raise LibpcapError(self.get_handler_error())

        # Set BPF filter
        if self.filters:
            self.set_filter(self.handler, self.filters)

        self.out_pcap = pcap_dump_open(self.handler, self.out_file) if out_file else NULL
    
    def capture_nonblocking_thread(self):
        """Code that runs in the thread
        """

        captured_packets = pcap_loop(self.handler, self.count, sniff_callback, <u_char*>self.out_pcap)
        if captured_packets != PCAP_ERROR_BREAK and captured_packets > 0:
            self.capture_cnt += captured_packets
        self.nonblocking_thread = 0

    def capture_nonblocking(self):
        """Start capturing packets in another thread
        """

        if not self.nonblocking_thread:
            self.nonblocking_thread = Thread(target = self.capture_nonblocking_thread)
            self.nonblocking_thread.start()

    def is_running_nonblocking(self):
        """Return whether there is a nonblocking capture thread is_running_nonblocking
        """
        return self.nonblocking_thread and self.nonblocking_thread.is_alive()

    
    def stop_capture_nonblocking(self):
        """Stop capturing packets in another thread (capture_nonblocking)
        """

        if self.nonblocking_thread:
            pcap_breakloop(self.handler)
            self.nonblocking_thread.join()
            self.nonblocking_thread = 0

    def capture(self):
        """Run capture packet
        """

        cdef pcap_pkthdr pkt_header

        count = self.count

        while count == -1 or count > 0:
            pkt = <u_char*>pcap_next(self.handler, &pkt_header)
            if pkt == NULL:
                # timeout
                yield 0, 0, b""
            else:
                if self.out_pcap != NULL:
                    pcap_dump(<u_char*>self.out_pcap, &pkt_header, pkt)

                self.capture_cnt += 1
                if count > 0:
                    count -= 1

                yield pkt_header.caplen, pkt_header.ts.tv_sec, (<char*>pkt)[:pkt_header.caplen]

    def stats(self):
        """stats
        """

        cdef pcap_stat ps

        if pcap_stats(self.handler, &ps) != 0:
            raise LibpcapError(self.get_handler_error())

        return StatsObject(self.capture_cnt, ps.ps_recv, ps.ps_drop, ps.ps_ifdrop)

    def close(self):
        """
        close
        """

        if self.out_pcap != NULL:
            pcap_dump_flush(self.out_pcap)
            pcap_dump_close(self.out_pcap)
            self.out_pcap = NULL

        if self.handler != NULL:
            pcap_close(self.handler)
            self.handler = NULL


cpdef str get_first_iface():
    """Get first iface
    """

    cdef char errbuf[PCAP_ERRBUF_SIZE]
    cdef char* iface

    iface = pcap_lookupdev(errbuf)

    return from_c_str(iface) if iface else ""


cpdef list get_iface_list():
    """Get iface list
    """

    cdef char errbuf[PCAP_ERRBUF_SIZE]
    cdef pcap_if_t *interfaces
    cdef pcap_if_t *temp
    cdef list iface_list = []

    if pcap_findalldevs(&interfaces, errbuf) == -1:
        return []

    temp = interfaces

    while temp:
        iface_list.append(temp.name.decode("utf-8"))
        temp = temp.next

    pcap_freealldevs(interfaces)

    return iface_list


cpdef bint send_packet(str iface, bytes buf):
    """
    Send raw packet
    """

    cdef char errbuf[PCAP_ERRBUF_SIZE]
    cdef bint status = False

    cdef pcap_t* handler = pcap_open_live(to_c_str(iface), 65535, 0, 0, errbuf)

    if handler == NULL:
        raise from_c_str(errbuf)

    if pcap_sendpacket(handler, buf, len(buf)) != -1:
        status = True

    pcap_close(handler)

    return status


cdef void sniff_callback(u_char *user, const pcap_pkthdr *pkt_header, const u_char *pkt_data):
    """
    """

    if user != NULL:
        pcap_dump(user, pkt_header, pkt_data)

# -*- coding: utf-8 -*-
# @Author: JanKinCai
# @Date:   2019-05-10 11:19:43
# @Last Modified by:   jankincai
# @Last Modified time: 2024-09-26 11:07:42

# https://docs.oracle.com/cd/E88353_01/html/E37845/pcap-3pcap.html


ctypedef unsigned int u_int
ctypedef unsigned char u_char
ctypedef unsigned int sa_family_t


cdef extern from "stdio.h":

    ctypedef struct FILE:
        pass


cdef extern from "sys/socket.h":

    struct sockaddr:
        sa_family_t sa_family
        char sa_data[14]


cdef extern from "pcap.h" nogil:

    ctypedef int bpf_int32

    ctypedef u_int bpf_u_int32

    struct bpf_insn:
        int __xxx

    struct bpf_program:
        bpf_insn *bf_insns

    struct bpf_timeval:
        u_int tv_sec
        u_int tv_usec

    struct pcap_stat:
        u_int ps_recv
        u_int ps_drop
        u_int ps_ifdrop

        # Win32
        u_int ps_capt
        u_int ps_sent
        u_int ps_netdrop

    struct pcap_pkthdr:
        bpf_timeval ts
        bpf_u_int32 caplen
        bpf_u_int32 len

    struct pcap_addr:
        pcap_addr *next
        sockaddr *addr
        sockaddr *netmask
        sockaddr *broadaddr
        sockaddr *dstaddr

    ctypedef struct pcap_t:
        pass

    ctypedef struct pcap_dumper_t:
        pass

    ctypedef struct pcap_if_t:
        pcap_if_t* next
        char* name
        char* description
        pcap_addr* addresses
        u_int flags

    ctypedef struct pcap_addr_t:
        pass


ctypedef void (*pcap_handler)(u_char *, const pcap_pkthdr *, const u_char *)


cdef extern from "pcap.h":

    pcap_t *pcap_open_live(const char *device, int snaplen, int promisc,
                           int to_ms, char *ebuf)

    pcap_t *pcap_open_dead(int linktype, int snaplen)

    pcap_t *pcap_open_offline(const char *fname, char *errbuf)

    pcap_dumper_t *pcap_dump_open(pcap_t *p, const char *fname)

    pcap_dumper_t *pcap_dump_open_append(pcap_t *p, const char *fname)

    int pcap_setnonblock(pcap_t *p, int nonblock, char *errbuf)

    int pcap_getnonblock(pcap_t *p, char* errbuf)

    int pcap_findalldevs(pcap_if_t **alldevsp, char *errbuf)

    void pcap_freealldevs(pcap_if_t *alldevs)

    char *pcap_lookupdev(char *errbuf)

    int pcap_lookupnet(const char *device, bpf_u_int32 *netp, bpf_u_int32 *maskp, char *errbuf)

    int pcap_dispatch(pcap_t *p, int cnt, pcap_handler callback, u_char *user)

    int pcap_loop(pcap_t *p, int cnt, pcap_handler callback, u_char *user)

    u_char *pcap_next(pcap_t *p, pcap_pkthdr *hdr)

    int pcap_next_ex(pcap_t *p, pcap_pkthdr **pkt_header, const u_char **pkt_data)

    void pcap_breakloop(pcap_t *)

    int pcap_sendpacket(pcap_t *p, const u_char *buf, int size)

    int pcap_inject(pcap_t *p, const void *buf, size_t size)

    void pcap_dump(u_char *user, const pcap_pkthdr *h, const u_char *sp)

    long pcap_dump_ftell(pcap_dumper_t *)

    int pcap_compile(pcap_t *p, bpf_program *fp, char *str, int optimize,
                     bpf_u_int32 netmask)

    int pcap_compile_nopcap(int snaplen_arg, int linktype_arg, bpf_program *program,
                            char *buf, int optimize, bpf_u_int32 mask)

    int pcap_setfilter(pcap_t *p, bpf_program *fp)

    void pcap_freecode(bpf_program *fp)

    int pcap_datalink(pcap_t *p)

    int pcap_list_datalink(pcap_t *p, int **dlt_buf)

    int pcap_set_datalink(pcap_t *p, int dlt)

    int pcap_datalink_name_to_val(const char *name)

    const char *pcap_datalink_val_to_name(int dlt)

    const char *pcap_datalink_val_to_description(int dlt)

    int pcap_snapshot(pcap_t *p)

    int pcap_is_swapped(pcap_t *p)

    int pcap_major_version(pcap_t *p)

    int pcap_minor_version(pcap_t *p)

    FILE *pcap_file(pcap_t *p)

    int pcap_stats(pcap_t *p, pcap_stat *ps)

    void pcap_perror(pcap_t *p, char *prefix)

    char *pcap_geterr(pcap_t *p)

    char *pcap_strerror(int error)

    const char *pcap_lib_version()

    void pcap_close(pcap_t *p)

    FILE *pcap_dump_file(pcap_dumper_t *p)

    int pcap_dump_flush(pcap_dumper_t *p)

    void pcap_dump_close(pcap_dumper_t *p)

    # SOCKET pcap_remoteact_accept(const char *address, const char *port, const char *hostlist,
    #                              char *connectinghost, pcap_rmtauth *auth, char *errbuf)

    int pcap_remoteact_close(const char *host, char *errbuf)

    void pcap_remoteact_cleanup()

    int pcap_remoteact_list(char *hostlist, char sep, int size, char *errbuf)

    pcap_t *pcap_create(char *source, char *errbuf)

    int pcap_set_snaplen(pcap_t *p, int snaplen)

    int pcap_set_promisc(pcap_t *p, int promisc)

    int pcap_set_timeout(pcap_t *p, int to_ms)

    int pcap_set_immediate_mode(pcap_t *p, int immediate_mode)

    int pcap_can_set_rfmon(pcap_t *)

    int pcap_set_rfmon(pcap_t *p, int rfmon)

    int pcap_activate(pcap_t *p)

    int bpf_filter(bpf_insn *insns, const u_char *buf, u_int len, u_int caplen)

    pcap_t *pcap_open_dead_with_tstamp_precision(int linktype, int snaplen, u_int precision)

# -*- coding: utf-8 -*-
# @Author: JanKinCai
# @Date:   2019-09-04 23:19:03
# @Last Modified by:   JanKinCai
# @Last Modified time: 2019-11-20 10:04:12
import os


def to_c_str(v):
    """
    Python str to C str
    """

    try:
        return v.encode("utf-8")
    except Exception:
        pass

    return b""


def from_c_str(v):
    """
    C str to Python str
    """

    try:
        return v.decode("utf-8")
    except Exception:
        pass

    return ""


def get_pcap_file(path):
    """
    get pcap file

    :param path: path.
    """

    if isinstance(path, bytes):
        path = from_c_str(path)

    if os.path.isfile(path):
        return (path, )

    return (
        os.path.join(directory, file)
        for directory, dirs, files in os.walk(path)
        for file in files if ".pcap" in file
    )

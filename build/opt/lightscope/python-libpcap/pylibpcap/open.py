# -*- coding: utf-8 -*-
# @Author: JanKinCai
# @Date:   2019-09-11 17:43:19
# @Last Modified by:   jankincai12@gmail.com
# @Last Modified time: 2019-09-12 09:27:39
from pylibpcap.base import LibPcap


class OpenPcap(object):
    """
    OpenPcap
    """

    def __init__(self, path, mode="r", *args, **kwargs):
        """
        init

        :param path: file path.
        :param mode: file model, default ``r``
        """

        self._pcapobj = LibPcap(path, mode, *args, **kwargs)

    def read(self):
        """
        Read
        """

        return self._pcapobj.read()

    def write(self, v):
        """
        Write

        :param v: Payload
        """

        return self._pcapobj.write(v)

    def write_path(self, path):
        """
        write path
        """

        return self._pcapobj.write_path(path)

    def __enter__(self):
        """
        enter
        """

        return self

    def __exit__(self, exception_type, exception_value, traceback):
        """
        exit
        """

        self._pcapobj.close()

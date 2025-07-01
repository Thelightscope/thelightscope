# -*- coding: utf-8 -*-
# @Author: jankincai
# @Date:   2021-01-26 23:18:43
# @Last Modified by:   jankincai
# @Last Modified time: 2021-01-26 23:27:01


class LibpcapError(Exception):
    """Exception raised for errors in the libpcap.
    """

    def __init__(self, message):
        """init
        """

        self.message = message

    def __str__(self):
        """"""

        return self.message

==========
Change Log
==========

All notable changes to the "python-libpcap" will be documented in this file.

Check `Keep a Changelog`_ for recommendations on how to structure this file.

Unreleased_ - 2021-01-28
------------------------


0.4.0_ - 2021-01-28
-------------------

Added
*****

* Support for the ``stats`` function in libpcap (#9)
* Support for the ``timeout`` function in libpcap (#8)

Fixed
*****

* Fix the memory overflow bug of ``get_iface_list``

Changed
*******

* Update error type of ``LibpcapError``
* Update show of capture 

0.3.0_ - 2020-12-12
-------------------

Added
*****

* Add packet simple parse
* Replace command line commands
  * libpcap-merge
  * libpcap-capture
* Add commands
  * libpcap-write
  * libpcap-read

0.2.5_ - 2020-10-12
-------------------

Fixed
*****

* Fix Sniff class don't create the pcap file (#7)

0.2.4_ - 2020-07-16
-------------------

Fixed
*****

* Fix send_packet function not free memory bug(#6).

0.2.2_ - 2020-04-04
-------------------

Fixed
*****

* Large delay with sniff() function after updating to Ubuntu 19.10 (#2)

.. _Unreleased: https://github.com/caizhengxin/python-libpcap/compare/v0.4.0...HEAD
.. _0.4.0: https://github.com/caizhengxin/python-libpcap/compare/v0.3.0...v0.4.0
.. _0.3.0: https://github.com/caizhengxin/python-libpcap/compare/v0.2.5...v0.3.0
.. _0.2.5: https://github.com/caizhengxin/python-libpcap/compare/v0.2.4...v0.2.5
.. _0.2.4: https://github.com/caizhengxin/python-libpcap/compare/v0.2.3...v0.2.4
.. _0.2.3: https://github.com/caizhengxin/python-libpcap/compare/v0.2.2...v0.2.3
.. _0.2.2: https://github.com/caizhengxin/python-libpcap/compare/v0.2.1...v0.2.2
.. _0.2.1: https://github.com/caizhengxin/python-libpcap/compare/v0.2.0...v0.2.1
.. _0.2.0: https://github.com/caizhengxin/python-libpcap/compare/v0.1.4...v0.2.0
.. _0.1.4: https://github.com/caizhengxin/python-libpcap/compare/v0.1.3...v0.1.4
.. _0.1.3: https://github.com/caizhengxin/python-libpcap/compare/v0.1.2...v0.1.3
.. _0.1.2: https://github.com/caizhengxin/python-libpcap/releases/tag/v0.1.2

.. _`Keep a Changelog`: http://keepachangelog.com/
.. _CHANGELOG.rst: ./CHANGELOG.rst

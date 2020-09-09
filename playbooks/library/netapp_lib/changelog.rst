====================
netapp-lib Changelog
====================

Change Log
----------

version: 2020.7.16
~~~~~~~~~~~~~~~~~~~
released: Jul 16 2020
tags: minor bug-fix
 - Fix issue with ONTAP 9.1 returning a BEL (0x07) character with \r\n.
 - Improved exception reporting (naked raise).
 - Include Apache license file in distribution.

version: 2020.3.13
~~~~~~~~~~~~~~~~~~~
released: Jul 14 2020
tags: minor bug-fix
 - Include tarball in addition to wheel file.

version: 2020.3.12
~~~~~~~~~~~~~~~~~~~
released: Mar 12 2020
tags: minor bug-fix
 - Update license to explicit reference Apache

version: 2019.12.20
~~~~~~~~~~~~~~~~~~~
released: Fri Dec 20 2019
tags: minor bug-fix
 - Update tags to reflect Ansible primary usage

version: 2019.12.19
~~~~~~~~~~~~~~~~~~~
released: Thu Dec 19 2019
tags: bug-fix
 - Fix issue with ONTAP returning a BEL (0x07) character
 - Improved exception reporting (Unexpected error)
 - Removed references to OpenStack

version: 2017.10.30
~~~~~~~~~~~~~~~~~~~
released: Mon Oct 30 2017
tags: bug-fix
 - Remove dependency on oslo.log.
 - Add lxml as a setup requirement
 - Remove i18n markup
 - Remove proprietary license. This code was borrowed from NetApp's
   integrations in OpenStack Cinder and OpenStack Manila, which are
   both licensed under Apache V2 License.

version: 2016.10.14
~~~~~~~~~~~~~~~~~~~
released: Fri Oct 14 2016
tags: minor bug-fix
- Fixed bug in code parsing ZAPI errors.

version: 2015.09.25
~~~~~~~~~~~~~~~~~~~
released: Fri Sep 25 2015
tags: attributions
- Updated source files to include OpenStack attributions.
- Added NOTICE.txt to include previous License.
- Added description to setup.py

version: 2015.08.20
~~~~~~~~~~~~~~~~~~~
released: Thu Aug 20 2015
tags: release

- Updated README.rst.
- Updated initial LICENSE.txt.
- Updated setup to include static files on installation.

version: 0.2
~~~~~~~~~~~~
released: Fri Aug 07 2015
tags: pre-release
- Added xmltodict and translation capability to NaServer ZAPI interface

version: 0.1
~~~~~~~~~~~~
released: Mon Jul 21 2015
tags: initial
- Compiled the ZAPI and REST interface code used within manila and cinder
  clients on OpenStack.
- Structured the project for PyPi release.
- Added tox.ini to enforce pep8 style-guide and run unit tests.

# Copyright (C) 2013 Tobias Oetiker
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307, USA.

AUTOMAKE_OPTIONS = foreign

SUBDIRS = backend

EXTRA_DIST = INSTALL COPYRIGHT LICENSE CHANGES AUTHORS setup/build-thirdparty.sh setup/sdbs.inc

YEAR := $(shell date +%Y)
DATE := $(shell date +%Y-%m-%d)

INSTALL: backend/lib/SmokePing/INSTALL.pod
	pod2text -l backend/lib/SmokePing/INSTALL.pod > INSTALL

dist-hook:
	$(PERL) -i -p -e 's/#VERSION#/$(PACKAGE_VERSION)/g;s/#YEAR#/$(YEAR)/g;s/#DATE#/$(DATE)/g;'  $(distdir)/README $(distdir)/COPYRIGHT

#END

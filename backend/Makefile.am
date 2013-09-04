# Copyright (C) 2013 Tobias Oetiker

AUTOMAKE_OPTIONS =  foreign

MJ_CLASS = SmokePing

ETC = etc/smokeping.cfg.dist
BIN = bin/@PACKAGE@.pl bin/run.sh

PM :=  $(shell find lib/ -name "*.pm")

POD :=  $(shell find lib/ -name "*.pod")

TEMPL := $(shell test -d templates && find templates -type f)

EXTRA_DIST = $(wildcard t/*.t) $(ETC) $(BIN) $(PM) $(POD) $(TEMPL)

YEAR := $(shell date +%Y)
DATE := $(shell date +%Y-%m-%d)

datadir = $(prefix)
nobase_data_DATA = $(PM) $(POD) $(ETC) $(TEMPL)

dist_bin_SCRIPTS = $(BIN)

install-exec-hook:
	[ "$(PERL5LIB)" != "" ] && cd "$(DESTDIR)$(bindir)" && $(PERL) -i -p -e 's{.*# PERL5LIB}{use lib qw($(PERL5LIB)); # PERL5LIB}' *.pl || true
	cd "$(DESTDIR)$(bindir)" && $(PERL) -i -p -e 's{^#!.*perl.*}{#!$(PERL)};' *.pl

dist-hook:
	$(PERL) -i -p -e '"$(PACKAGE_VERSION)" =~ /(\d+)\.(\d+)\.(\d+)/ and $$v = sprintf("%d.%03d%03d",$$1,$$2,$$3) and s/^\$$VERSION\s+=\s+".+?"/\$$VERSION = "$$d"/;'  $(distdir)/lib/$(MJ_CLASS).pm

install-data-local:
	mkdir -p $(DESTDIR)$(HTDOCSDIR)
	echo "#!/bin/sh" > $(DESTDIR)$(HTDOCSDIR)/index.fcgi.dist
	echo "export SMOKEPING_CONF=$(prefix)/etc/@PACKAGE@.cfg" >> $(DESTDIR)$(HTDOCSDIR)/index.fcgi.dist
	echo "$(prefix)/bin/@PACKAGE@.pl fastcgi" >> $(DESTDIR)$(HTDOCSDIR)/index.fcgi.dist
	chmod +x $(DESTDIR)$(HTDOCSDIR)/index.fcgi.dist

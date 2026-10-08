# arc-dgpu-ctl - Makefile
# VERSION (top-level file) is the single source of truth for the version.
# Everything else (script, debian/changelog, tarball, release) is derived.
#
#   make install                                    # /usr/local, units in /etc
#   make -C external/arc-dgpu-ctl install DESTDIR=… # from a parent project
#   make deb                                        # Debian package in dist/

NAME           := arc-dgpu-ctl
VERSION        := $(shell cat VERSION)
DEB_VERSION    := $(subst -,~,$(VERSION))
PREFIX         ?= /usr/local
# bin, not sbin: `state`/`status`/`power` are for normal users too.
BINDIR         ?= $(PREFIX)/bin
MANDIR         ?= $(PREFIX)/share/man
SYSCONFDIR     ?= /etc
SYSTEMDUNITDIR ?= $(SYSCONFDIR)/systemd/system
UDEVRULESDIR   ?= $(SYSCONFDIR)/udev/rules.d
DESTDIR        ?=
# Set WITH_UDEV=0 if you use vfio-pci passthrough for an Arc card.
WITH_UDEV      ?= 1
MAINTAINER     ?= Dane64 <Dane64@users.noreply.github.com>

INSTALL ?= install
SHELL_SOURCES := src/$(NAME) install.sh uninstall.sh tests/run.sh \
                 debian/prerm debian/postinst debian/postrm

.PHONY: all build install uninstall check lint test dist deb clean clean-all

all: build

# Always regenerated: output depends on VERSION and BINDIR, not just sources.
build:
	@mkdir -p build
	sed 's/^VERSION="@VERSION@"$$/VERSION="$(VERSION)"/' src/$(NAME) > build/$(NAME)
	chmod 0755 build/$(NAME)
	sed 's#@BINDIR@#$(BINDIR)#g' data/arc-dgpu-ctl.service.in > build/arc-dgpu-ctl.service

install: build
	$(INSTALL) -Dm0755 build/$(NAME)              $(DESTDIR)$(BINDIR)/$(NAME)
	$(INSTALL) -Dm0644 build/arc-dgpu-ctl.service $(DESTDIR)$(SYSTEMDUNITDIR)/arc-dgpu-ctl.service
	$(INSTALL) -Dm0644 man/$(NAME).8              $(DESTDIR)$(MANDIR)/man8/$(NAME).8
	@# never overwrite an existing config
	@if [ ! -e $(DESTDIR)$(SYSCONFDIR)/$(NAME).conf ]; then \
	  $(INSTALL) -Dm0644 data/$(NAME).conf $(DESTDIR)$(SYSCONFDIR)/$(NAME).conf; fi
ifeq ($(WITH_UDEV),1)
	$(INSTALL) -Dm0644 data/99-$(NAME).rules $(DESTDIR)$(UDEVRULESDIR)/99-$(NAME).rules
endif

uninstall:
	-PERSIST=0 $(DESTDIR)$(BINDIR)/$(NAME) on
	rm -f $(DESTDIR)$(BINDIR)/$(NAME) $(DESTDIR)$(PREFIX)/sbin/$(NAME) \
	      $(DESTDIR)$(SYSTEMDUNITDIR)/arc-dgpu-ctl.service \
	      $(DESTDIR)$(SYSTEMDUNITDIR)/arc-dgpu-off.service \
	      $(DESTDIR)$(MANDIR)/man8/$(NAME).8 \
	      $(DESTDIR)$(UDEVRULESDIR)/99-$(NAME).rules

check: lint test

lint:
	bash -n src/$(NAME)
	shellcheck -x $(SHELL_SOURCES)

test: build
	tests/run.sh

# debian/changelog is generated from VERSION - it is not kept in git.
# Date: SOURCE_DATE_EPOCH > last commit > now (reproducible in CI).
debian/changelog: VERSION
	@d=$${SOURCE_DATE_EPOCH:-$$(git log -1 --format=%ct 2>/dev/null || date +%s)}; \
	 printf '%s (%s) unstable; urgency=medium\n\n  * Release %s. See CHANGELOG.md.\n\n -- %s  %s\n' \
	   $(NAME) $(DEB_VERSION) $(VERSION) "$(MAINTAINER)" "$$(date -R -u -d @$$d)" > $@

deb: debian/changelog
	dpkg-buildpackage -us -uc -b
	@mkdir -p dist && mv ../$(NAME)_$(DEB_VERSION)_*.deb dist/
	@rm -f ../$(NAME)_$(DEB_VERSION)_*.buildinfo ../$(NAME)_$(DEB_VERSION)_*.changes

dist:
	@mkdir -p dist
	git -c safe.directory='*' archive --format=tar.gz --prefix=$(NAME)-$(VERSION)/ \
	  -o dist/$(NAME)-$(VERSION).tar.gz HEAD

# NB: dh_auto_clean runs `make clean` inside dpkg-buildpackage, so this must
# not delete dist/ or debian/changelog. Use clean-all for that.
clean:
	rm -rf build

clean-all: clean
	rm -rf dist debian/changelog

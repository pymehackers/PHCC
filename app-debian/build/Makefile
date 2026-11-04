# Makefile for PYMEHackers Control Center (core) on Debian.
#
# Builds the "phcc" binary (../frontend/indicator.c + ../frontend/i18n.c), which places an icon in
# the top bar of MATE (and of any desktop with AppIndicator support; on GNOME Shell the native
# extension in ../frontend/gnome-extension provides the icon instead).
#
# Requires: gtk+-3.0 and ayatana-appindicator3-0.1 (their -dev packages).
#   apt-get install libgtk-3-dev libayatana-appindicator3-dev
#
# Like every Makefile in this project, recipes avoid tabs by redefining .RECIPEPREFIX.
.RECIPEPREFIX := >

DESTDIR ?=
PREFIX  ?= /usr

CC       := gcc
BUILDDIR := out

# Source folders of the Debian app (this Makefile lives in app-debian/build/).
FRONTEND := ../frontend
BACKEND  := ../backend

PKG_CFLAGS := $(shell pkg-config --cflags gtk+-3.0 ayatana-appindicator3-0.1)
PKG_LIBS   := $(shell pkg-config --libs gtk+-3.0 ayatana-appindicator3-0.1)

CFLAGS := -std=c11 -O2 -Wall -Wextra -D_GNU_SOURCE $(PKG_CFLAGS)
LDLIBS := $(PKG_LIBS)

INDICATOR := $(BUILDDIR)/phcc
SOURCES   := $(FRONTEND)/indicator.c $(FRONTEND)/i18n.c
HEADERS   := $(FRONTEND)/i18n.h

# UUID and destination of the native GNOME Shell extension (installed next to the AppIndicator).
EXTUUID := phcc@pymehackers.com
EXTDIR  := $(DESTDIR)$(PREFIX)/share/gnome-shell/extensions/$(EXTUUID)

# Root of the hicolor icon theme where the PYMEHackers Control Center icons are installed.
ICONDIR := $(DESTDIR)$(PREFIX)/share/icons/hicolor

# Language files shared by the indicator, the GNOME extension and the backend scripts.
LANGDIR := $(DESTDIR)$(PREFIX)/share/pymehackers/core/lang
LANGS   := en-GB en-US es-AR es-ES

.PHONY: all clean install

all: $(INDICATOR)

$(INDICATOR): $(SOURCES) $(HEADERS)
> @mkdir -p $(BUILDDIR)
> $(CC) $(CFLAGS) $(SOURCES) -o $@ $(LDLIBS)

install: all
> install -D -m 0755 $(INDICATOR) $(DESTDIR)$(PREFIX)/bin/phcc
> install -D -m 0755 $(BACKEND)/phcc-show $(DESTDIR)$(PREFIX)/bin/phcc-show
> install -D -m 0755 $(BACKEND)/phcc-modules $(DESTDIR)$(PREFIX)/libexec/phcc/phcc-modules
> install -D -m 0644 $(BACKEND)/polkit/com.pymehackers.phcc.modules.policy $(DESTDIR)$(PREFIX)/share/polkit-1/actions/com.pymehackers.phcc.modules.policy
> install -D -m 0644 $(FRONTEND)/desktop/phcc.desktop $(DESTDIR)/etc/xdg/autostart/phcc.desktop
> install -D -m 0644 $(FRONTEND)/desktop/phcc-gnome-activate.desktop $(DESTDIR)/etc/xdg/autostart/phcc-gnome-activate.desktop
> install -D -m 0644 $(FRONTEND)/desktop/pymehackers-control-center.desktop $(DESTDIR)$(PREFIX)/share/applications/pymehackers-control-center.desktop
> install -D -m 0644 $(FRONTEND)/gnome-extension/metadata.json  $(EXTDIR)/metadata.json
> install -D -m 0644 $(FRONTEND)/gnome-extension/extension.js   $(EXTDIR)/extension.js
> install -D -m 0644 $(FRONTEND)/gnome-extension/stylesheet.css $(EXTDIR)/stylesheet.css
> for lang in $(LANGS); do install -D -m 0644 $(FRONTEND)/lang/$$lang.json $(LANGDIR)/$$lang.json; done
> install -D -m 0644 $(FRONTEND)/icons/phcc.svg $(ICONDIR)/scalable/apps/phcc.svg
> install -D -m 0644 $(FRONTEND)/icons/phcc-symbolic.svg $(ICONDIR)/symbolic/apps/phcc-symbolic.svg
> for sz in 16 22 24 32 48 64 128 256 512; do install -D -m 0644 $(FRONTEND)/icons/phcc-$$sz.png $(ICONDIR)/$${sz}x$${sz}/apps/phcc.png; done
> install -d -m 0755 $(DESTDIR)$(PREFIX)/share/pymehackers/modules/sys $(DESTDIR)$(PREFIX)/share/pymehackers/modules/cs

clean:
> rm -rf $(BUILDDIR)

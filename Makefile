CFLAGS := -I $(SRC) $(CFLAGS) -m64 -std=gnu99 -O2 -g -pthread -D_GNU_SOURCE -D_REENTRANT -Wall -Werror
LDFLAGS := $(LDFLAGS) -lm
NVME = nvme
INSTALL ?= install
SRC = ./src
DESTDIR =
PREFIX := /usr/local
SBINDIR = $(PREFIX)/sbin
LIBUDEV:=$(shell ld -ludev > /dev/null 2>&1 ; echo $$?)
LIB_DEPENDS =

RPMBUILD = rpmbuild
TAR = tar
RM = rm -f

ifeq ($(LIBUDEV),0)
	LDFLAGS += -ludev
	CFLAGS  += -DLIBUDEV_EXISTS
	LIB_DEPENDS += udev
endif

# For the uapi header file we priorize this way:
# 1. Use /usr/src/$(uname -r)/include/uapi/linux/nvme.h
# 2. Use ./linux/nvme.h

ifneq (,$(wildcard /usr/src/linux-headers-$(shell uname -r)/include/uapi/linux/nvme.h))
	NVME_HEADER = /usr/src/linux-headers-$(shell uname -r)/include/uapi/linux/nvme.h
else
	NVME_HEADER = ./linux/nvme.h
endif

default: $(NVME)

NVME-VERSION-FILE: FORCE
	@$(SHELL_PATH) ./NVME-VERSION-GEN
-include NVME-VERSION-FILE
override CFLAGS += -DNVME_VERSION='"$(NVME_VERSION)"'

nvme: nvme.c $(NVME_HEADER) argconfig.o suffix.o NVME-VERSION-FILE
	$(CC) $(CFLAGS) nvme.c $(LDFLAGS) -o $(NVME) argconfig.o suffix.o

argconfig.o: $(SRC)/argconfig.c $(SRC)/argconfig.h $(SRC)/suffix.h
	$(CC) -c $(CFLAGS) $(SRC)/argconfig.c

suffix.o: $(SRC)/suffix.c $(SRC)/suffix.h
	$(CC) -c $(CFLAGS) $(SRC)/suffix.c

doc: $(NVME)
	$(MAKE) -C Documentation

all: doc

clean:
	$(RM) $(NVME) *.o *~ a.out NVME-VERSION-FILE *.tar* nvme.spec version control nvme-*.deb
	$(RM) -r nvme-*
	$(MAKE) -C Documentation clean

clobber: clean
	$(MAKE) -C Documentation clobber

install-man:
	$(MAKE) -C Documentation install-no-build

install-bin: default
	$(INSTALL) -d $(DESTDIR)$(SBINDIR)
	$(INSTALL) -m 755 nvme $(DESTDIR)$(SBINDIR)

install: install-bin install-man

nvme.spec: nvme.spec.in NVME-VERSION-FILE
	sed -e 's/@@VERSION@@/$(NVME_VERSION)/g' < $< > $@+
	mv $@+ $@

dist: nvme.spec
	git archive --format=tar --prefix=nvme-$(NVME_VERSION)/ HEAD > nvme-$(NVME_VERSION).tar
	@echo $(NVME_VERSION) > version
	$(TAR) rf  nvme-$(NVME_VERSION).tar nvme.spec version
	gzip -f -9 nvme-$(NVME_VERSION).tar

control: nvme.control.in NVME-VERSION-FILE
	sed -e 's/@@VERSION@@/$(NVME_VERSION)/g' < $< > $@+
	mv $@+ $@
	sed -e 's/@@DEPENDS@@/$(LIB_DEPENDS)/g' < $@ > $@+
	mv $@+ $@

pkg: control nvme.control.in
	mkdir -p nvme-$(NVME_VERSION)$(SBINDIR)
	mkdir -p nvme-$(NVME_VERSION)$(PREFIX)/share/man/man1
	mkdir -p nvme-$(NVME_VERSION)/DEBIAN/
	cp Documentation/*.1 nvme-$(NVME_VERSION)$(PREFIX)/share/man/man1
	cp nvme nvme-$(NVME_VERSION)$(SBINDIR)
	cp control nvme-$(NVME_VERSION)/DEBIAN/

deb: $(NVME) pkg nvme.control.in
	dpkg-deb --build nvme-$(NVME_VERSION)

rpm: dist
	$(RPMBUILD) -ta nvme-$(NVME_VERSION).tar.gz

.PHONY: default all doc clean clobber install install-bin install-man rpm deb FORCE

# SPDX-License-Identifier: MIT
#
# Copyright (C) 2018-2019 Jason A. Donenfeld <Jason@zx2c4.com>. All Rights Reserved.

# These are generally passed to us by xcode, but we set working defaults for standalone compilation too.
ARCHS ?= x86_64 arm64
PLATFORM_NAME ?= macosx
SDKROOT ?= $(shell xcrun --sdk $(PLATFORM_NAME) --show-sdk-path)
CONFIGURATION_BUILD_DIR ?= $(CURDIR)/out
CONFIGURATION_TEMP_DIR ?= $(CURDIR)/.tmp

# make cannot handle spaces in target names, and Xcode's archive paths contain the scheme's name, which may have
# spaces: build through links to both directories from a path without them.
ifneq ($(words $(CONFIGURATION_BUILD_DIR) $(CONFIGURATION_TEMP_DIR)),2)
SPACELESS_DIR := $(shell mkdir -p "$(CONFIGURATION_BUILD_DIR)" "$(CONFIGURATION_TEMP_DIR)" && \
	dir=$$(mktemp -d "$${TMPDIR:-/tmp}/wireguard-go-bridge.XXXXXX") && \
	ln -s "$(CONFIGURATION_BUILD_DIR)" "$$dir/build" && ln -s "$(CONFIGURATION_TEMP_DIR)" "$$dir/temp" && echo "$$dir")
override CONFIGURATION_BUILD_DIR := $(SPACELESS_DIR)/build
override CONFIGURATION_TEMP_DIR := $(SPACELESS_DIR)/temp
endif

export PATH := $(PATH):/usr/local/bin:/opt/homebrew/bin
export CC ?= clang
# amneziawg-go v3 needs Go >= 1.26; pin the toolchain (Go downloads it on first use) so the
# machine's default Go is left alone.
export GOTOOLCHAIN ?= go1.27.1
LIPO ?= lipo
DESTDIR ?= $(CONFIGURATION_BUILD_DIR)
BUILDDIR ?= $(CONFIGURATION_TEMP_DIR)/wireguard-go-bridge

CFLAGS_PREFIX := $(if $(DEPLOYMENT_TARGET_CLANG_FLAG_NAME),-$(DEPLOYMENT_TARGET_CLANG_FLAG_NAME)=$($(DEPLOYMENT_TARGET_CLANG_ENV_NAME)),) -isysroot $(SDKROOT) -arch
GOARCH_arm64 := arm64
GOARCH_x86_64 := amd64
GOOS_macosx := darwin
GOOS_iphoneos := ios
GOOS_iphonesimulator := ios
# Go has no tvOS target; the iOS runtime built against the tvOS SDK is what Apple's toolchain expects.
GOOS_appletvos := ios
GOOS_appletvsimulator := ios

build: $(DESTDIR)/libwg-go.a
version-header: $(DESTDIR)/wireguard-go-version.h

# $(shell) does not see Makefile exports on macOS make, so pass the toolchain explicitly.
REAL_GOROOT := $(shell GOTOOLCHAIN=$(GOTOOLCHAIN) go env GOROOT 2>/dev/null)
export GOROOT := $(BUILDDIR)/goroot
$(GOROOT)/.prepared:
	[ -n "$(REAL_GOROOT)" ]
	mkdir -p "$(GOROOT)"
	# The downloaded toolchain lives in the read-only module cache: an earlier copy must be made
	# writable before rsync --delete can touch it, and the fresh copy before patch can edit it.
	chmod -R u+w "$(GOROOT)"
	rsync -a --delete --exclude=pkg/obj/go-build "$(REAL_GOROOT)/" "$(GOROOT)/"
	chmod -R u+w "$(GOROOT)"
	cat goruntime-*.diff | patch -p1 -f -N -r- -d "$(GOROOT)"
	touch "$@"

define libwg-go-a
$(BUILDDIR)/libwg-go-$(1).a: export CGO_ENABLED := 1
$(BUILDDIR)/libwg-go-$(1).a: export CGO_CFLAGS := $(CFLAGS_PREFIX) $(ARCH)
$(BUILDDIR)/libwg-go-$(1).a: export CGO_LDFLAGS := $(CFLAGS_PREFIX) $(ARCH)
$(BUILDDIR)/libwg-go-$(1).a: export GOOS := $(GOOS_$(PLATFORM_NAME))
$(BUILDDIR)/libwg-go-$(1).a: export GOARCH := $(GOARCH_$(1))
$(BUILDDIR)/libwg-go-$(1).a: $(GOROOT)/.prepared go.mod
	go build -ldflags=-w -trimpath -v -o "$(BUILDDIR)/libwg-go-$(1).a" -buildmode c-archive
	rm -f "$(BUILDDIR)/libwg-go-$(1).h"
endef
$(foreach ARCH,$(ARCHS),$(eval $(call libwg-go-a,$(ARCH))))

$(DESTDIR)/wireguard-go-version.h: go.mod $(GOROOT)/.prepared
	 sed -E -n 's/.*golang\.zx2c4\.com\/wireguard +v[0-9.]+-[0-9]+-([0-9a-f]{8})[0-9a-f]{4}.*/#define WIREGUARD_GO_VERSION "\1"/p' "$<" > "$@"

$(DESTDIR)/libwg-go.a: $(foreach ARCH,$(ARCHS),$(BUILDDIR)/libwg-go-$(ARCH).a)
	@mkdir -vp "$(DESTDIR)"
	$(LIPO) -create -output "$@" $^

clean:
	rm -rf "$(BUILDDIR)" "$(DESTDIR)/libwg-go.a" "$(DESTDIR)/wireguard-go-version.h"

install: build

.PHONY: clean build version-header install

# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Ninon
SWIFTC ?= swiftc
ARCH := $(shell uname -m)
BUILD_DIR ?= build
MODULE_CACHE ?= $(BUILD_DIR)/module-cache
SWIFT_FLAGS = -swift-version 6 -O -target $(ARCH)-apple-macosx14.0 -module-cache-path $(MODULE_CACHE)

.PHONY: all test
all: $(BUILD_DIR)/webshot

$(BUILD_DIR)/webshot: Sources/main.swift
	mkdir -p $(BUILD_DIR) $(MODULE_CACHE)
	$(SWIFTC) $(SWIFT_FLAGS) $< -o $@

$(BUILD_DIR)/pixelcheck: tests/pixelcheck.swift
	mkdir -p $(BUILD_DIR) $(MODULE_CACHE)
	$(SWIFTC) $(SWIFT_FLAGS) $< -o $@

test: all $(BUILD_DIR)/pixelcheck
	WEBSHOT_BIN="$(abspath $(BUILD_DIR)/webshot)" PIXELCHECK_BIN="$(abspath $(BUILD_DIR)/pixelcheck)" /bin/sh tests/run.sh

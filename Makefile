PREFIX ?= $(HOME)/.local
INSTALL_PATH := $(PREFIX)/bin/abs

.PHONY: help install uninstall vendored-source test analyze format check examples

## help: list the available commands
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## /  /'

## install: compile abs to a native binary at $(PREFIX)/bin/abs
install: vendored-source
	mkdir -p $(PREFIX)/bin
	dart compile exe bin/abs.dart -o $(INSTALL_PATH)

## uninstall: remove the installed binary
uninstall:
	rm -f $(INSTALL_PATH)

## vendored-source: regenerate lib/src/vendored_source.dart
# abs vendor embeds lib/src, so rebuild it before compiling or the binary ships a stale copy
vendored-source:
	dart run tool/build_vendored_source.dart

## test: run the tests
test:
	dart test

## analyze: run the analyzer, failing on infos too
analyze:
	dart analyze --fatal-infos

## format: format the package sources
format:
	dart format bin lib test tool

## check: what CI should run; fails on unformatted code, lints or tests
check:
	dart format --output=none --set-exit-if-changed bin lib test tool
	dart analyze --fatal-infos
	dart test

## examples: regenerate examples/generated/html.dart
examples:
	cd examples && dart run ../bin/abs.dart

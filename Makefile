SHELL := /bin/bash
.DEFAULT_GOAL := help

SCRIPTS := $(wildcard scripts/*.sh scripts/lib/*.sh)

.PHONY: help build test app install uninstall release clean lint

help:
	@printf 'Watty\n\n'
	@printf '  make build      compile the release products with SwiftPM\n'
	@printf '  make test       run the unit tests (XCTest needs a full Xcode)\n'
	@printf '  make app        assemble build/Watty.app, ad-hoc signed\n'
	@printf '  make install    build from source and install the app (see scripts/install.sh --help)\n'
	@printf '  make uninstall  remove the app, its LaunchAgent and logs (UNINSTALL_ARGS=--purge also removes settings and history)\n'
	@printf '  make release    zip the app into dist/ (RELEASE_ARGS="--tap ../homebrew-tap")\n'
	@printf '  make clean      remove .build, build and dist\n'
	@printf '  make lint       shellcheck every script and check its syntax\n\n'
	@printf 'Variables for make install: INSTALL_DIR, BIN_DIR, LAUNCH_AGENT=1, RUN_TESTS=1, OPEN_APP=0\n'

build:
	swift build -c release

test:
	swift test

app:
	scripts/build-app.sh

install:
	scripts/install.sh

uninstall:
	scripts/uninstall.sh $(UNINSTALL_ARGS)

release:
	scripts/release.sh $(RELEASE_ARGS)

clean:
	rm -rf .build build dist

lint:
	@command -v shellcheck >/dev/null || { echo "shellcheck is required: brew install shellcheck" >&2; exit 1; }
	@for script in $(SCRIPTS); do bash -n "$$script" || exit 1; done
	shellcheck $(SCRIPTS)
